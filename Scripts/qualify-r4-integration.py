#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Ordinary release shared-owner, actual peer allocator and independent-oracle gate.
The supplied pinned peer snapshot is read-only; instrumentation lives in output only.
"""
import argparse,pathlib,json,hashlib,shutil,subprocess,os,time,re,sys,difflib
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--peer-snapshot',required=True,type=pathlib.Path);p.add_argument('--peer-manifest',required=True,type=pathlib.Path);a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
manifest=json.loads(a.peer_manifest.read_text());assert manifest['peerRevision']=='0791e54a5950bb8082af2218bce3800e03c777b9'
for name,digest in manifest['peerSourceSHA256'].items():assert hashlib.sha256((a.peer_snapshot/name).read_bytes()).hexdigest()==digest,name
assert shutil.disk_usage(out).free>1024**3
peer=out/'instrumented-peer';shutil.copytree(a.peer_snapshot,peer,ignore=shutil.ignore_patterns('.build','.git','.swiftpm'))
for f in peer.rglob('*'):
 if f.is_file():f.chmod(f.stat().st_mode|0o200)
f=peer/'Sources/SwiftJLS/ImageStorage.swift';original=f.read_text();needle='        self.byteCount = byteCount; self.allocationID = UUID()';assert original.count(needle)==1
modified=original.replace(needle,'        PixelAllocationProbe.observer?(byteCount)\n'+needle)+'\npublic enum PixelAllocationProbe {\n    @TaskLocal public static var observer: (@Sendable (Int) -> Void)?\n}\n';f.write_text(modified);(out/'instrumentation.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='pinned/ImageStorage.swift',tofile='instrumented/ImageStorage.swift')))
h=out/'SharedStorage';shutil.copytree(root/'Integration/SharedStorage',h,ignore=shutil.ignore_patterns('.build','.swiftpm','Package.resolved'))
text=(h/'Package.swift').read_text().replace('.package(path:"../..")','.package(path:'+json.dumps(str(root))+')').replace('.package(url:"https://github.com/raster-labs/SwiftJLS.git",revision:"0791e54a5950bb8082af2218bce3800e03c777b9")','.package(name:"SwiftJLS",path:'+json.dumps(str(peer))+')');(h/'Package.swift').write_text(text)
env=os.environ.copy();env['CLANG_MODULE_CACHE_PATH']=str(out/'module-cache');env['SWIFTPM_MODULECACHE_OVERRIDE']=str(out/'module-cache');env['SWIFTRLE_SHARED_ORACLE_OUTPUT']=str(out/'oracle')
r={'peerRevision':manifest['peerRevision'],'peerManifestSHA256':hashlib.sha256(a.peer_manifest.read_bytes()).hexdigest(),'ordinaryBuild':True,'checks':[],'passed':False};start=time.monotonic()
def run(name,cmd):
 t=time.monotonic();p=subprocess.run(cmd,cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/(name+'.log')).write_text(p.stdout);item={'name':name,'command':cmd,'exit':p.returncode,'seconds':time.monotonic()-t};r['checks'].append(item);(out/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');assert p.returncode==0,p.stdout[-3000:];return p.stdout,item
run('oracle-prepare',[sys.executable,'Scripts/shared-oracle.py','prepare',str(out/'oracle')])
text,item=run('integration-release',['swift','test','--disable-sandbox','--build-system','swiftbuild','--package-path',str(h),'--scratch-path',str(out/'build'),'-c','release','-j','2','--no-parallel','-Xswiftc','-DSWIFTRLE_PEER_ALLOCATION_AUDIT'])
counts=re.findall(r'Test run with (\d+) tests?.*passed',text);skips=len(re.findall(r'^.*↷.*$',text,re.M));assert skips==0;item['skippedTestEvents']=skips;assert counts and int(counts[-1])>=14;assert 'positive control1, real two-way transcode0' in text;item['testsPassed']=int(counts[-1]);item['actualPeerAllocatorPositiveControl']=1;item['actualPeerAllocatorAdditionalHandoffAllocations']=0
run('oracle-verify',[sys.executable,'Scripts/shared-oracle.py','verify',str(out/'oracle')])
r['passed']=True;r['seconds']=time.monotonic()-start;r['sourceSHA256']={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for base in ['Sources','Integration/SharedStorage'] for f in (root/base).rglob('*.swift')};r['instrumentationPatchSHA256']=hashlib.sha256((out/'instrumentation.patch').read_bytes()).hexdigest();(out/'receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(out)
