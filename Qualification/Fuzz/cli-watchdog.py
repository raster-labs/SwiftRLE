#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent two-second local CLI child timeout, including pipe EOF handling."""
import resource,subprocess,sys
payload=sys.stdin.buffer.read(16385)
if len(payload)>16384:raise SystemExit(5)
try:result=subprocess.run(sys.argv[1:],input=payload,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=2)
except subprocess.TimeoutExpired:raise SystemExit(124)
sys.stdout.buffer.write(result.stdout);sys.stderr.buffer.write(result.stderr)
rss=int(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)*(1 if sys.platform=='darwin' else 1024)
sys.stderr.buffer.write(('\nSWIFTRLE_CLI_CHILD_PEAK_RSS_BYTES='+str(rss)+'\n').encode())
ownrss=int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)*(1 if sys.platform=='darwin' else 1024)
sys.stderr.buffer.write(('SWIFTRLE_WATCHDOG_PEAK_RSS_BYTES='+str(ownrss)+'\n').encode())
raise SystemExit(result.returncode)
