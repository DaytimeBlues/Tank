extends SceneTree

# Additive prospective fixture, NOT RUN during CPU/source preparation.
# It reports and quits on a missing contact, without indexing an empty array.
var failures: Array[String] = []
var checks := 0
var cases: Array = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void: call_deferred("run")

func wire_shot(id: int, hit: Variant = null, blocked: bool = false) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"id":id,"time":10.0,"x":0.0,"y":2.0,"z":0.0,"endX":0.0,"endY":2.0,"endZ":20.0,"hit":hit,"blocked":blocked}))

func snapshot(main: Node, item: Variant, time_value: float = 10.0) -> Dictionary:
	var bases: Array = main.arena.source_data.bases.duplicate(true)
	for base in bases: base.merge({"owner":"neutral","net":0,"contested":false},true)
	return {"time":time_value,"players":[{"id":"p1","team":"blue","visualId":"kestrel","connected":true,"ready":true,"health":3,"respawnSeconds":0,"shot":item,"tank":{"x":0,"y":3,"z":0,"yaw":0,"turret":0,"reload":0,"speed":0,"quaternion":{"x":0,"y":0,"z":0,"w":1}}}],"playerId":"p1","hostId":"p1","staging":{"waiting":false,"canStart":false,"switchTo":null,"block":null},"won":false,"winner":null,"scores":{"blue":0,"red":0},"capture":{"bases":bases}}

func contacts(fx: TankAcceptedShotEffects) -> Array:
	return fx.active.filter(func(slot: Dictionary): return slot.kind == "contact")

func exercise(fx: TankAcceptedShotEffects, item: Dictionary, expected: bool, label: String) -> bool:
	fx.clear()
	var before := failures.size()
	var rejected_before := fx.rejected
	# Ignore the return here so a broken original gate can still reach the
	# guarded observations and terminal FAIL, rather than a second index error.
	fx.present(item,10.0)
	var found := contacts(fx)
	check(found.size() == (1 if expected else 0),label+": expected contact count")
	check(fx.active.size() == (3 if expected else 2),label+": unchanged muzzle/tracer counts")
	check(fx.rejected == rejected_before,label+": valid geometry is not rejected")
	if found.size() == 1:
		var slot: Dictionary = found[0]
		check(slot.kind == "contact" and slot.life == 0.85 and slot.size == 1.55,label+": baseline contact kind/life/size")
		check(slot.origin.distance_to(Vector3(0,2,19.8)) < 0.00001,label+": unchanged authoritative endpoint setback")
		check(slot.material.get_shader_parameter("variant") == 1.0,label+": original generic recipe only")
	cases.append({"label":label,"expectedContact":expected,"actualContacts":found.size(),"hitType":type_string(typeof(item.get("hit"))),"blockedType":type_string(typeof(item.get("blocked")))})
	return failures.size() == before

func finish(main: Node, stage: String) -> void:
	var report := {"status":"PASS" if failures.is_empty() else "FAIL","kind":"typed-wire headless presentation/history/pool fixture; not server, rendering or Web acceptance","stage":stage,"checks":checks,"failures":failures,"cases":cases,"sourceBinding":{"main":FileAccess.get_sha256("res://scripts/main.gd"),"effects":FileAccess.get_sha256("res://scripts/shot_effects.gd"),"shader":FileAccess.get_sha256("res://assets/effects/accepted_shot.gdshader"),"fixture":FileAccess.get_sha256("res://tests/wire_contact_types.gd")}}
	var output := FileAccess.open("res://evidence/wire-contact-types.json",FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"\t")+"\n")
		output.close()
	else:
		failures.append("Could not write fixture result")
		report.status = "FAIL"
	print("TANK_WIRE_CONTACT_TYPES "+JSON.stringify(report))
	main.queue_free()
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	if not main.presentation_preparation_complete: await main.presentation_preparation_finished
	var fx: TankAcceptedShotEffects = main.shot_effects
	var ids: Array = fx.slots.map(func(slot: Dictionary): return slot.node.get_instance_id())
	var matrix := [{"name":"enemy String","hit":"p2","unblocked":true},{"name":"null","hit":null,"unblocked":false},{"name":"legacy true","hit":true,"unblocked":true},{"name":"legacy false","hit":false,"unblocked":false},{"name":"empty String","hit":"","unblocked":false},{"name":"omitted","hit":null,"unblocked":false}]
	for row in matrix:
		for blocked in [false,true]:
			var item := wire_shot(1,row.hit,blocked)
			if row.name == "omitted": item.erase("hit")
			if not exercise(fx,item,row.unblocked or blocked,row.name+" / blocked="+str(blocked)):
				finish(main,"type_matrix")
				return
	for row in [{"name":"missing blocked miss","hit":null,"expected":false},{"name":"missing blocked enemy","hit":"p2","expected":true}]:
		var item := wire_shot(1,row.hit)
		item.erase("blocked")
		if not exercise(fx,item,row.expected,row.name):
			finish(main,"missing_blocked")
			return
	# Defensive malformed-type cases are injected AFTER the JSON wire fixture;
	# Vector/Object values are not claimed to be real backend JSON payloads.
	for value in [0,1,-1,0.5,[],[true],{},{"id":"p2"},Vector3.ONE,main]:
		for blocked in [false,true]:
			var item := wire_shot(2,null,blocked)
			item.hit = value
			if not exercise(fx,item,blocked,"unsupported hit "+type_string(typeof(value))+" / blocked="+str(blocked)):
				finish(main,"unsupported_hit")
				return
	for value in [null,0,1,0.5,"true","false","",[],{},Vector3.ONE,main]:
		var item := wire_shot(3)
		item.blocked = value
		if not exercise(fx,item,false,"unsupported blocked "+type_string(typeof(value))):
			finish(main,"unsupported_blocked")
			return
	fx.clear()
	for i in range(2000):
		fx.present(wire_shot(i,"p2" if i % 3 == 0 else null,i % 3 != 2),10.0+float(i)*0.001)
	check(fx.slots.size() == 24 and fx.active.size() == 24,"2000 mixed real-wire shots retain 24 slots")
	for kind in ["tracer","muzzle","contact"]:
		check(fx.active.filter(func(slot: Dictionary): return slot.kind == kind).size() == 8,"same eight "+kind+" slots")
	check(ids == fx.slots.map(func(slot: Dictionary): return slot.node.get_instance_id()),"measured pool node identities unchanged, not a general allocation/FPS claim")
	fx.clear()
	var emitted_before := fx.emitted
	main._accept_state(snapshot(main,wire_shot(1,"p2",true)))
	check(fx.emitted == emitted_before,"first real-wire snapshot seeds history without replay")
	main._accept_state(snapshot(main,wire_shot(2,"p2",true)))
	check(fx.emitted == emitted_before+3 and contacts(fx).size() == 1,"fresh String event emits once")
	emitted_before = fx.emitted
	main.peers.p1.recoil_age = 0.42
	main._accept_state(snapshot(main,wire_shot(2,"p2",true)))
	main._accept_state(snapshot(main,wire_shot(1,"p2",true)))
	main._accept_state(snapshot(main,wire_shot(2,"p2",true)))
	check(fx.emitted == emitted_before and main.peers.p1.recoil_age == 0.42,"duplicate/regression cannot emit or recoil")
	for reason in ["staging","dead","reloading","disconnected","won"]:
		var unchanged := snapshot(main,wire_shot(2,"p2",true))
		if reason == "staging": unchanged.staging.waiting = true
		if reason == "dead": unchanged.players[0].health = 0
		if reason == "reloading": unchanged.players[0].tank.reload = 4.0
		if reason == "disconnected": unchanged.players[0].connected = false
		if reason == "won": unchanged.won = true
		main._accept_state(unchanged)
		check(fx.emitted == emitted_before and main.peers.p1.recoil_age == 0.42,"unchanged server ID after "+reason+" rejection has no feedback; not a server rejection test")
	var stale := wire_shot(3,"p2",true)
	stale.time = 0.0
	main._accept_state(snapshot(main,stale,0.35))
	var future := wire_shot(4,"p2",true)
	future.time = 11.0
	main._accept_state(snapshot(main,future))
	main._accept_state(snapshot(main,wire_shot(4,"p2",true)))
	check(fx.emitted == emitted_before and main.old_shots.p1 == 4,"stale/future IDs consumed without later replay")
	main._accept_state(snapshot(main,wire_shot(5,null,true)))
	check(fx.emitted == emitted_before+3,"fresh generic blocked contact emits once")
	fx.clear()
	var absent := snapshot(main,null)
	absent.players = []
	main._accept_state(absent)
	main._accept_state(snapshot(main,wire_shot(6,"p2",true)))
	check(fx.active.is_empty(),"removed/reappearing seat seeds history")
	main._accept_state(snapshot(main,wire_shot(7,"p2",true)))
	main._network_error("Wire-type fixture disconnect")
	check(fx.active.is_empty(),"disconnect clears all cues")
	main._accept_state(snapshot(main,wire_shot(7,"p2",true)))
	check(fx.active.is_empty(),"first rejoin snapshot does not replay")
	main._accept_state(snapshot(main,wire_shot(8,null,false)))
	check(fx.active.size() == 2 and contacts(fx).is_empty(),"fresh null/false rejoin miss has no endpoint")
	fx.update(float(Time.get_ticks_msec())/1000.0+2.0,main.camera)
	check(fx.active.is_empty(),"normal expiry hides cues")
	finish(main,"complete")
