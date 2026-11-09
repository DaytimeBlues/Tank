// Shared-profile hangar state stays separate from the committed spawn choice.
export function fitTankPreview(THREE,model,camera,aspect){
 const corners=[],bounds=new THREE.Box3();
 model.updateMatrixWorld(true);
 model.traverseVisible(o=>{
  if(!o.isMesh)return;
  if(!o.geometry.boundingBox)o.geometry.computeBoundingBox();
  const {min,max}=o.geometry.boundingBox;
  for(const x of [min.x,max.x])for(const y of [min.y,max.y])for(const z of [min.z,max.z]){
   const p=new THREE.Vector3(x,y,z).applyMatrix4(o.matrixWorld);corners.push(p);bounds.expandByPoint(p);
  }
 });
 if(!corners.length)return;
 const center=bounds.getCenter(new THREE.Vector3());
 const outward=new THREE.Vector3(5,3,6.8).normalize();
 const right=new THREE.Vector3(0,1,0).cross(outward).normalize(),up=outward.clone().cross(right);
 const tan=Math.tan(camera.fov*Math.PI/360)*.88;
 let depth=1;
 for(const p of corners){
  const relative=p.sub(center);
  depth=Math.max(depth,relative.dot(outward)+Math.max(Math.abs(relative.dot(right))/(tan*aspect),Math.abs(relative.dot(up))/tan));
 }
 camera.aspect=aspect;camera.position.copy(center).addScaledVector(outward,depth);
 camera.lookAt(center);camera.updateProjectionMatrix();
}
export function setupHangar({THREE,doc,tank,profile,selection,onOpen,onClose,visuals,visualSelection,onVisualCommit}){
 const root=doc.getElementById('hangar'),canvas=doc.getElementById('tankPreview');let renderer,scene,camera,model,visible=false,returnFocus,framingDirty=true;
 doc.getElementById('tankName').textContent=profile.name;
 const profileLabel=doc.getElementById('tankProfileLabel');
 if(profileLabel)profileLabel.textContent=visuals?`Shared gameplay profile: ${profile.name}`:'Gameplay profile';
 doc.getElementById('tankStats').textContent=`DURABILITY  ${profile.durability??'Not modelled'}\nSPEED  ${(profile.forwardMps*3.6).toFixed(1)} km/h drive target\nFIREPOWER  ${profile.damage} damage / hit\nRELOAD  ${profile.reloadSeconds.toFixed(1)} s · lower is faster`;
 doc.getElementById('tankStrengths').textContent=profile.strengths.join(' · ');doc.getElementById('tankTradeoffs').textContent=profile.tradeoffs.join(' · ');
 const buttons=[];
 function previewVisual(id){
  if(!visuals)return;const item=visuals.find(v=>v.id===id);visualSelection.browse(id);
  if(model)for(const v of visuals){const part=model.getObjectByName('Visual_'+v.id);if(part){part.visible=v.id===id;part.getObjectByName('TurretYaw').rotation.y=0;part.getObjectByName('BarrelPitch').rotation.x=0;}}
  for(const [key,button]of buttons)button.setAttribute('aria-pressed',String(key===id));
  doc.getElementById('tankName').textContent=item.name;
  doc.getElementById('tankArtCaption').textContent=`${item.kind}. ${item.description}`;
  doc.getElementById('tankTradeoffs').textContent=profile.tradeoffs.slice(1).join(' · ');
  canvas.setAttribute('aria-label',`${item.name} tank preview`);
  canvas.dataset.visual=id;
  framingDirty=true;
 }
 if(visuals){
  const first=doc.getElementById('tankRosterChoice');
  visuals.forEach((v,i)=>{const button=i?doc.createElement('button'):first;if(i){button.id='tankRoster'+v.name;first.parentElement.append(button);}button.textContent=String(i+1).padStart(2,'0')+' · '+v.name;button.onclick=()=>previewVisual(v.id);buttons.push([v.id,button]);});
 }
 function open(){returnFocus=doc.activeElement;selection.open();visible=true;root.hidden=false;onOpen();if(!renderer){renderer=new THREE.WebGLRenderer({canvas,antialias:true});renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio||1,1.5));scene=new THREE.Scene();scene.background=new THREE.Color('#222c29');scene.add(new THREE.HemisphereLight(0xfff1d2,0x26342e,3));const sun=new THREE.DirectionalLight(0xffebc1,3);sun.position.set(-4,8,6);scene.add(sun);model=tank.clone(true);model.position.set(0,-1,0);model.rotation.set(0,.5,0);model.traverse(o=>{if(o.isLine)o.visible=false;});scene.add(model);camera=new THREE.PerspectiveCamera(35,1,.1,50);camera.position.set(5,3.5,6.8);camera.lookAt(0,.5,0);}if(visuals)previewVisual(visualSelection.open());doc.getElementById('tankRosterChoice').focus();}
 function close(confirm){if(confirm){selection.confirm();if(visuals)onVisualCommit(visualSelection.confirm());}else{selection.back();visualSelection?.back();}visible=false;root.hidden=true;onClose();returnFocus?.focus();}
 doc.getElementById('chooseTank').onclick=open;if(!visuals)doc.getElementById('tankRosterChoice').onclick=()=>selection.browse(profile.id);
 doc.getElementById('tankConfirm').onclick=()=>close(true);doc.getElementById('tankBack').onclick=()=>close(false);
 root.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();close(false);}if(e.key==='Tab'){const focusable=[...root.querySelectorAll('button')],first=focusable[0],last=focusable.at(-1);if(e.shiftKey&&doc.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&doc.activeElement===last){e.preventDefault();first.focus();}}});
 doc.getElementById('previewRotate').onclick=()=>{if(model){model.rotation.y+=Math.PI/4;framingDirty=true;}};
 return {get visible(){return visible;},frame(){if(!visible||!renderer)return;const w=Math.max(1,canvas.clientWidth),h=Math.max(1,canvas.clientHeight);if(canvas.width!==Math.round(w*renderer.getPixelRatio())||canvas.height!==Math.round(h*renderer.getPixelRatio())){renderer.setSize(w,h,false);framingDirty=true;}if(framingDirty){fitTankPreview(THREE,model,camera,w/h);framingDirty=false;}renderer.render(scene,camera);},dispose(){visible=false;renderer?.dispose();renderer?.forceContextLoss();renderer=null;framingDirty=true;}};
}
