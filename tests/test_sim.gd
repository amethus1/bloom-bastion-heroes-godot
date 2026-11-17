extends SceneTree
## Headless: play whole games with Bot Buddies and print how they went.
## godot --headless --path . -s tests/test_sim.gd -- [map] [difficulty] [mode] [heroes,comma,separated]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map: String = args[0] if args.size() > 0 else "meadow"
	var diff: String = args[1] if args.size() > 1 else "normal"
	var mode: String = args[2] if args.size() > 2 else "adventure"
	var hero_list: PackedStringArray = (args[3] if args.size() > 3 else "frostlotus,snapdragon").split(",")
	var D = load("res://autoload/game_data.gd").new()
	var sim := SimWorld.new(D)
	for i in hero_list.size():
		sim.add_player(100 + i, "Bot %d" % i, hero_list[i], true)
	sim.start(map, diff, mode)
	var t := 0.0
	var counts := {}
	var started := Time.get_ticks_msec()
	var max_t := 45.0 * 60.0
	while sim.phase == "playing" and t < max_t:
		if not sim.wave_active:
			sim.start_next_wave()
		sim.step(SimWorld.TICK)
		for e in sim.events:
			counts[e.type] = counts.get(e.type, 0) + 1
		sim.events.clear()
		t += SimWorld.TICK
	print("%s %s %s %s -> %s after %.1f min, wave %d, lives %d/%d (%.1f s real)" % [mode, diff, map, ",".join(hero_list), sim.phase, t / 60.0, sim.wave, sim.lives, sim.max_lives, (Time.get_ticks_msec() - started) / 1000.0])
	for h in sim.heroes:
		var p: Dictionary = sim.players[h.owner]
		print("   %s L%d A%dB%d towers %d pops %d" % [h.type, h.level, h.tierA, h.tierB, sim.gadgets.filter(func(g): return g.owner == h.owner).size(), p.pops])
	var keys := ["leak", "reaction", "special", "combo", "gadget_placed", "gadget_upgraded", "chest_open", "powerup_get", "level_up"]
	var parts: Array = []
	for k in keys:
		if counts.has(k):
			parts.append("%s %d" % [k, counts[k]])
	print("   events: ", ", ".join(parts))
	D.free()
	quit()
