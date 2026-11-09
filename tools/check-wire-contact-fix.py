"""Exact baseline64 source-only type repair; never runs/imports Godot."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = '64c42c08ed4db403c4c20833f738579e6c3fc98b'
MANIFEST = 'evidence/wire-contact-fix-manifest.json'
OLD_GATE = b'\tif bool(shot.get("hit",false)) or bool(shot.get("blocked",false)):\r\n'
NEW_GATE = (b'\tvar hit = shot.get("hit")\r\n'
            b'\tvar blocked = shot.get("blocked",false)\r\n'
            b'\tvar contact: bool = (hit is String and not hit.is_empty()) or (hit is bool and hit == true) or (blocked is bool and blocked == true)\r\n'
            b'\tif contact:\r\n')
BANNER = ('# Baseline64 typed-wire contact candidate, 8 November 2026\n\n'
          'This isolated checkout is Tank-Godot-Wire-Contact-Fix-20261108. Its only\n'
          'runtime delta from accepted64 is the explicit contact predicate. No style,\n'
          'shader, camera, model, authority or UI enhancement is included. Read\n'
          'docs/WIRE-CONTACT-FIX-20261108.md and evidence/wire-contact-fix-manifest.json.\n'
          'CPU/source packet only; source review, commit, Godot/runtime, ordinary Web,\n'
          'recovery and adoption remain HOLD. The historical record follows unchanged.\n\n').encode()
MODIFIED = {'scripts/shot_effects.gd','PROJECT_CARD.md'}
ADDED = {'tests/wire_contact_types.gd','tests/test_wire_contact_source.py',
         'tools/check-wire-contact-fix.py',MANIFEST,'evidence/wire-contact-cpu.json',
         'docs/WIRE-CONTACT-FIX-20261108.md'}
RUNTIME = {'assets/effects/accepted_shot.gdshader','assets/effects/accepted_shot.gdshader.uid',
           'data/arena.json','export_presets.cfg','project.godot','scenes/main.tscn'}
RUNTIME |= {'assets/models/'+n+'.glb'+suffix for n in ['bastion','foundry','kestrel','palisade'] for suffix in ['', '.import']}
RUNTIME |= {'scripts/'+n+'.gd'+suffix for n in ['arena_view','battle_map','main','shot_effects','tank_view','transport'] for suffix in ['', '.uid']}


def sha(raw): return hashlib.sha256(raw).hexdigest()


def baseline():
    names = subprocess.check_output(['git','ls-tree','-r','--name-only','-z',BASE],cwd=ROOT).decode().rstrip('\0').split('\0')
    raw = subprocess.check_output(['git','cat-file','--batch'],cwd=ROOT,input=''.join(BASE+':'+n+'\n' for n in names).encode())
    result,offset = {},0
    for name in names:
        end=raw.index(b'\n',offset);header=raw[offset:end].split()
        assert len(header)==3 and header[1]==b'blob'
        size=int(header[2]);result[name]=raw[end+1:end+1+size];offset=end+2+size
    assert offset==len(raw)
    return result


def snapshot():
    names=subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=ROOT).decode().rstrip('\0').split('\0')
    return {n:(ROOT/n).read_bytes() for n in set(names)}


def validate(actual,original,spec):
    assert spec['baselineCommit']==BASE and len(original)==spec['baselineTrackedFiles']==642
    assert set(spec['modifiedExisting'])==MODIFIED and set(spec['addedPaths'])==ADDED
    assert set(actual)==set(original)|ADDED,'Missing or unexpected packet path'
    old=original['scripts/shot_effects.gd'];assert old.count(OLD_GATE)==1
    assert actual['scripts/shot_effects.gd']==old.replace(OLD_GATE,NEW_GATE,1),'Runtime delta exceeds exact typed predicate'
    assert actual['PROJECT_CARD.md']==BANNER+original['PROJECT_CARD.md'],'Historical card changed'
    for n in set(original)-MODIFIED: assert actual[n]==original[n],'Baseline bytes changed: '+n
    assert set(spec['boundFiles'])==(MODIFIED|ADDED)-{MANIFEST,'evidence/wire-contact-cpu.json'}
    for n,v in spec['boundFiles'].items():assert sha(actual[n])==v['sha256'] and len(actual[n])==v['bytes'],'Unbound bytes: '+n
    assert set(spec['runtimeSources'])==RUNTIME and len(RUNTIME)==26
    for n,digest in spec['runtimeSources'].items():assert sha(actual[n])==digest,n
    bridge=json.loads(original['evidence/source-bridge-manifest.json'])['files'];assert len(bridge)==46
    for n,v in bridge.items():assert sha(actual[n])==v['sha256'] and len(actual[n])==v['bytes'],n
    assert not (ROOT/'.godot').exists(),'Source-only packet must not be imported/run'
    return {'status':'BASELINE64_TYPED_PREDICATE_CPU_SOURCE_PASS_RUNTIME_HOLD','baselineCommit':BASE,
            'baselineTrackedFiles':642,'other640BaselinePathsExact':True,'runtimeDelta':['scripts/shot_effects.gd'],
            'runtimeFiles':26,'authorityBridge46Exact':True,'allOriginalTestsAndShaderExact':True,
            'styleEnhancementsIncluded':False,'sourceReviewCommitRuntimeWebRecoveryAdoption':'HOLD'}


if __name__=='__main__':
    print(json.dumps(validate(snapshot(),baseline(),json.loads((ROOT/MANIFEST).read_text())),indent=2))
