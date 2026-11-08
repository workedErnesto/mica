#!/usr/bin/env python3
"""Run a release mica benchmark in its isolated QA profile. No UI automation and no user's tabs changed.
The final 10-tab workload stays open in the background for 15 minutes. Do not run other system
WebKit applications in this interval if relying on candidate PID attribution.
"""
import argparse,datetime,hashlib,json,pathlib,subprocess,sys,time
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--quick",action="store_true",help="Repeat 0/1/10 without the 15-minute soak")
options=parser.parse_args()
project=pathlib.Path(__file__).resolve().parent.parent
output=project/'work'/('benchmark-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
output.mkdir(parents=True)
(output/'binary-sha256.txt').write_text(hashlib.sha256((project/'build/mica.app/Contents/MacOS/mica').read_bytes()).hexdigest()+'\n')
profile=pathlib.Path.home()/'Library/Containers/app.mica.browser/Data/Library/Application Support/mica/QA'
startup=profile/'startup-seconds.txt'
for count,duration in ([(0,10),(1,65),(10,90)] if options.quick else [(0,15),(1,65),(10,900)]):
    directory=output/str(count);directory.mkdir()
    subprocess.run([sys.executable,str(project/'scripts/measure.py'),'baseline','--out',str(directory)],check=True)
    if startup.exists():startup.unlink()
    started=time.monotonic()
    with (directory/'console.txt').open('w') as console:
        process=subprocess.Popen([str(project/'build/mica.app/Contents/MacOS/mica'),'--qa',f'--benchmark={count}',f'--benchmark-duration={duration}'],stdout=console,stderr=console)
        while process.poll() is None and time.monotonic()-started<60 and not startup.exists():time.sleep(.05)
        launch=time.monotonic()-started
        (directory/'launch.json').write_text(json.dumps({'secondsToReadyMarker':launch,'pid':process.pid,'pollResolutionSeconds':.05,'coldBoot':False},indent=2))
        report=profile/f'benchmark-{count}.json'
        while process.poll() is None and (not report.exists() or report.stat().st_mtime<time.time()- (time.monotonic()-started)):time.sleep(.25)
        if report.exists():(directory/'pages.json').write_bytes(report.read_bytes())
        def measure(mode,label,seconds=None):
            cmd=[sys.executable,str(project/'scripts/measure.py'),mode,'--pid',str(process.pid),'--baseline',str(directory/'baseline.json'),'--out',str(directory/label)]
            if seconds:cmd+=['--seconds',str(seconds)]
            subprocess.run(cmd,check=True)
        measure('snapshot','loaded')
        print(json.dumps({'tabs':count,'pid':process.pid,'readySeconds':launch,'output':str(directory)}),flush=True)
        if count:measure('cpu','background',60)
        if count==10:
            for target in [300,600,850]:
                while process.poll() is None and time.monotonic()-started<target:time.sleep(1)
                if process.poll() is None:measure('snapshot',f'after-{target}s')
        process.wait()
    time.sleep(2)
print(str(output),flush=True)
