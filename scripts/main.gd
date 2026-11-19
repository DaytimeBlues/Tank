extends Node3D

var accepted_guide: Node3D
var guide_snapshot_msec := -1
const GUIDE_MAX_AGE_MSEC := 1000

var arena: TankArenaView
var transport := TankPortTransport.new()
var camera: Camera3D
var camera_obstruction = preload("res://scripts/chase_camera_obstruction.gd").new()
const TrackVisual = preload("res://scripts/track_tank_view.gd")
var peers: Dictionary = {}
var old_shots: Dictionary = {}
var effects: Array = []
var shot_effects: TankAcceptedShotEffects
var projectile_view: Node3D
var state: Dictionary = {}
var status_label: Label
var combat_strip: Control
var stats_label: Label
var room_field: LineEdit
var port_field: LineEdit
const ROLE_IDS = ["prototype","flanker","generalist","anchor"]
const RoleReadout = preload("res://scripts/trial_role_readout.gd")
var role_note: Label
var role_selector: OptionButton
var roster: OptionButton
var ready_button: Button
var start_button: Button
var rejoin_button: Button
var connect_buttons: Array[Button] = []
var panel: PanelContainer
var hud_panel: PanelContainer
var paused_controls := false
var controls_blocked := false
var input_gate = preload("res://scripts/input_gate.gd").new()
var window_focused := true
var input_elapsed := 0.0
var camera_seeded := false
var orbit_yaw := 0.0
var orbit_height := 12.0
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
	accepted_guide = preload("res://scripts/accepted_gun_guide.gd").new()
	add_child(accepted_guide)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	# Reuse the 16 Nov native sky study, without its rejected apron/skirt.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5b7e96")
	sky_material.sky_horizon_color = Color("c6cbc2")
	sky_material.ground_bottom_color = Color("535b4b")
	sky_material.ground_horizon_color = Color("c6cbc2")
	sky_material.sky_curve = 0.2
	sky_material.sun_angle_max = 4.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	settings.sky = sky
	settings.background_color = Color("8b9d9d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6d1c6")
	settings.ambient_light_energy = 0.30
	environment.environment = settings
	add_child(environment)
	var skyline := preload("res://scripts/watershed_skyline.gd").new()
	skyline.name = "WatershedSkyline"
	add_child(skyline)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52,-35,0)
	light.light_color = Color("fff0d5")
	light.light_energy = 0.95
	light.shadow_enabled = true
	add_child(light)
	shot_effects = TankAcceptedShotEffects.new(self)
	effects = shot_effects.active
	projectile_view = preload("res://scripts/projectile_view.gd").new()
	projectile_view.fx = shot_effects
	add_child(projectile_view)
	arena = TankArenaView.new()
	arena.name = "Arena"
	add_child(arena)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/arena.json"))
	arena.build(data)
	_dress_arena(data)
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
	_suspend_controls()
	for button in connect_buttons: button.disabled = true
	transport.joined.connect(func(code: String):
		_reset_track_histories()
		guide_snapshot_msec = -1
		accepted_guide.hide()
		combat_strip.retire()
		room_field.text = code
		camera_seeded = false
		_suspend_controls()
		# The immediate legacy format has no trees; render its actual authoritative map.
		if transport.map_data.get("version",0) != arena.source_data.get("version",0):
			remove_child(arena)
			arena.queue_free()
			arena = TankArenaView.new()
			arena.name = "Arena"
			add_child(arena)
			arena.build(transport.map_data)
			_dress_arena(transport.map_data)
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
			_suspend_controls()
			_neutral()
			return
		callback.call()
		_suspend_controls()
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
	_label("Matches: capture all seven bases. One tank per player, up to eight players.",content)
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
	role_selector = OptionButton.new()
	for id in ROLE_IDS: role_selector.add_item(RoleReadout.label(id))
	content.add_child(role_selector)
	role_note = _label("Role choice applies only to a handling trial.",content)
	role_selector.item_selected.connect(func(index: int):
		get_viewport().gui_release_focus()
		if transport.is_seated() and state.get("roleProtocol",0) == 1 and state.get("staging",{}).get("waiting",false):
			transport.send({"type":"selectRole","roleId":ROLE_IDS[index]})
			role_selector.select(maxi(0,ROLE_IDS.find(own_player().get("roleId","prototype"))))
	)
	for field in [port_field,room_field]:
		field.text_submitted.connect(func(_text: String): get_viewport().gui_release_focus())
	status_label = _label("Start Solo Practice to explore and shoot immediately. For multiplayer, create/join a room and mark Ready.",content)
	var buttons := HFlowContainer.new()
	content.add_child(buttons)
	connect_buttons.append(_button("SOLO PRACTICE - drive and shoot",buttons,func(): _connect_room("create","4v4",false,true)))
	connect_buttons.append(_button("Teacher: Create room",buttons,func(): _connect_room("create","4v4")))
	connect_buttons.append(_button("Create handling trial",buttons,func(): _connect_room("create","4v4",true)))
	connect_buttons.append(_button("Join room",buttons,func(): _connect_room("join","4v4")))
	if not OS.has_feature("web") or transport.browser_info().get("mode","")=="local":
		connect_buttons.append(_button("Brisk Practice (speed trial)",buttons,func(): _connect_room("create","4v4",false,true,true)))
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
		_suspend_controls()
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
	_label("W/S drive · A/D turn · pointer/arrows aim · Space/click fire. Right-drag looks around. Capture all 7 bases to win. Each hull takes 3 hits. The cannon strip shows when you can fire again. Online play continues while the menu is open.",content)
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
	stats_label = _label("W/S drive · A/D turn · right-drag look / pointer aim · Space / click fire\nEscape or focus loss cancels controls. Online play continues.",hud_panel)
	# Autowrap initially measures at a one-pixel width. Bound that minimum
	# height before the parent container's first layout to keep this HUD onscreen.
	stats_label.max_lines_visible = 5
	combat_strip = preload("res://scripts/combat_status_strip.gd").new()
	canvas.add_child(combat_strip)

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
	hud_panel.position = Vector2(16,viewport_size.y-164)
	hud_panel.size = Vector2(minf(420,viewport_size.x-32),148)
	combat_strip.position = Vector2((viewport_size.x-320)/2 if viewport_size.x>=1200 else viewport_size.x-336,viewport_size.y-84)
	combat_strip.visible = viewport_size.x>=900

func _backend_url() -> String:
	return "ws://127.0.0.1:"+port_field.text.strip_edges()

func _show_room_panel() -> void:
	panel.visible = paused_controls or state.is_empty() or state.get("staging",{}).get("waiting",false) or state.get("won",false)

static func normalized_bearing(offset: Vector2) -> float:
	return atan2(offset.x,offset.y)/PI

func _connect_room(kind: String, format_value: String, role_trial: bool = false, practice: bool = false, brisk: bool = false) -> void:
	if not presentation_prepared:
		_suspend_controls()
		input_elapsed = 0
		status_label.text = "Shot feedback could not prepare. Reload this page to retry." if presentation_preparation_complete else "Preparing shot feedback."
		_neutral()
		return
	for button in connect_buttons: button.disabled = true
	var request := {"type":kind,"mode":"battle","format":format_value,"role":"commander","team":"auto","visualId":TankPortVisual.IDS[roster.selected],"tankId":"prototype"}
	if practice: request["practice"] = true
	if brisk: request["practicePreset"] = "brisk-v1"
	if role_trial:
		request["roleProtocol"] = 1
		request["roleId"] = ROLE_IDS[role_selector.selected]
	if kind == "join": request["code"] = room_field.text.strip_edges().to_upper()
	state = {}
	_retire_objective_state()
	roster_label.text = "Connecting. Roster not yet confirmed."
	_reset_track_histories()
	guide_snapshot_msec = -1
	accepted_guide.hide()
	old_shots.clear()
	shot_effects.clear()
	projectile_view.clear()
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
	connect_buttons[0].get_parent().show()
	role_selector.disabled = transport.is_recovering()
	role_selector.show()
	role_selector.select(0)
	role_note.show()
	role_note.text = "Role choice applies only to a handling trial."
	for i in ROLE_IDS.size(): role_selector.set_item_text(i,RoleReadout.label(ROLE_IDS[i]))
	_reset_track_histories()
	guide_snapshot_msec = -1
	if is_instance_valid(accepted_guide): accepted_guide.hide()
	status_label.text = message
	_suspend_controls()
	state = {}
	_retire_objective_state()
	roster_label.text = "Reconnecting. Seat not yet confirmed." if transport.is_recovering() else "No active seat. Join a room."
	old_shots.clear()
	shot_effects.clear()
	projectile_view.clear()
	stats_label.text = "Disconnected. Controls are neutral. Recovering the same seat for up to 22 seconds." if transport.is_recovering() else "Connection stopped. Check the room code and join again. If access expired, return to Private access."
	ready_button.disabled = true
	start_button.disabled = true
	rematch_button.disabled = true
	switch_button.disabled = true
	for button in connect_buttons: button.disabled = not presentation_prepared or transport.is_recovering()
	_show_room_panel()

func _retire_objective_state() -> void:
	if is_instance_valid(combat_strip): combat_strip.retire()
	map_view.clear_accepted_state()
	arena.retire_objectives()

func _reset_track_histories() -> void:
	for visual in peers.values():
		if is_instance_valid(visual): visual.reset_track_history()

# An optional summary of explicit readiness in the accepted roster, never a
# local start decision. No summary is safer than an invented zero.
static func _ready_totals(players: Array) -> String:
	var total := Vector2i.ZERO
	var ready := Vector2i.ZERO
	for player in players:
		if not player is Dictionary or not player.get("connected") is bool:
			return ""
		if not player.connected:
			continue
		if not player.get("ready") is bool:
			return ""
		match player.get("team"):
			"blue":
				total.x += 1
				ready.x += int(player.ready)
			"red":
				total.y += 1
				ready.y += int(player.ready)
			_:
				return ""
	if total.x == 0 or total.y == 0:
		return ""
	return "Ready: Blue %d/%d · Red %d/%d" % [ready.x,total.x,ready.y,total.y]

func _accept_state(snapshot: Dictionary) -> void:
	if not presentation_prepared: return
	# Source-clock discontinuity or long snapshot gap: do not infer tread travel.
	var old_time: float = float(state.get("time",-1))
	var new_time: float = float(snapshot.get("time",0))
	# Offline restart replaces the entire simulation, including its shot IDs
	# and clock. Ignore retired epochs; never treat reordered online time as
	# a reset. Older FIFO solo workers synchronously emit time zero on restart.
	if snapshot.get("singlePlayer",false) and state.get("singlePlayer",false):
		var previous_epoch := int(state.get("soloEpoch",0))
		var next_epoch := int(snapshot.get("soloEpoch",0))
		if previous_epoch > 0 and next_epoch < previous_epoch: return
		if next_epoch > previous_epoch or (previous_epoch == 0 and next_epoch == 0 and new_time == 0.0 and old_time > 0.0):
			projectile_view.clear()
			shot_effects.clear()
			old_shots.clear()
		elif new_time < old_time: return
	if state.is_empty() or new_time < old_time or new_time-old_time > 1.0 or snapshot.get("staging",{}).get("waiting",false) or state.get("staging",{}).get("waiting",false):
		_reset_track_histories()
	state = snapshot
	projectile_view.accept(snapshot,float(Time.get_ticks_msec())/1000.0)
	guide_snapshot_msec = Time.get_ticks_msec()
	map_view.update_map(snapshot,arena.source_data)
	var active_ids: Array = []
	for player in state.players:
		active_ids.append(player.id)
		if not peers.has(player.id):
			var visual := TrackVisual.new()
			add_child(visual)
			peers[player.id] = visual
		var visual: TankPortVisual = peers[player.id]
		if not player.get("connected",true): visual.reset_track_history()
		visual.apply_player(player,player.id == state.playerId)
		if not player.get("connected",true) or state.get("staging",{}).get("waiting",false): visual.reset_track_history()
		var shot = player.get("shot")
		if shot is Dictionary:
			if old_shots.has(player.id) and shot.id > old_shots[player.id] and state.time-shot.time >= 0 and state.time-shot.time < 0.35:
				visual.recoil_age = 0
				_present_shot(shot)
				projectile_view.boom(Vector3(shot.x,shot.y,shot.z))
			old_shots[player.id] = maxi(int(old_shots.get(player.id,0)),int(shot.id))
		elif not old_shots.has(player.id): old_shots[player.id] = 0
	for id in peers.keys():
		if not id in active_ids:
			peers[id].queue_free()
			peers.erase(id)
			old_shots.erase(id)
	_update_accepted_guide()
	arena.update_bases(state.capture.bases)
	var waiting: bool = state.get("staging",{}).get("waiting",false)
	var own := own_player()
	var trial: bool = state.get("roleProtocol",0)==1
	var entries: Dictionary = RoleReadout.catalog(state)
	var role_id: String = str(own.get("roleId",""))
	connect_buttons[0].get_parent().visible = not trial
	role_selector.visible = trial
	role_note.visible = trial
	role_selector.disabled = not waiting or not trial or role_id not in entries
	for i in ROLE_IDS.size():
		var id: String = ROLE_IDS[i]
		role_selector.set_item_text(i,RoleReadout.option(id,entries.get(id,{})))
	role_selector.select(ROLE_IDS.find(role_id) if role_id in ROLE_IDS else -1)
	role_note.text = RoleReadout.tradeoff(role_id,entries)
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
		_suspend_controls()
		_neutral()
	if previous_won and not state.get("won",false):
		paused_controls = false
		_suspend_controls()
		camera_seeded = false
	previous_won = state.get("won",false)
	_show_room_panel()
	for button in connect_buttons: button.disabled = true
	if own.is_empty(): return
	if own.health > 0 and not previous_alive: camera_seeded = false
	if (own.health > 0) != previous_alive: _suspend_controls()
	previous_alive = own.health > 0
	var weapon := "Ready" if own.health > 0 and own.tank.reload <= 0 else "Reload %.1fs" % own.tank.reload
	if trial and (role_id not in entries or own.tank.reload > float(entries[role_id].reloadSeconds)): weapon = "Status unavailable"
	if own.health <= 0: weapon = "Scrapped · respawn %.1fs" % own.respawnSeconds
	if state.get("won",false): weapon = "Match complete"
	var objective: String = preload("res://scripts/capture_status.gd").describe(state,own)
	stats_label.text = "%s · Hull %d/3 · %.1f km/h\nCannon: %s · Bases Blue %d / Red %d\n%s" % [str(own.team).to_upper(),own.health,absf(own.tank.speed)*3.6,weapon,state.scores.blue,state.scores.red,objective]
	if state.get("practice",false) and state.get("practicePreset","")=="brisk-v1":
		stats_label.text = "Brisk Practice · %.1f m/s drive target\n" % float(state.get("driveTargetMps",0)) + stats_label.text
	# Waiting snapshots can retain zero health after Rematch; this is not a live death.
	if waiting:
		var readiness := "Ready." if own.get("ready",false) else "Choose Mark Ready."
		var start_hint := "Host: Start battle." if state.staging.get("canStart",false) else "Host starts when both teams are ready."
		var waiting_hint := "Hulls spawn at battle start." if own.health <= 0 else "Waiting for the host to start."
		stats_label.text = "%s · Waiting for battle\n%s %s\n%s" % [str(own.team).to_upper(),readiness,start_hint,waiting_hint]
	var staging_block = state.staging.get("block")
	status_label.text = (str(staging_block) if staging_block != null else "All ready. Host: Start battle.") if waiting else "Match complete. Host can return everyone to the ready room." if state.get("won",false) else "Controls suspended; the online match continues." if paused_controls else "Live room "+transport.room_code
	if waiting and staging_block == "Every player must mark Ready.":
		var totals := _ready_totals(state.players)
		if not totals.is_empty():
			status_label.text = totals + "\n" + status_label.text
	_refresh_combat_status()

func _present_shot(shot: Dictionary) -> void:
	# This receives only accepted new shots from _accept_state, not local fire input.
	shot_effects.present(shot,float(Time.get_ticks_msec())/1000.0)
	shot_effects.update(float(Time.get_ticks_msec())/1000.0,camera)
	projectile_view.update(float(Time.get_ticks_msec())/1000.0)

const CONTROL_KEYS = {KEY_W:"w", KEY_S:"s", KEY_A:"a", KEY_D:"d", KEY_LEFT:"left", KEY_RIGHT:"right", KEY_SPACE:"space"}

func _raw_controls() -> Dictionary:
	var raw := {}
	for key in CONTROL_KEYS: raw[CONTROL_KEYS[key]] = Input.is_physical_key_pressed(key)
	raw["mouse1"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	return raw

func _suspend_controls() -> void:
	controls_blocked = true
	input_gate.suspend(_raw_controls())

func _controls_eligible() -> bool:
	if not presentation_prepared or not transport.is_seated() or not window_focused or paused_controls: return false
	if OS.has_feature("web") and not transport.browser_info().get("visible",false): return false
	if get_viewport().gui_get_focus_owner() != null or state.get("won",false) or state.get("staging",{}).get("waiting",false): return false
	return own_player().get("health",0) > 0

func _pointer_over_ui(position: Vector2) -> bool:
	return (panel != null and panel.visible and panel.get_global_rect().has_point(position)) or (hud_panel != null and hud_panel.visible and hud_panel.get_global_rect().has_point(position)) or (combat_strip != null and combat_strip.visible and combat_strip.get_global_rect().has_point(position)) or (toolbar != null and toolbar.get_global_rect().has_point(position)) or (map_view != null and map_view.visible and map_view.get_global_rect().has_point(position))

func _input(event: InputEvent) -> void:
	# Observe releases before GUI consumption. Authorization remains separate.
	var key := ""
	var pressed := false
	var echo := false
	if event is InputEventKey and CONTROL_KEYS.has(event.physical_keycode):
		key = CONTROL_KEYS[event.physical_keycode]
		pressed = event.pressed
		echo = event.echo
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		key = "mouse1"
		pressed = event.pressed
	if key.is_empty(): return
	if not pressed:
		input_gate.edge(key,false)
		return
	if not _controls_eligible():
		_suspend_controls()
	elif key == "mouse1" and _pointer_over_ui(event.position):
		input_gate.ignore_hud_mouse_until_release()
		return
	else:
		input_gate.resume()
	input_gate.edge(key,true,echo)
	# A short fire tap must not be lost between the 20Hz periodic input sends.
	if not echo and key in ["space","mouse1"] and _controls_eligible() and (not event is InputEventMouseButton or not _pointer_over_ui(event.position)):
		if input_gate.command().fire: _send_fire_edge(input_gate.command())

func _send_fire_edge(command: Dictionary) -> void:
	transport.send({"type":"input","input":command})

func _neutral() -> void:
	transport.send({"type":"input","input":{"throttle":0,"steer":0,"aim":0,"fire":false}})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		window_focused = false
		_suspend_controls()
		_neutral()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		window_focused = true
		_suspend_controls()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		paused_controls = not paused_controls
		_suspend_controls()
		_neutral()
		_show_room_panel()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		map_enabled = not map_enabled
		map_view.visible = map_enabled
		_suspend_controls()
		_neutral()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _controls_eligible() and not _pointer_over_ui(event.position):
		orbit_yaw -= event.relative.x * 0.006
		orbit_height = clampf(orbit_height + event.relative.y * 0.06, 4.0, 24.0)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and not panel.get_global_rect().has_point(event.position):
		get_viewport().gui_release_focus()

func _refresh_combat_status() -> void:
	if is_instance_valid(combat_strip): combat_strip.present(state,own_player(),presentation_prepared and transport.is_seated(),Time.get_ticks_msec()-guide_snapshot_msec if guide_snapshot_msec>=0 else -1,not _controls_eligible() or controls_blocked)
	if is_instance_valid(combat_strip) and combat_strip.reading.mode=="unavailable" and not state.is_empty(): stats_label.text = "Combat status unavailable.\nWaiting for a fresh server update."
	if is_instance_valid(combat_strip) and combat_strip.reading.mode=="paused": stats_label.text = stats_label.text.replace("Cannon: Ready","Cannon: Paused")
	if is_instance_valid(combat_strip) and combat_strip.reading.mode=="ready": stats_label.text = stats_label.text.replace("Cannon: Paused","Cannon: Ready")

func _update_accepted_guide() -> void:
	_refresh_combat_status()
	if not is_instance_valid(accepted_guide): return
	accepted_guide.hide()
	var age := Time.get_ticks_msec()-guide_snapshot_msec
	if not presentation_prepared or not transport.is_seated() or guide_snapshot_msec < 0 or age < 0 or age > GUIDE_MAX_AGE_MSEC: return
	if state.get("staging",{}).get("waiting",true) or state.get("won",false): return
	var own := own_player()
	if own.is_empty() or not own.get("connected",false) or own.get("health",0) <= 0: return
	accepted_guide.update_from_visual(peers.get(own.id),true,true)

func _process(delta: float) -> void:
	_update_accepted_guide()
	if not presentation_prepared:
		_suspend_controls()
		input_elapsed = 0
		_neutral()
		return
	transport.poll()
	if not _controls_eligible():
		_suspend_controls()
	else:
		input_gate.resume()
		controls_blocked = not input_gate.blocked.is_empty()
	shot_effects.update(float(Time.get_ticks_msec())/1000.0,camera)
	projectile_view.update(float(Time.get_ticks_msec())/1000.0)
	if OS.has_feature("web") and not transport.browser_info().get("visible",false):
		_suspend_controls()
		_neutral()
	var own := own_player()
	if not own.is_empty() and peers.has(own.id):
		var target: Vector3 = peers[own.id].position
		var heading := Vector3(sin(own.tank.yaw+orbit_yaw),0,cos(own.tank.yaw+orbit_yaw))
		var desired := target-heading*20+Vector3.UP*orbit_height
		camera.position = camera_obstruction.update(target+Vector3.UP*1.4,camera.position,desired,delta,camera_seeded)
		camera.fov = camera_obstruction.framing_fov(target+Vector3.UP*1.4,camera.position,camera.fov,delta,camera_seeded)
		if camera.position.distance_squared_to(target+Vector3.UP*1.4)>0.000001: camera.look_at(target+Vector3.UP*1.4)
		camera_seeded = true
	input_elapsed += delta
	if input_elapsed < 0.05 or own.is_empty(): return
	input_elapsed = 0
	var command: Dictionary = input_gate.command()
	var aim: float = command.aim
	var over_ui := _pointer_over_ui(get_viewport().get_mouse_position())
	if not _controls_eligible():
		_suspend_controls()
		_neutral()
		return
	if over_ui: command.fire = input_gate.value("space") > 0
	if aim == 0 and not over_ui and input_gate.pointer_aim_allowed():
		var mouse := get_viewport().get_mouse_position()
		var point = Plane(Vector3.UP,own.tank.y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		if point is Vector3: command["bearing"] = normalized_bearing(Vector2(point.x-own.tank.x,point.z-own.tank.z))
	transport.send({"type":"input","input":command})

func _dress_arena(data: Dictionary) -> void:
	camera_obstruction.build(data)
	# Bounds-fitted, spatially batched crowns preserve trunks and server collision.
	for child in arena.get_children():
		if child is MeshInstance3D and child.has_meta("original_tree_crown"): child.hide()
	var crowns = load("res://scripts/meshy_crown_view.gd").new()
	crowns.name = "MeshyCrownClusters"
	crowns.build(data)
	arena.add_child(crowns)
	var low_foliage = load("res://scripts/low_foliage_view.gd").new()
	low_foliage.name = "LowFoliage"
	low_foliage.build()
	arena.add_child(low_foliage)
	arena.add_child(load("res://assets/map_dressing.tscn").instantiate())
	if not data.get("arches",[]).is_empty():
		arena.get_node("MapDressing/BridgeStoneFascia/Fascia240Batched").hide()
		preload("res://scripts/river_scenic_outlets.gd").reshape(arena.get_node("MapDressing/ScenicPerimeter"),data)
		preload("res://scripts/east_scenic_ridge.gd").reshape(arena.get_node("MapDressing/ScenicPerimeter"))
	var district = load("res://scripts/windmill_district.gd").new()
	district.name = "WindmillDistrict"
	district.build(data)
	arena.add_child(district)
	arena.add_child(load("res://assets/close_detail.tscn").instantiate())
	var verges = load("res://scripts/north_verge_view.gd").new()
	verges.name = "NorthVergeClusters"
	arena.add_child(verges)
	var understorey = load("res://scripts/district_groundcover.gd").new()
	understorey.name = "DistrictGroundcover"
	arena.add_child(understorey)
	var farm_verge = load("res://scripts/farm_verge.gd").new()
	farm_verge.name = "FarmVergeSkirt"
	arena.add_child(farm_verge)
	var ground_factory = load("res://scripts/road_wear_material.gd")
	for chunk in data.get("chunks",[]):
		var mesh = arena.get_node_or_null(NodePath(str(chunk.id)))
		if mesh is MeshInstance3D: mesh.set_surface_override_material(0,ground_factory.create_for_chunk(data,chunk))

	var water_material := ShaderMaterial.new()
	water_material.shader = load("res://assets/river_surface.gdshader")
	for child in arena.get_children():
		if child is MeshInstance3D and child.has_meta("river_surface"): child.material_override = water_material
	for child in arena.get_node("MapDressing/ScenicPerimeter").get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh and child.mesh.get_aabb().size.y < 0.01:
			child.material_override = water_material
