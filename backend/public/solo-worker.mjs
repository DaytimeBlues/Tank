import RAPIER from './vendor/rapier.mjs';
import { SoloSimulation } from './src/solo-simulation.mjs';
await RAPIER.init();
let simulation,last=performance.now(),accumulator=0,physicsMs=0;
const emit=()=>{if(simulation)postMessage({type:'state',...simulation.snapshot(),physicsMs});};
onmessage=({data})=>{
  try{
    if(data.type==='create'){
      simulation?.dispose();simulation=new SoloSimulation({visualId:data.visualId});
      simulation.pause(!!data.paused);
      accumulator=0;last=performance.now();
      postMessage({type:'joined',role:'commander',code:'OFFLINE',token:'local-only',paused:simulation.paused,map:simulation.room.map,...simulation.room.identity(simulation.human)});emit();
    }else if(data.type==='input')simulation?.command(data.input);
    else if(data.type==='pause'){simulation?.pause(data.paused);accumulator=0;last=performance.now();emit();}
    else if(data.type==='reset'){simulation?.resetPlayer();emit();}
    else if(data.type==='restart'){simulation?.restart();accumulator=0;last=performance.now();emit();}
    else if(data.type==='leave'){simulation?.dispose();simulation=null;postMessage({type:'left'});}
    else throw new Error('Unknown local command');
  }catch(error){postMessage({type:'error',message:error.message});}
};
setInterval(()=>{
  const now=performance.now(),dt=Math.min(.133,(now-last)/1000);last=now;
  if(!simulation||simulation.paused)return;
  accumulator+=dt;let steps=0;const start=performance.now();
  while(accumulator>=1/30&&steps<4){simulation.step(1/30);accumulator-=1/30;steps++;}
  if(steps){physicsMs=(performance.now()-start)/steps;emit();}
},8);
postMessage({type:'ready'});
