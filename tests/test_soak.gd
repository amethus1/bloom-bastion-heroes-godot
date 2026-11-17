extends SceneTree
## Headless soak test: the real game (main.tscn, HUD and drawing included)
## plays many fast games back to back in every mode and on every map, with
## bots doing everything. Watch the output for SCRIPT ERROR lines; at the end
## it prints how memory and object counts changed between the first and last
## game, so leaks show up.
## godot --headless --path . -s tests/test_soak.gd -- [seconds per game]

var main: Node
var Prof


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	Prof = load("res://ui/profile.gd")
	Prof.path = "user://test_profile.cfg"
	var cf := ConfigFile.new()
	cf.save(Prof.path)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var per_game := float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 25.0
	var repeat := OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "repeat"
	var plans := [
		["meadow", "normal", "adventure", "frostlotus"], ["river", "hard", "adventure", "bubblelily"],
		["courtyard", "nightmare", "adventure", "voltcactus"], ["hollow", "easy", "endless", "snapdragon"],
		["frosty", "normal", "endless", "sunblossom"], ["valley", "normal", "clash", "boomshroom"],
		["meadow", "hard", "clash", "peashooter"], ["courtyard", "normal", "endless", "bubblelily"],
	]
	if repeat:  # the same game again and again: memory should stay flat
		plans = []
		for i in 8:
			plans.append(["meadow", "normal", "adventure", "frostlotus"])
	var mem0 := 0.0
	var obj0 := 0
	var node0 := 0
	var n := 0
	for pl in plans:
		n += 1
		main.start_local({"hero": pl[3], "map": pl[0], "diff": pl[1], "gameMode": pl[2], "bots": 3, "name": "Soak"}, true)
		main.host.sim.speed_mult = 2.0
		var sim = main.host.sim
		# jump ahead so late-game things (bosses, Endless twists, Clash gates) show up too
		for i in 30 * (60 if pl[2] != "clash" else 400):
			if sim.phase != "playing":
				break
			if not sim.wave_active and pl[2] != "clash":
				sim.start_next_wave()
			sim.step(1.0 / 30.0)
		sim.events.clear()
		sim.auto_wave = true
		var t0 := Time.get_ticks_msec()
		var frames_run := 0
		while Time.get_ticks_msec() - t0 < per_game * 1000.0 and sim.phase == "playing":
			await process_frame
			frames_run += 1
			# poke a few UI bits too
			if frames_run % 90 == 0:
				main.hud.show_stats = not main.hud.show_stats
			if frames_run % 150 == 0:
				main.send({"t": "ping", "x": 600.0 + randf() * 900, "y": 300.0 + randf() * 700})
		print("game %d %s %s %s: wave %d, phase %s, %d pests, %d frames" % [n, pl[0], pl[1], pl[2], sim.wave, sim.phase, sim.enemies.size(), frames_run])
		if repeat:
			main._leave_game()  # no title-screen background game in between
		else:
			main.show_menu()
		await frames(20)
		var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		var obj := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		if n == 2:
			mem0 = mem
			obj0 = obj
			node0 = nodes
		print("   memory %.1f MB, objects %d, nodes %d" % [mem, obj, nodes])
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("SOAK: memory %.1f -> %.1f MB, objects %d -> %d, nodes %d -> %d (game 2 vs last)" % [mem0, mem1, obj0, int(Performance.get_monitor(Performance.OBJECT_COUNT)), node0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	quit()
