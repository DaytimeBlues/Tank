import * as THREE from '/vendor/three.module.js';
import { createClearanceHUD } from './clearance-hud.mjs';
import { buildBattlefield, updateBattlefieldHUD } from './battlefield-view.mjs';
import { battleConnection, BATTLE_REJOIN_DELAY_MS, BATTLE_REJOIN_WINDOW_MS } from './battle-connection.mjs';
import { tankProfile, selectionState } from './tank-config.mjs';
import { setupHangar } from './hangar.mjs';
import { GLTFLoader } from '/vendor/loaders/GLTFLoader.js';
import { loadTankVisuals, VISUALS } from './tank-visual.mjs';
import { createBattleClient, nearbyBaseStatus } from './battle-client.mjs';
import { drawTerritorialMap, MARKER_LEGEND } from './map-markers.mjs';
import { createFreeLook, bindFreeLook, createCameraGuard, LOOK_LIMITS } from './free-look.mjs';
import { createCombatVFX, soloPresentationShot } from './combat-vfx.mjs';
import { createFrameCadence } from './frame-cadence.mjs';
import { acquireHostedProtocols, GAME_PROTOCOL } from './hosted-ticket.mjs';

const $ = id => document.getElementById(id);
const clearanceHUD = createClearanceHUD({ root: $('clearanceHUD'), label: $('clearanceLabel'), mark: $('clearanceMark'), announcement: $('clearanceAnnouncement') });
const slopeRequested = new URLSearchParams(location.search).get('trial') === 'slope';
const soloRequested = document.documentElement.dataset.offline === 'true';
const hostedRequested = !soloRequested && document.documentElement.dataset.network === 'hosted';
const LocalTransport = soloRequested ? (await import('./local-transport.mjs')).LocalTransport : null;
const multiplayerRequested = soloRequested || new URLSearchParams(location.search).get('battle') === '1';
const online4v4Requested = !soloRequested && multiplayerRequested && new URLSearchParams(location.search).get('format') === '4v4';
const sessionKey = online4v4Requested ? 'tank-online4v4-session' : soloRequested ? 'tank-offline-session' : multiplayerRequested ? 'tank-battle-session' : new URLSearchParams(location.search).get('battlefield') === '1' ? 'tank-battlefield-session' : slopeRequested ? 'tank-slope-session' : 'tank-session';
const battlefieldRequested = multiplayerRequested || new URLSearchParams(location.search).get('battlefield') === '1';
const requestedMode = multiplayerRequested ? 'battle' : battlefieldRequested ? 'battlefield' : slopeRequested ? 'grade-drive' : 'range';
const selectedTank = selectionState();
let battlefieldMode = false, battleView;
let slopeMode = false;
if (slopeRequested) {
  $('lobbyTitle').textContent = 'Slope drive';
  $('intro').textContent = 'Climb the ridge, brake on the slope, then reverse home. One tank; steering and suspension trial.';
  $('role').options[1].textContent = 'Observer';
  $('status').textContent = 'W / S drive · A / D turn · release both to brake · R reset. Weapons disabled.';
}

const scene = new THREE.Scene();
scene.background = new THREE.Color('#929b93');
scene.fog = new THREE.Fog('#929b93', 65, 150);
const camera = new THREE.PerspectiveCamera(52, innerWidth / innerHeight, 0.1, 200);
const renderer = new THREE.WebGLRenderer({ canvas: $('scene'), antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
scene.add(new THREE.HemisphereLight(0xdce8db, 0x39442d, 2.1));
const sun = new THREE.DirectionalLight(0xffe3b0, 2.7);
sun.position.set(-25, 50, -20); sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -50, right: 50, top: 50, bottom: -50 });
sun.shadow.bias = -0.0005;
scene.add(sun);

function box(w, h, d, color, x = 0, y = 0, z = 0, parent = scene) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), new THREE.MeshStandardMaterial({ color, roughness: 0.9 }));
  mesh.position.set(x, y, z); mesh.castShadow = true; mesh.receiveShadow = true;
  parent.add(mesh);
  return mesh;
}
// Local, repeatable procedural surfaces. No downloaded image or asset licence needed.
// Box faces already have UVs; metre-based repeat prevents scale stretching.
function surface(mesh, colour, repeatX, repeatZ, seed = 7) {
  const canvas = document.createElement('canvas'); canvas.width = canvas.height = 128;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = colour; ctx.fillRect(0, 0, 128, 128);
  let value = seed;
  const rand = () => { value = (value * 1664525 + 1013904223) >>> 0; return value / 4294967296; };
  for (let i = 0; i < 2300; i++) {
    ctx.fillStyle = rand() > 0.5 ? 'rgba(255,255,220,0.055)' : 'rgba(12,20,12,0.08)';
    ctx.fillRect(rand() * 128, rand() * 128, 1 + rand() * 3, 1 + rand() * 3);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(repeatX, repeatZ);
  texture.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  mesh.material.map = texture; mesh.material.color.set(0xffffff);
}
const ground = box(180, 0.3, 180, 0x6c7851, 0, -0.2, 0);
surface(ground, '#65704f', 90, 90);
const tank = new THREE.Group(); scene.add(tank); tank.position.z = -20;
box(2.7, 0.9, 4, 0x505d3a, 0, 1, 0, tank);
box(0.6, 0.9, 4.5, 0x252a22, -1.5, 0.55, 0, tank);
box(0.6, 0.9, 4.5, 0x252a22, 1.5, 0.55, 0, tank);
const wheels = [];
for (const x of [-1.82, 1.82]) for (let z = -1.6; z <= 1.6; z += 0.8) {
  const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.32, 0.12, 12), new THREE.MeshStandardMaterial({ color: 0x68704e }));
  wheel.rotation.z = Math.PI / 2; wheel.position.set(x, 0.55, z); tank.add(wheel); wheels.push(wheel);
}
const turret = new THREE.Group(); turret.position.y = 1.65; tank.add(turret);
turret.name = 'LegacyTurret';
box(1.9, 0.7, 2, 0x66724b, 0, 0, 0, turret);
const barrel = box(0.22, 0.22, 3.5, 0x343e2a, 0, 0, 2.3, turret);
barrel.name = 'LegacyBarrel';
const barrelRestZ = barrel.userData.recoilRestZ = barrel.position.z;
box(0.6, 0.14, 0.6, 0x343e2a, 0, 0.43, 0, turret);
const aimLine = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0, 0, 4), new THREE.Vector3(0, 0, 65)]), new THREE.LineBasicMaterial({ color: 0xf4db86, transparent: true, opacity: 0.35 }));
turret.add(aimLine);
// Keep the exact primitive as a visual fallback; original art is only in the new mode.
let originalVisual;
const wantsOriginalArt = battlefieldRequested && new URLSearchParams(location.search).get('visual') !== 'primitive';
const modelLoader = wantsOriginalArt ? new GLTFLoader() : null;
const visualBank = modelLoader ? await loadTankVisuals(THREE,url=>modelLoader.loadAsync(url),
  (item,error)=>console.warn(`Tank visual unavailable: ${item.name}`,error)) : new Map();
const availableVisuals = VISUALS.filter(v=>visualBank.has(v.id));
const selectableVisuals = availableVisuals.length ? availableVisuals : VISUALS;
let initialVisual = 'kestrel';
try { const stored = sessionStorage.getItem('tank-visual-choice'); if (VISUALS.some(v=>v.id===stored)) initialVisual = stored; } catch {}
const queriedVisual = new URLSearchParams(location.search).get('visual');
if (VISUALS.some(v=>v.id===queriedVisual)) initialVisual = queriedVisual;
const visualSelection = selectionState(selectableVisuals,
  selectableVisuals.some(v=>v.id===initialVisual)?initialVisual:selectableVisuals[0].id);
function commitVisual(id) {
  if(!visualBank.has(id))return;
  for (const [key,v] of visualBank) v.root.visible = key === id;
  originalVisual = visualBank.get(id); originalVisual.yaw.add(aimLine);
  $('scene').dataset.visual = id;
  try { sessionStorage.setItem('tank-visual-choice',id); } catch {}
}
if (availableVisuals.length) {
  for (const child of tank.children) child.visible = false;
  for (const v of visualBank.values()) tank.add(v.root);
  commitVisual(visualSelection.committed);
}
if (!originalVisual) $('scene').dataset.visual = 'primitive';
addEventListener('pagehide', () => { for (const v of visualBank.values()) v.dispose(); }, { once: true });
const shotTrace = new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color: 0xffdf9c, transparent: true, opacity: .8 }));
shotTrace.visible = false; scene.add(shotTrace);

const hangar = setupHangar({ THREE, doc: document, tank, profile: multiplayerRequested ? {...tankProfile(), durability:3, tradeoffs:['Visual variants share the same tuning','Three hit points; no armour penetration','Turning reduces drive target speed']} : tankProfile(), selection: selectedTank, onOpen: () => release(), onClose: () => { if (session) $('scene').focus(); },
  ...(originalVisual ? { visuals: availableVisuals, visualSelection, onVisualCommit: commitVisual } : {}) });
if (!originalVisual) {
  $('hangarIntro').textContent = 'Primitive visual fallback. Current gameplay profile.';
  $('tankArtCaption').textContent = 'Locally authored primitive fallback · gameplay stats';
}
$('chooseTank').hidden = !battlefieldRequested;
if (!battlefieldRequested && !slopeRequested) { const link = document.createElement('a'); link.href = '?battlefield=1'; link.textContent = 'Open the seven-base battlefield'; link.className = 'battlefield-link'; $('lobby').append(link); }
if (battlefieldRequested) { $('lobbyTitle').textContent = 'Seven bases'; $('intro').textContent = 'One player. One whole tank. Secure seven bases across a nonflat river battlefield. Stationary training garrisons; no moving AI.'; $('role').replaceChildren(new Option('Commander — drive and aim', 'commander')); $('status').textContent = 'Inspect the tank, then create a local battlefield. W S drive · A D turn · pointer / Space fire.'; }
if (multiplayerRequested) {
  document.title = 'Tank Battle — Seven-base battle'; $('lobbyTitle').textContent = 'Seven-base battle';
  $('intro').textContent = 'Your own tank. One shared battlefield. Join Blue or Red and hold seven bases.';
  $('teamChoice').hidden = false; $('status').textContent = 'Create a match, then join its room code from another browser tab. Each player controls their own tank.';
} else { const link=document.createElement('a');link.href='?battle=1';link.textContent='Play independent-tank multiplayer';$('lobby').append(link); }
if (!soloRequested) {
  const link=document.createElement('a'); link.href=online4v4Requested?'?battle=1':'?battle=1&format=4v4';
  link.textContent=online4v4Requested?'Open legacy 2v2':'Open online 4v4'; $('lobby').append(link);
}
if (online4v4Requested) {
  $('resumeSeat').textContent = 'Rejoin tank';
  document.title='Tank Battle — Online 4v4'; $('lobbyTitle').textContent='Online 4v4';
  $('role').hidden=true; document.querySelector('label[for="role"]').hidden=true;
  $('create').textContent='Create 4v4 match'; document.querySelector('.divider').textContent='or join a match';
  $('scene').setAttribute('aria-label','Tank battlefield. W S drive, A D turn, pointer aim, Space fire.');
  $('intro').textContent='Up to eight players. Four tanks per team. Capture seven bases across hills, trees and three river crossings.';
  $('status').textContent='Create a match and share its code on this server. Each player drives and aims their own tank.';
  $('lobby').querySelector('small').textContent='Human multiplayer · local server preview';
}
if(soloRequested){
  document.title='Tank Battle — Single-player 4v4';$('lobbyTitle').textContent='Single-player 4v4';
  $('intro').textContent='You and three AI allies against four AI tanks. Capture seven bases across hills, trees and three river crossings.';
  $('create').textContent='Start battle';$('teamChoice').hidden=true;
  for(const node of [$('role'),document.querySelector('label[for="role"]'),document.querySelector('label[for="code"]'),document.querySelector('.join'),document.querySelector('.divider')])node.hidden=true;
  $('status').textContent='W S drive · A D turn · pointer aim · click or Space fire. Escape pauses.';
  $('lobby').querySelector('small').textContent='One player · seven AI · no server';
  if('serviceWorker' in navigator)navigator.serviceWorker.register('./sw.js').then(()=>navigator.serviceWorker.ready).then(()=>{$('lobby').querySelector('small').textContent='Offline ready · one player + seven AI';}).catch(()=>{$('lobby').querySelector('small').textContent='Local simulation · offline cache unavailable';});
}
const multiplayerView = multiplayerRequested ? createBattleClient({THREE,scene,doc:document,bank:visualBank,primitive:tank,camera,pooledEffects:true}) : null;
const combatFX = battlefieldRequested ? createCombatVFX(THREE,scene) : null;
const freeLook = createFreeLook(), cameraGuard=createCameraGuard(THREE);
let lookBinding, previousHealth;
const presentationPlayers=()=>multiplayerRequested?state.players:[{id:'solo',health:3,connected:true,tank:state.tank,shot:soloPresentationShot(state.shot)}];
addEventListener('pagehide',()=>{lookBinding?.dispose();combatFX?.dispose();},{once:true});
addEventListener('pagehide', () => multiplayerView?.dispose(), {once:true});
addEventListener('pagehide', () => battleView?.markers?.dispose(), {once:true});
const targets = new Map(), labels = new Map(), walls = [];
const cameraRay = new THREE.Raycaster(), cameraSight = new THREE.Vector3();
let mapData, state, socket, session, role, retryTimer, leaveTimer, manual = false, seated = false, leaving = false;
let battleRejoinUntil = 0, ticketAttempt;
let lastShot = 0, audio, particles = [], pointerBearing, pointerFire = false, wasWon = false;
let onlineRespawnCameraPending = false;
let noticeUntil = 0;
const keys = new Set();
function showStatus(message, seconds = 4) {
  $('status').textContent = message; $('mission').textContent = message;
  noticeUntil = performance.now() + seconds * 1000;
}
function setupMap(map) {
  if (mapData) return;
  mapData = map;
  for (const wall of map.walls) {
    const mesh = box(wall.w, (slopeMode || battlefieldMode) ? 8 : 4, wall.d, 0x828479, wall.x, (slopeMode || battlefieldMode) ? 4 : 2, wall.z);
    mesh.material.transparent = true;
    walls.push(mesh);
  }
  if (battlefieldMode) { ground.visible = false; scene.fog = new THREE.Fog('#a7b5ad', 180, 520); camera.far = 1200; camera.updateProjectionMatrix(); Object.assign(sun.shadow.camera, { left: -180, right: 180, top: 180, bottom: -180 }); sun.shadow.camera.updateProjectionMatrix(); battleView = buildBattlefield(THREE, scene, map, surface, {readableMarkers:multiplayerRequested}); $('scene').dataset.baseBadges = String(battleView.markers.size); return; }
  if (slopeMode) {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(map.vertices, 3));
    geometry.setIndex(map.indices);
    // World-space metre UVs keep the grass grain consistent along the whole ridge.
    const uv = []; for (let i = 0; i < map.vertices.length; i += 3) uv.push(map.vertices[i] / 2, map.vertices[i + 2] / 2);
    geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); geometry.computeVertexNormals();
    const terrain = new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ roughness: 0.95, flatShading: true }));
    surface(terrain, '#65704f', 1, 1); terrain.receiveShadow = true; scene.add(terrain);
    // Painted lane edges follow the same section heights; these are route cues, not barriers.
    for (const x of [-5, 5]) {
      const edge = new THREE.Line(new THREE.BufferGeometry().setFromPoints(map.sections.map(([z, y]) => new THREE.Vector3(x, y + 0.025, z))), new THREE.LineBasicMaterial({ color: 0xc9c5a1, transparent: true, opacity: 0.65 }));
      scene.add(edge);
    }
    // Two pairs of physical-height markers establish the start and turnaround.
    for (const [z, y] of [[-22, 0], [30, 1.05]]) for (const x of [-4, 4]) {
      box(0.18, 1.6, 0.18, 0xe0bb70, x, y + 0.8, z);
      box(0.6, 0.3, 0.12, 0xeee9db, x, y + 1.4, z);
    }
    aimLine.visible = false; return;
  }
  const mud = box(map.mud.w, 0.04, map.mud.d, 0x51493b, map.mud.x, 0.03, map.mud.z);
  surface(mud, '#4d4233', map.mud.w / 2, map.mud.d / 2, 29);
  // Wheel ruts distinguish the slow surface without relying on colour alone.
  for (let x = map.mud.x - map.mud.w / 2 + 1; x < map.mud.x + map.mud.w / 2; x += 2)
    box(0.12, 0.02, map.mud.d - 1, 0x39352b, x, 0.06, map.mud.z);
}
function tone(freq, duration, volume = 0.07) {
  if (!audio) return;
  const oscillator = audio.createOscillator(), gain = audio.createGain();
  oscillator.frequency.setValueAtTime(freq, audio.currentTime);
  oscillator.frequency.exponentialRampToValueAtTime(Math.max(20, freq / 3), audio.currentTime + duration);
  gain.gain.setValueAtTime(volume, audio.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + duration);
  oscillator.connect(gain).connect(audio.destination); oscillator.start(); oscillator.stop(audio.currentTime + duration);
}
$('audio').onclick = () => { audio ??= new AudioContext(); audio.resume(); $('audio').textContent = 'Sound on'; tone(300, 0.15); };
function effect(x, z, colour, count = 14) {
  for (let i = 0; i < count; i++) {
    const mesh = box(0.2, 0.2, 0.2, colour, x, 1, z);
    particles.push({ mesh, life: 1, v: new THREE.Vector3((Math.random() - 0.5) * 8, Math.random() * 6, (Math.random() - 0.5) * 8) });
  }
}
function send(data) { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(data)); }
function busy(value) { $('create').disabled = value; $('join').disabled = value; }
function showBattleLobby() {
  state = null; wasWon = false; lastShot = 0;
  onlineRespawnCameraPending = false;
  $('nearbyBase').textContent = '';
  for (const id of ['readyRoom','hud','menu','result']) $(id).hidden = true;
  $('menuToggle').setAttribute('aria-expanded','false');
  $('lobby').hidden = false;
}
async function connect(request) {
  seated = false; leaving = false; release();
  if (online4v4Requested) {
    showBattleLobby();
    if (request.type !== 'reconnect') battleRejoinUntil = 0;
    $('forgetSeat').hidden = !session;
  }
  $('resumeSeat').hidden = true;
  clearanceHUD.begin(slopeRequested, performance.now());
  request = { ...request, mode: requestedMode, ...(battlefieldRequested ? { tankId: selectedTank.committed } : {}), ...(online4v4Requested ? {format:'4v4'} : {}), ...(multiplayerRequested ? {team:$('battleTeam').value,visualId:visualSelection.committed} : {}) };
  clearTimeout(retryTimer); manual = false; busy(true);
  showStatus(online4v4Requested && request.type === 'reconnect' ? `Rejoining room ${request.code}…` : 'Connecting…');
  let closeMessage = '', confirmed = false;
  let protocols;
  if (hostedRequested) {
    ticketAttempt?.abort();
    const attempt = new AbortController(); ticketAttempt = attempt;
    const old = socket; socket = null; old?.close();
    try {
      if (location.protocol !== 'https:') throw new Error('HTTPS required');
      protocols = await acquireHostedProtocols(request, { signal: attempt.signal });
    } catch {
      if (ticketAttempt !== attempt) return;
      ticketAttempt = null; battleRejoinUntil = 0; busy(false);
      $('resumeSeat').hidden = !session;
      showStatus(!online4v4Requested ? 'Hosted play requires online 4v4.' :
        'Could not get a connection ticket. Sign in to the host and try again.', 60);
      return;
    }
    if (ticketAttempt !== attempt) return;
    ticketAttempt = null;
  }
  const previousSocket = socket;
  const url = (location.protocol === 'https:' ? 'wss' : 'ws') + '://' + location.host;
  const raw = soloRequested ? new LocalTransport() : protocols ? new WebSocket(url, protocols) : new WebSocket(url);
  const connection = online4v4Requested ? battleConnection(raw, { visible: !document.hidden }) : raw;
  socket = connection; previousSocket?.close();
  connection.onopen = () => {
    if (socket !== connection) return;
    if (hostedRequested && raw.protocol !== GAME_PROTOCOL) {
      manual = true; closeMessage = 'Hosted connection could not be verified.'; connection.close(); return;
    }
    send({...request,...(soloRequested?{paused:document.hidden||!$('menu').hidden}:{})});
  };
  connection.onmessage = event => {
    if (socket !== connection) return;
    const msg = JSON.parse(event.data);
    if (msg.type === 'error') {
      if (!online4v4Requested || confirmed) busy(false);
      showStatus(msg.message);
      if (!$('readyRoom').hidden) $('readyError').textContent = msg.message;
      if (request.type === 'reconnect' && !seated) {
        manual = !(online4v4Requested && msg.code === 'SESSION_ACTIVE' && battleRejoinUntil > performance.now());
        closeMessage = msg.code === 'SESSION_ACTIVE' || msg.message === 'Session unavailable'
          ? online4v4Requested ? 'Your tank is still connected. Close the other tab if it is open, then select Rejoin tank.' : 'Seat already connected. Close the other tab, then rejoin this seat.'
          : msg.message;
        if (['SESSION_INVALID', 'SESSION_EXPIRED'].includes(msg.code) || ['Invalid session', 'Room not found'].includes(msg.message) || msg.message.startsWith('Room mode mismatch') || msg.message.startsWith('Room format mismatch')) {
          sessionStorage.removeItem(sessionKey); session = null; manual = true;
          state = null; $('result').hidden = true; $('hud').hidden = true; $('lobby').hidden = false;
          closeMessage = 'Saved seat is no longer available. Create or join a room.';
        }
        connection.close();
      } else if (online4v4Requested && !seated) {
        manual = true; closeMessage = msg.message; connection.close();
      }
      return;
    }
    if (msg.type === 'left' && leaving) {
      clearTimeout(leaveTimer); leaving = false;
      sessionStorage.removeItem(sessionKey); session = null;
      connection.close(); location.reload(); return;
    }
    if (msg.type === 'joined') {
      if (!online4v4Requested) busy(false);
      if (requestedMode !== (msg.map.mode ?? 'range')) {
        closeMessage = 'Mode mismatch. Open the matching range, slope or battlefield link.';
        manual = true; session = null; sessionStorage.removeItem(sessionKey); connection.close();
        showStatus(closeMessage, 60); return;
      }
      seated = true;
      if (online4v4Requested) $('forgetSeat').hidden = true;
      slopeMode = msg.map.mode === 'grade-drive'; battlefieldMode = ['battlefield','battle'].includes(msg.map.mode);
      if (multiplayerRequested && selectableVisuals.some(v=>v.id===msg.visualId)) { visualSelection.browse(msg.visualId);visualSelection.confirm();commitVisual(msg.visualId); }
      clearanceHUD.begin(slopeMode, performance.now());
      session = { code: msg.code, token: msg.token };
      if(!soloRequested)sessionStorage.setItem(sessionKey, JSON.stringify(session));
      role = msg.role; release(); setupMap(msg.map);
      $('lobby').hidden = !online4v4Requested; $('hud').hidden = online4v4Requested;
      $('room').textContent = msg.code;
      $('seatName').textContent = role === 'commander' ? 'Commander' : role === 'driver' ? 'Driver' : 'Gunner';
      $('controls').textContent = role === 'driver' ? 'W S drive  ·  A D turn  ·  release to brake' : 'Pointer aim  ·  Space fire  ·  E spot';
      $('disconnect').hidden = false; $('reconnect').hidden = true;
      showStatus(role === 'driver' ? 'Move into position. Cover blocks your gunner’s shots.' : 'Aim at a target. Each needs three hits.');
      if (slopeMode) configureSlopeUI();
      if (battlefieldMode) configureBattlefieldUI();
      if (multiplayerRequested) configureMultiplayerUI();
      if (online4v4Requested) showStatus('Tank connected. Waiting for the battlefield…', 60);
      if (soloRequested) configureSoloUI();
      if(soloRequested)menu(document.hidden||!!msg.paused);else if (!online4v4Requested) $('scene').focus();
    }
    if (msg.type === 'state' && (!online4v4Requested || seated)) {
      if (online4v4Requested) {
        if (confirmed && state?.staging?.waiting === false && msg.staging?.waiting === false &&
            state.playerId === msg.playerId && state.players.find(p => p.id === msg.playerId)?.health === 0 &&
            msg.players.find(p => p.id === msg.playerId)?.health > 0) onlineRespawnCameraPending = true;
        if (!confirmed) {
          confirmed = true; battleRejoinUntil = 0; $('lobby').hidden = true;
          busy(false);
          if (request.type === 'reconnect') {
            const team = msg.players.find(p => p.id === msg.playerId)?.team;
            showStatus(`Rejoined your ${team === 'blue' ? 'Blue' : 'Red'} tank.`, 8);
          } else showStatus('Drive and aim your own tank. Advance onto the crossing to contest base 4.', 8);
        }
        connection.snapshot();
      }
      state = msg; clearanceHUD.receive(msg, performance.now()); updateHUD();
      if(soloRequested)document.dispatchEvent(new CustomEvent('tank-observation',{detail:structuredClone(msg)}));
    }
  };
  connection.onclose = event => {
    if (socket !== connection) return;
    clearTimeout(leaveTimer);
    const wasSeated = seated;
    seated = false; busy(false); release(); clearanceHUD.disconnect(performance.now());
    if (online4v4Requested) {
      const now = performance.now();
      if (event.code === 1008) { manual = true; closeMessage = 'The server ended this connection. Select Rejoin tank to try again.'; }
      if (wasSeated && !manual && session && (confirmed || request.type !== 'reconnect')) battleRejoinUntil = now + BATTLE_REJOIN_WINDOW_MS;
      const retry = !manual && session && now + BATTLE_REJOIN_DELAY_MS < battleRejoinUntil;
      if (!retry) battleRejoinUntil = 0;
      showBattleLobby();
      if (session) $('code').value = session.code;
      if (leaving) { leaving = false; $('fresh').disabled = false; closeMessage = 'Seat release was not confirmed. Rejoin to check it, or let the reservation expire.'; }
      $('resumeSeat').hidden = !session || !!retry;
      $('forgetSeat').hidden = !session;
      busy(!!retry);
      const interrupted = event.timedOut ? 'Battle updates stopped.' : event.code === 1000 && manual ? 'Disconnected.' : 'Connection lost.';
      showStatus(retry ? `${interrupted} Rejoining room ${session.code}…` : closeMessage ||
        (session ? `${interrupted} Select Rejoin tank to try your saved seat.` : 'Could not connect. Create or join a room to try again.'), 60);
      (retry ? $('forgetSeat') : session ? $('resumeSeat') : $('create')).focus();
      if (retry) retryTimer = setTimeout(() => {
        if (!session || manual) return;
        if (performance.now() < battleRejoinUntil) connect({ type: 'reconnect', ...session });
        else {
          battleRejoinUntil = 0; busy(false); $('resumeSeat').hidden = false;
          showStatus('Automatic rejoin ended. Select Rejoin tank to try your saved seat.', 60);
          $('resumeSeat').focus();
        }
      }, BATTLE_REJOIN_DELAY_MS);
      return;
    }
    if (!$('readyRoom').hidden) { $('readyRoom').hidden = true; $('hud').hidden = true; $('lobby').hidden = false; }
    if(soloRequested){session=null;state=null;$('hud').hidden=true;$('lobby').hidden=false;showStatus('Local session ended. Start a new battle.',60);return;}
    if (leaving) { leaving = false; $('fresh').disabled = false; closeMessage = 'Seat release was not confirmed. Rejoin to check it, or wait for the 30-second reservation to expire.'; }
    $('disconnect').hidden = true; $('reconnect').hidden = !session;
    $('resumeSeat').hidden = !session;
    if (session && !$('lobby').hidden) $('resumeSeat').focus();
    $('crew').textContent = 'Disconnected · crew status unavailable';
    showStatus(closeMessage || (session ? 'Disconnected. Seat reserved for up to 30 seconds.' : 'Session ended. Create or join a room.'), 60);
    if (!session) $('create').focus();
    if (!manual && session) retryTimer = setTimeout(() => connect({ type: 'reconnect', ...session }), 1000);
  };
  connection.onerror = () => { if (socket === connection && !online4v4Requested) { clearanceHUD.disconnect(performance.now()); showStatus(soloRequested?'Local simulation could not start. Reload to retry.':'Server unavailable. Retrying saved seat…', 60); } };
}
$('create').onclick = () => connect({ type: 'create', role: $('role').value, mode: slopeRequested ? 'grade-drive' : 'range' });
$('join').onclick = () => {
  const code = $('code').value.trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(code)) { showStatus('Enter the six-character room code.'); $('code').focus(); return; }
  connect({ type: 'join', code, role: $('role').value });
};
$('disconnect').onclick = () => { manual = true; clearanceHUD.disconnect(performance.now()); socket?.close(); };
function rejoinSavedTank() {
  if (!session) return;
  if (online4v4Requested) battleRejoinUntil = performance.now() + BATTLE_REJOIN_WINDOW_MS;
  connect({ type: 'reconnect', ...session });
}
$('reconnect').onclick = rejoinSavedTank;
$('resumeSeat').onclick = $('reconnect').onclick;
$('forgetSeat').onclick = () => {
  if (!online4v4Requested || seated || !session) return;
  clearTimeout(retryTimer); battleRejoinUntil = 0; manual = true;
  ticketAttempt?.abort(); ticketAttempt = null;
  session = null; sessionStorage.removeItem(sessionKey);
  socket?.close(); busy(false);
  $('forgetSeat').hidden = true; $('resumeSeat').hidden = true;
  showStatus('Saved seat forgotten. The server releases any remaining reservation when it expires.', 60);
  $('create').focus();
};
$('fresh').onclick = () => {
  manual = true; clearTimeout(retryTimer); release();
  if (seated && socket?.readyState === WebSocket.OPEN) {
    leaving = true; seated = false; $('fresh').disabled = true;
    if (!$('readyRoom').hidden) { $('readyLeave').disabled = true; $('readyError').textContent = 'Releasing your seat…'; }
    showStatus('Releasing your seat…', 60); send({ type: 'leave' });
    leaveTimer = setTimeout(() => socket?.close(), 3000);
  } else {
    // A disconnected seat retains its existing server reservation until expiry.
    sessionStorage.removeItem(sessionKey); session = null; location.reload();
  }
};
$('readyLeave').onclick = $('fresh').onclick;
$('readyToggle').onclick = () => {
  if (!seated || !state?.staging?.waiting) return;
  $('readyError').textContent = '';
  send({ type: 'ready', ready: !state.players.find(p => p.id === state.playerId)?.ready });
};
$('readySwitch').onclick = () => {
  const team = state?.staging?.switchTo;
  if (!seated || !state?.staging?.waiting || !team) return;
  $('readyError').textContent = '';
  send({ type: 'switchTeam', team });
};
$('readyStart').onclick = () => {
  if (!seated || !state?.staging?.canStart) return;
  $('readyError').textContent = '';
  send({ type: 'start' });
};
function updateReadyRoom() {
  if (!online4v4Requested || !seated) return;
  const wasWaiting = !$('readyRoom').hidden, waiting = !!state.staging?.waiting;
  const wasHidden = $('hud').hidden;
  $('readyRoom').hidden = !waiting;
  $('hud').hidden = waiting;
  if (!waiting) { if (wasHidden) $('scene').focus(); return; }
  if (!wasWaiting) {
    release(); $('result').hidden = true; $('menu').hidden = true;
    $('menuToggle').setAttribute('aria-expanded', 'false');
    $('readyCode').textContent = session.code;
    $('readyError').textContent = ''; $('readyLeave').disabled = false;
    $('readyTitle').focus();
  }
  const host = state.playerId === state.hostId;
  const target = state.staging.switchTo;
  const status = target ? 'Your team is larger. You can switch sides to help balance the match.' :
    state.staging.block ?? (host ? 'All players ready.' : 'Waiting for the host to start.');
  if ($('readyStatus').textContent !== status) $('readyStatus').textContent = status;
  const own = state.players.find(p => p.id === state.playerId);
  $('readyToggle').textContent = own?.ready ? 'Cancel ready' : 'Mark ready';
  const switchButton = $('readySwitch'), switchFocused = document.activeElement === switchButton;
  switchButton.hidden = !target;
  if (target) switchButton.textContent = target === 'blue' ? 'Switch to Blue' : 'Switch to Red';
  else if (switchFocused) $('readyToggle').focus();
  $('readyStart').hidden = !host;
  $('readyStart').disabled = !state.staging.canStart;
  for (const [team, list] of [['blue', $('readyBlue')], ['red', $('readyRed')]]) {
    const lines = state.players.filter(p => p.team === team).map(p =>
      `${p.id === state.playerId ? 'You' : p.id.toUpperCase()}${p.id === state.hostId ? ' (host)' : ''} · ${!p.connected ? 'Rejoining' : p.ready ? 'Ready' : 'Not ready'}`);
    if (!lines.length) lines.push('No players');
    if (list.children.length === lines.length && lines.every((line, i) => list.children[i].textContent === line)) continue;
    list.replaceChildren(...lines.map(line => { const li = document.createElement('li'); li.textContent = line; return li; }));
  }
}
function configureBattlefieldUI() {
  document.body.classList.add('battlefield'); $('mapPanel').querySelector('small').textContent = 'BASES · THREE CROSSINGS'; $('objectiveLabel').textContent = 'SEVEN BASES'; $('objective').setAttribute('aria-label', 'Base ownership and capture progress');
  $('seatName').textContent = 'Commander'; $('controls').textContent = 'W S drive · A D turn · pointer / Space fire · hold RMB look · R recover';
  $('heatLabel').textContent = 'Hull pitch'; $('heatMeter').min = -20; $('heatMeter').max = 20; $('heatMeter').setAttribute('aria-label', 'Hull pitch in degrees');
  $('helpControls').textContent = 'One player controls the whole tank. W/S drive, A/D turn. Pointer controls gun bearing; hull pitch controls resting gun elevation. Space/click fire. R recovers to the depot without clearing captures.';
  if (!multiplayerRequested) {
    $('menuTitle').textContent = 'Battlefield controls';
    $('menuMode').textContent = 'Seven bases';
    $('scene').setAttribute('aria-label', 'Seven-base battlefield. W and S drive, A and D turn, pointer aims, click or Space fires.');
    $('map').setAttribute('aria-label', 'Tactical map. White square: your tank. Numbered bases and three river crossings.');
    $('controls').textContent = 'W S drive · A D turn · pointer aim · click or Space fire · hold RMB look · R recover';
    $('helpControls').textContent = 'W/S drive, A/D turn, pointer aims, click or Space fires. Hull pitch sets gun elevation. R returns to the depot and keeps captures. The menu releases controls; the battlefield keeps running.';
  }
  $('helpTerrain').textContent = 'Deep water is non-drivable. Use the three bridges. Hold a numbered base to capture gradually. Empty progress is retained; equal teams stall; net opponents reverse progress. Practice targets are near the depot. Stationary red posts contest bases 5 and 7; destroy them to gain advantage.';
  $('resetTrial').hidden = false; $('resetTrial').textContent = 'Recover to depot (R)'; $('restartBattle').hidden = false;
  $('resultTitle').textContent = 'Seven bases secured'; $('resultDescription').textContent = 'All seven bases reached the blue ownership endpoint.'; $('replay').textContent = 'Restart battlefield'; $('resultClose').textContent = 'Close';
  showStatus('Hold base 1 at the depot, then choose a bridge route. Deep water blocks the tank.', 8);
}
function updateBattleControlCopy(finished = false) {
  if (finished) {
    $('controls').textContent = 'Match complete · Hold right mouse to look · Esc for menu';
    $('helpControls').textContent = 'Driving, aiming, firing and respawn are off. Close the menu to look around. The host can open the next ready room.';
    return;
  }
  $('controls').textContent = 'W S drive · A D turn · pointer / Space fire · hold RMB look · R respawn (5s)';
  $('helpControls').textContent = 'W/S drive. A/D turn. Pointer or arrows aim; click/Space fires. Each player controls an independent tank. R abandons your hull and starts a five-second respawn.';
  if (!soloRequested) $('helpControls').textContent += ' The menu keeps your controls inactive and does not pause the match.';
}
function configureMultiplayerUI() {
  document.body.classList.add('multiplayer-markers'); $('mapLegend').hidden=false; $('mapLegend').textContent=MARKER_LEGEND;
  $('map').setAttribute('aria-label','Tactical map. Squares Blue, triangles Red, diamonds neutral bases; ring your tank; cross offline. All tank locations are shared.'); $('map').setAttribute('aria-describedby','mapLegend');
  $('seatName').textContent = 'Your tank'; $('battleStatus').hidden = false;
  updateBattleControlCopy();
  if (!soloRequested) {
    $('menuTitle').textContent = 'Battle controls';
    $('menuMode').textContent = online4v4Requested ? 'Online 4v4' : 'Legacy 2v2';
  }
  $('helpTerrain').textContent = 'Blue and Red compete for seven bases. Living connected grounded tanks capture gradually; equal teams stall, net opponents reverse. Score is current bases owned. Three hit points, four-second reload, five-second respawn. Friendly hulls block shots. All tank locations are shared; terrain blocks shells. Use the three bridges; deep water is impassable.';
  $('resetTrial').textContent = 'Request respawn (R)'; $('resetTrial').hidden = true; $('restartBattle').hidden = true;
  $('replay').textContent = 'Restart finished match'; $('resultClose').textContent = 'View battlefield';
  if (online4v4Requested) {
    document.body.classList.add('online-4v4');
    $('replay').textContent = 'Open ready room'; $('restartBattle').textContent = 'Open ready room';
  }
  showStatus('Drive and aim your own tank. Advance onto the crossing to contest base 4.', 8);
}
function configureSoloUI(){
  $('scene').setAttribute('aria-label','Single-player tank battle. W S drive, A D turn, pointer aim, Space fire, Escape pause.');
  $('room').textContent='SINGLE-PLAYER 4v4';$('menuTitle').textContent='Battle paused';
  $('disconnect').hidden=true;$('reconnect').hidden=true;$('fresh').textContent='End battle';
  $('seatHelp').textContent='You control the blue tank. Three AI allies fight four AI enemies. Opening this menu pauses every tank. Closing it resumes.';
  $('helpControls').textContent='W/S drive · A/D turn · pointer or arrows aim · click/Space fire · hold right mouse to look around · R respawn · Escape pause.';
  $('helpTerrain').textContent='Use the three bridges; deep water blocks driving. Trees block shells at their trunks; foliage gives no stealth. Hold a base to capture; opposing tanks reverse progress. Take all seven to win. Three hull points, four-second reload, five-second respawn.';
  $('restartBattle').hidden=false;$('restartBattle').textContent='Restart battle';$('replay').textContent='Play again';
  $('menuMode').textContent='Offline battle';
  showStatus('Blue team. Hold a numbered base to capture it; your allies are already moving.',8);
}
$('restartBattle').onclick = () => { if (battlefieldMode) { release(); send({ type: 'restart' }); menu(false); } };
function configureSlopeUI() {
  $('scene').setAttribute('aria-label', 'Slope driving trial. W forward, S reverse, A and D turn, release both controls to brake, R reset.');
  $('seatName').textContent = role === 'driver' ? 'Driver' : 'Observer';
  $('objectiveLabel').textContent = 'SLOPE DRIVE';
  $('objective').setAttribute('aria-label', 'Slope drive progress');
  $('targetProgress').hidden = true; $('mapToggle').hidden = true; $('mapPanel').hidden = true;
  $('heatLabel').textContent = 'Hull pitch'; $('heatMeter').min = -20; $('heatMeter').max = 20;
  $('heatMeter').setAttribute('aria-label', 'Hull pitch in degrees');
  $('weaponLabel').textContent = 'Ground rise'; $('reloadMeter').max = 3.5;
  $('reloadMeter').setAttribute('aria-label', 'Ground rise in metres');
  $('controls').textContent = role === 'driver' ? 'W S drive · A D turn · release both to brake · R reset' : 'Watching the driver · controls disabled';
  $('helpControls').textContent = 'W / S forward and reverse. A / D turn, including at rest. Release both controls to brake. R returns the tank to its start pad. The observer can watch or reconnect.';
  $('helpTerrain').textContent = '3.5 m ridge, approximately 10° ramps. Assisted steering trial: turn around or reverse home. Weapons, mud and heat are disabled.';
  $('resetTrial').hidden = role !== 'driver'; $('replay').hidden = role !== 'driver';
  $('resultTitle').textContent = 'Drive complete';
  $('resultDescription').textContent = 'Ridge crossed and return to start completed.';
  $('replay').textContent = 'Drive again'; $('resultClose').textContent = 'Close';
  showStatus('Pass between the far posts, then turn around or reverse between the start posts. Release both controls to brake.', 8);
}
function resetTrial() {
  if (multiplayerRequested && (!seated || $('resetTrial').hidden)) return;
  if ((slopeMode && role === 'driver') || (battlefieldMode && role === 'commander')) { release(); clearanceHUD.reset(performance.now()); send({ type: 'reset' }); menu(false); }
}
$('resetTrial').onclick = resetTrial;
function menu(open) {
  release(); $('menu').hidden = !open; $('menuToggle').setAttribute('aria-expanded', String(open));
  if (open && battlefieldMode && (!multiplayerRequested || online4v4Requested)) $('menuBody').scrollTop = 0;
  if(soloRequested){document.body.classList.toggle('offline-paused',open);send({type:'pause',paused:open});}
  (open ? $('menuClose') : $('scene')).focus();
}
$('menuToggle').onclick = () => menu($('menu').hidden);
$('menuClose').onclick = () => menu(false);
$('mapToggle').onclick = () => {
  $('mapPanel').hidden = !$('mapPanel').hidden;
  $('mapToggle').setAttribute('aria-expanded', String(!$('mapPanel').hidden)); $('scene').focus();
};
$('resultClose').onclick = () => { $('result').hidden = true; $('scene').focus(); };
$('replay').onclick = () => { release(); pointerBearing = undefined; if (slopeMode) clearanceHUD.reset(performance.now()); send({ type: 'restart' }); };
try {
  const saved = JSON.parse(sessionStorage.getItem(sessionKey));
  if (saved && !soloRequested) { session = saved; rejoinSavedTank(); }
} catch { sessionStorage.removeItem(sessionKey); }

function playable() { return seated && session && (!online4v4Requested || state?.staging?.waiting === false) && $('menu').hidden && $('result').hidden && !document.hidden && !hangar.visible; }
function release() {
  lookBinding?.cancel(true); combatFX?.reset(); previousHealth=undefined;
  keys.clear(); pointerFire = false; pointerBearing = undefined;
  if (session) send({ type: 'input', input: role === 'commander' ? { throttle: 0, steer: 0, aim: 0, fire: false, spot: false } : role === 'driver' ? { throttle: 0, steer: 0 } : { aim: 0, fire: false, spot: false } });
}
addEventListener('keydown', event => {
  if (event.code === 'Escape' && session && $('readyRoom').hidden && !$('hud').hidden) {
    event.preventDefault();
    if (!event.repeat) menu($('menu').hidden);
    return;
  }
  if (['INPUT', 'SELECT', 'BUTTON'].includes(event.target.tagName) || !playable()) return;
  if (event.code === 'KeyR' && (slopeMode || battlefieldMode)) { event.preventDefault(); if (!event.repeat) resetTrial(); return; }
  if (['Space', 'ArrowLeft', 'ArrowRight', 'KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyE', 'ShiftLeft', 'ShiftRight'].includes(event.code)) {
    event.preventDefault();
    // A repeat cannot reacquire a control cleared by a menu, focus change, or reconnect.
    if (event.repeat && !keys.has(event.code)) return;
    if (event.code.startsWith('Arrow')) pointerBearing = undefined;
    keys.add(event.code); input();
  }
});
addEventListener('keyup', event => { keys.delete(event.code); input(); });
$('scene').addEventListener('blur', () => {
  if (keys.size || pointerFire || pointerBearing !== undefined || freeLook.held) release();
});
addEventListener('blur', release);
document.addEventListener('visibilitychange', () => { socket?.setVisible?.(!document.hidden); if (document.hidden) {release();if(soloRequested&&seated)menu(true);} });
const raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2(), aimPoint = new THREE.Vector3();
const aimPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -1);
function pointerAim(event) {
  if (freeLook.held || event.buttons&2 || slopeMode || !['gunner', 'commander'].includes(role) || !state || !playable()) return;
  const rect = $('scene').getBoundingClientRect();
  pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
  raycaster.setFromCamera(pointer, camera);
  const hit = battlefieldMode && battleView ? raycaster.intersectObjects([...battleView.terrainMeshes, ...battleView.bridgeMeshes], false)[0] : null;
  if (hit) aimPoint.copy(hit.point);
  if (hit || (!battlefieldMode && raycaster.ray.intersectPlane(aimPlane, aimPoint)))
    pointerBearing = Math.atan2(aimPoint.x - state.tank.x, aimPoint.z - state.tank.z) / Math.PI;
}
$('scene').addEventListener('pointermove', pointerAim);
lookBinding=bindFreeLook({canvas:$('scene'),global:window,doc:document,control:freeLook,active:()=>battlefieldMode&&playable()&&(!multiplayerRequested||state?.players.find(p=>p.id===state.playerId)?.health>0)});
$('scene').addEventListener('mousedown', event => {
  if(event.button!==0)return;
  $('scene').focus(); if(!freeLook.held)pointerAim(event);
  if (!slopeMode && event.button === 0 && ['gunner', 'commander'].includes(role) && playable()) { pointerFire = true; input(); }
});
addEventListener('mouseup', event => { if(event.button===0){pointerFire = false; input();} });
addEventListener('pointercancel', () => { pointerFire=false;input(); });
function input() {
  if (!playable()) return;
  const axis = (a, b) => Number(keys.has(a)) - Number(keys.has(b));
  const fine = keys.has('ShiftLeft') || keys.has('ShiftRight') ? 0.2 : 1;
  const command = role === 'commander' ? { throttle: axis('KeyW', 'KeyS'), steer: axis('KeyA', 'KeyD'), aim: axis('ArrowLeft', 'ArrowRight') * fine, fire: pointerFire || keys.has('Space'), spot: false } : role === 'driver'
    ? { throttle: axis('KeyW', 'KeyS'), steer: axis('KeyA', 'KeyD') }
    : { aim: axis('ArrowLeft', 'ArrowRight') * fine, fire: pointerFire || keys.has('Space'), spot: keys.has('KeyE') };
  if (slopeMode && role === 'gunner') return;
  if (['gunner', 'commander'].includes(role) && pointerBearing !== undefined) command.bearing = pointerBearing;
  send({ type: 'input', input: command });
}
setInterval(input, 50);

function updateHUD() {
  updateReadyRoom();
  if (multiplayerRequested) $('resetTrial').hidden = !!(state.won || state.staging?.waiting);
  const t = state.tank;
  const presentationReady=combatFX?.timeline.ready;
  if(combatFX){
    if(seated&&$('menu').hidden&&!document.hidden&&!hangar.visible)combatFX.timeline.accept({time:state.time,won:state.won,players:presentationPlayers(),viewerId:multiplayerRequested?state.playerId:'solo'},performance.now()/1000,reducedMotion.matches);
    else combatFX.reset();
    const health=multiplayerRequested?state.players.find(p=>p.id===state.playerId)?.health:3;
    if(previousHealth!==undefined&&(previousHealth>0)!==(health>0))lookBinding.cancel();
    previousHealth=health;
  }
  $('speed').textContent = Math.abs(t.speed * 3.6).toFixed(0);
  $('terrain').textContent = (t.speed < -0.1 ? 'REV · ' : '') + t.terrain.toUpperCase();
  $('heat').textContent = t.heat.toFixed(0) + '%' + (t.heat > 80 ? ' LIMITED' : '');
  $('heatMeter').value = t.heat; $('instruments').classList.toggle('hot', t.heat > 80);
  $('reload').textContent = t.reload > 0 ? t.reload.toFixed(1) + 's' : 'Ready';
  $('reloadMeter').value = 1 - t.reload / 4;
  $('targets').textContent = state.targets.filter(target => target.hp === 0).length + ' / 3';
  if (slopeMode) {
    $('heat').textContent = (t.pitch >= 0 ? '+' : '') + t.pitch.toFixed(1) + '°'; $('heatMeter').value = t.pitch;
    $('reload').textContent = t.groundHeight.toFixed(1) + 'm'; $('reloadMeter').value = t.groundHeight;
    $('targets').textContent = state.trial.stage === 'outbound' ? 'Cross ridge' : state.trial.stage === 'return' ? 'Return to start' : 'Complete';
  }
  $('crew').textContent = battlefieldMode ? 'SOLO · commander ' + (state.seats.commander?.connected ? 'online' : 'rejoining') : ['driver', 'gunner'].map(r => (slopeMode && r === 'gunner' ? 'observer' : r) + ': ' + (state.seats[r]?.connected ? 'online' : state.seats[r] ? 'rejoining' : 'empty')).join(' · ');
  if (battlefieldMode) { $('heat').textContent = (t.pitch >= 0 ? '+' : '') + t.pitch.toFixed(1) + '°'; $('heatMeter').value = t.pitch; updateBattlefieldHUD(document, state); for (const b of state.capture.bases) battleView?.flags.get(b.id)?.material.color.setHex(b.owner === 'blue' ? 0x98c6df : b.owner === 'red' ? 0xe49380 : 0xdfd8b8); }
  if (multiplayerView) {
    const own=multiplayerView.update(state);tank.visible=own.health>0;battleView.markers.update(state.capture.bases);
    if (online4v4Requested) {
      const cue = $('nearbyBase'), text = nearbyBaseStatus(state, own);
      if (cue.textContent !== text) cue.textContent = text;
    }
  }
  if (online4v4Requested) {
    $('restartBattle').hidden = !state.won || state.hostId !== state.playerId;
    if (state.won !== wasWon) updateBattleControlCopy(state.won);
  }
  if (!battlefieldMode) $('targetProgress').replaceChildren(...state.targets.map(target => {
    const node = document.createElement('span'); node.className = 'target-health' + (target.hp === 0 ? ' dead' : '');
    node.append('0' + target.id);
    const health = document.createElement('b'); health.textContent = target.hp ? '●'.repeat(target.hp) + '○'.repeat(3 - target.hp) : '✓';
    node.append(health); node.setAttribute('aria-label', 'Target ' + target.id + ': ' + (target.hp ? target.hp + ' hits remaining' : 'destroyed'));
    return node;
  }));
  for (const target of state.targets) {
    if (!targets.has(target.id)) {
      const group = new THREE.Group(); group.position.set(target.x, battlefieldMode ? target.y - 1 : 0, target.z); scene.add(group);
      box(3, 2, 1, 0xa76b3e, 0, 1, 0, group);
      box(1.4, 1.4, 0.05, 0xf1d5a2, 0, 1, -0.53, group); targets.set(target.id, group);
      const label = document.createElement('div'); label.className = 'target-label';
      $('targetLabels').append(label); labels.set(target.id, label);
    }
    const obj = targets.get(target.id); obj.scale.y = target.hp > 0 || battlefieldMode ? 1 : 0.18;
    obj.children[1].material.color.setHex(target.hp === 3 ? 0xf1d5a2 : target.hp === 2 ? 0xd9a34f : target.hp === 1 ? 0xb86136 : 0x383a32);
    const label = labels.get(target.id);
    label.classList.toggle('dead', target.hp === 0);
    label.textContent = battlefieldMode && target.captureTeam ? 'RED POST ' + target.id + (target.hp ? '  ' + '●'.repeat(target.hp) : ' DESTROYED') : target.hp ? '0' + target.id + '  ' + '●'.repeat(target.hp) : '0' + target.id + '  CLEAR';
  }
  if (state.shot && state.shot.id !== lastShot) {
    // Reconnect to a historical shot must not play a fresh effect.
    if ((!combatFX||presentationReady) && state.time - state.shot.time < 0.5) {
      tone(90, 0.5, 0.2); if(!combatFX)effect(state.shot.endX, state.shot.endZ, state.shot.hit ? 0xffb248 : 0xaea288);
      if (!originalVisual && !combatFX) barrel.position.z = 1.8;
      if (!combatFX && originalVisual && [state.shot.x,state.shot.y,state.shot.z,state.shot.endX,state.shot.endY,state.shot.endZ].every(Number.isFinite)) {
        shotTrace.geometry.setFromPoints([new THREE.Vector3(state.shot.x,state.shot.y,state.shot.z),new THREE.Vector3(state.shot.endX,state.shot.endY,state.shot.endZ)]);
      }
      const contact = multiplayerRequested ? state.shot.blocked : soloPresentationShot(state.shot).blocked;
      showStatus(state.shot.hit ? (multiplayerRequested ? 'Enemy ' + state.shot.hit.toUpperCase() + ' hit' : 'Target 0' + state.shot.hit + ' hit')
        : !combatFX ? 'Cover or ground hit — reposition for a clear shot.'
        : contact ? 'Shot blocked — reposition for a clear shot.' : 'No contact.');
    }
    lastShot = state.shot.id;
  }
  if (state.won && !wasWon) { release(); $('result').hidden = false; (slopeMode && role !== 'driver' || multiplayerRequested && state.playerId!==state.hostId ? $('resultClose') : $('replay')).focus(); showStatus(''); }
  if (!state.won && wasWon) { $('result').hidden = true; pointerBearing = undefined; if (!state.staging?.waiting) { $('scene').focus(); showStatus('New run. Crew ready.'); } }
  wasWon = state.won;
  if (!slopeMode) drawMap();
}
function drawMap() {
  if(multiplayerRequested){drawTerritorialMap($('map').getContext('2d'),mapData,state);return;}
  if (battlefieldMode) { const ctx = $('map').getContext('2d'), p = v => 100 + v / mapData.size * 190; ctx.fillStyle = '#3e4d35'; ctx.fillRect(0, 0, 200, 200); ctx.fillStyle = '#356b78'; ctx.fillRect(p(-8), 5, 16 / mapData.size * 190, 190); ctx.fillStyle = '#b5ae96'; for (const b of mapData.bridges) ctx.fillRect(p(-b.w/2), p(b.z-b.d/2), b.w/mapData.size*190, b.d/mapData.size*190); ctx.font = '12px monospace'; for (const b of state.capture.bases) { ctx.fillStyle = b.owner === 'blue' ? '#a8d2ea' : b.owner === 'red' ? '#ef927b' : '#eee9db'; ctx.fillText(b.id, p(b.x)-4, p(b.z)+4); } if(multiplayerRequested)for(const u of state.players){if(!u.health)continue;ctx.fillStyle=u.id===state.playerId?'#fff':u.team==='blue'?'#a8d2ea':'#ef927b';ctx.fillRect(p(u.tank.x)-2,p(u.tank.z)-2,4,4);}else{ctx.fillStyle = '#fff'; ctx.fillRect(p(state.tank.x)-2,p(state.tank.z)-2,4,4);} return; }

  const ctx = $('map').getContext('2d'), pos = value => 100 + value * 2.3;
  ctx.fillStyle = '#27392e'; ctx.fillRect(0, 0, 200, 200);
  ctx.strokeStyle = '#455445'; ctx.lineWidth = 0.5;
  for (let i = 10; i < 200; i += 23) { ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, 200); ctx.moveTo(0, i); ctx.lineTo(200, i); ctx.stroke(); }
  ctx.fillStyle = '#534a36'; const m = mapData.mud; ctx.fillRect(pos(m.x - m.w / 2), pos(m.z - m.d / 2), m.w * 2.3, m.d * 2.3);
  ctx.fillStyle = '#899080'; for (const w of mapData.walls) ctx.fillRect(pos(w.x - w.w / 2), pos(w.z - w.d / 2), w.w * 2.3, w.d * 2.3);
  ctx.fillStyle = '#e0bb70'; ctx.font = '10px monospace';
  for (const p of state.targets) if (p.hp > 0 && p.spottedUntil > state.time) { ctx.beginPath(); ctx.arc(pos(p.x), pos(p.z), 3, 0, Math.PI * 2); ctx.fill(); ctx.fillText(String(p.id), pos(p.x) + 5, pos(p.z)); }
  const t = state.tank; ctx.fillStyle = '#eee9db'; ctx.save(); ctx.translate(pos(t.x), pos(t.z)); ctx.rotate(-t.yaw);
  ctx.beginPath(); ctx.moveTo(0, 7); ctx.lineTo(-4, -4); ctx.lineTo(4, -4); ctx.fill(); ctx.restore();
}
let chaseHeading = 0;
let previous = performance.now(), dust = 0;
const desired = new THREE.Vector3(), projected = new THREE.Vector3(), cameraFocus=new THREE.Vector3();
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const frameCadence = createFrameCadence(), performanceLabel = $('performance');
function syncFrameVisibility() {
  if (!frameCadence.setVisible(!document.hidden)) return;
  performanceLabel.textContent = document.hidden ? 'Frame timing paused (tab hidden)' : 'Measuring frame cadence…';
  for (const key of ['drawCalls','triangles','frameSamples','frameWindowMs','frameP95Ms','frameMaxMs','meanFps']) delete performanceLabel.dataset[key];
}
document.addEventListener('visibilitychange', syncFrameVisibility);
syncFrameVisibility();
function frame(now) {
  requestAnimationFrame(frame);
  clearanceHUD.tick(performance.now());
  hangar.frame();
  const elapsed = now - previous, dt = Math.min(elapsed / 1000, 0.05); previous = now;
  syncFrameVisibility();
  const cadence = frameCadence.observe(now);
  if (cadence) {
    const { count, spanMs, p95Ms, maxMs, meanFps } = cadence;
    performanceLabel.textContent = `Frame p95 ${p95Ms.toFixed(1)} ms · max ${maxMs.toFixed(1)} ms · avg ${meanFps.toFixed(1)} fps`;
    Object.assign(performanceLabel.dataset, { frameSamples: count, frameWindowMs: spanMs, frameP95Ms: p95Ms, frameMaxMs: maxMs, meanFps,
      drawCalls: renderer.info.render.calls, triangles: renderer.info.render.triangles });
  }
  // Use the arrival clock; the rAF timestamp can predate a just-received shot.
  const fxTime = performance.now() / 1000, reduceFX = reducedMotion.matches;
  const recoil = combatFX?.timeline.recoil(multiplayerRequested ? state?.playerId : 'solo',fxTime,reduceFX) ?? 0;
  if (state) {
    if (slopeMode || battlefieldMode) {
      const t = state.tank;
      // The mesh's hull centre is local Y=1. Rotate its offset with the physical body.
      tank.quaternion.set(t.quaternion.x, t.quaternion.y, t.quaternion.z, t.quaternion.w);
      desired.set(0, -1, 0).applyQuaternion(tank.quaternion).add(new THREE.Vector3(t.x, t.y, t.z));
      tank.position.copy(desired);
    } else {
      tank.position.lerp(desired.set(state.tank.x, 0, state.tank.z), 1 - Math.exp(-12 * dt));
      tank.rotation.set(0, state.tank.yaw, 0);
    }
    turret.rotation.y = state.tank.turret;
    originalVisual?.pose(state.tank.turret); // Local barrel pitch stays at the authoritative resting angle.
    shotTrace.visible = !!(!combatFX && originalVisual && state.shot && state.time - state.shot.time < .16);
    originalVisual?.recoil(recoil);
    barrel.position.z = combatFX ? barrelRestZ-recoil : THREE.MathUtils.lerp(barrel.position.z, barrelRestZ, dt * 5);
    multiplayerView?.recoil(id=>combatFX.timeline.recoil(id,fxTime,reduceFX));
    for (const wheel of wheels) wheel.rotation.x += state.tank.speed * dt;
    dust += dt;
    if (!combatFX && !slopeMode && dust > 0.18 && Math.abs(state.tank.speed) > 1 && !reducedMotion.matches) {
      dust = 0; effect(tank.position.x - Math.sin(tank.rotation.y) * 2, tank.position.z - Math.cos(tank.rotation.y) * 2, 0x9c987b, 1);
    }
  }
  for (const p of particles) { p.life -= dt; p.mesh.position.addScaledVector(p.v, dt); p.v.y -= 10 * dt; p.mesh.scale.setScalar(Math.max(0, p.life)); }
  particles = particles.filter(p => { if (p.life > 0) return true; scene.remove(p.mesh); p.mesh.geometry.dispose(); p.mesh.material.dispose(); return false; });
  const targetHeading = state?.tank.yaw ?? 0;
  const snapRespawn = onlineRespawnCameraPending && state?.players.find(p => p.id === state.playerId)?.health > 0;
  onlineRespawnCameraPending = false;
  if (snapRespawn) {
    chaseHeading = targetHeading;
    lookBinding.cancel(true);
  } else if (slopeMode || battlefieldMode) chaseHeading += Math.atan2(Math.sin(targetHeading - chaseHeading), Math.cos(targetHeading - chaseHeading)) * (1 - Math.exp(-4 * dt));
  const heading = (slopeMode || battlefieldMode) ? chaseHeading : targetHeading;
  desired.set(tank.position.x - Math.sin(heading) * 20, (slopeMode ? 14 : 22) + tank.position.y, tank.position.z - Math.cos(heading) * 20);
  const look=freeLook.step(dt,reducedMotion.matches);
  cameraFocus.copy(tank.position);cameraFocus.y+=1.4;
  if(battlefieldMode&&look.blend>0){const pitch=LOOK_LIMITS.basePitch+look.pitch,distance=LOOK_LIMITS.distance;desired.set(tank.position.x-Math.sin(heading+look.yaw)*Math.cos(pitch)*distance,tank.position.y+Math.sin(pitch)*distance,tank.position.z-Math.cos(heading+look.yaw)*Math.cos(pitch)*distance);}
  // A new hull appears at its spawn; the camera should not travel from the wreck.
  if (snapRespawn) camera.position.copy(desired);
  else camera.position.lerp(desired, 1 - Math.exp(-4 * dt));
  let guard={clipped:false,clearance:null};
  if(battlefieldMode&&look.blend>0&&battleView)guard=cameraGuard.constrain(cameraFocus,camera.position,[...battleView.terrainMeshes,...battleView.bridgeMeshes,...walls]);
  camera.lookAt(tank.position.x + Math.sin(heading) * (slopeMode ? 8 : 14)*(1-look.blend), tank.position.y, tank.position.z + Math.cos(heading) * (slopeMode ? 8 : 14)*(1-look.blend));
  camera.updateMatrixWorld();
  if(combatFX){
    if(state&&playable())combatFX.timeline.ambient(presentationPlayers(),fxTime,reduceFX);
    combatFX.frame(fxTime,camera);
    Object.assign($('scene').dataset,{lookHeld:String(look.held),lookYaw:String(look.yaw),lookPitch:String(look.pitch),lookBlend:String(look.blend),cameraClipped:String(guard.clipped),cameraClearance:guard.clearance===null?'none':String(guard.clearance),cameraPosition:camera.position.toArray().join(','),fx:JSON.stringify(combatFX.stats()),legacyParticles:String(particles.length),recoil:String(recoil)});
  }
  if(multiplayerRequested)battleView?.markers.face(camera);
  multiplayerView?.frame();
  // Keep solid cover readable but reveal the tank when the chase camera is outside it.
  const occluders = new Set();
  for (const [x, z] of [[0, 0], [-1.85, -2.25], [1.85, -2.25], [-1.85, 2.25], [1.85, 2.25]]) {
    cameraSight.set(x, 0.3, z).applyAxisAngle(THREE.Object3D.DEFAULT_UP, heading).add(tank.position).sub(camera.position);
    cameraRay.far = cameraSight.length();
    cameraRay.set(camera.position, cameraSight.normalize());
    for (const hit of cameraRay.intersectObjects(walls, false)) occluders.add(hit.object);
  }
  for (const wall of walls) {
    wall.material.opacity = occluders.has(wall) ? 0.22 : 1;
    wall.material.depthWrite = !occluders.has(wall);
  }
  if (state) for (const target of state.targets) {
    const label = labels.get(target.id);
    projected.set(target.x, battlefieldMode ? target.y + 1.7 : 2.7, target.z).project(camera);
    label.hidden = $('hud').hidden || projected.z > 1 || Math.abs(projected.x) > 0.98 || Math.abs(projected.y) > 0.98;
    label.style.left = ((projected.x + 1) / 2 * innerWidth) + 'px';
    label.style.top = ((1 - projected.y) / 2 * innerHeight) + 'px';
  }
  if (now > noticeUntil && socket?.readyState === WebSocket.OPEN) $('mission').textContent = '';
  renderer.render(scene, camera);
}
camera.position.set(22, 28, -38); requestAnimationFrame(frame);
addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); });



// Keep room actions disabled until renderer and input handlers are ready.
if(soloRequested){
  const {SOLO_MAP,SOLO_SPAWNS}=await import('./src/solo-map.mjs');
  battlefieldMode=true;setupMap({...SOLO_MAP,mode:'battle'});
  const spawn=SOLO_SPAWNS.blue[0];tank.position.set(spawn.x,spawn.y-1,spawn.z);tank.rotation.y=Math.PI/2;
  camera.position.set(spawn.x+22,spawn.y+28,spawn.z-38);camera.lookAt(tank.position);
}
if (!session) busy(false);

addEventListener('pagehide', () => hangar.dispose());
addEventListener('pagehide',()=>{if(soloRequested)socket?.close();});
