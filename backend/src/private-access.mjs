import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';

const COOKIE = '__Host-tank-session', GAME = '/?battle=1&format=4v4';
const HOUR = 3_600_000, SESSION_MS = 8 * HOUR, INVITE_MS = 15 * 60_000, TICKET_MS = 25_000;
const GUESTS = 7, TICKETS = 128, MAX_RATE_KEYS = 512;
const rates = { login:[120,60], manage:[90,60,45], ticket:[160,100,30], upgrade:[220,140,40] };
const concurrency = { login:[12,4], manage:[12,4,2], ticket:[20,8,3], upgrade:[24,10,3] };
const hash = value => createHash('sha256').update(value).digest('hex');
const fresh = bytes => randomBytes(bytes).toString('base64url');
const exactHeader = (req, name) => req.headersDistinct?.[name]?.length === 1 ? req.headersDistinct[name][0] : null;
const keyFormat = /^[A-Za-z0-9_-]{43}$/;
const formType = 'application/x-www-form-urlencoded';
const sessionCookie = (key, age) => COOKIE+'='+key+'; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age='+age;
const privacyHeaders = {
 'Cache-Control':'no-store', 'Referrer-Policy':'same-origin', 'X-Content-Type-Options':'nosniff',
 'X-Frame-Options':'DENY', 'Cross-Origin-Resource-Policy':'same-origin',
};
const intro = '<p>Private online 4v4. Each invited player controls one tank.</p>';
const form = (label, type) => '<form method="post" action="/access/login"><input type="hidden" name="type" value="'+type+
 '"><label>'+label+' <input name="code" type="password" required maxlength="65" autocomplete="off"></label><button>Sign in</button></form>';
const loginPage = intro+form('Invite code','guest')+form('Host key','host')+'<p><a href="'+GAME+'">Continue if already signed in</a></p>';
const signOut = '<form method="post" action="/access/logout"><button>Sign out</button></form>';
const guestPage = intro+'<p><a href="'+GAME+'">Open Online 4v4</a> · <a href="/licenses/three.txt">Three.js notice</a></p>'+signOut;
const hostPage = intro+'<p>Send each guest their own invite through your approved private channel. Share the room code separately after creating the match. Invites expire in 15 minutes.</p>'+
 '<form method="post" action="/access/invite"><button>Create one invite</button></form><p><a href="'+GAME+'">Open Online 4v4</a> · <a href="/licenses/three.txt">Three.js notice</a></p>'+
 signOut;
const page = body => '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Tank Battle private access</title><main><h1>Tank Battle</h1>'+body+'</main></html>';
function pass(res) {
 for(const [name,value] of Object.entries(privacyHeaders))res.setHeader(name,value);
 return true;
}
function reply(res, status, body='', extra={}) {
 if (!res.destroyed && !res.writableEnded) {
  res.writeHead(status, {...privacyHeaders,'Content-Type':'text/html; charset=utf-8',
   'Content-Security-Policy':"default-src 'none'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",...(status>=400?{Connection:'close'}:{}),...extra});
  res.end(body);
 }
 return false;
}
async function formBody(req) {
 const declared=exactHeader(req,'content-length');
 if (exactHeader(req,'content-type')!==formType || declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>256)) return null;
 const timer=setTimeout(()=>req.destroy(),2000);
 try {
  let length=0;const parts=[];
  for await (const b of req.iterator({destroyOnReturn:false})) {
   length+=b.length;if(length>256)return null;
   parts.push(b);
  }
  if(!req.complete)return null;
  return new URLSearchParams(Buffer.concat(parts).toString('utf8'));
 }catch{return null;}
 finally{clearTimeout(timer);}
}

// Every capability is admitted only by the boot that minted it. Rotation is
// invalidation: no old record is reloaded or derivable from the host key.
export function createPrivateAccess({ audience, hostKeyDigest, now=Date.now }) {
 const expectedHost=new URL(audience).host, hostDigest=Buffer.from(hostKeyDigest,'hex');
 const epoch=fresh(16), hostSubject='host_'+fresh(16);
 const mint=()=>epoch+fresh(32);
 const epochValue=value=>typeof value==='string'&&value.length===65&&value.startsWith(epoch)&&/^[A-Za-z0-9_-]+$/.test(value);
 const sessions=new Map(),invites=new Map(),tickets=new Map(),rateKeys=new Map(),work=new Map();
 let hostLease=null,room=null,rateMinute=-1,roomGeneration=0;
 function active(lease) {
  return !!lease && sessions.get(lease.key)===lease && lease.until>now();
 }
 function remove(lease) {
  sessions.delete(lease.key);
  if(hostLease===lease)hostLease=null;
  for(const [key,item] of invites)if(item.by===lease)invites.delete(key);
  for(const [key,item] of tickets)if(item.lease===lease)tickets.delete(key);
 }
 function prune() {
  const t=now();
  for(const lease of sessions.values())if(lease.until<=t)remove(lease);
  for(const [key,v] of invites)if(v.until<=t)invites.delete(key);
  for(const [key,v] of tickets)if(v.expiresAt<=t)tickets.delete(key);
 }
 function leaseFor(req) {
  const raw=exactHeader(req,'cookie');
  if(!raw||raw.length>4096)return null;
  const matches=raw.split(';').map(v=>v.trim()).filter(v=>v.startsWith(COOKIE+'='));
  if(matches.length!==1)return null;
  const key=matches[0].slice(COOKIE.length+1);
  if(!epochValue(key))return null;
  const lease=sessions.get(hash(key));
  return active(lease)?lease:null;
 }
 function ipFor(req) {
  // Render public ingress overwrites this single header. Never use XFF or
  // the header as identity; global quotas remain independent of proxy trust.
  const ip=exactHeader(req,'cf-connecting-ip');
  return ip && isIP(ip) ? ip.toLowerCase() : null;
 }
 function keys(kind,ip,lease) {
  return [kind+'|all',kind+'|ip|'+ip,...(lease?[kind+'|subject|'+lease.subject]:[])];
 }
 function rate(kind,ip,lease) {
  const minute=Math.floor(now()/60000);
  if(minute!==rateMinute){rateKeys.clear();rateMinute=minute;}
  const bucket=keys(kind,ip,lease);
  if(bucket.some((k,i)=>(rateKeys.get(k)??0)>=rates[kind][i])||
    rateKeys.size+bucket.filter(k=>!rateKeys.has(k)).length>MAX_RATE_KEYS)return false;
  for(const k of bucket)rateKeys.set(k,(rateKeys.get(k)??0)+1);
  return true;
 }
 function acquire(kind,ip,lease) {
  const bucket=keys(kind,ip,lease);
  if(bucket.some((k,i)=>(work.get(k)??0)>=concurrency[kind][i]))return null;
  for(const k of bucket)work.set(k,(work.get(k)??0)+1);
  let done=false;
  return ()=>{
   if(done)return;done=true;
   for(const k of bucket){const n=work.get(k)-1;if(n)work.set(k,n);else work.delete(k);}
  };
 }
 function permits(lease,scope,generation) {
  if(!active(lease))return false;
  if(scope.action==='create')return lease.host && !room && (generation===undefined||generation===roomGeneration);
  return !!room && scope.room===room.code && (generation===undefined||generation===room.generation);
 }
 function startLease(host) {
  const key=mint(),lease={key:hash(key),subject:host?hostSubject:'guest_'+fresh(16),host,until:now()+SESSION_MS};
  sessions.set(lease.key,lease);if(host)hostLease=lease;
  return key;
 }
 async function handleHttp(req,res,path) {
  if(exactHeader(req,'host')!==expectedHost)return reply(res,403);
  prune();
  const lease=leaseFor(req);
  if(req.method==='GET'||req.method==='HEAD'){
   if(path==='/'){
    if(!lease)return reply(res,200,page(loginPage));
    if(req.url!==GAME)return reply(res,303,'',{Location:GAME});
   }
   if(req.url==='/access')return lease?reply(res,200,page(lease.host?hostPage:guestPage)):reply(res,403);
   return lease?pass(res):reply(res,401);
  }
  if(req.method!=='POST')return reply(res,405);
  if(exactHeader(req,'origin')!==audience)return reply(res,403);
  const ip=ipFor(req);if(!ip)return reply(res,403);
  const kind=req.url==='/access/login'?'login':req.url==='/connection-ticket'?'ticket':
   ['/access/invite','/access/logout'].includes(req.url)?'manage':null;
  if(!kind)return reply(res,404);
  if(kind==='ticket'&&!lease)return reply(res,401);
  if(kind==='manage'&&(!lease||req.url==='/access/invite'&&!lease.host))return reply(res,403);
  if(!rate(kind,ip,lease))return reply(res,429);
  const release=acquire(kind,ip,lease);
  if(!release)return reply(res,429);
  res.once('close',release);res.once('finish',release);
  if(kind==='ticket')return pass(res);
  const fields=await formBody(req);
  if(!fields)return reply(res,400);
  if(kind==='login'){
   if(fields.size!==2||fields.getAll('type').length!==1||fields.getAll('code').length!==1)return reply(res,400);
   if(active(lease))return reply(res,303,'',{Location:lease.host?'/access':GAME});
   const type=fields.get('type'),code=fields.get('code');let key;
   prune();
   if(type==='host'){
    if(!keyFormat.test(code)||!timingSafeEqual(Buffer.from(hash(code),'hex'),hostDigest)||hostLease)return reply(res,401,page(loginPage));
    key=startLease(true);
   }else if(type==='guest'){
    const record=epochValue(code)&&invites.get(hash(code));
    if(!record||record.until<=now()||!active(record.by))return reply(res,401,page(loginPage));
    invites.delete(hash(code));key=startLease(false);
   }else return reply(res,400);
   return reply(res,303,'',{'Set-Cookie':sessionCookie(key,SESSION_MS/1000),Location:type==='host'?'/access':GAME});
  }
  if(fields.size||!active(lease))return reply(res,400);
  if(req.url==='/access/logout'){
   remove(lease);return reply(res,303,'',{'Set-Cookie':sessionCookie('',0),Location:'/'});
  }
  const guestCount=sessions.size-(hostLease?1:0);
  if(invites.size+guestCount>=GUESTS)return reply(res,409,page(hostPage+'<p>All guest places are reserved.</p>'));
  const code=mint();
  invites.set(hash(code),{by:lease,until:now()+INVITE_MS});
  return reply(res,200,page('<p>Copy this one-time invite:</p><code id="invite">'+code+'</code>'+hostPage));
 }
 function startUpgrade(req) {
  if(exactHeader(req,'host')!==expectedHost||exactHeader(req,'origin')!==audience)return {status:403};
  const ip=ipFor(req),lease=leaseFor(req); // Upgrade lease holds a slot until socket close.
  if(!ip)return {status:403};
  if(!lease)return {status:401};
  if(!rate('upgrade',ip,lease))return {status:429};
  const release=acquire('upgrade',ip,lease);
  if(!release)return {status:429};
  return {lease,release,generation:null};
 }
 function issueTicket({request,scope,origin,signal}) {
  const lease=leaseFor(request);
  prune();
  if(signal.aborted||origin!==audience||!permits(lease,scope)||tickets.size>=TICKETS)return null;
  const raw=mint(),id=hash(raw),expiresAt=now()+TICKET_MS;
  tickets.set(id,{id,lease,subject:lease.subject,origin,audience,...scope,expiresAt,generation:room?.generation??roomGeneration});
  return raw;
 }
 function verifyAndConsume({ticket,origin,signal,context}) {
  if(signal.aborted||origin!==audience||!epochValue(ticket))return null;
  const id=hash(ticket),record=tickets.get(id);
  if(!record||record.expiresAt<=now()||record.lease!==context?.lease||
    !permits(record.lease,record,record.generation))return null;
  tickets.delete(id); // No await between lookup, validation and deletion.
  context.generation=record.generation;
  const {lease,generation,...claims}=record;
  return claims;
 }
 return Object.freeze({audience,handleHttp,startUpgrade,active,permits,issueTicket,verifyAndConsume,
  roomOpened(code){room={code,generation:++roomGeneration};},
  roomClosed(code){if(room?.code===code)room=null;}});
}
