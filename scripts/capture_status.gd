extends RefCounted
# Presentation only. Team occupancy is accepted server state, never own contribution.
static func describe(state: Dictionary, own: Dictionary) -> String:
	if state.get("won",false): return str(state.get("winner","")).to_upper()+" WINS · Host: choose Rematch"
	var fallback := "Capture all seven bases. M: map · Esc: menu"
	if state.get("practice",false): fallback = "Solo practice: drive, shoot or try a capture. No win condition. M: map"
	var tank: Dictionary = own.get("tank",{})
	if not tank.has("x") or not tank.has("z"): return fallback
	var x := float(tank.x)
	var z := float(tank.z)
	if not is_finite(x) or not is_finite(z): return fallback
	var nearest: Dictionary = {}
	var distance := INF
	for base in state.get("capture",{}).get("bases",[]):
		if not base.has_all(["x","z","radius"]): continue
		if not is_finite(float(base.radius)) or float(base.radius)<=0: continue
		var d := Vector2(x-float(base.x),z-float(base.z)).length()
		if is_finite(d) and d <= float(base.radius)+5.0 and d < distance:
			nearest = base
			distance = d
	if nearest.is_empty(): return fallback
	var b := nearest
	var action:=_public_pressure(b)
	var hint:=_own_hint(b,tank,own,distance)
	# Missing occupancy is unknown, not an invented zero. Counts include eligible teammates.
	var counts := "Team count unavailable"
	if b.has("blue") and b.has("red"): counts = "Blue %d / Red %d" % [int(b.blue),int(b.red)]
	return "%s %s: %s\n%s - %s" % [str(b.get("id","")),str(b.get("name","Base")),action,counts,hint]

# Snapshot counters describe the team. Local geometry only supplies an instruction.
static func _public_pressure(b: Dictionary) -> String:
	var progress := float(b.get("progress",0))
	var net := int(b.get("net",0))
	var action := "Contested" if b.get("contested",false) else "Blue taking" if net>0 and progress<1 else "Red taking" if net<0 and progress> -1 else "Hold the circle"
	# A contested circle can still advance. Read only the published counters;
	# never infer player participation or direction from team proximity.
	if b.get("contested",false) and b.has_all(["blue","red","net","progress"]):
		var blue = b.blue
		var red = b.red
		if (blue is int or blue is float) and (red is int or red is float) and (b.net is int or b.net is float) and blue>0 and red>0 and blue==floorf(blue) and red==floorf(red) and b.net==blue-red and is_finite(progress):
			if net==0: action = "Contested - Even: progress paused"
			elif net>0: action = "Contested - Blue advancing" if progress<1 else "Contested - Blue holding"
			else: action = "Contested - Red advancing" if progress> -1 else "Contested - Red holding"
	if not b.get("contested",false) and ((progress>=1 and net>=0) or (progress<= -1 and net<=0)): action = "Blue secured" if progress>=1 else "Red secured"
	return action

static func _own_hint(b: Dictionary,tank: Dictionary,own: Dictionary,distance: float) -> String:
	var hint := "Stay grounded in circle"
	if own.get("health",0)<=0: hint = "Respawn to help"
	elif not own.get("connected",false): hint = "Reconnect to help"
	elif distance>float(b.radius): hint = "Enter circle"
	elif not tank.has("y") or not b.has("y") or not is_finite(float(tank.y)) or not is_finite(float(b.y)): hint = "Ground contact required"
	elif absf(float(tank.y)-(float(b.y)+1.05))>0.65: hint = "Move onto base ground"
	return hint

# Larger, high-contrast reading of the existing above-base sign. No player lists:
# use own accepted pose for proximity, fixed landmarks and public base counters.
static func field_card(state: Dictionary, own: Dictionary, arena: TankArenaView) -> String:
	var tank: Dictionary = own.get("tank",{})
	if not is_instance_valid(arena) or not tank.has_all(["x","z"]) or own.get("health",0)<=0: return ""
	var selected: Dictionary = {}
	var nearest := INF
	for b in state.get("capture",{}).get("bases",[]):
		if not b.has_all(["x","z","radius","name","id","owner"]): continue
		var d := Vector2(float(tank.x)-float(b.x),float(tank.z)-float(b.z)).length()
		if d<=float(b.radius)+5.0 and d<nearest:
			selected=b
			nearest=d
	if selected.is_empty(): return ""
	var b:=selected
	var owner := "Blue owned" if b.owner=="blue" else "Red owned" if b.owner=="red" else "Neutral"
	var rail := arena.capture_rail(b)
	var timing := rail.get_slice("   ",1)
	var line := _public_pressure(b)
	if timing=="Paused":
		line="Contested / Paused" if b.get("contested",false) else "Paused"
	elif not timing.is_empty():
		line+=" / "+timing
	var hint := _own_hint(b,tank,own,nearest)
	# ETA may come from an eligible teammate. Keep local instructions independent
	# of the public timer. Being inside does not establish individual contribution.
	if hint!="Stay grounded in circle": line=hint if line=="Hold the circle" else line+"\n"+hint
	return "%s   /   %s   /   %s\n%s" % [str(b.id),str(b.name),owner,line]
