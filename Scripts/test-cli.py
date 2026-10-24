#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Real process contract tests; no external codec substitute."""
import argparse, hashlib, json, os, pathlib, re, signal, struct, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--binary',required=True);p.add_argument('--output',required=True);a=p.parse_args()
binary=str(pathlib.Path(a.binary).resolve()); out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
checks=[]
def run(args,code=0,data=None):
 r=subprocess.run([binary]+args,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
 assert r.returncode==code,(args,r.returncode,r.stderr)
 checks.append({'args':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest()});return r
with tempfile.TemporaryDirectory(prefix='SwiftRLE é ') as temp:
 d=pathlib.Path(temp);raw=bytes(range(256))*16;(d/'payload.bin').write_bytes(raw)
 for args in [[],['-h'],['--help'],['help'],['decode','--help'],['help','encode'],['--version'],['version'],['--quiet','--version']]:run(args)
 for n in range(1,6):
  for form in [['-'+'v'*n],['--verbose',str(n)],['--verbose='+str(n)],['-verbose:',str(n)],['-verbose:'+str(n)],['--verbose','+'*n],['-verbose:'+'+'*n],['-v']*n]:run(['capabilities']+form)
 for form in [['--verbose'],['-verbose'],['-v','--verbose=2','-v']]:run(['capabilities']+form)
 for form in [['-vvvvvv'],['--verbose=6'],['--verbose=-1'],['--verbose=bad'],['--quiet','-v'],['--verbose=0']]:run(['capabilities']+form,2)
 enc=['encode','-i',str(d/'payload.bin'),'--input-format','raw','--output-format','packbits','-o',str(d/'payload.packbits')]
 run(enc);run(enc,6);run(enc+['--overwrite']);encoded=(d/'payload.packbits').read_bytes()
 dec=['decode','-i',str(d/'payload.packbits'),'--input-format','packbits','--decoded-bytes','4096','--output-format','raw','-o',str(d/'restored.bin')]
 run(dec);assert (d/'restored.bin').read_bytes()==raw
 report=run(['decode','-i','-','--input-format','packbits','--decoded-bytes','4096','--output-format','raw','-o','-','--json','-vvvvv'],data=encoded)
 assert report.stdout==raw and b'"success":true' in report.stderr and str(d).encode() not in report.stderr
 run(['decode','-i','-','--input-format','packbits','--decoded-bytes','4','--output-format','raw','-o','-'],3,b'\x02A')
 for extra,code in [(['--mode','lossy'],4),(['--backend','required-accelerated'],4),(['--max-memory','100'],5),(['--quality','10'],2)]:run(enc+extra,code)
 run(['encode','-i','missing','--input-format','rle','--output-format','packbits','-o','bad'],4)
 frameflags=['--width','5','--height','3','--storage-bits','16','--meaningful-bits','16','--sample-type','unsigned','--components','1','--colour','greyscale','--byte-order','little','--planar-configuration','0']
 samples=[0,65535,257,8191,43,9,31999,49152,17,1,256,4095,60000,81,512]
 pixels=struct.pack('<15H',*samples)
 header=b'NRRD0005\ntype: ushort\ndimension: 2\nsizes: 5 3\nencoding: raw\nendian: little\n\n'
 nrrd=header+pixels
 frame=run(['encode','-i','-','--input-format','nrrd','--output-format','dicom-rle-frame','-o','-'],data=nrrd).stdout
 restored=run(['decode','-i','-','--input-format','dicom-rle-frame','--output-format','nrrd','-o','-']+frameflags,data=frame).stdout
 assert restored==nrrd
 for verb in ['inspect','validate']:
  assert json.loads(run([verb,'-i','-','--input-format','dicom-rle-frame']+frameflags,data=frame).stdout)['interpretationSource']=='external'
 for valid in [header.replace(b'\n',b'\r\n')+pixels,header.replace(b'type: ushort',b'TYPE: USHORT  ').replace(b'endian: little',b'ENDIAN:\tLITTLE ').replace(b'sizes: 5 3',b'sizes: 5\t3')+pixels]:run(['encode','-i','-','--input-format','nrrd','--output-format','dicom-rle-frame','-o','-'],data=valid)
 bads=[(nrrd[:-1],3),(header.replace(b'dimension: 2\nsizes: 5 3',b'sizes: 5 3\ndimension: 2')+pixels,3),(header.replace(b'type: ushort',b'type: ushort\ntype: ushort')+pixels,3),(header.replace(b'encoding: raw',b'encoding: gzip')+pixels,4),(header.replace(b'encoding: raw',b'data file: https://invalid/secret\nencoding: raw')+pixels,4),(b'NRRD0005\n'+b'X'*20000,3)]
 for field in [b'type: ushort\n',b'dimension: 2\n',b'sizes: 5 3\n',b'encoding: raw\n',b'endian: little\n']:
  bads.append((header.replace(field,b'')+pixels,3))
 for old,new,code in [(b'type: ushort',b'type: short',4),(b'dimension: 2',b'dimension: 3',4),(b'sizes: 5 3',b'sizes: 0 3',3),(b'sizes: 5 3',b'sizes: 5 3 1',3),(b'endian: little',b'endian: middle',4),(b'encoding: raw',b'encoding: ascii',4),(b'encoding: raw',b'byte skip: -1\nencoding: raw',4),(b'encoding: raw',b'kinds: domain domain\nencoding: raw',4)]:bads.append((header.replace(old,new)+pixels,code))
 bads.extend([(nrrd+b'X',3),(b'NRRD0005\n'+b'# short\n'*64+header.split(b'\n',1)[1]+pixels,5)])
 for data,code in bads:run(['encode','-i','-','--input-format','nrrd','--output-format','dicom-rle-frame','-o','-'],code,data)
 run(['decode','-i','-','--input-format','dicom-rle-frame','--output-format','nrrd','-o','-']+[('12' if x=='16' and i>0 and frameflags[i-1]=='--meaningful-bits' else x) for i,x in enumerate(frameflags)],4,frame)
 # Deterministic closed stdout pipe: no reader exists before process starts.
 read,write=os.pipe();os.close(read)
 r=subprocess.run([binary,'capabilities'],stdout=write,stderr=subprocess.PIPE);os.close(write);assert r.returncode==6;checks.append({'case':'closed-pipe','exit':6})
 # Input stalls remain cancellable and honor the same operation deadline.
 for cancel in [False,True]:
  cmd=[binary,'encode','-i','-','--input-format','raw','--output-format','packbits','-o',str(d/'slow'),'--timeout','0.15' if not cancel else '5']
  proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  if cancel:time.sleep(.1);proc.send_signal(signal.SIGINT)
  proc.wait(timeout=3);proc.stdin.close();assert proc.returncode==(130 if cancel else 5);assert not (d/'slow').exists();checks.append({'case':'slow-read-cancel' if cancel else 'slow-read-timeout','exit':proc.returncode})
 # Staged install and update include Unicode/space paths, matching manual and binary.
 root=pathlib.Path(__file__).resolve().parents[1];env=os.environ|{'PREFIX':'/Swift RLE é','DESTDIR':str(d/'stage')}
 subprocess.run([str(root/'Scripts/install-cli.sh'),binary],env=env,check=True)
 manual=d/'stage/Swift RLE é/share/man/man1/swiftrle-cli.1';assert manual.read_bytes()==(root/'ManPages/swiftrle-cli.1').read_bytes();manual.write_text('stale')
 subprocess.run([str(root/'Scripts/install-cli.sh'),binary],env=env,check=True);assert manual.read_bytes()==(root/'ManPages/swiftrle-cli.1').read_bytes()
 render=subprocess.run(['/usr/bin/mandoc','-Tascii',str(manual)] if pathlib.Path('/usr/bin/mandoc').exists() else ['groff','-man','-Tascii',str(manual)],stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert render.returncode==0 and b'EXIT STATUS' in re.sub(rb'.\x08',b'',render.stdout)
 lookup=subprocess.run(['man','-w','-M',str(manual.parents[1]),'swiftrle-cli'],stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert lookup.returncode==0 and b'swiftrle-cli.1' in lookup.stdout
 checks.append({'case':'staged-install-update-man-render-lookup','exit':0})
 assert not list(d.glob('.swiftrle-*.tmp'))
(out/'cli.json').write_text(json.dumps({'passed':True,'tests':len(checks),'checks':checks},indent=2)+'\n');print('CLI checks passed:',len(checks))
