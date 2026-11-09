"""Validate original Blender outputs against retained source GLBs, without dependencies."""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
IDS = ('kestrel', 'bastion', 'foundry', 'palisade')
EXPECTED = json.loads((ROOT / 'evidence/map-model-provenance.json').read_text())['models']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def glb(path):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from('<III', raw)
    assert (magic, version, size) == (0x46546C67, 2, len(raw)), path
    count, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    document = json.loads(raw[20:20+count])
    binary_size, kind = struct.unpack_from('<II', raw, 20+count)
    assert kind == 0x004E4942
    return document, raw[28+count:28+count+binary_size]


def values(document, binary, index):
    accessor = document['accessors'][index]
    view = document['bufferViews'][accessor['bufferView']]
    assert not accessor.get('sparse') and not view.get('byteStride')
    components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[accessor['type']]
    format_code = {5123: 'H', 5125: 'I', 5126: 'f'}[accessor['componentType']]
    return struct.unpack_from('<'+format_code*components*accessor['count'], binary,
                              view.get('byteOffset', 0)+accessor.get('byteOffset', 0))


def stats(document, binary):
    parents = {c: i for i, node in enumerate(document['nodes']) for c in node.get('children', [])}
    bounds = [[math.inf]*3, [-math.inf]*3]
    triangles = 0
    primitives = 0
    for index, node in enumerate(document['nodes']):
        if 'mesh' not in node:
            continue
        translation = [0.0, 0.0, 0.0]
        cursor = index
        while True:
            ancestor = document['nodes'][cursor]
            assert ancestor.get('rotation', [0, 0, 0, 1]) == [0, 0, 0, 1]
            assert ancestor.get('scale', [1, 1, 1]) == [1, 1, 1]
            assert 'matrix' not in ancestor
            translation = [a+b for a, b in zip(translation, ancestor.get('translation', [0, 0, 0]))]
            if cursor not in parents:
                break
            cursor = parents[cursor]
        for primitive in document['meshes'][node['mesh']]['primitives']:
            assert primitive.get('mode', 4) == 4
            primitives += 1
            indices = values(document, binary, primitive['indices'])
            assert len(indices) % 3 == 0
            triangles += len(indices)//3
            position = values(document, binary, primitive['attributes']['POSITION'])
            normal = values(document, binary, primitive['attributes']['NORMAL'])
            assert all(math.isfinite(v) for v in position+normal)
            assert max(indices) < len(position)//3
            for axis in range(3):
                bounds[0][axis] = min(bounds[0][axis], min(position[axis::3])+translation[axis])
                bounds[1][axis] = max(bounds[1][axis], max(position[axis::3])+translation[axis])
    return {'triangles': triangles, 'primitives': primitives, 'materials': len(document['materials']), 'worldBounds': bounds}


def barrel(document, binary):
    node = next(n for n in document['nodes'] if n.get('name') == 'Barrel')
    return [{key: values(document, binary, accessor) for key, accessor in primitive['attributes'].items()} |
            {'indices': values(document, binary, primitive['indices'])}
            for primitive in document['meshes'][node['mesh']]['primitives']]


models = {}
for visual_id in IDS:
    baseline_path = ROOT / 'art/models/baseline' / (visual_id+'.glb')
    path = ROOT / 'assets/models' / (visual_id+'.glb')
    native = ROOT / 'art/models' / visual_id / (visual_id+'.blend')
    assert sha(baseline_path) == EXPECTED[visual_id], 'retained original '+visual_id
    baseline, baseline_binary = glb(baseline_path)
    document, binary = glb(path)
    before = stats(baseline, baseline_binary)
    after = stats(document, binary)
    assert document['nodes'] == baseline['nodes'], 'hierarchy, pivots, units and Muzzle '+visual_id
    assert barrel(document, binary) == barrel(baseline, baseline_binary), 'unchanged posed/recoiling Barrel '+visual_id
    assert [m['name'] for m in document['materials']] == [m['name'] for m in baseline['materials']]
    assert after['triangles'] < 12000 and after['primitives'] == before['primitives'] == 12
    assert after['materials'] == 6 and path.stat().st_size < 1024*1024
    assert not any(document.get(k) for k in ['images', 'textures', 'skins', 'animations'])
    assert not any('uri' in b for b in document['buffers'])
    assert all(abs(before['worldBounds'][end][axis]-after['worldBounds'][end][axis]) < 0.00001
               for end in range(2) for axis in range(3)), 'unchanged broad silhouette/bounds '+visual_id
    assert native.is_file(), 'editable original native Blender source '+visual_id
    assert sha(path) == sha(ROOT / 'art/models' / visual_id / (visual_id+'.glb'))
    models[visual_id] = {'baselineSha256': sha(baseline_path), 'candidateSha256': sha(path),
                         'baselineBytes': baseline_path.stat().st_size, 'bytes': path.stat().st_size,
                         'nativeBlendSha256': sha(native), 'nativeBlendBytes': native.stat().st_size,
                         'before': before, 'after': after, 'hierarchyAndPivotsUnchanged': True,
                         'muzzleAndBarrelGeometryUnchanged': True, 'boundsUnchanged': True}

result = {'status': 'PASS', 'basisCommit': '230a267f40087d8194de6cd45e8d390953e2fab3',
          'kind': 'Intentional source-original Blender geometry/material changes; no reference-image alignment claim',
          'generatorSha256': sha(ROOT / 'tools/build-original-tank.py'),
          'originalGeneratorSha256': sha(ROOT / 'art/models/generator-baseline.py'), 'models': models}
if '--write' in sys.argv:
    (ROOT / 'evidence/visual-model-changes.json').write_text(json.dumps(result, indent=2)+'\n')
else:
    expected = json.loads((ROOT / 'evidence/visual-model-changes.json').read_text())
    assert result == expected, 'Manifest drift; inspect and regenerate intentionally'
print(json.dumps(result, indent=2))
