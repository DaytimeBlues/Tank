import {createGodotHostedGame} from './godot-assets.mjs';
try{
 const game=await createGodotHostedGame();
 const stop=()=>game.close().catch(()=>{process.exitCode=1;});
 process.once('SIGTERM',stop);process.once('SIGINT',stop);
 game.server.once('error',()=>{console.error('Private Godot classroom listener failed');process.exitCode=1;stop();});
 game.server.listen(game.port,game.host,()=>console.log('Private Godot classroom listener ready'));
}catch{console.error('Private Godot hosted configuration invalid');process.exitCode=1;}
