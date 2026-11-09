"""Read-only byte checks of the retained authority, model and map foundation."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

failures = []
bridge = json.loads((ROOT / 'evidence/source-bridge-manifest.json').read_text())
for name, item in bridge['files'].items():
    path = ROOT / name
    if not path.is_file() or sha(path) != item['sha256']:
        failures.append('copied bridge bytes: ' + name)
provenance = json.loads((ROOT / 'evidence/map-model-provenance.json').read_text())
for name, expected in provenance['sources'].items():
    if sha(ROOT / 'backend' / name) != expected:
        failures.append('source provenance: ' + name)
for name, expected in provenance['models'].items():
    if sha(ROOT / 'assets/models' / (name + '.glb')) != expected:
        failures.append('model provenance: ' + name)
if sha(ROOT / 'data/arena.json') != provenance['mapSha256']:
    failures.append('exact source map JSON')
report = {'kind': 'read-only exact bridge/model/map bytes', 'status': 'FAIL' if failures else 'PASS',
          'bridgeFiles': len(bridge['files']), 'models': len(provenance['models']), 'failures': failures}
print(json.dumps(report))
raise SystemExit(bool(failures))
