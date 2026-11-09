// Local classroom preview. Hosted admission is a separate fail-closed factory.
import {createGameServer} from './server.mjs';
import {installGodotAssets} from './godot-assets.mjs';
const port=Number(process.env.TANK_GODOT_PORT??5218);
if(!Number.isInteger(port)||port<1||port>65535)throw Error('Invalid local port');
const game=createGameServer({networkMode:'local'});
export {game};
try{game.godot=await installGodotAssets(game,{mode:'local'});}catch(e){await game.close();throw e;}
await new Promise((ok,no)=>{game.server.once('error',no);game.server.listen(port,'127.0.0.1',ok);});
console.log(JSON.stringify({project:'tank-godot-classroom',host:'127.0.0.1',port,web:'http://127.0.0.1:'+port+'/godot/',exportedAssets:Object.keys(game.godot.files).length,authority:'preserved Node/Rapier00c832da'}));
let stopping=false;async function close(){if(stopping)return;stopping=true;await game.close();}
process.once('SIGTERM',close);process.once('SIGINT',close);
