extends RefCounted
# Accepted snapshot values only. No guessed role stats while joining or after
# disconnect. Normal rooms have the original fixed four-second cannon cycle.
const IDS := ["prototype","flanker","generalist","anchor"]

static func label(id: String) -> String:
	return "Standard" if id=="prototype" else id.capitalize()

static func number(v: Variant) -> bool:
	return (typeof(v)==TYPE_FLOAT or typeof(v)==TYPE_INT) and is_finite(float(v)) and v>0

static func catalog(state: Dictionary) -> Dictionary:
	if state.get("roleProtocol")!=1: return {}
	var rows: Variant = state.get("roleCatalog")
	if not rows is Array or rows.size()!=IDS.size(): return {}
	var result := {}
	for r in rows:
		if not r is Dictionary: return {}
		var id: Variant = r.get("id")
		if id not in IDS or result.has(id): return {}
		if not number(r.get("forwardMps")) or not number(r.get("reloadSeconds")): return {}
		if r.get("health")!=3 or r.get("damage")!=1: return {}
		result[id]=r
	return result

static func duration(state: Dictionary, own: Dictionary) -> float:
	if not state.has("roleProtocol"):
		return -1.0 if state.has("roleCatalog") or own.has("roleId") else 4.0
	var entries:=catalog(state)
	var r: Dictionary = entries.get(own.get("roleId"),{})
	return float(r.get("reloadSeconds",-1.0))

static func option(id: String, r: Dictionary) -> String:
	if r.is_empty(): return label(id)
	return "%s   ·   %.1f m/s drive   ·   %.1f s reload" % [label(id),r.forwardMps,r.reloadSeconds]

static func tradeoff(id: String, entries: Dictionary) -> String:
	if id not in entries: return "Trial stats unavailable."
	var role: Dictionary=entries[id]
	var standard: Dictionary=entries.prototype
	var comparison: String
	if role.forwardMps>standard.forwardMps and role.reloadSeconds>standard.reloadSeconds:
		comparison="Faster drive, slower reload."
	elif role.forwardMps<standard.forwardMps and role.reloadSeconds<standard.reloadSeconds:
		comparison="Slower drive, faster reload."
	elif role.forwardMps==standard.forwardMps and role.reloadSeconds==standard.reloadSeconds:
		comparison="Standard drive and reload."
	else: comparison="Shorter reload means you can fire sooner."
	return "%s   All roles: %d HP · %d damage." % [comparison,int(role.health),int(role.damage)]
