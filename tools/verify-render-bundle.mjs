import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('../',import.meta.url);
const manifest=JSON.parse(await readFile(new URL('deploy/web-manifest.json',root),'utf8'));
if(manifest.source!=='1bf63699d7ee745418e4de5594b0b93b5a0a0313'||manifest.files.length!==9)throw Error('Unexpected pilot source or export inventory');
const expected=['index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'].sort();
if(JSON.stringify(manifest.files.map(f=>f.name).sort())!==JSON.stringify(expected))throw Error('Missing, duplicate or unexpected export filename');
for(const entry of manifest.files){
 if(!/^index\.[a-z.-]+$/.test(entry.name))throw Error('Invalid export path');
 const data=await readFile(new URL('web/'+entry.name,root));
 if(data.length!==entry.bytes||createHash('sha256').update(data).digest('hex')!==entry.sha256)throw Error('Export mismatch: '+entry.name);
}
console.log('Verified nine exact baseline Web files; this is not live gameplay acceptance.');
