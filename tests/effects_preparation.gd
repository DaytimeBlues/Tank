extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-4000,-4000)
	call_deferred("run")

func run() -> void:
	var source_paths := ["scripts/main.gd","scripts/shot_effects.gd","tests/effects_preparation.gd"]
	var before := {}
	for path in source_paths: before[path] = FileAccess.get_sha256("res://"+path)
	var headless := DisplayServer.get_name() == "headless"
	var fail_draw := OS.get_cmdline_user_args().has("--simulate-render-disabled") and not headless
	var late_draw := OS.get_cmdline_user_args().has("--simulate-late-completion") and not headless
	var scene_late := OS.get_cmdline_user_args().has("--simulate-scene-late") and not headless
	var expected_failure := fail_draw or late_draw or scene_late
	if scene_late:
		RenderingServer.frame_post_draw.connect(func(): OS.delay_msec(20100),CONNECT_ONE_SHOT)
	var started := Time.get_ticks_msec()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	var fx: TankAcceptedShotEffects = main.shot_effects
	if fail_draw:
		fx.scene_startup_finished.connect(func(ok: bool):
			if ok: RenderingServer.render_loop_enabled = false
		,CONNECT_ONE_SHOT)
	var on_late: Callable
	var delayed := {"done":false}
	if late_draw:
		on_late = func():
			if not delayed.done and is_instance_valid(fx.preparation_viewport):
				delayed.done = true
				OS.delay_msec(2100)
		RenderingServer.frame_post_draw.connect(on_late)
	var original_ids: Array = []
	for slot in fx.slots: original_ids.append(slot.node.get_instance_id())
	if not main.presentation_preparation_complete:
		await main.presentation_preparation_finished
	check(main.presentation_preparation_complete,"explicit completion signal ends preparation")
	check(main.presentation_prepared == not expected_failure,"READY eligibility requires actual success or explicit headless skip")
	check(fx.active.is_empty() and fx.emitted == 0 and fx.rejected == 0,"preparation creates no fake shot/emission/rejection")
	check(main.old_shots.is_empty() and main.peers.is_empty() and main.state.is_empty(),"preparation does not seed history/peers/state")
	check(fx.slots.size() == 24 and fx.slots.all(func(slot: Dictionary): return not slot.node.visible and slot.node.position == Vector3.ZERO),"permanent24 nodes remain hidden/unmoved")
	var final_ids: Array = []
	for slot in fx.slots: final_ids.append(slot.node.get_instance_id())
	check(original_ids == final_ids,"no pool node was replaced or borrowed")
	check(not is_instance_valid(fx.preparation_viewport) and main.get_node_or_null("EffectsPreparation") == null,"temporary viewport and all children retired before completion")
	check(main.camera.position == Vector3(-145,25,-65),"production camera position is unchanged")
	check(main.get_viewport().get_camera_3d() == main.camera,"offscreen preparation cannot steal production viewport camera")
	check(TankAcceptedShotEffects.preparation_result_on_time(17,1999),"completed verified readback just before deadline is eligible")
	check(not TankAcceptedShotEffects.preparation_result_on_time(17,2000) and not TankAcceptedShotEffects.preparation_result_on_time(17,2001) and not TankAcceptedShotEffects.preparation_result_on_time(16,39),"late draw/readback completion or missing cell cannot be accepted")
	var scene_receipt := fx.scene_startup_report
	check((headless and scene_receipt.status == "SKIPPED_HEADLESS") or (not headless and not scene_late and scene_receipt.status == "FIRST_SCENE_DRAW_VERIFIED" and scene_receipt.drawCalls > 0 and not scene_receipt.effectViewportCreated) or (scene_late and scene_receipt.status == "FAILED" and not scene_receipt.effectViewportCreated),"normal first-scene draw/readback precedes isolated effect allocation")
	check(TankAcceptedShotEffects.scene_startup_result_on_time(true,19999) and not TankAcceptedShotEffects.scene_startup_result_on_time(true,20000) and not TankAcceptedShotEffects.scene_startup_result_on_time(false,50),"separate scene-startup allowance rejects late or unverified completion")
	if late_draw and RenderingServer.frame_post_draw.is_connected(on_late): RenderingServer.frame_post_draw.disconnect(on_late)
	var receipt := fx.preparation_report.duplicate(true)
	var repeated := await fx.prepare()
	check(repeated == not expected_failure and fx.preparation_report == receipt,"repeated preparation is idempotent and allocates nothing")
	if headless:
		check(receipt.status == "SKIPPED_HEADLESS" and receipt.temporaryNodes == 0 and receipt.drawnMaterials == 0,"headless is an explicit no-draw/no-allocation skip")
		check(Time.get_ticks_msec()-started < 1500,"headless path never waits for draw signals")
	elif scene_late:
		check(receipt.status == "FAILED" and receipt.phase == "SCENE_STARTUP" and receipt.reason == "LATE_SCENE_DRAW_TIMEOUT","late first-scene completion is rejected under its own deadline")
		check(receipt.sceneStartup.deadlineOverrunMs > 0 and receipt.temporaryNodes == 0 and receipt.drawnMaterials == 0,"failed first scene never allocates or verifies fancy effects")
	elif late_draw:
		check(receipt.status == "FAILED" and receipt.reason == "LATE_DRAW_TIMEOUT","late completed draw cannot become READY")
		check(receipt.deadlineOverrunMs > 0 and receipt.retired,"late completion records overrun and retires all temporary nodes")
	elif fail_draw:
		check(receipt.status == "FAILED" and receipt.reason == "DRAW_TIMEOUT","disabled draw loop fails without false READY")
		check(receipt.attempts <= 3 and receipt.retired,"timeout cleanup remains bounded")
		RenderingServer.render_loop_enabled = true
	else:
		check(receipt.status == "DRAW_VERIFIED" and receipt.drawnMaterials == 17 and receipt.samples.size() == 17,"all17 material-cell pixels verified by completed GPU texture readback")
		var names: Array = receipt.samples.map(func(item: Dictionary): return item.cue)
		check(names.any(func(n: String): return n.begins_with("muzzle_hot")) and names.any(func(n: String): return n.begins_with("muzzle_smoke")) and names.any(func(n: String): return n.begins_with("contact_hot")) and names.any(func(n: String): return n.begins_with("contact_smoke")) and "tracer" in names,"actual muzzle/contact hot+smoke and tracer coverage recorded")
	var after := {}
	for path in source_paths: after[path] = FileAccess.get_sha256("res://"+path)
	check(before == after,"main/pool/fixture source bytes unchanged throughout actual test")
	var binding := {"before":before,"after":after,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"displayServer":DisplayServer.get_name()}
	var report := {"status":"PASS" if failures.is_empty() else "FAIL","kind":"presentation startup lifecycle/readback fixture, not ordinary combat or frame-performance acceptance","sourceBinding":binding,"headless":headless,"simulatedDrawFailure":fail_draw,"simulatedLateCompletion":late_draw,"simulatedSceneLate":scene_late,"checks":checks,"failures":failures,"preparation":receipt}
	var suffix := "headless" if headless else ("scene-late" if scene_late else ("late" if late_draw else ("timeout" if fail_draw else "native")))
	var file := FileAccess.open("res://evidence/startup-bound-"+suffix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("TANK_PREPARATION_TEST "+JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
