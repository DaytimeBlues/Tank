extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void: call_deferred("run")

func shot(id: int = 1, contact: bool = false) -> Dictionary:
	return {"id":id,"time":10.0,"x":0.0,"y":2.0,"z":0.0,"endX":0.0,"endY":2.0,"endZ":20.0,"hit":contact,"blocked":false}

func fixture(main: Node, item: Variant, time_value: float = 10.0) -> Dictionary:
	var bases: Array = main.arena.source_data.bases.duplicate(true)
	for base in bases:
		base.merge({"owner":"neutral","net":0,"contested":false},true)
	return {"time":time_value,"players":[{"id":"p1","team":"blue","visualId":"kestrel","connected":true,"ready":true,"health":3,"respawnSeconds":0,"shot":item,"tank":{"x":0,"y":3,"z":0,"yaw":0,"turret":0,"reload":0,"speed":0,"quaternion":{"x":0,"y":0,"z":0,"w":1}}}],"playerId":"p1","hostId":"p1","staging":{"waiting":false,"canStart":false,"switchTo":null,"block":null},"won":false,"winner":null,"scores":{"blue":0,"red":0},"capture":{"bases":bases}}

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await process_frame
	var fx: TankAcceptedShotEffects = main.shot_effects
	var instance_ids: Array = []
	for slot in fx.slots: instance_ids.append(slot.node.get_instance_id())
	check(fx.slots.size() == 24 and fx.active.is_empty(),"eight slots per cue type,24 permanent initially hidden mesh nodes")
	check(fx.present(shot(),10.0),"finite accepted miss is presentable")
	check(fx.active.size() == 2,"miss has muzzle and tracer only")
	check(fx.active.all(func(slot: Dictionary): return slot.kind != "contact"),"miss has zero impact/smoke at endpoint")
	fx.clear()
	var blocked := shot()
	blocked.blocked = true
	fx.present(blocked,10.0)
	check(fx.active.size() == 3 and fx.active[-1].kind == "contact","confirmed blocked endpoint has one contact")
	check(fx.active[-1].origin.distance_to(Vector3(0,2,19.8))<0.00001,"contact visual anchored to accepted endpoint with 0.20m ray setback")
	fx.clear()
	for i in range(8): fx.present(shot(i,false),10.0)
	for kind in ["muzzle","tracer"]:
		check(fx.active.filter(func(slot: Dictionary): return slot.kind == kind).size() == 8,"eight simultaneous misses retain eight "+kind+" acknowledgements")
	check(fx.active.size() == 16,"eight misses have sixteen essential cues and zero contact")
	fx.clear()
	for i in range(8): fx.present(shot(i,true),10.0)
	for kind in ["muzzle","tracer","contact"]:
		check(fx.active.filter(func(slot: Dictionary): return slot.kind == kind).size() == 8,"eight simultaneous contacts retain eight "+kind+" cues")
	fx.update(10.14,main.camera)
	check(fx.active.filter(func(slot: Dictionary): return slot.kind == "contact").size() == 8,"lingering cosmetics retain eight contact cards")
	for i in range(8): fx.present(shot(i+9,false),10.15)
	for kind in ["muzzle","tracer"]:
		check(fx.active.filter(func(slot: Dictionary): return slot.kind == kind).size() == 8,"saturated smoke cannot evict new essential "+kind+" cues")
	fx.clear()
	for i in range(2000):
		fx.present(shot(i,true),10.0)
	check(fx.active.size() == 24 and fx.slots.size() == 24,"2000 accepted contacts saturate at24 total nodes and eight per cue")
	var current_ids: Array = []
	for slot in fx.slots: current_ids.append(slot.node.get_instance_id())
	check(current_ids == instance_ids,"pool reuses the same nodes under saturation, with no per-shot node allocation")
	check(fx.active.all(func(slot: Dictionary): return is_instance_valid(slot.node) and slot.node.visible),"saturated slots remain valid and visible")
	fx.update(12.0,main.camera)
	check(fx.active.is_empty() and fx.slots.all(func(slot: Dictionary): return not slot.node.visible),"all expired effects hide without freeing the permanent pool")
	var invalid := shot()
	invalid.x = NAN
	check(not fx.present(invalid,12.0) and fx.active.is_empty(),"NaN shot cannot create effects")
	invalid = shot()
	invalid.endZ = 151.0
	check(not fx.present(invalid,12.0),"out-of-contract range cannot create effects")
	invalid = shot()
	invalid.erase("endY")
	check(not fx.present(invalid,12.0),"incomplete shot cannot create effects")
	main._accept_state(fixture(main,shot(4,true)))
	check(fx.active.is_empty(),"first snapshot seeds shot history without replaying contact")
	main._accept_state(fixture(main,shot(5,true)))
	check(fx.active.size() == 3,"new fresh authoritative shot presents once")
	var count_before := fx.emitted
	main._accept_state(fixture(main,shot(5,true)))
	check(fx.emitted == count_before,"duplicate shot snapshot cannot double present")
	main._accept_state(fixture(main,shot(3,true)))
	main._accept_state(fixture(main,shot(5,true)))
	check(fx.emitted == count_before,"regressing shot id cannot reset history and re-enable a replay")
	var stale := shot(6,true)
	stale.time = 9.0
	main._accept_state(fixture(main,stale))
	check(fx.emitted == count_before,"stale accepted shot history does not replay contact")
	var future := shot(7,true)
	future.time = 11.0
	main._accept_state(fixture(main,future))
	check(fx.emitted == count_before,"future-dated shot has no early impact")
	main._network_error("Fixture disconnect")
	check(fx.active.is_empty(),"disconnect clears all visible pool entries")
	main._accept_state(fixture(main,shot(7,true)))
	check(fx.active.is_empty(),"first rejoin snapshot seeds history without an old impact")
	main._accept_state(fixture(main,shot(8,false)))
	check(fx.active.size() == 2,"next fresh miss after rejoin still has zero contact")
	var result := {"kind":"headless presentation/history/pool fixtures, not rendered visual or device performance proof","checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL"}
	var output := FileAccess.open("res://evidence/visual-effects-tests.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t")+"\n")
	print("TANK_VISUAL_EFFECTS "+JSON.stringify(result))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
