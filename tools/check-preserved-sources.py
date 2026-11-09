"""Compare original Tank sources with the before-work read-only snapshots."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('snapshots', nargs='+', type=Path)
args = parser.parse_args()
sources = []
for snapshot in args.snapshots:
    before = json.loads(snapshot.read_text())
    root = Path(before['source']).resolve(strict=True)
    def git(*command):
        return subprocess.check_output(['git', '-C', str(root), *command]).decode().strip()
    head = git('rev-parse', 'HEAD')
    status = git('status', '--porcelain')
    failures = []
    if head != before['head']: failures.append('HEAD changed')
    if status != before['status']: failures.append('Git status changed')
    current = set(subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard', '-z']).decode().strip('\0').split('\0'))
    if current != set(before['files']): failures.append('tracked/untracked source file set changed')
    for name, item in before['files'].items():
        path = root / name
        if not path.is_file() or path.stat().st_size != item['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            failures.append('source bytes changed: ' + name)
    sources.append({'source':str(root),'head':head,'checkedFiles':len(before['files']),
                    'status':'PASS' if not failures else 'FAIL','failures':failures,
                    'preexistingGitStatusPreserved':status == before['status']})
report = {'status':'PASS' if all(s['status']=='PASS' for s in sources) else 'FAIL','sources':sources}
print(json.dumps(report, indent=2))
raise SystemExit(report['status'] != 'PASS')
