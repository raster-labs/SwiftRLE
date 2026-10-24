#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Summarize all raw samples without hiding per-case regressions."""
import argparse,json,math,pathlib,statistics
p=argparse.ArgumentParser();p.add_argument('raw',type=pathlib.Path);p.add_argument('output',type=pathlib.Path);p.add_argument('--memory',type=pathlib.Path);a=p.parse_args();rows=[]
def stats(samples,pixels,byte_count):
 ordered=sorted(samples);median=statistics.median(samples)
 return {'count':len(samples),'medianSeconds':median,'p95Seconds':ordered[math.ceil(len(samples)*.95)-1],'minSeconds':ordered[0],'maxSeconds':ordered[-1],'spreadSeconds':ordered[-1]-ordered[0],'pixelsPerSecond':pixels/median,'logicalMiBPerSecond':byte_count/1048576/median}
for line in a.raw.read_text().splitlines():
 r=json.loads(line);c=r['case'];metrics={name:stats(r[name],c['width']*c['height'],r['logicalBytes']) for name in ['predecessor','baseline','candidate'] if r[name]}
 rows.append({'id':r['id'],'case':c,'operation':r['operation'],'metrics':metrics,'candidateOverScalar':metrics['candidate']['medianSeconds']/metrics['baseline']['medianSeconds'],'encodedBytes':r['encodedBytes'],'scalarEncodedBytes':r['scalarEncodedBytes'],'sizeIncreaseFraction':r['encodedBytes']/r['scalarEncodedBytes']-1,'ratio':r['encodedBytes']/r['logicalBytes'],'storageBytes':r['storageBytes'],'inputSHA256':r['inputSHA256'],'encodedSHA256':r['encodedSHA256'],'decodedStorageSHA256':r['decodedStorageSHA256'],'predecessorExclusion':r['predecessorExclusion']})
mem=[]
if a.memory:
 data=[json.loads(l) for l in a.memory.read_text().splitlines()]
 for r in data:
  if r['implementation']!='candidate':continue
  base=next(x for x in data if x['id']==r['id'] and x['operation']==r['operation'] and x['implementation']=='baseline')
  mem.append({'id':r['id'],'operation':r['operation'],'candidatePeakRSSBytes':r['peakRSSBytes'],'scalarPeakRSSBytes':base['peakRSSBytes'],'candidateOverScalar':r['peakRSSBytes']/base['peakRSSBytes'],'candidateOwned':r['owned'],'scalarOwned':base['owned'],'processPeakIncludesSetup':True})
a.output.write_text(json.dumps({'timingRows':len(rows),'rows':rows,'memory':mem,'latencyInvestigations':[r for r in rows if r['candidateOverScalar']>1.05],'memoryInvestigations':[r for r in mem if r['candidateOverScalar']>1.05],'sizeInvestigations':[r for r in rows if r['sizeIncreaseFraction']>.01],'methodology':'per-case median/p95/full spread; logical throughput includes components, padding excluded from throughput but included in capacity; memory runs are isolated ordinary-build processes; >5% is an investigation trigger, not a significance conclusion'},indent=2)+'\n')
