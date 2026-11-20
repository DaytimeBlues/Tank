extends Control
# Public objective ledger: fixed arrays, updated on accepted snapshots only.
# No player list or position enters this instrument. No match clock is invented.
const Kit := preload("res://scripts/field_kit.gd")
const CYAN := Color("#84def2")
const AMBER := Color("#ffbd64")
const PAPER := Color("#f3f1e9")
const PLATE := Color("#101f29")
const MUTED := Color("#98aeb2")
const NONE := -1
var codes := PackedInt32Array([-1,-1,-1,-1,-1,-1,-1])
var scratch := PackedInt32Array([-1,-1,-1,-1,-1,-1,-1])
var names := PackedStringArray(["","","","","","",""])
var seeded := false
var blue := 0
var red := 0
var last_time := -1.0
var last_index := 6
var last_priority := 0
var notice := ""
var notice_id := ""
var timer := Timer.new()
signal marker_changed(id: String, glyph: String)

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	timer.one_shot = true
	timer.wait_time = 2.3
	add_child(timer)
	timer.timeout.connect(clear_notice)

func clear_notice() -> void:
	if notice.is_empty(): return
	timer.stop()
	notice = ""
	notice_id = ""
	last_priority = 0
	marker_changed.emit("","")
	queue_redraw()

func begin_epoch() -> void:
	clear_notice()
	if seeded: queue_redraw()
	seeded = false
	last_time = -1
	last_index = 6
	codes.fill(NONE)

func present(t: float, bases: Array) -> void:
	if not is_finite(t) or t <= last_time or bases.size() != 7: return
	var mask := 0
	var next_blue := 0
	var next_red := 0
	for b in bases:
		if not b is Dictionary: return
		var id := str(b.get("id",""))
		if id.length()!=1 or not id.is_valid_int(): return
		var i := id.to_int()-1
		if i<0 or i>6 or mask & (1<<i): return
		mask |= 1<<i
		var o := str(b.get("owner",""))
		if o!="blue" and o!="red" and o!="neutral": return
		if not b.get("name") is String or str(b.name).is_empty() or not b.get("contested") is bool: return
		if not (typeof(b.get("progress")) in [TYPE_FLOAT, TYPE_INT]) or not (typeof(b.get("net")) in [TYPE_FLOAT,TYPE_INT]): return
		var progress := float(b.progress)
		var net := float(b.net)
		if not is_finite(progress) or absf(progress)>1 or not is_finite(net) or net!=floorf(net) or absf(net)>8: return
		var owner := 1 if o=="blue" else 2 if o=="red" else 0
		var activity := 3 if b.contested else 1 if net>0 and progress<1 else 2 if net<0 and progress> -1 else 0
		scratch[i] = owner*4+activity
		names[i] = str(b.name)
		if owner==1: next_blue+=1
		if owner==2: next_red+=1
	var best := -1
	var priority := 0
	var changed := not seeded
	for offset in 7:
		# Round-robin tie break; a busy first landmark cannot monopolise equal notices.
		var i := (last_index+1+offset)%7
		var v := scratch[i]
		var old := codes[i]
		if old==v: continue
		changed = true
		if not seeded: continue
		var act := v%4
		var p := 3 if (v>>2)!=(old>>2) and (v>>2)!=0 else 2 if act==3 and old%4!=3 else 1 if (act==1 or act==2) and old%4!=act else 0
		if p>priority:
			best=i
			priority=p
	last_time=t
	if not changed: return
	var tmp := codes
	codes=scratch
	scratch=tmp
	blue=next_blue
	red=next_red
	seeded=true
	if best>=0 and (timer.is_stopped() or priority>last_priority):
		last_index=best
		last_priority=priority
		var v := codes[best]
		var side := "Blue" if (v>>2 if priority==3 else v%4)==1 else "Red"
		notice=side+" captured "+names[best] if priority==3 else names[best]+" is contested" if priority==2 else side+" is taking "+names[best]
		notice_id=str(best+1)
		marker_changed.emit(notice_id,"F" if priority==3 else "!" if priority==2 else "+")
		timer.start()
	queue_redraw()

func _draw() -> void:
	if not seeded: return
	var font := ThemeDB.fallback_font
	# Five-sided numbered badges keep their identity when an owner changes.
	draw_rect(Rect2(0,0,size.x,52),Kit.PLATE)
	draw_line(Vector2(1,1),Vector2(size.x-1,1),Kit.EDGE,2)
	draw_string(font,Vector2(0,17),"BASE CONTROL",HORIZONTAL_ALIGNMENT_CENTER,size.x,14,Kit.PAPER)
	draw_string(font,Vector2(8,39),"BLUE %d"%blue,HORIZONTAL_ALIGNMENT_LEFT,62,16,Kit.BLUE)
	draw_string(font,Vector2(size.x-67,39),"%d RED"%red,HORIZONTAL_ALIGNMENT_RIGHT,59,16,Kit.RED)
	Kit.paint_owner(self,Vector2(63,33),3.5,"blue")
	Kit.paint_owner(self,Vector2(size.x-63,33),3.5,"red")
	var w := 30.0
	var x := (size.x-7*w)*0.5
	for i in 7:
		var n := codes[i]>>2
		var owner := "blue" if n==1 else "red" if n==2 else "neutral"
		var left := x+i*w
		var points := PackedVector2Array([Vector2(left,21),Vector2(left+27,21),Vector2(left+27,42),Vector2(left+13.5,48),Vector2(left,42)])
		draw_colored_polygon(points,Color("#263c40"))
		points.append(points[0])
		draw_polyline(points,Kit.BLUE if n==1 else Kit.RED if n==2 else Kit.EDGE,1.4,true)
		Kit.paint_owner(self,Vector2(left+7,33),3,owner)
		draw_string(font,Vector2(left+12,40),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Kit.PAPER)
		if codes[i]%4==3: draw_line(Vector2(left+8,44),Vector2(left+20,44),Kit.PAPER,2)
	if not notice.is_empty():
		draw_rect(Rect2(0,56,size.x,26),Kit.PLATE)
		draw_string(font,Vector2(0,75),notice,HORIZONTAL_ALIGNMENT_CENTER,size.x,16,Kit.PAPER)
