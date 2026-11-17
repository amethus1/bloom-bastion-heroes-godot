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
