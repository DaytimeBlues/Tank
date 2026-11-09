"""Read-only binding of production, raw/served Web, native pixels and browser QA."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return json.loads((ROOT / name).read_text())


def sha(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


exported = read('evidence/visual-export-manifest.json')
assert len(exported['runtimeSources']) == 26
assert len(exported['rawExportFiles']) == 9
for name, expected in exported['runtimeSources'].items():
    assert sha(name) == expected['sha256'], 'production source drift: '+name
    assert (ROOT / name).stat().st_size == expected['bytes'], name
for name, expected in exported['rawExportFiles'].items():
    assert sha('web/'+name) == expected['sha256'], 'raw Web drift: '+name
    assert (ROOT / 'web' / name).stat().st_size == expected['bytes'], name

native = read('evidence/visual-native/report.json')
binding = native['sourceBinding']
assert binding['productionSources'] == {name: item['sha256'] for name, item in exported['runtimeSources'].items()}
original_models = read('evidence/map-model-provenance.json')['models']
assert binding['retainedBaselineGlbs'] == original_models
for name, expected in original_models.items():
    assert sha('art/models/baseline/'+name+'.glb') == expected
assert binding['fixtureSha256'] == sha('tests/visual_capture.gd')
assert binding['exportManifestSha256'] == sha('evidence/visual-export-manifest.json')
assert binding['pckSha256'] == sha('web/index.pck')
comparison = read('evidence/visual-native-comparison.json')
assert comparison['status'] == 'PASS' and comparison['mismatches'] == []
assert comparison['capturesCompared'] == len(native['captures']) == len(comparison['pngSha256']) == 21
assert comparison['reportSha256'] == sha('evidence/visual-native/report.json')
assert comparison['fixtureSha256'] == binding['fixtureSha256']
for name, expected in comparison['pngSha256'].items():
    assert sha('evidence/visual-native/'+name) == expected, 'native PNG drift: '+name
assert {Path(item['file']).name for item in native['captures']} == set(comparison['pngSha256'])

browser = read('evidence/visual-browser/browser-visual-review.json')
copied = read('evidence/visual-browser-copy.json')
assert sha('evidence/visual-browser/browser-visual-review.json') == copied['reportSha256'] == 'cd80ec91238cea267e0f808b6dd61c84f4b3088d64bde3e7b3df57087440c112'
assert sha('tools/browser-visual-review.mjs') == copied['runnerSha256'] == '93e6ca53dd5bbafcc592f5754b65bff73e7a29f328565cde1c4c270f03969253'
expected_browser_files = {'evidence/visual-browser/'+item['screenshot'] for item in browser['attempts']}
expected_browser_files |= {'evidence/visual-browser/'+name for name in ('visual-student-initial.png', 'browser-visual-review.json', 'browser-runner.log')}
assert len(expected_browser_files) == 29
assert set(copied['files']) == expected_browser_files, 'incomplete independent browser manifest membership'
actual_browser_files = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'evidence/visual-browser').rglob('*') if p.is_file()}
assert actual_browser_files == expected_browser_files, 'incomplete independent browser on-disk membership'
for name, expected in copied['files'].items():
    assert sha(name) == expected['sha256'], 'independent browser copy drift: '+name
    assert (ROOT / name).stat().st_size == expected['bytes'], name
assert browser['status'] == 'PASS' and len(browser['checks']) == 7 and len(browser['attempts']) == 26
assert not any(browser[key] for key in ('errors', 'consoleErrors', 'requestFailures'))
assert not any('error' in item for item in browser['attempts'])
assert browser['cleanup'] == {'browserClosed': True, 'serverListening': False}
served = read('evidence/visual-served-export-manifest.json')
assert len(served['files']) == 10
assert served['files'] == browser['frozenLocalExportManifest']
assert sha('evidence/visual-served-export-manifest.json') == copied['servedManifestSha256']
for name, expected in exported['rawExportFiles'].items():
    if name != 'index.html':
        assert served['files'][name] == expected, 'raw/served identity: '+name

print(json.dumps({'status': 'PASS', 'kind': 'Read-only byte/evidence binding, not visual quality or performance acceptance',
                  'productionSources': 26, 'retainedBaselineGlbs': 4, 'rawExportFiles': 9,
                  'servedExportFiles': 10, 'nativePngs': 21, 'browserChecks': 7,
                  'performanceAcceptance': 'BLOCKED_UNRESOLVED_CADENCE',
                  'observedBrowserRafMedianMs': browser['frameCadence']['allActive']['p50ms']}))
