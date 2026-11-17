import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
const sha=b=>createHash('sha256').update(b).digest('hex');
const names=['index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'].sort();
export function verifyManifestContract(manifest,identity,inventory){
 if(!/^[a-f0-9]{40}$/.test(identity.source??'')||manifest.source!==identity.source)throw Error('Source identity mismatch');
 if(!Array.isArray(manifest.files)||JSON.stringify(manifest.files.map(f=>f.name).sort())!==JSON.stringify(names))throw Error('Unexpected export inventory');
 if(!Array.isArray(inventory.paths)||!inventory.paths.length||new Set(inventory.paths).size!==inventory.paths.length)throw Error('Invalid required runtime inventory');
 const actual=Object.keys(manifest.runtimeSources??{}).sort(),required=[...inventory.paths].sort();
 if(JSON.stringify(actual)!==JSON.stringify(required))throw Error('Runtime inventory incomplete or unexpected');
 for(const name of required){
  if((! /^(assets|scripts|scenes|data|backend)\//.test(name)&&!['project.godot','export_presets.cfg'].includes(name))||name.includes('..')||name.includes('\\'))throw Error('Invalid runtime path');
  if(!/^[a-f0-9]{64}$/.test(manifest.runtimeSources[name]))throw Error('Invalid runtime digest');
 }
 return true;
}
export async function verifyBundle(root=new URL('../',import.meta.url)){
 const manifest=JSON.parse(await readFile(new URL('deploy/web-manifest.json',root),'utf8'));
 const identity=JSON.parse(await readFile(new URL('deploy/source-identity.json',root),'utf8'));
 const inventoryBytes=await readFile(new URL('deploy/runtime-inventory.json',root));
 if(sha(inventoryBytes)!==identity.runtimeInventorySha256)throw Error('Required runtime inventory identity mismatch');
 verifyManifestContract(manifest,identity,JSON.parse(inventoryBytes));
 for(const f of manifest.files){const data=await readFile(new URL('web/'+f.name,root));if(data.length!==f.bytes||sha(data)!==f.sha256)throw Error('Export mismatch: '+f.name);}
 for(const [name,expected] of Object.entries(manifest.runtimeSources)){if(sha(await readFile(new URL(name,root)))!==expected)throw Error('Runtime source mismatch: '+name);}
 return {source:manifest.source,exports:manifest.files.length,runtimeSources:Object.keys(manifest.runtimeSources).length};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))console.log(JSON.stringify(await verifyBundle()));
