extends SceneTree
## Headless: Bot Buddies play whole Garden Clash games.
## godot --headless --path . -s tests/test_clash.gd -- [difficulty] [heroes,comma,separated] [games] [idle|quick]
## "idle" adds a player who just stands at the tree, like the Node balance oracle (tools/sim.js).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var diff: String = args[0] if args.size() > 0 else "normal"
	var hero_list: PackedStringArray = (args[1] if args.size() > 1 else "frostlotus,snapdragon").split(",")
	var games: int = int(args[2]) if args.size() > 2 else 1
	var D = load("res://autoload/game_data.gd").new()
	var fails := 0
	for g in games:
		var sim := ClashWorld.new(D)
		if args.size() > 4:
			sim.retarget_every = float(args[4])
		if args.size() > 3 and args[3] == "idle":
			sim.add_player(1, "Idle Kid", "peashooter", false)
		for i in hero_list.size():
			sim.add_player(100 + i, "Bot %d" % i, hero_list[i], true)
		sim.start("valley", diff, "quickclash" if args.has("quick") else "clash")
		var t := 0.0
		var started := Time.get_ticks_msec()
		var counts := {}
		var peak_enemies := 0
		var peak_allies := 0
		var bytes := 0
		while sim.phase == "playing" and t < 70.0 * 60.0:
			sim.step(SimWorld.TICK)
			for e in sim.events:
				counts[e.type] = counts.get(e.type, 0) + 1
			sim.events.clear()
			t += SimWorld.TICK
			peak_enemies = maxi(peak_enemies, sim.enemies.size())
			peak_allies = maxi(peak_allies, sim.cl.allies.size())
			if int(t * 30) % 1800 == 0:
				bytes = maxi(bytes, NetCommon.encode({"m": "snap", "s": sim.snapshot()}, true).size())
		var lv := []
		var items := []
		for h in sim.heroes:
			lv.append(h.level)
			items.append(",".join(h.items))
		print("clash %s %s -> %s after %.1f min (%.1f s real) | levels %s | towers down: ours %d, theirs %d | rival KOs %d | hero KOs %d | revives %d | peak %d pests, %d sproutlings | %.1f KB snap" % [
			diff, ",".join(hero_list), sim.phase, t / 60.0, (Time.get_ticks_msec() - started) / 1000.0, lv,
			sim.cl.ally_towers_down, sim.cl.foe_towers_down, sim.cl.rival_kos, counts.get("hero_down", 0), counts.get("revive", 0),
			peak_enemies, peak_allies, bytes / 1024.0])
		print("   story: ", " → ".join(ClashWorld.story_summary(sim.cl.story).map(func(x): return "%s (%d:%02d)" % [x.text, int(x.t) / 60, int(x.t) % 60])))
		print("   items: ", items, "  camps: ", counts.get("camp_down", 0), "  power-ups: ", counts.get("powerup_get", 0), "  gate regrows: ", counts.get("gate_regrow", 0))
		if sim.phase == "playing":
			fails += 1
	D.free()
	quit(1 if fails > 0 else 0)
