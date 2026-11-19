extends Control
# Passive view framing. No central hit dot, target lock or range estimate.
# The model's accepted muzzle guide remains the only directional marker.
var zoom_step := 0
func _init() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	focus_mode=FOCUS_NONE
func set_zoom(step: int) -> void:
	if step!=zoom_step:
		zoom_step=step
		queue_redraw()
func _draw() -> void:
	var center := size*0.5
	var r := 39.0 if zoom_step==0 else 52.0
	for side in [-1,1]:
		var angle := 0.0 if side==1 else PI
		draw_arc(center,r,angle-0.44,angle+0.44,12,Color("#182936"),3,true)
		draw_arc(center,r,angle-0.44,angle+0.44,12,Color("#98eafa"),1,true)
		draw_line(center+Vector2(side*r,0),center+Vector2(side*(r-7),0),Color("#e4f1ed"),1,true)
