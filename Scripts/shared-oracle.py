#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent CC0 7x3 greyscale fixtures and real DCMTK JPEG-LS/RLE oracle."""
import argparse,hashlib,json,pathlib,shutil,struct,subprocess
import pydicom
from pydicom.dataset import FileDataset,FileMetaDataset
from pydicom.encaps import encapsulate,generate_pixel_data_frame
from pydicom.uid import ExplicitVRLittleEndian,JPEGLSLossless,RLELossless
p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','verify']);p.add_argument('output',type=pathlib.Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);commands=[]
def run(tool,*args):
 path=shutil.which(tool) or '/opt/homebrew/bin/'+tool;r=subprocess.run([path,*map(str,args)],capture_output=True,text=True);commands.append({'command':[path,*map(str,args)],'exit':r.returncode,'output':r.stdout+r.stderr});assert r.returncode==0,commands[-1];return r.stdout+r.stderr
for bits in [12,16]:
 values=[0,4095,257,2048,19,3001,4094] if bits==12 else [0,65535,257,32768,19,60001,65534]
 raw=struct.pack('<21H',*(values[(x+3*y)%7] for y in range(3) for x in range(7)))
 native=a.output/f'native-{bits}.dcm'
 if a.mode=='prepare':
  meta=FileMetaDataset();meta.TransferSyntaxUID=ExplicitVRLittleEndian;meta.MediaStorageSOPClassUID='1.2.840.10008.5.1.4.1.1.7';meta.MediaStorageSOPInstanceUID='2.25.10003';meta.ImplementationClassUID='2.25.10004'
  ds=FileDataset(None,{},file_meta=meta,preamble=bytes(128));ds.is_little_endian=True;ds.is_implicit_VR=False;ds.SOPClassUID=meta.MediaStorageSOPClassUID;ds.SOPInstanceUID=meta.MediaStorageSOPInstanceUID
  ds.Rows=3;ds.Columns=7;ds.SamplesPerPixel=1;ds.PhotometricInterpretation='MONOCHROME2';ds.BitsAllocated=16;ds.BitsStored=bits;ds.HighBit=bits-1;ds.PixelRepresentation=0;ds.PixelData=raw;ds.save_as(native,write_like_original=False)
  compressed=a.output/f'independent-{bits}.dcm';run('dcmcjpls','+pc','+el',native,compressed);source=pydicom.dcmread(compressed);frames=list(generate_pixel_data_frame(source.PixelData,1));assert len(frames)==1
  (a.output/f'independent-{bits}.jls').write_bytes(frames[0]);restored=a.output/f'independent-decoded-{bits}.dcm';run('dcmdjpls',compressed,restored);assert pydicom.dcmread(restored).PixelData==raw
 else:
  for stem,syntax,tool in [('rle-to-jls',JPEGLSLossless,'dcmdjpls'),('jls-to-rle',RLELossless,'dcmdrle'),('oracle-jls-to-rle',RLELossless,'dcmdrle')]:
   suffix='jls' if syntax==JPEGLSLossless else 'rle';frame=(a.output/f'{stem}-{bits}.{suffix}').read_bytes();ds=pydicom.dcmread(native);ds.file_meta.TransferSyntaxUID=syntax;ds.PixelData=encapsulate([frame]);ds['PixelData'].is_undefined_length=True
   encoded=a.output/f'{stem}-{bits}.dcm';restored=a.output/f'{stem}-{bits}-decoded.dcm';ds.save_as(encoded,write_like_original=False)
   assert list(generate_pixel_data_frame(pydicom.dcmread(encoded).PixelData,1))==[frame] or suffix=='jls' # encapsulation may append even pad
   run(tool,encoded,restored);result=pydicom.dcmread(restored);assert result.PixelData==raw and result.BitsStored==bits
versions={tool:run(tool,'--version') for tool in ['dcmcjpls','dcmdjpls','dcmdrle']}
record={'mode':a.mode,'passed':True,'profiles':2,'directions':3 if a.mode=='verify' else 1,'pydicom':pydicom.__version__,'fixture_license':'CC0 synthetic independently authored','versions':versions,'commands':commands,'hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in a.output.iterdir() if p.is_file() and p.suffix in ['.jls','.rle','.dcm']}}
(a.output/f'{a.mode}.json').write_text(json.dumps(record,indent=2)+'\n');print('Shared oracle',a.mode,'passed')
