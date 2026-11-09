class_name TankBattleMap
extends Control

var snapshot: Dictionary = {}
var map_data: Dictionary = {}

func update_map(state: Dictionary, data: Dictionary) -> void:
	snapshot = state
	map_data = data
	queue_redraw()

func point(x: float, z: float) -> Vector2:
	var span: float = map_data.get("size",320)
	return Vector2(12+(x/span+0.5)*(size.x-24),30+(z/span+0.5)*(size.y-48))

func _draw() -> void:
	draw_style_box(_background(),Rect2(Vector2.ZERO,size))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(10,19),"SEVEN BASES · M to hide",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	if map_data.is_empty(): return
	var water: Dictionary = map_data.water
	var west := point(-float(water.w)/2.0,-160)
	var east := point(float(water.w)/2.0,160)
	draw_rect(Rect2(west,east-west),Color("426d77"))
	for bridge in map_data.bridges:
		var a := point(bridge.x-bridge.w/2.0,bridge.z-bridge.d/2.0)
		var b := point(bridge.x+bridge.w/2.0,bridge.z+bridge.d/2.0)
		draw_rect(Rect2(a,b-a),Color("bdad82"))
	for base in snapshot.get("capture",{}).get("bases",[]):
		var p := point(base.x,base.z)
		var color := Color("79c9f0") if base.owner == "blue" else Color("ef9b88") if base.owner == "red" else Color("f1e6ba")
		if base.owner == "blue": draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),color)
		elif base.owner == "red": draw_colored_polygon(PackedVector2Array([p+Vector2(0,-6),p+Vector2(6,5),p+Vector2(-6,5)]),color)
		else: draw_circle(p,5,color)
		draw_string(font,p+Vector2(7,4),str(base.id),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		if base.get("contested",false): draw_arc(p,9,0,TAU,16,Color.WHITE,1.5)
	for player in snapshot.get("players",[]):
		var p := point(player.tank.x,player.tank.z)
		var color := Color("6ac4ed") if player.team == "blue" else Color("f08c79")
		if player.health <= 0: continue
		var yaw: float = player.tank.yaw
		var heading := Vector2(sin(yaw),cos(yaw))
		var side := Vector2(heading.y,-heading.x)
		draw_colored_polygon(PackedVector2Array([p+heading*5,p-heading*3+side*3,p-heading*3-side*3]),color)
		if player.id == snapshot.get("playerId",""): draw_arc(p,7,0,TAU,16,Color.WHITE,1.5)
	draw_string(font,Vector2(10,size.y-8),"Blue | Red | Neutral",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("deded4"))

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04,0.08,0.07,0.93)
	style.corner_radius_top_left = 5
	style.corner_radius_bottom_right = 5
	return style
