extends SceneTree
## The newer gameplay features: aiming towers with the mouse, marking pests,
## card rerolls, rare capstone cards, the Bloom Pot / Sap Pitcher / Gust
## Blossom, the Thornback Toad mini-boss, Garden Rules, acorn gifts, and the
## Practice Garden + Garden Guide screens.
## Run: godot --headless --path . -s tests/test_features.gd

var fails := 0
var D


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	run.call_deferred()


func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame


## A fresh game with me (id 1) and a friend (id 2), wave not started yet
func new_sim(mutators := {}) -> SimWorld:
	var sim := SimWorld.new(D)
	sim.mutators = mutators
	sim.add_player(1, "Me", "peashooter")
	sim.add_player(2, "Pal", "frostlotus")
	sim.start("meadow", "normal", "adventure")
	return sim


## Put a pest at a spot along trail 0 (fraction of the way along it)
func pest_at(sim: SimWorld, type: String, frac: float) -> Dictionary:
	var pts: PackedVector2Array = sim._paths[0]
	var seg := int(frac * (pts.size() - 1))
	sim.spawn_enemy(type, 0, seg, 0.5)
	var e: Dictionary = sim.enemies[-1]
	var a := pts[seg]
	var b := pts[mini(seg + 1, pts.size() - 1)]
	e.x = lerpf(a.x, b.x, 0.5)
	e.y = lerpf(a.y, b.y, 0.5)
	e.progress = seg + 0.5
	e.sheltered = false  # spawned at the burrow, but it's out on the trail now
	return e


## A walkable spot next to the trail, for towers
func beside_trail(sim: SimWorld, frac: float) -> Vector2:
	var pts: PackedVector2Array = sim._paths[0]
	var seg := int(frac * (pts.size() - 1))
	var p := pts[seg].lerp(pts[seg + 1], 0.5)
	var dirv := (pts[seg + 1] - pts[seg]).normalized().orthogonal()
	for k in [80.0, -80.0, 110.0, -110.0]:
		var c: Vector2 = p + dirv * k
		if D.is_walkable(sim.map_id, c.x, c.y) and D.gadget_spot(sim.map_id, "sentry", c.x, c.y).ok:
			return c
	return p + dirv * 80.0


func run() -> void:
	D = load("res://autoload/game_data.gd").new()
	aiming()
	marks()
	cards()
	new_towers()
	toad()
	rules()
	gifts()
	await screens()
	D.free()
	print("feature tests: %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)


func aiming() -> void:
	print("Aiming towers with the mouse")
	var sim := new_sim()
	var h: Dictionary = sim.hero_of(1)
	var spot := beside_trail(sim, 0.5)
	h.x = spot.x
	h.y = spot.y
	sim.players[1].acorns = 1000
	var aim := spot + Vector2(140, 0)
	if not D.gadget_spot(sim.map_id, "sentry", aim.x, aim.y).ok:
		aim = spot + Vector2(-140, 0)
	sim.plant(1, "sentry", aim)
	var g = sim.gadgets[-1] if not sim.gadgets.is_empty() else null
	check(g != null and Vector2(g.x, g.y).distance_to(aim) < 70 and Vector2(g.x, g.y).distance_to(spot) > 80, "a tower goes where the mouse points, not at my feet")
	sim.plant(1, "fern", spot + Vector2(0, 900))
	var g2 = sim.gadgets[-1]
	check(g2 != g and Vector2(g2.x, g2.y).distance_to(spot) <= SimWorld.AIM_REACH + 60, "aiming far away is pulled back to within reach of my hero")


func marks() -> void:
	print("Right-click marks a pest for everyone")
	var sim := new_sim()
	sim.wave_active = true
	var front := pest_at(sim, "sprout", 0.5)
	var back := pest_at(sim, "beetle", 0.5)
	back.progress -= 0.3
	back.x += 50
	var h: Dictionary = sim.hero_of(1)
	h.x = front.x + 25
	h.y = front.y + 30
	var st := sim.hero_stats(h)
	var aura := {"speed": 0.0, "damage": 0.0, "pierce": 0, "reveal": false}
	check(sim.pick_target(h, st, aura) == front, "normally the hero shoots the pest in front")
	sim.mark(1, back.x, back.y)
	check(back.get("mark_t", 0.0) > 0 and sim.pick_target(h, st, aura) == back, "a marked pest is shot first")
	check(sim.snapshot().enemies.any(func(e): return e.id == back.id and e.get("marked", false)), "everyone sees the mark")
	check(sim.events.any(func(e): return e.type == "mark"), "a mark event goes out")
	for i in 30 * 7:
		sim.update_marks(SimWorld.TICK)
	check(sim.marked.is_empty() and sim.pick_target(h, st, aura) == front, "the mark wears off after a few seconds")


func cards() -> void:
	print("Card rerolls and rare capstone cards")
	var sim := new_sim()
	var h: Dictionary = sim.hero_of(1)
	h.offer = []
	h.pending = 2
	sim.ensure_offer(h)
	var before: Array = h.offer.map(func(c): return c.get("id", c.get("path", "")))
	check(int(h.rerolls) == 1, "every hero starts with one free reroll")
	sim.players[1].acorns = 100
	sim.reroll(1)
	var after: Array = h.offer.map(func(c): return c.get("id", c.get("path", "")))
	check(int(h.rerolls) == 0 and int(sim.players[1].acorns) == 100 and before != after, "the free reroll swaps the cards (%s -> %s)" % [before, after])
	sim.reroll(1)
	check(int(sim.players[1].acorns) == 100 - D.REROLL_COST, "the next one costs %d acorns" % D.REROLL_COST)
	sim.players[1].acorns = 5
	var offer_before: Array = h.offer.duplicate()
	sim.reroll(1)
	check(h.offer == offer_before, "no acorns, no reroll")
	# capstones only from level 12
	var caps := 0
	h.level = 5
	for i in 60:
		h.offer = []
		sim.ensure_offer(h)
		caps += h.offer.filter(func(c): return D.CAPSTONES.has(String(c.get("id", "")))).size()
	check(caps == 0, "no rare cards before level 12")
	h.level = 14
	for i in 60:
		h.offer = []
		sim.ensure_offer(h)
		caps += h.offer.filter(func(c): return D.CAPSTONES.has(String(c.get("id", "")))).size()
	check(caps > 10, "rare cards show up from level 12 (%d in 60 hands)" % caps)
	# Catalyst Mastery: reactions hit 30% harder
	var e := pest_at(sim, "sprout", 0.5)
	e.chill_t = 2.0
	var plain := sim.reaction_mult(e, "blast", 10, 1, h.id, {})
	e.chill_t = 2.0
	h.cards["catalyst"] = 1
	var boosted := sim.reaction_mult(e, "blast", 10, 1, h.id, {})
	check(is_equal_approx(boosted / plain, 1.3), "Catalyst Mastery: Shatter x%.2f -> x%.2f" % [plain, boosted])
	# Acorn Magnet: 50% more acorns from pops
	sim.players[1].acorn_frac = 0.0
	sim.on_defeated(pest_at(sim, "sprout", 0.5), 1)
	var a0: float = float(sim.players[1].acorn_frac) + float(sim.players[1].acorns)
	h.cards["acornmagnet"] = 1
	sim.players[1].acorn_frac = 0.0
	sim.players[1].acorns = 5
	sim.on_defeated(pest_at(sim, "sprout", 0.5), 1)
	check(float(sim.players[1].acorn_frac) + float(sim.players[1].acorns) - 5 > (a0 - 5) * 1.4, "Acorn Magnet: more acorns per pop")
	# Echo Shot: some hits jump to a second pest
	h.cards["echo"] = 1
	sim.events.clear()
	var e1 := pest_at(sim, "ironpod", 0.5)
	var e2 := pest_at(sim, "ironpod", 0.5)
	e2.x += 40
	for i in 200:
		e1.hp = 5000
		e2.hp = 5000
		sim.apply_damage(e1, 5, 1, h.id, {})
	var echoes := sim.events.filter(func(ev): return ev.type == "echo").size()
	check(echoes > 10 and echoes < 60, "Echo Shot: about 15%% of hits echo (%d of 200)" % echoes)


func new_towers() -> void:
	print("Bloom Pot, Sap Pitcher, Gust Blossom")
	var sim := new_sim()
	sim.wave_active = true
	var spot := beside_trail(sim, 0.5)
	var h: Dictionary = sim.hero_of(1)
	h.x = spot.x
	h.y = spot.y
	sim.players[1].acorns = 2000
	sim.plant(1, "pot")
	var pot = sim.gadgets[-1] if not sim.gadgets.is_empty() else null
	check(pot != null and pot.kind == "pot", "a Bloom Pot can be built")
	var acorns := int(sim.players[1].acorns)
	var suns := sim.suns.size()
	h.x = spot.x + 400  # walk away so I don't grab the Sun
	for i in 30 * 7:
		sim.update_gadgets(SimWorld.TICK)
	check(int(sim.players[1].acorns) > acorns and sim.suns.size() > suns, "during a wave it grows acorns (+%d) and a Sun orb" % (int(sim.players[1].acorns) - acorns))
	# a sentry next to the pot fires faster
	var shots_near := 0
	var shots_far := 0
	for near in [true, false]:
		var s2 := new_sim()
		s2.wave_active = true
		var sp2 := beside_trail(s2, 0.5)
		s2.players[1].acorns = 2000
		var h2: Dictionary = s2.hero_of(1)
		h2.x = sp2.x
		h2.y = sp2.y
		s2.plant(1, "sentry")
		var sentry: Dictionary = s2.gadgets[-1]
		if near:
			s2.gadgets.append({"id": 999, "kind": "pot", "owner": 2, "slot": 1, "x": sentry.x + 30, "y": sentry.y, "level": 1, "branch": -1, "spent": 75, "cd": 99.0, "angle": 0.0, "sleep_t": 0.0, "wake_t": 0.0, "pulses": 0})
		h2.x = -999
		var n := 0
		for i in 30 * 10:
			if s2.enemies.is_empty() or s2.enemies[0].hp <= 0:
				s2.enemies.clear()
				var e := pest_at(s2, "ironpod", 0.5)
				e.x = sentry.x + 60
				e.y = sentry.y
				e.hp = 99999.0
				e.speed = 0.0
			s2.events.clear()
			s2.update_gadgets(SimWorld.TICK)
			n += s2.events.filter(func(ev): return ev.type == "shot").size()
		if near:
			shots_near = n
		else:
			shots_far = n
	check(shots_near > shots_far, "towers next to a Bloom Pot fire faster (%d vs %d shots)" % [shots_near, shots_far])
	# Sap Pitcher
	var s3 := new_sim()
	s3.wave_active = true
	var e3 := pest_at(s3, "camopuff", 0.5)
	s3.gadgets.append({"id": 998, "kind": "sap", "owner": 1, "slot": 0, "x": e3.x, "y": e3.y, "level": 1, "branch": -1, "spent": 55, "cd": 0.0, "angle": 0.0, "sleep_t": 0.0, "wake_t": 0.0, "pulses": 0})
	s3.update_gadgets(SimWorld.TICK)
	check(not e3.camo and float(e3.sap_until) > s3.game_time and e3.slow > 0.2, "sap washes off Camo and slows")
	e3.hp = 1000.0
	s3.apply_damage(e3, 100, 1, -1, {"element": "fire", "noReact": true})
	var fire_hit: float = 1000.0 - e3.hp
	e3.hp = 1000.0
	s3.apply_damage(e3, 100, 1, -1, {"element": "leaf", "noReact": true})
	var leaf_hit: float = 1000.0 - e3.hp
	check(fire_hit > leaf_hit * 1.15, "sapped pests take more fire damage (%d vs %d)" % [fire_hit, leaf_hit])
	# Gust Blossom
	var s4 := new_sim()
	s4.wave_active = true
	var e4 := pest_at(s4, "beetle", 0.5)
	var p0: float = e4.progress
	s4.gadgets.append({"id": 997, "kind": "gust", "owner": 1, "slot": 0, "x": e4.x + 50, "y": e4.y, "level": 1, "branch": 1, "spent": 95, "cd": 0.0, "angle": 0.0, "sleep_t": 0.0, "wake_t": 0.0, "pulses": 0})
	s4.update_gadgets(SimWorld.TICK)
	check(e4.progress < p0 and e4.stun_t > 0, "a Dizzy Gust blows pests back and stuns them")


func toad() -> void:
	print("Thornback Toad, the wave 13 mini-boss")
	var sim := new_sim()
	sim.wave = 12
	sim.start_next_wave()
	check(sim.spawn_queue.any(func(q): return q.type == "thorntoad"), "wave 13 brings a Thornback Toad")
	var sim2 := new_sim()
	sim2.wave = 14
	sim2.start_next_wave()
	check(not sim2.spawn_queue.any(func(q): return q.type == "thorntoad"), "other waves don't")
	sim.spawn_queue.clear()
	var tt := pest_at(sim, "thorntoad", 0.5)
	var buddy := pest_at(sim, "sprout", 0.5)
	buddy.x += 30
	sim.gadgets.append({"id": 996, "kind": "sentry", "owner": 1, "slot": 0, "x": tt.x + 60, "y": tt.y, "level": 1, "branch": -1, "spent": 60, "cd": 0.0, "angle": 0.0, "sleep_t": 0.0, "wake_t": 0.0, "pulses": 0})
	for h in sim.heroes:
		h.x = -900
	tt.abil_t = 0.01
	sim.enemy_powers(tt, SimWorld.TICK)
	check(sim.gadgets[-1].sleep_t > 0, "its stomp puts nearby towers to sleep")
	buddy.hp = 1000.0
	sim.apply_damage(buddy, 100, 1, -1, {"noReact": true})
	check(absf((1000.0 - buddy.hp) - 60.0) < 1.5, "pests next to it take 40%% less damage (%d)" % (1000.0 - buddy.hp))
	check(D.ENEMIES.thorntoad.boss and sim.snapshot().enemies.any(func(e): return e.type == "thorntoad" and e.boss), "it's a boss (health bar, chest)")


func rules() -> void:
	print("Garden Rules")
	var plain := new_sim()
	var turbo := new_sim({"turbo": true})
	check(is_equal_approx(turbo.hero_stats(turbo.hero_of(1)).moveSpeed, plain.hero_stats(plain.hero_of(1)).moveSpeed * 1.4), "Turbo Garden: heroes walk 40% faster")
	turbo.add_projectile({"kind": "pea", "x": 0.0, "y": 0.0, "vx": 100.0, "vy": 0.0})
	check(is_equal_approx(float(turbo.projectiles[-1].vx), 140.0), "Turbo Garden: shots fly 40% faster")
	var hm := new_sim({"heroes": true})
	var h: Dictionary = hm.hero_of(1)
	var spot := beside_trail(hm, 0.5)
	h.x = spot.x
	h.y = spot.y
	hm.players[1].acorns = 1000
	hm.plant(1, "sentry")
	check(hm.gadgets.is_empty() and hm.events.any(func(e): return e.type == "gadget_fail"), "Hero Mode: no towers")
	check(is_equal_approx(hm.hero_stats(h).xpMult, plain.hero_stats(plain.hero_of(1)).xpMult * 1.6), "Hero Mode: 60% more XP")
	var tw := new_sim({"twists": true})
	check(tw.plan_twist(3) != "" and plain.plan_twist(3) == "", "Oops! All Twists: twists from wave 3 (%s)" % tw.plan_twist(3))
	var ch := new_sim({"chaos": true})
	var e := pest_at(ch, "sprout", 0.5)
	e.chill_t = 2.0
	var e2 := pest_at(plain, "sprout", 0.5)
	e2.chill_t = 2.0
	check(is_equal_approx(ch.reaction_mult(e, "blast", 10, 1, -1, {}) / plain.reaction_mult(e2, "blast", 10, 1, -1, {}), 1.5), "Reaction Chaos: reactions 50% stronger")


func gifts() -> void:
	print("Gift acorns")
	var sim := new_sim()
	sim.players[1].acorns = 60
	sim.players[2].acorns = 10
	sim.gift(1, 2)
	check(int(sim.players[1].acorns) == 35 and int(sim.players[2].acorns) == 35, "25 acorns go to the friend")
	sim.players[1].acorns = 10
	sim.gift(1, 2)
	check(int(sim.players[1].acorns) == 10, "not without enough acorns")


func screens() -> void:
	print("Practice Garden and Garden Guide")
	var Prof = load("res://ui/profile.gd")
	Prof.path = "user://test_profile.cfg"
	var cf := ConfigFile.new()
	cf.save(Prof.path)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await secs(0.3)
	main.start_practice(Prof.load_profile())
	await secs(0.3)
	check(main.practicing and main.host.sim.practice and main.host.sim.max_wave == 3 and main.host.sim.players[1].acorns >= 300, "Practice Garden: a short, easy game with acorns to try things")
	check(String(main.hud.practice.get("text", "")).contains("Walk"), "step 1 is shown: %s" % main.hud.practice.get("text", ""))
	check(not main.host.sim.suns.is_empty(), "there is a Sun orb to grab")
	main._practice_step("walk")
	main._my_event({"type": "dash", "owner": main.my_id, "x": 500.0, "y": 500.0})
	check(int(main.hud.practice.get("step", 0)) == 3 and String(main.hud.practice.text).contains("Sun"), "steps tick off as you do them (now: %s)" % main.hud.practice.get("text", ""))
	var met: Array = Prof.load_profile().get("guideSeen", [])
	main.host.sim.spawn_enemy("wasp", 0)
	await secs(0.3)
	check(Prof.load_profile().get("guideSeen", []).has("wasp") and not met.has("wasp"), "meeting a pest adds its Garden Guide page")
	main.show_menu()
	await secs(0.2)
	for tab in ["heroes", "towers", "reactions", "pests"]:
		main.menu.show_guide(tab)
		await secs(0.1)
	var labels: Array = main.menu.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	check(labels.any(func(t): return t == "Zoom Wasp") and labels.any(func(t): return t == "❓ ???"), "the pest book shows met pests and hides the rest")
	main.menu.show_rules()
	await secs(0.1)
	main.menu.show_title()
	await secs(0.1)
	var btns: Array = main.menu.find_children("*", "Button", true, false).map(func(b): return String(b.text))
	check(btns.any(func(t): return t.begins_with("🎲 Garden Rules")) and btns.any(func(t): return t.contains("Practice")) and btns.has("📖"), "the title screen has Garden Rules, Practice and the Guide")
	main.queue_free()
	await secs(0.3)
