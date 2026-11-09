import { BattleRoom, BATTLE_RULES } from './battle-room.mjs';
import { SOLO_MAP, SOLO_SPAWNS } from './solo-map.mjs';

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
    if (!this.waiting) return { ...state, staging: { waiting: false } };
    const block = this.startBlock();
    return { ...state, staging: { waiting: true, block, canStart: !block && state.playerId === this.hostId,
      switchTo: this.teamSwitchTarget(this.seats[state.playerId]) },
      players: state.players.map(p => ({ ...p, ready: !!this.seats[p.id].ready })) };
  }
}
export function createOnlineBattle({ tankId = 'prototype', format } = {}) {
  format = battleFormat(format);
  const room = format === '4v4'
    ? new OnlineFourBattle({ tankId, configuration: { rules: ONLINE_RULES, map: SOLO_MAP, spawns: SOLO_SPAWNS } })
    : new BattleRoom({ tankId });
  room.format = format;
  return room;
}
