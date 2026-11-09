import RAPIER from '@dimforge/rapier3d-compat';
import { randomBytes } from 'node:crypto';
import { GradeDrive, GRADE_MAP } from './grade-drive.mjs';
import { muzzle, segment } from './terrain-query.mjs';
import { BattlefieldDrive } from './battlefield-drive.mjs';
import { BATTLEFIELD_MAP } from './battlefield-map.mjs';
import { freshBases, advanceCaptures } from './capture.mjs';

export const initPhysics = () => RAPIER.init();
export const MAP = { size: 80, mud: { x: -12, z: 10, w: 16, d: 22 }, walls: [
  { x: -40, z: 0, w: 2, d: 82 }, { x: 40, z: 0, w: 2, d: 82 },
  { x: 0, z: -40, w: 82, d: 2 }, { x: 0, z: 40, w: 82, d: 2 },
  { x: 10, z: 8, w: 5, d: 12 }, { x: -20, z: -12, w: 8, d: 5 }
] };

export class Room {
  constructor({ mode = 'range', tankId = 'prototype' } = {}) {
    if (!['range', 'grade-drive', 'battlefield'].includes(mode)) throw new Error('Unknown mode');
    this.mode = mode; this.map = mode === 'grade-drive' ? GRADE_MAP : MAP;
    if (mode === 'battlefield') {
      this.battle = new BattlefieldDrive(tankId); this.map = BATTLEFIELD_MAP; this.world = this.battle.world; this.body = this.battle.body;
    } else if (mode === 'grade-drive') {
      this.grade = new GradeDrive(); this.world = this.grade.world; this.body = this.grade.body;
    } else {
    this.world = new RAPIER.World({ x: 0, y: 0, z: 0 });
    this.body = this.world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(0, 1, -20).lockRotations().enabledTranslations(true, false, true));
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(1.85, 1, 2.25).setFriction(0), this.body);
    for (const wall of MAP.walls) this.world.createCollider(RAPIER.ColliderDesc.cuboid(wall.w / 2, 3, wall.d / 2).setTranslation(wall.x, 2, wall.z));
    }
    this.seats = {};
    this.time = 0;
    this.tank = { x: 0, z: -20, yaw: 0, turret: 0, heat: 0, reload: 0, speed: 0, terrain: 'grass' };
    this.targets = [{ id: 1, x: 0, z: 22, hp: 3 }, { id: 2, x: -24, z: 25, hp: 3 }, { id: 3, x: 26, z: 26, hp: 3 }];
    if (this.grade) { this.targets = []; Object.assign(this.tank, this.grade.pose()); }
    this.shot = null;
    this.shotId = 0;
    if (this.battle) { this.targets = this.battle.targets; Object.assign(this.tank, this.battle.pose(), { tankId: this.battle.profile.id }); this.bases = freshBases(this.map.bases); this.captureEvents = []; this.captureEventId = 0; }
    if (this.grade) this.clearance = { status: 'pending', reason: 'awaiting-physics-step' };
  }
  join(role) {
    if (!(this.battle ? ['commander'] : ['driver', 'gunner']).includes(role)) throw new Error('Unknown role');
    if (this.seats[role]) throw new Error('Seat occupied');
    const token = randomBytes(24).toString('hex');
    this.seats[role] = { token, connected: true, input: {}, lastInput: this.time, until: Infinity };
    return token;
  }
  seat(token) {
    const entry = Object.entries(this.seats).find(([, seat]) => seat.token === token);
    if (!entry) throw Object.assign(new Error('Invalid session'), { code: 'SESSION_INVALID' });
    return entry;
  }
  command(token, input) {
    const [role, seat] = this.seat(token);
    if (!seat.connected) throw new Error('Disconnected session');
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid input');
    const allowed = this.battle && role === 'commander' ? ['throttle', 'steer', 'aim', 'bearing', 'fire', 'spot'] : role === 'driver' ? ['throttle', 'steer'] : ['aim', 'bearing', 'fire', 'spot'];
    if (Object.keys(input).some(key => !allowed.includes(key))) throw new Error('Wrong role command');
    for (const [key, value] of Object.entries(input)) {
      if (['fire', 'spot'].includes(key)) { if (typeof value !== 'boolean') throw new Error('Invalid input'); }
      else if (!Number.isFinite(value) || Math.abs(value) > 1) throw new Error('Invalid input');
    }
    if (this.grade && Object.entries(input).some(([key, value]) => !['throttle', 'steer'].includes(key) && value))
      throw new Error('Weapons unavailable in slope drive');
    seat.input = { ...input };
    seat.lastInput = this.time;
  }
  disconnect(token) {
    const [, seat] = this.seat(token);
    seat.connected = false;
    seat.input = {};
    seat.until = this.time + 30;
  }
  leave(token) {
    const [role] = this.seat(token);
    delete this.seats[role];
  }
  reconnect(token) {
    const [, seat] = this.seat(token);
    if (seat.connected) throw Object.assign(new Error('Session unavailable: seat already connected'), { code: 'SESSION_ACTIVE' });
    if (seat.until <= this.time) throw Object.assign(new Error('Session unavailable: reservation expired'), { code: 'SESSION_EXPIRED' });
    seat.connected = true;
    seat.input = {};
    seat.lastInput = this.time;
    seat.until = Infinity;
  }
  step(dt) {
    if (!Number.isFinite(dt) || dt <= 0 || dt > 0.1) throw new Error('Invalid timestep');
    this.time += dt;
    for (const [role, seat] of Object.entries(this.seats)) {
      if (!seat.connected && seat.until <= this.time) delete this.seats[role];
      else if (this.time - seat.lastInput > 0.5) seat.input = {};
    }
    if (this.battle) {
      const gun = this.seats.commander?.input ?? {}, t = this.tank;
      t.reload = Math.max(0, t.reload - dt); t.heat = 0;
      this.battle.step(dt, (gun.throttle ?? 0), gun.steer ?? 0); Object.assign(t, this.battle.pose());
      if (gun.bearing !== undefined) { const delta = Math.atan2(Math.sin(gun.bearing * Math.PI - t.yaw - t.turret), Math.cos(gun.bearing * Math.PI - t.yaw - t.turret)); t.turret += Math.max(-.75 * dt, Math.min(.75 * dt, delta)); }
      else t.turret += (gun.aim ?? 0) * dt * .75;
      if (gun.fire && t.reload <= 0) this.fire();
      for (const event of advanceCaptures(this.bases, [this.battle.occupant(this.seats.commander?.connected), ...this.battle.garrisonOccupants()], dt)) this.captureEvents.push({ ...event, id: ++this.captureEventId, time: this.time });
      if (this.captureEvents.length > 100) this.captureEvents.splice(0, this.captureEvents.length - 100);
      if (this.bases.every(b => b.owner === 'blue')) this.battle.stage = 'complete';
      return;
    }
    const drive = this.seats.driver?.input ?? {};
    if (this.grade) {
      this.grade.step(dt, drive.throttle ?? 0, drive.steer ?? 0); Object.assign(this.tank, this.grade.pose());
      this.clearance = this.measureGradeClearance(); return;
    }
    const gun = this.seats.gunner?.input ?? {};
    const t = this.tank;
    const mud = MAP.mud;
    t.terrain = Math.abs(t.x - mud.x) < mud.w / 2 && Math.abs(t.z - mud.z) < mud.d / 2 ? 'mud' : 'grass';
    const throttle = drive.throttle ?? 0;
    t.heat = Math.max(0, Math.min(100, t.heat + (Math.abs(throttle) > 0 ? 5 * Math.abs(throttle) : -9) * dt));
    t.yaw += (drive.steer ?? 0) * dt * 0.8;
    this.body.setRotation({ x: 0, y: Math.sin(t.yaw / 2), z: 0, w: Math.cos(t.yaw / 2) }, true);
    if (gun.bearing !== undefined) {
      const delta = Math.atan2(Math.sin(gun.bearing * Math.PI - t.yaw - t.turret), Math.cos(gun.bearing * Math.PI - t.yaw - t.turret));
      t.turret += Math.max(-0.75 * dt, Math.min(0.75 * dt, delta));
    } else t.turret += (gun.aim ?? 0) * dt * 0.75;
    const desired = throttle * (t.terrain === 'mud' ? 4 : 9) * (t.heat > 80 ? 0.5 : 1);
    t.speed += Math.max(-8 * dt, Math.min(8 * dt, desired - t.speed));
    this.body.setLinvel({ x: Math.sin(t.yaw) * t.speed, y: 0, z: Math.cos(t.yaw) * t.speed }, true);
    this.world.timestep = dt;
    this.world.step();
    const p = this.body.translation();
    const travelled = ((p.x - t.x) * Math.sin(t.yaw) + (p.z - t.z) * Math.cos(t.yaw)) / dt;
    t.speed = Math.abs(travelled) < 0.01 ? 0 : travelled;
    t.x = p.x; t.z = p.z;
    t.reload = Math.max(0, t.reload - dt);
    if (gun.fire && t.reload <= 0) this.fire();
    if (gun.spot) for (const target of this.targets) {
      if (target.hp > 0 && Math.hypot(target.x - t.x, target.z - t.z) < 55) target.spottedUntil = this.time + 8;
    }
  }
  fire() {
    if (this.grade) return;
    const t = this.tank;
    if (this.battle) {
      if (t.reload > 0) return;
      const hit = this.battle.cast(t.turret); t.reload = this.battle.profile.reloadSeconds;
      if (hit.target) hit.target.hp = Math.max(0, hit.target.hp - this.battle.profile.damage);
      this.shot = { id: ++this.shotId, ...hit.origin, endX: hit.origin.x + hit.direction.x * hit.distance, endY: hit.origin.y + hit.direction.y * hit.distance, endZ: hit.origin.z + hit.direction.z * hit.distance, time: this.time, hit: hit.target?.id ?? null };
      return;
    }
    t.reload = 4;
    const angle = t.yaw + t.turret;
    const dx = Math.sin(angle), dz = Math.cos(angle);
    const ray = new RAPIER.Ray({ x: t.x, y: 1, z: t.z }, { x: dx, y: 0, z: dz });
    const hit = this.world.castRay(ray, 90, true, undefined, undefined, undefined, this.body);
    let distance = hit?.timeOfImpact ?? 90;
    let victim = null;
    for (const target of this.targets.filter(v => v.hp > 0)) {
      const x = target.x - t.x, z = target.z - t.z;
      const along = x * dx + z * dz, side = Math.abs(x * dz - z * dx);
      if (along > 0 && side < 2) {
        const near = along - Math.sqrt(4 - side * side);
        if (near < distance) { distance = near; victim = target; }
      }
    }
    if (victim) victim.hp--;
    this.shot = { id: ++this.shotId, x: t.x, z: t.z, endX: t.x + dx * distance, endZ: t.z + dz * distance, time: this.time, hit: victim?.id ?? null };
  }
  // Diagnostic only. Slope weapons and spotting remain unavailable.
  measureGradeClearance() {
    const m = muzzle(this.grade.pose(), 0);
    const base = { sampleTime: this.time, mapVersion: this.map.version, range: 10,
      kind: 'resting-muzzle', origin: m.origin };
    if (Math.abs(m.origin.x) > 40 || Math.abs(m.origin.z) > 40 || Math.abs(m.origin.y) > 90)
      return { ...base, status: 'unavailable', reason: 'outside-terrain-domain', blocked: null, endpoint: null, category: null, distance: null };
    const endpoint = { x: m.origin.x + 10 * m.direction.x,
      y: m.origin.y + 10 * m.direction.y, z: m.origin.z + 10 * m.direction.z };
    return { ...base, status: 'measured', endpoint, ...segment(this.grade, m.origin, endpoint) };
  }
  snapshot() {
    return { mode: this.mode, ...(this.battle ? { capture: { bases: this.bases.map(b => ({...b})), events: this.captureEvents.map(e => ({...e})), owned: this.bases.filter(b => b.owner === 'blue').length, tankId: this.battle.profile.id } } : {}), ...(this.grade ? { trial: { stage: this.grade.stage, clearance: structuredClone(this.clearance) } } : {}), time: this.time, tank: { ...this.tank }, seats: Object.fromEntries(Object.entries(this.seats).map(([role, s]) => [role, { connected: s.connected }])), targets: this.targets.map(t => ({ ...t })), shot: this.shot && { ...this.shot }, won: this.battle ? this.bases.every(b => b.owner === 'blue') : this.grade ? this.grade.stage === 'complete' : this.targets.every(t => t.hp === 0) };
  }
  resetTrial(token) {
    const [role, seat] = this.seat(token);
    if (!seat.connected) throw new Error('Disconnected session');
    if (this.battle && role === 'commander') { this.battle.reset(); this.body = this.battle.body; Object.assign(this.tank, this.battle.pose(), { turret: 0, reload: 0, heat: 0 }); for (const s of Object.values(this.seats)) s.input = {}; this.shot = null; return; }
    if (!this.grade || role !== 'driver') throw new Error('Only the slope driver can reset');
    this.grade.reset(); this.body = this.grade.body; Object.assign(this.tank, this.grade.pose());
    this.clearance = { status: 'pending', reason: 'awaiting-physics-step' };
    for (const occupant of Object.values(this.seats)) occupant.input = {};
  }
  restart(token) {
    if (this.battle) { const [role, seat] = this.seat(token); if (role !== 'commander' || !seat.connected) throw new Error('Only the commander can restart'); this.bases = freshBases(this.map.bases); this.captureEvents = []; this.captureEventId = 0; this.battle.restartTargets(); this.resetTrial(token); return; }
    if (this.grade) return this.resetTrial(token);
    const [, seat] = this.seat(token);
    if (!seat.connected) throw new Error('Disconnected session');
    if (!this.targets.every(t => t.hp === 0)) throw new Error('Complete the range before restarting');
    this.body.setTranslation({ x: 0, y: 1, z: -20 }, true);
    this.body.setRotation({ x: 0, y: 0, z: 0, w: 1 }, true);
    this.body.setLinvel({ x: 0, y: 0, z: 0 }, true);
    Object.assign(this.tank, { x: 0, z: -20, yaw: 0, turret: 0, heat: 0, reload: 0, speed: 0, terrain: 'grass' });
    for (const target of this.targets) { target.hp = 3; delete target.spottedUntil; }
    for (const occupant of Object.values(this.seats)) occupant.input = {};
    this.shot = null;
  }
  dispose() { this.world.free(); }
}
