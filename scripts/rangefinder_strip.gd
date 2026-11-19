extends Control
# Public objective ledger: fixed arrays, updated on accepted snapshots only.
# No player list or position enters this instrument. No match clock is invented.
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
	draw_rect(Rect2(0,0,size.x,52), PLATE)
	draw_line(Vector2(0,0),Vector2(size.x,0),CYAN,2)
	draw_string(font,Vector2(0,16),"BASE CONTROL",HORIZONTAL_ALIGNMENT_CENTER,size.x,12,PAPER)
	draw_string(font,Vector2(8,38),"BLUE %d"%blue,HORIZONTAL_ALIGNMENT_LEFT,50,13,CYAN)
	draw_string(font,Vector2(size.x-50,38),"%d RED"%red,HORIZONTAL_ALIGNMENT_RIGHT,42,13,AMBER)
	var w := 22.0
	var x := (size.x-7*w)/2
	for i in 7:
		var owner := codes[i]>>2
		var col := CYAN if owner==1 else AMBER if owner==2 else MUTED
		var box := Rect2(x+i*w,22,w-3,21)
		draw_rect(box,col,owner!=0)
		draw_string(font,box.position+Vector2(0,16),str(i+1)+("B" if owner==1 else "R" if owner==2 else ""),HORIZONTAL_ALIGNMENT_CENTER,box.size.x,12,PLATE if owner!=0 else PAPER)
		if codes[i]%4==3: draw_line(box.position+Vector2(0,22),box.end+Vector2(0,1),PAPER,2)
	if not notice.is_empty():
		draw_rect(Rect2(0,56,size.x,26),PLATE)
		draw_string(font,Vector2(0,75),notice,HORIZONTAL_ALIGNMENT_CENTER,size.x,15,PAPER)
