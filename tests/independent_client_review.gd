extends SceneTree

class CaptureTransport extends TankPortTransport:
	var outbound: Array[Dictionary] = []
	func is_seated() -> bool: return true
	func poll() -> void: pass
	func send(message: Dictionary) -> void: outbound.append(message.duplicate(true))

var failures: Array[String] = []
var checks := 0
var main: Node
var capture: CaptureTransport

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void: call_deferred("run")

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	main._unhandled_key_input(event)

func last_input() -> Dictionary:
	for i in range(capture.outbound.size()-1,-1,-1):
		if capture.outbound[i].get("type") == "input": return capture.outbound[i].input
	return {}

func fixture(waiting: bool = false, won: bool = false, own_id: String = "p1") -> Dictionary:
	var players: Array = []
	for i in range(8):
		players.append({"id":"p"+str(i+1),"team":"blue" if i%2 == 0 else "red","visualId":TankPortVisual.IDS[i%4],"connected":true,"ready":false,"health":3,"respawnSeconds":0,"shot":null,"tank":{"x":-100+i*10,"y":3,"z":-60,"yaw":0,"turret":0,"reload":0,"speed":0,"quaternion":{"x":0,"y":0,"z":0,"w":1}}})
	var bases: Array = main.arena.source_data.bases.duplicate(true)
	for base in bases:
		base["owner"] = "blue" if won else "neutral"
		base["net"] = 0
		base["contested"] = false
	return {"time":10,"players":players,"playerId":own_id,"hostId":"p1","staging":{"waiting":waiting,"canStart":false,"switchTo":null,"block":"Every player must mark Ready."},"won":won,"winner":"blue" if won else null,"scores":{"blue":7 if won else 0,"red":0},"capture":{"bases":bases}}

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await process_frame
	root.size = Vector2i(1280,800)
	await process_frame
	capture = CaptureTransport.new()
	capture.room_code = "ABC123"
	main.transport = capture
	main._accept_state(fixture())
	check(main.roster_label.text.contains("P8") and main.roster_label.text.contains("BLUE 4/4") and main.roster_label.text.contains("RED 4/4"),"eight anonymous seats render in roster")
	check(not main.panel.visible,"live match hides room panel until menu")
	# Startup intentionally retains the same release latch as focus/menu resume.
	# Establish a released-input tick before the original drive assertion.
	main._process(0.1)
	key(KEY_W,true)
	main._process(0.1)
	check(last_input().get("throttle") == 1.0,"fixture keyboard can drive before menu")
	escape()
	main._process(0.1)
	check(main.paused_controls and last_input().get("throttle") == 0,"Escape neutralizes held drive")
	escape()
	main._process(0.1)
	check(not main.paused_controls and main.controls_blocked and last_input().get("throttle") == 0,"resume keeps held drive neutral until release")
	key(KEY_W,false)
	main._process(0.1)
	key(KEY_W,true)
	main._process(0.1)
	check(last_input().get("throttle") == 1.0,"fresh release/press resumes drive")
	main._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	main._process(0.1)
	check(not main.window_focused and last_input().get("throttle") == 0,"focus loss neutralizes held drive")
	main._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	main._process(0.1)
	check(main.window_focused and main.controls_blocked and last_input().get("throttle") == 0,"focus return retains release latch")
	key(KEY_W,false)
	main._process(0.1)
	main._accept_state(fixture(false,true))
	check(main.paused_controls and main.panel.visible and not main.rematch_button.disabled,"winning host sees active rematch and forced neutral menu")
	check(main.stats_label.text.contains("BLUE WINS"),"authoritative winner has clear result label")
	main._accept_state(fixture(true,false))
	check(not main.paused_controls and main.panel.visible and not main.ready_button.disabled and main.rematch_button.disabled,"rematch snapshot returns to readiness")
	var ready_state := fixture(true,false)
	ready_state.staging.canStart = true
	ready_state.staging.block = null
	main._accept_state(ready_state)
	check(not main.start_button.disabled,"host start follows authoritative canStart")
	main._accept_state(fixture(false,true,"p2"))
	check(main.rematch_button.disabled,"nonhost cannot invoke rematch UI")
	main._network_error("Terminal fixture")
	check(main.state.is_empty() and main.ready_button.disabled and main.start_button.disabled,"terminal failure clears authority/UI state")
	var forbidden := false
	for message in capture.outbound:
		if message.type != "input": continue
		for field in message.input:
			if not field in ["throttle","steer","aim","fire","bearing"]: forbidden = true
	check(not forbidden,"outbound fixture controls contain intentions only")
	print("TANK_INDEPENDENT_CLIENT_REVIEW "+JSON.stringify({"kind":"isolated headless presentation/input fixtures, not server match or browser acceptance","checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL"}))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
