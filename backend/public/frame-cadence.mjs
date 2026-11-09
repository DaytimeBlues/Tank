// Reporting only: rAF callback cadence, independent of the presentation time step.
export function createFrameCadence({ windowMs = 3000 } = {}) {
  if (!Number.isFinite(windowMs) || windowMs <= 0) throw new RangeError('Invalid frame window');
  let visible = true, previous, span = 0, samples = [];

  return {
    setVisible(value) {
      if (visible === value) return false;
      visible = value;
      previous = undefined; span = 0; samples = [];
      return true;
    },
    observe(now) {
      if (!visible || !Number.isFinite(now) || now < 0 || (previous !== undefined && now <= previous)) return null;
      if (previous === undefined) { previous = now; return null; }

      const interval = now - previous;
      previous = now;
      samples.push(interval); span += interval;
      if (span < windowMs) return null;

      samples.sort((a, b) => a - b);
      const count = samples.length;
      const report = { count, spanMs: span, p95Ms: samples[Math.ceil(count * .95) - 1], maxMs: samples[count - 1], meanFps: count * 1000 / span };
      span = 0; samples = [];
      // Keep the boundary timestamp: the next interval starts here.
      return report;
    },
  };
}
