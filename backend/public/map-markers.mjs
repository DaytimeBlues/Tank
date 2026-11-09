// Presentation only. Team names and ownership come from authoritative snapshots.
const OWNERS = Object.freeze({
  blue: Object.freeze({ label: 'BLUE', shape: 'square', symbol: '■', colour: '#a8d2ea' }),
  red: Object.freeze({ label: 'RED', shape: 'triangle', symbol: '▲', colour: '#ef927b' }),
  neutral: Object.freeze({ label: 'NEUTRAL', shape: 'diamond', symbol: '◇', colour: '#eee9db' })
});
export const MARKER_LEGEND = '■ BLUE · ▲ RED · ◇ NEUTRAL · ◎ YOU · × OFFLINE';
export function ownershipMarker(owner) { return OWNERS[owner] ?? OWNERS.neutral; }
export function markerPath(ctx, shape, x, y, size) {
  ctx.beginPath();
  if (shape === 'square') ctx.rect(x - size, y - size, size * 2, size * 2);
  else if (shape === 'triangle') { ctx.moveTo(x, y - size); ctx.lineTo(x + size, y + size); ctx.lineTo(x - size, y + size); ctx.closePath(); }
  else { ctx.moveTo(x, y - size); ctx.lineTo(x + size, y); ctx.lineTo(x, y + size); ctx.lineTo(x - size, y); ctx.closePath(); }
}
export function paintBaseBadge(ctx, id, owner) {
  const m = ownershipMarker(owner);
  ctx.clearRect(0, 0, 512, 512); ctx.fillStyle = '#17211ef2'; ctx.fillRect(8, 8, 496, 496);
  markerPath(ctx, m.shape, 256, 205, 170); ctx.strokeStyle = '#fff8e8'; ctx.lineWidth = 14; ctx.stroke();
  ctx.fillStyle = '#fff8e8'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.font = 'bold 172px sans-serif'; ctx.fillText(String(id), 256, 220);
  ctx.font = 'bold 54px sans-serif'; ctx.fillText(m.label, 256, 444);
}
export function drawTerritorialMap(ctx, map, state) {
  const p = v => 100 + v / map.size * 190;
  ctx.save(); ctx.clearRect(0, 0, 200, 200); ctx.fillStyle = '#3e4d35'; ctx.fillRect(0, 0, 200, 200);
  ctx.fillStyle = '#356b78'; ctx.fillRect(p(-8), 5, 16 / map.size * 190, 190);
  ctx.fillStyle = '#b5ae96'; for (const b of map.bridges) ctx.fillRect(p(-b.w / 2), p(b.z - b.d / 2), b.w / map.size * 190, b.d / map.size * 190);
  for (const b of state.capture.bases) {
    const m = ownershipMarker(b.owner), x = p(b.x), y = p(b.z);
    markerPath(ctx, m.shape, x, y, 10); ctx.fillStyle = '#17211e'; ctx.fill(); ctx.strokeStyle = m.colour; ctx.lineWidth = 1.5; ctx.stroke();
    ctx.fillStyle = '#fff8e8'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = 'bold 11px monospace'; ctx.fillText(String(b.id), x, y);
  }
  for (const u of state.players) {
    if (u.health <= 0) continue;
    const m = ownershipMarker(u.team), x = p(u.tank.x), y = p(u.tank.z);
    markerPath(ctx, m.shape, x, y, 4); ctx.fillStyle = m.colour; ctx.fill(); ctx.strokeStyle = '#17211e'; ctx.lineWidth = 1; ctx.stroke();
    if (u.id === state.playerId) {
      ctx.beginPath(); ctx.arc(x, y, 7, 0, Math.PI * 2); ctx.strokeStyle = '#fff8e8'; ctx.lineWidth = 2; ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + Math.sin(u.tank.yaw) * 12, y + Math.cos(u.tank.yaw) * 12); ctx.stroke();
    }
    if (!u.connected) {
      ctx.beginPath(); ctx.moveTo(x - 6, y - 6); ctx.lineTo(x + 6, y + 6); ctx.moveTo(x + 6, y - 6); ctx.lineTo(x - 6, y + 6);
      ctx.strokeStyle = '#fff8e8'; ctx.lineWidth = 2; ctx.stroke();
    }
  }
  ctx.restore();
}
