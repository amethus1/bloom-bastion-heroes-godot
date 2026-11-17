extends SceneTree
## Save & resume: a solo game saves itself after each cleared wave, the title
## screen offers Continue, and continuing puts everything back.
## Run: godot --headless --path . -s tests/test_save.gd

var fails := 0
var main: Node


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


## Bots play until `waves` waves are cleared
func play_waves(sim: SimWorld, waves: int) -> void:
	var guard := 0
	while sim.wave < waves or sim.wave_active:
		if not sim.wave_active:
			sim.start_next_wave()
		sim.step(SimWorld.TICK)
		sim.events.clear()
		guard += 1
		if guard > 30 * 60 * 15:
			break


func run() -> void:
	var SG = load("res://sim/save_game.gd")
	SG.path = "user://test_autosave.save"
	SG.clear()
	var D = load("res://autoload/game_data.gd").new()

	print("Saving and loading the game itself")
	var sim := SimWorld.new(D)
	sim.add_player(1, "Me", "frostlotus", true)
	sim.add_player(100, "Sprout", "snapdragon", true)
	sim.start("river", "normal", "adventure")
	play_waves(sim, 4)
	sim.players[1].acorns = 321
	var me: Dictionary = sim.hero_of(1)
	check(not sim.wave_active and sim.wave == 4, "four waves played (wave %d)" % sim.wave)
	check(SG.save(sim, {"map": "river", "diff": "normal", "gameMode": "adventure", "hero": "frostlotus"}, 77), "it saves between waves")
	var d: Dictionary = SG.info()
	check(not d.is_empty() and int(d.run) == 77, "the save can be read back")
	print("     title screen says: ", SG.describe(d, D))
	var sim2 := SimWorld.new(D)
	SG.restore(sim2, d)
	var me2 = sim2.hero_of(1)
	check(sim2.phase == "playing" and sim2.wave == 4 and sim2.lives == sim.lives and sim2.map_id == "river", "same map, wave and Bloom Tree lives")
	check(me2 != null and me2.level == me.level and me2.tierA == me.tierA and me2.tierB == me.tierB and me2.cards == me.cards, "my hero has the same level, upgrades and cards (Lv %d)" % me.level)
	check(int(sim2.players[1].acorns) == 321, "same acorns")
	check(sim2.gadgets.size() == sim.gadgets.size() and sim2.gadgets.size() > 0, "same towers (%d)" % sim.gadgets.size())
	check(sim2.heroes.size() == 2 and sim2.players[100].is_bot, "the Bot Buddy is back too")
	var id_before := sim2.gen_id()
	check(id_before > int(d.state._next_id) - 1, "new things get fresh ids")
	play_waves(sim2, 6)
	check(sim2.wave == 6 and sim2.phase == "playing", "the continued game plays on (wave %d)" % sim2.wave)
	sim.wave_active = true
	check(not SG.save(sim, {}, 1), "it never saves in the middle of a wave")
	SG.clear(12345)
	check(not SG.info().is_empty(), "ending a different game keeps this save")
	SG.clear(77)
	check(SG.info().is_empty(), "ending this game removes its save")

	print("The real game: autosave, Continue button, continuing")
	var Prof = load("res://ui/profile.gd")
	Prof.path = "user://test_profile.cfg"
	var cf := ConfigFile.new()
	cf.save(Prof.path)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await secs(0.3)
	main.start_local({"hero": "voltcactus", "map": "meadow", "diff": "easy", "gameMode": "adventure", "bots": 1, "name": "Saver"}, false)
	var hs: SimWorld = main.host.sim
	hs.speed_mult = 2.0
	hs.start_wave()
	var t0 := Time.get_ticks_msec()
	while hs.wave < 2 or hs.wave_active:
		if not hs.wave_active and hs.wave < 2:
			hs.start_next_wave()
		await process_frame
		if Time.get_ticks_msec() - t0 > 90000:
			break
	await secs(0.2)
	var auto: Dictionary = SG.info()
	check(not auto.is_empty() and int(auto.state.wave) == 2, "clearing a wave saved the game (wave %d)" % (int(auto.state.wave) if not auto.is_empty() else -1))
	var my_level: int = hs.hero_of(1).level
	main.show_menu()
	await secs(0.3)
	var found := false
	for b in main.menu.find_children("*", "Button", true, false):
		if String(b.text).contains("Continue (wave 2)"):
			found = true
			print("     ", b.text)
	check(found, "the title screen offers Continue")
	main.resume_saved()
	await secs(0.5)
	var rs: SimWorld = main.host.sim
	check(main.playing and rs.wave == 2 and not rs.wave_active, "Continue puts me back after wave 2")
	check(rs.hero_of(1) != null and rs.hero_of(1).level == my_level and rs.hero_of(1).type == "voltcactus", "with my own hero at the same level")
	rs.lives = 0
	rs.wave_active = true
	await secs(0.5)
	check(SG.info().is_empty(), "losing the game removes the save")
	main.queue_free()
	await secs(0.3)
	D.free()
	print("save tests: %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
