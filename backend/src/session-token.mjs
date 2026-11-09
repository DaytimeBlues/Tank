export function sessionToken() {
  const bytes = new Uint8Array(24);
  globalThis.crypto.getRandomValues(bytes);
  return Array.from(bytes, n => n.toString(16).padStart(2, '0')).join('');
}
