class_name TankBattleMap
extends Control

const DEFAULT_HEADER := "SEVEN BASES · M to hide"
const HEADER_SIZE := 13
const HEADER_INSET := 10
const HUD_CONTEXT_MARGIN := 5.0
const MAP_PROXIMITY_MARGIN := 13.0

var snapshot: Dictionary = {}
var map_data: Dictionary = {}

func update_map(state: Dictionary, data: Dictionary) -> void:
	snapshot = state
	map_data = data
	queue_redraw()

func clear_accepted_state() -> void:
	snapshot = {}
	queue_redraw()

func point(x: float, z: float) -> Vector2:
	var span: float = map_data.get("size",320)
	return Vector2(12+(x/span+0.5)*(size.x-24),30+(z/span+0.5)*(size.y-48))

# Map-only proximity hint. It deliberately begins where the existing HUD's
# radius+5m context ends; it does not infer visibility, capture, or ownership.
func header_text() -> String:
	if not is_visible_in_tree() or snapshot.is_empty() or snapshot.get("staging", {}).get("waiting", true) or snapshot.get("won", false):
		return DEFAULT_HEADER
	var player_id = snapshot.get("playerId")
	if not player_id is String or player_id.is_empty(): return DEFAULT_HEADER
	var own: Dictionary = {}
	for player in snapshot.get("players", []):
		if player.id == player_id:
			own = player
			break
	if own.is_empty() or not own.get("connected", false) or own.get("health", 0) <= 0:
		return DEFAULT_HEADER
	var tank: Dictionary = own.get("tank", {})
	if not tank.has_all(["x", "z"]): return DEFAULT_HEADER
	var position := Vector2(float(tank.x), float(tank.z))
	if not position.is_finite(): return DEFAULT_HEADER
	var nearest_id := 8
	var nearest_distance := INF
	var nearest: Dictionary = {}
	for base in snapshot.get("capture", {}).get("bases", []):
		if not base.has_all(["id", "name", "x", "z", "radius"]): continue
		var id := str(base.id)
		if not id in ["1", "2", "3", "4", "5", "6", "7"] or not base.name is String or base.name.strip_edges().is_empty(): continue
		var radius := float(base.radius)
		var distance := position.distance_to(Vector2(float(base.x), float(base.z)))
		if not is_finite(distance) or not is_finite(radius) or radius <= 0: continue
		if distance < nearest_distance or (distance == nearest_distance and int(id) < nearest_id):
			nearest = base
			nearest_id = int(id)
			nearest_distance = distance
	if nearest.is_empty(): return DEFAULT_HEADER
	# Do not add a minimap prompt if the main HUD has context for any nearby base,
	# even if a farther centre is picked there because its radius is larger.
	for base in snapshot.get("capture", {}).get("bases", []):
		if not base.has_all(["x", "z", "radius"]): continue
		var radius := float(base.radius)
		var distance := position.distance_to(Vector2(float(base.x), float(base.z)))
		if is_finite(distance) and is_finite(radius) and radius > 0 and distance <= radius + HUD_CONTEXT_MARGIN:
			return DEFAULT_HEADER
	if nearest_distance > float(nearest.radius) + MAP_PROXIMITY_MARGIN: return DEFAULT_HEADER
	var title := "Near %d · %s" % [nearest_id, nearest.name]
	var full := title + " · M to hide"
	var font := ThemeDB.fallback_font
	var width := size.x - 2 * HEADER_INSET
	if font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_SIZE).x <= width:
		return full
	var compact := title + " [M]"
	return compact if font.get_string_size(compact, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_SIZE).x <= width else DEFAULT_HEADER

func _draw() -> void:
	draw_style_box(_background(),Rect2(Vector2.ZERO,size))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(HEADER_INSET,19),header_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,HEADER_SIZE,Color.WHITE)
	if map_data.is_empty(): return
	var water: Dictionary = map_data.water
	var west := point(-float(water.w)/2.0,-160)
	var east := point(float(water.w)/2.0,160)
	draw_rect(Rect2(west,east-west),Color("426d77"))
	for bridge in map_data.bridges:
		var a := point(bridge.x-bridge.w/2.0,bridge.z-bridge.d/2.0)
		var b := point(bridge.x+bridge.w/2.0,bridge.z+bridge.d/2.0)
		draw_rect(Rect2(a,b-a),Color("bdad82"))
	# Unknown is not neutral ownership. Keep only grey outlined static anchors.
	if snapshot.is_empty():
		for base in map_data.get("bases",[]):
			var p := point(base.x,base.z)
			draw_arc(p,5,0,TAU,16,Color("aaaaaa"),1.0)
			draw_string(font,p+Vector2(7,4),str(base.id),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("cccccc"))
		draw_string(font,Vector2(10,size.y-8),"State unavailable",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("cccccc"))
		return
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
