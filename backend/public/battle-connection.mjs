// Browser WebSockets can stay OPEN during a dead link, or linger in CLOSING.
// Retire the application connection independently so stale events cannot drive it.
export const BATTLE_REJOIN_WINDOW_MS = 22000;
export const BATTLE_REJOIN_DELAY_MS = 1250;
const SNAPSHOT_MS = 8000;

export function battleConnection(raw, {
  timers = globalThis, now = () => performance.now(), visible = true,
} = {}) {
  let retired = false, receiving = false, timer, deadline = now() + SNAPSHOT_MS;
  const connection = {
    get readyState() { return retired ? 3 : raw.readyState; },
    send(data) { if (!retired && raw.readyState === 1) raw.send(data); },
    close() { finish({ code: 1000, reason: '' }, true); },
    snapshot() {
      receiving = true; deadline = now() + SNAPSHOT_MS;
      if (visible) arm(); else clear();
    },
    setVisible(value) {
      if (visible === value) return;
      visible = value;
      if (receiving) {
        if (visible) deadline = now() + SNAPSHOT_MS;
        else clear();
        arm();
      }
    },
  };
  function clear() { if (timer !== undefined) timers.clearTimeout(timer); timer = undefined; }
  function arm() {
    if (retired || timer !== undefined || (receiving && !visible)) return;
    timer = timers.setTimeout(() => {
      timer = undefined;
      if (now() >= deadline) finish({ code: 1006, reason: 'No battle updates', timedOut: true }, true);
      else arm();
    }, Math.max(0, deadline - now()));
  }
  function finish(event, closeRaw = false) {
    if (retired) return;
    retired = true; clear();
    if (closeRaw) raw.close();
    connection.onclose?.(event);
  }
  raw.onopen = event => { if (!retired) connection.onopen?.(event); };
  raw.onmessage = event => { if (!retired) connection.onmessage?.(event); };
  raw.onerror = event => { if (!retired) connection.onerror?.(event); };
  raw.onclose = event => finish(event);
  arm();
  return connection;
}
