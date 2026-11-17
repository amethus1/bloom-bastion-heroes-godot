extends SceneTree
## Headless: rule fixes that should never come back.
##  - 2x game speed does exactly the same damage-over-time per game-second as 1x
##  - Frostbite and burning are separate (one never replaces the other)
##  - Snapdragon wisps use the hero's current stats
##  - targeting modes can be changed
## godot --headless --path . -s tests/test_rules.gd

var fails := 0
var D


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func burn_damage(speed: float) -> float:
	var sim := SimWorld.new(D)
	sim.add_player(1, "T", "peashooter", false)
	sim.start("meadow", "normal", "adventure")
	sim.heroes.clear()  # nobody shoots, just the burn
	sim.spawn_enemy("beetle", 0)
	var e: Dictionary = sim.enemies[0]
	e.hp = 1e6
	e.max_hp = 1e6
	e.burn_dps = 9.0
	e.burn_t = 999.0
	sim.speed_mult = speed
	var game_seconds := 0.0
	while game_seconds < 6.0:
		sim.step(SimWorld.TICK)
		game_seconds += SimWorld.TICK * speed
	return 1e6 - e.hp


func _init() -> void:
	D = load("res://autoload/game_data.gd").new()
	var one := burn_damage(1.0)
	var two := burn_damage(2.0)
	check(absf(one - two) < 3, "burn per game-second is the same at 1x and 2x speed (%d vs %d)" % [one, two])

	var sim := SimWorld.new(D)
	sim.add_player(1, "T", "frostlotus", false)
	sim.start("meadow", "normal", "adventure")
	sim.spawn_enemy("beetle", 0)
	var e: Dictionary = sim.enemies[0]
	e.burn_dps = 20.0
	e.burn_t = 3.0
	e.burn_tower = 999
	sim.apply_frost(e, {"slowAmount": 0.3, "slowDuration": 2.0, "frostDot": 12.0}, 0, 1, sim.heroes[0].id)
	check(e.burn_dps == 20.0 and e.burn_tower == 999, "frostbite doesn't overwrite a burn")
	check(e.frost_t > 0 and e.frost_dps == 12.0, "frostbite has its own timer")
	var snap := sim.snapshot()
	check(snap.enemies[0].frostbit and snap.enemies[0].burning, "the snapshot shows both")

	var sim2 := SimWorld.new(D)
	sim2.add_player(1, "T", "snapdragon", false)
	sim2.start("meadow", "normal", "adventure")
	var h: Dictionary = sim2.heroes[0]
	h.tierB = 3
	h._st = null
	sim2.sync_wisps(h)
	if sim2.wisps.size() > 0:
		var before: float = sim2.wisps[0].damage
		sim2.grant_xp(1, 5000)
		sim2.step(SimWorld.TICK)
		check(sim2.wisps[0].damage > before, "wisps get stronger when the hero levels up (%d -> %d)" % [before, sim2.wisps[0].damage])
	else:
		check(D.gnum(sim2.hero_stats(h), "wispCount") == 0, "(no wisps at this tier)")
	sim2.set_target_mode(1, "strong")
	check(sim2.heroes[0].target_mode == "strong", "targeting mode can be changed")
	sim2.set_target_mode(1, "nonsense")
	check(sim2.heroes[0].target_mode == "strong", "unknown targeting modes are ignored")
	# every named team combo fires and does its thing
	for key in SimWorld.NAMED_COMBOS:
		var pair: PackedStringArray = String(key).split("+")
		var cs := SimWorld.new(D)
		cs.add_player(1, "A", pair[0], false)
		cs.add_player(2, "B", pair[1], false)
		cs.start("meadow", "easy", "adventure")
		cs.spawn_enemy("beetle", 0)
		var a: Dictionary = cs.heroes[0]
		var b: Dictionary = cs.heroes[1]
		var pest: Dictionary = cs.enemies[0]
		pest.hp = 1e6
		pest.max_hp = 1e6
		pest.sheltered = false
		a.x = pest.x
		a.y = pest.y
		b.x = pest.x + 40
		b.y = pest.y
		a.special_cd = 0.0
		b.special_cd = 0.0
		cs.events.clear()
		cs.use_special(1)
		cs.use_special(2)
		var got := ""
		for ev in cs.events:
			if ev.type == "combo":
				got = String(ev.get("id", ""))
		check(got == SimWorld.NAMED_COMBOS[key][0], "%s combo: %s" % [key, SimWorld.NAMED_COMBOS[key][1]])
	# every Adventure map has its gimmick, somewhere you can walk, and it works
	for map_id in MapFeatures.PLAN:
		var ms := SimWorld.new(D)
		ms.add_player(1, "A", "peashooter", false)
		ms.start(map_id, "easy", "adventure")
		var fl: Array = ms.features.list
		var walk_ok := fl.size() > 0
		for f in fl:
			if not D.is_walkable(map_id, f.x, f.y):
				walk_ok = false
		check(walk_ok, "%s: %d %s placed where heroes can walk" % [map_id, fl.size(), MapFeatures.PLAN[map_id].kind])
		var f0: Dictionary = fl[0]
		var hh: Dictionary = ms.heroes[0]
		ms.start_next_wave()
		f0.cd = 0.0
		f0.charge = MapFeatures.OBELISK_FULL
		hh.x = f0.x
		hh.y = f0.y
		ms.events.clear()
		ms.step(SimWorld.TICK)
		var fired := false
		for ev in ms.events:
			if ev.type == "feature":
				fired = true
		check(fired, "%s: the %s does its thing" % [map_id, f0.kind])
	# perfect waves: a growing bonus; Kid assist regrows the tree
	var pw := SimWorld.new(D)
	pw.add_player(1, "A", "peashooter", false)
	pw.start("meadow", "easy", "adventure")
	pw.kid_assist = true
	pw.lives -= 5
	for wv in 2:
		pw.start_next_wave()
		pw.spawn_queue.clear()
		pw.enemies.clear()
		pw.events.clear()
		pw.step(SimWorld.TICK)
	var clear_ev := {}
	for ev in pw.events:
		if ev.type == "wave_clear":
			clear_ev = ev
	check(int(clear_ev.get("perfect", 0)) == 2, "two clean waves in a row = perfect streak x2")
	check(pw.lives == pw.max_lives - 1 and int(clear_ev.get("regrow", 0)) == 2, "Kid assist: the tree regrows 2 lives a wave")
	# Endless acorn shop
	var es := SimWorld.new(D)
	es.add_player(1, "A", "peashooter", false)
	es.start("meadow", "normal", "endless")
	es.wave = 6
	es.players[1].acorns = 1000
	es.lives -= 3
	var lv0 := es.lives
	es.endless_shop(1, "life")
	es.endless_shop(1, "life")
	check(es.lives == lv0 + 1, "Endless shop: +1 life, only once every 5 waves")
	es.endless_shop(1, "overclock")
	check(es.overclock_t >= 59.0, "Endless shop: overclock runs for a minute")
	var pu0 := es.powerups.size()
	es.endless_shop(1, "mystery")
	check(es.powerups.size() == pu0 + 1 and es.players[1].acorns == 1000 - 250 - 100 - 120, "Endless shop: mystery power-up, acorns spent right")
	# Leaf Leap perks
	var lp := SimWorld.new(D)
	lp.add_player(1, "A", "bubblelily", false)
	lp.start("meadow", "easy", "adventure")
	lp.spawn_enemy("beetle", 0)
	var pest2: Dictionary = lp.enemies[0]
	pest2.sheltered = false
	var hb: Dictionary = lp.heroes[0]
	hb.dash_cd = 0.0
	lp.leap_perk(hb, Vector2(pest2.x - 150, pest2.y), Vector2(pest2.x, pest2.y))
	check(pest2.soak_t > 0, "Bubble Lily's Leaf Leap splash soaks pests")
	print("test_rules: %d failure(s)" % fails)
	D.free()
	quit(1 if fails > 0 else 0)
