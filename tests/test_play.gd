extends SceneTree
## Headless: start a solo game through main.tscn and drive it with real
## key presses (walk, click-to-walk, Leaf Leap, build, upgrade, cards,
## special, pause, waves, game over -> menu).
## godot --headless --path . -s tests/test_play.gd

var main: Node
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func key(code: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Wait until the 30 Hz simulation has run a few ticks (frames can be much faster)
func ticks() -> void:
	await secs(0.15)


func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await ticks()
	check(main.menu.visible, "title menu shows on start")
	main.start_local({"hero": "peashooter", "map": "meadow", "diff": "normal", "gameMode": "adventure", "bots": 1, "name": "Tester", "hat": "crown", "pet": "bee"})
	await ticks()
	check(not main.menu.visible and main.hud.visible, "game starts, HUD visible")
	check(main.my_pos != null, "my hero is under my control")
	check(main.snap.heroes.size() == 2, "me + 1 bot buddy")
	var sim: SimWorld = main.host.sim
	var p0: Vector2 = main.my_pos
	key(KEY_D)
	await secs(0.5)
	key(KEY_D, false)
	await ticks()
	var moved: float = main.my_pos.x - p0.x
	check(moved > 60 and moved < 140, "D walks right (%.0f px in 0.5 s)" % moved)
	var h = sim.hero_of(1)
	check(absf(h.x - main.my_pos.x) < 30, "the simulation follows my walking")
	# click-to-walk with path finding
	var target: Vector2 = main.my_pos + Vector2(0, 120)
	main.walk_to(target)
	check(main.move_path.size() > 0, "click-to-walk finds a path")
	await secs(1.2)
	check(main.my_pos.distance_to(target) < 20, "click-to-walk arrives (%.0f px away)" % main.my_pos.distance_to(target))
	# Leaf Leap
	var before: Vector2 = main.my_pos
	key(KEY_A)
	await frames(2)
	await tap(KEY_SHIFT)
	key(KEY_A, false)
	await ticks()
	check(main.my_pos.distance_to(before) > 100, "Shift = Leaf Leap (%.0f px)" % main.my_pos.distance_to(before))
	check(main._my_hero().dashCd > 0, "Leaf Leap goes on cooldown")
	# build + upgrade
	sim.players[1].acorns = 1000
	await tap(KEY_F)
	await ticks()
	var mine: Array = main.snap.gadgets.filter(func(g): return g.owner == 1)
	check(mine.size() == 1, "F builds the selected tower")
	await tap(KEY_U)
	await ticks()
	mine = main.snap.gadgets.filter(func(g): return g.owner == 1)
	check(mine.size() == 1 and mine[0].level == 2, "U upgrades it to level 2")
	await tap(KEY_U)
	await frames(2)
	await tap(KEY_U)
	await ticks()
	mine = main.snap.gadgets.filter(func(g): return g.owner == 1)
	check(mine[0].level == 3 and mine[0].branch == 0, "U, U picks special version A at level 3")
	await tap(KEY_G)
	check(main.selected_gadget != "sentry", "G picks the next tower (%s)" % main.selected_gadget)
	await tap(KEY_X)
	await ticks()
	check(main.snap.gadgets.filter(func(g): return g.owner == 1).is_empty(), "X sells it")
	# waves, cards, special
	await tap(KEY_SPACE)
	await ticks()
	check(main.snap.waveActive, "Space starts wave 1")
	sim.grant_xp(1, 400)
	await ticks()
	var lvl: int = main._my_hero().level
	var pend: int = main._my_hero().pending
	check(pend > 0, "level up gives cards (level %d, %d to pick)" % [lvl, pend])
	await tap(KEY_1)
	await ticks()
	check(main._my_hero().pending == pend - 1, "1 picks a card")
	await tap(KEY_Q)
	await ticks()
	check(main._my_hero().specialCd > 0, "Q uses the special")
	await tap(KEY_P)
	await ticks()
	check(main.snap.paused, "P pauses")
	await tap(KEY_P)
	await ticks()
	check(not main.snap.paused, "P resumes")
	await tap(KEY_H)
	await ticks()
	check(main._my_hero().homeCd > 0, "H teleports home")
	# Esc: pause menu (solo pauses the game too)
	await tap(KEY_ESCAPE)
	await ticks()
	check(main.hud.menu_open and main.snap.paused, "Esc opens the pause menu and pauses")
	await tap(KEY_ESCAPE)
	await ticks()
	check(not main.hud.menu_open and not main.snap.paused, "Esc again keeps playing")
	# T: targeting
	await tap(KEY_T)
	await ticks()
	check(main._my_hero().targetMode == "strong", "T switches targeting to Strongest")
	# with no cards waiting, number keys pick towers and show where they'd go
	var guard := 0
	while int(main._my_hero().pending) > 0 and guard < 10:
		await tap(KEY_1)
		await ticks()
		guard += 1
	await tap(KEY_2)
	await frames(2)
	check(main.selected_gadget == root.get_node("GameData").GADGET_ORDER[1] and main.world.ghost == root.get_node("GameData").GADGET_ORDER[1], "2 picks the second tower and shows where it goes")
	await secs(2.0)
	check(main.snap.enemies.size() > 0, "pests are on the field")
	# game over -> menu
	sim.lives = 0
	await ticks()
	check(main.snap.phase == "gameover", "losing all lives ends the game")
	await tap(KEY_ESCAPE)
	await ticks()
	check(main.menu.visible, "Esc returns to the title menu")
	await couch_part()
	await clash_part()
	print("test_play: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)


## Garden Clash: shop, Berry Juice, recall, knock-out and revive, the end
func clash_part() -> void:
	main.start_local({"hero": "snapdragon", "map": "meadow", "diff": "normal", "gameMode": "clash", "bots": 1, "name": "Tester", "hat": "none", "pet": "none"})
	await ticks()
	check(main.snap.has("clash") and main.snap.map == "valley", "Garden Clash starts on Three-Lane Valley")
	var sim: ClashWorld = main.host.sim
	check(main.snap.clash.allyTowers.size() == 12 and main.snap.clash.foeTowers.size() == 12, "12 buildings on each side")
	var h: Dictionary = main._my_hero()
	check(h.get("canShop", false), "you can shop at the start")
	var acorns: int = sim.players[1].acorns
	var a: Dictionary = {}
	for b in main.hud._buttons:
		if b[1].get("t", "") == "buy" and b[1].get("item", "") == "sword":
			a = b[1]
	check(not a.is_empty(), "the shop shows a Thorn Sword button")
	main.do_hud_action(a)
	await ticks()
	check(main._my_hero().items == ["sword"] and sim.players[1].acorns == acorns - 300, "clicking it buys the Thorn Sword")
	main.do_hud_action({"t": "buy", "item": "sword"})
	await ticks()
	check(main._my_hero().items == [] or main._my_hero().items == ["sword+"] or sim.players[1].acorns < 450, "buying it again makes it Golden (when you can afford it)")
	sim.players[1].acorns = 2000
	main.do_hud_action({"t": "buy", "item": "sword"})
	main.do_hud_action({"t": "buy", "item": "juice"})
	await ticks()
	check(main._my_hero().items == ["sword+"], "Golden Thorn Sword")
	check(main._my_hero().potions == 1, "bought a Berry Juice")
	var hero = sim.hero_of(1)
	hero.hp = 100.0
	await tap(KEY_R)
	await ticks()
	check(main._my_hero().potions == 0 and D_buff(hero, "juice") > 0, "R drinks the Berry Juice")
	# recall: walk away from the tree, press B, stand still 3 s
	hero.x = 1000.0
	hero.y = 700.0
	main.my_pos = Vector2(1000, 700)
	main.last_sent = {"p": main.my_pos, "at": main.clock}
	await ticks()
	await tap(KEY_B)
	await ticks()
	check(main._my_hero().recall > 0, "B starts going home")
	await secs(3.3)
	check(main._my_hero().get("canShop", false), "after 3 seconds you are back at the tree")
	# knocked out, then revived by a friend standing next to you
	hero.x = 1000.0
	hero.y = 700.0
	main.my_pos = Vector2(1000, 700)
	sim.hurt_hero(hero, 1e9, "Test")
	await ticks()
	check(main._my_hero().dead, "a hero can be knocked out")
	var before: Vector2 = main.my_pos
	key(KEY_D)
	await secs(0.3)
	key(KEY_D, false)
	check(main.my_pos == before, "knocked-out heroes can't walk")
	var buddy = sim.hero_of(100)
	sim.players[100].is_bot = false  # hold the bot still next to me
	buddy.x = hero.x + 30
	buddy.y = hero.y
	await secs(3.0)
	check(not main._my_hero().dead, "a friend standing next to you revives you")
	# win
	for e in sim.enemies:
		if e.get("core", false):
			e.sheltered = false
			sim.apply_damage(e, 1e12, 1, hero.id, {"armorPierce": true})
	await ticks()
	check(main.snap.phase == "victory", "smashing the Thorn Heart wins")


func D_buff(h: Dictionary, k: String) -> float:
	return float(h.buffs.get(k, 0.0))


func pad(device: int, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := InputEventJoypadButton.new()
	u.device = device
	u.button_index = button
	u.pressed = false
	Input.parse_input_event(u)
	await frames(2)


func stick(device: int, x: float, y: float) -> void:
	for ax in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
		var m := InputEventJoypadMotion.new()
		m.device = device
		m.axis = ax[0]
		m.axis_value = ax[1]
		Input.parse_input_event(m)


## Couch co-op: controllers join mid-game, walk, act, and the camera frames everyone
func couch_part() -> void:
	main.start_local({"hero": "peashooter", "map": "meadow", "diff": "easy", "gameMode": "adventure", "bots": 2, "name": "Tester", "hat": "none", "pet": "none"})
	await ticks()
	var sim: SimWorld = main.host.sim
	check(sim.players.size() == 3, "couch: me + 2 bots to start")
	await pad(0, JOY_BUTTON_START)
	check(main.couch.joining().size() == 1, "couch: Start on a controller opens a hero picker")
	var before: int = main.couch.joining()[0].hero_i
	await pad(0, JOY_BUTTON_DPAD_RIGHT)
	check(main.couch.joining()[0].hero_i != before, "couch: the D-pad changes the hero")
	await pad(0, JOY_BUTTON_A)
	await ticks()
	check(sim.players.has(11) and sim.players.size() == 4, "couch: A joins as Player 2")
	var h = sim.hero_of(11)
	var x0: float = h.x
	stick(0, 1.0, 0.0)
	await secs(0.5)
	stick(0, 0.0, 0.0)
	check(h.x - x0 > 50, "couch: the left stick walks (%d px)" % (h.x - x0))
	h.special_cd = 0.0
	await pad(0, JOY_BUTTON_X)
	check(h.special_cd > 0, "couch: X uses the special")
	sim.players[11].acorns = 500
	var GD = root.get_node("GameData")
	var found := false
	for r in range(60, 600, 30):  # stand somewhere a Sprout Sentry can go
		for k in 12:
			var at := Vector2(h.x, h.y) + Vector2(cos(k * TAU / 12), sin(k * TAU / 12)) * r
			if GD.is_walkable(sim.map_id, at.x, at.y) and GD.gadget_spot(sim.map_id, "sentry", at.x, at.y).ok:
				h.x = at.x
				h.y = at.y
				found = true
				break
		if found:
			break
	await pad(0, JOY_BUTTON_Y)
	await ticks()
	check(sim.gadgets.any(func(g): return g.owner == 11), "couch: Y builds a tower")
	sim.grant_xp(11, 300)
	var pend: int = h.pending
	await pad(0, JOY_BUTTON_DPAD_UP)
	check(h.pending == pend - 1, "couch: the D-pad picks a level-up card")
	await ticks()
	check(main.world.follow_ids.size() == 1, "couch: the camera frames both local heroes")
	# a second controller when the team is full takes over from a Bot Buddy
	await pad(1, JOY_BUTTON_A)
	await pad(1, JOY_BUTTON_A)
	await ticks()
	var bots := 0
	for p in sim.players.values():
		if p.is_bot:
			bots += 1
	check(sim.players.has(12) and sim.players.size() == 4 and bots == 1, "couch: a 5th player replaces a bot")
	# play again keeps the couch players
	sim.lives = 0
	await ticks()
	main.do_hud_action({"t": "again"})
	await ticks()
	check(main.host.sim.players.has(11) and main.host.sim.players.has(12), "couch: Play again keeps the controller players")
	main.show_menu()
	await ticks()
