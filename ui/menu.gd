class_name Menu
extends Control
## Title screen (pick hero, hat, pet, map, difficulty, bots), the LAN "Join"
## browser and the LAN lobby. Built from regular Godot controls.

signal play(cfg: Dictionary)
signal leave
signal settings_changed

var profile: Dictionary
var finder: LanFinder
var _net: Node
var _is_host := false
var _status: Label
var _players_box: VBoxContainer
var _error := ""
var _hero_info: Label
var _hero_buttons := {}
var _games_list: ItemList
var _game_ips: Array = []
var _start_btn: Button


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finder = LanFinder.new()
	add_child(finder)
	finder.games_changed.connect(_refresh_games)
	profile = Profile.load_profile()


func hide_all() -> void:
	visible = false
	finder.stop()
	_net = null


func show_error(msg: String) -> void:
	_error = msg
	show_title()


func _clear() -> void:
	for c in get_children():
		if c != finder:
			c.queue_free()
	_status = null
	_players_box = null
	_games_list = null


func _frame(min_w := 1080.0) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.05, 0.02, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(min_w, 0)
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	return v


func _label(text: String, size := 18, col := Color("ecfdf5"), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	return l


func _title(v: VBoxContainer, text: String, sub: String) -> void:
	var t := _label(text, 40, Color("fde047"), HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color("14532d"))
	v.add_child(t)
	if sub != "":
		v.add_child(_label(sub, 16, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_CENTER))


func _option(parent: Control, label: String, items: Array, current: String, on_pick: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(label, 16, Color("bbf7d0"))
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(250, 40)
	ob.fit_to_longest_item = false
	ob.add_theme_font_size_override("font_size", 16)
	for i in items.size():
		ob.add_item(String(items[i][1]), i)
		if items[i].size() > 2 and items[i][2]:
			ob.set_item_disabled(i, true)  # locked: earn it in a game
		if String(items[i][0]) == current:
			ob.select(i)
	ob.item_selected.connect(func(i): on_pick.call(String(items[i][0])))
	row.add_child(ob)
	parent.add_child(row)
	return ob


func _button(text: String, size := 20, min_w := 200.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 52)
	return b


# ---------------------------------------------------------------------------
# Title screen
# ---------------------------------------------------------------------------
func show_title() -> void:
	visible = true
	finder.stop()
	_net = null
	_clear()
	profile = Profile.load_profile()
	if not Profile.is_unlocked(profile, "hats", profile.hat):
		profile.hat = "none"
	if not Profile.is_unlocked(profile, "pets", profile.pet):
		profile.pet = "none"
	var v := _frame()
	_title(v, "🌸 Bloom Bastion Heroes 🌸", "Team up with up to 4 friends on the same Wi-Fi to protect the Bloom Tree from garden pests!")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)

	# left: name + hero
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var nrow := HBoxContainer.new()
	nrow.add_child(_label("Your name", 16, Color("bbf7d0")))
	var name_edit := LineEdit.new()
	name_edit.text = String(profile.name)
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(240, 40)
	name_edit.text_changed.connect(func(t): profile.name = t; Profile.save_profile(profile))
	nrow.add_child(name_edit)
	left.add_child(nrow)
	left.add_child(_label("Pick your hero", 16, Color("bbf7d0")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	var group := ButtonGroup.new()
	_hero_buttons.clear()
	for type in GameData.HERO_ORDER:
		var t: Dictionary = GameData.TOWERS[type]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.icon = UiKit.hero_icon(type)
		b.expand_icon = true
		b.text = String(t.name)
		b.add_theme_font_size_override("font_size", 12)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(118, 104)
		b.add_theme_constant_override("icon_max_width", 78)
		b.button_pressed = type == profile.hero
		b.pressed.connect(func(): _pick_hero(type))
		grid.add_child(b)
		_hero_buttons[type] = b
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 12)
	left.add_child(prow)
	_preview = HeroPreview.new()
	_preview.custom_minimum_size = Vector2(150, 150)
	prow.add_child(_preview)
	var pinfo := VBoxContainer.new()
	pinfo.add_theme_constant_override("separation", 6)
	prow.add_child(pinfo)
	_hero_info = _label("", 13, Color("ecfdf5"))
	_hero_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_info.custom_minimum_size = Vector2(340, 52)
	pinfo.add_child(_hero_info)
	_update_hero_info()

	# right: game settings
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(_label("Game settings", 16, Color("bbf7d0")))
	_map_label = _label("", 15, Color("ecfdf5"))
	right.add_child(_map_label)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	right.add_child(mrow)
	var mgroup := ButtonGroup.new()
	var medals: Dictionary = profile.get("medals", {})
	for id in GameData.maps.maps:
		if GameData.maps.maps[id].get("clash", false):
			continue
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 0)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = mgroup
		b.icon = Sprites.tex(Sprites.atlas.maps.get(id, ""))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(72, 50)
		b.button_pressed = id == profile.map
		var lvl := int(medals.get(id, 0))
		b.tooltip_text = "%s%s" % [GameData.maps.maps[id].name, (" · %s %s" % [Profile.MEDAL_ICON[lvl], Profile.MEDAL_NAME[lvl]]) if lvl > 0 else ""]
		b.pressed.connect(func(): profile.map = id; Profile.save_profile(profile); _update_map_label())
		card.add_child(b)
		card.add_child(_label(Profile.MEDAL_ICON[lvl] if lvl > 0 else "·", 13, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER))
		mrow.add_child(card)
	_update_map_label()
	var diffs: Array = []
	for id in GameData.DIFFICULTIES:
		diffs.append([id, GameData.DIFFICULTIES[id].name])
	_option(right, "Difficulty", diffs, profile.diff, func(id): profile.diff = id; Profile.save_profile(profile); _update_mode_info())
	_option(right, "Mode", [["adventure", "🗺️ Adventure"], ["endless", "♾️ Endless"], ["clash", "⚔️ Garden Clash (3 lanes)"]], profile.gameMode, func(id): profile.gameMode = id; Profile.save_profile(profile); _update_mode_info())
	_mode_info = _label("", 13, Color("d1fae5"))
	_mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.custom_minimum_size = Vector2(380, 0)
	right.add_child(_mode_info)
	_update_mode_info()
	_option(right, "Bot Buddies", [["0", "None"], ["1", "🤖 1 bot"], ["2", "🤖 2 bots"], ["3", "🤖 3 bots"]], str(profile.bots), func(id): profile.bots = int(id); Profile.save_profile(profile))
	var hats: Array = []
	for hat in GameData.cosmetics.hats:
		var ok := Profile.is_unlocked(profile, "hats", hat.id)
		hats.append([hat.id, ("%s %s" % [hat.icon, hat.name]) if ok else ("🔒 %s: %s" % [hat.name, hat.how]), not ok])
	_option(pinfo, "Hat", hats, profile.hat, func(id): profile.hat = id; Profile.save_profile(profile); _update_hero_info())
	var pets: Array = []
	for pet in GameData.cosmetics.pets:
		var ok := Profile.is_unlocked(profile, "pets", pet.id)
		pets.append([pet.id, ("%s %s" % [pet.icon, pet.name]) if ok else ("🔒 %s: %s" % [pet.name, pet.how]), not ok])
	_option(pinfo, "Pet", pets, profile.pet, func(id): profile.pet = id; Profile.save_profile(profile); _update_hero_info())
	right.add_child(_label("Games %d · Wins %d · Best Endless wave %d" % [int(profile.games), int(profile.wins), int(profile.bestEndless)], 13, Color("86efac")))

	# buttons
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var solo := _button("▶  Play Solo", 22, 220)
	solo.pressed.connect(func(): _go("solo"))
	row.add_child(solo)
	var hostb := _button("🏠  Host LAN Game", 20, 230)
	hostb.pressed.connect(func(): _go("host"))
	row.add_child(hostb)
	var joinb := _button("🔍  Join LAN Game", 20, 230)
	joinb.pressed.connect(show_join)
	row.add_child(joinb)
	var settings := _button("⚙", 20, 60)
	settings.tooltip_text = "Settings"
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	var quit := _button("Quit", 18, 100)
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)
	if _error != "":
		v.add_child(_label("⚠️ " + _error, 15, Color("fca5a5"), HORIZONTAL_ALIGNMENT_CENTER))
		_error = ""
	solo.grab_focus()


var _mode_info: Label
var _preview: HeroPreview
var _map_label: Label


func _update_map_label() -> void:
	if _map_label == null or not is_instance_valid(_map_label):
		return
	var lvl := int(profile.get("medals", {}).get(profile.map, 0))
	_map_label.text = "Map: %s%s" % [GameData.maps.maps.get(profile.map, {}).get("name", profile.map), ("   %s %s" % [Profile.MEDAL_ICON[lvl], Profile.MEDAL_NAME[lvl]]) if lvl > 0 else ""]


## What the chosen difficulty and mode mean, in one or two lines
func _update_mode_info() -> void:
	if _mode_info == null or not is_instance_valid(_mode_info):
		return
	var d: Dictionary = GameData.DIFFICULTIES.get(profile.diff, {})
	match String(profile.gameMode):
		"clash":
			var cd: Dictionary = GameData.clash.difficulty.get(profile.diff, {})
			_mode_info.text = "⚔️ Three lanes on Three-Lane Valley: smash the Thorn Heart. " + String(cd.get("desc", ""))
		"endless":
			_mode_info.text = "♾️ The waves never stop and get a surprise twist every few waves. How far can you go? (%s pests)" % String(d.get("short", ""))
		_:
			_mode_info.text = String(d.get("description", ""))


func _pick_hero(type: String) -> void:
	profile.hero = type
	Profile.save_profile(profile)
	_update_hero_info()
	Audio.play_sfx("ui_click")
	Audio.say_hero(type, "pick", -1, true)
	if _net and _net.has_method("pick_hero"):
		_net.pick_hero(type)


func _update_hero_info() -> void:
	if _hero_info == null:
		return
	var t: Dictionary = GameData.TOWERS[profile.hero]
	var info: Dictionary = GameData.HERO_INFO[profile.hero]
	_hero_info.text = "%s (%s): %s\nSpecial (Q): %s %s" % [t.name, t.role, info.style, info.special.icon, info.special.name]
	_hero_info.tooltip_text = String(info.special.desc)
	_hero_info.mouse_filter = Control.MOUSE_FILTER_PASS
	if _preview and is_instance_valid(_preview):
		_preview.hero = profile.hero
		_preview.hat = profile.hat
		_preview.pet = profile.pet


func _go(kind: String) -> void:
	Audio.play_sfx("ui_click")
	var cfg := profile.duplicate()
	cfg.kind = kind
	cfg.name = NetCommon.clean_name(String(cfg.name))
	play.emit(cfg)


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
func show_settings() -> void:
	_clear()
	var v := _frame(560)
	_title(v, "⚙ Settings", "Saved on this computer. You can also change these in a game (Esc).")
	var prof := Profile.load_profile()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	v.add_child(rows)
	_option(rows, "Screen shake", [["1.0", "100%"], ["0.5", "50%"], ["0.0", "Off"]], "%.1f" % float(prof.shake), func(id): Profile.set_value("shake", float(id)); settings_changed.emit())
	_option(rows, "Damage numbers", [["all", "All"], ["big", "Big hits only"], ["off", "Off"]], String(prof.dmgNums), func(id): Profile.set_value("dmgNums", id); settings_changed.emit())
	_option(rows, "Fullscreen", [["false", "Off"], ["true", "On (F11)"]], "true" if prof.fullscreen else "false", func(id): Profile.set_value("fullscreen", id == "true"); settings_changed.emit())
	_option(rows, "Controllers", [["couch", "Each = a new player"], ["p1", "Controller 1 = me"]], "p1" if prof.get("padP1", false) else "couch", func(id): Profile.set_value("padP1", id == "p1"); settings_changed.emit())
	_option(rows, "Kid assist", [["false", "Off"], ["true", "On: tree regrows, easier Sun"]], "true" if prof.get("kidAssist", false) else "false", func(id): Profile.set_value("kidAssist", id == "true"))
	_option(rows, "Hats & pets", [["false", "Earn them by playing"], ["true", "Unlock everything (for little kids)"]], "true" if prof.unlockAll else "false", func(id): Profile.set_value("unlockAll", id == "true"))
	_option(rows, "Sound", [["false", "🔊 On"], ["true", "🔇 Off (M in a game)"]], "true" if Audio.muted else "false", func(id): if (id == "true") != Audio.muted: Audio.toggle_mute())
	var vols := [["1.0", "100%"], ["0.65", "65%"], ["0.35", "35%"], ["0.0", "Off"]]
	_option(rows, "Music volume", vols, "%.2f" % float(prof.get("musicVol", 0.65)) if float(prof.get("musicVol", 0.65)) in [0.65, 0.35] else ("1.0" if float(prof.get("musicVol", 0.65)) > 0.8 else "0.0"), func(id): Profile.set_value("musicVol", float(id)); settings_changed.emit())
	_option(rows, "SFX volume", [["1.0", "100%"], ["0.85", "85%"], ["0.35", "35%"], ["0.0", "Off"]], "%.2f" % float(prof.get("sfxVol", 0.85)) if absf(float(prof.get("sfxVol", 0.85)) - 0.85) < 0.05 else ("0.35" if absf(float(prof.get("sfxVol", 0.85)) - 0.35) < 0.05 else ("1.0" if float(prof.get("sfxVol", 0.85)) > 0.9 else "0.0")), func(id): Profile.set_value("sfxVol", float(id)); settings_changed.emit())
	_option(rows, "Voice volume", [["1.0", "100%"], ["0.95", "95%"], ["0.65", "65%"], ["0.35", "35%"], ["0.0", "Off"]], "%.2f" % float(prof.get("voiceVol", 0.95)) if float(prof.get("voiceVol", 0.95)) in [0.95, 0.65, 0.35] else ("1.0" if float(prof.get("voiceVol", 0.95)) > 0.96 else "0.0"), func(id): Profile.set_value("voiceVol", float(id)); settings_changed.emit())
	_option(rows, "Hero chatter", [["all", "All lines"], ["key", "Key moments only"], ["off", "Off"]], String(prof.get("dialogMode", "all")), func(id): Profile.set_value("dialogMode", id); settings_changed.emit())
	var back := _button("◀ Back", 18, 140)
	back.pressed.connect(show_title)
	v.add_child(back)


# ---------------------------------------------------------------------------
# Join: browse LAN games
# ---------------------------------------------------------------------------
func show_join() -> void:
	_clear()
	var v := _frame(720)
	_title(v, "🔍 Join a LAN Game", "Games hosted on this Wi-Fi show up below.")
	_games_list = ItemList.new()
	_games_list.custom_minimum_size = Vector2(680, 220)
	_games_list.add_theme_font_size_override("font_size", 18)
	_games_list.item_activated.connect(func(i): _join_ip(_game_ips[i]))
	v.add_child(_games_list)
	var ok := finder.start()
	_status = _label("Looking for games…" if ok else "Can't listen for games on this computer. Type the host's address instead.", 15, Color("bbf7d0"))
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label("Host address", 16, Color("bbf7d0")))
	var addr := LineEdit.new()
	addr.placeholder_text = "e.g. 192.168.1.20"
	addr.text = String(profile.address)
	addr.custom_minimum_size = Vector2(260, 40)
	row.add_child(addr)
	var go := _button("Join", 18, 110)
	go.pressed.connect(func(): _join_ip(addr.text.strip_edges()))
	addr.text_submitted.connect(func(t): _join_ip(t.strip_edges()))
	row.add_child(go)
	v.add_child(row)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	var back := _button("◀ Back", 18, 140)
	back.pressed.connect(show_title)
	brow.add_child(back)
	var refresh := _button("↻ Refresh", 18, 140)
	refresh.pressed.connect(func(): finder.start(); _join_shown_ms = Time.get_ticks_msec(); _refresh_games())
	brow.add_child(refresh)
	v.add_child(brow)
	_join_shown_ms = Time.get_ticks_msec()
	_refresh_games()


var _join_shown_ms := 0


func _refresh_games() -> void:
	if _games_list == null:
		return
	_games_list.clear()
	_game_ips = []
	for ip in finder.games:
		var g: Dictionary = finder.games[ip]
		var map_name := String(GameData.maps.maps.get(g.get("map", ""), {}).get("name", ""))
		var mode: String = {"endless": "♾️ Endless", "clash": "⚔️ Clash"}.get(String(g.get("mode", "")), "🗺️ Adventure")
		if g.get("mode", "") == "clash":
			map_name = "Three-Lane Valley"
		var dname := String(GameData.DIFFICULTIES.get(String(g.get("diff", "")), {}).get("name", ""))
		var now := ("   ·   playing, wave %d (you can still join!)" % int(g.get("wave", 0))) if g.get("inGame", false) else ""
		_games_list.add_item("🌸 %s  ·  %d/4  ·  %s  ·  %s  ·  %s%s" % [g.get("name", "Game"), int(g.get("players", 1)), map_name, dname, mode, now])
		_game_ips.append(ip)
	if _status and finder.listening:
		if _game_ips.size() > 0:
			_status.text = "Double-click a game to join it."
		elif Time.get_ticks_msec() - _join_shown_ms > 5000:
			_status.text = "No games yet. Is your friend's game hosted on the same Wi-Fi? A firewall can hide it: then type the address their lobby shows."
		else:
			_status.text = "Looking for games… (ask a friend to press Host LAN Game)"


func _join_ip(ip: String) -> void:
	if ip == "":
		return
	profile.address = ip
	Profile.save_profile(profile)
	var cfg := profile.duplicate()
	cfg.kind = "join"
	cfg.address = ip
	cfg.name = NetCommon.clean_name(String(cfg.name))
	play.emit(cfg)


# ---------------------------------------------------------------------------
# Lobby (host or client)
# ---------------------------------------------------------------------------
func show_lobby(net: Node, is_host: bool) -> void:
	visible = true
	finder.stop()
	_clear()
	_net = net
	_is_host = is_host
	var v := _frame(720)
	_title(v, "🏠 Your LAN Game" if is_host else "🌸 LAN Game", "")
	_status = _label("", 15, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	if is_host:
		# the address friends can type, with a Copy button
		var addrs: Array = NetHost.local_addresses()
		var arow := HBoxContainer.new()
		arow.alignment = BoxContainer.ALIGNMENT_CENTER
		arow.add_theme_constant_override("separation", 10)
		arow.add_child(_label("Your address: %s" % (", ".join(addrs) if not addrs.is_empty() else "(no Wi-Fi?)"), 17, Color("fde047")))
		if not addrs.is_empty():
			var copy := _button("Copy", 14, 80)
			copy.custom_minimum_size.y = 34
			copy.pressed.connect(func(): DisplayServer.clipboard_set(String(addrs[0])); copy.text = "Copied!")
			arow.add_child(copy)
		v.add_child(arow)
	# my hero / hat / pet, changeable right here
	var pick := HBoxContainer.new()
	pick.alignment = BoxContainer.ALIGNMENT_CENTER
	pick.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for type in GameData.HERO_ORDER:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.icon = UiKit.hero_icon(type)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(56, 56)
		b.tooltip_text = String(GameData.TOWERS[type].name)
		b.button_pressed = type == profile.hero
		b.pressed.connect(func(): profile.hero = type; Profile.save_profile(profile); net.set_my_pick("hero", type))
		pick.add_child(b)
	v.add_child(pick)
	var cos := HBoxContainer.new()
	cos.alignment = BoxContainer.ALIGNMENT_CENTER
	cos.add_theme_constant_override("separation", 16)
	v.add_child(cos)
	var hats: Array = []
	for hat in GameData.cosmetics.hats:
		if Profile.is_unlocked(profile, "hats", hat.id):
			hats.append([hat.id, "%s %s" % [hat.icon, hat.name]])
	_option(cos, "Hat", hats, profile.hat, func(id): profile.hat = id; Profile.save_profile(profile); net.set_my_pick("hat", id))
	var pets: Array = []
	for pet in GameData.cosmetics.pets:
		if Profile.is_unlocked(profile, "pets", pet.id):
			pets.append([pet.id, "%s %s" % [pet.icon, pet.name]])
	_option(cos, "Pet", pets, profile.pet, func(id): profile.pet = id; Profile.save_profile(profile); net.set_my_pick("pet", id))
	if is_host:
		# the host can still change the game here
		var g1 := HBoxContainer.new()
		g1.alignment = BoxContainer.ALIGNMENT_CENTER
		g1.add_theme_constant_override("separation", 16)
		v.add_child(g1)
		var maps: Array = []
		for id in GameData.maps.maps:
			if not GameData.maps.maps[id].get("clash", false):
				maps.append([id, GameData.maps.maps[id].name])
		_option(g1, "Map", maps, String(net.cfg.map), func(id): profile.map = id; Profile.save_profile(profile); net.set_option("map", id))
		var diffs: Array = []
		for id in GameData.DIFFICULTIES:
			diffs.append([id, GameData.DIFFICULTIES[id].name])
		_option(g1, "Difficulty", diffs, String(net.cfg.diff), func(id): profile.diff = id; Profile.save_profile(profile); net.set_option("diff", id))
		var g2 := HBoxContainer.new()
		g2.alignment = BoxContainer.ALIGNMENT_CENTER
		g2.add_theme_constant_override("separation", 16)
		v.add_child(g2)
		_option(g2, "Mode", [["adventure", "🗺️ Adventure"], ["endless", "♾️ Endless"], ["clash", "⚔️ Garden Clash"]], String(net.cfg.gameMode), func(id): profile.gameMode = id; Profile.save_profile(profile); net.set_option("gameMode", id))
		_option(g2, "Bot Buddies", [["0", "None"], ["1", "🤖 1"], ["2", "🤖 2"], ["3", "🤖 3"]], str(net.cfg.bots), func(id): profile.bots = int(id); Profile.save_profile(profile); net.set_option("bots", int(id)))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_players_box.custom_minimum_size = Vector2(0, 150)
	v.add_child(_players_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	if is_host:
		_start_btn = _button("▶  Start Game", 22, 260)
		_start_btn.pressed.connect(func(): net.start_game())
		row.add_child(_start_btn)
	else:
		var rb := _button("✋ I'm ready!", 20, 200)
		rb.toggle_mode = true
		rb.toggled.connect(func(on): net.set_ready(on); rb.text = "✅ Ready!" if on else "✋ I'm ready!")
		row.add_child(rb)
	var back := _button("Leave", 18, 140)
	back.pressed.connect(func(): leave.emit())
	row.add_child(back)
	net.lobby_changed.connect(_refresh_lobby)
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _players_box == null or _net == null:
		return
	for c in _players_box.get_children():
		c.queue_free()
	var players: Array = _net.players_for_menu()
	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := TextureRect.new()
		icon.texture = UiKit.hero_icon(String(p.get("hero", "peashooter")))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)
		row.add_child(icon)
		var hero_name := String(GameData.TOWERS.get(p.get("hero", ""), {}).get("name", ""))
		var hat_icon := ""
		var pet_icon := ""
		for x in GameData.cosmetics.hats:
			if x.id == p.get("hat", "none") and x.id != "none":
				hat_icon = " " + String(x.icon)
		for x in GameData.cosmetics.pets:
			if x.id == p.get("pet", "none") and x.id != "none":
				pet_icon = " " + String(x.icon)
		var tick := "👑" if p.get("host", false) else ("✅" if p.get("ready", false) else "⏳")
		row.add_child(_label("%s %s%s  ·  %s%s%s" % [tick, p.name, "  (host)" if p.get("host", false) else "", hero_name, hat_icon, pet_icon], 18))
		_players_box.add_child(row)
	if _is_host and _start_btn and is_instance_valid(_start_btn):
		var rc: Array = _net.ready_count()
		_start_btn.text = "▶  Start Game" if rc[1] == 0 else "▶  Start (%d/%d ready)" % [rc[0], rc[1]]
	var c: Dictionary = _net.cfg if _is_host else _net.host_cfg
	if not c.is_empty():
		var map_name := String(GameData.maps.maps.get(c.get("map", ""), {}).get("name", ""))
		var dname := String(GameData.DIFFICULTIES.get(c.get("diff", ""), {}).get("name", ""))
		var mode_name: String = {"endless": "Endless", "clash": "Garden Clash"}.get(String(c.get("gameMode", "")), "Adventure")
		if c.get("gameMode", "") == "clash":
			map_name = "Three-Lane Valley"
		_players_box.add_child(_label("%s · %s · %s · %s" % [map_name, dname, mode_name, _bots_text(int(c.get("bots", 0)))], 15, Color("86efac")))


func _bots_text(n: int) -> String:
	return "no bot buddies" if n <= 0 else ("1 bot buddy" if n == 1 else "%d bot buddies" % n)


func _process(_delta: float) -> void:
	if visible and _net and _status:
		_status.text = String(_net.status)
