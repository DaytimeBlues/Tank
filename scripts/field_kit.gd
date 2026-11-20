extends RefCounted
# One visual alphabet for the ledger, map pins and key. No match state is stored here.
const BLUE := Color("#8adeef")
const RED := Color("#f9ba68")
const PAPER := Color("#faf1d9")
const MUTED := Color("#c1cfca")
const PLATE := Color("#15272c")
const EDGE := Color("#53747a")

static func paint_owner(canvas: Control, p: Vector2, radius: float, owner: String) -> void:
	if owner == "blue":
		canvas.draw_rect(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),BLUE)
	elif owner == "red":
		canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius-1),p+Vector2(radius+1,radius),p+Vector2(-radius-1,radius)]),RED)
	else:
		canvas.draw_arc(p,radius,0,TAU,20,PAPER,1.7,true)

static func plate(fill: Color, edge: Color, horizontal: int = 10, vertical: int = 5) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box

static func controls_theme() -> Theme:
	var theme := Theme.new()
	for type in ["Button","LineEdit","OptionButton"]:
		theme.set_stylebox("normal",type,plate(Color("#25393d"),EDGE))
		theme.set_stylebox("focus",type,focus_ring())
		theme.set_color("font_color",type,PAPER)
		theme.set_color("font_focus_color",type,PAPER)
		if type == "LineEdit":
			theme.set_color("font_placeholder_color",type,MUTED)
			continue
		theme.set_stylebox("hover",type,plate(Color("#33545a"),BLUE))
		theme.set_stylebox("pressed",type,plate(Color("#25464c"),PAPER))
		theme.set_stylebox("disabled",type,plate(Color("#222c2e"),Color("#435256")))
		theme.set_color("font_disabled_color",type,Color("#a4aeab"))
	theme.set_color("font_color","Label",PAPER)
	return theme

static func focus_ring() -> StyleBoxFlat:
	var box := plate(Color.TRANSPARENT,PAPER)
	box.draw_center = false
	box.set_border_width_all(2)
	return box
