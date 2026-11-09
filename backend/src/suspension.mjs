import RAPIER from '@dimforge/rapier3d-compat';

const HALF = { x: 1.85, y: 0.65, z: 2.25 };

export function rotate(q, v) {
  const t = { x: 2 * (q.y * v.z - q.z * v.y), y: 2 * (q.z * v.x - q.x * v.z), z: 2 * (q.x * v.y - q.y * v.x) };
  return { x: v.x + q.w * t.x + q.y * t.z - q.z * t.y,
    y: v.y + q.w * t.y + q.z * t.x - q.x * t.z,
    z: v.z + q.w * t.z + q.x * t.y - q.y * t.x };
}

export function createHull(world, lateralGrip = 1) {
  const body = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(0, 1.5, -10)
    .setLinearDamping(0.1).setAngularDamping(0.5).setCanSleep(false).setCcdEnabled(true));
  world.createCollider(RAPIER.ColliderDesc.cuboid(HALF.x, HALF.y, HALF.z).setMass(1000).setFriction(0.5), body);
  const vehicle = world.createVehicleController(body);
  vehicle.indexUpAxis = 1;
  vehicle.setIndexForwardAxis = 2;
  // Six support rays approximate two track runs; this is not a continuous-track model.
  for (const x of [-1.65, 1.65]) for (const z of [-1.6, 0, 1.6]) {
    vehicle.addWheel({ x, y: 0, z }, { x: 0, y: -1, z: 0 }, { x: -1, y: 0, z: 0 }, 0.65, 0.4);
    const i = vehicle.numWheels() - 1;
    vehicle.setWheelSuspensionStiffness(i, 35);
    vehicle.setWheelSuspensionCompression(i, 4.4);
    vehicle.setWheelSuspensionRelaxation(i, 4.4);
    vehicle.setWheelMaxSuspensionTravel(i, 0.3);
    vehicle.setWheelMaxSuspensionForce(i, 12000);
    vehicle.setWheelFrictionSlip(i, 2);
    vehicle.setWheelSideFrictionStiffness(i, lateralGrip);
  }
  return { body, vehicle };
}

// Assisted skid steering for the six-ray surrogate, not a continuous-track model.
// Centre rays retain lateral grip while fore/aft rays slip for yaw; neutral restores
// all six grips. Gravity feed-forward during turning and neutral hold prevents
// the assisted drive from becoming a downhill command on an incline.
export function differentialStep(grade, dt, throttle, steer, grip = 0.05, stepWorld = true) {
  const { body, vehicle, world } = grade;
  const q = body.rotation(), p = body.translation(), f = rotate(q, { x: 0, y: 0, z: 1 });
  const braking = (!throttle && !steer) || grade.stage === 'complete';
  const activeSteer = braking ? 0 : steer;
  for (let i = 0; i < vehicle.numWheels(); i++) {
    const local = vehicle.wheelChassisConnectionPointCs(i), r = rotate(q, local);
    const v = body.velocityAtPoint({ x: p.x + r.x, y: p.y + r.y, z: p.z + r.z });
    // Gravity acts along the contact surface, not the chassis pitch: suspension
    // compression makes those angles measurably different while stopped.
    const normal = vehicle.wheelContactNormal(i);
    let tangent = f;
    if (normal && vehicle.wheelIsInContact(i)) {
      const dot = f.x * normal.x + f.y * normal.y + f.z * normal.z;
      const projected = { x: f.x - normal.x * dot, y: f.y - normal.y * dot, z: f.z - normal.z * dot };
      const length = Math.hypot(projected.x, projected.y, projected.z);
      if (length > 0.001) tangent = { x: projected.x / length, y: projected.y / length, z: projected.z / length };
    }
    const speed = v.x * tangent.x + v.y * tangent.y + v.z * tangent.z;
    const target = braking ? 0 : throttle * (steer ? (grade.driveSpeed ?? 3) * 2 / 3 : (grade.driveSpeed ?? 3)) - steer * local.x * 0.6;
    // Motor hold complements wheel braking after yaw is unlocked. Wheel brake
    // impulse alone leaves a measurable slope creep even with a larger cap.
    const force = Math.max(-2000, Math.min(2000, (target - speed) * 1000 * (braking ? 8 : 2) / 6
      + (steer || braking ? 1000 * 9.81 * tangent.y / 6 : 0)));
    vehicle.setWheelEngineForce(i, force);
    vehicle.setWheelBrake(i, braking ? 200 : 0);
    vehicle.setWheelSideFrictionStiffness(i, activeSteer && Math.abs(local.z) > 0.1 ? grip : 1);
  }
  vehicle.updateVehicle(dt, undefined, undefined, c => grade.supportHandles ? grade.supportHandles.has(c.handle) : c.handle === grade.ground.handle);
  if (stepWorld) { world.timestep = dt; world.step(); }
}
