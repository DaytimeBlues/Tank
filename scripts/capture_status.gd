extends RefCounted
# Presentation only. Team occupancy is accepted server state, never own contribution.
static func describe(state: Dictionary, own: Dictionary) -> String:
	if state.get("won",false): return str(state.get("winner","")).to_upper()+" WINS · Host: choose Rematch"
	var fallback := "Capture all seven bases. M: map · Esc: menu"
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
	var progress := float(b.get("progress",0))
	var net := int(b.get("net",0))
	var action := "Contested" if b.get("contested",false) else "Blue taking" if net>0 and progress<1 else "Red taking" if net<0 and progress> -1 else "Hold the circle"
	if not b.get("contested",false) and ((progress>=1 and net>=0) or (progress<= -1 and net<=0)): action = "Blue secured" if progress>=1 else "Red secured"
	var hint := "Stay grounded in circle"
	if own.get("health",0)<=0: hint = "Respawn to help"
	elif not own.get("connected",false): hint = "Reconnect to help"
	elif distance>float(b.radius): hint = "Enter circle"
	elif not tank.has("y") or not b.has("y") or not is_finite(float(tank.y)) or not is_finite(float(b.y)): hint = "Ground contact required"
	elif absf(float(tank.y)-(float(b.y)+1.05))>0.65: hint = "Move onto base ground"
	# Missing occupancy is unknown, not an invented zero. Counts include eligible teammates.
	var counts := "Team count unavailable"
	if b.has("blue") and b.has("red"): counts = "Blue %d / Red %d" % [int(b.blue),int(b.red)]
	return "%s %s: %s\n%s - %s" % [str(b.get("id","")),str(b.get("name","Base")),action,counts,hint]
