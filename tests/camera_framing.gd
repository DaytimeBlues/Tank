extends SceneTree

func _initialize() -> void:
    call_deferred("run")

func meshes(node: Node) -> Array[MeshInstance3D]:
    var out: Array[MeshInstance3D] = []
    if node is MeshInstance3D: out.append(node)
    for child in node.get_children(): out.append_array(meshes(child))
    return out

func run() -> void:
    var viewport := SubViewport.new()
    viewport.own_world_3d = true
    root.add_child(viewport)
    var camera := Camera3D.new()
    viewport.add_child(camera)
    camera.current = true
    camera.fov = 55.0
    camera.far = 650.0
    camera.position = Vector3(0,12,-20)
    camera.look_at(Vector3(0,1.4,0))
    var rows: Array = []
    for id in ["kestrel","bastion","foundry","palisade"]:
        var model: Node3D = load("res://assets/models/%s.glb" % id).instantiate()
        viewport.add_child(model)
        var turret := model.find_child("TurretYaw",true,false) as Node3D
        for size in [Vector2i(1449,1232),Vector2i(1280,720),Vector2i(390,844),Vector2i(320,900)]:
            viewport.size = size
            camera.position = Vector3(0,12,-20)*load("res://scripts/main.gd").camera_distance_scale(Vector2(size))
            camera.look_at(Vector3(0,1.4,0))
            await process_frame
            var min_x := INF
            var max_x := -INF
            var min_y := INF
            var max_y := -INF
            var clipped_angles: Array = []
            for angle in range(0,360,5):
                model.rotation = Vector3(deg_to_rad(12),0,deg_to_rad(12))
                turret.rotation.y = deg_to_rad(angle)
                var clipped := false
                for mesh in meshes(model):
                    var box := mesh.get_aabb()
                    for i in range(8):
                        var world_point := mesh.global_transform * box.get_endpoint(i)
                        var point := camera.unproject_position(world_point)
                        min_x = minf(min_x,point.x)
                        max_x = maxf(max_x,point.x)
                        min_y = minf(min_y,point.y)
                        max_y = maxf(max_y,point.y)
                        if point.x < 0 or point.x > size.x or point.y < 0 or point.y > size.y: clipped = true
                if clipped: clipped_angles.append(angle)
            rows.append({"model":id,"viewport":[size.x,size.y],"minX":min_x,"maxX":max_x,"minY":min_y,"maxY":max_y,"clippedAngles":clipped_angles})
        model.queue_free()
        await process_frame
    var output := {"kind":"Headless conservative mesh-AABB projection, not rendered input acceptance","engine":Engine.get_version_info().string,"keepAspect":camera.keep_aspect,"cameraOffset":[0,12,-20],"fov":55,"candidate":"Scale chase offset by max(1,0.5/aspect); isolated only","rows":rows,"limits":["Fixed +12 degree pitch and roll stress pose; no dynamic camera lag or terrain occlusion.","Mesh AABB corners conservatively enclose the rendered geometry.","No UI/readability, physics, network or performance acceptance."]}
    var file := FileAccess.open("user://tank-narrow-camera-projection.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(output,"  "))
    file.close()
    var failures: Array = []
    for row in rows:
        if not row.clippedAngles.is_empty(): failures.append(row.model+str(row.viewport))
    var source = load("res://scripts/main.gd")
    if source.camera_distance_scale(Vector2(1280,720)) != 1.0: failures.append("Wide camera changed")
    if source.camera_distance_scale(Vector2.ZERO) != 1.0: failures.append("Invalid viewport fallback")
    print("CAMERA_PROJECTION ",JSON.stringify({"rows":rows.size(),"failures":failures}))
    quit(0 if failures.is_empty() else 1)
