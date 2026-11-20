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
# View-relative decoration only; never receives a tank pose, cursor or target.
func frame_radius() -> float:
	return [39.0,67.0,88.0][clampi(zoom_step,0,2)]

func _draw() -> void:
	var center := size*0.5
	var r := frame_radius()
	var span := 0.32 + 0.08*zoom_step
	for side in [-1,1]:
		var angle := 0.0 if side==1 else PI
		draw_arc(center,r,angle-span,angle+span,20,Color("#172a31"),3.5,true)
		draw_arc(center,r,angle-span,angle+span,20,Color("#98eafa"),1.6,true)
		var start := center+Vector2(side*r,0)
		var end := start-Vector2(side*(5+zoom_step*2),0)
		draw_line(start,end,Color("#172a31"),3,true)
		draw_line(start,end,Color("#eff2df"),1.4,true)
