import RAPIER from '@dimforge/rapier3d-compat';
import { BattleRoom, BATTLE_RULES } from './battle-room.mjs';
import { ROADSIDE_MAP } from './roadside-map.mjs';
import { quarryMap, quarrySpawns } from '../quarry/map.mjs';
import { SOLO_SPAWNS } from './solo-map.mjs';

export const ONLINE_RULES = Object.freeze({ ...BATTLE_RULES, maxPlayers: 8, teamSize: 4 });
export function battleFormat(value = '2v2') {
  if (!['2v2', '4v4'].includes(value)) throw new Error('Unknown battle format');
  return value;
}
class OnlineFourBattle extends BattleRoom {
  waiting = true;
  battleStarted() { return !this.waiting; }
  setReady(token, ready) {
    const [, player] = this.seat(token);
    if (!this.waiting || !player.connected) throw new Error('Readiness is only available in the ready room');
    if (typeof ready !== 'boolean') throw new Error('Invalid readiness');
    player.ready = ready;
  }
  teamSwitchTarget(player) {
    if (!this.waiting || !player?.connected) return null;
    const other = player.team === 'blue' ? 'red' : 'blue';
    const seats = Object.values(this.seats);
    const ownCount = seats.filter(p => p.team === player.team).length;
    // A reservation still occupies its original team and lane until it expires.
    return ownCount * 2 - seats.length >= 2 && this.openLane(other) !== undefined ? other : null;
  }
  switchTeam(token, team) {
    const [, player] = this.seat(token);
    if (!this.waiting || !player.connected) throw new Error('You can switch teams only in the ready room');
    if (!['blue', 'red'].includes(team)) throw new Error('Unknown team');
    if (player.team === team) return;
    if (team !== this.teamSwitchTarget(player)) throw new Error('Teams changed. A switch must reduce the imbalance.');
    const lane = this.openLane(team);
    player.drive?.remove();
    Object.assign(player, { team, lane, ready: false, input: {}, health: 0, respawnAt: this.time, tank: {}, drive: null, shot: null });
    this.spawn(player);
  }
  startBlock() {
    const players = Object.values(this.seats);
    const blue = players.filter(p => p.team === 'blue').length;
    if (!blue || blue * 2 !== players.length) return 'Both teams need the same number of players.';
    if (players.some(p => !p.connected)) return 'Waiting for a reserved seat to rejoin or expire.';
    if (players.some(p => !p.ready)) return 'Every player must mark Ready.';
    return null;
  }
  start(token) {
    const [id, player] = this.seat(token);
    if (!this.waiting || !player.connected || id !== this.hostId) throw new Error('Only the current host can start a waiting battle');
    const block = this.startBlock();
    if (block) throw new Error(block);
    this.waiting = false;
  }
  disconnect(token) {
    const [, player] = this.seat(token);
    player.ready = false;
    super.disconnect(token);
  }
  restart(token) {
    super.restart(token);
    this.waiting = true;
    for (const player of Object.values(this.seats)) { player.ready = false; player.shot = null; }
  }
  snapshot(token) {
    const state = super.snapshot(token);
    if (!this.waiting) return { ...state, practice: !!this.practice, staging: { waiting: false } };
    const block = this.startBlock();
    return { ...state, staging: { waiting: true, block, canStart: !block && state.playerId === this.hostId,
      switchTo: this.teamSwitchTarget(this.seats[state.playerId]) },
      players: state.players.map(p => ({ ...p, ready: !!this.seats[p.id].ready })) };
  }
}
// Ordinary multiplayer only. Use the existing per-hull travel target, not world time.
const ROOM_SPEED = new Map([['normal', 1], ['3x', 3], ['5x', 5]]);
class SpeedReadyRoom extends OnlineFourBattle {
  speedMode = 'normal';
  edgeGuards = [];
  setRoomSpeed(token, mode) {
    const [id, player] = this.seat(token);
    if (!this.waiting || !player.connected || id !== this.hostId) throw new Error('Only the current host can change speed in the ready room');
    if (!ROOM_SPEED.has(mode)) throw new Error('Choose Normal, 3x or 5x');
    if (mode === this.speedMode) return;
    this.updateEdgeGuards(mode !== 'normal');
    this.speedMode = mode;
    for (const p of Object.values(this.seats)) {
      p.ready = false; // Everyone confirms the changed rules before the host starts.
      if (p.drive) this.applySpeed(p);
    }
  }
  updateEdgeGuards(fast) {
    // Elevated terrain can crest the old outer walls at arcade travel speeds.
    // Extend only the existing footprints. These are not wheel supports or shot obstructions.
    if (!fast) {
      for (const c of this.edgeGuards) {
        this.arena.waterBlockers.delete(c.handle);
        this.world.removeCollider(c, true);
      }
      this.edgeGuards = [];
    } else if (!this.edgeGuards.length) {
      const bottom = 8;
      let top = bottom;
      for (const chunk of this.map.chunks)
        for (let i = 1; i < chunk.vertices.length; i += 3) top = Math.max(top, chunk.vertices[i] + 10);
      for (const w of this.map.walls) {
        const c = this.world.createCollider(RAPIER.ColliderDesc.cuboid(w.w/2, (top-bottom)/2, w.d/2)
          .setTranslation(w.x, (top+bottom)/2, w.z));
        this.edgeGuards.push(c);
        this.arena.waterBlockers.add(c.handle);
      }
    }
  }
  applySpeed(p) { p.drive.driveSpeed = p.drive.profile.forwardMps * ROOM_SPEED.get(this.speedMode); }
  spawn(p) {
    const ok = super.spawn(p);
    if (ok && this.speedMode !== 'normal') this.applySpeed(p);
    return ok;
  }
  snapshot(token) { return { ...super.snapshot(token), roomSpeedMode: this.speedMode }; }
}
// One human, no bots, no model-specific stats. The server chooses a fixed travel target.
export const BRISK_PRACTICE_ID = 'brisk-v1';
const BRISK_MPS = 3.3;
class BriskPractice extends OnlineFourBattle {
  get practicePreset() { return BRISK_PRACTICE_ID; }
  spawn(player) {
    const ok = super.spawn(player);
    if (ok) player.drive.driveSpeed = BRISK_MPS;
    return ok;
  }
  identity(token) { return { ...super.identity(token), practicePreset: BRISK_PRACTICE_ID }; }
  snapshot(token) { return { ...super.snapshot(token), practicePreset: BRISK_PRACTICE_ID, driveTargetMps: BRISK_MPS }; }
}
export function createOnlineBattle({ tankId = 'prototype', format, practice = false, practicePreset, roomSpeedControl = false, mapId = 'west-farm' } = {}) {
  if (practicePreset !== undefined && (practicePreset !== BRISK_PRACTICE_ID || practice !== true || format !== '4v4')) throw new Error('Invalid practice preset');
  if (typeof practice !== 'boolean' || practice && format !== '4v4') throw new Error('Invalid practice mode');
  format = battleFormat(format);
  if (!['west-farm', 'redstone-quarry'].includes(mapId)) throw new Error('Unknown arena');
  if (mapId === 'redstone-quarry' && (practice || format !== '4v4')) throw new Error('Redstone Quarry requires a two-player room.');
  const configuration = mapId === 'redstone-quarry'
    ? { rules: { ...ONLINE_RULES, maxPlayers: 2, teamSize: 1 }, map: quarryMap, spawns: quarrySpawns }
    : { rules: ONLINE_RULES, map: ROADSIDE_MAP, spawns: SOLO_SPAWNS };
  const room = format === '4v4'
    ? new (practicePreset === BRISK_PRACTICE_ID ? BriskPractice : !practice && roomSpeedControl ? SpeedReadyRoom : OnlineFourBattle)({ tankId, configuration })
    : new BattleRoom({ tankId });
  if (practice) {
    room.practice = true;
    room.waiting = false;
    room.rules = Object.freeze({ ...room.rules, maxPlayers: 1 });
  }
  room.format = format;
  return room;
}
