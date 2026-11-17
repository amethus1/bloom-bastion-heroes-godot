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
	print("test_rules: %d failure(s)" % fails)
	D.free()
	quit(1 if fails > 0 else 0)
