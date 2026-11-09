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
# Original authority/model provenance remains pinned. Visual assets intentionally
# differ, with their own explicit manifest and retained immutable source GLBs.
changes = json.loads((ROOT / 'evidence/visual-model-changes.json').read_text())
for name, expected in provenance['models'].items():
    if sha(ROOT / 'art/models/baseline' / (name + '.glb')) != expected:
        failures.append('original model provenance: ' + name)
    item = changes['models'][name]
    if item['baselineSha256'] != expected:
        failures.append('intentional model baseline: ' + name)
    if sha(ROOT / 'assets/models' / (name + '.glb')) != item['candidateSha256']:
        failures.append('intentional visual model manifest: ' + name)
if sha(ROOT / 'data/arena.json') != provenance['mapSha256']:
    failures.append('exact source map JSON')
report = {'kind': 'read-only exact bridge/map/original-model bytes plus intentional visual model manifest', 'status': 'FAIL' if failures else 'PASS',
          'bridgeFiles': len(bridge['files']), 'models': len(provenance['models']), 'failures': failures}
print(json.dumps(report))
raise SystemExit(bool(failures))
