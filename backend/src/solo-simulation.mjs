import { BattleRoom, BATTLE_RULES } from './battle-room.mjs';
import { SOLO_MAP, SOLO_SPAWNS } from './solo-map.mjs';
import { SoloAI } from './solo-ai.mjs';
export const SOLO_RULES=Object.freeze({...BATTLE_RULES,maxPlayers:8,teamSize:4});
export class SoloSimulation {
  constructor({visualId='kestrel'}={}) {
    this.visualId=visualId;this.paused=false;
    this.room=new BattleRoom({configuration:{rules:SOLO_RULES,map:SOLO_MAP,spawns:SOLO_SPAWNS}});
    this.human=this.room.join('commander',{team:'blue',visualId});
    this.bots=[];
    for(let i=0;i<7;i++) {const token=this.room.join('commander',{team:i<3?'blue':'red',visualId:i<3?visualId:'bastion'});this.bots.push({token,id:this.room.identity(token).playerId});}
    this.ai=new SoloAI(this.room,this.bots);
  }
  command(input){this.room.command(this.human,this.paused?{}:input);}
  step(dt){if(!this.paused){this.ai.update();this.room.step(dt);}}
  pause(value){this.paused=!!value;for(const p of Object.values(this.room.seats))p.input={};}
  resetPlayer(){this.room.resetTrial(this.human);}
  restart(){this.room.dispose();const next=new SoloSimulation({visualId:this.visualId});Object.assign(this,next);}
  snapshot(){const s=this.room.snapshot(this.human);s.singlePlayer=true;s.paused=this.paused;s.players=s.players.map(p=>({...p,ai:p.id!==s.playerId}));s.ai=this.ai.diagnostics();return s;}
  dispose(){this.room.dispose();}
}
