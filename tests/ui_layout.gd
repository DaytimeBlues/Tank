extends SceneTree

var main: Node
var frames := 0
var failures: Array[String] = []
var views: Array = []
var stage := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_delta: float) -> bool:
	frames += 1
	# The headless display initializes at 64x64 after SceneTree initialization.
	# Resize after that first display tick, then allow container layout to settle.
	if stage == 0 and frames == 1:
		root.size = Vector2i(1280,800)
		return false
	if frames < 10: return false
	var viewport := root.get_visible_rect()
	var hud: Rect2 = main.hud_panel.get_global_rect()
	var stats: Rect2 = main.stats_label.get_global_rect()
	if not viewport.encloses(hud): failures.append("HUD outside viewport")
	if not hud.encloses(stats): failures.append("stats outside HUD")
	if hud.size.y > 140: failures.append("HUD exceeds bounded height")
	views.append({"viewport":str(viewport),"hud":str(hud),"stats":str(stats),"visible":main.stats_label.is_visible_in_tree()})
	if stage == 0:
		stage = 1
		frames = 0
		root.size = Vector2i(390,844)
		return false
	if not is_equal_approx(viewport.size.x,390): failures.append("portrait viewport was not actually resized")
	print("TANK_UI_LAYOUT "+JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"views":views}))
	quit(0 if failures.is_empty() else 1)
	return false
