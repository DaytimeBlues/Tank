const MAX_AGE_MS = 1000;
const MARKS = { pending: '…', clear: '○', blocked: '×', unavailable: '—', stale: '!' };
const finiteVector = p => p && ['x','y','z'].every(k => Number.isFinite(p[k]));
function describe(snapshot) {
  const c = snapshot?.trial?.clearance;
  if (c?.status === 'pending') return { state: 'pending', label: 'Pending', speech: 'Muzzle clearance pending.' };
  if (c?.status !== 'measured' || c.kind !== 'resting-muzzle' || c.mapVersion !== 2 || c.range !== 10 ||
      c.sampleTime !== snapshot.time || !finiteVector(c.origin) || !finiteVector(c.endpoint) ||
      Math.abs(Math.hypot(c.endpoint.x-c.origin.x,c.endpoint.y-c.origin.y,c.endpoint.z-c.origin.z)-10) > .001)
    return { state: 'unavailable', label: 'Unavailable', speech: 'Muzzle clearance unavailable.' };
  if (c.blocked === false && c.category === null && c.distance === null)
    return { state: 'clear', label: 'Clear · next 10 m', speech: 'Muzzle clearance clear for the next ten metres. Weapons disabled.' };
  if (c.blocked === true && ['terrain','wall'].includes(c.category) && Number.isFinite(c.distance) && c.distance >= 0 && c.distance <= 10.0001) {
    const material = c.category === 'terrain' ? 'ground' : 'wall';
    return { state: 'blocked', category: c.category, label: `Blocked · ${material} at ${c.distance.toFixed(1)} m`, speech: `Muzzle clearance blocked by ${material}. Weapons disabled.` };
  }
  return { state: 'unavailable', label: 'Unavailable', speech: 'Muzzle clearance unavailable.' };
}
function resetPose(snapshot) {
  const t = snapshot?.tank, q = t?.quaternion;
  return snapshot?.trial?.stage === 'outbound' && t && q &&
    ['x','y','z','yaw','pitch','roll','speed'].every(k => Number.isFinite(t[k])) &&
    ['x','y','z','w'].every(k => Number.isFinite(q[k])) &&
    Math.abs(t.x) < .1 && Math.abs(t.z+24) < .1 && t.y >= .9 && t.y <= 1.51 &&
    Math.abs(t.yaw) < .01 && Math.abs(t.pitch) < 1 && Math.abs(t.roll) < 1 && Math.abs(t.speed) < .05 &&
    Math.hypot(q.x,q.y,q.z) < .01 && Math.abs(Math.abs(q.w)-1) < .001;
}
// This is a DOM adapter contract, not a browser renderer. Receipt age uses the
// client's monotonic clock; authoritative simulation timestamps only order data.
export function createClearanceHUD({ root, label, mark, announcement }) {
  let enabled = false, online = false, waitingReset = false, receivedAt = 0, lastTime = -Infinity, semanticKey;
  const write = (node, value) => { if (node.textContent !== value) node.textContent = value; };
  function paint(view) {
    if (root.hidden !== !enabled) root.hidden = !enabled;
    if (!enabled) { write(announcement, ''); semanticKey = undefined; return; }
    if (root.dataset.state !== view.state) root.dataset.state = view.state; write(label, view.label); write(mark, MARKS[view.state]);
    const key = view.state + ':' + (view.category ?? '');
    if (key !== semanticKey) { write(announcement, view.speech); semanticKey = key; }
  }
  const pending = () => paint({ state: 'pending', label: 'Pending', speech: 'Muzzle clearance pending.' });
  const stale = () => paint({ state: 'stale', label: 'Stale · waiting for update', speech: 'Muzzle clearance out of date. Waiting for update.' });
  function tick(now) {
    if (enabled && (!online || !Number.isFinite(now) || now < receivedAt || now-receivedAt > MAX_AGE_MS)) stale();
  }
  return {
    begin(slope, now) {
      enabled = slope === true; online = true; waitingReset = false; lastTime = -Infinity; receivedAt = now;
      pending(); tick(now);
    },
    receive(snapshot, now) {
      if (!enabled) return;
      if (!online) { stale(); return; }
      if (snapshot?.mode !== 'grade-drive' || !Number.isFinite(snapshot.time) || snapshot.time < 0 || !Number.isFinite(now)) {
        paint({ state: 'unavailable', label: 'Unavailable', speech: 'Muzzle clearance unavailable.' }); return;
      }
      const pendingReset = waitingReset && snapshot.trial?.clearance?.status === 'pending' && snapshot.time >= lastTime;
      if (snapshot.time <= lastTime && !pendingReset) { tick(now); return; }
      lastTime = snapshot.time;
      if (waitingReset && !pendingReset && !resetPose(snapshot)) { tick(now); return; }
      waitingReset = false; receivedAt = now; paint(describe(snapshot)); tick(now);
    },
    reset(now) {
      if (!enabled) return;
      if (!online) { stale(); return; }
      waitingReset = true; receivedAt = now; pending(); tick(now);
    },
    disconnect(now) { online = false; tick(now); },
    tick
  };
}
