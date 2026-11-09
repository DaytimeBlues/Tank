"""Package and read back the small original editable model deliverable."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'recovery/tank-original-model-sources-20261108.zip'
OUT.parent.mkdir(parents=True, exist_ok=True)
items = {
    'README.txt': ROOT / 'docs/MODEL-SOURCE-BUNDLE.txt',
    'build-original-tank.py': ROOT / 'tools/build-original-tank.py',
    'visual-model-changes.json': ROOT / 'evidence/visual-model-changes.json',
}
for name in ('kestrel', 'bastion', 'foundry', 'palisade'):
    for extension in ('blend', 'glb'):
        items[f'models/{name}/{name}.{extension}'] = ROOT / f'art/models/{name}/{name}.{extension}'
checks = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in items.items()}
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, path in items.items():
        archive.writestr(name, path.read_bytes())
    archive.writestr('SHA256SUMS.txt', ''.join(f'{digest}  {name}\n' for name, digest in checks.items()))
with zipfile.ZipFile(OUT) as archive:
    assert set(archive.namelist()) == set(items) | {'SHA256SUMS.txt'}
    assert archive.testzip() is None
    for name, path in items.items():
        assert archive.read(name) == path.read_bytes(), name
report = {'status': 'PASS', 'kind': 'portable original editable model source bundle with exact readback',
          'file': OUT.name, 'bytes': OUT.stat().st_size,
          'sha256': hashlib.sha256(OUT.read_bytes()).hexdigest(), 'files': checks}
(ROOT / 'evidence/model-source-bundle.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
