#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Isolated URL/revision consumer and persistent CLI/manual install/update proof."""
import argparse, hashlib, json, os, pathlib, re, shutil, subprocess, time
p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--revision',required=True);p.add_argument('--binary',required=True);p.add_argument('--consumer-evidence');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
if (out/'receipt.json').exists(): raise RuntimeError('new output directory required')
def sha(f): return hashlib.sha256(f.read_bytes()).hexdigest()
paths=[pathlib.Path(__file__).resolve(),root/'Examples/Consumer/Sources/Consumer/main.swift',root/'Scripts/install-cli.sh',root/'ManPages/swiftrle-cli.1',root/'VERSION',pathlib.Path(a.binary).resolve(),root/'Package.swift',*sorted((root/'Sources/SwiftRLE').glob('*.swift'))]
receipt={'status':'incomplete','revision':a.revision,'inputs':{str(f):sha(f) for f in paths},'commands':[]}
def save(): (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
def run(label,cmd,env=None,data=None,expected=0,timeout=300):
    entry={'label':label,'command':list(map(str,cmd)),'timeoutSeconds':timeout};receipt['commands'].append(entry);started=time.time()
    r=subprocess.run(entry['command'],cwd=root,env=env,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
    (out/(label+'.stdout')).write_bytes(r.stdout);(out/(label+'.stderr')).write_bytes(r.stderr);entry.update(exit=r.returncode,seconds=time.time()-started);save()
    if r.returncode!=expected: raise RuntimeError(label+' unexpected exit')
    return r.stdout
try:
    if shutil.disk_usage(out).free<1024**3: raise RuntimeError('less than 1GiB available')
    if a.consumer_evidence:
        previous=pathlib.Path(a.consumer_evidence).resolve();prior=json.loads((previous/'receipt.json').read_text())
        required=['url-consumer','consumer-binary','checkout-head']
        if any(not any(c['label']==label and c['exit']==0 for c in prior['commands']) for label in required): raise RuntimeError('prior consumer did not pass')
        for f in paths:
            if f!=pathlib.Path(__file__).resolve() and prior['inputs'].get(str(f))!=sha(f): raise RuntimeError('reused consumer input mismatch')
        if prior['revision']!=a.revision or not all(prior['coreComparison'].values()): raise RuntimeError('prior consumer revision mismatch')
        checkout=previous/'build/checkouts/SwiftRLE'
        current={str(f.relative_to(root)):sha(checkout/f.relative_to(root))==sha(f) for f in sorted((root/'Sources/SwiftRLE').glob('*.swift'))}
        if not all(current.values()): raise RuntimeError('reused checkout drift')
        executable=previous/'build/out/Products/Debug/Consumer'
        if sha(executable)!=prior['consumerBinarySHA256']: raise RuntimeError('reused consumer binary drift')
        receipt['consumerEvidence']={'receipt':str(previous/'receipt.json'),'sha256':sha(previous/'receipt.json'),'originalRunnerSHA256':prior['inputs'][str(pathlib.Path(__file__).resolve())],'scope':'only successful URL build/consumer/graph/core proof; original manual content assertion failed'}
        receipt['resolved']=prior['resolved'];receipt['coreComparison']=current
        run('reused-consumer-binary',[executable])
    else:
        consumer=out/'consumer';(consumer/'Sources/Consumer').mkdir(parents=True)
        shutil.copyfile(root/'Examples/Consumer/Sources/Consumer/main.swift',consumer/'Sources/Consumer/main.swift')
        (consumer/'Package.swift').write_text('// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "Consumer", platforms: [.macOS(.v26)], dependencies: [.package(url: "https://github.com/raster-labs/SwiftRLE.git", revision: "'+a.revision+'")], targets: [.executableTarget(name:"Consumer",dependencies:[.product(name:"SwiftRLE",package:"SwiftRLE")],swiftSettings:[.swiftLanguageMode(.v6)])])\n')
        args=['swift','run','--build-system','swiftbuild','-j','2','--package-path',consumer,'--scratch-path',out/'build','--cache-path',out/'cache','Consumer']
        run('url-consumer',args,timeout=600)
        resolved=json.loads((consumer/'Package.resolved').read_text());receipt['resolved']=resolved
        pins=resolved['pins']
        if len(pins)!=1 or pins[0]['location']!='https://github.com/raster-labs/SwiftRLE.git' or pins[0]['state']['revision']!=a.revision: raise RuntimeError('unexpected dependency graph')
        checkout=out/'build/checkouts/SwiftRLE'
        receipt['checkoutHead']=run('checkout-head',['git','-C',checkout,'rev-parse','HEAD']).decode().strip()
        if receipt['checkoutHead']!=a.revision: raise RuntimeError('checkout revision mismatch')
        receipt['coreComparison']={str(f.relative_to(root)):sha(checkout/f.relative_to(root))==sha(f) for f in sorted((root/'Sources/SwiftRLE').glob('*.swift'))}
        if not all(receipt['coreComparison'].values()): raise RuntimeError('URL core differs from submitted core')
        # Execute a second time without resolution/building: no runtime fetch is needed.
        executables=[f for f in (out/'build/out/Products/Debug').glob('Consumer') if f.is_file() and os.access(f,os.X_OK)]
        if len(executables)!=1: raise RuntimeError('consumer executable not uniquely found')
        receipt['consumerBinarySHA256']=sha(executables[0]);run('consumer-binary',[executables[0]])
    prefix=out/'Swift RLE é';env=dict(os.environ,PREFIX=str(prefix))
    run('install',[root/'Scripts/install-cli.sh',a.binary],env=env)
    installed=prefix/'bin/swiftrle-cli';manual=prefix/'share/man/man1/swiftrle-cli.1'
    if sha(installed)!=sha(pathlib.Path(a.binary)) or sha(manual)!=sha(root/'ManPages/swiftrle-cli.1'): raise RuntimeError('install differs')
    installed.write_bytes(b'stale binary');manual.write_bytes(b'stale manual')
    run('update',[root/'Scripts/install-cli.sh',a.binary],env=env)
    if sha(installed)!=sha(pathlib.Path(a.binary)) or sha(manual)!=sha(root/'ManPages/swiftrle-cli.1'): raise RuntimeError('update failed')
    run('version',[installed,'--version']);run('help',[installed,'--help']);run('command-help',[installed,'help','encode'])
    actual=run('manual-discovery',['man','-w','-M',prefix/'share/man','swiftrle-cli']).decode().strip()
    if manual.resolve() not in [pathlib.Path(x).resolve() for x in actual.splitlines()]: raise RuntimeError('manual not discovered')
    render=run('manual-render',['/usr/bin/mandoc','-Tascii',manual])
    if b'EXIT STATUS' not in re.sub(rb'.\x08',b'',render): raise RuntimeError('manual not rendered')
    raw=bytes(range(256))*2
    coded=run('encode-pipe',[installed,'encode','-i','-','--input-format','raw','--output-format','packbits','-o','-'],data=raw)
    decoded=run('decode-pipe',[installed,'decode','-i','-','--input-format','packbits','--decoded-bytes','512','--output-format','raw','-o','-'],data=coded)
    if decoded!=raw: raise RuntimeError('binary pipe changed bytes')
    run('malformed',[installed,'decode','-i','-','--input-format','packbits','--decoded-bytes','3','--output-format','raw','-o','-'],data=b'\x02A',expected=3)
    receipt['installedHashes']={'binary':sha(installed),'manual':sha(manual)}
    receipt['endInputs']={str(f):sha(f) for f in paths}
    if receipt['inputs']!=receipt['endInputs']: raise RuntimeError('input drift')
    receipt['status']='passed'
except Exception as e: receipt['status']='failed';receipt['error']=repr(e);raise
finally: save()
