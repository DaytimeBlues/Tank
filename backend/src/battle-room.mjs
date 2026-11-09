import RAPIER from '@dimforge/rapier3d-compat';
import { sessionToken } from './session-token.mjs';
import { BattlefieldDrive } from './battlefield-drive.mjs';
import { differentialStep } from './suspension.mjs';
import { freshBases, advanceCaptures } from './capture.mjs';
import { tankProfile } from '../public/tank-config.mjs';
import { VISUALS } from '../public/tank-visual.mjs';

const failure = (message, code) => Object.assign(new Error(message), { code });
const BLOCKED_SPAWN_GRACE = 2;
export const BATTLE_RULES = Object.freeze({ maxPlayers: 4, teamSize: 2, health: 3, respawnSeconds: 5, reservationSeconds: 30 });
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
      pitch: 0, roll: 0, groundHeight: 1, speed: 0, terrain: 'bridge', turret: 0, reload: 0, heat: 0, tankId: this.tankId };
    const positions = Object.values(this.seats).filter(other => other !== p && other.drive).map(other => other.drive.body.translation());
    const clear = anchor => positions.every(pos => Math.hypot(pos.x - anchor.x, pos.z - anchor.z) >= 6);
    let spawn = preferred;
    if (!clear(preferred)) {
      if (!anchors || this.time < p.respawnAt + BLOCKED_SPAWN_GRACE) return false;
      spawn = anchors.find(anchor => anchor !== preferred && clear(anchor));
      if (!spawn) return false;
    }
    p.drive = new BattlefieldDrive(this.tankId, this.arena); p.drive.reset(spawn, yaw);
    // Zero mass preserves chassis tuning while covering the actual visible turret.
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(.85, .4, 1).setTranslation(0, .75, 0).setMass(0), p.drive.body);
    p.health = BATTLE_RULES.health; p.input = {}; p.lastInput = this.time; p.respawnAt = null; p.shot = null;
    p.tank = { ...p.drive.pose(), turret: 0, reload: 0, heat: 0, tankId: this.tankId }; return true;
  }
  command(token, input) {
    const [, p] = this.seat(token); if (!p.connected) throw new Error('Disconnected session');
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid input');
    if (Object.keys(input).some(k => !['throttle', 'steer', 'aim', 'bearing', 'fire', 'spot'].includes(k))) throw new Error('Invalid input field');
    for (const [key, value] of Object.entries(input)) {
      if (['fire', 'spot'].includes(key)) { if (typeof value !== 'boolean') throw new Error('Invalid input'); }
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
    p.drive?.remove(); delete this.seats[id];
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
    const hit = p.drive.cast(p.tank.turret), profile = p.drive.profile;
    const victim = hit.bodyHandle === undefined ? null : Object.values(this.seats).find(other => other.drive?.body.handle === hit.bodyHandle);
    let damaged = null;
    if (victim && victim.team !== p.team && victim.health > 0) {
      victim.health = Math.max(0, victim.health - profile.damage); damaged = victim.id;
      if (!victim.health) this.kill(victim);
    }
    p.tank.reload = profile.reloadSeconds;
    p.shot = { id: ++this.shotId, ...hit.origin, endX: hit.origin.x + hit.direction.x * hit.distance,
      endY: hit.origin.y + hit.direction.y * hit.distance, endZ: hit.origin.z + hit.direction.z * hit.distance,
      time: this.time, hit: damaged, blocked: !!hit.category || !!victim };
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
    }
    for (const p of Object.values(this.seats)) if (p.drive) {
      Object.assign(p.tank, p.drive.pose());
      const delta = p.input.bearing === undefined ? (p.input.aim ?? 0) * .75 * dt
        : Math.max(-.75 * dt, Math.min(.75 * dt, Math.atan2(Math.sin(p.input.bearing * Math.PI - p.tank.yaw - p.tank.turret), Math.cos(p.input.bearing * Math.PI - p.tank.yaw - p.tank.turret))));
      if (!this.winner) p.tank.turret += delta;
    }
    for (const p of Object.values(this.seats)) if (p.input.fire) this.fire(p);
    if (!this.winner) {
      const occupants = Object.values(this.seats).filter(p => p.drive).map(p => ({ ...p.drive.occupant(p.connected), id: p.id, team: p.team, alive: p.health > 0 }));
      for (const event of advanceCaptures(this.bases, occupants, dt)) this.events.push({ ...event, id: ++this.eventId, time: this.time });
      if (this.events.length > 100) this.events.splice(0, this.events.length - 100);
      this.winner = ['blue', 'red'].find(team => this.bases.every(b => b.owner === team)) ?? null;
      if (this.winner) for (const p of Object.values(this.seats)) p.input = {};
    }
  }
  restart(token) {
    const [id, actor] = this.seat(token);
    if (!actor.connected || id !== this.hostId || !this.winner) throw new Error('Only the current host can restart a finished battle');
    for (const p of Object.values(this.seats)) { p.drive?.remove(); p.drive = null; p.health = 0; p.input = {}; p.respawnAt = this.time; }
    this.bases = freshBases(this.map.bases); this.events = []; this.winner = null;
  }
  snapshot(token) {
    const own = Object.values(this.seats).find(p => p.token === token);
    const players = Object.values(this.seats).map(p => ({ id: p.id, team: p.team, visualId: p.visualId, connected: p.connected,
      health: p.health, maxHealth: BATTLE_RULES.health, respawnSeconds: p.health ? 0 : Math.max(0, p.respawnAt - this.time),
      tank: { ...p.tank, ...(p.tank.quaternion ? { quaternion: { ...p.tank.quaternion } } : {}) }, shot: p.shot && { ...p.shot } }));
    const local = players.find(p => p.id === own?.id), scores = Object.fromEntries(['blue', 'red'].map(team => [team, this.bases.filter(b => b.owner === team).length]));
    return { mode: this.mode, time: this.time, players, playerId: own?.id ?? null, hostId: this.hostId, scores, winner: this.winner,
      rules: this.rules, tank: local?.tank ?? null, targets: [], shot: local?.shot ?? null, seats: {},
      capture: { bases: this.bases.map(b => ({ ...b })), events: this.events.map(e => ({ ...e })), owned: scores.blue }, won: !!this.winner };
  }
  dispose() { this.world.free(); }
}
