import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createGameServer} from './server.mjs';
import {serverConfig} from './src/server-config.mjs';
import {createPrivateAccess} from './src/private-access.mjs';

const names=['index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'];
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png'};
const sha=b=>createHash('sha256').update(b).digest('hex');

function browserBridge(mode){
 return `(()=>{'use strict';document.documentElement.dataset.tankNetwork=${JSON.stringify(mode)};
 let pending=null;
 window.tankGodotBridge=Object.freeze({
  info(){return JSON.stringify({protocol:location.protocol,host:location.host,mode:document.documentElement.dataset.tankNetwork,visible:document.visibilityState==='visible'});},
  cancel(){if(pending){pending.abort();pending=null;}},
  requestTicket(raw,generation,callback){
   if(pending)pending.abort();
   const controller=new AbortController();pending=controller;
   const answer=value=>{if(pending===controller)pending=null;callback(JSON.stringify({generation,...value}));};
   let scope;
   try{if(typeof raw!=='string'||raw.length>128||!Number.isSafeInteger(generation))throw Error();scope=JSON.parse(raw);
    if(!scope||Object.keys(scope).length!==2||!(scope.action==='create'&&scope.room===null||['join','reconnect'].includes(scope.action)&&typeof scope.room==='string'&&/^[A-Z0-9]{6}$/.test(scope.room)))throw Error();
   }catch{answer({error:'Invalid room action.'});return;}
   if(location.protocol!=='https:'||document.documentElement.dataset.tankNetwork!=='hosted'){answer({error:'Private online play requires the secure classroom page.'});return;}
   const timer=setTimeout(()=>controller.abort(),4000);
   fetch('/connection-ticket',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(scope),cache:'no-store',mode:'same-origin',credentials:'same-origin',redirect:'error',signal:controller.signal})
    .then(async response=>{if(!response.ok)throw Error();const data=await response.json();if(typeof data.ticket!=='string'||!/^[A-Za-z0-9_-]{16,512}$/.test(data.ticket))throw Error();answer({ticket:data.ticket});})
    .catch(()=>answer({error:'Access expired or unavailable. Return to Private access, then try again.'})).finally(()=>clearTimeout(timer));
  }
 });})();`;
}

export async function installGodotAssets(game,{mode='local',access=null,assetRoot=new URL('../web/',import.meta.url)}={}){
 if(!['local','hosted'].includes(mode)||mode==='hosted'&&!access)throw Error('Invalid Godot asset boundary');
 const assets=new Map();
 for(const name of names){
  let data=await readFile(new URL(name,assetRoot));
  if(name==='index.html'){
   const html=data.toString('utf8');
   if(!html.includes('</head>')||!html.includes('GODOT_CONFIG'))throw Error('Invalid Godot Web export');
   data=Buffer.from(html.replace('</head>','<script src="/godot-bridge.js"></script>\n</head>'));
  }
  assets.set(name,{data,type:types[name.slice(name.lastIndexOf('.'))],sha256:sha(data)});
 }
 const bridge=Buffer.from(browserBridge(mode));assets.set('godot-bridge.js',{data:bridge,type:types['.js'],sha256:sha(bridge)});
 const index=assets.get('index.html').data.toString('utf8');
 const hashes=[...index.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].filter(m=>m[1].trim()).map(m=>"'sha256-"+createHash('sha256').update(m[1]).digest('base64')+"'");
 const policy="default-src 'none'; script-src 'self' 'wasm-unsafe-eval' "+hashes.join(' ')+"; style-src 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; worker-src 'self' blob:; font-src 'self' data:; media-src 'self' blob:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";
 const handlers=game.server.listeners('request');
 if(handlers.length!==1)throw Error('Unexpected authority HTTP handler count');
 game.server.removeAllListeners('request');
 game.server.on('request',async(req,res)=>{
  let path;
  try{path=new URL(req.url,'http://localhost').pathname;}catch{res.writeHead(400,{'Cache-Control':'no-store'});res.end();return;}
  let name=path.startsWith('/godot/')?path.slice(7):path==='/godot-bridge.js'?'godot-bridge.js':mode==='hosted'?path.slice(1):null;
  if(path==='/godot/'||mode==='hosted'&&path==='/')name='index.html';
  const isGodot=name!==null&&(path.startsWith('/godot/')||assets.has(name)||mode==='hosted'&&path==='/');
  if(!isGodot){handlers[0].call(game.server,req,res);return;}
  try{
   if(access&&!await access.handleHttp(req,res,path))return;
   const asset=assets.get(name);
   if(!['GET','HEAD'].includes(req.method)||!asset){res.writeHead(404,{'Cache-Control':'no-store'});res.end('Not found');return;}
   res.writeHead(200,{'Content-Type':asset.type,'Content-Length':asset.data.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'same-origin','Cross-Origin-Resource-Policy':'same-origin','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp',
    ...(name==='index.html'?{'Content-Security-Policy':policy}:{} )});
   res.end(req.method==='HEAD'?undefined:asset.data);
  }catch{if(!res.destroyed&&!res.writableEnded){res.writeHead(503,{'Cache-Control':'no-store'});res.end('Classroom game unavailable');}}
 });
 return {files:Object.fromEntries([...assets].map(([name,a])=>[name,{bytes:a.data.length,sha256:a.sha256}])),mode};
}

// Same fail-closed Render constraints as the preserved entry. No listener,
// credential generation or paid resource is created by this factory.
export async function createGodotHostedGame(env=process.env,options={}){
 const fail=()=>{throw Error('Private Godot hosted configuration invalid');};
 const host=env.RENDER_EXTERNAL_HOSTNAME,origin=typeof host==='string'?'https://'+host:null;
 if(env.RENDER!=='true'||env.RENDER_SERVICE_TYPE!=='web'||env.IS_PULL_REQUEST!=='false'||env.TANK_NETWORK_MODE!=='hosted'||env.TANK_PRIVATE_PILOT!=='one-instance-epoch-v1'||
  !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.onrender\.com$/.test(host??'')||origin!==env.RENDER_EXTERNAL_URL||origin!==env.TANK_ALLOWED_ORIGINS||
  !/^[0-9a-f]{64}$/.test(env.TANK_HOST_KEY_SHA256??'')||!/^\d{1,5}$/.test(env.PORT??''))fail();
 let config;try{config=serverConfig(env);}catch{fail();}
 if(!config.port||[18012,18013,19099].includes(config.port))fail();
 const access=createPrivateAccess({audience:origin,hostKeyDigest:env.TANK_HOST_KEY_SHA256,now:options.now});
 const game=createGameServer({...config,hostedProvider:access,hostedAccess:access});
 try{return {...game,port:config.port,host:config.host,godot:await installGodotAssets(game,{mode:'hosted',access,assetRoot:options.assetRoot})};}
 catch(e){await game.close();throw e;}
}
