import RAPIER from '@dimforge/rapier3d-compat';
import { createHull, rotate, differentialStep } from './suspension.mjs';

const sections = [[-40, 0], [-12, 0], [8, 3.5], [16, 3.5], [36, 0], [40, 0]];
const vertices = [], indices = [];
for (const [z, y] of sections) vertices.push(-40, y, z, 40, y, z);
for (let i = 0; i < sections.length - 1; i++) {
  const a = i * 2; indices.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
}
// This exact mesh is also sent to the renderer. Units are metres, Y up.
export const GRADE_MAP = { mode: 'grade-drive', version: 2, size: 80, vertices, indices,
  sections, walls: [{ x: -40, z: 0, w: 2, d: 82 }, { x: 40, z: 0, w: 2, d: 82 },
    { x: 0, z: -40, w: 82, d: 2 }, { x: 0, z: 40, w: 82, d: 2 }] };

function height(z) {
  for (let i = 1; i < sections.length; i++) {
    const [a, h] = sections[i - 1], [b, k] = sections[i];
    if (z <= b) return h + (k - h) * Math.max(0, Math.min(1, (z - a) / (b - a)));
  }
  return 0;
}

export class GradeDrive {
  constructor() {
    this.world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
    this.ground = this.world.createCollider(RAPIER.ColliderDesc.trimesh(new Float32Array(vertices), new Uint32Array(indices)).setFriction(0.8));
    for (const w of GRADE_MAP.walls) this.world.createCollider(RAPIER.ColliderDesc.cuboid(w.w / 2, 4, w.d / 2).setTranslation(w.x, 4, w.z));
    this.reset();
  }
  reset() {
    if (this.vehicle) this.world.removeVehicleController(this.vehicle);
    if (this.body) this.world.removeRigidBody(this.body);
    Object.assign(this, createHull(this.world));
    this.body.setTranslation({ x: 0, y: 1.5, z: -24 }, true);
    // All rotation comes from suspension, contact and differential drive forces.
    this.stage = 'outbound';
  }
  step(dt, throttle, steer = 0) {
    // Match the verified suspension step even when the network ticks at 30 Hz.
    const steps = Math.ceil(dt / (1 / 120)), substep = dt / steps;
    this.world.timestep = substep;
    for (let n = 0; n < steps; n++) {
      differentialStep(this, substep, throttle, steer);
      const { x, z } = this.body.translation();
      if (this.stage === 'outbound' && z >= 30 && Math.abs(x) <= 4) this.stage = 'return';
      if (this.stage === 'return' && z <= -22 && Math.abs(x) <= 4) this.stage = 'complete';
    }
  }
  pose() {
    const p = this.body.translation(), q = this.body.rotation(), v = this.body.linvel();
    const forward = rotate(q, { x: 0, y: 0, z: 1 }), right = rotate(q, { x: 1, y: 0, z: 0 });
    return { x: p.x, y: p.y, z: p.z, quaternion: { ...q }, yaw: Math.atan2(forward.x, forward.z),
      pitch: Math.asin(Math.max(-1, Math.min(1, forward.y))) * 180 / Math.PI,
      roll: Math.asin(Math.max(-1, Math.min(1, right.y))) * 180 / Math.PI,
      speed: v.x * forward.x + v.y * forward.y + v.z * forward.z,
      groundHeight: height(p.z), terrain: 'slope trial' };
  }
}
