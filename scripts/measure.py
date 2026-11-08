#!/usr/bin/env python3
"""Capture a group with Apple's footprint, never sum RSS. Python 3 is a developer prerequisite.
Use baseline before launching the isolated benchmark, then snapshot. New system WebKit XPC
processes are candidates, not proven ownership; inspect attribution.json before comparing.
"""
import argparse, datetime, json, pathlib, platform, subprocess, time

def run(*args):
    p = subprocess.run(args, text=True, capture_output=True)
    return {'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
def processes():
    rows=[]
    for line in run('/bin/ps','-axo','pid=,ppid=,rss=,%cpu=,time=,comm=')['stdout'].splitlines():
        parts=line.strip().split(None,5)
        if len(parts)==6:
            rows.append(dict(zip(['pid','ppid','rssKiB','cpuPercent','cpuTime','command'],parts)))
    return rows
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('mode',choices=['baseline','snapshot','cpu'])
p.add_argument('--out',required=True,type=pathlib.Path)
p.add_argument('--pid',type=int)
p.add_argument('--baseline',type=pathlib.Path)
p.add_argument('--webkit-pids',default='')
p.add_argument('--seconds',type=int,default=60)
a=p.parse_args(); a.out.mkdir(parents=True,exist_ok=True)
if a.mode=='baseline':
    (a.out/'baseline.json').write_text(json.dumps(processes(),indent=2)); raise SystemExit
rows=processes()
base={int(x['pid']) for x in json.loads(a.baseline.read_text())} if a.baseline else set()
explicit={int(x) for x in a.webkit_pids.split(',') if x}
webkit=[x for x in rows if x['command'].startswith('/System/Library/Frameworks/WebKit.framework/') and ('com.apple.WebKit.' in x['command']) and (int(x['pid']) in explicit if explicit else int(x['pid']) not in base)]
pids=[a.pid]+[int(x['pid']) for x in webkit] if a.pid else [int(x['pid']) for x in webkit]
pids=[x for x in pids if x]
(a.out/'attribution.json').write_text(json.dumps({'pids':pids,'webkitCandidates':webkit,'method':'explicit PIDs' if explicit else 'new WebKit PIDs relative to baseline, not ownership proof','warning':'Do not start other WebKit apps or integrated browser tabs during this interval. Inspect candidates. Existing XPC processes may be reused, so a baseline delta can undercount.'},indent=2))
if a.mode=='cpu':
    samples=[]; started=time.monotonic()
    while time.monotonic()-started<a.seconds:
        current=[x for x in processes() if int(x['pid']) in pids]
        samples.append({'elapsedSeconds':time.monotonic()-started,'processes':current})
        time.sleep(2)
    (a.out/'cpu.json').write_text(json.dumps(samples,indent=2))
    def cpu_seconds(value):
        fields=value.split(':')
        return sum(float(v)*60**i for i,v in enumerate(reversed(fields)))
    if len(samples)>1:
        elapsed=samples[-1]['elapsedSeconds']-samples[0]['elapsedSeconds']
        initial={x['pid']:cpu_seconds(x['cpuTime']) for x in samples[0]['processes']}
        deltas={x['pid']:cpu_seconds(x['cpuTime'])-initial[x['pid']] for x in samples[-1]['processes'] if x['pid'] in initial}
        (a.out/'cpu-summary.json').write_text(json.dumps({'elapsedSeconds':elapsed,'cpuSecondsPerProcess':deltas,'groupCpuPercent':sum(deltas.values())/elapsed*100,'limit':'Excludes processes created or exited during this interval. Frozen PID set.'},indent=2))
    raise SystemExit
if not pids: raise SystemExit('No processes. Supply --pid.')
result=run('/usr/bin/footprint',*[str(x) for x in pids],'-j',str(a.out/'footprint.json'))
(a.out/'footprint.txt').write_text(result['stdout']+result['stderr'])
metadata={'localTime':datetime.datetime.now().astimezone().isoformat(),'architecture':platform.machine(),'os':run('/usr/bin/sw_vers'),'hardwareModel':run('/usr/sbin/sysctl','-n','hw.model'),'memoryBytes':run('/usr/sbin/sysctl','-n','hw.memsize'),'swap':run('/usr/sbin/sysctl','vm.swapusage'),'pressure':run('/usr/bin/memory_pressure','-Q'),'vmStat':run('/usr/bin/vm_stat'),'footprintReturnCode':result['returncode'],'processes':rows if a.pid is None else [x for x in rows if int(x['pid']) in pids]}
(a.out/'metadata.json').write_text(json.dumps(metadata,indent=2))
print(json.dumps({'pids':pids,'footprintReturnCode':result['returncode'],'directory':str(a.out)}))
