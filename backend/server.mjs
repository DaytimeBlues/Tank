import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomInt, randomBytes, createHash } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { Room, initPhysics } from './src/room.mjs';
import { validateBattleOptions } from './src/battle-room.mjs';
import { battleFormat, createOnlineBattle } from './src/online-battle.mjs';
import { serverConfig, acceptsOrigin, validateOrigins } from './src/server-config.mjs';
import { createHostedTickets, bounded } from './src/hosted-tickets.mjs';
import { GAME_PROTOCOL, hostedScope } from './public/hosted-ticket.mjs';
import { VISUALS } from './public/tank-visual.mjs';

await initPhysics();
const files = { '/': 'public/index.html', '/game.mjs': 'public/game.mjs', '/clearance-hud.mjs': 'public/clearance-hud.mjs', '/battlefield-view.mjs': 'public/battlefield-view.mjs', '/tank-config.mjs': 'public/tank-config.mjs', '/hangar.mjs': 'public/hangar.mjs', '/vendor/Sky.js': 'node_modules/three/examples/jsm/objects/Sky.js', '/style.css': 'public/style.css', '/vendor/three.module.js': 'node_modules/three/build/three.module.js', '/vendor/three.core.js': 'node_modules/three/build/three.core.js' };
Object.assign(files, {
  '/free-look.mjs': 'public/free-look.mjs',
  '/combat-vfx.mjs': 'public/combat-vfx.mjs',
  '/battle-client.mjs': 'public/battle-client.mjs',
  '/battle-connection.mjs': 'public/battle-connection.mjs',
  '/frame-cadence.mjs': 'public/frame-cadence.mjs',
  '/hosted-ticket.mjs': 'public/hosted-ticket.mjs',
  '/licenses/three.txt': 'node_modules/three/LICENSE',
  '/map-markers.mjs': 'public/map-markers.mjs',
  '/tank-visual.mjs': 'public/tank-visual.mjs',
  '/landscape-art.mjs': 'public/landscape-art.mjs',
  '/vendor/loaders/GLTFLoader.js': 'node_modules/three/examples/jsm/loaders/GLTFLoader.js',
  '/vendor/utils/BufferGeometryUtils.js': 'node_modules/three/examples/jsm/utils/BufferGeometryUtils.js',
  '/vendor/utils/SkeletonUtils.js': 'node_modules/three/examples/jsm/utils/SkeletonUtils.js'
},Object.fromEntries(VISUALS.map(v=>[v.url,v.source])));
// Pin served assets and source identity to this process, avoiding mixed hot-edited clients.
const assets = Object.fromEntries(await Promise.all(Object.entries(files).map(async ([url, file]) => {
  try { return [url, await readFile(new URL(file, import.meta.url))]; }
  catch (error) { if (file.endsWith('.glb') && error.code === 'ENOENT') return [url, null]; throw error; }
})));
const assetBytes = new Map(Object.entries(files).map(([url,file])=>[file,assets[url]]));
const fingerprint = createHash('sha256');
for (const file of ['server.mjs', 'src/online-battle.mjs', 'src/server-config.mjs', 'src/hosted-tickets.mjs', 'src/private-access.mjs', 'deploy/render-entry.mjs', 'src/solo-map.mjs', 'src/room.mjs', 'src/battle-room.mjs', 'src/session-token.mjs', 'src/grade-drive.mjs', 'src/suspension.mjs', 'src/terrain-query.mjs', 'src/battlefield-map.mjs', 'src/battlefield-drive.mjs', 'src/capture.mjs', 'package-lock.json', ...Object.values(files)]) {
  fingerprint.update(file);
  fingerprint.update(assetBytes.has(file) ? assetBytes.get(file) ?? 'missing optional visual' : await readFile(new URL(file, import.meta.url)));
}
const build = fingerprint.digest('hex');
const PROBE_MS = 4000;
export function createGameServer({ networkMode = 'local', allowedOrigins = [], hostedProvider = null, hostedAccess = null } = {}) {
  if (!['local', 'hosted'].includes(networkMode)) throw new Error('Unknown network mode');
  if (hostedAccess && (networkMode !== 'hosted' || hostedAccess !== hostedProvider)) throw new Error('Invalid private hosted access adapter');
  allowedOrigins = validateOrigins(allowedOrigins);
  const hosted = networkMode === 'hosted' ? createHostedTickets(hostedProvider, allowedOrigins) : null;
  const hostedMarkup = hosted ? assets['/'].toString('utf8').replace('<html lang="en">','<html lang="en" data-network="hosted">') : null;
  const accessLink = '<a href="/access" target="_blank" rel="noopener">Private access</a>';
  const hostedHtml = hostedMarkup ? Buffer.from(hostedAccess ? hostedMarkup
    .replace('<p id="status"', '<p>'+accessLink+'</p><p id="status"')
    .replace('<div id="menuBody">','<div id="menuBody"><p>'+accessLink+'</p>') : hostedMarkup) : null;
  const stopping = new AbortController(), owners = new WeakMap();
  let closing = false, closePromise;
  const rooms = new Map(), accessLeases = new WeakMap();
  async function issueTicket(req, res) {
    const answer = (status, value) => {
      if (!res.destroyed && !res.writableEnded) {
        const closeRequest=hostedAccess && status>=400;
        res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
          ...(closeRequest ? { Connection: 'close' } : {}) });
        res.end(JSON.stringify(value), () => { if (closeRequest && !req.complete) req.destroy(); });
      }
    };
    if (closing) return answer(503, { error: 'Hosted ticket unavailable' });
    if (req.method !== 'POST' || req.headers['content-type'] !== 'application/json') return answer(400, { error: 'Invalid ticket request' });
    const origin = req.headers.origin;
    if (origin !== hosted.audience) return answer(403, { error: 'Origin not allowed' });
    const peer = new AbortController();
    res.once('close', () => peer.abort());
    const signal = AbortSignal.any([stopping.signal, peer.signal, AbortSignal.timeout(2000)]);
    let reading = true;
    const stopRead = () => { if (reading) req.destroy(); };
    signal.addEventListener('abort', stopRead, { once: true });
    try {
      const scope = await bounded(async () => {
        let size = 0; const chunks = [];
        const stream = hostedAccess ? req.iterator({destroyOnReturn:false}) : req;
        for await (const chunk of stream) {
          size += chunk.length;
          if (size > 512) return null;
          chunks.push(chunk);
        }
        reading = false;
        try {
          const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          return Object.keys(body).length === 2 ? hostedScope(body.action, body.room) : null;
        } catch { return null; }
      }, signal);
      if (!scope) return answer(400, { error: 'Invalid ticket request' });
      const ticket = await bounded(() => hosted.issue(req, scope, origin, signal), signal);
      return ticket ? answer(200, { ticket }) : answer(401, { error: 'Hosted ticket unavailable' });
    } catch { return answer(503, { error: 'Hosted ticket unavailable' }); }
    finally { signal.removeEventListener('abort', stopRead); }
  }
  const server = http.createServer(hostedAccess ? {
    headersTimeout: 5000, requestTimeout: 10000, connectionsCheckingInterval: 1000, maxHeaderSize: 8192,
  } : {}, async (req, res) => {
    let path;
    try { path = new URL(req.url, 'http://localhost').pathname; }
    catch { res.writeHead(400, { 'Cache-Control': 'no-store' }); return res.end(); }
    if (path === '/health') { res.writeHead(closing ? 503 : 200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); return res.end(JSON.stringify({ project: 'tank-battle', version: '0.1.0', build, ready: !closing, networkMode })); }
    if (hostedAccess) {
      if (closing) { res.writeHead(503, { 'Cache-Control': 'no-store' }); return res.end(); }
      try { if (!await hostedAccess.handleHttp(req, res, path)) return; }
      catch { if (!res.destroyed && !res.writableEnded) { res.writeHead(503, { 'Cache-Control': 'no-store' }); res.end(); } return; }
    }
    if (hosted && req.url === '/connection-ticket') return issueTicket(req, res);
    const file = files[path];
    if (!file) { res.writeHead(404); return res.end('Not found'); }
    try {
      const body = path === '/' && hosted ? hostedHtml : assets[path];
      if (body === null) { res.writeHead(404, { 'Cache-Control': 'no-store' }); return res.end('Optional visual unavailable'); }
      res.writeHead(200, { 'Content-Type': file.endsWith('.glb') ? 'model/gltf-binary' : file.endsWith('.html') ? 'text/html' : file.endsWith('.css') ? 'text/css' : file.endsWith('.txt') ? 'text/plain; charset=utf-8' : 'text/javascript', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(body);
    } catch { res.writeHead(500); res.end('Unable to load game file'); }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 2048,
    handleProtocols: protocols => hosted ? GAME_PROTOCOL : protocols.values().next().value });
  const pendingUpgrades = new Set();
  server.on('upgrade', async (req, socket, head) => {
    socket.on('error', () => {});
    const reject = status => {
      const response = `HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`;
      if (hostedAccess) socket.end(response, () => socket.destroy());
      else socket.end(response);
    };
    if (closing || hostedAccess && pendingUpgrades.size >= 32) return reject('503 Service Unavailable');
    pendingUpgrades.add(socket); socket.once('close', () => pendingUpgrades.delete(socket));
    if (req.url !== '/') return reject('404 Not Found');
    if (!acceptsOrigin(req.headers.origin, req.headers.host, { networkMode, allowedOrigins })) return reject('403 Forbidden');
    let admission, context, upgraded=false;
    try {
      if (hosted) {
        if (req.method !== 'GET' || req.headers.upgrade?.toLowerCase() !== 'websocket' || req.headers['sec-websocket-version'] !== '13' ||
            !/^[+/0-9A-Za-z]{22}==$/.test(req.headers['sec-websocket-key'] ?? '')) return reject('400 Bad Request');
        if (hostedAccess) {
          context = hostedAccess.startUpgrade(req);
          if (context.status) return reject(context.status === 429 ? '429 Too Many Requests' : context.status === 403 ? '403 Forbidden' : '401 Unauthorized');
        }
        const peer = new AbortController();
        socket.once('close', () => peer.abort());
        const signal = AbortSignal.any([stopping.signal, peer.signal, AbortSignal.timeout(2000)]);
        admission = await bounded(() => hosted.admit(req.headers['sec-websocket-protocol'], req.headers.origin, signal, context), signal);
        if (!admission || hostedAccess && (!hostedAccess.active(context.lease) || admission.subject !== context.lease.subject)) return reject('401 Unauthorized');
      }
      if (closing || socket.destroyed) return reject('503 Service Unavailable');
      wss.handleUpgrade(req, socket, head, ws => {
        upgraded=true;
        if (context) socket.once('close', context.release); // Hold private socket capacity until disconnect.
        wss.emit('connection', ws, admission, context);
      });
      pendingUpgrades.delete(socket);
    } catch { reject('401 Unauthorized'); }
    finally { if (!upgraded) context?.release?.(); }
  });
  const send = (socket, data) => { if (socket.readyState === WebSocket.OPEN && socket.bufferedAmount < 65536) socket.send(JSON.stringify(data)); };
  const heartbeat = setInterval(() => {
    const now = performance.now();
    for (const socket of wss.clients) {
      if (hostedAccess && !hostedAccess.active(accessLeases.get(socket))) {
        if (socket.readyState === WebSocket.OPEN) socket.close(1008, 'Session expired');
        continue;
      }
      const probe = socket.binding?.probe;
      if (!probe || socket.readyState !== WebSocket.OPEN || now < probe.due) continue;
      if (probe.nonce) { socket.terminate(); continue; }
      probe.nonce = randomBytes(8);
      probe.due = now + PROBE_MS;
      socket.ping(probe.nonce);
    }
  }, 500);
  wss.on('connection', (socket, admission, context) => {
    if (hostedAccess) accessLeases.set(socket, context.lease);
    let binding = null, messages = 0;
    let firstAdmission = admission;
    const ticketExpiry = admission && setTimeout(() => socket.close(1008, 'Ticket expired'), Math.max(0, admission.expiresAt - Date.now()));
    const rate = setInterval(() => { messages = 0; }, 1000);
    socket.on('error', () => {});
    socket.on('pong', data => {
      const probe = binding?.probe, now = performance.now();
      if (!probe?.nonce?.equals(data) || now >= probe.due) return;
      probe.nonce = null;
      probe.due = now + PROBE_MS;
    });
    socket.on('message', raw => {
      if (socket.readyState !== WebSocket.OPEN) return;
      if (hostedAccess && !hostedAccess.active(context.lease)) return socket.close(1008, 'Session expired');
      try {
        if (++messages > 80) return socket.close(1008, 'Rate limit');
        const msg = JSON.parse(raw.toString());
        if (!msg || typeof msg !== 'object') throw new Error('Invalid message');
        if (msg.type === 'leave') {
          if (!binding) throw new Error('Join a room first');
          binding.room.leave(binding.token);
          binding = null; socket.binding = null;
          send(socket, { type: 'left' });
          if (hosted) socket.close(1000, 'Seat released');
          return;
        }
        if (msg.type === 'restart' || msg.type === 'reset') {
          if (!binding) throw new Error('Join a room first');
          if (msg.type === 'reset') binding.room.resetTrial(binding.token);
          else binding.room.restart(binding.token);
          return;
        }
        if (msg.type === 'ready' || msg.type === 'start' || msg.type === 'switchTeam') {
          if (!binding) throw new Error('Join a room first');
          if (binding.room.format !== '4v4') throw new Error('Ready rooms are for online 4v4');
          if (msg.type === 'ready') binding.room.setReady(binding.token, msg.ready);
          else if (msg.type === 'switchTeam') binding.room.switchTeam(binding.token, msg.team);
          else binding.room.start(binding.token);
          return;
        }
        if (msg.type === 'input') {
          if (!binding) throw new Error('Join a room first');
          binding.room.command(binding.token, msg.input); return;
        }
        if (binding) throw new Error('Already seated');
        if (!['create', 'join', 'reconnect'].includes(msg.type)) throw new Error('Unknown message');
        if (hosted) {
          const scope = hostedScope(msg.type, msg.type === 'create' && msg.code === undefined ? null : msg.code);
          if (!firstAdmission || Date.now() >= firstAdmission.expiresAt || !scope || scope.action !== firstAdmission.action ||
              scope.room !== firstAdmission.room || msg.mode !== 'battle' || msg.format !== '4v4' ||
              hostedAccess && !hostedAccess.permits(context.lease, scope, context.generation)) {
            send(socket, { type: 'error', message: 'Ticket does not permit this action' });
            socket.close(1008, 'Ticket scope'); return;
          }
          firstAdmission = null; // One admission attempt, including failed join or reconnect.
        }
        let code = String(msg.code ?? '').toUpperCase();
        let room;
        if (msg.type === 'create') {
          if (!(['battlefield', 'battle'].includes(msg.mode) ? ['commander'] : ['driver', 'gunner']).includes(msg.role)) throw new Error('Unknown role');
          if (msg.mode === 'battle') { validateBattleOptions(msg); battleFormat(msg.format); }
          if (rooms.size >= 24) throw new Error('Server full');
          do { code = randomInt(0, 36 ** 6).toString(36).padStart(6, '0').toUpperCase(); } while (rooms.has(code));
          room = msg.mode === 'battle' ? createOnlineBattle({ tankId: msg.tankId, format: msg.format }) : new Room({ mode: msg.mode, tankId: msg.tankId }); rooms.set(code, room);
        } else { room = rooms.get(code); if (!room) throw new Error('Room not found'); }
        // Reject the requested view before allocating or reconnecting a seat.
        // Older range clients omit mode; slope clients must explicitly opt in.
        if ((msg.mode ?? 'range') !== room.mode) throw new Error('Room mode mismatch. Open the matching range, slope, solo or battle link.');
        if (room.mode === 'battle' && battleFormat(msg.format) !== room.format) throw new Error('Room format mismatch. Open the matching 2v2 or 4v4 link.');
        let token, role;
        if (msg.type === 'reconnect') {
          if (hosted && owners.get(room.seat(msg.token)[1]) !== admission.subject) {
            throw Object.assign(new Error('Invalid session'), { code: 'SESSION_INVALID' });
          }
          room.reconnect(msg.token); token = msg.token; role = room.mode === 'battle' ? 'commander' : room.seat(token)[0];
        } else {
          if (hosted && Object.values(room.seats).some(player => owners.get(player) === admission.subject)) {
            throw new Error('This identity already has a tank in the room');
          }
          role = msg.role; token = room.join(role, msg);
          if (hosted) owners.set(room.seat(token)[1], admission.subject);
        }
        if (hostedAccess && msg.type === 'create') hostedAccess.roomOpened(code);
        clearTimeout(ticketExpiry);
        binding = { code, room, token, ...(room.format === '4v4' ? { probe: { due: performance.now() + PROBE_MS, nonce: null } } : {}) };
        socket.binding = binding;
        send(socket, { type: 'joined', code, role, token, map: room.map, ...(room.mode === 'battle' ? room.identity(token) : {}) });
        send(socket, { type: 'state', ...room.snapshot(token) });
      } catch (error) {
        send(socket, { type: 'error', message: error.message, ...(error.code ? { code: error.code } : {}) });
        if (hosted && !binding) socket.close(1000, 'Admission rejected');
      }
    });
    socket.on('close', () => { clearInterval(rate); clearTimeout(ticketExpiry); if (binding) { try { binding.room.disconnect(binding.token); } catch {} } });
  });
  let previous = performance.now(), accumulator = 0;
  const tick = setInterval(() => {
    const now = performance.now();
    accumulator += Math.min(0.25, (now - previous) / 1000);
    previous = now;
    let steps = 0;
    while (accumulator >= 1 / 30) {
      for (const [code, room] of rooms) {
        room.step(1 / 30);
        if (room.time > 30 && Object.keys(room.seats).length === 0) { room.dispose(); rooms.delete(code); hostedAccess?.roomClosed(code); }
      }
      accumulator -= 1 / 30; steps++;
    }
    if (!steps) return;
    for (const socket of wss.clients) if (socket.binding && (!hostedAccess || hostedAccess.active(accessLeases.get(socket)))) send(socket, { type: 'state', ...socket.binding.room.snapshot(socket.binding.token) });
  }, 16);
  return { server, close() {
    if (closePromise) return closePromise;
    closing = true; stopping.abort(); clearInterval(tick); clearInterval(heartbeat);
    for (const socket of pendingUpgrades) socket.destroy(); pendingUpgrades.clear();
    closePromise = (async () => {
      const stopped = new Promise(resolve => server.close(resolve));
      for (const socket of wss.clients) socket.close(1001, 'Server shutting down');
      const deadline = setTimeout(() => { for (const socket of wss.clients) socket.terminate(); server.closeAllConnections(); }, 1000);
      await new Promise(resolve => wss.close(resolve)); await stopped; clearTimeout(deadline);
      for (const room of rooms.values()) room.dispose(); rooms.clear();
    })();
    return closePromise;
  } };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = serverConfig(), game = createGameServer(config);
  game.server.listen(config.port, config.host, () => console.log(`Tank Battle: http://${config.host}:${game.server.address().port}`));
  const shutdown = () => { game.close().catch(() => { process.exitCode = 1; }); };
  process.once('SIGTERM', shutdown); process.once('SIGINT', shutdown);
}
