"""Read-only staged startup identity, rendered receipt and PNG binding.

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


exported = read('evidence/startup-export-manifest.json')
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
served = read('evidence/startup-served-export-manifest.json')['files']
assert set(served) == raw_names | {'godot-bridge.js'}
for name in raw_names - {'index.html'}:
    assert served[name] == exported['rawExportFiles'][name]
html = (ROOT / 'web/index.html').read_bytes().decode('utf-8')
assert html.count('</head>') == 1
served_html = html.replace('</head>', '<script src="/godot-bridge.js"></script>\n</head>').encode('utf-8')
assert served['index.html'] == {'bytes': len(served_html), 'sha256': hashlib.sha256(served_html).hexdigest()}, 'served HTML/helper injection drift'
assert served['godot-bridge.js'] == {'bytes': 1844, 'sha256': '606993f82facb63c0d2c4beeebc964167250e31f9b13822892f640d1c7a89973'}, 'approved local bridge identity drift'
local = read('evidence/startup-local-adapter.json')
assert local['status'] == 'PASS' and local['cleanup'] == {'serverListening': False}

for suffix in ('headless', 'native', 'timeout', 'late', 'scene-late'):
    report = read('evidence/startup-bound-' + suffix + '.json')
    assert report['status'] == 'PASS' and report['checks'] == 17 and not report['failures']
    binding = report['sourceBinding']
    assert binding['before'] == binding['after']
    assert set(binding['before']) == {'scripts/main.gd', 'scripts/shot_effects.gd', 'tests/effects_preparation.gd'}
    for name, expected in binding['before'].items():
        assert sha(name) == expected, 'preparation receipt source drift: ' + name
    receipt = report['preparation']
    assert receipt['retired']
    scene = receipt['sceneStartup']
    if suffix not in ('headless', 'scene-late'):
        assert scene['status'] == 'FIRST_SCENE_DRAW_VERIFIED' and scene['success']
        assert scene['drawCalls'] > 0 and not scene['effectViewportCreated']
        assert all(n > 0 for n in scene['imageSize'])
        assert scene['elapsedMs'] < scene['deadlineMs'] == 20000 and scene['deadlineOverrunMs'] == 0
        assert receipt['phase'] == 'EFFECT_VERIFICATION' and receipt['deadlineMs'] == 2000
        assert receipt['totalElapsedMs'] >= scene['elapsedMs'] + receipt['elapsedMs']
    if suffix == 'headless':
        assert receipt['status'] == 'SKIPPED_HEADLESS' and receipt['temporaryNodes'] == 0
    elif suffix == 'scene-late':
        assert receipt['status'] == 'FAILED' and not receipt['success']
        assert receipt['phase'] == 'SCENE_STARTUP' and receipt['temporaryNodes'] == receipt['drawnMaterials'] == 0
        assert scene['status'] == 'FAILED' and scene['reason'] == 'LATE_SCENE_DRAW_TIMEOUT'
        assert scene['deadlineOverrunMs'] > 0 and not scene['effectViewportCreated']
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
        assert receipt['elapsedMs'] >= receipt['deadlineMs'] == 2000
        assert receipt['deadlineOverrunMs'] == max(0, receipt['elapsedMs'] - 2000) and receipt['attempts'] <= 3

native = read('evidence/startup-native/report.json')
binding = native['sourceBinding']
assert binding['productionSources'] == {n: e['sha256'] for n, e in exported['runtimeSources'].items()}
assert binding['exportManifestSha256'] == sha('evidence/startup-export-manifest.json')
assert binding['pckSha256'] == sha('web/index.pck')
assert binding['fixtureSha256'] == sha('tests/visual_capture.gd')
original = read('evidence/map-model-provenance.json')['models']
assert binding['retainedBaselineGlbs'] == original
for name, expected in original.items():
    assert sha('art/models/baseline/' + name + '.glb') == expected
assert native['startupPreparation']['status'] == 'DRAW_VERIFIED'
comparison = read('evidence/startup-native-comparison.json')
assert comparison['status'] == 'PASS' and comparison['mismatches'] == []
assert comparison['reportSha256'] == sha('evidence/startup-native/report.json')
assert comparison['historicalReportSha256'] == sha('evidence/visual-native/report.json')
assert comparison['fixtureSha256'] == binding['fixtureSha256']
pngs = {Path(item['file']).name for item in native['captures']}
assert len(pngs) == comparison['capturesCompared'] == 21
assert set(comparison['pngSha256']) == pngs
assert {p.name for p in (ROOT / 'evidence/startup-native').glob('*.png')} == pngs
for name, expected in comparison['pngSha256'].items():
    assert sha('evidence/startup-native/' + name) == expected
    assert sha('evidence/visual-native/' + name) == expected, 'historical PNG mismatch: ' + name
gate = read('evidence/startup-gate.json')
assert gate['status'] == 'PASS' and gate['checks'] == 10 and not gate['failures']

# Independent browser evidence has explicit membership, not just whatever files
# happen to remain in a mutable copied manifest. Retain failed/partial attempts.
WEB = 'evidence/staged-web-final/'
copied = read(WEB + 'MANIFEST.json')
assert sha(WEB + 'MANIFEST.json') == '9dea60e4a0acf1c20c7deddaf6299725c91a8109d9bca416d82881845def466d'
fixed = {'browser-staged-cadence-repeat.mjs', 'browser-warmup-candidate-first-contact-miss.mjs',
         'browser-warmup-integration-attempt-3.mjs', 'browser-warmup-integration-attempt-4.mjs',
         'cadence-staged-candidate-first-repeat.json', 'cadence-warmup-candidate-first.json',
         'staged-candidate-first-plan.json', 'staged-candidate-first-repeat-runner.log',
         'staged-candidate-first-runner.log', 'staged-final-cleanup.json', 'startup-export-manifest.json'}
expected_web = set(fixed)
for number in (3, 4):
    folder = 'warmup-browser-attempt-' + str(number) + '/'
    report = read(WEB + folder + 'browser-warmup-integration.json')
    expected_web |= {folder + a['screenshot'] for a in report['attempts'] if a.get('screenshot')}
    expected_web |= {folder + n for n in ('browser-warmup-integration.json', 'runner.log', 'warmup-student-initial.png')}
    assert report['status'] == ('PARTIAL' if number == 3 else 'PASS')
assert len(expected_web) == 66 and set(copied) == expected_web, 'incomplete browser handoff membership'
assert {p.relative_to(ROOT / WEB).as_posix() for p in (ROOT / WEB).rglob('*') if p.is_file()} == expected_web | {'MANIFEST.json'}, 'browser on-disk membership'
for name, expected in copied.items():
    assert entry(WEB + name) == expected, 'independent browser evidence drift: ' + name
for name in fixed:
    if name.endswith('.mjs'):
        assert sha('tools/' + name) == copied[name]['sha256'], 'technical runner copy drift: ' + name
assert read(WEB + 'startup-export-manifest.json') == exported

browser = read(WEB + 'warmup-browser-attempt-4/browser-warmup-integration.json')
assert browser['candidateProducerCommit'] == '0e73b2408324fb6be7280e929cbf464f3909b75b'
assert browser['producerManifestSha256'] == sha('evidence/startup-export-manifest.json')
assert browser['runtimeSources'] == exported['runtimeSources'] and browser['rawExportFiles'] == exported['rawExportFiles']
assert browser['frozenLocalExportManifest'] == served
assert set(browser['checks']) == {'seated2', 'staging', 'ready', 'driveFire', 'neutral', 'sameSeat', 'noErrors'}
assert len(browser['attempts']) == 26 and not any(a.get('error') for a in browser['attempts'])
assert not browser['errors'] and not browser['consoleErrors'] and not browser['requestFailures']
assert browser['cleanup'] == {'browserClosed': True, 'serverListening': False}
assert browser['requestedJoinCode'] == browser['connectionAttempts'][1]['code']
assert sum(len(a) for a in browser['acceptedShotEvents']) == 4
assert len(browser['preparation']) == len(browser['webgl']) == 2
for receipt in browser['preparation']:
    assert receipt['status'] == 'DRAW_VERIFIED' and receipt['retired'] and receipt['drawnMaterials'] == 17
    assert receipt['elapsedMs'] < receipt['deadlineMs'] == 2000
    assert receipt['sceneStartup']['status'] == 'FIRST_SCENE_DRAW_VERIFIED'
    assert receipt['sceneStartup']['elapsedMs'] < receipt['sceneStartup']['deadlineMs'] == 20000
for renderer in browser['webgl']:
    assert 'RTX 5070' in renderer['unmaskedRenderer'] and 'D3D11' in renderer['unmaskedRenderer']

diagnostic = read(WEB + 'cadence-staged-candidate-first-repeat.json')
assert diagnostic['status'] == 'DIAGNOSTIC_COMPLETE_NOT_PERFORMANCE_ACCEPTED' and not diagnostic['errors']
assert diagnostic['candidateProductionCommit'] == browser['candidateProducerCommit']
assert diagnostic['candidateRuntimeSources'] == exported['runtimeSources']
assert diagnostic['episodes'][0]['label'] == 'visual-candidate', 'candidate must run first'
for episode in diagnostic['episodes']:
    assert episode['status'] == 'PASS_FUNCTIONAL_DIAGNOSTIC_ONLY' and not episode['errors']
    assert 'RTX 5070' in episode['webgl']['unmaskedRenderer'] and 'D3D11' in episode['webgl']['unmaskedRenderer']
    assert len(episode['shots']) == 3 and len(episode['phases']) == 4
    assert [shot['blocked'] for shot in episode['shots']] == [True, True, False]
    assert all(shot['hit'] is None for shot in episode['shots'])
    assert all(60 < phase['authoritativeDistanceM'] < 62 for phase in episode['phases'][1:3])
    assert abs(episode['phases'][3]['authoritativeDistanceM'] - 90) < 0.0001
    events = episode['requestEvents']
    requests = [event for event in events if event['event'] == 'request']
    assert {event['path'] for event in requests} == {'/godot/index.wasm', '/godot/index.pck'}
    assert not any(event['event'] == 'failed' for event in events)
    for request in requests:
        response = [e for e in events if e['id'] == request['id'] and e['event'] == 'response']
        finished = [e for e in events if e['id'] == request['id'] and e['event'] == 'finished']
        assert len(response) == len(finished) == 1 and response[0]['status'] == 200
        assert finished[0]['encodedDataLength'] >= episode['rawExport'][request['path'].split('/')[-1]]['bytes']
assert diagnostic['episodes'][0]['rawExport'] == exported['rawExportFiles']
assert diagnostic['episodes'][0]['servedExport'] == served
assert diagnostic['cleanup'] == {'browserClosed': True, 'activeGameClosed': True}
assert read(WEB + 'cadence-warmup-candidate-first.json')['status'] == 'FAIL', 'retain isolated aborted-loader attempt as FAIL'
cleanup = read(WEB + 'staged-final-cleanup.json')
assert not cleanup['ownedProcesses'] and not cleanup['ownedListeners']
assert len(cleanup['socketChecks']) == 5
assert all(not item['connected'] and item['refused'] and item['nativeError'] == 10061 for item in cleanup['socketChecks'])
print(json.dumps({'status': 'PASS', 'kind': 'Staged current runtime/Web, separate root-scene/effect actual-draw deadlines and raw PNG identity only; ordinary browser/performance acceptance separate',
                  'runtimeSources': len(inventory), 'rawWeb': 9, 'servedWeb': 10,
                  'materialCells': 17, 'nativePngs': 21, 'historicalPngMismatches': 0,
                  'independentBrowserFiles': 66, 'ordinaryBrowserChecks': 7, 'ordinaryAttempts': 26,
                  'candidateFirstContactMiss': 'functional diagnostic only, not performance acceptance'}))
