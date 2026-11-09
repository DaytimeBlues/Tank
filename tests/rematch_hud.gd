extends SceneTree

class CaptureTransport extends TankPortTransport:
	var outbound: Array[Dictionary] = []
	func is_seated() -> bool: return true
	func poll() -> void: pass
	func send(message: Dictionary) -> void: outbound.append(message.duplicate(true))

var failures: Array[String] = []
var samples: Array[Dictionary] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void: call_deferred("run")

func fixture(main: Node, waiting: bool = true, health: int = 0, own_id: String = "p1") -> Dictionary:
	var players: Array = []
	for i in range(2):
		players.append({"id":"p"+str(i+1),"team":"blue" if i == 0 else "red","visualId":"kestrel","connected":true,"ready":false,"health":health,"respawnSeconds":0,"shot":null,"tank":{"x":-100+i*200,"y":3,"z":-60,"yaw":0,"turret":0,"reload":0,"speed":0,"quaternion":{"x":0,"y":0,"z":0,"w":1}}})
	var bases: Array = main.arena.source_data.bases.duplicate(true)
	for base in bases: base.merge({"owner":"neutral","net":0,"contested":false},true)
	return {"time":10,"players":players,"playerId":own_id,"hostId":"p1","staging":{"waiting":waiting,"canStart":false,"switchTo":null,"block":"Every player must mark Ready."},"won":false,"winner":null,"scores":{"blue":0,"red":0},"capture":{"bases":bases}}

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("This CPU fixture requires --headless.")
		quit(2)
		return
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await process_frame
	var capture := CaptureTransport.new()
	capture.room_code = "ABC123"
	main.transport = capture
	var rematch := fixture(main)
	main._accept_state(rematch)
	check(main.stats_label.text.contains("Waiting for battle") and not main.stats_label.text.contains("Hull 0/3") and not main.stats_label.text.contains("Scrapped") and not main.stats_label.text.contains("respawn"),"rematch waiting HUD takes priority over zero-health battle wording")
	for own_id in ["p1","p2"]:
		for health in [0,3]:
			var waiting := fixture(main,true,health,own_id)
			# Deliberately nonzero battle fields must still not leak into waiting text.
			for player in waiting.players:
				player.respawnSeconds = 4.3
				player.tank.reload = 2.5
				player.tank.speed = 1.25
			var before := waiting.duplicate(true)
			main._accept_state(waiting)
			var label: String = own_id+" waiting health "+str(health)
			var expected := ("BLUE" if own_id == "p1" else "RED")+" · Waiting for battle\nChoose Mark Ready. Host starts when both teams are ready.\n"+("Hulls spawn at battle start." if health == 0 else "Waiting for the host to start.")
			check(main.stats_label.text == expected,label+" shows exact readiness-first instructions")
			check(not main.stats_label.text.contains("Hull ") and not main.stats_label.text.contains("Cannon:") and not main.stats_label.text.contains("respawn") and not main.stats_label.text.contains("Hold the circle"),label+" omits battle health/reload/death/capture prompts")
			check(main.state == before and waiting == before,label+" never rewrites authoritative snapshot")
			check(main.peers[own_id].visible == (health > 0),label+" preserves health-driven model visibility")
			check(main.panel.visible and not main.ready_button.disabled and main.ready_button.text == "Mark Ready" and main.start_button.disabled and main.rematch_button.disabled,label+" preserves waiting button permissions")
			check(main.status_label.text == "Every player must mark Ready.",label+" retains authoritative readiness blocker")
			check(not main.stats_label.text.contains("Host: Start battle."),label+" blocked room never urges an immediate host Start")
			samples.append({"case":label,"hud":main.stats_label.text})
			for player in waiting.players: player.ready = true
			waiting.staging.canStart = own_id == "p1"
			waiting.staging.block = null
			main._accept_state(waiting)
			check(main.stats_label.text.contains("Ready. ") and not main.stats_label.text.contains("Mark Ready"),label+" reflects own ready state without asking to mark again")
			check(main.stats_label.text.contains("Host: Start battle.") == (own_id == "p1"),label+" immediate Start instruction follows authoritative canStart")
			check(main.ready_button.text == "Unready" and main.start_button.disabled == (own_id != "p1"),label+" only authoritative host can Start")
			check(main.status_label.text == "All ready. Host: Start battle.",label+" retains all-ready room status")
			main.ready_button.pressed.emit()
			check(capture.outbound.any(func(m: Dictionary): return m == {"type":"ready","ready":false}),label+" Unready remains an intention")
			capture.outbound.clear()
			if own_id == "p1":
				main.start_button.pressed.emit()
				check(capture.outbound.any(func(m: Dictionary): return m == {"type":"start"}),label+" enabled host Start keeps its existing intention")
				capture.outbound.clear()
			for player in waiting.players: player.ready = false
			waiting.staging.canStart = false
			waiting.staging.block = "Every player must mark Ready."
			main._accept_state(waiting)
			check(main.stats_label.text.contains("Choose Mark Ready.") and main.start_button.disabled,label+" repeated ready-to-unready returns to readiness guidance")
	var dead := fixture(main,false,0)
	dead.players[0].respawnSeconds = 4.3
	main._accept_state(dead)
	check(main.stats_label.text.contains("BLUE · Hull 0/3 · 0.0 km/h") and main.stats_label.text.contains("Cannon: Scrapped · respawn 4.3s"),"live death retains genuine hull and respawn countdown")
	check(not main.stats_label.text.contains("Waiting for battle") and main.ready_button.disabled and main.start_button.disabled and not main.peers.p1.visible,"live death never gets waiting instructions or a visible hull")
	samples.append({"case":"live death","hud":main.stats_label.text})
	var alive := fixture(main,false,2)
	alive.players[0].tank.reload = 2.5
	alive.players[0].tank.speed = 1.25
	main._accept_state(alive)
	check(main.stats_label.text.contains("BLUE · Hull 2/3 · 4.5 km/h") and main.stats_label.text.contains("Cannon: Reload 2.5s · Bases Blue 0 / Red 0"),"live alive retains exact health/speed/reload/scores")
	check(not main.stats_label.text.contains("Waiting for battle") and main.peers.p1.visible and main.ready_button.disabled,"live alive never gets waiting instructions or hidden hulls")
	alive.players[0].tank.reload = 0
	main._accept_state(alive)
	check(main.stats_label.text.contains("Cannon: Ready · Bases Blue 0 / Red 0"),"live ready cannon remains ready")
	samples.append({"case":"live alive","hud":main.stats_label.text})
	var won := fixture(main,false,0)
	won.won = true
	won.winner = "blue"
	won.scores.blue = 7
	for base in won.capture.bases: base.owner = "blue"
	main._accept_state(won)
	check(main.stats_label.text.contains("Cannon: Match complete") and main.stats_label.text.contains("BLUE WINS · Host: choose Rematch"),"finished match retains its result rather than readiness text")
	check(main.paused_controls and main.controls_blocked and not main.rematch_button.disabled,"finished host retains rematch and neutral controls")
	main._accept_state(fixture(main))
	check(not main.paused_controls and main.controls_blocked and main.stats_label.text.contains("Waiting for battle") and main.ready_button.text == "Mark Ready", "win-to-rematch transition restores readiness text and fresh-release input gate")
	check(capture.outbound.all(func(m: Dictionary): return m.type == "input" and m.input == {"throttle":0,"steer":0,"aim":0,"fire":false}),"snapshot presentation emits no gameplay mutations and existing neutral messages stay neutral")
	for size in [Vector2i(1280,800),Vector2i(390,844)]:
		root.size = size
		await process_frame
		await process_frame
		check(main.stats_label.get_line_count() <= main.stats_label.max_lines_visible,"waiting HUD text fits visible line bound at "+str(size))
		check(root.get_visible_rect().encloses(main.hud_panel.get_global_rect()) and main.hud_panel.get_global_rect().encloses(main.stats_label.get_global_rect()),"waiting HUD geometry stays in viewport at "+str(size))
	var report := {"status":"PASS" if failures.is_empty() else "FAIL","kind":"CPU-only authoritative snapshot HUD fixtures, not browser or ordinary-match proof","checks":checks,"failures":failures,"samples":samples,"mainSha256":FileAccess.get_sha256("res://scripts/main.gd"),"fixtureSha256":FileAccess.get_sha256("res://tests/rematch_hud.gd"),"displayServer":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"videoAdapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string}
	var file := FileAccess.open("res://evidence/rematch-hud.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("TANK_REMATCH_HUD "+JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
