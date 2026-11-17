extends SceneTree
## Headless check: the Godot rules give the same numbers as the original JS game.
## Run: godot --headless --path . -s tests/test_data.gd

var fails := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
		print("FAIL ", label)

func near(a, b) -> bool:
	return absf(float(a) - float(b)) < 0.001

func _init() -> void:
	var D = load("res://autoload/game_data.gd").new()
	# hero stats vs the exported samples
	var n := 0
	for type in D.HERO_ORDER:
		var table: Dictionary = D.heroes.computedStats[type]
		for key in table:
			var want: Dictionary = table[key]
			var got: Dictionary
			if key.begins_with("L11_A4B2"):
				got = D.compute_hero_stats(type, 4, 2, {}, 11)
			elif key.begins_with("L11_A2B4"):
				got = D.compute_hero_stats(type, 2, 4, {}, 11)
			else:
				got = D.compute_hero_stats(type, 0, 0, {}, int(key.substr(1, key.find("_") - 1)))
			for stat in want:
				var w = want[stat]
				var g = got.get(stat)
				if w is float or w is int:
					check("%s %s %s: want %s got %s" % [type, key, stat, w, g], g != null and near(w, g))
				elif w is bool:
					check("%s %s %s bool" % [type, key, stat], g == w)
				n += 1
	# XP curve
	for row in D.heroes.xpCurve:
		check("xp L%d" % row.level, near(D.xp_to_next(int(row.level)), row.xpToNext))
	# waves 1..60: groups + elite resistances
	for row in D.waves.waves:
		var w := int(row.wave)
		var spec: Array = D.wave_spec(w)
		check("wave %d group count" % w, spec.size() == row.spec.size())
		for i in mini(spec.size(), row.spec.size()):
			check("wave %d group %d" % [w, i], spec[i].type == row.spec[i].type and int(spec[i].count) == int(row.spec[i].count) and near(spec[i].interval, row.spec[i].interval) and near(spec[i].delay, row.spec[i].delay))
			var want_res = row.resists[i]
			check("wave %d resist %d: want %s got %s" % [w, i, want_res, D.group_resist(w, i, spec[i].type)], (want_res == null and D.group_resist(w, i, spec[i].type) == "") or D.group_resist(w, i, spec[i].type) == want_res)
		var plan: Dictionary = D.plan_wave(w, D.DIFFICULTIES.normal, 1, false, "")
		var wplan: Dictionary = row.plan1HeroNormal
		check("wave %d plan hpBoost" % w, near(plan.hpBoost, wplan.hpBoost))
		for i in plan.groups.size():
			check("wave %d plan count %d" % [w, i], int(plan.groups[i].count) == int(wplan.groups[i].count))
	# pathfinding sanity on every map
	for id in D.maps.maps:
		var sc: Vector2 = D.sanctuary(id)
		var route: Array = D.find_path(id, 300, 300, sc.x - 120, sc.y)
		check("path on %s" % id, route.size() > 0)
	print("checked %d hero stats, %d xp levels, %d waves; failures: %d" % [n, D.heroes.xpCurve.size(), D.waves.waves.size(), fails])
	D.free()  # no leaked objects at exit
	quit(1 if fails > 0 else 0)
