#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Incremental isolated ordinary-release comparison. Protected snapshots stay read-only."""
import argparse,hashlib,json,pathlib,platform,subprocess,time,shutil,datetime,os
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--predecessor-source',required=True,type=pathlib.Path);p.add_argument('--scalar-ref',default='a72aa30f84129c2add8b84008675061203f8bbc0');p.add_argument('--quick',action='store_true');p.add_argument('--memory',action='store_true');p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();os.environ['CLANG_MODULE_CACHE_PATH']=str(out/'module-cache');os.environ['SWIFTPM_MODULECACHE_OVERRIDE']=str(out/'module-cache');h=out/'Harness';h.mkdir(parents=True,exist_ok=True)
assert shutil.disk_usage(out).free>1024**3,'Insufficient disk headroom'
assert hashlib.sha256(a.predecessor_source.read_bytes()).hexdigest()=='59f7b00112760ce7b2342546185935dc457f17d6dcc1b4519b43374da18bca43'
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ');run=out/('qualified-'+stamp);run.mkdir();(run/'executed-driver.py').write_bytes(pathlib.Path(__file__).read_bytes())
wrapper='''// SPDX-License-Identifier: Apache-2.0
// Qualification-only read access to existing internal allocator hooks; no production modification.
public enum BenchmarkTelemetry {
 public static func measureAsync(_ body: @Sendable () async throws -> Void) async rethrows -> [String:Int] {
 let recorder=StorageTelemetry.Recorder()
 try await StorageTelemetry.$recorder.withValue(recorder) {try await body()}
 let c=recorder.counts
 return ["pixelAllocations":c.pixelAllocations,"pixelBytes":c.pixelBytes,"pixelReleases":c.pixelReleases,"pixelReleasedBytes":c.pixelReleasedBytes,"workspaceAllocations":c.workspaceAllocations,"workspaceBytes":c.workspaceBytes,"observedPeakPixelBytes":c.observedPeakPixelBytes,"copyEvents":c.copyEvents,"copyBytes":c.copyBytes]
 }
 public static func measure(_ body: () throws -> Void) rethrows -> [String:Int] {
 let recorder=StorageTelemetry.Recorder()
 try StorageTelemetry.$recorder.withValue(recorder) {try body()}
 let c=recorder.counts
 return ["pixelAllocations":c.pixelAllocations,"pixelBytes":c.pixelBytes,"pixelReleases":c.pixelReleases,"pixelReleasedBytes":c.pixelReleasedBytes,"workspaceAllocations":c.workspaceAllocations,"workspaceBytes":c.workspaceBytes,"observedPeakPixelBytes":c.observedPeakPixelBytes,"copyEvents":c.copyEvents,"copyBytes":c.copyBytes]
 }
}
'''
for name in ['BaselineRLE','CandidateRLE','Predecessor','Bench','BenchSystem/include','Experiments']:(h/'Sources'/name).mkdir(parents=True,exist_ok=True)
source_hashes={}
for f in (root/'Sources/SwiftRLE').glob('*.swift'):
 scalar=subprocess.check_output(['git','show',a.scalar_ref+':Sources/SwiftRLE/'+f.name],cwd=root)
 (h/'Sources/BaselineRLE'/f.name).write_bytes(scalar);(h/'Sources/CandidateRLE'/f.name).write_bytes(f.read_bytes());source_hashes[str(f.relative_to(root))]=hashlib.sha256(f.read_bytes()).hexdigest()
# Qualification-only high-water bookkeeping inside the existing real allocator hooks.
# Unbound timing calls retain the original recorder==nil fast path.
for name in ['BaselineRLE','CandidateRLE']:
 (h/'Sources'/name/'BenchmarkTelemetry.swift').write_text(wrapper)
 telemetry=h/'Sources'/name/'Telemetry.swift';original=telemetry.read_text()
 modified=original.replace('var pixelAllocations = 0','var observedPeakPixelBytes = 0\n        var pixelAllocations = 0').replace('state.withLock { body(&$0) }','state.withLock { body(&$0); $0.observedPeakPixelBytes = max($0.observedPeakPixelBytes, $0.pixelBytes - $0.pixelReleasedBytes) }')
 assert original!=modified
 telemetry.write_text(modified)
 (run/(name+'-telemetry-instrumentation.patch')).write_text(''.join(__import__('difflib').unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='original/Telemetry.swift',tofile='qualification/Telemetry.swift')))
(h/'Sources/Predecessor/RLECodec.swift').write_bytes(a.predecessor_source.read_bytes());(h/'Sources/Predecessor/Context.swift').write_bytes((root/'Qualification/Benchmark/PredecessorContext.swift').read_bytes());(h/'Sources/Bench/main.swift').write_bytes((root/'Qualification/Benchmark/main.swift').read_bytes())
(h/'Sources/BenchSystem/include/BenchSystem.h').write_text('''#include <stdint.h>
typedef struct { uint64_t peak_rss_bytes, malloc_live_bytes, malloc_live_blocks, malloc_max_bytes; } BenchMemory;
BenchMemory bench_memory(void);
''')
(h/'Sources/BenchSystem/memory.c').write_text('''#include "BenchSystem.h"
#include <sys/resource.h>
#ifdef __APPLE__
#include <malloc/malloc.h>
#endif
BenchMemory bench_memory(void) {
 struct rusage u;getrusage(RUSAGE_SELF,&u);BenchMemory r={0};
#ifdef __APPLE__
 r.peak_rss_bytes=u.ru_maxrss;malloc_statistics_t s;malloc_zone_statistics(NULL,&s);r.malloc_live_bytes=s.size_in_use;r.malloc_live_blocks=s.blocks_in_use;r.malloc_max_bytes=s.max_size_in_use;
#else
 r.peak_rss_bytes=u.ru_maxrss*1024;
#endif
 return r;
}
''')
(h/'Sources/Experiments/main.swift').write_bytes((root/'Qualification/Benchmark/experiments.swift').read_bytes())
(h/'Package.swift').write_text('// swift-tools-version: 6.2\nimport PackageDescription\nlet package=Package(name:"R4Qualification",platforms:[.macOS(.v26)],targets:[.target(name:"BaselineRLE"),.target(name:"CandidateRLE"),.target(name:"Predecessor"),.target(name:"BenchSystem"),.executableTarget(name:"Experiments",dependencies:["CandidateRLE","BenchSystem"]),.executableTarget(name:"Bench",dependencies:["Predecessor","BaselineRLE","CandidateRLE","BenchSystem"])])\n')
command=['swift','build','--disable-sandbox','--build-system','swiftbuild','-j','2','--package-path',str(h),'--scratch-path',str(out/'build'),'-c','release','--product','Bench']
start=time.monotonic()
with (run/'build.log').open('w') as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
receipt={'command':command,'buildExit':r.returncode,'scalarRef':a.scalar_ref,'predecessorSHA256':hashlib.sha256(a.predecessor_source.read_bytes()).hexdigest(),'host':platform.platform(),'compiler':subprocess.check_output(['swift','--version'],text=True),'sources':source_hashes,'timingSanitizersCoverageTracing':False,'accounting':'existing real pixel allocator hooks in source copies plus qualification-only wrapper/high-water bookkeeping patch archived per module; system malloc zone snapshot reported distinctly'}
if r.returncode==0:
 binary=out/'build/out/Products/Release/Bench';assert binary.exists()
 shutil.copy2(binary,run/'Bench');binary=run/'Bench'
 receipt['binary']=str(binary);receipt['binarySHA256']=hashlib.sha256(binary.read_bytes()).hexdigest()
 shutil.copytree(h/'Sources',run/'built-sources');shutil.copy2(h/'Package.swift',run/'Package.swift')
 for label,cmd in [('hardware',['sysctl','-n','machdep.cpu.brand_string']),('memory',['sysctl','-n','hw.memsize']),('power',['pmset','-g','batt']),('thermal',['pmset','-g','therm']),('os',['sw_vers']),('sdk',['xcrun','--show-sdk-version'])]:
  e=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);receipt[label]={'command':cmd,'exit':e.returncode,'output':e.stdout}
 flags=['--quick'] if a.quick else []
 manifest=subprocess.check_output([str(binary),'--list']+flags,text=True);(run/'cases.jsonl').write_text(manifest)
 if not a.prepare_only:
  cmd=[str(binary)]+flags
  with (run/'raw.jsonl').open('w') as log,(run/'run.log').open('w') as err:e=subprocess.run(cmd,stdout=log,stderr=err)
  receipt['timingCommand']=cmd;receipt['timingExit']=e.returncode
  timing_rows=[json.loads(line) for line in (run/'raw.jsonl').read_text().splitlines()]
  timing_expected={(row['id'],op) for row in map(json.loads,manifest.splitlines()) for op in ['encode','decode']}
  timing_actual={(row['id'],row['operation']) for row in timing_rows}
  receipt['timingExpectedRows']=len(timing_expected);receipt['timingActualRows']=len(timing_rows)
  if len(timing_rows)!=len(timing_expected) or timing_actual!=timing_expected or any(len(row['baseline'])!=20 or len(row['candidate'])!=20 or row['warmups']!=5 for row in timing_rows):receipt['timingExit']=1
  if a.memory and receipt['timingExit']==0:
   memory_commands=[]
   with (run/'memory.jsonl').open('w') as log,(run/'memory.log').open('w') as err:
    for row in map(json.loads,manifest.splitlines()):
     c=row['case'];implementations=['baseline','candidate']+(['predecessor'] if not c['padded'] and not c['big'] else [])
     for impl in implementations:
      for op in ['encode','decode']:
       cmd=[str(binary),'--case',row['id'],'--memory',impl,'--operation',op]+flags;e=subprocess.run(cmd,stdout=log,stderr=err);memory_commands.append({'command':cmd,'exit':e.returncode})
       if e.returncode:
        receipt['memoryFailure']={'command':cmd,'exit':e.returncode}
        break
   receipt['memoryCommands']=memory_commands
   expected_total=sum(2*(2+(not row['case']['padded'] and not row['case']['big'])) for row in map(json.loads,manifest.splitlines()))
   captured=[json.loads(line) for line in (run/'memory.jsonl').read_text().splitlines()]
   receipt['memoryExpectedRows']=expected_total;receipt['memoryActualRows']=len(captured)
   expected_keys={(row['id'],impl,op) for row in map(json.loads,manifest.splitlines()) for impl in ['baseline','candidate']+(['predecessor'] if not row['case']['padded'] and not row['case']['big'] else []) for op in ['encode','decode']}
   actual_keys={(row['id'],row['implementation'],row['operation']) for row in captured}
   receipt['memoryExit']=0 if len(memory_commands)==len(captured)==expected_total and actual_keys==expected_keys and all(x['exit']==0 for x in memory_commands) else 1
receipt['elapsedSeconds']=time.monotonic()-start;receipt['harnessHashes']={str(f.relative_to(h)):hashlib.sha256(f.read_bytes()).hexdigest() for f in (h/'Sources').rglob('*') if f.is_file()};(run/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(run);raise SystemExit(receipt.get('memoryExit',0) or receipt.get('timingExit',receipt['buildExit']))
