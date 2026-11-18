extends SceneTree
## Smoothness checks for what's drawn on screen (no window needed):
##   - a LAN friend sees pests glide evenly even when Wi-Fi delivers snapshots unevenly
##   - pausing on a LAN friend's screen holds everything still, then resumes without a jump
##   - new pests fade in; heroes and pests don't flicker between facing left and right
## Run: godot --headless --path . --script res://tests/test_smooth.gd

var fails := 0
var WV  # render/world_view.gd, loaded at run time (after the autoloads exist)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	await process_frame
	WV = load("res://render/world_view.gd")
	var world: Node2D = WV.new()
	world.mute_audio = true
	root.add_child(world)
	_lan_glide(world)
	_lan_pause(world)
	_spawn_and_facing(world)
	_dash_and_pops(world)
	await _graphics(world)
	print("smooth tests: %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)


func _snap(t: float, x: float, extra := {}) -> Dictionary:
	var s := {"time": t, "map": "meadow", "speed": 1.0, "paused": false, "heroes": [], "projectiles": [], "lives": 20, "maxLives": 20,
		"enemies": [{"id": 5, "type": "sprout", "x": x, "y": 300.0, "hp": 10, "maxHp": 10, "boss": false, "big": false, "burrowed": false,
			"frozen": false, "stunned": false, "slowed": false, "camo": false, "sheltered": false, "flash": false, "burning": false}]}
	s.merge(extra, true)
	return s


## A pest walks right at 120 px/s. The host sends 20 snapshots a second; each one
## reaches the friend 30-90 ms later (Wi-Fi jitter). Draw at 60 fps and see how
## evenly the pest moves from frame to frame.
func _run_lan(world: Node2D, use_buffer: bool, seed_n: int) -> Dictionary:
	world.reset()
	world.remote_interp = use_buffer
	world.snap_dt = 0.05
	seed(seed_n)
	var arrivals: Array = []
	var last_arrive := 0.0
	for i in 120:
		var t := i * 0.05
		var arrive := maxf(last_arrive, t + 0.03 + randf() * 0.06)  # stays in order (unreliable-ordered channel)
		last_arrive = arrive
		arrivals.append([arrive, t])
	var frame := 1.0 / 60.0
	var clock := 0.0
	var next := 0
	var snap_at := 0.0
	var snap_gap := 0.05
	var steps: Array = []
	var last_x := -1.0
	var backwards := 0
	while clock < 5.5:
		clock += frame
		while next < arrivals.size() and arrivals[next][0] <= clock:
			var t: float = arrivals[next][1]
			snap_gap = lerpf(snap_gap, clampf(clock - snap_at, 0.01, 0.2), 0.2)
			snap_at = clock
			world.push_snapshot(_snap(t, 100.0 + 120.0 * t))
			next += 1
		world.snap_dt = snap_gap
		world.tick_alpha = clampf((clock - snap_at) / maxf(snap_gap, 0.016), 0, 1.5)  # what main.gd does for LAN friends
		world._process(frame)
		if world.snap.is_empty():
			continue
		var x: float = world.pos_of(5, Vector2.ZERO).x
		if last_x >= 0 and clock > 1.0:
			var dx: float = x - last_x
			steps.append(dx)
			if dx < -0.01:
				backwards += 1
		last_x = x
	var mean := 0.0
	for d in steps:
		mean += d
	mean /= maxf(1.0, steps.size())
	var worst := 0.0
	var still := 0
	for d in steps:
		worst = maxf(worst, absf(d - mean))
		if absf(d) < 0.05:
			still += 1
	return {"mean": mean, "worst": worst, "back": backwards, "still": still, "n": steps.size()}


func _lan_glide(world: Node2D) -> void:
	print("LAN friend: pests glide evenly through Wi-Fi jitter")
	var old_worst := 0.0
	var new_worst := 0.0
	var new_back := 0
	var new_still := 0
	var old_still := 0
	for sd in [1, 2, 3, 4]:
		var old := _run_lan(world, false, sd)
		var buf := _run_lan(world, true, sd)
		old_worst = maxf(old_worst, old.worst)
		new_worst = maxf(new_worst, buf.worst)
		new_back += int(buf.back)
		new_still += int(buf.still)
		old_still += int(old.still)
	print("     per-frame step should be 2.0 px; worst miss: before %.2f px (%d frozen frames), now %.2f px (%d frozen frames)" % [old_worst, old_still, new_worst, new_still])
	check(new_back == 0, "never steps backwards")
	check(new_still == 0, "never freezes for a frame while it should be moving")
	check(new_worst < 0.8, "each frame's step stays within 0.8 px of even (was %.2f px)" % old_worst)
	check(new_worst < old_worst * 0.5, "at least twice as even as blending only the last two snapshots")


func _lan_pause(world: Node2D) -> void:
	print("LAN friend: pausing holds still, unpausing doesn't jump")
	world.reset()
	world.remote_interp = true
	world.snap_dt = 0.05
	var t := 0.0
	var clock := 0.0
	var xs: Array = []
	# 1 s moving, 1 s paused (snapshots keep coming with the same game time), 1 s moving
	for i in 180:
		clock += 1.0 / 60.0
		var paused := i >= 60 and i < 120
		if i % 3 == 0:
			if not paused:
				t += 0.05
			world.push_snapshot(_snap(t, 100.0 + 120.0 * t, {"paused": paused}))
		world._process(1.0 / 60.0)
		xs.append(world.pos_of(5, Vector2.ZERO).x)
	var moved_in_pause: float = absf(float(xs[115]) - float(xs[80]))
	check(moved_in_pause < 0.01, "stands still while paused (moved %.2f px)" % moved_in_pause)
	var biggest := 0.0
	for i in range(121, 179):
		biggest = maxf(biggest, absf(float(xs[i + 1]) - float(xs[i])))
	check(biggest < 4.0, "after unpausing it walks on without a jump (biggest step %.1f px)" % biggest)


func _spawn_and_facing(world: Node2D) -> void:
	print("New pests fade in; facing doesn't flicker")
	world.reset()
	world.remote_interp = false
	world.tick_alpha = 1.0
	world.time = 10.0
	world.push_snapshot(_snap(0.0, 200.0))
	var e: Dictionary = world.snap.enemies[0]
	for k in ["big", "boss", "burrowed", "frozen", "stunned", "slowed", "camo", "sheltered", "flash", "burning"]:
		e[k] = false
	e["hp"] = 10
	e["maxHp"] = 10
	var a: Dictionary = world._enemy_anim(e, Vector2(200, 300))
	check(is_equal_approx(float(a.born), 10.0), "a new pest remembers when it appeared (to fade and grow in)")
	# a pest walking straight down with a little sideways wobble keeps its facing
	var flips := 0
	a.face = 1
	a.lx = 200.0
	for i in 120:
		WV.face_toward(a, 200.0 + sin(i * 0.9) * 0.4, 1.0 / 60.0, 8.0)  # sub-pixel wobble from rounding
		if a.face != 1:
			flips += 1
	check(flips == 0, "wobbling while walking down never flips a pest's picture (%d flips)" % flips)
	# a hero who really turns around faces the new way within a few frames
	var h := {"lx": 300.0, "face": 1, "vx": 200.0}
	var x := 300.0
	var frames := 0
	while h.face == 1 and frames < 60:
		x -= 200.0 / 60.0
		WV.face_toward(h, x, 1.0 / 60.0, 25.0)
		frames += 1
	check(h.face == -1 and frames <= 4, "a hero turning around faces the new way quickly (%d frames)" % frames)


func _dash_and_pops(world: Node2D) -> void:
	print("Dashes slide, defeated pests pop, new towers spring up")
	world.reset()
	world.my_pos = Vector2(100, 100)
	world.slide_from(Vector2(100, 100), Vector2(260, 100))
	world.my_pos = Vector2(260, 100)
	var xs: Array = [world._me().x]
	for i in 12:
		world._process(1.0 / 60.0)
		xs.append(world._me().x)
	var ordered := true
	for i in xs.size() - 1:
		if xs[i + 1] < xs[i] - 0.001:
			ordered = false
	check(is_equal_approx(float(xs[0]), 100.0) and is_equal_approx(float(xs[-1]), 260.0), "my hero is drawn zipping from where it was to where it leapt (%.0f -> %.0f)" % [xs[0], xs[-1]])
	check(ordered and float(xs[3]) > 160.0, "the zip only goes forward and starts fast (%.0f px after 3 frames)" % xs[3])
	world.my_pos = null
	world.time = 5.0
	world.push_snapshot(_snap(1.0, 300.0, {"events": [{"type": "enemy_pop", "id": 5, "x": 300.0, "y": 300.0, "kind": "sprout", "color": "#a3e635", "boss": false}]}))
	var ghosts: Array = world._fx.filter(func(f): return f.kind == "ghost")
	check(ghosts.size() == 1 and ghosts[0].type == "sprout", "a defeated pest leaves a quick bright pop of its own picture")
	check(is_zero_approx(world._ease_back(0.0)) and is_equal_approx(world._ease_back(1.0), 1.0) and world._ease_back(0.8) > 1.0, "towers spring up with a small overshoot")


func _hero(id: int, owner: int, slot: int, x: float, y: float) -> Dictionary:
	return {"id": id, "owner": owner, "slot": slot, "type": "peashooter", "x": x, "y": y, "tierA": 0, "tierB": 0, "level": 3, "recoil": 0.0,
		"angle": 0.0, "buffs": {}, "rally": false, "dazed": false, "pending": 0, "range": 150.0, "hat": "none", "pet": "none"}


## Pests pop in a puff of smoke, words rise and slow down, towers bounce when they
## fire, heroes' name tags never pile up, and Graphics: Simple turns the extras off
func _graphics(world: Node2D) -> void:
	print("Puffs, rising words, firing towers, name tags, Graphics setting")
	check(world._parts.any(func(p): return p.has("grow")) and world._parts.any(func(p): return p.has("star")), "a popped pest leaves a puff of smoke and a few twinkles")
	world._floats.clear()
	world.float_text(Vector2(0, 0), "12", Color.WHITE, 12, 1.0)
	var ys: Array = [0.0]
	for i in 36:
		world._update_fx(1.0 / 60.0)
		ys.append(world._floats[0].p.y)
	var early: float = ys[0] - ys[6]
	var late: float = ys[30] - ys[36]
	check(early > 0 and early > late * 2.5, "pop-up words rise quickly, then slow down (%.1f px vs %.1f px)" % [early, late])

	world.reset()
	world.my_owner = 1  # the camera follows hero 1, so the tower next to it is on screen
	var g := {"id": 70, "kind": "sentry", "x": 540.0, "y": 470.0, "slot": 0, "owner": 1, "level": 1, "branch": -1, "angle": 0.0, "asleep": false, "spent": 60, "shots": 0}
	var two_heroes := [_hero(1, 1, 0, 600.0, 500.0), _hero(2, 2, 1, 604.0, 502.0)]
	var players := [{"id": 1, "name": "Ana", "slot": 0}, {"id": 2, "name": "Ben", "slot": 1}]
	world.push_snapshot(_snap(1.0, 900.0, {"gadgets": [g], "heroes": two_heroes, "players": players, "phase": "playing"}))
	await process_frame
	await process_frame
	var g2 := g.duplicate()
	g2.shots = 1
	world.push_snapshot(_snap(1.05, 900.0, {"gadgets": [g2], "heroes": two_heroes, "players": players, "phase": "playing"}))
	await process_frame
	await process_frame
	var an: Dictionary = world._anim.get("g70", {})
	check(an.has("fire") and world.time - float(an.fire) < 0.2, "a tower that fires gets a bounce (and a flash of light)")
	check(world._tags.size() == 2 and not (world._tags[0] as Rect2).intersects(world._tags[1]), "two heroes standing together get their name tags stacked, not piled up")
	world.my_owner = -1
	world.set_fancy(false)
	check(not world.lights.visible and world.map_sprite.material == null, "Graphics: Simple turns off the light and the cloud & water shader")
	world.set_fancy(true)
	check(world.lights.visible and world.map_sprite.material is ShaderMaterial, "Graphics: Fancy turns them back on")
	var hud = load("res://ui/hud.gd").new()
	hud._frame_dt = 1.0 / 60.0
	hud.eased("bar", 0.0)
	var mid: float = hud.eased("bar", 1.0)
	for i in 60:
		hud.eased("bar", 1.0)
	check(mid > 0.0 and mid < 0.5 and is_equal_approx(hud.eased("bar", 1.0), 1.0), "HUD bars glide to a new value instead of jumping (%.2f after one frame)" % mid)
	hud.free()
