class_name MapFeatures
extends RefCounted
## One light, friendly gimmick per Adventure map, placed next to (or on) the trails:
##   Sunny Meadow       Sunflower Patch: walk past during a wave, it blooms a bonus Sun
##   Lilypad Crossing   Lily Pad: step on it for a short speed boost
##   Starlight Crossr.  Starlight Obelisk: charges as pests pop nearby; stand on it when full to blast
##   Maple Hollow       Leaf Pile (on a trail): walk through it to slow the pests around it
##   Frosty Glade       Frost Geyser: erupts by itself, chilling nearby pests (sets up Shatter & Melt)

const PLAN := {
	"meadow": {"kind": "sunflower", "spots": [[0, 0.35, 80], [1, 0.55, 80]]},
	"river": {"kind": "lilypad", "spots": [[0, 0.3, 80], [0, 0.65, 80]]},
	"courtyard": {"kind": "obelisk", "spots": [[0, 0.82, 95]]},
	"hollow": {"kind": "leafpile", "spots": [[0, 0.5, 0], [1, 0.45, 0], [2, 0.5, 0]]},
	"frosty": {"kind": "geyser", "spots": [[0, 0.45, 75], [1, 0.6, 75]]},
}
const COOLDOWN := {"sunflower": 22.0, "lilypad": 18.0, "leafpile": 12.0, "geyser": 14.0}
const OBELISK_FULL := 40.0

var list: Array = []  # {kind, x, y, cd, charge}


func place(sim) -> void:
	list.clear()
	var plan: Dictionary = PLAN.get(sim.map_id, {})
	if plan.is_empty():
		return
	for s in plan.spots:
		var path_i: int = s[0]
		if path_i >= sim._paths.size():
			continue
		var at := _spot(sim, sim._paths[path_i], float(s[1]), float(s[2]))
		if at != Vector2.INF:
			list.append({"kind": plan.kind, "x": at.x, "y": at.y, "cd": 3.0 if plan.kind != "obelisk" else 0.0, "charge": 0.0})


## A point `frac` of the way along a trail, `side` pixels off to one side
## (somewhere a hero can walk and not on the trail); side 0 = on the trail
func _spot(sim, pts: PackedVector2Array, frac: float, side: float) -> Vector2:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	for tries in 7:
		var f := clampf(frac + (tries - 3) * 0.04 * (1 if tries % 2 else -1), 0.05, 0.95)
		var want := total * f
		var p := pts[0]
		var d := Vector2.RIGHT
		for i in pts.size() - 1:
			var L := pts[i].distance_to(pts[i + 1])
			if want <= L:
				d = (pts[i + 1] - pts[i]).normalized()
				p = pts[i] + d * want
				break
			want -= L
		if side <= 0:
			return p
		for sgn in [1.0, -1.0]:
			var c: Vector2 = p + d.orthogonal() * side * sgn
			var tile := Vector2i(int(c.x / sim.D.TILE), int(c.y / sim.D.TILE))
			if sim.D.is_walkable(sim.map_id, c.x, c.y) and not sim.D.is_path_tile(sim.map_id, tile.x, tile.y) and not sim.D.in_brambles(sim.map_id, c.x, c.y, 20):
				return c
	return Vector2.INF


func update(sim, dt: float) -> void:
	for f in list:
		if f.cd > 0:
			f.cd -= dt
		match String(f.kind):
			"sunflower":
				if f.cd <= 0 and sim.wave_active and _hero_near(sim, f, 55) != null:
					f.cd = COOLDOWN.sunflower
					sim.add_sun(f.x, f.y - 30, 30 + sim.wave, -1, 0.5, false, true)
					sim.ev({"type": "feature", "kind": "sunflower", "x": f.x, "y": f.y})
			"lilypad":
				var h = _hero_near(sim, f, 45) if f.cd <= 0 else null
				if h:
					f.cd = COOLDOWN.lilypad
					h.buffs.zoom = maxf(float(h.buffs.get("zoom", 0.0)), 4.0)
					h._st = null
					sim.ev({"type": "feature", "kind": "lilypad", "x": f.x, "y": f.y, "owner": h.owner})
			"obelisk":
				if f.charge >= OBELISK_FULL and _hero_near(sim, f, 60) != null:
					f.charge = 0.0
					var dmg: float = 60.0 + sim.wave * 18.0
					for e in sim.enemies:
						if e.hp > 0 and not e.sheltered and sim.dist(f.x, f.y, e.x, e.y) <= 420:
							sim.apply_damage(e, round(dmg * (0.5 if e.boss else 1.0)), -1, -1, {"armorPierce": true, "noReact": true})
							sim.try_stun(e, 1.0)
					sim.ev({"type": "feature", "kind": "obelisk", "x": f.x, "y": f.y, "r": 420})
			"leafpile":
				if f.cd <= 0 and _hero_near(sim, f, 50) != null:
					f.cd = COOLDOWN.leafpile
					for e in sim.enemies:
						if e.hp > 0 and sim.dist(f.x, f.y, e.x, e.y) <= 150:
							e.slow = maxf(e.slow, 0.5)
							e.slow_t = maxf(e.slow_t, 3.0)
					sim.ev({"type": "feature", "kind": "leafpile", "x": f.x, "y": f.y, "r": 150})
			"geyser":
				if f.cd <= 0 and sim.wave_active:
					f.cd = COOLDOWN.geyser
					for e in sim.enemies:
						if e.hp > 0 and e.resist != "ice" and sim.dist(f.x, f.y, e.x, e.y) <= 150:
							e.chill_t = maxf(e.chill_t, 3.0)
							e.slow = maxf(e.slow, 0.3)
							e.slow_t = maxf(e.slow_t, 3.0)
					sim.ev({"type": "feature", "kind": "geyser", "x": f.x, "y": f.y, "r": 150})


## The obelisk charges when pests pop near it
func on_pop(sim, e: Dictionary) -> void:
	for f in list:
		if f.kind == "obelisk" and f.charge < OBELISK_FULL and sim.dist(f.x, f.y, e.x, e.y) <= 450:
			f.charge = minf(OBELISK_FULL, f.charge + (4.0 if e.boss else 1.0))


func _hero_near(sim, f: Dictionary, r: float):
	for h in sim.heroes:
		if not h.get("dead", false) and sim.dist(h.x, h.y, f.x, f.y) <= r:
			return h
	return null


func snapshot() -> Array:
	var out: Array = []
	for f in list:
		var ready: float
		if f.kind == "obelisk":
			ready = f.charge / OBELISK_FULL
		else:
			ready = 1.0 - clampf(f.cd / COOLDOWN.get(f.kind, 10.0), 0, 1)
		out.append({"kind": f.kind, "x": roundf(f.x), "y": roundf(f.y), "ready": snappedf(ready, 0.01)})
	return out
