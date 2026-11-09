const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export const LOOK_LIMITS=Object.freeze({yaw:Math.PI*.86,minPitch:Math.PI/6,maxPitch:Math.PI*.39,distance:Math.hypot(20,22),basePitch:Math.atan2(22,20)});
export function createFreeLook(){
 let held=false,pointer=null,x=0,y=0,targetYaw=0,targetPitch=0,yaw=0,pitch=0,blend=0;
 return {
  get held(){return held;},get pointer(){return pointer;},
  begin(id,px,py){if(!Number.isInteger(id)||![px,py].every(Number.isFinite))return false;held=true;pointer=id;x=px;y=py;return true;},
  move(id,px,py){if(!held||id!==pointer||![px,py].every(Number.isFinite))return;targetYaw=clamp(targetYaw-(px-x)*.005,-LOOK_LIMITS.yaw,LOOK_LIMITS.yaw);targetPitch=clamp(targetPitch-(py-y)*.004,LOOK_LIMITS.minPitch-LOOK_LIMITS.basePitch,LOOK_LIMITS.maxPitch-LOOK_LIMITS.basePitch);x=px;y=py;},
  cancel(hard=false){held=false;pointer=null;targetYaw=targetPitch=0;if(hard)yaw=pitch=blend=0;},
  step(dt,reduced=false){const k=reduced?1:1-Math.exp(-(held?15:8)*Math.max(0,Math.min(.25,dt)));yaw+=(targetYaw-yaw)*k;pitch+=(targetPitch-pitch)*k;blend+=((held?1:0)-blend)*k;if(!held&&Math.abs(yaw)+Math.abs(pitch)+blend<.0001)yaw=pitch=blend=0;return {yaw,pitch,blend,held};}
 };
}
export function bindFreeLook({canvas,global,doc,control,active,onChange=()=>{}}){
 let lastId=null,captured=null,ownedContext=false,disposed=false;const listeners=[];
 const on=(target,type,fn)=>{target.addEventListener(type,fn);listeners.push([target,type,fn]);};
 function cancel(hard=false){control.cancel(hard);const id=captured;captured=null;try{if(id!==null&&canvas.hasPointerCapture(id))canvas.releasePointerCapture(id);}catch{}canvas.classList.remove('free-looking');onChange(false);}
 function begin(e){
  if(e.button!==2||disposed)return;if(!active()){ownedContext=false;return;}if(control.held)return;
  const id=e.pointerId??lastId;if(id===null||!control.begin(id,e.clientX,e.clientY))return;
  // Keep compatibility mouse events: they carry the second button of a chord.
  ownedContext=true;canvas.focus({preventScroll:true});
  try{canvas.setPointerCapture(id);captured=id;}catch{cancel();return;}
  canvas.classList.add('free-looking');onChange(true);
 }
 on(canvas,'pointerdown',e=>{if(e.pointerType==='touch')return;lastId=e.pointerId;begin(e);});
 // Mouse chords do not necessarily produce another pointerdown event.
 on(canvas,'mousedown',e=>begin(e));
 on(global,'pointermove',e=>{if(e.pointerType==='touch')return;lastId=e.pointerId;if(control.held&&e.pointerId===control.pointer){if(!active()||!(e.buttons&2))cancel();else control.move(e.pointerId,e.clientX,e.clientY);}});
 on(global,'pointerup',e=>{if(control.held&&e.pointerId===control.pointer&&(e.button===2||!(e.buttons&2)))cancel();});
 on(global,'mouseup',e=>{if(e.button===2&&control.held)cancel();});
 on(global,'pointercancel',e=>{if(e.pointerId===control.pointer)cancel();});
 on(canvas,'lostpointercapture',e=>{if(e.pointerId===control.pointer)cancel();});
 on(global,'blur',()=>{ownedContext=false;cancel();});
 on(doc,'visibilitychange',()=>{if(doc.hidden){ownedContext=false;cancel();}});
 on(global,'keydown',e=>{if(e.code==='Escape')cancel();});
 on(canvas,'contextmenu',e=>{if(e.button===2&&ownedContext){e.preventDefault();ownedContext=false;}});
 return {cancel,dispose(){if(disposed)return;disposed=true;cancel(true);for(const [t,type,fn]of listeners)t.removeEventListener(type,fn);listeners.length=0;}};
}
export function createCameraGuard(THREE){
 const ray=new THREE.Raycaster(),delta=new THREE.Vector3(),direction=new THREE.Vector3(),down=new THREE.Vector3(0,-1,0),origin=new THREE.Vector3(),hits=[];
 return {constrain(focus,candidate,obstacles){
  let clipped=false;delta.copy(candidate).sub(focus);const length=delta.length();
  if(length>.001){direction.copy(delta).multiplyScalar(1/length);ray.set(focus,direction);ray.near=.001;ray.far=length;hits.length=0;ray.intersectObjects(obstacles,false,hits);if(hits.length){candidate.copy(focus).addScaledVector(direction,Math.max(.2,hits[0].distance-.65));clipped=true;}}
  origin.set(candidate.x,100,candidate.z);ray.set(origin,down);ray.near=0;ray.far=200;hits.length=0;ray.intersectObjects(obstacles,false,hits);
  let floor=null;if(hits.length){floor=hits[0].point.y;if(candidate.y<floor+.65){candidate.y=floor+.65;clipped=true;}}
  return {clipped,floor,clearance:floor===null?null:candidate.y-floor};
 }};
}
