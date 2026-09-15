from pathlib import Path
import subprocess,json,time
p=Path(__file__).resolve().parent
controller='/Users/applelevne/.codex/skills/cursor-agents/scripts/cursor_worker.py'
command=['python3',controller,'run','--backend','devin','--project','/Users/applelevne/Documents/coding-projects/zoomies','--job',str(p/'job'),'--prompt-file',str(p/'assignment.txt'),'--assignment','Verify 30-second supervisor check-in and return to waiting','--read',str(p/'assignment.txt'),'--write',str(p/'scratch'),'--timeout','180']
with (p/'controller-output.json').open('w') as output:
 result=subprocess.run(command,stdout=output,stderr=subprocess.STDOUT)
rows=(p/'controller-output.json').read_text().splitlines()
try:
 final=json.loads(rows[-1])
 print(json.dumps({k:final.get(k) for k in ['status','elapsed_seconds','session_id','result','tool_failure_count','handoff']}))
except Exception:
 print((p/'controller-output.json').read_text()[-2000:])
raise SystemExit(result.returncode)
