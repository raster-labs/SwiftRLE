#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run only against a build explicitly compiled -DSWIFTRLE_CLI_TESTING.
The fault-injection branch does not exist in ordinary builds.
"""
import argparse,json,os,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--binary',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
r=subprocess.run([a.binary,'capabilities'],env=os.environ|{'SWIFTRLE_TEST_INTERNAL_FAILURE':'1'},stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert r.returncode==7 and not r.stdout and b'exit 7' in r.stderr
record={'tests':1,'passed':True,'exit':r.returncode,'stdout_empty':not r.stdout,'test_only_build_flag':'SWIFTRLE_CLI_TESTING'};a.output.write_text(json.dumps(record,indent=2)+'\n');print('Test-only internal-error process exit7 passed')
