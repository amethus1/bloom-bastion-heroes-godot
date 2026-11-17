extends SceneTree
## Headless: snapshot packets survive encode/decode, and stay small enough
## for Wi-Fi at 20 per second, even in a big late-game wave.
## godot --headless --path . -s tests/test_net.gd

func _init() -> void:
	var D = load("res://autoload/game_data.gd").new()
	var sim := SimWorld.new(D)
	for i in 4:
		sim.add_player(100 + i, "Bot %d" % i, D.HERO_ORDER[i * 2 % 7], true)
	sim.start("courtyard", "normal", "endless")
	var fails := 0
	var worst := 0
	var worst_raw := 0
	var worst_n := 0
	var t := 0.0
	while sim.phase == "playing" and sim.wave < 35 and t < 3600:
		if not sim.wave_active:
			sim.start_next_wave()
		sim.step(SimWorld.TICK)
		t += SimWorld.TICK
		if int(t * 30) % 15 == 0:
			var s := sim.snapshot()
			var raw := var_to_bytes({"m": "snap", "s": s}).size()
			var pkt := NetCommon.encode({"m": "snap", "s": s}, true)
			if pkt.size() > worst:
				worst = pkt.size()
				worst_raw = raw
				worst_n = s.enemies.size()
			var back := NetCommon.decode(pkt)
			if back.get("s", {}).get("enemies", []).size() != s.enemies.size() or back.s.wave != s.wave:
				fails += 1
		sim.events.clear()
	var junk := NetCommon.decode(PackedByteArray([2, 255, 255, 255, 127, 1, 2, 3]))
	if not junk.is_empty():
		fails += 1
	print("played to wave %d; biggest snapshot: %d enemies, %.1f KB raw -> %.1f KB packed (%.0f KB/s at 20 Hz)" % [sim.wave, worst_n, worst_raw / 1024.0, worst / 1024.0, worst * 20 / 1024.0])
	print("test_net: %d failure(s)" % fails)
	D.free()
	quit(1 if fails > 0 else 0)
