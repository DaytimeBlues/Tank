import RAPIER from '@dimforge/rapier3d-compat';
import { ProjectilePool, PROJECTILE_RULES } from './projectiles.mjs';
import { sessionToken } from './session-token.mjs';
import { BattlefieldDrive } from './battlefield-drive.mjs';
import { differentialStep } from './suspension.mjs';
import { freshBases, advanceCaptures } from './capture.mjs';
import { tankProfile } from '../public/tank-config.mjs';
import { VISUALS } from '../public/tank-visual.mjs';

const failure = (message, code) => Object.assign(new Error(message), { code });
const BLOCKED_SPAWN_GRACE = 2;
// Game balance only: sixteen tags remove one pip; cannon health stays integral.
const SECONDARY = Object.freeze({ interval: .20, range: 53, tagsPerPip: 16 });
export const BATTLE_RULES = Object.freeze({ maxPlayers: 4, teamSize: 2, health: tankProfile().health, respawnSeconds: 5, reservationSeconds: 30 });
export function validateBattleOptions({ team = 'auto', visualId = 'kestrel', tankId = 'prototype' } = {}) {
  if (!['auto', 'blue', 'red'].includes(team)) throw new Error('Unknown team');
  if (!VISUALS.some(v=>v.id===visualId)) throw new Error('Unknown tank visual');
  tankProfile(tankId); return { team, visualId, tankId };
}

export class BattleRoom {
  constructor({ tankId = 'prototype', configuration = null } = {}) {
    this.rules = configuration?.rules ?? BATTLE_RULES;
    this.spawnPoints = configuration?.spawns;
    tankProfile(tankId); this.tankId = tankId; this.mode = 'battle'; this.time = 0;
    this.arena = new BattlefieldDrive(tankId, null, configuration?.map); this.arena.remove(); this.world = this.arena.world;
    for (const handle of this.arena.targetColliders.keys()) this.world.removeCollider(this.world.getCollider(handle), true);
    this.arena.targets.length = 0; this.arena.targetColliders.clear();
    this.map = { ...this.arena.map, mode: 'battle' }; this.seats = {}; this.nextPlayer = 0;
    this.projectilePool = new ProjectilePool();
    this.bases = freshBases(this.map.bases); this.events = []; this.eventId = 0; this.shotId = 0; this.winner = null;
  }
  seat(token) {
    const entry = Object.entries(this.seats).find(([, p]) => p.token === token);
    if (!entry) throw failure('Invalid session', 'SESSION_INVALID'); return entry;
  }
  identity(token) { const [id, p] = this.seat(token); return { playerId: id, team: p.team, visualId: p.visualId }; }
  battleStarted() { return true; }
  openLane(team) {
    const occupied = new Set(Object.values(this.seats).filter(p => p.team === team).map(p => p.lane));
    for (let lane = 0; lane < this.rules.teamSize; lane++) if (!occupied.has(lane)) return lane;
  }
  join(role, options = {}) {
    if (role !== 'commander') throw new Error('Unknown role');
    const validated = validateBattleOptions(options), players = Object.values(this.seats);
    if (validated.tankId !== this.tankId) throw new Error('Tank configuration mismatch');
    if (players.length >= this.rules.maxPlayers) throw new Error('Match full');
    const count = team => players.filter(p => p.team === team).length;
    const team = validated.team === 'auto' ? (count('blue') <= count('red') ? 'blue' : 'red') : validated.team;
    const lane = this.openLane(team);
    if (lane === undefined) throw new Error('Team full');
    const id = 'p' + ++this.nextPlayer, token = sessionToken();
    const p = { id, token, team, lane, visualId: validated.visualId, connected: true, input: {}, lastInput: this.time, until: Infinity,
      health: 0, respawnAt: this.time, tank: {}, drive: null, shot: null };
    this.seats[id] = p; this.hostId ??= id; this.spawn(p); return token;
  }
  spawn(p) {
    const anchors = this.spawnPoints?.[p.team];
    const preferred = anchors?.[p.lane] ?? { x: p.team === 'blue' ? -24 : 24, y: 2.5, z: p.lane === 0 ? -4 : 4 };
    const yaw = p.team === 'blue' ? Math.PI / 2 : -Math.PI / 2;
    if (!p.tank.quaternion) p.tank = { ...preferred, quaternion: { x: 0, y: Math.sin(yaw / 2), z: 0, w: Math.cos(yaw / 2) }, yaw,
      pitch: 0, roll: 0, groundHeight: 1, speed: 0, terrain: 'bridge', turret: 0, gunPitch: 0, reload: 0, heat: 0, tankId: this.tankId };
    const positions = Object.values(this.seats).filter(other => other !== p && other.drive).map(other => other.drive.body.translation());
    const clear = anchor => positions.every(pos => Math.hypot(pos.x - anchor.x, pos.z - anchor.z) >= 6);
    let spawn = preferred;
    if (!clear(preferred)) {
      if (!anchors || this.time < p.respawnAt + BLOCKED_SPAWN_GRACE) return false;
      spawn = anchors.find(anchor => anchor !== preferred && clear(anchor));
      if (!spawn) return false;
    }
    p.drive = new BattlefieldDrive(this.tankId, this.arena, undefined, p.visualId); p.drive.reset(spawn, yaw);
    // Zero mass preserves chassis tuning while covering the actual visible turret.
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(.85, .4, 1).setTranslation(0, .75, 0).setMass(0), p.drive.body);
    p.health = tankProfile(this.tankId).health; p.input = {}; p.lastInput = this.time; p.respawnAt = null; p.shot = null;
    p.tags = 0; p.nextPulse = this.time; p.pulse = null;
    p.tank = { ...p.drive.pose(), turret: 0, gunPitch: 0, reload: 0, heat: 0, tankId: this.tankId }; return true;
  }
  command(token, input) {
    const [, p] = this.seat(token); if (!p.connected) throw new Error('Disconnected session');
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid input');
    if (Object.keys(input).some(k => !['throttle', 'steer', 'aim', 'elevate', 'bearing', 'fire', 'secondary', 'spot'].includes(k))) throw new Error('Invalid input field');
    for (const [key, value] of Object.entries(input)) {
      if (['fire', 'secondary', 'spot'].includes(key)) { if (typeof value !== 'boolean') throw new Error('Invalid input'); }
      else if (!Number.isFinite(value) || Math.abs(value) > 1) throw new Error('Invalid input');
    }
    if (input.spot) throw new Error('Spotting unavailable in player battle');
    p.input = p.health > 0 && !this.winner && this.battleStarted() ? { ...input } : {}; p.lastInput = this.time;
  }
  disconnect(token) { const [, p] = this.seat(token); p.connected = false; p.input = {}; p.until = this.time + BATTLE_RULES.reservationSeconds; }
  reconnect(token) {
    const [, p] = this.seat(token);
    if (p.connected) throw failure('Session unavailable: tank already connected', 'SESSION_ACTIVE');
    if (p.until <= this.time) throw failure('Session unavailable: reservation expired', 'SESSION_EXPIRED');
    p.connected = true; p.input = {}; p.lastInput = this.time; p.until = Infinity;
    this.hostId ??= p.id;
  }
  removeSeat(id, p) {
    p.drive?.remove(); this.projectilePool.removeOwner(id); delete this.seats[id];
    if (this.hostId === id) this.hostId = Object.values(this.seats).find(other => other.connected)?.id;
  }
  leave(token) { const [id, p] = this.seat(token); this.removeSeat(id, p); }
  kill(p) {
    if (!p.drive) return;
    p.health = 0; p.input = {}; p.respawnAt = this.time + BATTLE_RULES.respawnSeconds;
    p.drive.remove(); p.drive = null; p.tank.speed = 0;
  }
  resetTrial(token) { const [, p] = this.seat(token); if (!p.connected) throw new Error('Disconnected session'); if (this.winner) throw new Error('Match complete'); if (!this.battleStarted()) throw new Error('Battle has not started'); this.kill(p); }
  fire(p) {
    if (!p.connected || !p.drive || !p.health || p.tank.reload > 0 || this.winner || !this.battleStarted()) return;
    if (this.projectilePool.active.length >= PROJECTILE_RULES.cap) return;
    const probe = p.drive.cast(p.tank.turret, undefined, p.tank.gunPitch??0), profile = p.drive.profile;
    const id = ++this.shotId, direction = probe.direction;
    const shell = { id, ownerId:p.id, team:p.team, damage:profile.damage, bodyHandle:p.drive.body.handle,
      ...probe.origin, dx:direction.x, dy:direction.y, dz:direction.z, time:this.time };
    p.tank.reload = profile.reloadSeconds;
    p.shot = { id, ...probe.origin, endX:probe.origin.x+direction.x*PROJECTILE_RULES.range,
      endY:probe.origin.y+direction.y*PROJECTILE_RULES.range,endZ:probe.origin.z+direction.z*PROJECTILE_RULES.range,
      time:this.time,hit:null,blocked:false,projectile:true };
    // Retain physical muzzle/mount obstruction guard; never tunnel out of cover.
    if(probe.distance <= .0001 && probe.category) { Object.assign(p.shot,{blocked:true,endX:probe.origin.x,endY:probe.origin.y,endZ:probe.origin.z});this.projectilePool.impact(shell,probe.origin,this.time,{blocked:true}); }
    else this.projectilePool.launch(shell);
  }
  pulse(p) {
    if (!p.connected || !p.drive || !p.health || this.winner || !this.battleStarted() || this.time + 1e-9 < p.nextPulse) return;
    p.nextPulse = this.time + SECONDARY.interval;
    const probe = p.drive.cast(p.tank.turret, SECONDARY.range, p.tank.gunPitch ?? 0, true);
    const victim = probe.bodyHandle === undefined ? null : Object.values(this.seats).find(other => other.drive?.body.handle === probe.bodyHandle);
    const tagged = !!victim && victim.team !== p.team && victim.health > 0;
    if (tagged && ++victim.tags === SECONDARY.tagsPerPip) {
      victim.tags = 0;
      if (--victim.health === 0) this.kill(victim);
    }
    const {origin:o, direction:d, distance:n} = probe;
    p.pulse = {time:this.time, x:o.x, y:o.y, z:o.z, endX:o.x+d.x*n, endY:o.y+d.y*n, endZ:o.z+d.z*n, tag:tagged};
  }
  sweepProjectile(p,distance) {
    const owner=this.seats[p.ownerId];
    const excluded=owner?.drive?.body.handle===p.bodyHandle?owner.drive.body:undefined;
    const ray=new RAPIER.Ray({x:p.x,y:p.y,z:p.z},{x:p.dx,y:p.dy,z:p.dz});
    const hit=this.world.castRay(ray,distance,true,undefined,undefined,undefined,excluded,c=>!this.arena.waterBlockers.has(c.handle));
    if(!hit)return null;
    const body=hit.collider.parent();
    const victim=body?Object.values(this.seats).find(other=>other.drive?.body.handle===body.handle):null;
    let damaged=null,knockout=false;
    if(victim && victim.team!==p.team && victim.health>0){
      victim.health=Math.max(0,victim.health-p.damage);damaged=victim.id;
      if(!victim.health){this.kill(victim);knockout=true;}
    }
    if(owner?.shot?.id===p.id) Object.assign(owner.shot,{hit:damaged,blocked:true,endX:p.x+p.dx*hit.timeOfImpact,endY:p.y+p.dy*hit.timeOfImpact,endZ:p.z+p.dz*hit.timeOfImpact});
    return {distance:hit.timeOfImpact,hit:damaged,blocked:true,...(knockout?{knockout:true}:{})};
  }

  step(dt) {
    if (!Number.isFinite(dt) || dt <= 0 || dt > .1) throw new Error('Invalid timestep');
    this.time += dt;
    const started = this.battleStarted();
    for (const [id, p] of Object.entries(this.seats)) {
      if (!p.connected && p.until <= this.time) { this.removeSeat(id, p); continue; }
      if (!p.connected || this.time - p.lastInput > .5) p.input = {};
      if (!started) continue;
      if (!p.health && p.connected && p.respawnAt <= this.time && !this.winner) this.spawn(p);
      p.tank.reload = Math.max(0, (p.tank.reload ?? 0) - dt);
    }
    if (!started) return;
    const n = Math.ceil(dt / (1 / 120));
    for (let i = 0; i < n; i++) {
      for (const p of Object.values(this.seats)) if (p.drive) {
        p.drive.stage = this.winner ? 'complete' : 'active';
        differentialStep(p.drive, dt / n, p.input.throttle ?? 0, p.input.steer ?? 0, .05, false);
      }
      this.world.timestep = dt / n; this.world.step();
      if(!this.winner)this.projectilePool.step(dt/n,this.time-dt+(i+1)*dt/n,(p,d)=>this.sweepProjectile(p,d));
    }
    for (const p of Object.values(this.seats)) if (p.drive) {
      Object.assign(p.tank, p.drive.pose());
      const turretRate = p.drive.profile.turretRadiansPerSecond;
      const delta = p.input.bearing === undefined ? (p.input.aim ?? 0) * turretRate * dt
        : Math.max(-turretRate * dt, Math.min(turretRate * dt, Math.atan2(Math.sin(p.input.bearing * Math.PI - p.tank.yaw - p.tank.turret), Math.cos(p.input.bearing * Math.PI - p.tank.yaw - p.tank.turret))));
      if (!this.winner) {
        p.tank.turret += delta;
        p.tank.gunPitch = Math.max(-Math.PI/18,Math.min(Math.PI/6,(p.tank.gunPitch??0)+(p.input.elevate??0)*Math.PI/6*dt));
      }
    }
    for (const p of Object.values(this.seats)) if (p.input.fire) this.fire(p);
    for (const p of Object.values(this.seats)) if (p.input.secondary) this.pulse(p);
    if (!this.winner) {
      const occupants = Object.values(this.seats).filter(p => p.drive).map(p => ({ ...p.drive.occupant(p.connected), id: p.id, team: p.team, alive: p.health > 0 }));
      for (const event of advanceCaptures(this.bases, occupants, dt)) this.events.push({ ...event, id: ++this.eventId, time: this.time });
      if (this.events.length > 100) this.events.splice(0, this.events.length - 100);
      this.winner = this.practice ? null : ['blue', 'red'].find(team => this.bases.every(b => b.owner === team)) ?? null;
      if (this.winner) { this.projectilePool.clear(); for (const p of Object.values(this.seats)) p.input = {}; }
    }
  }
  restart(token) {
    const [id, actor] = this.seat(token);
    if (!actor.connected || id !== this.hostId || !this.winner) throw new Error('Only the current host can restart a finished battle');
    for (const p of Object.values(this.seats)) { p.drive?.remove(); p.drive = null; p.health = 0; p.input = {}; p.respawnAt = this.time; }
    this.projectilePool.clear();
    this.bases = freshBases(this.map.bases); this.events = []; this.winner = null;
  }
  snapshot(token) {
    const own = Object.values(this.seats).find(p => p.token === token);
    const players = Object.values(this.seats).map(p => ({ id: p.id, ...(p.displayName ? {displayName:p.displayName} : {}), team: p.team, visualId: p.visualId, connected: p.connected,
      ...(p.pulse && this.time - p.pulse.time < .25 && !this.winner && this.battleStarted() ? {pulse:{...p.pulse}} : {}),
      health: p.health, maxHealth: tankProfile(this.tankId).health, respawnSeconds: p.health ? 0 : Math.max(0, p.respawnAt - this.time),
      tank: { ...p.tank, ...(p.tank.quaternion ? { quaternion: { ...p.tank.quaternion } } : {}) }, shot: p.shot && { ...p.shot } }));
    const local = players.find(p => p.id === own?.id), scores = Object.fromEntries(['blue', 'red'].map(team => [team, this.bases.filter(b => b.owner === team).length]));
    return { ...this.projectilePool.snapshot(), secondaryProtocol: 1, mode: this.mode, time: this.time, players, playerId: own?.id ?? null, hostId: this.hostId, scores, winner: this.winner,
      rules: this.rules, tank: local?.tank ?? null, targets: [], shot: local?.shot ?? null, seats: {},
      capture: { bases: this.bases.map(b => ({ ...b })), events: this.events.map(e => ({ ...e })), owned: scores.blue }, won: !!this.winner };
  }
  dispose() { this.projectilePool.clear(); this.world.free(); }
}
