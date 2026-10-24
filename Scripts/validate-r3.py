#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""R3 gates supplement (and do not replace) validate-r1.py / the seven CI jobs."""
import argparse,hashlib,json,os,pathlib,platform,re,subprocess,sys,time
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--build-system',choices=['native','swiftbuild'],required=True);a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
receipt={'host':platform.platform(),'architecture':platform.machine(),'build_system':a.build_system,'checks':[],'passed':False};environment=os.environ.copy();environment['SWIFTRLE_SHARED_ORACLE_OUTPUT']=str(out/'shared-oracle')
def run(name,command,minimum_tests=None):
 start=time.monotonic();r=subprocess.run(list(map(str,command)),cwd=root,env=environment,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);(out/(name+'.log')).write_text(r.stdout);item={'name':name,'command':list(map(str,command)),'exit':r.returncode,'seconds':time.monotonic()-start}
 if minimum_tests is not None:
  counts=re.findall(r'Test run with (\d+) tests?.*passed',r.stdout);item['tests_passed']=int(counts[-1]) if counts else 0;item['required_tests']=minimum_tests
 receipt['checks'].append(item);(out/'r3-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 assert r.returncode==0 and (minimum_tests is None or item['tests_passed']>=minimum_tests),(name,r.stdout[-7000:]);print(name,'passed',flush=True);return r.stdout.strip()
common=['--disable-sandbox','--build-system',a.build_system,'-j','2']
run('peer-fixtures',[sys.executable,'Scripts/shared-oracle.py','prepare',out/'shared-oracle'])
for config in ['debug','release']:
 run('cli-build-'+config,['swift','build',*common,'-c',config,'--scratch-path',out/'cli-build'])
 binary=pathlib.Path(run('cli-bin-'+config,['swift','build',*common,'-c',config,'--scratch-path',out/'cli-build','--show-bin-path']).splitlines()[-1])/'swiftrle-cli'
 run('cli-'+config,[sys.executable,'Scripts/test-cli.py','--binary',binary,'--output',out/('cli-'+config)])
 run('integration-'+config,['swift','test',*common,'--package-path','Integration/SharedStorage','--scratch-path',out/'integration-build','-c',config,'--no-parallel'],12)
run('shared-oracle',[sys.executable,'Scripts/shared-oracle.py','verify',out/'shared-oracle'])
peer=out/'integration-build/checkouts/SwiftJLS';assert subprocess.check_output(['git','-C',str(peer),'rev-parse','HEAD'],text=True).strip()=='0791e54a5950bb8082af2218bce3800e03c777b9'
run('peer-cli-build',['swift','build',*common,'--package-path',peer,'--scratch-path',out/'peer-cli-build','--product','swiftjls-cli'])
peerbin=pathlib.Path(run('peer-cli-bin',['swift','build',*common,'--package-path',peer,'--scratch-path',out/'peer-cli-build','--show-bin-path']).splitlines()[-1])/'swiftjls-cli'
run('peer-pipes',[sys.executable,'Scripts/test-peer-cli.py','--rle',binary,'--jls',peerbin,'--output',out/'peer-pipes'])
run('internal-exit-build',['swift','build',*common,'--scratch-path',out/'internal-build','-Xswiftc','-DSWIFTRLE_CLI_TESTING'])
internal=pathlib.Path(run('internal-exit-bin',['swift','build',*common,'--scratch-path',out/'internal-build','--show-bin-path']).splitlines()[-1])/'swiftrle-cli'
run('internal-exit',[sys.executable,'Scripts/test-internal-exit.py','--binary',internal,'--output',out/'internal-exit.json'])
run('peer-allocator',[sys.executable,'Scripts/audit-peer-allocator.py','--peer',peer,'--output',out/'allocator-audit','--build-system',a.build_system])
receipt['passed']=True;receipt['peer_revision']='0791e54a5950bb8082af2218bce3800e03c777b9';receipt['head']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip();receipt['source_sha256']={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for base in ['Sources/SwiftRLECLI','Integration/SharedStorage/Sources','Integration/SharedStorage/Tests'] for p in (root/base).rglob('*.swift')};(out/'r3-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
