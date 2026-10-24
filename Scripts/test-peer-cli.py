#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
import argparse,hashlib,json,os,pathlib,signal,struct,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--rle',required=True);p.add_argument('--jls',required=True);p.add_argument('--output',required=True);a=p.parse_args();rle=str(pathlib.Path(a.rle).resolve());jls=str(pathlib.Path(a.jls).resolve());out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True);checks=[]
def run(binary,args,data=None):
 r=subprocess.run([binary]+args,input=data,capture_output=True,timeout=10);assert r.returncode==0,(args,r.returncode,r.stderr);checks.append({'command':[binary]+args,'exit':r.returncode});return r.stdout
with tempfile.TemporaryDirectory(prefix='RLE pipe é ') as directory:
 d=pathlib.Path(directory);pixels=struct.pack('<21H',*[((x*193+y*31337)^0xA53C)&65535 for y in range(3) for x in range(7)])
 nrrd=b'NRRD0005\ntype: uint16\ndimension: 2\nsizes: 7 3\nencoding: raw\nendian: little\n\n'+pixels
 flags=['--width','7','--height','3','--storage-bits','16','--meaningful-bits','16','--sample-type','unsigned','--components','1','--colour','greyscale','--byte-order','little','--planar-configuration','0']
 source=d/'source.rle';source.write_bytes(run(rle,['encode','-i','-','--input-format','nrrd','--output-format','dicom-rle-frame','-o','-'],nrrd))
 jlsfile=d/'destination.jls'
 producer=subprocess.Popen([rle,'decode','-i',str(source),'--input-format','dicom-rle-frame','--output-format','nrrd','-o','-']+flags,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 consumer=subprocess.Popen([jls,'encode','-i','-','--input-format','nrrd','--mode','lossless','-o',str(jlsfile)],stdin=producer.stdout,stdout=subprocess.PIPE,stderr=subprocess.PIPE);producer.stdout.close()
 _,err=consumer.communicate(timeout=10);producer.wait(timeout=10);assert consumer.returncode==0 and producer.returncode==0,(consumer.returncode,err,producer.stderr.read());checks.append({'case':'rle-decode-pipe-jls-encode','exits':[producer.returncode,consumer.returncode]})
 producer=subprocess.Popen([jls,'decode','-i',str(jlsfile),'--output-format','nrrd','-o','-'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 consumer=subprocess.Popen([rle,'encode','-i','-','--input-format','nrrd','--output-format','dicom-rle-frame','-o','-'],stdin=producer.stdout,stdout=subprocess.PIPE,stderr=subprocess.PIPE);producer.stdout.close()
 restored,err=consumer.communicate(timeout=10);producer.wait(timeout=10);assert consumer.returncode==0 and producer.returncode==0,(consumer.returncode,err,producer.stderr.read());checks.append({'case':'jls-decode-pipe-rle-encode','exits':[producer.returncode,consumer.returncode]})
 raw=run(rle,['decode','-i','-','--input-format','dicom-rle-frame','--output-format','raw','-o','-']+flags,restored);assert raw==pixels
 # Slow producer exercises real cross-codec NRRD pipe admission/backpressure.
 proc=subprocess.Popen([jls,'encode','-i','-','--input-format','nrrd','-o',str(d/'slow.jls')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 for start in range(0,len(nrrd),7):proc.stdin.write(nrrd[start:start+7]);proc.stdin.flush();time.sleep(.002)
 proc.stdin.close();proc.wait(timeout=10);assert proc.returncode==0,proc.stderr.read();checks.append({'case':'slow-peer-nrrd-producer','exit':0})
 # Closed and deliberately stalled consumers must not hang or publish success.
 compressed=d/'large.packbits';compressed.write_bytes(bytes([0x81,0])*8192)
 base=[rle,'decode','-i',str(compressed),'--input-format','packbits','--decoded-bytes',str(1024*1024),'--output-format','raw','-o','-']
 for cancel in [False,True]:
  proc=subprocess.Popen(base+['--timeout','5' if cancel else '.15'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  if cancel:time.sleep(.1);proc.send_signal(signal.SIGINT)
  proc.wait(timeout=3);partial=proc.stdout.read();expected=130 if cancel else 5;assert proc.returncode==expected,(proc.returncode,proc.stderr.read());assert 0<=len(partial)<1024*1024;checks.append({'case':'slow-write-cancel' if cancel else 'slow-write-deadline','exit':proc.returncode,'partialBytes':len(partial)})
 read,write=os.pipe();os.close(read);proc=subprocess.run(base,stdout=write,stderr=subprocess.PIPE,timeout=3);os.close(write);assert proc.returncode==6;checks.append({'case':'closed-binary-output','exit':6})
 # A competing creator wins; the CLI cannot replace it without --overwrite.
 target=d/'race';proc=subprocess.Popen([rle,'encode','-i','-','--input-format','raw','--output-format','packbits','-o',str(target)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 target.write_bytes(b'creator');_,err=proc.communicate(b'pixels',timeout=3);assert proc.returncode==6 and target.read_bytes()==b'creator';assert not list(d.glob('.swiftrle-*.tmp'));checks.append({'case':'competing-creator-no-clobber','exit':6})
(out/'peer-cli.json').write_text(json.dumps({'passed':True,'tests':len(checks),'checks':checks},indent=2)+'\n');print('Peer/pipe checks passed:',len(checks))
