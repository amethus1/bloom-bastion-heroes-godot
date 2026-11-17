extends SceneTree
## A LAN friend whose Wi-Fi drops keeps their hero: a Bot Buddy plays it while
## they're away, and joining again (same computer + name) hands it back with
## its level, cards, acorns and towers.
## Run: godot --headless --path . -s tests/test_rejoin.gd
## (The real network path: see README, "--dropat".)

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var D = load("res://autoload/game_data.gd").new()
	for clash in [false, true]:
		print("Garden Clash" if clash else "Adventure")
		var sim: SimWorld = ClashWorld.new(D) if clash else SimWorld.new(D)
		sim.add_player(1, "Host", "peashooter")
		sim.add_player(5, "Kid", "frostlotus")
		sim.start("valley" if clash else "meadow", "normal", "clash" if clash else "adventure")
		if not clash:
			sim.start_wave()
		for i in 30 * 5:
			sim.step(SimWorld.TICK)
		sim.grant_xp(5, 400)
		sim.players[5].acorns = 777
		var h: Dictionary = sim.hero_of(5)
		var hero_id: int = h.id
		var level: int = h.level
		if not clash:
			sim.players[5].acorns = 900
			sim.plant(5, "sentry")
			sim.players[5].acorns = 777
		var mine_before := sim.gadgets.filter(func(g): return g.owner == 5).size()
		var at := Vector2(h.x, h.y)

		sim.set_away(5, "abc:Kid")
		check(sim.players.has(5) and sim.players[5].is_bot and sim.is_away("abc:Kid"), "a dropped friend's hero stays, played by a Bot Buddy")
		check(sim.snapshot().players.any(func(p): return p.id == 5 and p.away), "the team list shows them as away")
		for i in 30 * 8:
			sim.step(SimWorld.TICK)
		var h_away = sim.hero_of(5)
		check(h_away != null and Vector2(h_away.x, h_away.y).distance_to(at) > 5, "the bot walks the hero around meanwhile")

		check(not sim.rejoin(9, "zzz:Kid"), "someone else (another computer) doesn't get the hero")
		check(sim.rejoin(42, "abc:Kid"), "the same computer and name joining again gets it back")
		check(not sim.players.has(5) and sim.players.has(42) and not sim.players[42].is_bot and not sim.players[42].has("away"), "they're a player again under their new connection")
		var h2 = sim.hero_of(42)
		check(h2 != null and h2.id == hero_id and h2.level >= level, "same hero, level kept (was %d, now %d)" % [level, h2.level if h2 else -1])
		check(int(sim.players[42].acorns) >= 777 - 50, "acorns kept (%d)" % int(sim.players[42].acorns))
		if not clash:
			check(mine_before > 0 and sim.gadgets.filter(func(g): return g.owner == 42).size() == mine_before, "their towers are theirs again (%d)" % mine_before)
		check(sim.events.any(func(e): return e.type == "player_back"), "everyone hears they're back")
		check(not sim.is_away("abc:Kid") and not sim.rejoin(43, "abc:Kid"), "it only works once")
		for i in 30 * 2:
			sim.step(SimWorld.TICK)
		sim.move_hero(42, h2.x + 30, h2.y)
		check(sim.hero_of(42) != null, "the returned player can play on")

		sim.set_away(42, "")
		check(not sim.players.has(42) and sim.hero_of(42) == null, "without a key (old version) leaving removes the hero like before")
		sim.add_player(7, "Pal", "boomshroom", true)
		sim.set_away(7, "x:Pal")
		check(not sim.players.has(7), "a Bot Buddy leaving is just removed")
	D.free()
	print("rejoin tests: %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
