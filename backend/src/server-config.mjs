export function validateOrigins(values) {
  if (!Array.isArray(values)) throw new Error('Hosted origins must be an array of exact HTTPS origins');
  for (const value of values) {
    if (typeof value !== 'string') throw new Error('Hosted origins must be exact HTTPS origins');
    const url = new URL(value);
    if (url.origin !== value || url.protocol !== 'https:') throw new Error('Hosted origins must be exact HTTPS origins');
  }
  return Object.freeze([...values]);
}

export function serverConfig(env = process.env) {
  const networkMode = env.TANK_NETWORK_MODE ?? 'local';
  if (!['local', 'hosted'].includes(networkMode)) throw new Error('Unknown network mode');
  const raw = env.PORT ?? '5197';
  if (!/^\d+$/.test(raw)) throw new Error('PORT must be an integer');
  const port = Number(raw);
  if (!Number.isSafeInteger(port) || port < 0 || port > 65535) throw new Error('PORT out of range');
  const allowedOrigins = validateOrigins(env.TANK_ALLOWED_ORIGINS?.split(',').map(s => s.trim()).filter(Boolean) ?? []);
  return { port, host: networkMode === 'hosted' ? '0.0.0.0' : '127.0.0.1', networkMode, allowedOrigins };
}

// An Origin header is a browser boundary, not player authentication.
export function acceptsOrigin(origin, host, { networkMode, allowedOrigins }) {
  if (networkMode === 'hosted') return typeof origin === 'string' && Array.isArray(allowedOrigins) && allowedOrigins.includes(origin);
  if (!origin) return true; // Existing local protocol fixtures have no browser Origin.
  try { return new URL(origin).origin === `http://${host}`; } catch { return false; }
}
