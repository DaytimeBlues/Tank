import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {game} from '../backend/run-godot-local.mjs';
const {WebSocket}=createRequire(new URL('../backend/package.json',import.meta.url))('ws');
const report={kind:'actual local HTTP export bytes and unchanged WebSocket Origin admission',status:'INCOMPLETE',checks:[]};
const base='http://127.0.0.1:5218',sha=b=>createHash('sha256').update(b).digest('hex');
try {
 for(const [name,expected] of Object.entries(game.godot.files)){
  const path='/godot/'+name,r=await fetch(base+path);assert.equal(r.status,200,path);
  const bytes=Buffer.from(await r.arrayBuffer());
  assert.equal(sha(bytes),expected.sha256,path+' frozen served bytes');
  assert.equal(bytes.length,expected.bytes,path+' byte length');
  if(name==='index.html'){
   const text=bytes.toString('utf8'),policy=r.headers.get('content-security-policy');
   assert.equal(text,(await readFile(new URL('../web/index.html',import.meta.url),'utf8')).replace('</head>','<script src="/godot-bridge.js"></script>\n</head>'));
   assert.ok(policy.includes("'wasm-unsafe-eval'"));assert.ok(!policy.includes("'unsafe-eval'"));
   for(const match of text.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(match[1].trim())assert.ok(policy.includes("'sha256-"+createHash('sha256').update(match[1]).digest('base64')+"'"));
   report.checks.push('Exact generated helper injection and inline CSP hashes without JS unsafe-eval');
  }else if(name==='godot-bridge.js')assert.ok(bytes.toString().includes('requestTicket'));
  else assert.equal(sha(bytes),sha(await readFile(new URL('../web/'+name,import.meta.url))),path+' exact raw export');
  assert.equal(r.headers.get('x-content-type-options'),'nosniff');
  report.checks.push('Exact frozen export bytes '+path);
 }
 for(const path of ['/godot/backend/server.mjs','/godot/evidence/source-bridge-manifest.json','/godot/recovery/original-node-history.bundle','/godot/missing.pck','/godot/%2e%2e%2fbackend%2fserver.mjs']){
  assert.equal((await fetch(base+path)).status,404,path);report.checks.push('Not served '+path);
 }
 const head=await fetch(base+'/godot/index.html',{method:'HEAD'});assert.equal(head.status,200);assert.equal((await head.arrayBuffer()).byteLength,0);
 assert.equal((await fetch(base+'/godot/index.html',{method:'POST'})).status,404);report.checks.push('HEAD has no body; POST cannot mutate export');
 await new Promise((ok,no)=>{
  const socket=new WebSocket('ws://127.0.0.1:5218',{origin:'http://attacker.invalid'});const timer=setTimeout(()=>{socket.terminate();no(Error('Invalid Origin was not rejected'));},3000);
  socket.on('open',()=>{clearTimeout(timer);socket.close();no(Error('Cross-origin socket accepted'));});
  socket.on('unexpected-response',(_request,response)=>{clearTimeout(timer);try{assert.equal(response.statusCode,403);response.resume();socket.terminate();ok();}catch(e){no(e);}});
  socket.on('error',()=>{});
 });report.checks.push('Unchanged local WebSocket Origin rejects an attacker origin');
 report.status='PASS';
} catch(e){report.failure=String(e.stack||e);process.exitCode=1;}
finally{await game.close();report.cleanup={serverListening:game.server.listening};await writeFile(new URL('../evidence/local-adapter-smoke.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));}
