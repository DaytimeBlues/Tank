export const GAME_PROTOCOL = 'tank-v1';
export const TICKET_PREFIX = 'ticket.';
export const validTicket = value => typeof value === 'string' && /^[A-Za-z0-9_-]{16,512}$/.test(value);

export function hostedScope(action, room) {
  if (action === 'create' && room === null) return { action, room };
  if (['join', 'reconnect'].includes(action) && typeof room === 'string' && /^[A-Z0-9]{6}$/.test(room)) return { action, room };
  return null;
}

// Same-origin acquisition only. Tickets stay off URLs/storage; a saved seat token is not sent to the issuer.
export async function acquireHostedProtocols(request, { signal, fetcher = fetch } = {}) {
  if (request.mode !== 'battle' || request.format !== '4v4') throw new Error('Hosted mode requires online 4v4');
  const scope = hostedScope(request.type, request.type === 'create' ? null : request.code);
  if (!scope) throw new Error('Invalid hosted connection scope');
  const deadline = AbortSignal.timeout(4000);
  const response = await fetcher('/connection-ticket', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(scope),
    cache: 'no-store', mode: 'same-origin', credentials: 'same-origin', redirect: 'error',
    signal: signal ? AbortSignal.any([signal, deadline]) : deadline,
  });
  if (!response.ok) throw new Error('Hosted ticket unavailable');
  const { ticket } = await response.json();
  if (!validTicket(ticket)) throw new Error('Hosted ticket unavailable');
  return [GAME_PROTOCOL, TICKET_PREFIX + ticket];
}
