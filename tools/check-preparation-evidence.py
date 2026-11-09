"""Read-only final startup-preparation identity, rendered receipt and PNG binding.

The earlier visual-export/native/browser evidence belongs to 8b500974, not this
source. Its original validator is intentionally not relabelled for this export.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return json.loads((ROOT / name).read_text())


def sha(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def entry(name):
    return {'bytes': (ROOT / name).stat().st_size, 'sha256': sha(name)}


exported = read('evidence/preparation-export-manifest.json')
inventory = {'project.godot', 'export_presets.cfg'}
for directory in ('scripts', 'scenes', 'assets', 'data'):
    inventory |= {p.relative_to(ROOT).as_posix() for p in (ROOT / directory).rglob('*') if p.is_file()}
assert set(exported['runtimeSources']) == inventory, 'complete runtime membership'
for name, expected in exported['runtimeSources'].items():
    assert entry(name) == expected, 'runtime drift: ' + name
raw_names = {'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png',
             'index.icon.png', 'index.apple-touch-icon.png',
             'index.audio.worklet.js', 'index.audio.position.worklet.js'}
assert set(exported['rawExportFiles']) == raw_names
assert {p.name for p in (ROOT / 'web').iterdir() if p.is_file() and not p.name.startswith('.')} == raw_names
for name, expected in exported['rawExportFiles'].items():
    assert entry('web/' + name) == expected, 'raw Web drift: ' + name
served = read('evidence/preparation-served-export-manifest.json')['files']
assert set(served) == raw_names | {'godot-bridge.js'}
for name in raw_names - {'index.html'}:
    assert served[name] == exported['rawExportFiles'][name]
html = (ROOT / 'web/index.html').read_bytes().decode('utf-8')
assert html.count('</head>') == 1
served_html = html.replace('</head>', '<script src="/godot-bridge.js"></script>\n</head>').encode('utf-8')
assert served['index.html'] == {'bytes': len(served_html), 'sha256': hashlib.sha256(served_html).hexdigest()}, 'served HTML/helper injection drift'
assert served['godot-bridge.js'] == {'bytes': 1844, 'sha256': '606993f82facb63c0d2c4beeebc964167250e31f9b13822892f640d1c7a89973'}, 'approved local bridge identity drift'
local = read('evidence/preparation-local-adapter.json')
assert local['status'] == 'PASS' and local['cleanup'] == {'serverListening': False}

for suffix in ('headless', 'native', 'timeout', 'late'):
    report = read('evidence/preparation-bound-' + suffix + '.json')
    assert report['status'] == 'PASS' and report['checks'] == 15 and not report['failures']
    binding = report['sourceBinding']
    assert binding['before'] == binding['after']
    assert set(binding['before']) == {'scripts/main.gd', 'scripts/shot_effects.gd', 'tests/effects_preparation.gd'}
    for name, expected in binding['before'].items():
        assert sha(name) == expected, 'preparation receipt source drift: ' + name
    receipt = report['preparation']
    assert receipt['retired']
    if suffix == 'headless':
        assert receipt['status'] == 'SKIPPED_HEADLESS' and receipt['temporaryNodes'] == 0
    elif suffix == 'native':
        assert binding['renderer'] == 'gl_compatibility' and 'RTX 5070' in binding['adapter']
        assert receipt['status'] == 'DRAW_VERIFIED' and receipt['success']
        assert receipt['drawCalls'] == receipt['drawnMaterials'] == len(receipt['samples']) == 17
        assert receipt['elapsedMs'] < receipt['deadlineMs'] == 2000
        assert receipt['deadlineOverrunMs'] == 0 and receipt['temporaryNodes'] == 19
        assert len({tuple(item['pixel']) for item in receipt['samples']}) == 17
        assert all(int(item['rgba'][-2:], 16) > 10 for item in receipt['samples'])
        names = [item['cue'] for item in receipt['samples']]
        assert all(any(n.startswith(prefix) for n in names) for prefix in ('muzzle_hot', 'muzzle_smoke', 'contact_hot', 'contact_smoke', 'tracer'))
    else:
        assert receipt['status'] == 'FAILED' and not receipt['success']
        assert receipt['reason'] == ('DRAW_TIMEOUT' if suffix == 'timeout' else 'LATE_DRAW_TIMEOUT')
        assert receipt['deadlineOverrunMs'] > 0 and receipt['attempts'] <= 3

native = read('evidence/preparation-native/report.json')
binding = native['sourceBinding']
assert binding['productionSources'] == {n: e['sha256'] for n, e in exported['runtimeSources'].items()}
assert binding['exportManifestSha256'] == sha('evidence/preparation-export-manifest.json')
assert binding['pckSha256'] == sha('web/index.pck')
assert binding['fixtureSha256'] == sha('tests/visual_capture.gd')
original = read('evidence/map-model-provenance.json')['models']
assert binding['retainedBaselineGlbs'] == original
for name, expected in original.items():
    assert sha('art/models/baseline/' + name + '.glb') == expected
assert native['startupPreparation']['status'] == 'DRAW_VERIFIED'
comparison = read('evidence/preparation-native-comparison.json')
assert comparison['status'] == 'PASS' and comparison['mismatches'] == []
assert comparison['reportSha256'] == sha('evidence/preparation-native/report.json')
assert comparison['historicalReportSha256'] == sha('evidence/visual-native/report.json')
assert comparison['fixtureSha256'] == binding['fixtureSha256']
pngs = {Path(item['file']).name for item in native['captures']}
assert len(pngs) == comparison['capturesCompared'] == 21
assert set(comparison['pngSha256']) == pngs
assert {p.name for p in (ROOT / 'evidence/preparation-native').glob('*.png')} == pngs
for name, expected in comparison['pngSha256'].items():
    assert sha('evidence/preparation-native/' + name) == expected
    assert sha('evidence/visual-native/' + name) == expected, 'historical PNG mismatch: ' + name
gate = read('evidence/preparation-gate.json')
assert gate['status'] == 'PASS' and gate['checks'] == 10 and not gate['failures']
print(json.dumps({'status': 'PASS', 'kind': 'Current runtime/Web, native actual-draw lifecycle and raw PNG identity only; ordinary browser/performance acceptance separate',
                  'runtimeSources': len(inventory), 'rawWeb': 9, 'servedWeb': 10,
                  'materialCells': 17, 'nativePngs': 21, 'historicalPngMismatches': 0}))
