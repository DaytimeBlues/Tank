extends Node3D

var arena: TankArenaView
var transport := TankPortTransport.new()
var camera: Camera3D
var peers: Dictionary = {}
var old_shots: Dictionary = {}
var effects: Array = []
var shot_effects: TankAcceptedShotEffects
var state: Dictionary = {}
var status_label: Label
var stats_label: Label
var room_field: LineEdit
var port_field: LineEdit
var roster: OptionButton
var ready_button: Button
var start_button: Button
var rejoin_button: Button
var connect_buttons: Array[Button] = []
var panel: PanelContainer
var hud_panel: PanelContainer
var paused_controls := false
var controls_blocked := false
var window_focused := true
var input_elapsed := 0.0
var camera_seeded := false
var roster_label: Label
var switch_button: Button
var rematch_button: Button
var map_view: TankBattleMap
var toolbar: HBoxContainer
var map_enabled := true
var previous_won := false
var previous_alive := false
signal presentation_preparation_finished
var presentation_preparation_complete := false
var presentation_prepared := false

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("8b9d9d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6d1c6")
	settings.ambient_light_energy = 0.30
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52,-35,0)
	light.light_color = Color("fff0d5")
	light.light_energy = 0.95
	light.shadow_enabled = true
	add_child(light)
	shot_effects = TankAcceptedShotEffects.new(self)
	effects = shot_effects.active
	arena = TankArenaView.new()
	arena.name = "Arena"
	add_child(arena)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/arena.json"))
	arena.build(data)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 650.0
	camera.position = Vector3(-145,25,-65)
	add_child(camera)
	camera.look_at(Vector3(-118,3,-46))
	_build_ui()
	var initial_status := status_label.text
	status_label.text = "Loading battlefield."
	shot_effects.scene_startup_finished.connect(func(ok: bool):
		if ok: status_label.text = "Preparing shot feedback."
	)
	controls_blocked = true
	for button in connect_buttons: button.disabled = true
	transport.joined.connect(func(code: String):
		room_field.text = code
		camera_seeded = false
		controls_blocked = true
		# The immediate legacy format has no trees; render its actual authoritative map.
		if transport.map_data.get("version",0) != arena.source_data.get("version",0):
			remove_child(arena)
			arena.queue_free()
			arena = TankArenaView.new()
			arena.name = "Arena"
			add_child(arena)
			arena.build(transport.map_data)
		status_label.text = "Seat acknowledged. Waiting for its authoritative snapshot."
	)
	transport.state_received.connect(_accept_state)
	transport.server_notice.connect(func(message: String): status_label.text = message)
	transport.failed.connect(_network_error)
	get_viewport().size_changed.connect(_fit_ui)
	_fit_ui()
	presentation_prepared = await shot_effects.prepare()
	presentation_preparation_complete = true
	print("TANK_EFFECTS_PREPARATION "+JSON.stringify(shot_effects.preparation_report))
	if not presentation_prepared:
		status_label.text = "Shot feedback could not prepare. Reload this page to retry."
		_neutral()
		push_error("Accepted-shot presentation preparation failed; READY withheld.")
		presentation_preparation_finished.emit()
		return
	status_label.text = initial_status
	for button in connect_buttons: button.disabled = false
	print("TANK_GODOT_READY chunks=%d bridges=%d trees=%d" % [arena.terrain_chunks,arena.bridge_count,arena.tree_count])
	presentation_preparation_finished.emit()

func _label(text: String, parent: Node) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result

func _button(text: String, parent: Node, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(func():
		if not presentation_prepared:
			controls_blocked = true
			_neutral()
			return
		callback.call()
		controls_blocked = true
		_neutral()
		get_viewport().gui_release_focus()
	)
	parent.add_child(result)
	return result

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	panel = PanelContainer.new()
	panel.position = Vector2(16,58)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055,0.085,0.075,0.94)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.corner_radius_top_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel",style)
	canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	scroll.add_child(content)
	var heading := _label("TANK BATTLE",content)
	heading.add_theme_font_size_override("font_size",22)
	_label("Capture all seven bases. One player, one tank. Up to eight players.",content)
	var fields := HBoxContainer.new()
	content.add_child(fields)
	port_field = LineEdit.new()
	port_field.text = "5218"
	port_field.placeholder_text = "Local port"
	port_field.custom_minimum_size.x = 75
	fields.add_child(port_field)
	port_field.visible = not OS.has_feature("web")
	room_field = LineEdit.new()
	room_field.placeholder_text = "Six-character room code"
	room_field.max_length = 6
	room_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(room_field)
	roster = OptionButton.new()
	for id in TankPortVisual.IDS:
		roster.add_item(id.capitalize())
	content.add_child(roster)
	roster.item_selected.connect(func(_index: int): get_viewport().gui_release_focus())
	for field in [port_field,room_field]:
		field.text_submitted.connect(func(_text: String): get_viewport().gui_release_focus())
	status_label = _label("Teacher: create a room. Students: enter its code and join. Both teams must mark Ready before the host starts.",content)
	var buttons := HFlowContainer.new()
	content.add_child(buttons)
	connect_buttons.append(_button("Teacher: Create room",buttons,func(): _connect_room("create","4v4")))
	connect_buttons.append(_button("Join room",buttons,func(): _connect_room("join","4v4")))
	roster_label = _label("Room roster will appear here. No student names or email accounts are needed.",content)
	var ready_row := HFlowContainer.new()
	content.add_child(ready_row)
	ready_button = _button("Mark Ready",ready_row,func():
		var own := own_player()
		if not own.is_empty(): transport.send({"type":"ready","ready":not own.get("ready",false)})
	)
	start_button = _button("Start battle",ready_row,func(): transport.send({"type":"start"}))
	switch_button = _button("Balance team",ready_row,func():
		var team: String = state.get("staging",{}).get("switchTo","")
		if not team.is_empty(): transport.send({"type":"switchTeam","team":team})
	)
	rejoin_button = _button("Rejoin seat",ready_row,func():
		if transport.rejoin() != OK: _network_error("No in-memory seat is available to rejoin.")
	)
	rematch_button = _button("Rematch",ready_row,func(): transport.send({"type":"restart"}))
	_button("Controls / Resume",ready_row,func():
		paused_controls = not paused_controls
		controls_blocked = true
		_neutral()
		_show_room_panel()
	)
	ready_button.disabled = true
	start_button.disabled = true
	rejoin_button.disabled = true
	rematch_button.disabled = true
	switch_button.disabled = true
	# Ready/Start stay before a growing eight-seat roster in the scroll view.
	content.move_child(ready_row,roster_label.get_index())
	_label("W/S drive · A/D turn · pointer/arrows aim · Space/click fire. Capture all 7 bases to win. Each hull takes 3 hits; cannon reload is 4 seconds. Online play continues while the menu is open.",content)
	if OS.has_feature("web"):
		_button("Private access / invitations",content,func():
			var location = JavaScriptBridge.get_interface("location")
			location.href = "/access"
		)
	toolbar = HBoxContainer.new()
	toolbar.position = Vector2(16,16)
	canvas.add_child(toolbar)
	_button("Menu / Room · Esc",toolbar,func():
		paused_controls = not paused_controls
		_show_room_panel()
	)
	_button("Map · M",toolbar,func():
		map_enabled = not map_enabled
		map_view.visible = map_enabled
	)
	map_view = TankBattleMap.new()
	canvas.add_child(map_view)
	hud_panel = PanelContainer.new()
	hud_panel.add_theme_stylebox_override("panel",style.duplicate())
	canvas.add_child(hud_panel)
	stats_label = _label("W/S drive · A/D turn · arrows or pointer aim · Space / click fire\nEscape or focus loss cancels controls. Online play continues.",hud_panel)
	# Autowrap initially measures at a one-pixel width. Bound that minimum
	# height before the parent container's first layout to keep this HUD onscreen.
	stats_label.max_lines_visible = 4

func _fit_ui() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	panel.size = Vector2(minf(420,viewport_size.x-32),minf(470,viewport_size.y-220))
	map_view.size = Vector2(206,224)
	map_view.position = Vector2(viewport_size.x-222,58)
	if viewport_size.x < 720:
		map_enabled = false
		map_view.visible = false
	stats_label.custom_minimum_size.x = minf(388,viewport_size.x-64)
	stats_label.size.x = stats_label.custom_minimum_size.x
	hud_panel.position = Vector2(16,viewport_size.y-140)
	hud_panel.size = Vector2(minf(420,viewport_size.x-32),124)

func _backend_url() -> String:
	return "ws://127.0.0.1:"+port_field.text.strip_edges()

func _show_room_panel() -> void:
	panel.visible = paused_controls or state.is_empty() or state.get("staging",{}).get("waiting",false) or state.get("won",false)

static func normalized_bearing(offset: Vector2) -> float:
	return atan2(offset.x,offset.y)/PI

func _connect_room(kind: String, format_value: String) -> void:
	if not presentation_prepared:
		controls_blocked = true
		input_elapsed = 0
		status_label.text = "Shot feedback could not prepare. Reload this page to retry." if presentation_preparation_complete else "Preparing shot feedback."
		_neutral()
		return
	for button in connect_buttons: button.disabled = true
	var request := {"type":kind,"mode":"battle","format":format_value,"role":"commander","team":"auto","visualId":TankPortVisual.IDS[roster.selected],"tankId":"prototype"}
	if kind == "join": request["code"] = room_field.text.strip_edges().to_upper()
	state = {}
	old_shots.clear()
	shot_effects.clear()
	camera_seeded = false
	status_label.text = "Connecting to the room."
	var error: Error = transport.open_browser(request) if OS.has_feature("web") else transport.open_local(_backend_url(),request)
	if error != OK:
		_network_error("Connection could not start. Check the classroom page or local backend.")

func own_player() -> Dictionary:
	for player in state.get("players",[]):
		if player.id == state.get("playerId",""): return player
	return {}

func _network_error(message: String) -> void:
	status_label.text = message
	controls_blocked = true
	state = {}
	old_shots.clear()
	shot_effects.clear()
	stats_label.text = "Disconnected. Controls are neutral. Recovering the same seat for up to 22 seconds." if transport.is_recovering() else "Connection stopped. Check the room code and join again. If access expired, return to Private access."
	ready_button.disabled = true
	start_button.disabled = true
	rematch_button.disabled = true
	switch_button.disabled = true
	for button in connect_buttons: button.disabled = not presentation_prepared or transport.is_recovering()
	_show_room_panel()

func _accept_state(snapshot: Dictionary) -> void:
	if not presentation_prepared: return
	state = snapshot
	map_view.update_map(snapshot,arena.source_data)
	var active_ids: Array = []
	for player in state.players:
		active_ids.append(player.id)
		if not peers.has(player.id):
			var visual := TankPortVisual.new()
			add_child(visual)
			peers[player.id] = visual
		var visual: TankPortVisual = peers[player.id]
		visual.apply_player(player,player.id == state.playerId)
		var shot = player.get("shot")
		if shot is Dictionary:
			if old_shots.has(player.id) and shot.id > old_shots[player.id] and state.time-shot.time >= 0 and state.time-shot.time < 0.35:
				visual.recoil_age = 0
				_present_shot(shot)
			old_shots[player.id] = maxi(int(old_shots.get(player.id,0)),int(shot.id))
		elif not old_shots.has(player.id): old_shots[player.id] = 0
	for id in peers.keys():
		if not id in active_ids:
			peers[id].queue_free()
			peers.erase(id)
			old_shots.erase(id)
	arena.update_bases(state.capture.bases)
	var waiting: bool = state.get("staging",{}).get("waiting",false)
	var own := own_player()
	ready_button.disabled = not waiting
	start_button.disabled = not state.get("staging",{}).get("canStart",false)
	rejoin_button.disabled = transport.room_code.is_empty()
	ready_button.text = "Unready" if own.get("ready",false) else "Mark Ready"
	switch_button.disabled = not waiting or state.staging.get("switchTo") == null
	rematch_button.disabled = not state.get("won",false) or state.playerId != state.hostId
	var lines: Array[String] = []
	for team in ["blue","red"]:
		var members: Array[String] = []
		for player in state.players:
			if player.team != team: continue
			members.append(str(player.id).to_upper()+ (" (you)" if player.id == state.playerId else "")+ (" [host]" if player.id == state.hostId else "")+ (" · reserved" if not player.connected else " · Ready" if player.get("ready",false) else " · not ready" if waiting else ""))
		lines.append(team.to_upper()+" %d/4: " % members.size()+", ".join(members))
	roster_label.text = "\n".join(lines)
	if state.get("won",false) and not previous_won:
		paused_controls = true
		controls_blocked = true
		_neutral()
	if previous_won and not state.get("won",false):
		paused_controls = false
		controls_blocked = true
		camera_seeded = false
	previous_won = state.get("won",false)
	_show_room_panel()
	for button in connect_buttons: button.disabled = true
	if own.is_empty(): return
	if own.health > 0 and not previous_alive: camera_seeded = false
	previous_alive = own.health > 0
	var weapon := "Ready" if own.health > 0 and own.tank.reload <= 0 else "Reload %.1fs" % own.tank.reload
	if own.health <= 0: weapon = "Scrapped · respawn %.1fs" % own.respawnSeconds
	if state.get("won",false): weapon = "Match complete"
	var objective := "Capture all seven bases. M: map · Esc: menu"
	for base in state.capture.bases:
		if Vector2(own.tank.x-base.x,own.tank.z-base.z).length() <= base.radius+5:
			objective = "%s · %s · %s" % [str(base.id)+" "+base.name,str(base.owner).capitalize()+" holds" if base.owner != "neutral" else "Neutral", "Contested" if base.get("contested",false) else "Blue taking" if base.net > 0 else "Red taking" if base.net < 0 else "Hold the circle"]
	if state.get("won",false): objective = str(state.winner).to_upper()+" WINS · Host: choose Rematch"
	stats_label.text = "%s · Hull %d/3 · %.1f km/h\nCannon: %s · Bases Blue %d / Red %d\n%s" % [str(own.team).to_upper(),own.health,absf(own.tank.speed)*3.6,weapon,state.scores.blue,state.scores.red,objective]
	# Waiting snapshots can retain zero health after Rematch; this is not a live death.
	if waiting:
		var readiness := "Ready." if own.get("ready",false) else "Choose Mark Ready."
		var start_hint := "Host: Start battle." if state.staging.get("canStart",false) else "Host starts when both teams are ready."
		var waiting_hint := "Hulls spawn at battle start." if own.health <= 0 else "Waiting for the host to start."
		stats_label.text = "%s · Waiting for battle\n%s %s\n%s" % [str(own.team).to_upper(),readiness,start_hint,waiting_hint]
	var staging_block = state.staging.get("block")
	status_label.text = (str(staging_block) if staging_block != null else "All ready. Host: Start battle.") if waiting else "Match complete. Host can return everyone to the ready room." if state.get("won",false) else "Controls suspended; the online match continues." if paused_controls else "Live room "+transport.room_code

func _present_shot(shot: Dictionary) -> void:
	# This receives only accepted new shots from _accept_state, not local fire input.
	shot_effects.present(shot,float(Time.get_ticks_msec())/1000.0)
	shot_effects.update(float(Time.get_ticks_msec())/1000.0,camera)

func _neutral() -> void:
	transport.send({"type":"input","input":{"throttle":0,"steer":0,"aim":0,"fire":false}})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		window_focused = false
		controls_blocked = true
		_neutral()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		window_focused = true
		controls_blocked = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		paused_controls = not paused_controls
		controls_blocked = true
		_neutral()
		_show_room_panel()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		map_enabled = not map_enabled
		map_view.visible = map_enabled
		controls_blocked = true
		_neutral()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not panel.get_global_rect().has_point(event.position):
		get_viewport().gui_release_focus()

func _process(delta: float) -> void:
	if not presentation_prepared:
		controls_blocked = true
		input_elapsed = 0
		_neutral()
		return
	transport.poll()
	shot_effects.update(float(Time.get_ticks_msec())/1000.0,camera)
	if OS.has_feature("web") and not transport.browser_info().get("visible",false):
		controls_blocked = true
		_neutral()
	var own := own_player()
	if not own.is_empty() and peers.has(own.id):
		var target: Vector3 = peers[own.id].position
		var heading := Vector3(sin(own.tank.yaw),0,cos(own.tank.yaw))
		var distance_scale := camera_distance_scale(get_viewport().get_visible_rect().size)
		var desired := target+(Vector3.UP*12-heading*20)*distance_scale
		camera.position = camera.position.lerp(desired,1.0-exp(-4.0*delta)) if camera_seeded else desired
		camera.look_at(target+Vector3.UP*1.4)
		camera_seeded = true
	input_elapsed += delta
	if input_elapsed < 0.05 or own.is_empty(): return
	input_elapsed = 0
	var throttle := float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
	var steer := float(Input.is_physical_key_pressed(KEY_A))-float(Input.is_physical_key_pressed(KEY_D))
	var aim := float(Input.is_physical_key_pressed(KEY_LEFT))-float(Input.is_physical_key_pressed(KEY_RIGHT))
	var fire := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var ui_focus := get_viewport().gui_get_focus_owner() != null
	var mouse_position := get_viewport().get_mouse_position()
	var over_ui := (panel.visible and panel.get_global_rect().has_point(mouse_position)) or hud_panel.get_global_rect().has_point(mouse_position) or toolbar.get_global_rect().has_point(mouse_position) or (map_view.visible and map_view.get_global_rect().has_point(mouse_position))
	if throttle == 0 and steer == 0 and aim == 0 and not fire: controls_blocked = false
	if not transport.is_seated() or not window_focused or (OS.has_feature("web") and not transport.browser_info().get("visible",false)) or paused_controls or controls_blocked or ui_focus or (over_ui and fire) or state.get("won",false):
		_neutral()
		return
	var command := {"throttle":throttle,"steer":steer,"aim":aim,"fire":fire}
	if aim == 0 and not over_ui:
		var mouse := get_viewport().get_mouse_position()
		var point = Plane(Vector3.UP,own.tank.y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		if point is Vector3: command["bearing"] = normalized_bearing(Vector2(point.x-own.tank.x,point.z-own.tank.z))
	transport.send({"type":"input","input":command})

# Preserve the existing wide-view camera. Narrow windows need more horizontal
# room for the shared cannon envelope, especially when the hull is tilted.
# This changes presentation only; mouse aim still projects through this camera.
static func camera_distance_scale(viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	var aspect := viewport_size.x / viewport_size.y
	return maxf(1.0,0.5 / maxf(0.25,aspect))
