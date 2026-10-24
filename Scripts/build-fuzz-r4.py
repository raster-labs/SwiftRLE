#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compile the local synthetic parser qualification harness with shipped sources."""
import argparse,hashlib,json,pathlib,platform,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--sanitize',choices=['none','address','thread'],default='none');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
sources=sorted((root/'Sources/SwiftRLE').glob('*.swift'))+[root/'Sources/SwiftRLECLI/NRRD.swift',root/'Qualification/Fuzz/main.swift']
command=['swiftc','-parse-as-library','-module-name','SwiftRLE','-swift-version','6','-O','-num-threads','2','-module-cache-path',str(out/'module-cache')]
if platform.system()=='Darwin':command+=['-target',platform.machine()+'-apple-macos26.0']
if a.sanitize!='none':command+=['-sanitize='+a.sanitize]
command+=list(map(str,sources))+['-o',str(out/'mutation-campaign')]
start=time.monotonic()
with (out/'build.log').open('w') as log:r=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
receipt={'command':command,'exit':r.returncode,'elapsedSeconds':time.monotonic()-start,'sanitizer':a.sanitize,'host':platform.platform(),'compiler':subprocess.check_output(['swiftc','--version'],text=True),'inputSHA256':{str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}}
if r.returncode==0:receipt['binarySHA256']=hashlib.sha256((out/'mutation-campaign').read_bytes()).hexdigest()
(out/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');raise SystemExit(r.returncode)
