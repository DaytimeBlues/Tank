import { Sky } from '/vendor/Sky.js';
import { paintBaseBadge } from './map-markers.mjs';
import { prepareTerrain, terrainPaint, buildRiverArt, buildBridgeArt, buildTreeArt } from './landscape-art.mjs';
export function buildBattlefield(THREE,scene,map,surface,{readableMarkers=false}={}){
 const terrainMeshes=[],flags=new Map(),terrain=prepareTerrain(map);
 const groundMaterial=new THREE.MeshStandardMaterial({color:0xffffff,roughness:1,vertexColors:true});
 for(const c of map.chunks){const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(c.vertices,3));g.setIndex(c.indices);g.setAttribute('color',new THREE.Float32BufferAttribute(terrainPaint(c.vertices,c.colors,map),3));const uv=[];for(let i=0;i<c.vertices.length;i+=3)uv.push(c.vertices[i]/4,c.vertices[i+2]/4);g.setAttribute('uv',new THREE.Float32BufferAttribute(uv,2));g.setAttribute('normal',new THREE.Float32BufferAttribute(terrain.normalsFor(c.vertices),3));const mesh=new THREE.Mesh(g,groundMaterial);if(!terrainMeshes.length)surface(mesh,'#c4c0aa',1,1);mesh.receiveShadow=true;scene.add(mesh);terrainMeshes.push(mesh);}
 scene.add(buildRiverArt(THREE,map.water,terrain.heightAt));
 if(map.trees?.length)scene.add(...buildTreeArt(THREE,map.trees));
 const bridgeMeshes=buildBridgeArt(THREE,map.bridges);
 scene.add(...bridgeMeshes);
 const postGeometry=new THREE.BoxGeometry(.3,2,.3),posts=new THREE.InstancedMesh(postGeometry,new THREE.MeshStandardMaterial({color:0xd9d0ad,roughness:1}),map.bases.length*4),matrix=new THREE.Matrix4();let i=0;
 for(const b of map.bases){for(const dx of [-b.radius,b.radius])for(const dz of [-b.radius,b.radius]){matrix.makeTranslation(b.x+dx,b.y+1,b.z+dz);posts.setMatrixAt(i++,matrix);}const ring=new THREE.Mesh(new THREE.RingGeometry(b.radius-.25,b.radius,64),new THREE.MeshBasicMaterial({color:0xdfd8b8,side:THREE.DoubleSide}));ring.rotation.x=-Math.PI/2;ring.position.set(b.x,b.y+.04,b.z);scene.add(ring);flags.set(b.id,ring);}
 posts.instanceMatrix.needsUpdate=true;posts.computeBoundingSphere();scene.add(posts);
 const sky=new Sky();sky.scale.setScalar(900);sky.material.uniforms.sunPosition.value.set(-.4,.7,-.2);sky.material.uniforms.turbidity.value=4;scene.add(sky);
 const badges=new Map(),badgeGeometry=readableMarkers?new THREE.PlaneGeometry(5.2,5.2):null;
 if(readableMarkers)for(const b of map.bases){
  const canvas=document.createElement('canvas');canvas.width=canvas.height=512;const ctx=canvas.getContext('2d');paintBaseBadge(ctx,b.id,'neutral');
  const texture=new THREE.CanvasTexture(canvas);texture.colorSpace=THREE.SRGBColorSpace;
  const material=new THREE.MeshBasicMaterial({map:texture,transparent:true,depthWrite:false,polygonOffset:true,polygonOffsetFactor:-2});
  const mesh=new THREE.Mesh(badgeGeometry,material);mesh.name='BaseBadge_'+b.id;mesh.rotation.x=-Math.PI/2;mesh.position.set(b.x,b.y+.08,b.z);scene.add(mesh);
  badges.set(b.id,{mesh,texture,ctx,owner:'neutral'});
 }
 const markers={get size(){return badges.size;},face(camera){for(const b of badges.values())b.mesh.rotation.z=Math.atan2(camera.position.x-b.mesh.position.x,camera.position.z-b.mesh.position.z);},update(bases){for(const b of bases){const badge=badges.get(b.id);if(badge&&badge.owner!==b.owner){paintBaseBadge(badge.ctx,b.id,b.owner);badge.texture.needsUpdate=true;badge.owner=b.owner;}}},dispose(){for(const b of badges.values()){scene.remove(b.mesh);b.texture.dispose();b.mesh.material.dispose();}badges.clear();badgeGeometry?.dispose();}};
 return {terrainMeshes,bridgeMeshes,flags,sky,markers};
}
export function updateBattlefieldHUD(doc,state){
 const owned=state.capture.owned;doc.getElementById('targets').textContent=`${owned} / 7`;
 const panel=doc.getElementById('targetProgress');
 for(const b of state.capture.bases){let node=doc.getElementById('base-'+b.id);if(!node){node=doc.createElement('div');node.id='base-'+b.id;node.className='base-status';panel.append(node);}const direction=b.net>0?'↑ BLUE':b.net<0?'↓ RED':b.contested?'Ⅱ STALLED':'— HOLD';node.textContent=`${b.id} ${b.name} · ${b.owner.toUpperCase()} · ${Math.round(Math.abs(b.progress)*100)}% ${direction}`;node.dataset.owner=b.owner;}
}
