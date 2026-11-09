class_name TankPortTransport
extends RefCounted

signal state_received(state: Dictionary)
signal joined(code: String)
signal failed(message: String)
signal server_notice(message: String)
var socket: WebSocketPeer
var latest: Dictionary = {}
var map_data: Dictionary = {}
var room_code := ""
var _token := ""
var _request: Dictionary = {}
var _url := ""
var _session_url := ""
var _session_format := "4v4"
var _session_hosted := false
var _hosted := false
var _seated := false
var _joined_current := false
var _sent := false
var _phase := "idle"
var _deadline := 0
var _last_state := 0
var _retry_until := 0
var _retry_at := 0
var _generation := 0
var _ticket_callback
var _visible_was := true

func is_seated() -> bool:
	return _seated

func is_recovering() -> bool:
	return not _seated and _phase != "idle"

func _valid_local(url: String) -> bool:
	var allowed := RegEx.new()
	allowed.compile("^ws://(127\\.0\\.0\\.1|localhost):([0-9]{1,5})/?$")
	var matched := allowed.search(url)
	return matched != null and int(matched.get_string(2)) >= 1 and int(matched.get_string(2)) <= 65535

func open_local(url: String, request: Dictionary) -> Error:
	if not _valid_local(url):
		failed.emit("This native/local client permits only a loopback backend.")
		return ERR_UNAUTHORIZED
	_retry_until = 0
	return _begin(url,request,false)

func open_browser(request: Dictionary) -> Error:
	if not OS.has_feature("web"): return ERR_UNAVAILABLE
	var info := browser_info()
	var protocol: String = info.get("protocol","")
	var host: String = info.get("host","")
	var mode: String = info.get("mode","")
	_retry_until = 0
	if protocol == "https:" and mode == "hosted":
		if request.get("mode") != "battle" or request.get("format") != "4v4": return ERR_UNAUTHORIZED
		return _begin("wss://"+host,request,true)
	if protocol == "http:" and mode == "local": return open_local("ws://"+host,request)
	failed.emit("Use the secure classroom game page or the local preview.")
	return ERR_UNAUTHORIZED

func _begin(url: String, request: Dictionary, hosted: bool) -> Error:
	_cancel_ticket()
	if socket != null: socket.close()
	socket = null
	_seated = false
	_joined_current = false
	_sent = false
	latest = {}
	_request = request.duplicate(true)
	_url = url
	_hosted = hosted
	_deadline = Time.get_ticks_msec()+8000
	if hosted:
		_phase = "ticket"
		_ticket_callback = JavaScriptBridge.create_callback(_ticket_result)
		var bridge = JavaScriptBridge.get_interface("tankGodotBridge")
		if bridge == null:
			_phase = "idle"
			failed.emit("Classroom connection helper is unavailable. Reload the game page.")
			return ERR_UNAVAILABLE
		var action: String = request.get("type","")
		var scope := {"action":action,"room":null if action == "create" else request.get("code","")}
		bridge.requestTicket(JSON.stringify(scope),_generation,_ticket_callback)
		return OK
	return _connect(PackedStringArray())

func _cancel_ticket() -> void:
	_generation += 1
	if OS.has_feature("web"):
		var bridge = JavaScriptBridge.get_interface("tankGodotBridge")
		if bridge != null: bridge.cancel()

func _ticket_result(arguments: Array) -> void:
	if arguments.is_empty() or not arguments[0] is String: return
	var result = JSON.parse_string(arguments[0])
	if not result is Dictionary or int(result.get("generation",-1)) != _generation or _phase != "ticket": return
	var ticket: String = result.get("ticket","")
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{16,512}$")
	if pattern.search(ticket) == null:
		_retire("Private access expired or unavailable. Return to Private access and try again.")
		return
	_connect(PackedStringArray(["tank-v1","ticket."+ticket]))

func _connect(protocols: PackedStringArray) -> Error:
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 2097152
	socket.outbound_buffer_size = 65536
	socket.max_queued_packets = 256
	socket.supported_protocols = protocols
	_phase = "connecting"
	_deadline = Time.get_ticks_msec()+8000
	var error := socket.connect_to_url(_url)
	if error != OK: _retire("Connection could not start.")
	return error

func send(message: Dictionary) -> void:
	if _seated and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))

func _visible() -> bool:
	return browser_info().get("visible",false) if OS.has_feature("web") else true

func browser_info() -> Dictionary:
	if not OS.has_feature("web"): return {}
	var bridge = JavaScriptBridge.get_interface("tankGodotBridge")
	if bridge == null: return {}
	var value = JSON.parse_string(str(bridge.info()))
	return value if value is Dictionary else {}

func poll() -> void:
	var now := Time.get_ticks_msec()
	var visible := _visible()
	if visible and not _visible_was: _last_state = now
	_visible_was = visible
	if _phase == "closing_for_rejoin":
		if socket != null: socket.poll()
		if socket == null or socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or now >= _deadline:
			socket = null
			_phase = "retry"
			_retry_at = now+250
		return
	if _phase == "retry":
		if now >= _retry_until:
			_phase = "idle"
			failed.emit("Seat recovery timed out. Reopen the ready room or ask the teacher to restart.")
		elif now >= _retry_at:
			_begin(_session_url,_rejoin_request(),_session_hosted)
		return
	if _phase == "ticket":
		if now >= _deadline: _retire("Private connection request timed out.")
		return
	if socket == null: return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _sent:
			if _hosted and socket.get_selected_protocol() != "tank-v1":
				_retire("Classroom connection was not acknowledged.")
				return
			socket.send_text(JSON.stringify(_request))
			_sent = true
		while socket.get_available_packet_count() > 0:
			var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if not message is Dictionary: continue
			if message.get("type") == "joined":
				map_data = message.map
				room_code = message.code
				_token = message.token
				_session_url = _url
				_session_format = _request.get("format","4v4")
				_session_hosted = _hosted
				_joined_current = true
				joined.emit(room_code)
			elif message.get("type") == "state" and _joined_current:
				_seated = true
				_phase = "seated"
				_retry_until = 0
				_last_state = now
				latest = message
				state_received.emit(latest)
			elif message.get("type") == "error":
				if _seated: server_notice.emit(str(message.message))
				else:
					var transient: bool = _request.get("type") == "reconnect" and message.get("code") == "SESSION_ACTIVE"
					_retire(str(message.message),transient)
					return
		if _seated and visible and now-_last_state > 8000: _retire("No fresh battle updates. Recovering the same seat.")
		elif not _seated and now >= _deadline: _retire("The room did not acknowledge this connection.")
	elif state == WebSocketPeer.STATE_CLOSED:
		_retire("Disconnected. Recovering the same seat when available.")
	elif now >= _deadline:
		_retire("Connection timed out.")

func _retire(message: String, allow_retry: bool = true) -> void:
	var recoverable: bool = allow_retry and not room_code.is_empty() and not _token.is_empty() and (_joined_current or _request.get("type") == "reconnect")
	_cancel_ticket()
	if socket != null: socket.close()
	socket = null
	_seated = false
	latest = {}
	_phase = "idle"
	if recoverable:
		if _retry_until == 0: _retry_until = Time.get_ticks_msec()+22000
		_retry_at = Time.get_ticks_msec()+1250
		_phase = "retry"
	failed.emit(message)

func _rejoin_request() -> Dictionary:
	return {"type":"reconnect","code":room_code,"token":_token,"mode":"battle","format":_session_format,"role":"commander"}

func rejoin() -> Error:
	if room_code.is_empty() or _token.is_empty(): return ERR_UNCONFIGURED
	_retry_until = Time.get_ticks_msec()+22000
	if socket != null and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		send({"type":"input","input":{"throttle":0,"steer":0,"aim":0,"fire":false}})
		_cancel_ticket()
		socket.close()
		_seated = false
		latest = {}
		_phase = "closing_for_rejoin"
		_deadline = Time.get_ticks_msec()+2000
		failed.emit("Rejoining the same seat. Controls are neutral.")
		return OK
	return _begin(_session_url,_rejoin_request(),_session_hosted)

func close() -> void:
	send({"type":"input","input":{"throttle":0,"steer":0,"aim":0,"fire":false}})
	_cancel_ticket()
	if socket != null: socket.close()
	socket = null
	_seated = false
	_phase = "idle"
	_retry_until = 0
