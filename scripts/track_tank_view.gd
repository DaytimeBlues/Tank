extends "res://scripts/tank_view.gd"
const Travel=preload("res://scripts/accepted_track_travel.gd")
var track_travel=Travel.new()
var track_material:ShaderMaterial
var track_surfaces:=0
func choose(id:String)->void:
	super.choose(id)
	track_travel.reset()
	track_surfaces=0
	track_material=null
	# Preserve unsupported donor exactly; do not invent surface mappings.
	if id=="leichttraktor":return
	track_material=ShaderMaterial.new()
	track_material.shader=preload("res://scripts/track_pilot.gdshader")
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source=mesh.get_active_material(surface)
			if source!=null and source.resource_name=="Track":
				mesh.set_surface_override_material(surface,track_material)
				track_surfaces+=1
	assert(track_surfaces==1)
func reset_track_history()->void:
	track_travel.reset()
	if track_material!=null:
		track_material.set_shader_parameter("left_metres",0.0)
		track_material.set_shader_parameter("right_metres",0.0)
func apply_player(player:Dictionary,own:bool)->void:
	super.apply_player(player,own)
	var t:Dictionary=player.tank
	var metres=track_travel.sample(Vector3(t.x,t.y,t.z),t.yaw,player.health>0)
	if track_material!=null:
		track_material.set_shader_parameter("left_metres",metres.x)
		track_material.set_shader_parameter("right_metres",metres.y)
