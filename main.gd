extends Node
## Game flow and local controls: title menu -> (LAN lobby) -> game.
## Walking is predicted on this computer so it feels instant; everything else
## comes from the simulation (run here for solo / LAN host, or received from
## the LAN host when joining).

const MOVE_SEND_INTERVAL := 0.05

var world: WorldView
var hud: Hud
var couch: Couch  # controllers: couch co-op players on this computer
var menu: Menu
var host: GameHost  # set when this computer runs the simulation
var net: Node  # NetHost or NetClient while in a LAN game

var my_id := 1
var snap: Dictionary = {}
var playing := false
var my_pos = null
var my_hero_id := -1
var my_speed := 195.0
var move_path: Array = []
var last_sent := {"p": Vector2.ZERO, "at": -10.0}
var clock := 0.0
var selected_gadget := "sentry"
var branch_arm_until := 0.0
var ghost_until := 0.0  # show where the selected tower would go until this time
const TARGET_MODES := ["first", "strong", "close", "last"]
var last_cfg: Dictionary = {}
var snap_at := 0.0
var snap_gap := 1.0 / 30.0

# command-line options for testing: --solo --demo --hero=x --map=x --diff=x --mode=x
# --bots=N --warp=SECONDS --shot=FILE.png --shot-after=SECONDS --quit
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_window().title = "Bloom Bastion Heroes"
	get_tree().auto_accept_quit = false  # closing the window goes through quit_game()
	if args.has("netcheck") or args.has("shot") or args.has("demo") or args.has("warp"):
		Profile.path = "user://test_profile.cfg"  # test runs never change your real profile
	world = WorldView.new()
	add_child(world)
	# a soft vignette frames the garden (under the HUD)
	var vig_layer := CanvasLayer.new()
	vig_layer.layer = 2
	add_child(vig_layer)
	var vig := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_offset(0, 0.62)
	grad.set_color(1, Color(0.0, 0.03, 0.01, 0.38))
	grad.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig_layer.add_child(vig)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Hud.new()
	hud.theme = UiKit.theme()
	hud_layer.add_child(hud)
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu = Menu.new()
	menu_layer.add_child(menu)
	couch = Couch.new()
	couch.main = self
	couch.p1_pad = bool(Profile.load_profile().get("padP1", false))
	add_child(couch)
	hud.couch = couch
	hud.world = world
	menu.play.connect(_on_menu_play)
	menu.settings_changed.connect(apply_settings)
	apply_settings()
	menu.leave.connect(show_menu)
	var cfg := Profile.load_profile()
	cfg.merge({"hero": args.get("hero", cfg.hero), "map": args.get("map", cfg.map), "diff": args.get("diff", cfg.diff), "name": args.get("name", cfg.name),
		"gameMode": args.get("mode", cfg.gameMode), "bots": int(args.get("bots", "2" if args.has("demo") else str(cfg.bots)))}, true)
	if args.has("solo") or args.has("demo"):
		start_local(cfg, args.has("demo"))
	elif args.has("host"):
		cfg.kind = "host"
		cfg.bind = String(args.get("bind", ""))
		_on_menu_play(cfg)
	elif args.has("join"):
		cfg.kind = "join"
		cfg.address = String(args.join)
		_on_menu_play(cfg)
	else:
		show_menu()
	if args.has("shot"):
		_screenshot_later(String(args.shot), float(args.get("shot-after", "3")))
	if args.has("netcheck"):
		_netcheck(float(args.netcheck))
	if args.has("perflog"):
		_perflog()


func show_menu() -> void:
	_leave_game()
	couch.reset()
	couch.p1_pad = bool(Profile.load_profile().get("padP1", false))
	menu.show_title()
	hud.visible = false
	Audio.set_music_state("menu")
	Sprites.warm_up()
	start_attract()


## A bot-only game plays behind the title screen
var attract := false
var _tree_low_warned := false


func start_attract() -> void:
	attract = true
	hud.visible = false
	world.reset()
	world.mute_audio = true
	var clash := randf() < 0.35
	host = GameHost.new(clash)
	add_child(host)
	host.snapshot_ready.connect(_on_snapshot)
	my_id = -1
	var types: Array = GameData.HERO_ORDER.duplicate()
	types.shuffle()
	for i in 4:
		host.add_player(100 + i, ["Sprout", "Clover", "Pip", "Juniper"][i], types[i], true, ["flower", "wizard", "party", "propeller"][i], ["ladybug", "bee", "bunny", "dragon"][i])
	var maps: Array = ["meadow", "river", "courtyard", "hollow", "frosty"]
	host.start(maps[randi() % maps.size()], "easy", "adventure")
	host.sim.auto_wave = true
	host.sim.start_wave()
	for i in 30 * (150 if clash else 25):
		host.sim.step(SimWorld.TICK)
	host.sim.events.clear()
	world.my_owner = 100
	world.zoom = 0.85


func _leave_game() -> void:
	playing = false
	attract = false
	if host:
		host.queue_free()
		host = null
	if net:
		net.close()
		net.queue_free()
		net = null
	snap = {}
	hud.snap = {}
	my_pos = null
	world.my_pos = null


func _on_menu_play(cfg: Dictionary) -> void:
	match String(cfg.kind):
		"solo":
			start_local(cfg, false)
		"host":
			_leave_game()
			net = NetHost.new()
			add_child(net)
			net.main = self
			if not net.open(cfg):
				net.queue_free()
				net = null
				show_menu()
				menu.show_error("Could not start a LAN game (port %d busy?)" % NetHost.PORT)
				return
			menu.show_lobby(net, true)
			start_attract()
		"join":
			_leave_game()
			net = NetClient.new()
			add_child(net)
			net.main = self
			net.join(cfg)
			menu.show_lobby(net, false)
			start_attract()


## Solo (or a LAN host's game, called by NetHost with its player list)
func start_local(cfg: Dictionary, demo := false, lan_players: Array = []) -> void:
	if not net:
		_leave_game()
	else:
		playing = false
		attract = false
		if host:
			host.queue_free()
			host = null
	world.zoom = 1.0
	world.reset()
	last_cfg = cfg
	host = GameHost.new(String(cfg.get("gameMode", "")) == "clash")
	add_child(host)
	host.snapshot_ready.connect(_on_snapshot)
	my_id = 1
	host.add_player(my_id, String(cfg.get("name", "Player")), String(cfg.hero), demo, String(cfg.get("hat", "none")), String(cfg.get("pet", "none")))
	for p in lan_players:
		host.add_player(int(p.id), String(p.name), String(p.hero), false, String(p.get("hat", "none")), String(p.get("pet", "none")))
	var used := [String(cfg.hero)]
	for p in lan_players:
		used.append(String(p.hero))
	var sofa := couch.players()  # couch players stay in for "play again"
	for pid in sofa:
		var cp: Dictionary = sofa[pid]
		host.add_player(pid, String(cp.name), String(cp.hero), false, String(cp.hat), String(cp.pet))
		used.append(String(cp.hero))
	for i in mini(int(cfg.get("bots", 0)), 3 - lan_players.size() - sofa.size()):
		var pick := ""
		for t in GameData.HERO_ORDER:
			if not t in used:
				pick = t
				break
		if pick == "":
			pick = GameData.HERO_ORDER[randi() % GameData.HERO_ORDER.size()]
		used.append(pick)
		host.add_player(100 + i, ["Sprout", "Clover", "Pip", "Juniper"][i % 4], pick, true, ["flower", "cap", "party", "propeller"][i % 4], ["ladybug", "bee", "bunny", "snail"][i % 4])
	if net:
		net.attach_host(host)
	_begin_play()
	host.start(String(cfg.map), String(cfg.diff), String(cfg.gameMode))
	host.sim.kid_assist = bool(Profile.load_profile().get("kidAssist", false))
	if demo:
		host.sim.auto_wave = true
		host.sim.start_wave()
	if args.has("wave"):  # test-only: jump to a wave
		host.sim.wave = int(args.wave) - 1
		host.sim.start_next_wave()
		host.sim.auto_wave = true
	if args.has("warp"):
		var t := float(args.warp)
		host.sim.auto_wave = true
		host.sim.start_wave()
		while t > 0 and host.sim.phase == "playing":
			host.sim.step(SimWorld.TICK)
			host.sim.events.clear()
			t -= SimWorld.TICK
		host.sim.auto_wave = demo


## Called when a LAN client's game starts
func start_remote(id: int) -> void:
	if host:
		host.queue_free()
		host = null
	attract = false
	world.reset()
	world.remote_interp = true
	world.zoom = 1.0
	my_id = id
	_begin_play()


func _begin_play() -> void:
	hud.menu_open = false
	hud.new_unlocks = []
	hud.next_challenge = ""
	menu.hide_all()
	hud.visible = true
	playing = true
	my_pos = null
	my_hero_id = -1
	move_path = []
	hud.my_owner = my_id
	hud.is_host = host != null
	world.my_owner = my_id
	world.mute_audio = false
	_tree_low_warned = false
	var m_id := "valley" if String(last_cfg.get("gameMode", "")) == "clash" else String(last_cfg.get("map", "meadow"))
	Audio.set_music_state("calm", m_id)
	hud.banner("Defend the Bloom Tree!", "WASD or click to walk · Space starts a wave · Q special · Shift leaps")
	_tips_started_at = clock
	if not args.has("warp"):
		Audio.say("ann_welcome", -1, true)


# ---------------------------------------------------------------------------
# Snapshots (from the local host or the network)
# ---------------------------------------------------------------------------
func _on_snapshot(s: Dictionary) -> void:
	snap_gap = lerpf(snap_gap, clampf(clock - snap_at, 0.01, 0.2), 0.2)
	snap_at = clock
	snap = s
	world.push_snapshot(s)
	hud.snap = s
	_sync_my_hero()
	_unlock_from_snapshot(s)
	if playing and not attract:
		_update_music_from_snap(s)
	for e in s.get("events", []):
		_my_event(e)


func _update_music_from_snap(s: Dictionary) -> void:
	var ph := String(s.get("phase", "playing"))
	if ph != "playing":
		Audio.set_music_state("silent")
		return
	var mid := String(s.get("map", "meadow"))
	if s.has("clash"):
		var cl: Dictionary = s.clash
		var boss_on: bool = int(cl.get("elderT", 0)) > 0
		if not boss_on:
			for ft in cl.get("foeTowers", []):
				if ft.get("core", false) and not ft.get("shield", true):
					boss_on = true
					break
		Audio.set_music_state("boss" if boss_on else "wave", mid)
		return
	if not _tree_low_warned and float(s.get("maxLives", 1)) > 0 and float(s.get("lives", 1)) / float(s.get("maxLives", 1)) <= 0.30:
		_tree_low_warned = true
		Audio.say("ann_tree_low", -1, true)
	var has_boss := false
	for e in s.get("enemies", []):
		if e.get("boss", false):
			has_boss = true
			break
	if has_boss:
		Audio.set_music_state("boss", mid)
	elif s.get("waveActive", false):
		Audio.set_music_state("wave", mid)
	else:
		Audio.set_music_state("calm", mid)


## Events that came on their own (reliably) over the LAN
func handle_events(list: Array) -> void:
	for e in list:
		if typeof(e) == TYPE_DICTIONARY:
			world.on_event(e)
			_my_event(e)


## New pests and bosses get a warning card the first time they show up
func _pest_intro(w: int) -> void:
	if snap.has("clash") or attract:
		return
	var intro: Dictionary = GameData.enemies.get("newPestIntro", {})
	for type in intro:
		if int(intro[type]) == w:
			hud.pest_card(String(type))
			return
	var plan: Dictionary = GameData.plan_wave(w, GameData.DIFFICULTIES.get(snap.get("difficulty", "normal"), {}), maxi(1, snap.get("heroes", []).size()), bool(snap.get("endless", false)), "")
	for g in plan.groups:
		if g.boss:
			hud.pest_card(String(g.type))
			return


# ---------------------------------------------------------------------------
# Hats & pets you earn (saved on this computer; everyone in the game earns them)
# ---------------------------------------------------------------------------
func _earn(kind: String, id: String) -> void:
	if attract or not playing or not Profile.unlock(kind, id):
		return
	for x in GameData.cosmetics[kind]:
		if x.id == id:
			hud.new_unlocks.append("%s %s" % [x.icon, x.name])
			hud.banner("🎉 New %s: %s %s!" % ["hat" if kind == "hats" else "pet", x.icon, x.name], "Pick it on the title screen", Color("f0abfc"), 3.5)
			Audio.play_sfx("chest_open", 0.0, 0.0, 300)


func _unlock_from_event(e: Dictionary) -> void:
	if attract or not playing:
		return
	var hard: bool = String(snap.get("difficulty", "")) in ["hard", "nightmare"]
	match String(e.type):
		"victory":
			_earn("pets", "bunny")
			if snap.has("clash"):
				_earn("hats", "helmet")
				if hard:
					_earn("hats", "thorncrown")
			else:
				_earn("hats", "crown")
				if hard:
					_earn("hats", "goldcrown")
			if hard:
				_earn("pets", "dragon")
			if String(snap.get("difficulty", "")) == "nightmare":
				_earn("hats", "firecrown")
		"enemy_pop":
			if e.get("boss", false) and not snap.has("clash"):
				_earn("hats", "pirate")
		"level_up":
			if int(e.get("level", 0)) >= 20:
				_earn("hats", "wizard")
		"wave_clear":
			if snap.get("endless", false):
				if int(e.wave) >= 15:
					_earn("pets", "snail")
				if int(e.wave) >= 30:
					_earn("hats", "propeller")
		"camp_down":
			if String(e.get("kind", "")) == "rumbletoad":
				_earn("pets", "froggy")
		"hero_upgraded":
			if int(e.get("tier", 0)) >= 3:
				var tw: Dictionary = GameData.TOWERS.get(String(e.get("hero", "")), {})
				world.evolve_fx(Vector2(e.x, e.y), int(e.tier))
				if int(e.get("owner", -1)) == my_id:
					hud.banner("✨ Evolved: %s!" % e.label, "%s, path %s tier %d" % [tw.get("name", ""), e.path, int(e.tier)], Color("fde047"), 3.0)
				Audio.play_sfx("level_up", 0.0, 0.0, 200)
				Audio.say_hero(String(e.get("hero", "")), "evolve", int(e.get("owner", -1)))


func _unlock_from_snapshot(s: Dictionary) -> void:
	if attract or not playing:
		return
	for p in s.get("players", []):
		if int(p.get("pops", 0)) >= 250:
			_earn("hats", "party")
		if int(p.get("reactions", 0)) >= 30:
			_earn("pets", "butterfly")
		if int(p.get("towersDown", 0)) >= 5:
			_earn("pets", "hedgehog")


## After a win: the next map, or the next difficulty after the last map
const MAP_ORDER := ["meadow", "river", "courtyard", "hollow", "frosty"]
const DIFF_ORDER := ["easy", "normal", "hard", "nightmare"]


func _next_cfg() -> Dictionary:
	var c := last_cfg.duplicate()
	if String(c.get("gameMode", "")) == "clash":
		var di := DIFF_ORDER.find(String(c.diff))
		if di < 0 or di >= DIFF_ORDER.size() - 1:
			return {}
		c.diff = DIFF_ORDER[di + 1]
		return c
	var mi := MAP_ORDER.find(String(c.map))
	if mi >= 0 and mi < MAP_ORDER.size() - 1:
		c.map = MAP_ORDER[mi + 1]
	else:
		var di := DIFF_ORDER.find(String(c.diff))
		if di < 0 or di >= DIFF_ORDER.size() - 1:
			return {}
		c.map = MAP_ORDER[0]
		c.diff = DIFF_ORDER[di + 1]
	return c


func _next_challenge() -> void:
	var c := _next_cfg()
	if c.is_empty():
		return
	var prof := Profile.load_profile()
	prof.map = c.map
	prof.diff = c.diff
	Profile.save_profile(prof)
	if net and net is NetHost:
		net.cfg.map = c.map
		net.cfg.diff = c.diff
		net.restart()
	else:
		start_local(c)


func _my_hero() -> Dictionary:
	for h in snap.get("heroes", []):
		if h.owner == my_id:
			return h
	return {}


func _sync_my_hero() -> void:
	var h := _my_hero()
	if h.is_empty() or _is_bot_me():
		my_pos = null
		world.my_pos = null
		return
	my_speed = GameData.compute_hero_stats(h.type, h.tierA, h.tierB, h.cards, h.level, h.buffs).moveSpeed
	var hp := Vector2(h.x, h.y)
	if my_hero_id != h.id or my_pos == null:
		my_hero_id = h.id
		my_pos = hp
		last_sent = {"p": hp, "at": clock}
	else:
		var recently: bool = clock - last_sent.at < 0.4
		if hp.distance_to(my_pos) > (90.0 if recently else 30.0) and hp.distance_to(last_sent.p) > 30:
			my_pos = hp
	world.my_pos = my_pos


func _is_bot_me() -> bool:
	for p in snap.get("players", []):
		if p.id == my_id:
			return p.bot
	return false


func _my_event(e: Dictionary) -> void:
	couch.on_event(e)
	_unlock_from_event(e)
	var mine: bool = int(e.get("owner", -999)) == my_id
	match String(e.type):
		"dash", "teleport":
			if mine and my_pos != null:
				if e.type == "dash":
					world.slide_from(my_pos, Vector2(e.x, e.y))
				my_pos = Vector2(e.x, e.y)
				move_path = []
				last_sent = {"p": my_pos, "at": clock}
		"wave_start":
			var tw := ""
			if String(e.get("twist", "")) != "":
				tw = "🌀 " + String(GameData.TWISTS.get(e.twist, {}).get("name", ""))
			var wn := int(e.wave)
			hud.banner("Wave %d" % wn, tw if tw != "" else "Here they come!", Color("fde047"))
			_pest_intro(wn)
			if not attract:
				Audio.play_sfx("wave_start")
				if wn == 20 or (wn >= 25 and wn % 5 == 0):
					Audio.play_sfx("boss_warn")
					Audio.say("boss_monarch", -1, true)
				elif wn == 10 or (wn >= 15 and wn % 5 == 0):
					Audio.play_sfx("boss_warn")
					Audio.say("boss_zep", -1, true)
				elif wn == 5:
					Audio.say("ann_camo", -1, true)
				elif wn == 11:
					Audio.say("ann_mole", -1, true)
				elif wn == 1 or wn % 4 == 0:
					Audio.say("ann_wave")
		"wave_clear":
			var streak := int(e.get("perfect", 0))
			var sub := "+%d XP · +%d acorns" % [int(e.bonus), int(e.acorns)]
			if int(e.get("regrow", 0)) > 0:
				sub += " · 🌳 +%d lives" % int(e.regrow)
			if streak > 0:
				hud.banner("✨ Perfect wave %d!%s" % [int(e.wave), ("  ×%d in a row" % streak) if streak > 1 else ""], sub, Color("fde047"))
			else:
				hud.banner("Wave %d cleared!" % int(e.wave), sub, Color("86efac"))
			if not attract:
				Audio.play_sfx("wave_clear")
				if int(e.wave) % 5 == 0:
					Audio.say("ann_clear", -1, true)
		"milestone":
			hud.banner("Milestone!", "+5 lives and a bonus card for everyone", Color("f0abfc"))
			if not attract:
				Audio.say("ann_milestone", -1, true)
		"sleep_dust":
			if not attract:
				Audio.say("ann_sleep")
		"gadget_fail":
			if mine:
				hud.toast(String(e.reason), Color("fca5a5"))
				if not attract:
					Audio.play_sfx("error")
		"gadget_choose":
			if mine:
				var d: Dictionary = GameData.GADGETS[e.kind]
				branch_arm_until = clock + 5.0
				hud.toast("Pick a special power: U = %s %s, Y = %s %s" % [d.branches[0].icon, d.branches[0].name, d.branches[1].icon, d.branches[1].name], Color("fde047"), 5.0)
		"gadget_placed":
			if mine:
				hud.toast("%s built!" % GameData.GADGETS[e.kind].name, Color("86efac"), 2.0)
		"gadget_upgraded":
			if mine:
				hud.toast("Upgraded to level %d %s" % [int(e.level), String(e.get("branchIcon", ""))], Color("fde047"), 2.5)
		"gadget_sold":
			if mine:
				hud.toast("Sold for %d acorns" % int(e.refund), Color("fcd34d"), 2.0)
		"eshop":
			var what: String = {"life": "a Bloom Tree life 🌳", "overclock": "Overclock ⚡ (towers 25% faster for a minute)", "mystery": "a mystery power-up 🎁"}.get(String(e.item), "")
			hud.toast("%s bought %s" % [e.name, what], Color("fde047"), 3.0)
		"chest_drop":
			_tip("chest", "🎁 A treasure chest! Walk over it: everyone gets a bonus.")
		"level_up":
			if mine:
				hud.toast("Level %d! Pick a card with 1, 2 or 3" % int(e.level), Color("fde047"), 3.0)
				_tip("cards", "⭐ Level-up cards make your hero stronger. Press 1, 2 or 3, or click one. C hides them for a moment.")
				if not attract:
					Audio.say_hero(String(_my_hero().get("type", "")), "level", my_id)
		"combo":
			hud.banner(String(e.get("name", "TEAM COMBO!")), String(e.get("desc", "")), Color("f0abfc"), 2.4)
		"chest_open":
			if int(e.get("bonus", 0)) > 0:
				hud.toast("🎁 %s opened a chest: +%d card%s for everyone!" % [e.name, int(e.bonus), "s" if int(e.bonus) > 1 else ""], Color("fde047"), 3.0)
			else:
				hud.toast("🎁 %s opened a chest: +%d XP and +%d acorns for everyone!" % [e.name, int(e.xp), int(e.acorns)], Color("fde047"), 3.0)
		"boss_enrage":
			hud.banner("👑 %s is ENRAGED!" % e.get("name", "The boss"), "Faster, and it calls helpers more often. Focus fire!", Color("f87171"), 3.0)
		"victory", "game_over":
			if e.type == "victory" and host and not attract:
				var nc := _next_cfg()
				if not nc.is_empty():
					var label := "Next: %s →" % String(GameData.maps.maps.get(nc.map, {}).get("name", nc.map)) if nc.get("map", "") != last_cfg.get("map", "") else "Next: %s →" % String(GameData.DIFFICULTIES.get(nc.diff, {}).get("short", nc.diff))
					hud.next_challenge = label
			if playing and not attract:
				Profile.record_game(e.type == "victory", bool(snap.endless), int(snap.wave), String(snap.get("map", "")), String(snap.get("difficulty", "")), String(snap.get("mode", "")))
				Audio.play_sfx("victory" if e.type == "victory" else "game_over", 0.0, 0.0, 500)
				Audio.say("ann_victory" if e.type == "victory" else "ann_gameover", -1, true)
		# --- Garden Clash
		"clash_start":
			hud.banner("⚔️ Garden Clash!", "Push the lanes with your Sproutlings and smash the Thorn Heart!", Color("f0abfc"), 4.0)
			if not attract:
				Audio.play_sfx("wave_start")
				Audio.say("ann_welcome", -1, true)
		"rival_spawn":
			if e.get("first", false):
				hud.feed("👑 %s joins the battle (Lv %d)" % [e.name, int(e.lvl)], Color("fca5a5"))
		"rival_down":
			hud.feed("👑 %s knocked out%s! Back in %ds" % [e.name, (" by " + String(e.by)) if String(e.by) != "" else "", int(e.back)], Color("fde047"))
		"struct_down":
			var foe: bool = e.team == "foe"
			if e.get("core", false):
				hud.banner("💜 The Thorn Heart is broken!", "", Color("f0abfc"))
			else:
				hud.feed(("💥 %s smashed%s!" if foe else "😢 Our %s fell!") % ([e.name, (" by " + String(e.by)) if String(e.get("by", "")) != "" else ""] if foe else [e.name]), Color("f5d0fe") if foe else Color("fca5a5"))
				if foe and int(e.get("tier", 0)) == 3:
					hud.banner("Gate smashed!", "Super Sprouts march down that lane now", Color("f0abfc"))
					if not attract:
						Audio.say("ann_gate_down", -1, true)
				elif foe and e.get("heart_open", false):
					if not attract:
						Audio.say("ann_heart_open", -1, true)
		"hero_down":
			hud.feed("💫 %s was knocked out%s" % [e.name, (" by " + String(e.by)) if String(e.by) != "" else ""], Color("fca5a5"))
			if mine:
				hud.banner("Knocked out!", "Back in %ds, or a friend can stand next to you to revive you" % int(e.respawn), Color("fca5a5"), 3.0)
		"revive":
			hud.feed("💚 %s revived %s" % [e.by, e.name], Color("86efac"))
		"tower_alert":
			hud.toast("⚠️ A %s is under attack and nobody is there!" % ("Bloom Gate" if e.kind == "gate" else ("Tree Guardian" if e.kind == "guardian" else ("Bloom Tree" if e.kind == "tree" else "Bloom Tower"))), Color("fca5a5"), 4.0)
			if not attract:
				Audio.say("ann_tower_alert", -1, true)
		"camp_up":
			if e.get("epic", false):
				hud.feed("🐸 %s woke up in the jungle!" % e.name, Color("86efac"))
				if not attract:
					Audio.say("ann_toad_up", -1, true)
		"camp_down":
			if e.get("epic", false):
				hud.banner("🐸 Toad Power!", "Your Sproutlings grow big and strong for a while", Color("86efac"))
				if not attract:
					Audio.say("ann_elder_power" if e.get("elder", false) else "ann_toad_power", -1, true)
		"gate_regrow":
			hud.feed(("🌱 Our Bloom Gate grew back" if e.side == "ally" else "🌿 A Thorn Gate grew back"), Color("bbf7d0"))
		"recall_cancel":
			if mine:
				hud.toast("Going home stopped: stand still for 3 seconds", Color("fca5a5"), 2.0)
		"recall_start":
			if mine:
				move_path = []
		"item_bought":
			if mine:
				var info: Dictionary = GameData.clash_item(String(e.item))
				hud.toast("%s %s!" % [info.get("icon", "🧃"), info.get("name", "Berry Juice")], Color("fde047"), 2.0)
		"powerup_get":
			if mine:
				var pu: Dictionary = GameData.POWERUPS.get(e.get("kind", ""), {})
				if not pu.is_empty():
					hud.toast("%s %s!" % [pu.get("icon", ""), pu.get("name", "")], Color("fde047"), 2.5)


# ---------------------------------------------------------------------------
# Sending actions
# ---------------------------------------------------------------------------
func send(a: Dictionary) -> void:
	if host:
		host.apply(my_id, a)
	elif net and net.has_method("send_action"):
		net.send_action(a)


func _process(delta: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(delta)
	PerfStats.add("main update" , Time.get_ticks_usec() - _pt0)


func _process_inner(delta: float) -> void:
	clock += delta
	if attract and host and host.sim.phase != "playing":
		host.queue_free()
		host = null
		start_attract()
	if host:
		world.tick_alpha = host.alpha()
	else:
		world.tick_alpha = clampf((clock - snap_at) / maxf(snap_gap, 0.016), 0, 1.5)
	_update_movement(delta)
	if playing and int(clock * 2) != int((clock - delta) * 2):
		_check_tips()
	if net and net is NetClient and playing:
		world.snap_dt = snap_gap
		hud.net_note = "📶 LAN: %d updates a second" % roundi(1.0 / maxf(snap_gap, 0.01))
	else:
		world.snap_dt = SimWorld.TICK
		hud.net_note = ""
	var preview := playing and not snap.is_empty() and not snap.has("clash") and (clock < ghost_until or hud.over_build_bar())
	world.ghost = selected_gadget if preview else ""
	hud.selected_gadget = selected_gadget
	# frame every local hero (couch co-op) with the camera
	var follow: Array = []
	if playing and couch:
		var sofa := couch.players()
		for x in snap.get("heroes", []):
			if sofa.has(x.owner) and not x.get("dead", false):
				follow.append(x.id)
	world.follow_ids = follow
	hud.show_stats = playing and (Input.is_physical_key_pressed(KEY_TAB) or args.has("stats"))


func _move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if v == Vector2.ZERO and couch:
		v = couch.p1_stick()  # a controller playing as P1
	return v


func _update_movement(dt: float) -> void:
	if not playing or my_pos == null or snap.is_empty() or snap.phase != "playing" or snap.paused:
		return
	if _my_hero().get("dead", false):
		move_path = []
		return
	var dir := _move_input()
	var step: float = my_speed * float(snap.speed) * dt
	if dir != Vector2.ZERO:
		move_path = []
	elif move_path.size() > 0:
		var wp: Vector2 = move_path[0]
		var d: float = wp.distance_to(my_pos)
		while d < 4 and move_path.size() > 1:
			move_path.pop_front()
			wp = move_path[0]
			d = wp.distance_to(my_pos)
		if d < 3:
			move_path = []
		else:
			dir = wp - my_pos
			step = minf(step, d)
	if dir != Vector2.ZERO:
		var n: Vector2 = my_pos + dir.normalized() * step
		var map_id: String = snap.map
		if GameData.is_walkable(map_id, n.x, n.y):
			my_pos = n
		elif GameData.is_walkable(map_id, n.x, my_pos.y):
			my_pos = Vector2(n.x, my_pos.y)
		elif GameData.is_walkable(map_id, my_pos.x, n.y):
			my_pos = Vector2(my_pos.x, n.y)
		else:
			move_path = []
		world.my_pos = my_pos
	if clock - last_sent.at > MOVE_SEND_INTERVAL and my_pos.distance_to(last_sent.p) > 0.5:
		send({"t": "move", "x": snappedf(my_pos.x, 0.1), "y": snappedf(my_pos.y, 0.1)})
		last_sent = {"p": my_pos, "at": clock}


func walk_to(target: Vector2) -> void:
	if my_pos == null or snap.is_empty():
		return
	var tx := clampf(target.x, 16, GameData.W - 16)
	var ty := clampf(target.y, 16, GameData.H - 16)
	# clicking near a Sun orb walks right onto it
	for s in snap.get("suns", []):
		if Vector2(s.x, s.y).distance_to(target) < 40:
			tx = s.x
			ty = s.y
	move_path = GameData.find_path(snap.map, my_pos.x, my_pos.y, tx, ty)
	if move_path.size() > 0:
		world.click_marker(move_path[move_path.size() - 1])


func dash() -> void:
	var h := _my_hero()
	if h.is_empty() or my_pos == null:
		return
	if h.dashCd > 0:
		hud.toast("💨 Leaf Leap recharging (%ds)" % ceili(h.dashCd), Color("fca5a5"), 1.5)
		return
	var dir := _move_input()
	if dir == Vector2.ZERO and move_path.size() > 0:
		dir = Vector2(move_path[0]) - my_pos
	if dir == Vector2.ZERO:
		dir = world.get_global_mouse_position() - my_pos
	if dir.length() < 1:
		dir = Vector2(h.facing, 0)
	send({"t": "move", "x": snappedf(my_pos.x, 0.1), "y": snappedf(my_pos.y, 0.1)})
	send({"t": "dash", "dx": dir.x, "dy": dir.y})
	move_path = []


func upgrade_key(branch: int) -> void:
	var g := _my_gadget_near()
	if g.is_empty():
		if branch == 0:
			send({"t": "upgrade"})
		return
	var def: Dictionary = GameData.GADGETS[g.kind]
	if def.has("branches") and int(g.level) == 2:
		if branch == 1 or clock < branch_arm_until:
			branch_arm_until = 0.0
			send({"t": "upgrade", "id": g.id, "branch": branch})
		else:
			send({"t": "upgrade", "id": g.id})  # asks the sim to offer the choice
		return
	if branch == 0:
		send({"t": "upgrade", "id": g.id})


func _my_gadget_near() -> Dictionary:
	var best := {}
	var bd := 110.0
	if my_pos == null:
		return best
	for g in snap.get("gadgets", []):
		if g.owner != my_id:
			continue
		var d: float = Vector2(g.x, g.y).distance_to(my_pos)
		if d <= bd:
			bd = d
			best = g
	return best


func do_hud_action(a: Dictionary) -> void:
	match String(a.t):
		"mute":
			var m := Audio.toggle_mute()
			hud.toast("🔇 Sound Muted" if m else "🔊 Sound On", Color("fde047"), 1.5)
			if not m:
				Audio.play_sfx("ui_click")
		"select_gadget":
			Audio.play_sfx("ui_click", -3.0)
			if selected_gadget == a.kind:
				send({"t": "plant", "kind": selected_gadget})
				ghost_until = clock + 1.2
			else:
				ghost_until = clock + 3.0
			selected_gadget = a.kind
		"target":
			Audio.play_sfx("ui_click", -3.0)
			cycle_target()
		"resume":
			Audio.play_sfx("ui_click")
			close_pause_menu()
		"emote":
			hud.emote_open = false
			send(a)
		"eshop":
			Audio.play_sfx("ui_click", -3.0)
			send(a)
		"hide_cards":
			hud.cards_hidden = true
		"show_cards":
			hud.cards_hidden = false
		"set_shake":
			Audio.play_sfx("ui_click", -3.0)
			Profile.set_value("shake", Profile.next_shake(float(Profile.load_profile().shake)))
			apply_settings()
		"set_dmg":
			Audio.play_sfx("ui_click", -3.0)
			Profile.set_value("dmgNums", Profile.next_dmg(String(Profile.load_profile().dmgNums)))
			apply_settings()
		"fullscreen":
			toggle_fullscreen()
		"dash_ui":
			dash()
		"again":
			Audio.play_sfx("ui_click")
			if host and not net:
				start_local(last_cfg)
			elif net and net.has_method("restart"):
				net.restart()
		"next":
			Audio.play_sfx("ui_click")
			_next_challenge()
		"menu":
			Audio.play_sfx("ui_click")
			hud.menu_open = false
			show_menu()
		"card":
			Audio.play_sfx("card_pick")
			send(a)
		_:
			Audio.play_sfx("ui_click", -4.0)
			send(a)


func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			world.zoom_by(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			world.zoom_by(1.0 / 1.1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and mb.alt_pressed):
			# ping: "look here!" on everyone's screen
			if not snap.is_empty() and snap.phase == "playing" and not hud.over_ui(hud.get_local_mouse_position()):
				var wp: Vector2 = world.get_global_mouse_position()
				send({"t": "ping", "x": wp.x, "y": wp.y})
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			var a := hud.click(hud.get_local_mouse_position())
			var mp := hud.get_local_mouse_position()
			if a.is_empty() and hud.minimap_rect.has_point(mp) and not snap.is_empty() and snap.phase == "playing" and not snap.paused:
				# click the minimap: walk there
				var k := (mp - hud.minimap_rect.position) / hud.minimap_rect.size
				walk_to(Vector2(k.x * GameData.W, k.y * GameData.H))
				get_viewport().set_input_as_handled()
				return
			if not a.is_empty():
				do_hud_action(a)
			elif not hud.over_ui(hud.get_local_mouse_position()) and not snap.is_empty() and snap.phase == "playing" and not snap.paused:
				walk_to(world.get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).physical_keycode
	if snap.is_empty():
		return
	if snap.phase != "playing":
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			do_hud_action({"t": "again"})
		elif k == KEY_ESCAPE:
			show_menu()
		return
	if hud.menu_open:
		if k == KEY_ESCAPE or k == KEY_P:
			close_pause_menu()
		elif k == KEY_M:
			do_hud_action({"t": "mute"})
		return
	match k:
		KEY_P:
			send({"t": "pause"})
		KEY_M:
			do_hud_action({"t": "mute"})
		KEY_ESCAPE:
			open_pause_menu()
			return
		KEY_Z:
			world.toggle_overview()
		KEY_EQUAL, KEY_KP_ADD:
			world.zoom_by(1.15)
		KEY_MINUS, KEY_KP_SUBTRACT:
			world.zoom_by(0.87)
	if snap.paused:
		return
	if hud.emote_open and k >= KEY_1 and k <= KEY_5:
		var em: Array = GameData.cosmetics.emotes
		if k - KEY_1 < em.size():
			do_hud_action({"t": "emote", "id": em[k - KEY_1].id})
		return
	match k:
		KEY_V:
			hud.emote_open = not hud.emote_open
		KEY_N:
			hud.minimap_on = not hud.minimap_on
		KEY_C:
			hud.cards_hidden = not hud.cards_hidden
		KEY_SPACE:
			if not snap.waveActive:
				send({"t": "wave"})
		KEY_SHIFT:
			dash()
		KEY_Q, KEY_E:
			send({"t": "special"})
		KEY_H, KEY_B:
			send({"t": "home"})
			if not snap.has("clash"):
				move_path = []
		KEY_R:
			if snap.has("clash"):
				send({"t": "potion"})
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			# 1-3 pick a level-up card; with no cards waiting, 1-6 pick a tower
			var cards: bool = int(_my_hero().get("pending", 0)) > 0 and _my_hero().get("offer", []).size() > 0
			if cards and k <= KEY_3:
				Audio.play_sfx("card_pick")
				send({"t": "card", "i": k - KEY_1})
			elif not cards and not snap.has("clash") and k - KEY_1 < GameData.GADGET_ORDER.size():
				pick_gadget(GameData.GADGET_ORDER[k - KEY_1])
		KEY_F:
			send({"t": "plant", "kind": selected_gadget})
			ghost_until = clock + 1.2
		KEY_G when not snap.has("clash"):
			var i := GameData.GADGET_ORDER.find(selected_gadget)
			pick_gadget(GameData.GADGET_ORDER[(i + 1) % GameData.GADGET_ORDER.size()])
		KEY_T when not snap.has("clash"):
			cycle_target()
		KEY_U:
			upgrade_key(0)
		KEY_Y:
			upgrade_key(1)
		KEY_X:
			send({"t": "sell"})
		KEY_TAB:
			pass


## Screen shake, damage numbers, fullscreen and audio from the profile
func apply_settings() -> void:
	var prof := Profile.load_profile()
	Audio.apply_settings()
	world.shake_mult = float(prof.shake)
	world.dmg_mode = String(prof.dmgNums)
	if DisplayServer.get_name() != "headless":
		var fs: bool = prof.fullscreen
		var now := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if fs != now:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)


func toggle_fullscreen() -> void:
	Profile.set_value("fullscreen", not bool(Profile.load_profile().fullscreen))
	apply_settings()


## F11 works everywhere, even on the title screen
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# First-time tips: each shows once per computer, at the moment it's useful
# ---------------------------------------------------------------------------
var _tips_started_at := 0.0


func _tip(id: String, text: String) -> void:
	if attract or not playing or args.has("warp") or args.has("demo"):
		return
	var prof := Profile.load_profile()
	var seen: Array = Array(prof.get("tipsSeen", []))
	if seen.has(id):
		return
	seen.append(id)
	Profile.set_value("tipsSeen", seen)
	hud.toast("💡 " + text, Color("bae6fd"), 6.0)


func _check_tips() -> void:
	if not playing or snap.is_empty() or snap.phase != "playing":
		return
	var t := clock - _tips_started_at
	if snap.has("clash"):
		if t > 4:
			_tip("clash", "⚔️ Walk down a lane WITH your Sproutlings. Smash the Thorn Towers, then the Thorn Heart. B goes home to heal and shop.")
		return
	if t > 5 and int(snap.wave) == 0 and not snap.waveActive:
		_tip("start", "▶ Press Space (or the green button) to start the first wave.")
	if int(snap.wave) >= 1 and not snap.waveActive:
		_tip("build", "🏗️ Build a tower: press 1–6 to pick one, then F where you stand. Towers cost acorns.")
	var h := _my_hero()
	if not h.is_empty() and snap.waveActive and float(h.get("specialCd", 1)) <= 0 and snap.get("enemies", []).size() >= 4:
		_tip("special", "✨ Your special is ready: press Q next to lots of pests! Two friends pressing Q together make a Team Combo.")
	if int(snap.wave) >= 3 and snap.waveActive:
		_tip("leap", "💨 Press Shift to Leaf Leap: a quick dash, and every hero's leap does something special.")


func pick_gadget(kind: String) -> void:
	Audio.play_sfx("ui_click", -3.0)
	selected_gadget = kind
	ghost_until = clock + 3.0
	var d: Dictionary = GameData.GADGETS[kind]
	hud.toast("%s %s selected (%d acorns). Press F to build it here." % [d.icon, d.name, int(d.cost)], Color("bbf7d0"), 2.5)


## T: which pest does my hero shoot first?
func cycle_target() -> void:
	var h := _my_hero()
	if h.is_empty():
		return
	var i := TARGET_MODES.find(String(h.get("targetMode", "first")))
	var next: String = TARGET_MODES[(i + 1) % TARGET_MODES.size()]
	send({"t": "target", "mode": next})
	var what: String = {"first": "the pest closest to the Bloom Tree", "strong": "the toughest pest", "close": "the pest closest to you", "last": "the pest furthest back"}[next]
	hud.toast("🎯 Your hero now shoots %s first" % what, Color("bae6fd"), 2.2)


## Esc: Resume / Restart / Leave to menu. Solo and LAN hosts also pause the game.
var _paused_by_menu := false


func open_pause_menu() -> void:
	hud.menu_open = true
	move_path = []
	_paused_by_menu = false
	if host and not snap.paused:
		send({"t": "pause"})
		_paused_by_menu = true


func close_pause_menu() -> void:
	hud.menu_open = false
	if host and snap.paused and _paused_by_menu:
		send({"t": "pause"})
	_paused_by_menu = false


## Test-only: print frame rate and timings once a second
func _perflog() -> void:
	PerfStats.on = true
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	var marks := {"start": 0, "pre": 0}
	get_tree().process_frame.connect(func(): marks.start = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():
		marks.pre = Time.get_ticks_usec()
		if marks.start > 0:
			PerfStats.add("[whole process]", marks.pre - marks.start))
	RenderingServer.frame_post_draw.connect(func(): PerfStats.add("[render]", Time.get_ticks_usec() - marks.pre))
	while true:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		if Time.get_ticks_msec() - t0 >= 1000:
			t0 = Time.get_ticks_msec()
			print("PERF fps %d | worst frame %.1f ms | process %.1f ms | draw calls %d | static %.0f MB | video %.0f MB | pests %d | wave %d" % [
				Engine.get_frames_per_second(), worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				snap.get("enemies", []).size(), int(snap.get("wave", 0))])
			worst = 0.0
			var parts: Array = []
			var tk := PerfStats.take()
			for k in tk:
				parts.append("%s %.1f ms" % [k, tk[k] / 1000.0 / maxf(1.0, Engine.get_frames_per_second())])
			print("     per frame: ", ", ".join(parts))


## Quit cleanly: stop every sound first (a stream still playing at exit shows up as a leak)
func quit_game() -> void:
	Sprites.finish_warm_up()
	_leave_game()  # stop the game (and tell LAN friends) first, so nothing starts a new sound while we quit
	attract = false
	for c in Audio.get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer2D:
			c.stop()
			c.stream = null
	Audio.process_mode = Node.PROCESS_MODE_DISABLED
	# the sound card lets go of stopped music on its own thread; give it a moment
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()  # closing the window: stop sounds, tell LAN friends, then quit


# ---------------------------------------------------------------------------
# Testing helpers
# ---------------------------------------------------------------------------
## LAN test: the host auto-starts once N friends joined; the client walks a
## little; after SECS both print what they see and quit.
func _netcheck(secs: float) -> void:
	var t0 := clock
	var walked := false
	var full_at := -1.0
	var picked := false
	var readies := 0
	var start_x := 0.0
	var last_at := {}  # smoothness on a LAN friend's screen: how evenly do pests move frame to frame?
	var steps: Array = []
	while clock - t0 < secs:
		await get_tree().process_frame
		if net is NetClient and playing and not snap.is_empty():
			if args.has("nointerp"):
				world.remote_interp = false  # test-only: the old way, to compare
			var now_at := {}
			for e in snap.get("enemies", []):
				var p := world.pos_of(e.id, Vector2(e.x, e.y))
				now_at[e.id] = p
				if last_at.has(e.id) and not e.stunned and not e.frozen and not e.get("trapped", false):
					steps.append(p.distance_to(last_at[e.id]))
			last_at = now_at
		if net is NetHost and not net.in_game and net.lobby.size() >= int(args.get("autostart", "1")):
			if full_at < 0:
				full_at = clock
			if clock - full_at > (1.5 if int(args.get("autostart", "1")) > 0 else 0.0):
				net.start_game()
		if net is NetClient and not playing and not picked and args.has("pick") and net.my_id > 0:
			picked = true
			net.set_my_pick("hero", String(args.pick))
			net.set_ready(true)
		if net is NetHost and not net.lobby.is_empty():
			readies = net.ready_count()[0]
		if net is NetClient and playing and my_pos != null and not walked:
			walked = true
			start_x = my_pos.x
			move_path = [my_pos + Vector2(90, 0)]
			if snap.has("clash"):
				send({"t": "buy", "item": "sword"})
			elif not snap.waveActive:
				send({"t": "wave"})
	var out := {"role": "host" if net is NetHost else "client", "status": net.status if net else "", "playing": playing, "my_id": my_id}
	if net is NetHost and host:
		out.players = []
		for h in host.sim.heroes:
			out.players.append({"owner": h.owner, "type": h.type, "x": roundf(h.x), "y": roundf(h.y)})
		out.wave = host.sim.wave
		out.readyFriends = readies
	elif net is NetClient:
		out.packets = net.packets
		out.kb_per_snap = 0
		var h := _my_hero()
		out.my_hero = h.get("type", "none")
		out.moved = roundf(float(h.get("x", 0)) - start_x) if walked else 0
		out.enemies = snap.get("enemies", []).size()
		out.wave = snap.get("wave", -1)
		out.heroes = snap.get("heroes", []).size()
		if steps.size() > 100:
			steps.sort()
			var med: float = steps[steps.size() / 2]
			var frozen := 0
			var off := 0.0
			for st in steps:
				if st < med * 0.1:
					frozen += 1
				off += absf(st - med)
			out.smooth = {"samples": steps.size(), "median_step": snappedf(med, 0.01), "frozen_pct": snappedf(100.0 * frozen / steps.size(), 0.1),
				"avg_off_pct": snappedf(100.0 * off / steps.size() / maxf(med, 0.001), 0.1)}
		if snap.has("clash"):
			out.items = h.get("items", [])
			out.hp = h.get("hp", 0)
			out.allies = snap.clash.allies.size()
			out.buildings = snap.clash.allyTowers.size() + snap.clash.foeTowers.size()
	print("NETCHECK ", JSON.stringify(out))
	get_tree().quit()


# Save a screenshot after a delay (and optionally quit)
# ---------------------------------------------------------------------------
func _screenshot_later(path: String, after: float) -> void:
	# test-only staging: --plant=KIND (build next to me), --ghost=KIND (show the build preview), --pausemenu
	if args.has("plant") and playing:
		host.sim.players[my_id].acorns += 500
		send({"t": "plant", "kind": String(args.plant)})
		send({"t": "move", "x": my_pos.x + 40, "y": my_pos.y + 10})
		my_pos = Vector2(my_pos.x + 40, my_pos.y + 10)
	if args.has("couch") and playing:  # pretend N controllers join
		for dev in int(args.couch):
			for b in [JOY_BUTTON_START, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A]:
				for down in [true, false]:
					var ev := InputEventJoypadButton.new()
					ev.device = dev
					ev.button_index = b
					ev.pressed = down
					Input.parse_input_event(ev)
					await get_tree().process_frame
		for i in 40:
			for dev in int(args.couch):
				var m := InputEventJoypadMotion.new()
				m.device = dev
				m.axis = JOY_AXIS_LEFT_X
				m.axis_value = 1.0 if dev == 0 else -1.0
				Input.parse_input_event(m)
			await get_tree().process_frame
		for dev in int(args.couch):
			var m := InputEventJoypadMotion.new()
			m.device = dev
			m.axis = JOY_AXIS_LEFT_X
			m.axis_value = 0.0
			Input.parse_input_event(m)
	if args.has("xp") and playing:  # test-only: level my hero up
		host.sim.grant_xp(my_id, float(args.xp))
	if args.has("ghost") and playing:
		selected_gadget = String(args.ghost)
		ghost_until = clock + 999.0
	await get_tree().create_timer(maxf(0.1, after - 0.4)).timeout
	if args.has("pausemenu") and playing:
		open_pause_menu()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)
	if args.has("quit"):
		quit_game()
