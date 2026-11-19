extends "res://scripts/tank_view.gd"
const Travel=preload("res://scripts/accepted_track_travel.gd")
var track_travel=Travel.new()
var donor_wheels=preload("res://scripts/leichttraktor_wheels.gd").new()
var gear=preload("res://scripts/physical_running_gear.gd").new()
func choose(id:String)->void:
	super.choose(id)
	track_travel.reset()
	donor_wheels.bind_model(model,id)
	if not gear.bind(model,id):
		gear.wheels.clear()
		gear.belts.clear()
		push_error("Running-gear asset contract failed: "+id)
func reset_track_history()->void:
	track_travel.reset()
	donor_wheels.reset_history()
	gear.reset_history()
func apply_player(player:Dictionary,own:bool)->void:
	super.apply_player(player,own)
	var t:Dictionary=player.tank
	var metres=track_travel.sample(Vector3(t.x,t.y,t.z),t.yaw,player.health>0)
	var active:bool=player.health>0 and player.get("connected",true)
	donor_wheels.consume(metres,track_travel.generation,track_travel.half_width,active)
	gear.consume(metres,track_travel.generation,track_travel.half_width,active)

