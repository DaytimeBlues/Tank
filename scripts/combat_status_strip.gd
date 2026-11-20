extends Control
# Accepted-state instrument only; never predicts firing, damage or timer completion.
const Kit = preload("res://scripts/field_kit.gd")
var reading:Dictionary={"mode":"unavailable","status":"STATUS UNAVAILABLE","health":-1,"progress":0.0}
var plate:=StyleBoxFlat.new()
func _init():
 plate.bg_color=Color("#10212b");plate.border_color=Color("#5b9caa");plate.set_border_width_all(1);plate.set_corner_radius_all(3)
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 custom_minimum_size=Vector2(320,68)
 size=custom_minimum_size
func retire()->void:
 reading={"mode":"unavailable","status":"STATUS UNAVAILABLE","health":-1,"progress":0.0};queue_redraw()
func present(state:Dictionary,own:Dictionary,seated:bool,age:int,paused:bool)->void:
 retire()
 if not seated or age<0 or age>1000 or own.is_empty() or not own.get("connected",false):return
 var health=own.get("health",null);var reload_value=own.get("tank",{}).get("reload",null)
 if not (health is int or health is float) or not (reload_value is int or reload_value is float):return
 var duration: float = preload("res://scripts/trial_role_readout.gd").duration(state,own)
 if duration<=0.0:return
 if not is_finite(float(health)) or not is_finite(float(reload_value)) or health<0 or health>3 or float(health)!=int(health) or reload_value<0 or reload_value>duration:return
 reading={"mode":"ready","status":"READY","health":int(health),"progress":1.0-float(reload_value)/duration,"reload":float(reload_value)}
 if state.get("staging",{}).get("waiting",true):reading.mode="waiting";reading.status="WAITING FOR BATTLE";reading.progress=0.0
 elif state.get("won",false):reading.mode="complete";reading.status="MATCH COMPLETE";reading.progress=0.0
 elif health<=0:reading.mode="dead";reading.status="RESPAWNING";reading.progress=0.0
 elif paused:reading.mode="paused";reading.status="CONTROLS PAUSED"
 elif reload_value>0:reading.mode="reload";reading.status="RELOAD %.1f s" % reload_value
 queue_redraw()
func _draw():
 var font=ThemeDB.fallback_font
 draw_style_box(plate,Rect2(Vector2.ZERO,size))
 var accent=Kit.RED if reading.mode=="reload" else Kit.BLUE
 draw_line(Vector2(212,10),Vector2(212,size.y-10),Kit.EDGE,1)
 draw_string(font,Vector2(12,18),"CANNON",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Kit.MUTED)
 draw_string(font,Vector2(12,40),reading.status,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Kit.PAPER)
 draw_rect(Rect2(12,49,185,7),Color("#34474a"))
 if reading.health>=0:draw_rect(Rect2(12,49,185*reading.progress,7),accent)
 draw_string(font,Vector2(226,18),"HULL",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Kit.MUTED)
 for i in 3:
  var box=Rect2(226+i*25,25,21,10)
  draw_rect(box,Kit.PAPER if reading.health>i else Color("#34474a"));draw_rect(box,Kit.EDGE,false,1)
 draw_string(font,Vector2(226,57),str(reading.health)+" / 3" if reading.health>=0 else "-- / 3",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Kit.PAPER)
