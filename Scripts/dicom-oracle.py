#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Synthetic CC0 fixtures. pydicom writes/reads containers; DCMTK codes pixels.
No oracle dependency is imported by SwiftRLE. Missing tools are fatal.
"""
import argparse, hashlib, json, shutil, struct, subprocess
from pathlib import Path
import pydicom
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.encaps import encapsulate, generate_pixel_data_frame
from pydicom.uid import ExplicitVRLittleEndian, RLELossless

parser=argparse.ArgumentParser()
parser.add_argument('mode',choices=['prepare','verify'])
parser.add_argument('directory',type=Path)
a=parser.parse_args(); a.directory.mkdir(parents=True,exist_ok=True)
commands=[]
def tool(name):
    result=shutil.which(name) or next((str(p/name) for p in [Path('/opt/homebrew/bin'),Path('/usr/local/bin')] if (p/name).is_file()),None)
    if not result: raise RuntimeError('Required DCMTK tool unavailable: '+name)
    return result
def run(name,args):
    cmd=[tool(name)]+list(map(str,args)); p=subprocess.run(cmd,capture_output=True,text=True)
    commands.append({'command':cmd,'exit':p.returncode,'output':p.stdout+p.stderr})
    if p.returncode: raise RuntimeError(commands[-1])
    return p.stdout

def value(bits,precision,signed,c,x,y):
    mask=(1<<precision)-1
    n=[0,mask,1,1<<(precision-1),mask-1,0x53][(x+y*3+c)%6]&mask
    return n|(((1<<bits)-1)^mask) if signed and n&(1<<(precision-1)) else n

def payload(case,planar=None):
    bits=case['bits']; planar=case['planar'] if planar is None else planar
    cells=[]
    order=((c,x,y) for c in range(case['components']) for y in range(2) for x in range(3)) if planar else ((c,x,y) for y in range(2) for x in range(3) for c in range(case['components']))
    for c,x,y in order: cells.append(value(bits,case['precision'],case['signed'],c,x,y))
    return b''.join(n.to_bytes(bits//8,'little') for n in cells)

def create(case):
    meta=FileMetaDataset(); meta.TransferSyntaxUID=ExplicitVRLittleEndian
    meta.MediaStorageSOPClassUID='1.2.840.10008.5.1.4.1.1.7'; meta.MediaStorageSOPInstanceUID='2.25.10001'
    meta.ImplementationClassUID='2.25.10002'
    ds=FileDataset(None,{},file_meta=meta,preamble=bytes(128)); ds.is_little_endian=True; ds.is_implicit_VR=False
    ds.SOPClassUID=meta.MediaStorageSOPClassUID; ds.SOPInstanceUID=meta.MediaStorageSOPInstanceUID
    ds.Rows=2; ds.Columns=3; ds.SamplesPerPixel=case['components']; ds.PhotometricInterpretation=case['photo']
    ds.BitsAllocated=case['bits']; ds.BitsStored=case['precision']; ds.HighBit=case['precision']-1; ds.PixelRepresentation=int(case['signed'])
    if case['components']>1: ds.PlanarConfiguration=case['planar']
    if case['photo']=='PALETTE COLOR':
        for channel in ['Red','Green','Blue']:
            setattr(ds,channel+'PaletteColorLookupTableDescriptor',[2,0,16])
            setattr(ds,channel+'PaletteColorLookupTableData',struct.pack('<HH',0,65535))
    ds.PixelData=payload(case)
    return ds

if a.mode=='prepare':
    cases=[]
    for photo,components in [('MONOCHROME2',1),('MONOCHROME1',1),('RGB',3),('YBR_FULL',3),('PALETTE COLOR',1)]:
        for bits in [8,16]:
            for signed in ([False,True] if photo.startswith('MONO') else [False]):
                for precision in ([12,16] if bits==16 else [8]):
                    for planar in ([0,1] if components==3 else [0]):
                        case=dict(name=f'case-{len(cases):02}',photo=photo,components=components,bits=bits,precision=precision,signed=signed,planar=planar)
                        ds=create(case); native=a.directory/(case['name']+'-native.dcm'); compressed=a.directory/(case['name']+'-oracle.dcm')
                        ds.save_as(native,write_like_original=False)
                        # Independent container writer/readback and DCMTK tag validation.
                        assert pydicom.dcmread(native).PixelData==payload(case)
                        dump=run('dcmdump',['+P','0028,0010','+P','0028,0011','+P','0028,0100',native])
                        assert 'Rows' in dump and 'Columns' in dump and 'BitsAllocated' in dump
                        run('dcmcrle',[native,compressed])
                        encoded=pydicom.dcmread(compressed)
                        assert encoded.file_meta.TransferSyntaxUID==RLELossless
                        frames=list(generate_pixel_data_frame(encoded.PixelData,1)); assert len(frames)==1
                        frame=frames[0]
                        # Independent frame facts; no Swift parser is involved here.
                        words=struct.unpack('<16I',frame[:64]); assert words[0]==components*bits//8 and words[1]==64
                        assert all(v==0 for v in words[words[0]+1:])
                        (a.directory/(case['name']+'.rle')).write_bytes(frame)
                        case['native_sha256']=hashlib.sha256(native.read_bytes()).hexdigest(); case['frame_sha256']=hashlib.sha256(frame).hexdigest()
                        # Extracted/embedded frame must independently decode to expected cells.
                        ds.file_meta.TransferSyntaxUID=RLELossless; ds.PixelData=encapsulate([frame]); ds['PixelData'].is_undefined_length=True
                        embedded=a.directory/(case['name']+'-reembedded.dcm'); restored=a.directory/(case['name']+'-restored.dcm')
                        ds.save_as(embedded,write_like_original=False); run('dcmdrle',[embedded,restored])
                        restored_ds=pydicom.dcmread(restored)
                        assert restored_ds.PixelData[:len(payload(case))]==payload(case,int(getattr(restored_ds,'PlanarConfiguration',0)))
                        cases.append(case)
    record={'fixture_license':'CC0 synthetic','pydicom':pydicom.__version__,'cases':cases,'versions':{n:run(n,['--version']) for n in ['dcmcrle','dcmdrle','dcmdump']},'commands':commands}
    (a.directory/'oracle.json').write_text(json.dumps(record,indent=2))
    print(f'Prepared {len(cases)} independently embedded/extracted two-way fixtures')
else:
    record=json.loads((a.directory/'oracle.json').read_text())
    for case in record['cases']:
        ds=pydicom.dcmread(a.directory/(case['name']+'-native.dcm'))
        frame=(a.directory/(case['name']+'-swift.rle')).read_bytes()
        ds.file_meta.TransferSyntaxUID=RLELossless; ds.PixelData=encapsulate([frame]); ds['PixelData'].is_undefined_length=True
        path=a.directory/(case['name']+'-swift.dcm'); output=a.directory/(case['name']+'-decoded.dcm')
        ds.save_as(path,write_like_original=False)
        assert list(generate_pixel_data_frame(pydicom.dcmread(path).PixelData,1))==[frame]
        run('dcmdrle',[path,output]); decoded=pydicom.dcmread(output)
        expected=payload(case,int(getattr(decoded,'PlanarConfiguration',0)))
        assert decoded.PixelData[:len(expected)]==expected
        assert decoded.BitsStored==case['precision'] and decoded.PixelRepresentation==int(case['signed'])
        assert decoded.PhotometricInterpretation==case['photo']
        case['swift_frame_sha256']=hashlib.sha256(frame).hexdigest()
    record['swift_commands']=commands; record['two_way_passed']=len(record['cases'])
    (a.directory/'oracle.json').write_text(json.dumps(record,indent=2))
    print(f'Verified SwiftRLE -> DCMTK for {len(record["cases"])} cases')
