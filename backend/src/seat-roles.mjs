// Opt-in travel / reload trial; common durability, damage and suspension.
import {createOnlineBattle} from './online-battle.mjs';
import {tankProfile} from '../public/tank-config.mjs';
const ROLE_IDS=Object.freeze(['prototype','flanker','generalist','anchor']);
// Only this opt-in room creates these profiles. Normal rooms keep the
// untouched prototype. Rules, physics and appearance never come from input.
const standard=tankProfile('prototype');
const overrides=Object.freeze({prototype:null,generalist:null,
 flanker:{forwardMps:3.6,reloadSeconds:5},anchor:{forwardMps:2.4,reloadSeconds:3}});
export const EXPERIMENTAL_ROLES=Object.freeze(ROLE_IDS.map(id=>Object.freeze({id,
 profile:overrides[id]?Object.freeze({...standard,...overrides[id]}):standard})));
export const ROLE_CATALOG=Object.freeze(EXPERIMENTAL_ROLES.map(({id,profile})=>{
 const {forwardMps,health,damage,reloadSeconds}=profile;
 return Object.freeze({id,forwardMps,health,damage,reloadSeconds});
}));
const roleFor=id=>{const role=EXPERIMENTAL_ROLES.find(r=>r.id===id);if(!role)throw new Error('Unknown role identity');return role;};
function exactObject(value,keys){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!keys.includes(k)))throw new Error('Invalid role request');}
export function validateSeatRoleAdmission(options={}){exactObject(options,['team','visualId','tankId','roleId']);return roleFor(Object.hasOwn(options,'roleId')?options.roleId:'prototype');}
export function createSeatRolePrototype(){
 const room=createOnlineBattle({format:'4v4'}),accepted=new Map();
 const base={restart:room.restart.bind(room),join:room.join.bind(room),spawn:room.spawn.bind(room),snapshot:room.snapshot.bind(room),identity:room.identity.bind(room),removeSeat:room.removeSeat.bind(room)};
 const apply=p=>{const role=roleFor(accepted.get(p.id)??'prototype');if(p.drive){p.drive.profile=role.profile;p.drive.driveSpeed=role.profile.forwardMps;}return role;};
 // The mapping is server-owned and stays outside command/input payloads.
 room.spawn=p=>{const spawned=base.spawn(p);if(spawned)apply(p);return spawned;};
 room.join=(seat,options={})=>{
  if(!room.waiting)throw new Error('Role admission is staging only');
  exactObject(options,['team','visualId','tankId','roleId']);
  const role=roleFor(Object.hasOwn(options,'roleId')?options.roleId:'prototype');
  const {roleId,...legacy}=options;const token=base.join(seat,legacy),[,p]=room.seat(token);
  accepted.set(p.id,role.id);apply(p);return token;
 };
 room.selectRole=(token,request)=>{
  const [,p]=room.seat(token);
  if(!room.waiting||!p.connected)throw new Error('Role selection is staging only for connected seat');
  exactObject(request,['roleId']);const role=roleFor(request.roleId);
  if(accepted.get(p.id)===role.id)return;
  accepted.set(p.id,role.id);p.ready=false;p.input={};apply(p);
 };
 room.identity=token=>{const identity=base.identity(token);return {...identity,roleProtocol:1,roleId:accepted.get(identity.playerId)??'prototype'};};
 room.snapshot=token=>{const state=base.snapshot(token);return {...state,roleProtocol:1,roleCatalog:ROLE_CATALOG,players:state.players.map(p=>({...p,roleId:accepted.get(p.id)??'prototype'}))};};
 // The old body and shot are gone on rematch. No cooldown belongs to the new staging seat.
 room.restart=token=>{base.restart(token);for(const p of Object.values(room.seats))p.tank.reload=0;};
 room.removeSeat=(id,p)=>{base.removeSeat(id,p);accepted.delete(id);};
 return room;
}
