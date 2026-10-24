#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compile exact core and run bounded fixtures in one uniquely owned simulator.
No downloads; explicit installed runtime/device type. Host mode is supplemental.
"""
import argparse, hashlib, json, os, pathlib, re, shutil, subprocess, time, uuid
p=argparse.ArgumentParser()
p.add_argument('--output',required=True);p.add_argument('--sdk',default='macosx')
p.add_argument('--triple',default='arm64-apple-macosx26.0');p.add_argument('--runtime');p.add_argument('--device-type')
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.output).resolve()
out.mkdir(parents=True,exist_ok=True)
if (out/'receipt.json').exists(): raise RuntimeError('use a new output directory; preserve prior executions')
def digest(f): return hashlib.sha256(f.read_bytes()).hexdigest()
inputs=[pathlib.Path(__file__).resolve(),root/'Qualification/Runtime/main.swift',*sorted((root/'Sources/SwiftRLE').glob('*.swift'))]
def hashes(): return {str(f.relative_to(root)):digest(f) for f in inputs}
receipt={'commands':[],'inputHashes':hashes(),'sdk':a.sdk,'triple':a.triple,'runtime':a.runtime,'status':'incomplete','skips':0}
def save(): (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
def run(label,cmd,timeout=180,env=None):
    started=time.time();command=list(map(str,cmd));entry={'label':label,'command':command,'timeoutSeconds':timeout};receipt['commands'].append(entry)
    try:
        r=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout,cwd=root,env=env)
        (out/(label+'.log')).write_text(r.stdout);entry.update(exit=r.returncode,seconds=time.time()-started);save()
        if r.returncode: raise RuntimeError(label+' failed; see log')
        return r.stdout.strip()
    except subprocess.TimeoutExpired as e:
        data=e.stdout or b''; (out/(label+'.log')).write_bytes(data.encode() if isinstance(data,str) else data)
        entry.update(error='timeout',seconds=time.time()-started);save();raise
owned=None
try:
    mapping={'iphonesimulator':('iOS','ios','iOS'),'appletvsimulator':('tvOS','tvos','tvOS'),'watchsimulator':('watchOS','watchos','watchOS'),'xrsimulator':('xrOS','xros','xrOS')}
    if a.runtime:
        if a.sdk not in mapping or not a.device_type: raise RuntimeError('explicit simulator SDK/runtime/device required')
        platform,target,runtime_prefix=mapping[a.sdk]
        if a.triple != 'arm64-apple-'+target+'26.0-simulator' or not a.runtime.startswith('com.apple.CoreSimulator.SimRuntime.'+runtime_prefix+'-'):
            raise RuntimeError('SDK/triple/runtime mismatch')
    elif a.sdk!='macosx' or a.triple!='arm64-apple-macosx26.0': raise RuntimeError('host mode requires macOS arm64 triple')
    if shutil.disk_usage(out).free < 1024**3: raise RuntimeError('less than 1GiB available; stop')
    receipt['swift']=run('swift-version',['xcrun','swiftc','--version']);receipt['host']=run('host',['sw_vers']);receipt['architecture']=run('architecture',['uname','-m'])
    sdk=run('sdk-path',['xcrun','--sdk',a.sdk,'--show-sdk-path']);receipt['sdkVersion']=run('sdk-version',['xcrun','--sdk',a.sdk,'--show-sdk-version'])
    target_env=dict(os.environ,SDKROOT=sdk)
    receipt['compileSDKROOT']=sdk
    common=['xcrun','swiftc','-v','-swift-version','6','-strict-concurrency=complete','-module-cache-path',out/'module-cache','-sdk',sdk,'-target',a.triple,'-parse-as-library']
    run('build-library',common+['-emit-module','-emit-library','-static','-module-name','SwiftRLE',*sorted((root/'Sources/SwiftRLE').glob('*.swift')),'-emit-module-path',out/'SwiftRLE.swiftmodule','-o',out/'libSwiftRLE.a'],env=target_env)
    run('build-fixture',common+['-I',out,'-L',out,'-lSwiftRLE',root/'Qualification/Runtime/main.swift','-o',out/'runtime'],env=target_env)
    products=[out/'runtime',out/'libSwiftRLE.a',out/'SwiftRLE.swiftmodule']
    receipt['productHashes']={f.name:digest(f) for f in products}
    run('binary-identity',['file',out/'runtime']);receipt['machO']=run('macho-platform',['xcrun','vtool','-show-build',out/'runtime'])
    archive=run('archive-platform',['xcrun','otool','-l',out/'libSwiftRLE.a'])
    archive_platforms=re.findall(r'platform (\d+)',archive)
    archive_minima=re.findall(r'minos ([0-9.]+)',archive)
    expected_number={'macosx':'1','iphonesimulator':'7','appletvsimulator':'8','watchsimulator':'9','xrsimulator':'12'}[a.sdk]
    if not archive_platforms or any(v!=expected_number for v in archive_platforms) or len(archive_platforms)!=len(archive_minima) or any(v!='26.0' for v in archive_minima): raise RuntimeError('archive target platform/minimum mismatch')
    receipt['archiveObjectPlatforms']=archive_platforms;receipt['archiveObjectMinima']=archive_minima
    expected_platform={'macosx':'MACOS','iphonesimulator':'IOSSIMULATOR','appletvsimulator':'TVOSSIMULATOR','watchsimulator':'WATCHOSSIMULATOR','xrsimulator':'VISIONOSSIMULATOR'}[a.sdk]
    if 'platform '+expected_platform not in receipt['machO'] or 'minos 26.0' not in receipt['machO']: raise RuntimeError('Mach-O platform/minimum mismatch')
    if a.runtime:
        inventory=json.loads(run('runtime-inventory',['xcrun','simctl','list','runtimes','-j']))
        matches=[r for r in inventory['runtimes'] if r['identifier']==a.runtime and r['isAvailable']]
        if len(matches)!=1: raise RuntimeError('runtime unavailable')
        runtime=matches[0];receipt['runtimeIdentity']=runtime
        if a.device_type not in [d['identifier'] for d in runtime['supportedDeviceTypes']]: raise RuntimeError('device type unsupported by runtime')
        owned=run('create',['xcrun','simctl','create','SwiftRLE-R5-'+str(uuid.uuid4()),a.device_type,a.runtime]);receipt['ownedDevice']=owned;save()
        run('boot',['xcrun','simctl','boot',owned]);run('bootstatus',['xcrun','simctl','bootstatus',owned,'-b'],300)
        result=run('execute',['xcrun','simctl','spawn',owned,out/'runtime'])
    else: result=run('execute',[out/'runtime'])
    result=json.loads(result.splitlines()[-1]);receipt['result']=result
    if result['status']!='passed': raise RuntimeError('fixture did not pass')
    if a.runtime:
        env=result['processEnvironment']
        if result['compiledPlatform']!=platform or result['compiledSimulator'] is not True or env.get('SIMULATOR_UDID')!=owned or env.get('SIMULATOR_RUNTIME_VERSION')!=runtime['version'] or env.get('SIMULATOR_RUNTIME_BUILD_VERSION')!=runtime['buildversion'] or env.get('SIMULATOR_ARCHS')!='arm64':
            raise RuntimeError('actual target process identity mismatch')
        if runtime['version'] not in result['processOS'] or runtime['buildversion'] not in result['processOS']: raise RuntimeError('process OS mismatch')
    elif result['compiledPlatform']!='macOS' or result['compiledSimulator']: raise RuntimeError('host identity mismatch')
    receipt['endInputHashes']=hashes();receipt['endProductHashes']={f.name:digest(f) for f in products}
    if receipt['inputHashes']!=receipt['endInputHashes'] or receipt['productHashes']!=receipt['endProductHashes']: raise RuntimeError('qualification input/product drift')
    receipt['status']='passed'
except Exception as e:
    receipt['status']='failed';receipt['error']=repr(e);raise
finally:
    if owned:
        for label,verb in [('shutdown','shutdown'),('delete','delete')]:
            try: run(label,['xcrun','simctl',verb,owned])
            except Exception as e: receipt[label+'Error']=repr(e);receipt['status']='cleanup-failed'
    save()
