export function battleWeaponPresentation(own, winner) {
  if (winner) return { text: 'Match complete', value: 0, label: 'Cannon unavailable: match complete' };
  if (!own?.connected) return { text: 'Disconnected', value: 0, label: 'Cannon unavailable: disconnected' };
  if (own.health <= 0) return { text: own.respawnSeconds > 0 ? `Respawn ${Math.ceil(own.respawnSeconds)}s` : 'Waiting for lane', value: 0, label: 'Cannon unavailable: hull scrapped' };
  const reload = Math.max(0, own.tank.reload);
  return reload > 0 ? { text: `${reload.toFixed(1)}s`, value: Math.max(0, 1 - reload / 4), label: 'Cannon reloading' }
    : { text: 'Ready', value: 1, label: 'Cannon ready' };
}

export function nearbyBaseStatus(state, own) {
  if (state.staging?.waiting !== false || state.won || state.winner || !own?.connected || own.health <= 0) return '';
  const { x, y, z } = own.tank;
  // Proximity only decides where to show the cue; the server decides occupancy and capture.
  const base = state.capture.bases.find(b => Math.hypot(x-b.x, z-b.z) <= b.radius+5 && Math.abs(y-b.y-1.05) <= 3);
  if (!base) return '';
  const owner = { blue: 'Blue', red: 'Red' }[base.owner];
  const gaining = base.net > 0 ? 'Blue' : base.net < 0 ? 'Red' : '';
  const advancing = gaining && base.progress !== Math.sign(base.net);
  const holds = owner ? owner+' holds' : 'Neutral';
  if (base.contested) return [base.name+' contested', holds, advancing && gaining+' gaining'].filter(Boolean).join(' · ');
  if (!advancing) return base.name+' · '+holds;
  const advance = gaining+(owner === gaining ? ' regaining' : ' taking');
  return [base.name, owner && holds, advance].filter(Boolean).join(' · ');
}

// Screen-space placement only: callers retain the game's existing eligibility rules.
export function layoutPlayerLabels(items, { width, height, obstacles = [], previous = [] }) {
  const placed = [], gap = 5, margin = 6;
  const area = (a, b) => Math.max(0, Math.min(a.x+a.width+gap,b.x+b.width)-Math.max(a.x-gap,b.x))
    * Math.max(0, Math.min(a.y+a.height+gap,b.y+b.height)-Math.max(a.y-gap,b.y));
  for (const item of [...items].sort((a,b) => Number(b.own)-Number(a.own) || a.id.localeCompare(b.id))) {
    const w = item.width, h = item.height, idealX = item.x-w/2, idealY = item.y-h-6;
    const candidates = [], old = previous.find(p=>p.id===item.id);
    const add = (x,y,retained=false) => candidates.push({x:Math.max(margin,Math.min(width-w-margin,x)),y:Math.max(margin,Math.min(height-h-margin,y)),retained});
    if(old) add(item.x+old.x-old.anchorX,item.y+old.y-old.anchorY,true);
    add(idealX,idealY);
    // Nearby rows first; full screen candidates provide a bounded crowded-view fallback.
    for(let row=1;row<=6;row++) for(const sign of [-1,1]) {
      add(idealX,idealY+sign*row*(h+gap));
      add(idealX-w-gap,idealY+sign*(row-1)*(h+gap));
      add(idealX+w+gap,idealY+sign*(row-1)*(h+gap));
    }
    for(let y=margin;y<=height-h-margin;y+=h+gap) for(let x=margin;x<=width-w-margin;x+=Math.max(32,w/2)) add(x,y);
    let best, score=Infinity;
    for(const c of candidates) {
      const rect={...c,width:w,height:h};
      const covered=[...obstacles,...placed].reduce((n,r)=>n+area(rect,r),0);
      const cost=covered*1e6+(c.x-idealX)**2+(c.y-idealY)**2-(c.retained?144:0);
      if(cost<score){score=cost;best={id:item.id,x:c.x,y:c.y,width:w,height:h,anchorX:item.x,anchorY:item.y,crowded:covered>0};}
    }
    // When exclusion space is exhausted keep identities and their leader lines; never silently cull.
    placed.push(best);
  }
  return placed;
}

// Remote clones borrow the asset bank; only per-player labels/traces are owned here.
export function createBattleClient({ THREE, scene, doc, bank, primitive, camera, pooledEffects = false }) {
  const peers = new Map(), labels = new Map(), leaders = new Map(); let latest, previous = [];
  const projected = new THREE.Vector3(), offset = new THREE.Vector3();
  function remove(id) {
    const p = peers.get(id); if (p) { scene.remove(p.group); if(p.trace){scene.remove(p.trace);p.trace.geometry.dispose();p.trace.material.dispose();} peers.delete(id); }
    labels.get(id)?.remove(); labels.delete(id); leaders.get(id)?.remove(); leaders.delete(id);
  }
  function update(state) {
    latest = state;
    const aliveIds = new Set(state.players.map(p => p.id));
    for (const id of labels.keys()) if (!aliveIds.has(id)) remove(id);
    for (const p of state.players) {
      if (!labels.has(p.id)) {
        const label = doc.createElement('div'); label.className = 'player-label'; label.dataset.playerId = p.id;
        doc.getElementById('targetLabels').append(label); labels.set(p.id, label);
        const leader = doc.createElement('div'); leader.className = 'player-label-leader';
        doc.getElementById('targetLabels').append(leader); leaders.set(p.id, leader);
      }
      const label = labels.get(p.id); label.dataset.team = p.team;
      label.textContent = `${p.id === state.playerId ? 'YOU' : p.ai ? 'AI '+p.id.slice(1) : p.id.toUpperCase()} · ${p.team.toUpperCase()} · ${p.health}/${p.maxHealth}${p.connected ? '' : ' · OFFLINE'}`;
      if (p.id === state.playerId) continue;
      let peer = peers.get(p.id);
      if (!peer || peer.visualId !== p.visualId) {
        if (peer) { scene.remove(peer.group);if(peer.trace){scene.remove(peer.trace);peer.trace.geometry.dispose();peer.trace.material.dispose();} }
        const source = bank.get(p.visualId)?.root, model = (source ?? primitive).clone(true);
        model.position.set(0, 0, 0); model.quaternion.identity(); model.visible = true;
        // Asset root is local-space even when its bank source is posed under the local tank.
        model.traverse(o => { if (o.isLine) o.visible = false; });
        const yaw = model.getObjectByName(source ? 'TurretYaw' : 'LegacyTurret');
        const pitch = model.getObjectByName('BarrelPitch'); if (yaw) yaw.rotation.y = 0; if (pitch) pitch.rotation.x = 0;
        const barrel = model.getObjectByName(source ? 'Barrel' : 'LegacyBarrel');
        const barrelRestZ = barrel?.userData.recoilRestZ ?? barrel?.position.z;
        if (barrel) barrel.position.z = barrelRestZ;
        const group = new THREE.Group(); group.add(model); group.name = 'Player_' + p.id; scene.add(group);
        const trace = pooledEffects ? null : new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color: p.team === 'blue' ? 0xb9d8ea : 0xef927b }));
        if(trace){trace.visible = false; scene.add(trace);} peer = { group, yaw, barrel, barrelRestZ, trace, visualId: p.visualId }; peers.set(p.id, peer);
      }
      const t = p.tank; peer.group.visible = p.health > 0;
      peer.group.quaternion.set(t.quaternion.x, t.quaternion.y, t.quaternion.z, t.quaternion.w);
      offset.set(0, -1, 0).applyQuaternion(peer.group.quaternion); peer.group.position.set(t.x + offset.x, t.y + offset.y, t.z + offset.z);
      if (peer.yaw) peer.yaw.rotation.y = t.turret;
      if(peer.trace){peer.trace.visible = !!(p.shot && state.time - p.shot.time < .16);
      if (peer.trace.visible) peer.trace.geometry.setFromPoints([new THREE.Vector3(p.shot.x, p.shot.y, p.shot.z), new THREE.Vector3(p.shot.endX, p.shot.endY, p.shot.endZ)]);}
    }
    const own = state.players.find(p => p.id === state.playerId);
    doc.getElementById('scene').dataset.peerCount = String(peers.size);
    doc.getElementById('scene').dataset.playerId = state.playerId;
    doc.getElementById('crew').textContent = state.singlePlayer ? `BLUE · 3 AI allies · 4 AI enemies${state.paused?' · PAUSED':''}` : `${own.team.toUpperCase()} · ${state.players.filter(p => p.connected).length}/${state.rules?.maxPlayers ?? 4} players`;
    doc.getElementById('targets').textContent = `BLUE ${state.scores.blue} · RED ${state.scores.red}`;
    const weapon = battleWeaponPresentation(own, state.winner);
    doc.getElementById('reload').textContent = weapon.text;
    const meter = doc.getElementById('reloadMeter'); meter.value = weapon.value; meter.setAttribute('aria-label', weapon.label);
    const status = state.paused ? 'Paused · close menu to resume' : state.winner ? `${state.winner.toUpperCase()} wins · Match complete`
      : own.health > 0 ? `${own.team.toUpperCase()} · Hull ${own.health}/${own.maxHealth} · Capture seven bases`
      : own.respawnSeconds > 0 ? 'Hull scrapped · Respawning' : 'Hull scrapped · Waiting for a clear lane';
    const live = doc.getElementById('battleStatus'); if (live.textContent !== status) live.textContent = status;
    doc.getElementById('resultTitle').textContent = `${state.winner?.toUpperCase() ?? ''} controls seven bases`;
    doc.getElementById('resultDescription').textContent = `Blue ${state.scores.blue} / 7 · Red ${state.scores.red} / 7`;
    const canRestart = state.playerId === state.hostId;
    doc.getElementById('replay').hidden = !canRestart;
    doc.getElementById('restartBattle').hidden = !state.singlePlayer && (!state.won || !canRestart);
    return own;
  }
  return { update, recoil(value){for(const [id,p]of peers)if(p.barrel)p.barrel.position.z=p.barrelRestZ-value(id);}, frame() {
    if (!latest) return;
    const items = [], width = doc.defaultView.innerWidth, height = doc.defaultView.innerHeight;
    for (const p of latest.players) {
      const label = labels.get(p.id); projected.set(p.tank.x, p.tank.y + 2, p.tank.z).project(camera);
      label.hidden = doc.getElementById('hud').hidden || p.health <= 0 || projected.z > 1 || Math.abs(projected.x) > .98 || Math.abs(projected.y) > .98;
      leaders.get(p.id).hidden = true;
      if(!label.hidden) items.push({id:p.id,x:(projected.x+1)/2*width,y:(1-projected.y)/2*height,own:p.id===latest.playerId});
    }
    // Batch measurements before placement writes; only the existing eligible labels participate.
    for(const item of items){const r=labels.get(item.id).getBoundingClientRect();item.width=r.width;item.height=r.height;}
    const obstacles = ['crewBar','objective','instruments','nearbyBase','mapPanel','mapToggle','notice','menu','result'].flatMap(id=>{
      const e=doc.getElementById(id); if(!e||!e.getClientRects().length)return [];
      const r=e.getBoundingClientRect(); return r.width&&r.height ? [{x:r.x,y:r.y,width:r.width,height:r.height}] : [];
    });
    obstacles.push({x:width/2-38,y:height/2-38,width:76,height:76});
    previous = layoutPlayerLabels(items,{width,height,obstacles,previous});
    for(const r of previous){
      const label=labels.get(r.id);label.style.left=r.x+'px';label.style.top=r.y+'px';label.dataset.crowded=String(r.crowded);
      const x=Math.max(r.x,Math.min(r.x+r.width,r.anchorX)),y=Math.max(r.y,Math.min(r.y+r.height,r.anchorY));
      const dx=x-r.anchorX,dy=y-r.anchorY,length=Math.hypot(dx,dy),leader=leaders.get(r.id);
      leader.hidden=length<9;leader.style.left=r.anchorX+'px';leader.style.top=r.anchorY+'px';leader.style.width=length+'px';leader.style.transform=`rotate(${Math.atan2(dy,dx)}rad)`;
    }
  }, dispose() { for (const id of [...labels.keys()]) remove(id); } };
}
