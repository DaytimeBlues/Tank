extends SceneTree

var clients: Array[TankPortTransport] = []
var negative := TankPortTransport.new()
var stage := 0
var started := 0
var stage_started := 0
var last_input := 0
var initial := Vector3.ZERO
var after_drive := Vector3.ZERO
var player_id := ""
var old_socket_id := 0
var negative_error := ""
var checks: Array[String] = []
var notifications: Array[String] = []
var report: Dictionary = {"kind":"eight actual native Godot peers plus negative clients; ordinary intentions, no transforms/damage injection","status":"INCOMPLETE"}

func _initialize() -> void:
	started = Time.get_ticks_msec()
	for i in range(8):
		var client := TankPortTransport.new()
		clients.append(client)
		client.failed.connect(func(message: String):
			if i == 0 and stage >= 4: notifications.append(message)
			else: finish("peer %d: %s" % [i,message])
		)
	clients[0].joined.connect(func(code: String):
		if stage == 0:
			for i in range(1,8): clients[i].open_local("ws://127.0.0.1:5218",request("join",i,code))
	)
	negative.failed.connect(func(message: String): negative_error = message)
	clients[0].open_local("ws://127.0.0.1:5218",request("create",0))

func request(action: String, index: int, code: String = "") -> Dictionary:
	var value := {"type":action,"mode":"battle","format":"4v4","role":"commander","team":"auto","visualId":TankPortVisual.IDS[index%4],"tankId":"prototype"}
	if action == "join": value["code"] = code
	return value

func own(client: TankPortTransport) -> Dictionary:
	for p in client.latest.get("players",[]):
		if p.id == client.latest.get("playerId",""): return p
	return {}

func position_of(p: Dictionary) -> Vector3:
	return Vector3(p.tank.x,p.tank.y,p.tank.z)

func input_to(client: TankPortTransport, throttle: float = 0.0, fire: bool = false) -> void:
	client.send({"type":"input","input":{"throttle":throttle,"steer":0,"aim":0,"fire":fire}})

func _process(_delta: float) -> bool:
	if stage == 99: return false
	for client in clients: client.poll()
	negative.poll()
	var now := Time.get_ticks_msec()
	if now-started > 30000:
		finish("timeout at stage "+str(stage))
		return false
	var host := clients[0]
	var blue := own(host)
	if stage == 0:
		for client in clients:
			if client.latest.get("players",[]).size() != 8: return false
		var teams := {"blue":0,"red":0}
		var ids: Dictionary = {}
		for client in clients: ids[client.latest.playerId] = true
		for p in host.latest.players:
			teams[p.team] += 1
		if teams.blue != 4 or teams.red != 4 or ids.size() != 8 or host.latest.rules.maxPlayers != 8:
			finish("not actual balanced eight-peer format")
			return false
		initial = position_of(blue)
		player_id = blue.id
		checks.append("eight independent Godot peers, four per team, all snapshots contain eight seats")
		input_to(host,1.0,true)
		stage = 1
		stage_started = now
	elif stage == 1 and now-stage_started > 350:
		if initial.distance_to(position_of(blue)) > 0.05 or blue.get("shot") != null:
			finish("staging accepted movement or fire")
			return false
		checks.append("eight-seat staging blocks ordinary movement/fire until all Ready and host Start")
		input_to(host)
		for client in clients: client.send({"type":"ready","ready":true})
		stage = 2
	elif stage == 2 and host.latest.staging.get("canStart",false):
		host.send({"type":"start"})
		stage = 3
		stage_started = now
	elif stage == 3 and not host.latest.staging.waiting:
		if now-last_input > 50:
			input_to(host,1.0 if now-stage_started < 1600 else 0.0,now-stage_started > 1800)
			for i in range(1,8): input_to(clients[i])
			last_input = now
		if now-stage_started > 1900 and blue.get("shot") != null:
			after_drive = position_of(blue)
			if initial.distance_to(after_drive) < 2.0 or blue.tank.reload <= 0:
				finish("normal move/fire/reload failed")
				return false
			for p in host.latest.players:
				if p.health != 3:
					finish("unexpected hull damage")
					return false
			checks.append("normal host drive >2m, accepted shot/reload, all eight hulls remain3/3")
			input_to(host)
			stage = 4
			host.rejoin()
	elif stage == 4 and host.is_seated():
		if blue.id != player_id or blue.visualId != "kestrel" or position_of(blue).distance_to(after_drive) > 0.5:
			finish("manual same-seat reconnect identity/pose failed")
			return false
		checks.append("manual Rejoin waits for old socket close and preserves identity, visual and supported pose")
		old_socket_id = host.socket.get_instance_id()
		host.socket.close()
		stage = 5
	elif stage == 5 and host.is_seated() and host.socket != null and host.socket.get_instance_id() != old_socket_id:
		if blue.id != player_id:
			finish("automatic recovery changed player")
			return false
		checks.append("unexpected socket close triggers bounded automatic recovery of the same seat")
		negative_error = ""
		negative.open_local("ws://127.0.0.1:5218",request("join",0,"ZZZZZZ" if host.room_code != "ZZZZZZ" else "YYYYYY"))
		stage = 6
	elif stage == 6 and not negative_error.is_empty():
		if negative.is_seated() or negative.is_recovering():
			finish("wrong room did not return to idle")
			return false
		checks.append("wrong-room server error is terminal/idle and does not dereference retired socket")
		negative_error = ""
		negative.open_local("ws://127.0.0.1:5218",request("join",0,host.room_code))
		stage = 7
	elif stage == 7 and not negative_error.is_empty():
		if negative.is_seated() or host.latest.players.size() != 8:
			finish("ninth player bypassed capacity")
			return false
		checks.append("ninth player rejected without changing the eight bound seats")
		report["distance_m"] = initial.distance_to(after_drive)
		finish("")
	return false

func finish(failure: String) -> void:
	if stage == 99: return
	stage = 99
	for client in clients: client.close()
	negative.close()
	report["status"] = "PASS" if failure.is_empty() else "FAIL"
	report["checks"] = checks
	report["failure"] = failure
	report["notifications"] = notifications
	report["elapsed_ms"] = Time.get_ticks_msec()-started
	var file := FileAccess.open("res://evidence/godot-network-smoke.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("TANK_GODOT_NETWORK "+JSON.stringify(report))
	quit(0 if failure.is_empty() else 1)
