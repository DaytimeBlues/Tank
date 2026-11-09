// Presentation only. World-space colour is continuous across terrain chunks.
const clamp01=n=>Math.max(0,Math.min(1,n));

// Read the same indexed triangles used for terrain meshes and colliders.
// Accumulate face normals in world space so the chunk split is invisible.
export function prepareTerrain(map){
  const {size,step,chunks}=map,half=size/2,side=size/step,cells=new Map(),normals=new Map();
  const cell=(x,z)=>Math.max(0,Math.min(side-1,Math.floor((x+half)/step)))+
    side*Math.max(0,Math.min(side-1,Math.floor((z+half)/step)));
  const key=(x,z)=>`${x},${z}`;
  for(const {vertices,indices} of chunks)for(let i=0;i<indices.length;i+=3){
    const [a,b,c]=indices.slice(i,i+3).map(n=>vertices.slice(n*3,n*3+3));
    const u=b.map((n,k)=>n-a[k]),v=c.map((n,k)=>n-a[k]);
    const normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
    const bucket=cell(Math.min(a[0],b[0],c[0]),Math.min(a[2],b[2],c[2]));
    if(!cells.has(bucket))cells.set(bucket,[]);
    cells.get(bucket).push({a,u,v});
    for(const [x,,z] of [a,b,c]){
      const id=key(x,z),sum=normals.get(id)??[0,0,0];
      for(let k=0;k<3;k++)sum[k]+=normal[k];
      normals.set(id,sum);
    }
  }
  for(const [id,n] of normals){const length=Math.hypot(...n);normals.set(id,n.map(x=>x/length));}
  return {
    heightAt(x,z){
      if(Math.abs(x)>half||Math.abs(z)>half)return;
      for(const {a,u,v} of cells.get(cell(x,z))??[]){
        const dx=x-a[0],dz=z-a[2],det=u[0]*v[2]-u[2]*v[0];
        const s=(dx*v[2]-dz*v[0])/det,t=(u[0]*dz-u[2]*dx)/det;
        if(s>=-1e-8&&t>=-1e-8&&s+t<=1+1e-8)return a[1]+s*u[1]+t*v[1];
      }
    },
    normalsFor(vertices){
      const result=[];
      for(let i=0;i<vertices.length;i+=3)result.push(...normals.get(key(vertices[i],vertices[i+2])));
      return result;
    }
  };
}

function roadDistance(x,z,roads){
  let nearest=Infinity;
  for(const {a,b} of roads){
    const dx=b.x-a.x,dz=b.z-a.z,px=x-a.x,pz=z-a.z;
    const along=clamp01((px*dx+pz*dz)/(dx*dx+dz*dz));
    nearest=Math.min(nearest,(px-dx*along)**2+(pz-dz*along)**2);
  }
  return Math.sqrt(nearest);
}

export function terrainPaint(vertices,base,{water,roads}){
  const colors=[];
  for(let i=0;i<vertices.length;i+=3){
    const [x,y,z]=[vertices[i],vertices[i+1],vertices[i+2]];
    const edge=Math.abs(x-water.x)-water.w/2;
    const wet=clamp01((8-Math.abs(edge))/8)*clamp01((water.y+3.3-y)/3.3);
    const dry=clamp01((y-water.y+.1)/.65);
    const road=clamp01((10-roadDistance(x,z,roads))/6)*dry;
    const patch=.5+.24*Math.sin(.065*x+.052*z)+.15*Math.cos(.11*z-.058*x);
    const shade=.82+patch*.24;
    const soil=[.31,.27,.17],track=[.66,.58,.40],grass=base[i]>.6?[.38,.49,.29]:base.slice(i,i+3);
    for(let c=0;c<3;c++){
      const verge=grass[c]*[.91,1,.84][c],paint=(verge+(track[c]-verge)*road)*shade;
      colors.push(clamp01(paint+(soil[c]-paint)*wet*.7));
    }
  }
  return colors;
}

export function buildRiverArt(THREE,water,heightAt){
  const geometry=new THREE.PlaneGeometry(water.w,water.d,8,96);
  geometry.rotateX(-Math.PI/2);
  const positions=geometry.attributes.position,colors=[];
  const deep=new THREE.Color('#244c56'),shallows=new THREE.Color('#587a70'),glint=new THREE.Color('#819b96'),color=new THREE.Color();
  for(let i=0;i<positions.count;i++){
    const x=positions.getX(i),z=positions.getZ(i)+water.z;
    const depth=water.y-(heightAt(water.x+x,z)??water.y-3);
    const shallow=clamp01((1.5-depth)/1.35);
    const current=.5+.5*Math.sin(z*.08+x*.39+.7*Math.sin(z*.031));
    const thread=Math.pow(.5+.5*Math.sin(x*.85+z*.085),3)*(.34+.66*current);
    color.copy(deep).lerp(shallows,shallow*.68).lerp(glint,thread*(1-shallow)*.14);
    colors.push(color.r,color.g,color.b);
  }
  geometry.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));
  const river=new THREE.Mesh(geometry,new THREE.MeshStandardMaterial({vertexColors:true,roughness:.55,metalness:0}));
  river.name='RiverSurface';river.position.set(water.x,water.y,water.z);river.receiveShadow=true;
  return river;
}

// The box sides and the painted top occupy the old deck's exact bounds.
// Edge bars identify crossings by count, without building a rail or barrier.
export function buildBridgeArt(THREE,bridges){
  const material=new THREE.MeshStandardMaterial({vertexColors:true,roughness:.9,
    polygonOffset:true,polygonOffsetFactor:-1,polygonOffsetUnits:-1});
  const wall=new THREE.Color('#716d60'),foot=new THREE.Color('#565448'),deck=new THREE.Color('#969181');
  const edge=new THREE.Color('#827d6b'),paint=new THREE.Color('#c6b997');
  const names=[...bridges].sort((a,b)=>a.z-b.z).map(b=>b.id);
  const marks=[[12,12.7],[13.7,14.4],[15.4,16.1]],halfStations=[0,8,...marks.flat(),26,40];
  return bridges.map(b=>{
    const box=new THREE.BoxGeometry(b.w,b.thickness,b.d),p=box.attributes.position,n=box.attributes.normal;
    const positions=Array.from(p.array),normals=Array.from(n.array),indices=[],colors=[];
    const color=new THREE.Color();
    for(let i=0;i<p.count;i++)colors.push(...color.copy(p.getY(i)>0?wall:foot).toArray());
    for(const group of box.groups)if(group.materialIndex!==2)
      for(let i=group.start;i<group.start+group.count;i++)indices.push(box.index.getX(i));
    box.dispose();
    const xs=[...halfStations.slice(1).reverse().map(x=>-x),...halfStations],zs=[-1,-.81,-.59,.59,.81,1];
    const count=names.indexOf(b.id)+1;
    for(let j=0;j<zs.length-1;j++)for(let i=0;i<xs.length-1;i++){
      const low=xs[i],high=xs[i+1],mid=Math.abs((low+high)/2),outer=j===0||j===4;
      const marked=(j===1||j===3)&&marks.slice(0,count).some(([a,end])=>mid>a&&mid<end);
      const offset=positions.length/3;
      for(const [x,z] of [[low,zs[j]],[low,zs[j+1]],[high,zs[j]],[high,zs[j+1]]]){
        positions.push(x*b.w/80,b.thickness/2,z*b.d/2);normals.push(0,1,0);
        colors.push(...color.copy(marked?paint:outer?edge:deck).toArray());
      }
      indices.push(offset,offset+1,offset+2,offset+2,offset+1,offset+3);
    }
    const geometry=new THREE.BufferGeometry();
    for(const [name,values] of [['position',positions],['normal',normals],['color',colors]])
      geometry.setAttribute(name,new THREE.Float32BufferAttribute(values,3));
    geometry.setIndex(indices);
    const mesh=new THREE.Mesh(geometry,material);
    mesh.name=b.id;mesh.position.set(b.x,b.top-b.thickness/2,b.z);mesh.castShadow=true;mesh.receiveShadow=true;
    return mesh;
  });
}

function trunkShape(THREE){
  const sides=7,positions=[0,-.5,0],indices=[];
  // The tip sits on the sampled ground at the collider's lower centre. A
  // tapered foot avoids a floating flat cap without drawing solid wood below it.
  for(const y of [-.38,.5,.5])for(let i=0;i<sides;i++){
    const a=i*2*Math.PI/sides;positions.push(Math.sin(a),y,Math.cos(a));
  }
  const cap=positions.length/3;positions.push(0,.5,0);
  for(let i=0;i<sides;i++){
    const a=1+i,b=1+(i+1)%sides;
    indices.push(0,b,a,a,b,a+sides,b,b+sides,a+sides,cap,a+2*sides,b+2*sides);
  }
  const geometry=new THREE.BufferGeometry();
  geometry.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));
  geometry.setIndex(indices);geometry.computeVertexNormals();
  return geometry;
}

export function buildTreeArt(THREE,trees){
  const trunks=new THREE.InstancedMesh(trunkShape(THREE),new THREE.MeshStandardMaterial({color:0xffffff,roughness:1}),trees.length);
  const crowns=new THREE.InstancedMesh(new THREE.IcosahedronGeometry(1,0),new THREE.MeshStandardMaterial({color:0xffffff,roughness:1,flatShading:true}),trees.length*3);
  trunks.name='TreeTrunks';crowns.name='TreeCrowns';
  const transform=new THREE.Object3D(),colour=new THREE.Color();
  trees.forEach((t,i)=>{
    const seed=(Math.sin(t.x*8.12+t.z*5.91)+1)/2;
    transform.position.set(t.x,t.y+t.trunkHeight/2,t.z);transform.rotation.set(0,seed*Math.PI*2,0);
    transform.scale.set(t.radius,t.trunkHeight,t.radius);transform.updateMatrix();trunks.setMatrixAt(i,transform.matrix);
    trunks.setColorAt(i,colour.setHSL(.075+seed*.03,.22,.26+seed*.1,THREE.SRGBColorSpace));
    for(let lobe=0;lobe<3;lobe++){
      const a=seed*6.28+lobe*2.4,offset=lobe?t.crown*.42:0;
      transform.position.set(t.x+Math.cos(a)*offset,t.y+t.trunkHeight+(lobe?1.03:2.12),t.z+Math.sin(a)*offset);
      transform.rotation.set(0,a,0);
      const breadth=.91+.09*seed;
      transform.scale.set(t.crown*(lobe?.77:.88)*breadth,lobe?1.54:2.21,t.crown*(lobe?.75:.86)*breadth);
      transform.updateMatrix();crowns.setMatrixAt(i*3+lobe,transform.matrix);
      crowns.setColorAt(i*3+lobe,colour.setHSL(.21+seed*.087,.31+seed*.12,.30+seed*.10+(lobe?0:.047),THREE.SRGBColorSpace));
    }
  });
  for(const mesh of [trunks,crowns]){
    mesh.instanceMatrix.needsUpdate=true;mesh.instanceColor.needsUpdate=true;mesh.computeBoundingSphere();
    mesh.castShadow=true;mesh.receiveShadow=true;
  }
  return [trunks,crowns];
}
