import { BATTLE_SHOT_RANGE } from './battlefield-drive.mjs';

const clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
const angle=n=>Math.atan2(Math.sin(n),Math.cos(n));
const distance=(a,b)=>Math.hypot(a.x-b.x,a.z-b.z);
const point=(nodes,id)=>({id,x:nodes[id][0],z:nodes[id][1]});
const CONVOY_WAIT=15;
// A muzzle can extend ~4.1 m from its hull center and a hit can land ~3 m
// from the other hull center. This prefilter never authorizes a shot.
const MUZZLE_CHECK_REACH=BATTLE_SHOT_RANGE+8;
const lanePosition=(pose,other)=>{
  const sin=Math.sin(pose.yaw),cos=Math.cos(pose.yaw),dx=other.x-pose.x,dz=other.z-pose.z;
  return {ahead:dx*sin+dz*cos,lateral:Math.abs(dx*cos-dz*sin)};
};
const rearOccupied=(pose,others)=>others.some(q=>{
  const {ahead,lateral}=lanePosition(pose,q.tank);
  return ahead<0&&ahead>-8.5&&lateral<4.6;
});

// Road graph planning only. Physical movement, gun rays and capture stay in BattleRoom.
// A denied crossing removes every deck-dependent edge (the centre has two).
export function planRoute(map,pose,goal,denied=new Set()){
  const nodes={...map.routes.nodes},edges=map.routes.edges;
  if(!nodes[goal])return [];
  const crossing=(a,b)=>nodes[a][1]===nodes[b][1]&&nodes[a][0]*nodes[b][0]<=0&&nodes[a][0]!==nodes[b][0];
  const available=edges.filter(([a,b])=>!crossing(a,b)||!denied.has(nodes[a][1]));
  const deck=map.bridges.find(b=>Math.abs(pose.x-b.x)<=b.w/2&&Math.abs(pose.z-b.z)<b.d/2);
  const bank=Math.sign(pose.x);
  const candidates=Object.keys(nodes).filter(id=>nodes[id][0]*bank>0);
  let start=candidates.sort((a,b)=>distance(pose,point(nodes,a))-distance(pose,point(nodes,b)))[0];
  // Join the nearest usable road segment, rather than backtracking to a busy
  // endpoint. A hull already on a denied deck can only attach toward its
  // nearer bank (the entry bank at the midpoint), never through the closure.
  const retreat=deck&&denied.has(deck.z);
  const exitSide=bank||(Math.sin(pose.yaw??0)<0?1:-1);
  const joins=(deck?edges:available).filter(([a,b])=>deck
    ? crossing(a,b)&&nodes[a][1]===deck.z&&(!retreat||[a,b].some(id=>nodes[id][0]*exitSide>0))
    : nodes[a][0]*bank>0&&nodes[b][0]*bank>0).map(([a,b])=>{
    const [ax,az]=nodes[a],[bx,bz]=nodes[b],dx=bx-ax,dz=bz-az;
    const t=clamp(((pose.x-ax)*dx+(pose.z-az)*dz)/(dx*dx+dz*dz),0,1),x=ax+t*dx,z=az+t*dz;
    return {a,b,x,z,d:Math.hypot(pose.x-x,pose.z-z)};
  }).sort((a,b)=>a.d-b.d);
  if(joins[0]?.d<=20){
    const j=joins[0];start='@road';nodes[start]=[j.x,j.z];
    for(const id of [j.a,j.b])if(!retreat||nodes[id][0]*exitSide>0)available.push([start,id]);
  }
  if(!start)return [];
  const costs=new Map([[start,0]]),previous=new Map(),pending=new Set(Object.keys(nodes));
  while(pending.size){
    const id=[...pending].sort((a,b)=>(costs.get(a)??Infinity)-(costs.get(b)??Infinity))[0];
    if(!Number.isFinite(costs.get(id)))break;
    pending.delete(id);if(id===goal)break;
    for(const [a,b]of available){const next=a===id?b:b===id?a:null;if(!next||!pending.has(next))continue;
      const cost=costs.get(id)+distance(point(nodes,id),point(nodes,next));
      if(cost<(costs.get(next)??Infinity)){costs.set(next,cost);previous.set(next,id);}
    }
  }
  if(!costs.has(goal))return [];
  const result=[goal];while(result[0]!==start){const id=previous.get(result[0]);if(!id)return [];result.unshift(id);}
  return result.map(id=>point(nodes,id));
}

export class SoloAI {
  constructor(room,bots){this.room=room;this.bots=bots;this.nextDecision=0;for(const bot of bots)this.clear(bot);}
  clear(bot){Object.assign(bot,{goal:null,path:[],index:0,input:{},mode:'deploy',sample:null,stalled:0,queueSince:null,convoyRecovery:false,recoveryUntil:0,recoveries:0,denied:new Map()});}
  recover(bot,p){
    bot.mode='recover';
    const blocked=bot.convoyRecovery&&rearOccupied(p.tank,Object.values(this.room.seats).filter(q=>q!==p&&q.drive&&q.health));
    // Don't swing the hull either: a turn can sweep into the waiting tail.
    bot.input=blocked?{}:{throttle:this.room.time<bot.recoveryUntil-1?-.7:0,steer:bot.recoveries%2?1:-1};
  }
  update(){
    const room=this.room;
    if(room.time+1e-6>=this.nextDecision){this.nextDecision=room.time+.1;for(const bot of this.bots)this.decide(bot);}
    for(const bot of this.bots)room.command(bot.token,bot.input);
  }
  decide(bot){
    const room=this.room,p=room.seats[bot.id];
    if(!p?.drive||!p.health||room.winner){this.clear(bot);bot.mode=room.winner?'finished':'respawning';return;}
    const pose=p.tank,time=room.time;
    for(const [z,until]of bot.denied)if(until<=time)bot.denied.delete(z);
    if(bot.recoveryUntil>time){this.recover(bot,p);return;}
    const live=Object.values(room.seats).filter(q=>q!==p&&q.drive&&q.health);
    // Back out of a bridge lane only for an aligned ally physically reversing
    // toward us. Keep the route and leave the reverse lane clear for others.
    const inApproach=(tank,b)=>Math.abs(tank.x-b.x)<b.w/2+10&&Math.abs(tank.z-b.z)<b.d/2-2;
    const bridge=Math.abs(Math.cos(pose.yaw))<.35&&room.map.bridges.find(b=>inApproach(pose,b));
    if(bridge&&live.some(q=>{
      if(q.team!==p.team||q.tank.speed>=-.25||!inApproach(q.tank,bridge)||Math.abs(angle(q.tank.yaw-pose.yaw))>.6)return false;
      const {ahead,lateral}=lanePosition(pose,q.tank);
      return ahead>0&&ahead<10.5&&lateral<3.8;
    })){
      const heading=Math.sign(Math.sin(pose.yaw))*Math.PI/2;
      bot.input=rearOccupied(pose,live)?{}:{throttle:-1,steer:clamp(2*angle(heading-pose.yaw),-1,1)};
      bot.mode='yield';bot.sample=null;bot.stalled=0;bot.queueSince=null;return;
    }
    const base=room.bases.find(b=>b.id===bot.goal);
    if(!base||base.owner===p.team||!bot.path.length){
      const options=room.bases.filter(b=>b.owner!==p.team).map(b=>{
        const path=planRoute(room.map,pose,'b'+b.id,new Set(bot.denied.keys()));
        const length=path.reduce((sum,n,i)=>sum+distance(i?path[i-1]:pose,n),0);
        const assigned=this.bots.filter(q=>q!==bot&&q.goal===b.id&&room.seats[q.id]?.team===p.team).length;
        return {base:b,path,cost:path.length?length+assigned*95:Infinity};
      }).sort((a,b)=>a.cost-b.cost);
      const chosen=options.find(o=>Number.isFinite(o.cost));
      if(!chosen){bot.mode='hold';bot.input={};return;}
      bot.goal=chosen.base.id;bot.path=chosen.path;bot.index=0;bot.sample=null;bot.stalled=0;
    }
    while(bot.index<bot.path.length-1&&distance(pose,bot.path[bot.index])<4)bot.index++;
    const target=bot.path[bot.index],last=bot.index===bot.path.length-1;
    const arrived=last&&distance(pose,target)<3.5;
    const desired=Math.atan2(target.x-pose.x,target.z-pose.z),error=angle(desired-pose.yaw);
    let throttle=arrived?0:Math.abs(error)>1.05?0:Math.abs(error)>.35?.55:1;
    let steer=arrived?0:Math.abs(error)<.045?0:clamp(error*1.8,-1,1);
    bot.mode=arrived?'capture':'travel';
    const nearby=live.filter(q=>distance(pose,q.tank)<88);
    const enemies=nearby.filter(q=>q.team!==p.team).sort((a,b)=>distance(pose,a.tank)-distance(pose,b.tank));
    const enemy=enemies[0];
    const bearingTo=q=>Math.atan2(q.tank.x-pose.x,q.tank.z-pose.z);
    let bearing=desired/Math.PI,fire=false;
    if(enemy)bearing=bearingTo(enemy)/Math.PI;
    if(enemy||live.some(q=>q.team!==p.team&&distance(pose,q.tank)<=MUZZLE_CHECK_REACH)){
      const hit=p.drive.cast(pose.turret);
      const victim=live.find(q=>q.drive.body.handle===hit.bodyHandle);
      fire=!!victim&&victim.team!==p.team;
      // Don't turn toward another hull (or a route waypoint) between the
      // verified hit and BattleRoom's authoritative fire step.
      if(fire&&victim!==enemy)bearing=angle(pose.yaw+pose.turret)/Math.PI;
      if(fire&&distance(pose,victim.tank)<65){throttle=0;steer=0;bot.mode='engage';}
    }
    // When the intended line is masked by an ally, look for a physically
    // clear alternate bearing. This selects aim only; firing still requires
    // the current muzzle (above) and the room's authoritative recast.
    if(!fire&&enemies.length>1&&nearby.some(q=>q.team===p.team)){
      const intended=p.drive.cast(angle(bearingTo(enemy)-pose.yaw));
      if(live.some(q=>q.team===p.team&&q.drive.body.handle===intended.bodyHandle)){
        for(const alternate of enemies.slice(1)){
          const heading=bearingTo(alternate);
          if(p.drive.cast(angle(heading-pose.yaw)).bodyHandle===alternate.drive.body.handle){
            bearing=heading/Math.PI;break;
          }
        }
      }
    }
    // Keep a physical gap behind a friendly tank moving or facing down the
    // same lane. Seat IDs say nothing about which hull is ahead.
    let convoyGap=Infinity;
    if(throttle>0&&Math.abs(error)<.65){
      for(const q of nearby){
        if(q.team!==p.team||Math.abs(angle(q.tank.yaw-pose.yaw))>.6)continue;
        const {ahead,lateral}=lanePosition(pose,q.tank);
        if(ahead>0&&lateral<3.8)convoyGap=Math.min(convoyGap,ahead);
      }
    }
    const queued=convoyGap<7.5;
    if(queued){throttle=0;bot.mode='yield';bot.queueSince??=time;}
    else {
      bot.queueSince=null;
      if(convoyGap<10.5)throttle=Math.min(throttle,.45);
    }
    // The existing local yield still handles non-convoy meetings.
    const obstruction=nearby.find(q=>distance(pose,q.tank)<7&&Math.abs(angle(Math.atan2(q.tank.x-pose.x,q.tank.z-pose.z)-pose.yaw))<.65);
    if(obstruction&&obstruction.id<p.id&&throttle>0){throttle=0;bot.mode='yield';}
    if(!bot.sample)bot.sample={x:pose.x,z:pose.z,yaw:pose.yaw,time};
    if(time-bot.sample.time>=1){
      const intentionalWait=queued&&time-bot.queueSince<CONVOY_WAIT;
      const attempted=!intentionalWait&&(throttle>0||bot.mode==='yield'||Math.abs(steer)>.2);
      const progress=distance(pose,bot.sample)>.35||Math.abs(angle(pose.yaw-bot.sample.yaw))>.12;
      bot.stalled=attempted&&!progress?bot.stalled+time-bot.sample.time:0;
      bot.sample={x:pose.x,z:pose.z,yaw:pose.yaw,time};
      if(bot.stalled>=3){
        bot.convoyRecovery=queued;
        bot.recoveries++;bot.recoveryUntil=time+2.5;bot.stalled=0;bot.queueSince=null;bot.path=[];
        if(bot.recoveries%3===0&&Math.abs(pose.x)<75){const z=[-80,0,80].sort((a,b)=>Math.abs(a-pose.z)-Math.abs(b-pose.z))[0];bot.denied.set(z,time+35);}
        this.recover(bot,p);return;
      }
    }
    bot.input={throttle,steer,bearing,fire};
  }
  diagnostics(){return this.bots.map(b=>({id:b.id,goal:b.goal,mode:b.mode,waypoint:b.path[b.index]?.id??null,recoveries:b.recoveries}));}
}
