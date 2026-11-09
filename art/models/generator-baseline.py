"""Original Tank Battle hard-surface model. Run with installed Blender, --disable-autoexec.
All vertices/materials below are original; no external assets, fonts, scripts or textures.
Coordinates in helpers are game metres: X right, Y up, Z forward. glTF preserves this.
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector

OUT = Path(sys.argv[sys.argv.index('--')+1]).resolve()
VISUAL = sys.argv[sys.argv.index('--')+2] if len(sys.argv)>sys.argv.index('--')+2 else 'kestrel'
assert VISUAL in ('kestrel','bastion','foundry','palisade')
B = VISUAL == 'bastion'
F = VISUAL == 'foundry'
P = VISUAL == 'palisade'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.use_scripts_auto_execute = False
bpy.context.preferences.filepaths.save_version = 0
bpy.context.scene['original_work'] = 'Original Tank Battle geometry; authored in this project; no external model or texture'

def coord(p): return (p[0], -p[2], p[1])
palette = [('Armor',(.17,.23,.18,1),.67,.12),('Edge',(.29,.34,.26,1),.59,.20),
           ('Track',(.033,.040,.035,1),.82,.35),('Steel',(.105,.13,.125,1),.42,.58),
           ('Mark',(.82,.62,.28,1),.65,.05),('Optic',(.015,.08,.11,1),.20,.30)]
if F:
 palette[0]=('Armor',(.22,.245,.127,1),.76,.10)
 palette[1]=('Edge',(.31,.32,.186,1),.70,.13)
 palette[4]=('Mark',(.67,.63,.43,1),.80,.04)
if P:
 palette[0]=('Armor',(.225,.191,.124,1),.78,.11)
 palette[1]=('Edge',(.327,.288,.197,1),.70,.16)
 palette[4]=('Mark',(.66,.62,.46,1),.77,.04)
materials=[]
for name,color,rough,metal in palette:
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=color;bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal;materials.append(m)

class Builder:
 def __init__(self): self.v=[];self.f=[];self.m=[];self.s=[]
 def piece(self,vertices,faces,mat,smooth=None):
  n=len(self.v);self.v.extend(vertices);self.f.extend([[n+i for i in f]for f in faces]);self.m.extend([mat]*len(faces));self.s.extend(smooth if smooth is not None else [False]*len(faces))
 def box(self,c,s,mat=0,angle=0):
  x,y,z=c;w,h,d=[a/2 for a in s];v=[]
  for a,b,k in [(-w,-h,-d),(w,-h,-d),(w,-h,d),(-w,-h,d),(-w,h,-d),(w,h,-d),(w,h,d),(-w,h,d)]:
   v.append((x+a,y+b*math.cos(angle)-k*math.sin(angle),z+b*math.sin(angle)+k*math.cos(angle)))
  self.piece(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
 def loft(self,levels,mat=0,cast=False):
  # Each level is a clockwise XZ polygon as seen from above, at Y.
  v=[(x,y,z)for y,poly in levels for x,z in poly];n=len(levels[0][1]);f=[tuple(reversed(range(n))),tuple((len(levels)-1)*n+i for i in range(n))]
  for j in range(len(levels)-1):
   for i in range(n):k=(i+1)%n;f.append((j*n+i,j*n+k,(j+1)*n+k,(j+1)*n+i))
  self.piece(v,f,mat,[False,False]+[True]*(len(f)-2) if cast else None)
 def cyl(self,c,r,length,axis='x',mat=3,n=16,inner=0):
  # Rings with consistent outward normals. Optional annulus for barrel bore.
  def point(a,s,rad):
   u,v=rad*math.cos(a),rad*math.sin(a)
   return (c[0]+s,c[1]+u,c[2]+v)if axis=='x' else (c[0]+u,c[1]+v,c[2]+s)if axis=='z' else(c[0]+u,c[1]+s,c[2]-v)
  vertices=[point(i*2*math.pi/n,s,rad)for rad in ([r,inner]if inner else[r])for s in [-length/2,length/2]for i in range(n)]
  faces=[]
  for i in range(n):k=(i+1)%n;faces.append((i,k,n+k,n+i))
  if inner:
   for i in range(n):k=(i+1)%n;faces.extend([(2*n+k,2*n+i,3*n+i,3*n+k),(i,2*n+i,2*n+k,k),(n+k,3*n+k,3*n+i,n+i)])
  else:faces.extend([tuple(reversed(range(n))),tuple(n+i for i in range(n))])
  self.piece(vertices,faces,mat)
 def object(self,name,parent=None):
  mesh=bpy.data.meshes.new(name+'Mesh');mesh.from_pydata([coord(v)for v in self.v],[],self.f);mesh.materials.clear()
  for m in materials:mesh.materials.append(m)
  for poly,m,s in zip(mesh.polygons,self.m,self.s):poly.material_index=m;poly.use_smooth=s
  mesh.update();bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
  # Small original chamfers catch light on major panels, without rounding cleats,
  # optics or the exact bore/socket. Avoid blanket subdivision/material growth.
  if name in ('Hull','Turret'):
   edges=[e for e in bm.edges if len(e.link_faces)==2 and e.calc_length()>.45 and min(f.calc_area()for f in e.link_faces)>.06 and e.calc_face_angle()>.4]
   if edges:bmesh.ops.bevel(bm,geom=edges,offset=.018,segments=2,affect='EDGES',profile=.5,clamp_overlap=True,material=1)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
  obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.parent=parent;return obj

def octagon(w,rear,front,cut=.25):
 return [(-w+cut,rear),(w-cut,rear),(w,rear+cut),(w,front-cut),(w-cut,front),(-w+cut,front),(-w,front-cut),(-w,rear+cut)]
def cast_ring(w,d,center,power=1,n=20):
 return [(w*math.copysign(abs(math.cos(a))**power,math.cos(a)),
          center+d*math.copysign(abs(math.sin(a))**power,math.sin(a)))for a in [2*math.pi*i/n for i in range(n)]]
def empty(name,position,parent=None):
 obj=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(obj);obj.parent=parent;obj.location=coord(position);obj.empty_display_size=.18;return obj

root=empty('TankVisual',(0,0,0));root['visual_id']=VISUAL;root['units']='metres';root['forward']='+Z in glTF';root['gameplay_profile']='prototype'
h=Builder()
# Broad sloped glacis, inset lower tub, chamfered shoulder and rear engine deck.
if P:
 # Built-up plates and a stepped front, in contrast to Foundry's cast form.
 h.loft([(.40,octagon(1.05,-1.93,1.85,.15)),(.76,octagon(1.23,-2.07,2.08,.11)),
         (.92,octagon(1.24,-2.02,1.91,.09)),(1.18,octagon(1.21,-1.94,1.14,.09)),
         (1.32,octagon(1.17,-1.82,1.07,.09))])
 h.box((0,1.125,1.15),(2.34,.27,.14),1)
 h.box((-.57,1.20,1.23),(.45,.12,.06),3)
 h.cyl((.58,1.16,1.24),.12,.12,'z',3,12)
 h.box((0,1.32,-1.30),(1.80,.08,.72),1)
 for z in [-1.56,-1.40,-1.24,-1.08]:h.box((0,1.368,z),(1.56,.04,.065),3)
 h.cyl((0,.77,-2.00),.145,1.37,'x',3,12)
 for x in [-.53,.53]:h.box((x,1.355,.74),(.54,.045,.45),1)
elif F:
 # Original cast profile, scaled to the existing game envelope. The M4A1
 # reference is a period cue, not a dimensional drawing or replica.
 h.loft([(.42,cast_ring(1.04,1.79,-.04,.52)),(.72,cast_ring(1.33,2.05,-.02,.62)),
         (1.02,cast_ring(1.33,1.96,-.05,.63)),(1.24,cast_ring(1.22,1.72,-.18,.65)),
         (1.33,cast_ring(1.08,1.40,-.24,.66))],cast=True)
 h.loft([(.55,cast_ring(.98,.36,1.83,.64)),(.76,cast_ring(1.05,.34,1.83,.65)),
         (.99,cast_ring(.97,.25,1.78,.70))],1,cast=True)
 h.box((0,1.33,-1.22),(1.54,.08,.67),1)
 for x in [-.65,-.44,-.22,0,.22,.44,.65]:h.box((x,1.385,-1.22),(.075,.035,.51),3)
 for side in [-1,1]:
  h.cyl((side*.61,1.34,.77),.24,.08,'y',1,12)
  h.box((side*.61,1.39,.77),(.22,.04,.04),3)
 h.cyl((.68,1.07,1.49),.115,.14,'z',3,12)
elif B:
 h.loft([(.43,octagon(1.12,-1.71,1.78,.34)),(.86,octagon(1.37,-1.90,1.96,.62)),(1.32,octagon(1.31,-1.75,1.00,.46)),(1.39,octagon(1.19,-1.68,.85,.38))])
 h.loft([(1.38,octagon(.94,-1.65,-.91,.09)),(1.45,octagon(.85,-1.60,-.94,.09))],1)
 for z in [-1.50,-1.36,-1.22,-1.08]:h.box((0,1.47,z),(1.45,.035,.065),3)
else:
 h.loft([(.42,octagon(.98,-1.82,1.7,.24)),(.78,octagon(1.31,-2.02,2.04,.32)),(1.19,octagon(1.29,-1.96,1.61,.32)),(1.28,octagon(1.20,-1.85,1.50,.28))])
 h.loft([(1.27,octagon(.99,-1.81,-.73,.16)),(1.32,octagon(.94,-1.75,-.78,.16))],1)
 for x in [-.66,-.42,-.18,.06,.30,.54,.78]:h.box((x,1.34,-1.36),(.10,.035,.55),3)
# Continuous hollow track loops and inset wheels; all authored within existing envelope.
for side in [-1,1]:
 x=side*1.53;profile=[]
 for center,start in [(1.57,-math.pi/2),(-1.57,math.pi/2)]:
  for i in range(9):a=start+i*math.pi/8;profile.append((center+.55*math.cos(a),.525+.55*math.sin(a)))
 inner=[(z*.97,.525+(y-.525)*.73)for z,y in profile];n=len(profile);v=[]
 for xx in [x-.28,x+.28]:
  for loop in [profile,inner]:v.extend((xx,y,z)for z,y in loop)
 f=[]
 for i in range(n):k=(i+1)%n;f.extend([(i,k,2*n+k,2*n+i),(n+k,n+i,3*n+i,3*n+k),(i,n+i,n+k,k),(2*n+k,3*n+k,3*n+i,2*n+i)])
 h.piece(v,f,2)
 # Individual cleats follow the actual track polygon, not a row of floating blocks.
 for i,(z,y) in enumerate(profile):
  zz,yy=profile[(i+1)%n];length=math.hypot(zz-z,yy-y);count=max(1,round(length/.18));a=-math.atan2(yy-y,zz-z)
  for j in range(count):t=(j+.5)/count;h.box((x,y+(yy-y)*t,z+(zz-z)*t),(.59,.045,length/count*.78),3,a)
 wheel_z=[(i-3.5)*.404 for i in range(8)] if P else ([-1.35,-.95,-.20,.20,.95,1.35] if F else ([-1.50,-.75,0,.75,1.50] if B else [-1.55,-.93,-.31,.31,.93,1.55]))
 for z in wheel_z:
  if P:
   h.cyl((x,.325,z),.208,.42,'x',2,12);h.cyl((side*1.765,.325,z),.157,.05,'x',1,10);h.cyl((side*1.798,.325,z),.052,.035,'x',3,8)
   continue
  if F:
   h.cyl((x,.40,z),.31,.43,'x',2,12);h.cyl((side*1.77,.40,z),.23,.035,'x',1,10);h.cyl((side*1.80,.40,z),.09,.045,'x',3,8)
   continue
  h.cyl((x,.48,z),.46 if B else .43,.43,'x',2,16);h.cyl((side*1.77,.48,z),.35 if B else .32,.035,'x',1,12);h.cyl((side*1.80,.48,z),.13,.045,'x',3,12)
 if P:
  for z in [-1.57,1.57]:h.cyl((x,.55,z),.415,.49,'x',3,14);h.cyl((side*1.79,.55,z),.28,.03,'x',1,12)
  h.box((side*1.52,1.115,-.02),(.62,.07,4.02),1)
  # Shallow offset shields leave the eight wheels visible below.
  for z in [-1.43,-.74,-.05,.64,1.33]:
   h.box((side*1.81,.88,z),(.064,.40,.65),0);h.box((side*1.82,1.084,z),(.04,.032,.47),1)
  for z in [-1.88,1.84]:h.cyl((side*.88,.78,z),.104,.09,'z',3,10,.052)
  continue
 if F:
  for z in [-1.57,1.57]:h.cyl((x,.55,z),.43,.48,'x',3,14);h.cyl((side*1.79,.55,z),.29,.03,'x',1,12)
  for z in [-1.15,0,1.15]:h.box((side*1.74,.67,z),(.13,.29,.48),0);h.cyl((side*1.79,.84,z-.14),.115,.08,'x',3,10)
  h.box((side*1.52,1.11,-.07),(.62,.065,3.86),1)
  h.box((side*1.42,1.18,-.99),(.20,.20,.51),0)
  for z in [-1.9,1.86]:h.cyl((side*.81,.74,z),.11,.10,'z',3,12,.052)
  continue
 # Split side skirt, shoulders, tow eyes and restrained external stowage.
 for z in ([-1.03,.10,1.23]if B else[-1.3,-.46,.38,1.22]):h.box((side*1.38,1.14,z),(.13,.55 if B else .41,1.03 if B else .76),0)
 h.box((side*1.53,1.33 if B else 1.19,-.25 if B else 0),(.64,.09,3.10 if B else 3.98),1)
 for z in [-1.90,1.82]:h.cyl((side*.87,.76,z),.12,.09,'z',3,12,.065)
 h.box((side*.92,1.30,.88),(.38,.06,.20),3)
 # Original bolt heads and grab rails; details stay inside the current envelope.
 for z in [-1.25,-.45,.35,1.15]:h.cyl((side*1.46,1.15,z),.032,.025,'x',3,6)
 top=1.47 if B else 1.36
 h.box((side*1.04,top,-.40),(.055,.055,.58),3)
 for z in [-.66,-.14]:h.box((side*1.04,top-.055,z),(.055,.11,.055),3)
# Original identification stripe, rear grille and exhaust; no historical insignia.
h.box((-.58,1.224,1.45),(.12,.025,.42),4);h.box((-.35,1.224,1.45),(.12,.025,.42),4)
for x in [-.70,-.50,-.30,-.10,.10,.30,.50,.70]:h.box((x,.91,-2.01),(.085,.29,.045),3)
h.object('Hull',root)

yaw=empty('TurretYaw',(0,1.65,0),root);yaw['axis']='local +Y';t=Builder()
t.cyl((0,-.30,-.03),.79,.10,'y',3,20)
if P:
 # Faceted turret with a separate, visibly spaced rear shield.
 t.loft([(-.30,octagon(.83,-1.08,.85,.24)),(-.17,octagon(.96,-1.15,.83,.22)),
         (.23,octagon(.91,-1.07,.70,.20)),(.35,octagon(.77,-.98,.54,.17))])
 t.loft([(-.17,octagon(.57,.49,.88,.10)),(.18,octagon(.48,.50,.88,.09))],1)
 for side in [-1,1]:
  t.box((side*.99,.015,-.45),(.075,.43,1.08),1)
  t.box((side*.91,.04,-.43),(.24,.07,.52),3)
  t.box((side*.74,.19,.33),(.14,.09,.18),5)
 t.box((0,.014,-1.16),(1.82,.42,.073),1)
 t.box((0,.014,-1.206),(.38,.13,.026),4)
 t.cyl((0,.42,-.43),.29,.18,'y',0,16)
 t.cyl((0,.53,-.43),.27,.062,'y',1,16)
 t.box((0,.572,-.43),(.22,.04,.055),3)
elif F:
 t.loft([(-.31,cast_ring(.84,1.02,-.10,.78)),(-.16,cast_ring(.97,1.14,-.12,.84)),
         (.12,cast_ring(.94,1.09,-.17,.90)),(.36,cast_ring(.80,.91,-.21,.94)),
         (.46,cast_ring(.63,.72,-.24,1))],cast=True)
 t.cyl((0,-.01,.69),.31,.66,'x',1,16)
 t.cyl((-.27,.48,-.31),.29,.13,'y',1,14)
 t.cyl((-.27,.56,-.31),.25,.045,'y',0,14)
 t.box((-.27,.598,-.31),(.24,.045,.045),3)
 t.box((.34,.48,-.25),(.28,.065,.38),1)
 t.box((.32,.515,-.05),(.16,.07,.05),5)
 t.box((0,.07,-1.23),(.42,.13,.025),4)
elif B:
 t.loft([(-.29,octagon(.99,-1.32,.95,.13)),(.03,octagon(.99,-1.30,.89,.17)),(.36,octagon(.77,-1.12,.51,.12)),(.42,octagon(.71,-1.05,.44,.09))],0)
 t.loft([(-.10,octagon(.88,-1.49,-1.06,.10)),(.20,octagon(.78,-1.43,-1.10,.10))],1)
else:
 t.loft([(-.29,octagon(.96,-.98,.95,.30)),(.06,octagon(.99,-.88,.81,.30)),(.30,octagon(.77,-.75,.59,.27)),(.35,octagon(.69,-.67,.51,.25))],0)
 t.loft([(-.12,octagon(.83,-1.12,-.70,.10)),(.17,octagon(.76,-1.12,-.72,.10))],1)
# Small cheek shields, commander hatch and periscopes. Chamfers provide a clear silhouette.
for side in ([] if F or P else [-1,1]):
 t.loft([(-.15,[(side*.43,.82),(side*.85,.60),(side*.94,.16),(side*.71,.10)]),(.08,[(side*.40,.76),(side*.76,.56),(side*.82,.18),(side*.65,.14)])],1)
 t.box((side*.62,.18,.25),(.10,.10,.26),5)
if F or P:
 pass
elif B:
 for x in [-.35,.35]:t.box((x,.46,-.41),(.47,.08,.48),1);t.box((x,.51,-.40),(.23,.04,.045),3)
 t.box((-.40,.50,-.13),(.30,.15,.14),1);t.box((-.40,.52,-.05),(.23,.075,.025),5)
 t.box((.0,.03,-1.49),(.50,.17,.035),4)
else:
 t.cyl((-.20,.39,-.18),.34,.08,'y',1,16);t.box((-.20,.455,-.18),(.27,.045,.055),3)
 t.box((.35,.38,-.30),(.28,.08,.24),1);t.box((.35,.43,-.20),(.20,.07,.04),5)
 t.box((.0,.03,-1.14),(.50,.17,.035),4)
t.object('Turret',yaw)

pitch=empty('BarrelPitch',(0,0,.75),yaw);pitch['axis']='local +X;resting local pitch0;no gameplay elevation added'
b=Builder();b.cyl((0,0,0),.28,.68,'x',1,16);b.cyl((0,0,.16),.18,.36,'z',3,16)
if B:b.box((0,0,.32),(.36,.28,.38),1)
b.cyl((0,0,1.55),.105,2.95,'z',3,12,.057)
for z in ([.52] if F or P else [.50,1.28,2.64]):b.cyl((0,0,z),.133,.12,'z',1,12,.105)
# Bored muzzle end terminates exactly at the authoritative resting socket z4.05.
if P:
 b.cyl((0,0,3.20),.164,.20,'z',3,12,.064)
 for side in [-1,1]:
  for z in [3.07,3.25]:b.box((side*.132,0,z),(.12,.18,.081),3)
else:b.cyl((0,0,3.18),.12 if F else .19 if B else .155,.24,'z',3,12,.064)
b.object('Barrel',pitch)
socket=empty('Muzzle',(0,0,3.30),pitch);socket['contract']='model (0,1.65,4.05) at rest;forward +Z;no socket recoil'

# Save editable original before any studio-only objects are added. No embedded text/script.
model_objects=list(bpy.context.scene.objects)
for obj in model_objects:obj.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(VISUAL+'.blend')))
bpy.ops.export_scene.gltf(filepath=str(OUT/(VISUAL+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_animations=False)
if '--mesh-only' in sys.argv[sys.argv.index('--')+3:]:
 print('ORIGINAL_TANK_EXPORTED',str(OUT))
 sys.exit(0)

scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12 if F or P else 32
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=640 if F or P else 1000;scene.render.resolution_y=480 if F or P else 800;scene.render.resolution_percentage=100
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.22,.26,.25,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.055));floor=bpy.context.object;floor.name='StudioFloor';floor.data.materials.append(materials[3])
for name,pos,power,size in [('Key',(4,7,7),1500,7),('Fill',(-5,2,4),950,6),('Rim',(1,-6,6),1800,5)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=coord(pos);obj.rotation_euler=(Vector(coord((0,1,0)))-obj.location).to_track_quat('-Z','Y').to_euler()
camera_data=bpy.data.cameras.new('StudioCamera');camera=bpy.data.objects.new('StudioCamera',camera_data);scene.collection.objects.link(camera);scene.camera=camera;camera_data.type='ORTHO';camera_data.ortho_scale=8.2
for name,pos in [('front',(7,5.5,8)),('rear',(-7,4.5,-8))]:
 camera.location=coord(pos);camera.rotation_euler=(Vector(coord((0,1,.45)))-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(OUT/('studio-'+name+'.png'));bpy.ops.render.render(write_still=True)
print('ORIGINAL_TANK_EXPORTED',str(OUT))
