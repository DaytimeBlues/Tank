import { fileURLToPath } from 'node:url';
import { createGameServer } from '../server.mjs';
import { serverConfig } from '../src/server-config.mjs';
import { createPrivateAccess } from '../src/private-access.mjs';

export function createRenderGame(env=process.env, options={}) {
 const fail=()=>{throw new Error('Private hosted configuration invalid');};
 const host=env.RENDER_EXTERNAL_HOSTNAME, origin=typeof host==='string'?'https://'+host:null;
 if(env.RENDER!=='true'||env.RENDER_SERVICE_TYPE!=='web'||env.IS_PULL_REQUEST!=='false'||
   env.TANK_NETWORK_MODE!=='hosted'||env.TANK_PRIVATE_PILOT!=='one-instance-epoch-v1'||
   !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.onrender\.com$/.test(host??'')||
   origin!==env.RENDER_EXTERNAL_URL||origin!==env.TANK_ALLOWED_ORIGINS||
   !/^[0-9a-f]{64}$/.test(env.TANK_HOST_KEY_SHA256??'')||!/^\d{1,5}$/.test(env.PORT??''))fail();
 let config;
 try{config=serverConfig(env);}catch{fail();}
 if(!config.port||[18012,18013,19099].includes(config.port))fail();
 const access=createPrivateAccess({audience:origin,hostKeyDigest:env.TANK_HOST_KEY_SHA256,now:options.now});
 return {...createGameServer({...config,hostedProvider:access,hostedAccess:access}),port:config.port,host:config.host};
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 try{
  const game=createRenderGame();
  const shutdown=()=>game.close().catch(()=>{process.exitCode=1;});
  process.once('SIGINT',shutdown);process.once('SIGTERM',shutdown);
  game.server.once('error',()=>{console.error('Private hosted listener failed');process.exitCode=1;shutdown();});
  game.server.listen(game.port,game.host,()=>console.log('Tank Battle private hosted listener ready'));
 }catch{console.error('Private hosted configuration invalid');process.exitCode=1;}
}
