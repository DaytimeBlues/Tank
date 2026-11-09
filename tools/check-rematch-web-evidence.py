"""Read-only current rematch runtime/export/browser/image identity checks.

Inherited visual/startup/preparation evidence remains historical and is not
relabelled or evaluated as current rematch acceptance by this checker.
"""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
def load(p):return json.loads((ROOT/p).read_text(encoding='utf-8'))
def identity(p):
 b=(ROOT/p).read_bytes();return {'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
m=load('evidence/rematch-web-export-manifest.json')
assert m['basisCommit']=='668285593e203ec2b4e402081bd55a19d89ff45b'
paths={'project.godot','export_presets.cfg'}
for folder in ['scripts','scenes','assets','data']:
 paths|={p.relative_to(ROOT).as_posix() for p in (ROOT/folder).rglob('*') if p.is_file()}
assert set(m['runtimeSources'])==paths and len(paths)==26
assert all(identity(n)==v for n,v in m['runtimeSources'].items())
assert m['runtimeSources']['scripts/main.gd']['sha256']=='6e2a9314e54635795831e61719900f409d809d81b4d04bf32d5c379ef500c3d9'
raw={'index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'}
assert set(m['rawExportFiles'])==raw
assert {p.name for p in (ROOT/'web').iterdir() if p.is_file() and not p.name.startswith('.')}==raw
assert all(identity('web/'+n)==v for n,v in m['rawExportFiles'].items())
assert m['rawExportFiles']['index.pck']['sha256']=='92dc0ea3af9317a2f3e086b37dfb920ce6ff273a9abd3681e67aca45aef310cb'
assert load('evidence/rematch-runtime-identity.json')['files']==m['runtimeSources']
assert load('evidence/rematch-raw-export-identity.json')['files']==m['rawExportFiles']
bridge=load('evidence/source-bridge-manifest.json')['files'];assert len(bridge)==46
assert all(identity(n)==v for n,v in bridge.items())
assert identity('evidence/startup-export-manifest.json')==identity('evidence/historical-startup-export-manifest-before-rematch.json')
if '--export-only' in sys.argv:
 print(json.dumps({'status':'PASS','kind':'Current rematch source/raw identity only; browser not checked','runtimePaths':26,'rawFiles':9,'authorityFiles':46}));sys.exit(0)
base=Path('evidence/rematch-browser');r=load(base/'ordinary-rematch-second-round.json')
assert r['status']=='PASS' and not r.get('failure')
assert r['readOnlyObservationAndOrdinaryInputOnly']
assert identity('tools/ordinary-rematch-second-round.mjs')['sha256']==r['harnessSha256']
assert identity('evidence/rematch-web-export-manifest.json')['sha256']==r['producerManifestSha256']
assert r['runtimeSources']==m['runtimeSources'] and r['rawExportFiles']==m['rawExportFiles']
assert r['sourceDirty']=='' and len(r['actualCommit'])==40 and r['actualCommit']==r['expectedCommit']
assert r['loopbackOnly'] and r['notDeployed'] and r['server']['host']=='127.0.0.1'
assert all(not r[n] for n in ['errors','consoleErrors','requestFailures'])
required=set(r['required']);checks={x['name']:x for x in r['checks']};assert required<=checks.keys()
assert {'rematch-both-correct-waiting-guidance','second-round-ready-start-full-health','second-round-ordinary-drive','second-round-accepted-fire-damage'}<=required
served=load(base/'rematch-served-identity.json');assert served==r['servedIdentity']
assert served['producerManifestSha256']==r['producerManifestSha256']
assert set(served['files'])==raw|{'godot-bridge.js'}
for n,v in served['files'].items():assert served['readback'][n]=={'status':200,**v}
for n in raw-{'index.html'}:assert served['files'][n]==m['rawExportFiles'][n]
html=(ROOT/'web/index.html').read_bytes().decode('utf-8').replace('</head>','<script src="/godot-bridge.js"></script>\n</head>').encode()
assert served['files']['index.html']=={'bytes':len(html),'sha256':hashlib.sha256(html).hexdigest()}
assert served['files']['godot-bridge.js']=={'bytes':1844,'sha256':'606993f82facb63c0d2c4beeebc964167250e31f9b13822892f640d1c7a89973'}
assert len(r['startup'])==2
for fx in r['startup']:
 assert fx['success'] and fx['status']=='DRAW_VERIFIED' and fx['drawnMaterials']==17 and fx['retired']
 assert fx['elapsedMs']<fx['deadlineMs']==2000 and fx['deadlineOverrunMs']==0
 assert len(fx['samples'])==17
 scene=fx['sceneStartup'];assert scene['success'] and scene['status']=='FIRST_SCENE_DRAW_VERIFIED'
 assert scene['elapsedMs']<scene['deadlineMs']==20000 and scene['deadlineOverrunMs']==0
 assert scene['drawCalls']>0 and scene['effectViewportCreated']==False and all(n>0 for n in scene['imageSize'])
for i in [1,2,3]:assert checks['ordinary-hit-'+str(i)]['victimHealth']==3-i
observations={x['label']:x for x in r['observations']}
for s in observations['rematch']['clients']:
 assert s['staging']['waiting'] and s['winner'] is None and not s['won']
 assert s['scores']=={'blue':0,'red':0} and len(s['bases'])==7
 assert all(b['owner']=='neutral' for b in s['bases'])
 assert len(s['players'])==2 and all(p['ready']==False for p in s['players'])
for s in observations['second-round-start']['clients']:
 assert not s['staging']['waiting'] and not s['won'] and s['scores']=={'blue':0,'red':0}
 assert len(s['players'])==2 and all(p['health']==3 for p in s['players'])
assert r['waitingHUDVisualReview']['pass'] and {x['page'] for x in r['waitingHUDVisualReview']['clients']}=={0,1}
for x in r['waitingHUDVisualReview']['clients']:
 assert 'Waiting for battle' in x['text'] and 'Choose Mark Ready.' in x['text'] and 'Hulls spawn at battle start.' in x['text']
 assert not any(w in x['text'] for w in ['Scrapped','respawn','Hull 0/3','Cannon:'])
for s in r['screenshots']:assert identity(base/s['path'])=={'bytes':s['bytes'],'sha256':s['sha256']}
assert len(r['browserIdentity'])==2
for b in r['browserIdentity']:
 assert b['version'].startswith('WebGL 2.0') and 'NVIDIA' in b['renderer'] and 'Direct3D11' in b['renderer']
assert r['cleanup']=={'browserClosed':True,'remainingBrowserProcesses':[],'serverListening':False,'nativeLoopbackSocketRefused':True}
print(json.dumps({'status':'PASS','kind':'Current rematch runtime/raw/served/browser/image binding, not hosted or human acceptance','runtimePaths':26,'rawFiles':9,'servedFiles':10,'authorityFiles':46,'requiredChecks':len(required),'allChecks':len(checks),'screenshots':len(r['screenshots']),'proofSha256':identity(base/'ordinary-rematch-second-round.json')['sha256']}))
