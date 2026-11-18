extends SceneTree
## The newer gameplay features: aiming towers with the mouse, marking pests,
## card rerolls, rare capstone cards, the Bloom Pot / Sap Pitcher / Gust
## Blossom, the Thornback Toad mini-boss, Garden Rules, acorn gifts, and the
## Practice Garden + Garden Guide screens, and the UI size / messages / chatter
## settings with the "Your towers" list.
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
	tower_shots()
	review_fixes()
	clash_living()
	clash_quick()
	await screens()
	await hud_settings()
	await clash_shop()
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


## Towers tell the screen each time they fire (it bounces the picture and flashes)
func tower_shots() -> void:
	print("Towers report their shots")
	var sim := new_sim()
	var spot := beside_trail(sim, 0.5)
	var h: Dictionary = sim.hero_of(1)
	h.x = spot.x
	h.y = spot.y
	sim.players[1].acorns = 1000
	sim.plant(1, "sentry")
	var g: Dictionary = sim.gadgets[-1]
	var before := int(sim.snapshot().gadgets[-1].get("shots", -1))
	pest_at(sim, "sprout", 0.5)
	for i in 30:
		sim.update_gadgets(SimWorld.TICK)
	var after := int(sim.snapshot().gadgets[-1].get("shots", -1))
	check(before == 0 and after > 0 and after < 8, "a tower's shot count goes up as it fires (%d -> %d)" % [before, after])
	g.shots = 15
	check(int(sim.snapshot().gadgets[-1].shots) == 7, "...and stays one small number in the snapshot (kept small for LAN games)")


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


## UI size, fewer messages, quieter chatter, and upgrading from the "Your towers" list
func hud_settings() -> void:
	print("UI size, messages, chatter and Your towers")
	var Prof = load("res://ui/profile.gd")
	Prof.path = "user://test_profile.cfg"
	var cf := ConfigFile.new()
	cf.set_value("profile", "dialogMode", "key")
	cf.save(Prof.path)
	check(String(Prof.load_profile().chatter) == "few", "the old 'key moments' chatter setting carries over as 'Big moments only'")
	cf = ConfigFile.new()
	cf.save(Prof.path)
	var p: Dictionary = Prof.load_profile()
	check(is_equal_approx(float(p.uiScale), 0.8) and p.msgs == "fewer" and p.chatter == "some", "new defaults: UI size 80%, fewer messages, some chatter")
	check(is_equal_approx(Prof.step_ui_scale(0.8, 1), 0.9) and is_equal_approx(Prof.step_ui_scale(1.3, 1), 1.3) and is_equal_approx(Prof.step_ui_scale(0.6, -1), 0.6), "UI size steps up and down and stops at the ends")
	var audio = root.get_node("/root/Audio")
	var was: String = audio.dialog_mode
	audio.dialog_mode = "few"
	check(audio.chatter_allows("boss_monarch") and not audio.chatter_allows("ann_wave"), "Big moments only: bosses still talk, the everyday wave line doesn't")
	audio.dialog_mode = "off"
	check(not audio.chatter_allows("boss_monarch"), "chatter off: nobody talks")
	audio.dialog_mode = "lots"
	check(audio.chatter_allows("ann_wave", true), "Lots: every line")
	audio.dialog_mode = was

	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await secs(0.3)
	main.start_local({"hero": "peashooter", "map": "meadow", "diff": "normal", "gameMode": "adventure", "bots": 0, "name": "Tester", "hat": "none", "pet": "none"})
	await secs(0.3)
	var hud = main.hud
	hud.msg_level = 1
	hud._toasts = []
	hud.toast("small news", Color.WHITE, 2.0, 2)
	hud.toast("you can't do that", Color.WHITE, 2.0, 0)
	hud.toast("you can't do that", Color.WHITE, 2.0, 0)
	check(hud._toasts.size() == 1 and int(hud._toasts[0].n) == 2, "Messages: Fewer hides small news, and a repeated message counts up instead of stacking")

	var sim = main.host.sim
	var me: int = main.my_id
	sim.players[me].acorns = 3000
	var h: Dictionary = sim.hero_of(me)
	for i in 24:
		if sim.gadgets.any(func(x): return x.owner == me):
			break
		sim.plant(me, "sentry", Vector2(h.x, h.y) + Vector2.from_angle(i * TAU / 12.0) * (70.0 + 50.0 * (i / 12)))
	var mine: Array = sim.gadgets.filter(func(x): return x.owner == me)
	check(not mine.is_empty(), "built a tower to try it on")
	if mine.is_empty():
		main.queue_free()
		await secs(0.2)
		return
	var g: Dictionary = mine[0]
	var put := func(at: Vector2) -> void:
		h.x = at.x
		h.y = at.y
		main.my_pos = at
		main.move_path = []
	var far := Vector2(D.W / 2.0, D.H / 2.0)
	if far.distance_to(Vector2(g.x, g.y)) < 300:
		far = Vector2(200, 200)
	put.call(far)
	await secs(0.2)
	check(hud._buttons.any(func(b): return b[1].get("t", "") == "tower_up" and int(b[1].get("id", -1)) == int(g.id)), "Your towers lists it, with an upgrade button")
	main.do_hud_action({"t": "tower_up", "id": int(g.id)})
	await secs(0.15)
	check(int(g.level) == 1 and hud._toasts.any(func(t): return String(t.text).contains("Walk next to")), "too far away: Upgrade says to walk over, and nothing changes")
	check(hud.selected_tower == int(g.id), "...and it opens that tower's details")
	main.host.apply(me, {"t": "upgrade", "id": int(g.id)})
	main.host.apply(me, {"t": "sell", "id": int(g.id)})
	check(int(g.level) == 1 and sim.gadgets.has(g), "the game itself refuses upgrading or selling from far away (LAN friends too)")
	main.do_hud_action({"t": "tower_go", "id": int(g.id)})
	check(main.move_path.size() > 0, "Go there walks my hero to it")
	put.call(Vector2(g.x + 30, g.y))
	await secs(0.15)
	main.do_hud_action({"t": "tower_up", "id": int(g.id)})
	await secs(0.15)
	check(int(g.level) == 2, "standing next to it, the upgrade button works")
	main.do_hud_action({"t": "tower_up", "id": int(g.id)})
	await secs(0.15)
	check(int(g.level) == 2, "at level 2 the button shows the two special powers instead of guessing one")
	main.do_hud_action({"t": "tower_up", "id": int(g.id), "branch": 1})
	await secs(0.15)
	check(int(g.level) == 3 and int(g.branch) == 1, "picking a special power upgrades it to level 3")
	check(main._my_tower_at(Vector2(g.x, g.y - 12)) == int(g.id) and main._my_tower_at(Vector2(g.x + 200, g.y)) == -1, "clicking the tower in the garden picks it")
	var out: Dictionary = main.world.build_outcome("sentry", Vector2(g.x, g.y))
	check(not out.up.is_empty() and String(out.text).contains("max level"), "build preview: a Sentry on top of my level-3 Sentry says it's maxed, not 'build here' (%s)" % out.text)
	var free_spot := Vector2(g.x, g.y)
	main.do_hud_action({"t": "tower_sell", "id": int(g.id)})
	await secs(0.15)
	check(not sim.gadgets.has(g), "Sell works when I'm next to it")
	var real_snap: Dictionary = main.world.snap
	var fake := real_snap.duplicate()
	fake.players = [{"id": me, "acorns": 999}]
	fake.gadgets = []
	for i in 5:
		fake.gadgets.append({"id": 900 + i, "owner": me, "kind": "fern", "x": 40.0 + i * 50, "y": 40.0, "level": 1, "branch": -1})
	main.world.snap = fake
	var lim: Dictionary = main.world.build_outcome("sentry", free_spot)
	fake.gadgets = []
	fake.players = [{"id": me, "acorns": 10}]
	var poor: Dictionary = main.world.build_outcome("sentry", free_spot)
	fake.players = [{"id": me, "acorns": 999}]
	var good: Dictionary = main.world.build_outcome("sentry", free_spot)
	main.world.snap = real_snap
	check(not lim.ok and String(lim.text).contains("limit"), "build preview: tower limit reached (%s)" % lim.text)
	check(not poor.ok and String(poor.text).contains("needs"), "build preview: not enough acorns (%s)" % poor.text)
	check(good.ok and String(good.text).begins_with("Build Sprout Sentry"), "build preview: Build Sprout Sentry · 60 (%s)" % good.text)

	# hiding the cards gives the number keys back to the build bar
	hud.auto_cards = false
	main.selected_gadget = "sentry"
	var hero0: Dictionary = sim.hero_of(me)
	while int(hero0.pending) == 0:
		sim.grant_xp(me, 10.0)
	await secs(0.2)
	hud.cards_hidden = true
	var pend0: int = int(hero0.pending)
	var k2 := InputEventKey.new()
	k2.physical_keycode = KEY_2
	k2.pressed = true
	main._unhandled_input(k2)
	await secs(0.15)
	check(int(hero0.pending) == pend0 and main.selected_gadget == D.GADGET_ORDER[1], "cards tucked away (C): 2 picks the second tower, not a hidden card")
	hud.cards_hidden = false
	hud.auto_cards = true
	check(main.wave_ready(), "between waves, Start on a controller starts the wave (the same check)")
	main.practicing = true
	var nc: Dictionary = main._next_cfg()
	main.practicing = false
	check(nc.get("map", "") == "meadow" and int(nc.get("bots", 0)) >= 1 and nc.get("gameMode", "") == "adventure", "after Practice, the next game is Sunny Meadow with a Bot Buddy")
	hud._feed = []
	hud.guide_pages(["Grub Sprout"])
	hud.guide_pages(["Zoom Wasp", "Shell Beetle"])
	check(hud._feed.size() == 1 and String(hud._feed[0].text).contains("3"), "new Garden Guide pages share one line that counts up (%s)" % hud._feed[0].text)
	var hs: Dictionary = hud.snap
	hud.snap = {"players": [{"id": 1, "name": "Ann", "pops": 120, "damage": 900, "sun": 40, "built": 3, "combos": 0},
		{"id": 2, "name": "Bo", "pops": 20, "damage": 100, "sun": 2, "built": 0, "combos": 2}]}
	var aw: Array = hud._awards()
	hud.snap = {"comboOpen": {"owner": 2, "hero": 77, "x": 500.0, "y": 500.0, "left": 2.2}, "heroes": [{"id": 77, "owner": 2, "type": "bubblelily", "slot": 1, "x": 500.0, "y": 500.0}],
		"players": [{"id": 2, "name": "Lily"}]}
	var was_at = hud.hero_at
	hud.hero_at = Vector2(700, 500)
	var inv: Dictionary = hud.combo_invite({"id": 5, "owner": me, "type": "voltcactus", "specialCd": 0.0, "x": 700.0, "y": 500.0})
	var busy: Dictionary = hud.combo_invite({"id": 5, "owner": me, "type": "voltcactus", "specialCd": 4.0, "x": 700.0, "y": 500.0})
	hud.hero_at = was_at
	hud.snap = hs
	check(aw.size() >= 2 and String(aw[0]).begins_with("🤝 Combo Buddy: Bo") and String(aw[1]).contains("Ann"), "end screen: Combo Buddy leads, and everyone gets an award before anyone gets two (%s)" % ", ".join(aw))
	check(inv.get("near", false) and String(inv.get("what", "")).contains("STORM SURGE") and busy.is_empty(), "combo invite: Lily just cast nearby, so my Volt Cactus is asked for STORM SURGE (only when my special is ready)")
	await secs(0.1)
	check(hud.selected_tower == -1, "...and its details close")

	# Automatic level-ups: stat cards pick themselves, path upgrades wait in the side bar
	hud.auto_cards = true
	await secs(0.1)
	var hero: Dictionary = sim.hero_of(me)
	check(sim.players[me].auto_cards, "the game knows my level-ups are on Automatic")
	while int(hero.level) < 2:  # level 2: a path level
		sim.grant_xp(me, 10.0)
	await secs(1.0)
	check(int(hero.level) >= 2 and int(hero.pending) == 1 and D.path_waiting(hero.tierA, hero.tierB, hero.level, hero.pending) == 1, "level 2 waits for me to pick a path upgrade (level %d, %d waiting)" % [int(hero.level), int(hero.pending)])
	var evo := -1
	for b in hud._buttons:
		if b[1].get("t", "") == "card" and hero.offer[int(b[1].i)].kind == "path":
			evo = int(b[1].i)
	check(evo >= 0 and not hud._buttons.any(func(b): return b[1].get("t", "") == "reroll"), "the side bar shows the path upgrades (and no big cards)")
	if evo >= 0:
		main.do_hud_action({"t": "card", "i": evo})
		await secs(0.2)
	check(int(hero.tierA) + int(hero.tierB) == 1 and int(hero.pending) == 0, "clicking one evolves my hero")
	var cards_before: int = hero.cards.values().reduce(func(a, v): return a + int(v), 0)
	while int(hero.level) < 3:
		sim.grant_xp(me, 10.0)
	await secs(1.2)
	var cards_after: int = hero.cards.values().reduce(func(a, v): return a + int(v), 0)
	check(int(hero.pending) == 0 and cards_after == cards_before + 1 and int(hero.tierA) + int(hero.tierB) == 1, "level 3 isn't a path level: my hero picks a stat card by itself")
	hud.auto_cards = false
	await secs(0.1)
	check(not sim.players[me].auto_cards, "...and Pick every card turns that off")

	hud.ui_scale = 1.3
	await secs(0.1)
	var vp: Vector2 = hud.get_viewport_rect().size
	check(is_equal_approx(hud.scale.x, 1.3), "UI size 130% draws the HUD 1.3 times bigger")
	check(hud._hero_bar_rect(vp.x / 1.3, vp.y / 1.3).position.x <= 12.0 and hud._hero_bar_rect(vp.x / 0.8, vp.y / 0.8).position.x > 12.0, "with no room beside the build bar the hero panel sits on top of it (only at big sizes)")
	main.queue_free()
	await secs(0.3)


## The design review's game changes: combo invites (and Bot Buddies answering
## them), leak notes, Auto Wave waiting for evolutions, the Short Adventure
func review_fixes() -> void:
	print("Combo invites, leak notes, Auto Wave waits, Short Adventure")
	var sim := new_sim()
	var a: Dictionary = sim.hero_of(1)
	var b: Dictionary = sim.hero_of(2)
	b.x = a.x + 200
	b.y = a.y
	a.special_cd = 0.0
	b.special_cd = 0.0
	sim.use_special(1)
	var co: Dictionary = sim.snapshot().comboOpen
	check(not co.is_empty() and int(co.owner) == 1, "a special opens a Team Combo window everyone can see")
	check(sim.combo_invite(b) and not sim.combo_invite(a), "...for my friend close by, not for me")
	var combos: int = sim.players[2].combos
	sim.use_special(2)
	check(sim.players[2].combos == combos + 1 and sim.snapshot().comboOpen.is_empty(), "answering it in time makes the Team Combo and closes the window")

	var sb := SimWorld.new(D)
	sb.add_player(1, "Me", "bubblelily")
	sb.add_player(100, "Bot", "voltcactus", true)
	sb.start("meadow", "normal", "adventure")
	var me: Dictionary = sb.hero_of(1)
	var bot: Dictionary = sb.hero_of(100)
	bot.x = me.x + 120
	bot.y = me.y
	me.special_cd = 0.0
	bot.special_cd = 0.0
	sb.use_special(1)
	for i in 75:
		sb.step(SimWorld.TICK)
	check(int(sb.players[100].combos) == 1, "a Bot Buddy answers my special with its own: Team Combo")

	var sl := new_sim()
	sl.start_next_wave()
	sl.spawn_queue.clear()
	sl.enemies.clear()
	pest_at(sl, "wasp", 0.97)
	for i in 300:
		sl.step(SimWorld.TICK)
		if not sl.wave_active:
			break
	check(not sl.wave_active and sl.last_leaks.size() == 1 and sl.last_leaks[0].type == "wasp" and int(sl.last_leaks[0].n) == 1, "the game remembers which trail a pest got through (%s)" % str(sl.last_leaks))
	check(D.trail_name("meadow", int(sl.last_leaks[0].path) if not sl.last_leaks.is_empty() else 0).begins_with("the "), "trails get a name kids can find: %s" % D.trail_name("meadow", 0))

	var sa := new_sim()
	sa.auto_wave = true
	sa.start_next_wave()
	sa.spawn_queue.clear()
	sa.enemies.clear()
	var ha: Dictionary = sa.hero_of(1)
	sa.step(SimWorld.TICK)
	ha.level = 2
	ha.pending = 1
	ha.offer = []
	for i in 150:
		sa.step(SimWorld.TICK)
	check(sa.wave == 1 and not sa.wave_active and sa.snapshot().get("autoHold", false), "Auto Wave waits while a player picks an evolution")
	ha.pending = 0
	for i in 60:
		sa.step(SimWorld.TICK)
	check(sa.wave == 2, "...and goes on once it's picked")

	var ss := SimWorld.new(D)
	ss.add_player(1, "Me", "peashooter")
	ss.start("meadow", "normal", "short")
	check(ss.max_wave == 6 and int(ss.players[1].acorns) == D.SHORT_ACORNS, "Short Adventure: 6 waves and %d acorns to start" % D.SHORT_ACORNS)
	var types: Array = D.plan_wave(3, D.DIFFICULTIES.normal, 1, false, "", true).groups.map(func(g): return g.type)
	check(types.has("camopuff") and D.mini_boss_wave(6, false, true) and not D.mini_boss_wave(13, false, true), "wave 3 brings Camo pests and wave 6 ends with the Thornback Toad")


## Garden Clash as a living battlefield: Garden Plots, "cover me", Rival Raids,
## Sproutling Captains and Thorn Tower lock-on warnings
func clash_living() -> void:
	print("Garden Clash: plots, cover, raids, captains, tower lock-on")
	var sim := ClashWorld.new(D)
	sim.add_player(1, "Me", "peashooter")
	sim.add_player(100, "Bot", "frostlotus", true)
	sim.start("valley", "normal", "clash")
	check(sim.cl.plots.size() == 3 and sim.cl.plots.all(func(pl): return D.is_walkable(sim.map_id, pl.x, pl.y)), "a Garden Plot beside each of the 3 lanes, on open ground")
	var me: Dictionary = sim.hero_of(1)
	var pl: Dictionary = sim.cl.plots[1]
	me.x = pl.x
	me.y = pl.y
	for i in 100:
		sim.update_plots(SimWorld.TICK)
	check(pl.state == "ready", "standing on an empty plot for 3 seconds claims it")
	sim.grow_plot(1, pl.id, "berry")
	me.hp = 100.0
	for i in 30:
		sim.update_plots(SimWorld.TICK)
	check(pl.state == "berry" and me.hp > 100.0, "a Berry Bush heals heroes next to it")
	var pest := sim.make_foe("grunt", pl.x + 20, pl.y, 300.0)
	pest.minion = true
	sim.enemies.append(pest)
	me.x = pl.x + 600
	for i in 150:
		sim.update_plots(SimWorld.TICK)
	check(pl.state == "empty", "pests standing on it with no hero around trample it")
	sim.enemies.erase(pest)
	pl.state = "vine"
	pl.spring = {}
	me.x = pl.x
	me.y = pl.y
	sim.events.clear()
	sim.update_plots(SimWorld.TICK)
	check(Vector2(me.x, me.y).distance_to(Vector2(pl.x, pl.y)) > 300 and sim.events.any(func(e): return e.type == "spring"), "a Spring Vine flings a hero down the lane")

	# going home to shop asks a teammate to cover my lane; a Bot Buddy says yes
	me.x = 1000.0
	me.y = 820.0
	me.dead = false
	sim.update_bots(SimWorld.TICK)  # the bot gets its brain
	sim.teleport_home(1)
	check(sim.cl.covers.size() == 1 and int(sim.cl.covers[0].by) == 100 and int(sim.players[100].brain.lane) == int(sim.cl.covers[0].lane), "going home asks for cover, and the Bot Buddy takes over that lane")
	var tree: Vector2 = D.sanctuary(sim.map_id)
	me.x = tree.x
	me.y = tree.y
	sim.update_covers(0.1)
	me.x = tree.x + 700
	me.y = tree.y - 200
	sim.update_covers(0.1)
	check(sim.cl.covers.is_empty(), "...and the cover ends once I'm back out of base")

	# Rival Raids: two rivals announce which tower they're coming for
	var sr := ClashWorld.new(D)
	sr.add_player(1, "Me", "peashooter")
	sr.add_player(2, "Pal", "snapdragon")
	sr.start("valley", "normal", "clash")
	for i in 30 * 25:
		sr.step(SimWorld.TICK)
		if sr.enemies.filter(func(e): return e.rival and e.state == "lane").size() >= 2:
			break
	sr.cl.raid_t = 999.0
	sr.start_raid()
	var raid: Dictionary = sr.cl.raid
	check(not raid.is_empty() and raid.names.size() == 2 and raid.phase == "warn", "a Rival Raid is announced with two rivals and a few seconds' warning (%s)" % str(raid.get("names", [])))
	var acorns: int = sr.players[1].acorns
	if not raid.is_empty():
		for id in raid.ids:
			var e = sr.resolve({"t": "foe", "id": id})
			if e:
				e.hp = 0.0
		sr.update_raid(SimWorld.TICK)
	check(sr.cl.raid.is_empty() and sr.players[1].acorns == acorns + 60, "stopping the raiders ends the raid with 60 acorns for everyone")

	# Sproutling Captains and their rally flags
	var sc := ClashWorld.new(D)
	sc.add_player(1, "Me", "peashooter")
	sc.start("valley", "normal", "clash")
	sc.wave = 1
	sc.spawn_wave()
	for i in 30:
		sc.clash_update(SimWorld.TICK)
	var cap = null
	for u in sc.cl.allies:
		if u.captain != "":
			cap = u
	check(cap != null and not sc.cl.captain.is_empty() and cap.max_hp > 3.0 * D.clash.allies.budling.hp * 0.9, "wave 2: a named Captain leads a lane (%s)" % (cap.captain if cap else "none"))
	if cap:
		var tw = null
		for e in sc.enemies:
			if e.structure and e.lane == cap.lane and not e.sheltered:
				tw = e
		if tw:
			cap.x = tw.x - 150
			cap.y = tw.y
			sc.update_captain(SimWorld.TICK)
		check(sc.cl.flags.size() == 1 and sc.cl.captain.planted, "reaching a Thorn Tower, the Captain plants a rally flag")
		var u: Dictionary = sc.cl.allies[0]
		u.x = sc.cl.flags[0].x
		u.y = sc.cl.flags[0].y
		check(sc.rallied(u), "Sproutlings by the flag are rallied")

	# Thorn Towers lock on: the snapshot says whom, and how many shots in a row
	var tw2 = null
	for e in sc.enemies:
		if e.structure and e.range > 0 and not e.sheltered and not e.core:
			tw2 = e
			break
	var hero: Dictionary = sc.hero_of(1)
	sc.cl.allies.clear()
	hero.x = tw2.x
	hero.y = tw2.y + 60
	for i in 3:
		tw2.cd = 0.0
		sc.structure_act(tw2)
	var snap_e := {}
	var s2: Dictionary = sc.snapshot()
	for i in sc.enemies.size():
		if sc.enemies[i] == tw2:
			snap_e = s2.enemies[i]
	check(int(snap_e.get("lock", -1)) == int(hero.id) and int(snap_e.get("streak", 0)) == 2, "a Thorn Tower locked on me shows in the snapshot, with its 3-shot streak")


func clash_quick() -> void:
	print("Quick Clash, shop picks, the match story")
	check(D.clash_mode("clash") and D.clash_mode("quickclash") and not D.clash_mode("short"), "both Clash modes count as Garden Clash")
	var sim := ClashWorld.new(D)
	sim.add_player(1, "Me", "snapdragon")
	sim.add_player(100, "Bot", "peashooter", true)
	sim.start("valley", "normal", "quickclash")
	check(sim.quick and sim.cl.ally_towers.filter(func(t): return t.kind == "tower").size() == 3, "Quick Clash: one Bloom Tower before each gate")
	check(sim.enemies.filter(func(e): return e.structure and e.tier == 1).is_empty() and sim.enemies.filter(func(e): return e.structure and e.tier == 2).size() == 3, "...and one Thorn Tower before each pest gate")
	check(sim.hero_of(1).items == ["bark"] and sim.hero_of(100).items == ["bow"], "everyone starts with the first item picked for their hero")
	sim.spawn_wave()
	check(sim.cl.spawn_q.any(func(q): return q.kind == "pumpkin"), "Pumpkin Cannons march from the first wave")
	check(sim.snapshot().clash.get("quick", false), "the snapshot says it's Quick Clash")
	var full := ClashWorld.new(D)
	full.add_player(1, "Me", "snapdragon")
	full.start("valley", "normal", "clash")
	check(not full.quick and full.hero_of(1).items.is_empty() and full.cl.ally_towers.filter(func(t): return t.kind == "tower").size() == 6, "the full Clash keeps 6 towers and no free item")

	# shop picks
	check(ClashWorld.recommended_buys(D, "snapdragon", []) == ["bark", "rose"], "Snapdragon's picks: Bark Shield, Vampire Rose")
	check(ClashWorld.recommended_buys(D, "peashooter", ["bow"]) == ["sword", "sandals"], "items you have are skipped")
	check(ClashWorld.recommended_buys(D, "snapdragon", ["bark+", "rose", "sword", "moss", "sandals", "acorn"]) == ["rose", "sword"], "with every slot full, the picks are Golden upgrades")
	check(ClashWorld.recommended_buys(D, "sunblossom", ["bow", "bark", "sword", "rose", "acorn", "moss"]) == ["moss", "bark"], "full slots: Golden versions of what you own, best first")

	# the story: a Pumpkin Cannon breaks a gate while I walk with it
	var gate = null
	for e in sim.enemies:
		if e.structure and e.tier == 3 and e.lane == 1:
			gate = e
	gate.sheltered = false
	var me: Dictionary = sim.hero_of(1)
	me.x = gate.x + 100
	me.y = gate.y
	sim.events.clear()
	sim.hit({"t": "foe", "id": gate.id}, gate, 1e9, {"unit": "Pumpkin Cannon"})
	var down: Array = sim.events.filter(func(e): return e.type == "struct_down")
	check(not down.is_empty() and down[0].get("unit", "") == "Pumpkin Cannon" and down[0].get("helpers", []).has("Me"), "a gate broken by a Sproutling credits it and the heroes walking with it")
	check(sim.cl.story.any(func(x): return String(x.text).begins_with("Broke the Middle Lane gate (Pumpkin Cannon, with Me")), "the story remembers it")
	var list := [{"t": 10, "text": "a", "w": 3, "kind": "x"}, {"t": 20, "text": "b", "w": 8, "kind": "x"}, {"t": 30, "text": "c", "w": 2, "kind": "x"},
		{"t": 40, "text": "d", "w": 6, "kind": "x"}, {"t": 50, "text": "e", "w": 10, "kind": "x"}]
	check(ClashWorld.story_summary(list).map(func(x): return x.text) == ["b", "d", "e"], "the end screen shows the 3 biggest moments, in order")
	check(not sim.payload().has("story"), "the story isn't sent while playing")
	sim.phase = "victory"
	check(sim.payload().get("summary", []).size() >= 1, "...but is at the end")


func clash_shop() -> void:
	print("Clash shop: lane goal, pins, the Valley card")
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await secs(0.3)
	main.start_local({"hero": "snapdragon", "map": "meadow", "diff": "normal", "gameMode": "quickclash", "bots": 1, "name": "Tester", "hat": "none", "pet": "none"})
	await secs(0.3)
	var hud = main.hud
	var sim: ClashWorld = main.host.sim
	check(sim.quick and main.snap.clash.get("quick", false), "picking Quick Clash starts a Quick Clash")
	var goal: String = hud.clash_goal(main.snap.clash)
	check(goal.contains("Lane"), "the shop says what to do next (%s)" % goal)
	sim.cl.raid = {"phase": "warn", "t": 5.0, "lane": 2, "tower": -1, "x": 0.0, "y": 0.0, "ids": [], "names": ["Queen Stinger"], "kind": "tower"}
	check(hud.clash_goal(sim.payload()).begins_with("⚔️ Stop the raid on the Bottom Lane"), "...a raid comes first")
	sim.cl.raid = {}
	# pin the Vampire Rose, walk away, get rich, come back: F buys it
	main.do_hud_action({"t": "pin", "item": "rose"})
	check(hud.pinned_item == "rose", "📌 pins an item")
	sim.players[1].acorns = 0
	await secs(0.2)
	var st: Dictionary = hud.pinned_state(main._my_hero())
	check(not st.afford and not st.done, "the pin counts down to it")
	sim.players[1].acorns = 1000
	await secs(0.2)
	check(hud.can_buy_pinned(), "at the tree with enough acorns, it can be bought")
	check(hud._buttons.any(func(b): return b[1].get("t", "") == "buy_pinned"), "a 📌 F: buy button shows")
	main.buy_pinned()
	await secs(0.3)
	check(main._my_hero().items.has("rose") and hud.pinned_item == "", "F buys the pinned item, then the pin goes away")
	main.do_hud_action({"t": "pin", "item": "rose+"})
	main.do_hud_action({"t": "pin", "item": "rose+"})
	check(hud.pinned_item == "", "pressing 📌 again unpins")
	main.queue_free()
	await secs(0.2)
