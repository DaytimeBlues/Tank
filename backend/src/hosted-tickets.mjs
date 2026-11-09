import { GAME_PROTOCOL, TICKET_PREFIX, hostedScope, validTicket } from '../public/hosted-ticket.mjs';
import { validateOrigins } from './server-config.mjs';

const MAX_TICKET_MS = 30_000, MAX_CONSUMED = 4096, MAX_PROVIDER_CALLS = 32;
const identifier = value => typeof value === 'string' && value.length > 0 && value.length <= 160;

export function createHostedTickets(provider, allowedOrigins) {
  const { audience, issueTicket, verifyAndConsume } = provider ?? {};
  if (!allowedOrigins.includes(audience) || typeof issueTicket !== 'function' || typeof verifyAndConsume !== 'function') {
    throw new Error('Hosted startup held: exact origins, HTTPS audience and an authenticated ticket adapter are required');
  }
  validateOrigins([audience]);
  const consumed = new Map();
  let inFlight = 0;
  async function call(fn, args, signal) {
    if (signal.aborted || inFlight >= MAX_PROVIDER_CALLS) return null;
    inFlight++;
    try { return await fn({ ...args, audience, signal }); }
    finally { inFlight--; }
  }
  return {
    audience,
    async issue(request, scope, origin, signal) {
      const ticket = await call(issueTicket, { request, scope, origin }, signal);
      return !signal.aborted && validTicket(ticket) ? ticket : null;
    },
    async admit(header, origin, signal, context) {
      if (typeof header !== 'string' || header.length > 540) return null;
      const protocols = header.split(',').map(p => p.trim());
      if (protocols.length !== 2 || protocols[0] !== GAME_PROTOCOL || !protocols[1].startsWith(TICKET_PREFIX)) return null;
      const ticket = protocols[1].slice(TICKET_PREFIX.length);
      if (!validTicket(ticket)) return null;
      const result = await call(verifyAndConsume, { ticket, origin, ...(context ? { context } : {}) }, signal);
      if (signal.aborted || !result) return null;
      const { subject, id, action, room, expiresAt } = result;
      const scope = hostedScope(action, room), now = Date.now();
      if (!scope || !identifier(subject) || !identifier(id) || result.audience !== audience || result.origin !== origin ||
          !Number.isSafeInteger(expiresAt) || expiresAt <= now || expiresAt - now > MAX_TICKET_MS) return null;

      // No await between check and insert: one use per live authoritative process.
      for (const [key, expiry] of consumed) if (expiry <= now) consumed.delete(key);
      if (consumed.has(id) || consumed.size >= MAX_CONSUMED) return null;
      consumed.set(id, expiresAt);
      return { ...scope, subject, expiresAt };
    },
  };
}

// Bound the caller even when a provider ignores AbortSignal. The provider slot
// stays occupied until that operation settles, preventing runaway queued work.
export function bounded(work, signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) { reject(signal.reason); return; }
    const abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve().then(() => { signal.throwIfAborted(); return work(); }).then(resolve, reject)
      .finally(() => signal.removeEventListener('abort', abort));
  });
}
