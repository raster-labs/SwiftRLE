#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Second ordinary build: isolated, instrumentation-only peer snapshot.
Never edits a sibling repository or the unmodified pinned qualification snapshot.
"""
import argparse,difflib,hashlib,json,os,pathlib,re,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('--peer',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--build-system',choices=['native','swiftbuild'],default='swiftbuild');a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
assert shutil.disk_usage(out).free>1024**3,'Insufficient disk headroom'
head=subprocess.check_output(['git','-C',str(a.peer),'rev-parse','HEAD'],text=True).strip();assert head=='0791e54a5950bb8082af2218bce3800e03c777b9'
peer=out/'instrumented-peer'
# SPM intentionally makes dependency checkouts read-only. Change permissions
# only in this owned instrumentation copy, never the original dependency.
if peer.exists():
 for file in peer.rglob('*'):
  if file.is_file():file.chmod(file.stat().st_mode | 0o200)
shutil.copytree(a.peer,peer,ignore=shutil.ignore_patterns('.git','.build','.swiftpm'),dirs_exist_ok=True)
for file in peer.rglob('*'):
 if file.is_file():file.chmod(file.stat().st_mode | 0o200)
path=peer/'Sources/SwiftJLS/ImageStorage.swift';original=path.read_text();needle='        self.byteCount = byteCount; self.allocationID = UUID()';assert original.count(needle)==1
modified=original.replace(needle,'        PixelAllocationProbe.observer?(byteCount)\n'+needle)+'\npublic enum PixelAllocationProbe {\n    @TaskLocal public static var observer: (@Sendable (Int) -> Void)?\n}\n';path.write_text(modified)
patch=''.join(difflib.unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='pinned/ImageStorage.swift',tofile='instrumented/ImageStorage.swift'));(out/'instrumentation.patch').write_text(patch)
harness=out/'harness';shutil.copytree(root/'Integration/SharedStorage',harness,ignore=shutil.ignore_patterns('.build','.swiftpm','Package.resolved'),dirs_exist_ok=True)
manifest=(harness/'Package.swift').read_text().replace('.package(path:"../..")','.package(path:'+json.dumps(str(root))+')').replace('.package(url:"https://github.com/raster-labs/SwiftJLS.git",revision:"0791e54a5950bb8082af2218bce3800e03c777b9")','.package(name:"SwiftJLS",path:'+json.dumps(str(peer))+')');(harness/'Package.swift').write_text(manifest)
command=['swift','test','--disable-sandbox','--build-system',a.build_system,'--package-path',str(harness),'--scratch-path',str(out/'build'),'-j','2','--no-parallel','-Xswiftc','-DSWIFTRLE_PEER_ALLOCATION_AUDIT','--filter','instrumentedActualPeerAllocator']
r=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);(out/'allocator.log').write_text(r.stdout)
record={'peer_head':head,'instrumentation_patch_sha256':hashlib.sha256(patch.encode()).hexdigest(),'original_file_sha256':hashlib.sha256(original.encode()).hexdigest(),'instrumented_file_sha256':hashlib.sha256(modified.encode()).hexdigest(),'command':command,'exit':r.returncode,'passed':r.returncode==0 and 'positive control1, real two-way transcode0' in r.stdout,'sanitizer':False};(out/'allocator.json').write_text(json.dumps(record,indent=2)+'\n');assert record['passed'],r.stdout[-7000:];print('Actual peer allocator instrumented positive1 / transcode0 passed')
