extends SceneTree

class CaptureTransport extends TankPortTransport:
	var opened := 0
	var outbound: Array = []
	func open_local(_url: String, _request: Dictionary) -> Error:
		opened += 1
		return OK
	func open_browser(_request: Dictionary) -> Error:
		opened += 1
		return OK
	func poll() -> void: pass
	func is_seated() -> bool: return true
	func send(message: Dictionary) -> void: outbound.append(message.duplicate(true))

var checks := 0
var failures: Array[String] = []
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
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	if not main.presentation_preparation_complete: await main.presentation_preparation_finished
	var capture := CaptureTransport.new()
	main.transport = capture
	main.presentation_prepared = false
	main.presentation_preparation_complete = false
	for button in main.connect_buttons: button.disabled = true
	main._connect_room("create","4v4")
	main._connect_room("join","4v4")
	check(capture.opened == 0 and main.state.is_empty(),"direct Create/Join calls cannot bypass pending preparation")
	check(main.connect_buttons.all(func(button: Button): return button.disabled),"pending connect buttons stay disabled")
	for button in main.connect_buttons: button.pressed.emit()
	main.start_button.pressed.emit()
	check(capture.opened == 0 and capture.outbound.all(func(m: Dictionary): return m.type == "input" and m.input == {"throttle":0,"steer":0,"aim":0,"fire":false}),"direct button signals cannot send pending Create/Join/Start")
	key(KEY_W,true)
	key(KEY_SPACE,true)
	main._process(0.2)
	key(KEY_W,false)
	key(KEY_SPACE,false)
	check(main.controls_blocked and main.input_elapsed == 0 and capture.outbound.all(func(m: Dictionary): return not m.input.fire and m.input.throttle == 0 and m.input.steer == 0 and m.input.aim == 0),"held input during preparation remains neutral")
	main._accept_state({})
	check(main.state.is_empty() and main.old_shots.is_empty() and main.shot_effects.emitted == 0,"pending snapshot cannot seed state/history/effects")
	main.presentation_preparation_complete = true
	main._connect_room("create","4v4")
	main._process(0.2)
	check(capture.opened == 0 and main.status_label.text.contains("Reload this page"),"failed preparation never connects and gives a clear retry message")
	main._network_error("simulated notice")
	check(main.connect_buttons.all(func(button: Button): return button.disabled),"error callback cannot re-enable failed startup connect buttons")
	main.presentation_prepared = true
	main.state = {"players":[{"id":"p1","tank":{"x":0,"y":3,"z":0}}],"playerId":"p1"}
	key(KEY_W,true)
	main._process(0.2)
	check(main.controls_blocked and capture.outbound[-1].input.throttle == 0,"held drive cannot cross successful startup release latch")
	key(KEY_W,false)
	main._process(0.2)
	key(KEY_W,true)
	main._process(0.2)
	check(capture.outbound[-1].input.throttle == 1.0,"released then freshly pressed drive resumes after preparation")
	key(KEY_W,false)
	main._process(0.2)
	main._connect_room("create","4v4")
	check(capture.opened == 1,"successful preparation permits exactly one normal connection attempt")
	var report := {"status":"PASS" if failures.is_empty() else "FAIL","kind":"headless startup race/failure gate regression with capture transport, no actual network or shot injection","checks":checks,"failures":failures}
	var file := FileAccess.open("res://evidence/preparation-gate.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("TANK_PREPARATION_GATE "+JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
