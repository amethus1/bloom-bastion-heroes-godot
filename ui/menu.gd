class_name Menu
extends Control
## Title screen (pick hero, hat, pet, map, difficulty, bots), the LAN "Join"
## browser and the LAN lobby. Built from regular Godot controls.

signal play(cfg: Dictionary)
signal leave

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
	ob.add_theme_font_size_override("font_size", 16)
	for i in items.size():
		ob.add_item(String(items[i][1]), i)
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
		b.custom_minimum_size = Vector2(118, 124)
		b.add_theme_constant_override("icon_max_width", 96)
		b.button_pressed = type == profile.hero
		b.pressed.connect(func(): _pick_hero(type))
		grid.add_child(b)
		_hero_buttons[type] = b
	_hero_info = _label("", 14, Color("ecfdf5"))
	_hero_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_info.custom_minimum_size = Vector2(500, 64)
	left.add_child(_hero_info)
	_update_hero_info()

	# right: game settings
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(_label("Game settings", 16, Color("bbf7d0")))
	var maps: Array = []
	for id in GameData.maps.maps:
		if not GameData.maps.maps[id].get("clash", false):
			maps.append([id, GameData.maps.maps[id].name])
	_option(right, "Map", maps, profile.map, func(id): profile.map = id; Profile.save_profile(profile))
	var diffs: Array = []
	for id in GameData.DIFFICULTIES:
		diffs.append([id, GameData.DIFFICULTIES[id].name])
	_option(right, "Difficulty", diffs, profile.diff, func(id): profile.diff = id; Profile.save_profile(profile); _update_mode_info())
	_option(right, "Mode", [["adventure", "🗺️ Adventure"], ["endless", "♾️ Endless"], ["clash", "⚔️ Garden Clash (3 lanes)"]], profile.gameMode, func(id): profile.gameMode = id; Profile.save_profile(profile); _update_mode_info())
	_option(right, "Controllers", [["couch", "🎮 Each controller = a new player"], ["p1", "🎮 Controller 1 = me, more = new players"]], "p1" if profile.get("padP1", false) else "couch", func(id): profile.padP1 = id == "p1"; Profile.save_profile(profile))
	_mode_info = _label("", 13, Color("d1fae5"))
	_mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.custom_minimum_size = Vector2(380, 0)
	right.add_child(_mode_info)
	_update_mode_info()
	_option(right, "Bot Buddies", [["0", "None"], ["1", "🤖 1 bot"], ["2", "🤖 2 bots"], ["3", "🤖 3 bots"]], str(profile.bots), func(id): profile.bots = int(id); Profile.save_profile(profile))
	var hats: Array = []
	for hat in GameData.cosmetics.hats:
		hats.append([hat.id, "%s %s" % [hat.icon, hat.name]])
	_option(right, "Hat", hats, profile.hat, func(id): profile.hat = id; Profile.save_profile(profile))
	var pets: Array = []
	for pet in GameData.cosmetics.pets:
		pets.append([pet.id, "%s %s" % [pet.icon, pet.name]])
	_option(right, "Pet", pets, profile.pet, func(id): profile.pet = id; Profile.save_profile(profile))
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
	var quit := _button("Quit", 18, 100)
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)
	if _error != "":
		v.add_child(_label("⚠️ " + _error, 15, Color("fca5a5"), HORIZONTAL_ALIGNMENT_CENTER))
		_error = ""
	solo.grab_focus()


var _mode_info: Label


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
	_hero_info.text = "%s (%s): %s\nSpecial (Q): %s %s: %s" % [t.name, t.role, info.style, info.special.icon, info.special.name, info.special.desc]


func _go(kind: String) -> void:
	Audio.play_sfx("ui_click")
	var cfg := profile.duplicate()
	cfg.kind = kind
	cfg.name = NetCommon.clean_name(String(cfg.name))
	play.emit(cfg)


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
	var back := _button("◀ Back", 18, 140)
	back.pressed.connect(show_title)
	v.add_child(back)
	_refresh_games()


func _refresh_games() -> void:
	if _games_list == null:
		return
	_games_list.clear()
	_game_ips = []
	for ip in finder.games:
		var g: Dictionary = finder.games[ip]
		var map_name := String(GameData.maps.maps.get(g.get("map", ""), {}).get("name", ""))
		_games_list.add_item("🌸 %s   ·   %d/4 players   ·   %s%s" % [g.get("name", "Game"), int(g.get("players", 1)), map_name, "   ·   playing now (you can still join!)" if g.get("inGame", false) else ""])
		_game_ips.append(ip)
	if _status and finder.listening:
		_status.text = "Double-click a game to join it." if _game_ips.size() > 0 else "Looking for games… (ask a friend to press Host LAN Game)"


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
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_players_box.custom_minimum_size = Vector2(0, 260)
	v.add_child(_players_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	if is_host:
		_start_btn = _button("▶  Start Game", 22, 240)
		_start_btn.pressed.connect(func(): net.start_game())
		row.add_child(_start_btn)
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
		icon.custom_minimum_size = Vector2(56, 56)
		row.add_child(icon)
		var hero_name := String(GameData.TOWERS.get(p.get("hero", ""), {}).get("name", ""))
		row.add_child(_label("%s%s  ·  %s" % [p.name, "  (host)" if p.get("host", false) else "", hero_name], 20))
		_players_box.add_child(row)
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
