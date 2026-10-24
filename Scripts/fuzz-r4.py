#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Supervise selected bounded local synthetic mutation campaigns, not coverage-guided."""
import argparse,hashlib,json,os,pathlib,platform,resource,signal,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--seconds',type=int,default=3600);p.add_argument('--binary',required=True,type=pathlib.Path);p.add_argument('--cli',required=True,type=pathlib.Path);p.add_argument('--smoke',action='store_true');p.add_argument('--kernels',nargs='+',choices=['packbits','dicom','nrrd'],default=['packbits','dicom','nrrd']);a=p.parse_args()
assert len(a.kernels)==len(set(a.kernels)),'Duplicate kernel selection'
assert a.seconds>=3600 or a.smoke,'Full campaigns cannot be shorter than one hour'
root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
paths=[f for d in ['Sources','Qualification/Fuzz'] for f in (root/d).rglob('*') if f.suffix in ['.swift','.py']]+[pathlib.Path(__file__).resolve()]
inputs={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in paths+[a.binary.resolve(),a.cli.resolve()]}
receipt={'engine':'bounded deterministic xorshift64 mutation, not coverage-guided','host':platform.platform(),'seconds':a.seconds,'smoke':a.smoke,'inputSHA256':inputs,'selectedKernels':a.kernels,'maximumConcurrentKernelProcesses':len(a.kernels),'maximumConcurrentCLIChildren':1,'maximumConcurrentCLIWatchdogProcesses':1,'parserLimits':{'compressedBytes':16384,'decodedBytes':16384,'workspaceBytes':16384,'aggregateBytesPerOperation':65536,'packetDeadlineSeconds':1},'processLimits':{'addressSpaceHardLimit':'not set; parser allocation/work limits, watchdog and observed RSS reported separately','campaignProgressWatchdogSeconds':40,'CLIChildWallWatchdogSeconds':2},'campaigns':{},'passed':False};jobs={}
env=os.environ.copy();env['SWIFTRLE_FUZZ_CLI']=str(a.cli.resolve());env['SWIFTRLE_FUZZ_WATCHDOG']=str(root/'Qualification/Fuzz/cli-watchdog.py')
try:
 for mode in a.kernels:
  command=[str(a.binary.resolve()),mode,str(a.seconds),str(out/(mode+'.json'))];log=(out/(mode+'.log')).open('w')
  try:job=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  except BaseException:log.close();raise
  jobs[mode]=(job,time.monotonic(),log);receipt['campaigns'][mode]={'command':command,'pid':job.pid}
 while jobs:
  for mode,(job,start,log) in list(jobs.items()):
   waited,status,usage=os.wait4(job.pid,os.WNOHANG);path=out/(mode+'.json');elapsed=time.monotonic()-start
   if waited:
    job.returncode=os.waitstatus_to_exitcode(status);log.close();receipt['campaigns'][mode].update(exit=job.returncode,wallSeconds=elapsed,wait4MaximumRSSBytes=int(usage.ru_maxrss)*(1 if platform.system()=='Darwin' else 1024),rssSemantics='kernel wait4 ru_maxrss for this campaign job; CLI child independently reported; not an aggregate sum')
    assert job.returncode==0,(mode,job.returncode)
    item=json.loads(path.read_text());receipt['campaigns'][mode]['result']=item
    assert item['complete'] and item['elapsedSeconds']>=a.seconds and item['iterations']>0
    assert all(v>0 for k,v in item['surfaceCounts'].items() if k.endswith('.cases'))
    del jobs[mode]
   else:
    assert elapsed<a.seconds+90,(mode,'overall timeout')
    assert elapsed<40 or (path.exists() and time.time()-path.stat().st_mtime<40),(mode,'progress watchdog')
  (out/'campaigns.json').write_text(json.dumps(receipt,indent=2)+'\n');time.sleep(1)
 for name,digest in inputs.items():assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()==digest,('execution input changed',name)
 receipt['conservativeSumOfSeparateJobHighWaterRSSBytes']=sum(v['wait4MaximumRSSBytes'] for v in receipt['campaigns'].values())
 receipt['memoryLimitInterpretation']='Per-parser admission bounds are not whole-process RSS caps. Sum of separate job high-water RSS is conservative/non-simultaneous; do not infer an observed concurrent aggregate peak.'
 receipt['supervisorMaximumRSSBytes']=int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)*(1 if platform.system()=='Darwin' else 1024)
 receipt['passed']=True
finally:
 for job,start,log in jobs.values():
  if job.returncode is None:
   os.killpg(job.pid,signal.SIGTERM)
   try:job.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(job.pid,signal.SIGKILL);job.wait()
  log.close()
 (out/'campaigns.json').write_text(json.dumps(receipt,indent=2)+'\n')
