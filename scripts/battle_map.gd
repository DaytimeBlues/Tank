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
	return disc_center()+Vector2(x,z)*(disc_radius()*1.34/maxf(span,1.0))

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

var marker_id := ""
var glyph := ""
const DARK := Color("#10212b")
const GRID := Color("#42707b")
const CYAN := Color("#85dff1")
const AMBER := Color("#ffc272")

func disc_center() -> Vector2: return Vector2(size.x*0.5,(size.y+6)*0.5)
func disc_radius() -> float: return minf(size.x*0.5-8,size.y*0.5-24)
# Share the same painted regions between native GUI routing and world input.
# Transparent corners belong to the battlefield, including right-drag free look.
func ink_at(p: Vector2) -> bool:
	if not Rect2(Vector2.ZERO,size).has_point(p) or disc_radius()<12: return false
	return p.y<24 or (not map_data.is_empty() and p.y>=size.y-19) or p.distance_squared_to(disc_center())<=pow(disc_radius()+0.75,2)

func _has_point(p: Vector2) -> bool: return ink_at(p)

func set_marker(id: String, symbol: String) -> void:
	if marker_id==id and glyph==symbol: return
	marker_id=id
	glyph=symbol
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := disc_center()
	var r := disc_radius()
	if r<12: return
	draw_rect(Rect2(0,0,size.x,24),DARK)
	draw_string(font,Vector2(0,17),header_text(),HORIZONTAL_ALIGNMENT_CENTER,size.x,HEADER_SIZE,Color.WHITE)
	draw_circle(c,r,DARK)
	draw_arc(c,r,0,TAU,64,CYAN,1.5,true)
	draw_arc(c,r*0.62,0,TAU,48,GRID,1,true)
	draw_arc(c,r*0.32,0,TAU,32,GRID,1,true)
	draw_line(c-Vector2(r-2,0),c+Vector2(r-2,0),GRID)
	draw_line(c-Vector2(0,r-2),c+Vector2(0,r-2),GRID)
	if map_data.is_empty(): return
	if map_data.has("water"):
		var half_w := float(map_data.water.w)*0.5
		var west := point(-half_w,-160)
		draw_rect(Rect2(west,point(half_w,160)-west),Color("#284b59"))
		for bridge in map_data.get("bridges",[]):
			var a := point(bridge.x-bridge.w/2.0,bridge.z-bridge.d/2.0)
			draw_rect(Rect2(a,point(bridge.x+bridge.w/2.0,bridge.z+bridge.d/2.0)-a),Color("#aab3a4"))
	for base in map_data.get("bases",[]) if snapshot.is_empty() else snapshot.get("capture",{}).get("bases",[]):
		var p := point(base.x,base.z)
		var owner: String = base.get("owner","unknown")
		if owner=="blue":
			draw_rect(Rect2(p-Vector2(4,4),Vector2(8,8)),CYAN)
		elif owner=="red":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-5),p+Vector2(5,4),p+Vector2(-5,4)]),AMBER)
		else: draw_arc(p,4,0,TAU,12,Color.WHITE,1.3)
		draw_string(font,p+Vector2(6,4),str(base.id),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		if base.get("contested",false) or str(base.id)==marker_id:
			draw_arc(p,8,0,TAU,20,Color.WHITE,1.5)
		if str(base.id)==marker_id:
			draw_circle(p+Vector2(-7,-9),7,DARK)
			draw_string(font,p+Vector2(-14,-5),glyph,HORIZONTAL_ALIGNMENT_CENTER,14,12,Color.WHITE)
	# Fixed public bases plus own marker only. Never reveal another player's position.
	for player in snapshot.get("players",[]):
		if player.get("id")!=snapshot.get("playerId") or not player.get("connected",false) or player.get("health",0)<=0: continue
		var tank: Dictionary = player.get("tank",{})
		if not tank.has_all(["x","z","yaw"]): break
		var p := point(tank.x,tank.z)
		var h := Vector2(sin(tank.yaw),cos(tank.yaw))
		var side := Vector2(h.y,-h.x)
		draw_circle(p,7,DARK)
		draw_colored_polygon(PackedVector2Array([p+h*6,p-h*4+side*4,p-h*4-side*4]),Color.WHITE)
		break
	var caption := "State unavailable" if snapshot.is_empty() else "■ Blue   ▲ Red   ○ Neutral"
	draw_rect(Rect2(0,size.y-19,size.x,19),DARK)
	draw_string(font,Vector2(0,size.y-5),caption,HORIZONTAL_ALIGNMENT_CENTER,size.x,12,Color.WHITE)
