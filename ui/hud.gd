class_name Hud
extends Control
## The in-game heads-up display: Bloom Tree lives, wave, acorns, level & XP,
## ability cooldowns, the build bar, level-up cards, banners, toasts and the
## end-of-game screen. Drawn by hand; clicks are passed in from main.gd.

var snap: Dictionary = {}
var my_owner := -1
var selected_gadget := "sentry"
var is_host := true
var net_note := ""
var net_trouble := ""  # LAN friend: the connection dropped and we're trying to get back in
var practice := {}  # Practice Garden: {text, step, of} of the current step

var _font: Font
var _buttons: Array = []  # [Rect2, action]
var _toasts: Array = []
var _banner := {"text": "", "sub": "", "t": 0.0, "col": Color.WHITE}
var _subtitle := {"speaker": "", "text": "", "t": 0.0, "max": 1.0}
var _time := 0.0
var couch: Couch  # couch co-op players on this computer (set by main.gd)
var show_stats := false  # Tab held: scoreboard, hero stats, reaction guide
var emote_open := false  # V: the emote bar
var cards_hidden := false  # C: tuck the level-up cards away during a busy fight
var minimap_on := true  # N hides the Adventure minimap
var minimap_rect := Rect2()  # clicking the minimap walks there (main.gd)
var world: WorldView  # for edge arrows (set by main.gd)
var new_unlocks: Array = []  # things earned this game, shown on the end screen
var next_challenge := ""  # label for the "Next challenge" button ("" = none)
var menu_open := false  # Esc: pause menu
var _pest_card := {"type": "", "t": 0.0}
var _build_rect := Rect2()
var _shown := {}  # numbers on screen that glide to their new value (see eased())
var _frame_dt := 1.0 / 60.0
var _cards_key := ""  # the level-up cards on screen (they slide in when new ones come)
var _cards_t := 0.0
var _end_since := -1.0  # when the end-of-game screen appeared (it pops in)
var _confetti: Array = []  # a win: paper bits fluttering down over everything
var _menu_since := -1.0  # ...and the pause menu
var _wave_cache := {"key": "", "groups": []}
var ui_scale := 0.8  # the "UI size" setting: every panel and button is drawn this much bigger or smaller
var msg_level := 1  # the "Messages" setting: 2 = all, 1 = fewer, 0 = only important ones
var auto_cards := true  # "Level-ups: automatic": no card pop-ups, just path upgrades in the side bar
var selected_tower := -1  # the tower picked in "Your towers" (or clicked in the garden), by id
var hero_at = null  # where my hero is (main.gd), to tell whether a tower is close enough
const TOWER_REACH := 110.0  # stand this close to a tower to upgrade or sell it
const PEST_CARD_LIFE := 6.0
var _bl_top := 0.0  # the top of whatever is stacked in the bottom-left corner this frame
var _cards_rect := Rect2()  # the level-up cards, when they're showing
var _build_tip := ""  # the build bar's tooltip, drawn on top of everything near it
var _eff := 0.8  # the scale actually used this frame (Garden Clash's bottom row needs more room, so it caps it)
var pinned_item := ""  # Garden Clash: the item I want next ("bark", or "bark+" for the Golden one); F buys it at the tree
var shop_all := false  # the Clash shop shows every item instead of the two picked for my hero


func _ready() -> void:
	_font = UiKit.font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Audio.dialog_line.connect(_on_dialog_line)


func _on_dialog_line(speaker: String, text: String, owner_id: int, duration: float) -> void:
	if owner_id < 0 and text != "":
		_subtitle = {"speaker": speaker, "text": text, "t": duration, "max": duration}


func _throw_confetti(W: float, H: float) -> void:
	var cols := ["f472b6", "fde047", "60a5fa", "4ade80", "fb923c", "c084fc", "ffffff"]
	for i in 160:
		_confetti.append({"p": Vector2(randf() * W, -10.0 - randf() * H * 0.7), "v": Vector2((randf() - 0.5) * 70, 50 + randf() * 70),
			"life": 4.5 + randf() * 2.0, "size": 7.0 + randf() * 5.0, "col": Color(cols[i % cols.size()]), "spin": 3.0 + randf() * 7.0, "rot": randf() * TAU})


## A new game: bars and counters start from their new values (no gliding from the last game's)
func reset_anim() -> void:
	_shown = {}
	_cards_key = ""
	_end_since = -1.0
	_confetti = []


## A short message in the bottom-left corner. `level`: 0 = always (something you
## tried didn't work, warnings), 1 = normal, 2 = small news ("Messages: Fewer" hides it)
func toast(msg: String, col := Color.WHITE, life := 3.5, level := 1) -> void:
	if level > msg_level:
		return
	for t in _toasts:
		if t.text == msg:
			# the same message again: keep it up a bit longer and count it, instead of stacking copies
			t.n = int(t.n) + 1
			t.t = maxf(float(t.t), float(t.max) - 0.2)
			return
	_toasts.append({"text": msg, "col": col, "t": life, "max": life, "n": 1})
	while _toasts.size() > 3:
		_toasts.pop_front()


var _feed: Array = []


## The battle feed (Garden Clash): who smashed what, who got knocked out
func feed(text: String, col := Color.WHITE) -> void:
	_feed.append({"text": text, "col": col, "t": 7.0})
	if _feed.size() > 6:
		_feed.pop_front()


## New Garden Guide pages: one line that counts up, instead of a line per pest
func guide_pages(names: Array) -> void:
	if msg_level == 0 or names.is_empty():
		return
	for f in _feed:
		if f.get("key", "") == "guide":
			f.n = int(f.n) + names.size()
			f.text = "📖 %d new pages in the Garden Guide" % int(f.n)
			f.t = 7.0
			return
	var text := ("📖 New in the Garden Guide: %s" % names[0]) if names.size() == 1 else ("📖 %d new pages in the Garden Guide" % names.size())
	_feed.append({"text": text, "col": Color("bbf7d0"), "t": 7.0, "key": "guide", "n": names.size()})
	if _feed.size() > 6:
		_feed.pop_front()


## A "new pest!" warning card (first time a pest type or boss shows up)
func pest_card(type: String) -> void:
	if msg_level == 0 and not GameData.ENEMIES.get(type, {}).get("boss", false):
		return
	_pest_card = {"type": type, "t": PEST_CARD_LIFE}


func over_build_bar() -> bool:
	return _build_rect.has_point(get_local_mouse_position())


## Big words at the top of the screen. `level` works like toast()'s.
func banner(text: String, sub := "", col := Color("fde047"), life := 2.4, level := 1) -> void:
	if level > msg_level:
		return
	_banner = {"text": text, "sub": sub, "t": life, "col": col, "max": life}


func _process(delta: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(delta)
	PerfStats.add("hud update" , Time.get_ticks_usec() - _pt0)


func _process_inner(delta: float) -> void:
	_time += delta
	_frame_dt = delta
	_eff = ui_scale
	if snap.has("clash"):
		_eff = minf(ui_scale, get_viewport_rect().size.x / 1140.0)  # items, hero panel and minimap side by side
	scale = Vector2(_eff, _eff)
	for t in _toasts:
		t.t -= delta
	_toasts = _toasts.filter(func(t): return t.t > 0)
	_pest_card.t = maxf(0.0, _pest_card.t - delta)
	for f in _feed:
		f.t -= delta
	_feed = _feed.filter(func(f): return f.t > 0)
	_banner.t = maxf(0.0, _banner.t - delta)
	for c in _confetti:
		c.life -= delta
		c.rot += c.spin * delta
		c.v.x += sin(c.rot * 0.7) * 50.0 * delta  # flutter side to side
		c.v.y = minf(c.v.y + 40.0 * delta, 150.0)
		c.p += c.v * delta
	if not _confetti.is_empty():
		_confetti = _confetti.filter(func(c): return c.life > 0)
	_subtitle.t = maxf(0.0, _subtitle.t - delta)
	queue_redraw()


## Returns the action for a click at this screen point ({} when none)
func click(p: Vector2) -> Dictionary:
	for i in range(_buttons.size() - 1, -1, -1):
		if _buttons[i][0].has_point(p):
			return _buttons[i][1]
	return {}


func over_ui(p: Vector2) -> bool:
	return not click(p).is_empty() or _blocks(p)


var _block_rects: Array = []


func _blocks(p: Vector2) -> bool:
	for r in _block_rects:
		if r.has_point(p):
			return true
	return false


func my_hero() -> Dictionary:
	for h in snap.get("heroes", []):
		if h.owner == my_owner:
			return h
	return {}


func my_player() -> Dictionary:
	for p in snap.get("players", []):
		if p.id == my_owner:
			return p
	return {}


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------
## A number that glides to its new value instead of jumping (bars, counters)
func eased(key: String, target: float, speed := 8.0) -> float:
	var v: float = _shown.get(key, target)
	v = lerpf(v, target, minf(1.0, _frame_dt * speed))
	if absf(v - target) < 0.0005:
		v = target
	_shown[key] = v
	return v


## 0 -> 1 with a little overshoot at the end (things popping into place)
static func ease_back(k: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)


## Draw what follows scaled around `c` (pop-in animations); pop_end() puts it back
func pop_begin(c: Vector2, scale: float, offset := Vector2.ZERO) -> void:
	draw_set_transform(c - c * scale + offset, 0.0, Vector2(scale, scale))


func pop_end() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func panel(r: Rect2, bg := UiKit.PANEL, edge := UiKit.PANEL_EDGE, radius := 14) -> void:
	draw_style_box(UiKit.box(bg, edge, radius, 2, 0), r)


func txt(pos: Vector2, s: String, size := 16, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0:
		p.x -= _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
		align = HORIZONTAL_ALIGNMENT_LEFT
	elif align == HORIZONTAL_ALIGNMENT_RIGHT and width < 0:
		p.x -= _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		align = HORIZONTAL_ALIGNMENT_LEFT
	if outline > 0:
		draw_string_outline(_font, p, s, align, width, size, outline, Color(0, 0, 0, 0.75 * col.a))
	draw_string(_font, p, s, align, width, size, col)


func wrap_text(pos: Vector2, s: String, width: float, size := 14, col := Color.WHITE, lines := 3) -> void:
	draw_multiline_string(_font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size, lines, col)


## A rounded bar. `trail` (if more than k) shows, in pale, what was just lost.
func meter(r: Rect2, k: float, col: Color, back := Color(0, 0, 0, 0.45), trail := -1.0) -> void:
	draw_style_box(UiKit.box(back, Color(0, 0, 0, 0), int(r.size.y / 2), 0, 0), r)
	if trail > k + 0.004:
		var tw := maxf(r.size.y, r.size.x * clampf(trail, 0, 1))
		draw_style_box(UiKit.box(Color(1, 0.95, 0.85, 0.75), Color(0, 0, 0, 0), int(r.size.y / 2), 0, 0), Rect2(r.position, Vector2(tw, r.size.y)))
	if k > 0.001:
		var w := maxf(r.size.y, r.size.x * clampf(k, 0, 1))
		draw_style_box(UiKit.box(col, Color(0, 0, 0, 0), int(r.size.y / 2), 0, 0), Rect2(r.position, Vector2(w, r.size.y)))


func button(r: Rect2, label: String, action: Dictionary, col := Color("15803d"), size := 15, active := false) -> void:
	var hover := r.has_point(get_local_mouse_position())
	var c := col.lightened(0.15) if hover else col
	draw_style_box(UiKit.box(c, Color("fde047") if active else Color(1, 1, 1, 0.35 if hover else 0.18), 12, 2, 0), r)
	txt(Vector2(r.get_center().x, r.get_center().y + size * 0.36), label, size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_buttons.append([r, action])


## A round ability button with a cooldown sweep
func ability(c: Vector2, r: float, icon: String, key: String, cd: float, cd_max: float, action: Dictionary, col: Color) -> void:
	var ready := cd <= 0.05
	draw_circle(c, r + 3, Color(0, 0, 0, 0.5))
	draw_circle(c, r, col.darkened(0.45) if not ready else col.darkened(0.15))
	if not ready and cd_max > 0:
		var k := clampf(cd / cd_max, 0, 1)
		var pts := PackedVector2Array([c])
		var n := 32
		for i in n + 1:
			var a := -PI / 2 + TAU * k * float(i) / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
	else:
		var pulse := 0.5 + 0.5 * sin(_time * 4)
		draw_arc(c, r + 1, 0, TAU, 40, Color(col.r, col.g, col.b, 0.5 + 0.5 * pulse), 3, true)
	txt(c + Vector2(0, 9), icon, 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if not ready:
		txt(c + Vector2(0, 8), str(ceili(cd)), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	var kw := _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12
	draw_style_box(UiKit.box(Color(0.06, 0.09, 0.16, 0.95), Color(1, 1, 1, 0.4), 6, 1, 0), Rect2(c.x - kw / 2, c.y + r - 8, kw, 18))
	txt(Vector2(c.x, c.y + r + 5), key, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_buttons.append([Rect2(c - Vector2(r, r), Vector2(r, r) * 2), action])


# ---------------------------------------------------------------------------
# Main draw
# ---------------------------------------------------------------------------
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_hud()
	PerfStats.add("hud draw", Time.get_ticks_usec() - t0)


func _draw_hud() -> void:
	_buttons.clear()
	_block_rects.clear()
	_cards_rect = Rect2()
	_build_tip = ""
	if snap.is_empty():
		return
	# drawn _eff times bigger, so the screen is this many HUD units across
	var W := get_viewport_rect().size.x / _eff
	var H := get_viewport_rect().size.y / _eff
	_bl_top = H - 108.0
	var h := my_hero()
	var me := my_player()
	var phase: String = snap.phase

	var clash: Dictionary = snap.get("clash", {})
	if not clash.is_empty():
		_draw_clash_top(clash, me, h, W)
	# --- top-left: Bloom Tree, wave, acorns (Adventure / Endless)
	var lives_k: float = float(snap.lives) / maxf(1.0, float(snap.maxLives))
	if not clash.is_empty():
		lives_k = -1.0
	if lives_k >= 0:
		_draw_tree_panel(lives_k, me)
	_draw_team(W, h)
	minimap_rect = Rect2()
	if clash.is_empty() and minimap_on and phase == "playing":
		_draw_adv_minimap(W)
	if phase == "playing" and world:
		_draw_edge_arrows(W, H)

	# --- top middle, top down: boss bars, the banner, then who's talking
	var top := 12.0
	if not clash.is_empty():
		top = _draw_clash_status(clash, W)  # under the scoreboard: raids, covers
	elif phase == "playing":
		top = _draw_boss_bar(W)
	if _banner.t > 0:
		var a: float = clampf(_banner.t / 0.5, 0, 1) * clampf((_banner.max - _banner.t) / 0.25 + 0.2, 0, 1)
		var c: Color = _banner.col
		c.a = a
		pop_begin(Vector2(W / 2, top + 22), 0.75 + 0.25 * ease_back(clampf((_banner.max - _banner.t) / 0.35, 0, 1)))
		txt(Vector2(W / 2, top + 32), _banner.text, 30, c, HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
		pop_end()
		top += 42.0
		if _banner.sub != "":
			txt(Vector2(W / 2, top + 10), _banner.sub, 14, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
			top += 22.0
	if _subtitle.t > 0:
		var sa: float = clampf(_subtitle.t / 0.4, 0, 1) * clampf((_subtitle.max - _subtitle.t) / 0.18 + 0.2, 0, 1)
		var is_foe: bool = _subtitle.speaker in ["Spore Zeppelin", "Dread Monarch", "Sir Shellbash", "Queen Stinger", "Digger Duke", "Spore Witch"]
		var badge := "👑 " if is_foe else "🎙️ "
		var line := "%s%s: \"%s\"" % [badge, _subtitle.speaker, _subtitle.text]
		line = fit(line, W - 480, 13)
		var sw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24
		var sy := top + 4.0
		var edge := Color(0.97, 0.44, 0.44, 0.75 * sa) if is_foe else Color(0.99, 0.88, 0.28, 0.65 * sa)
		var tcol := Color(1.0, 0.85, 0.85, sa) if is_foe else Color(0.99, 0.96, 0.82, sa)
		panel(Rect2(W / 2 - sw / 2, sy, sw, 25), Color(0.04, 0.09, 0.06, 0.85 * sa), edge, 9)
		txt(Vector2(W / 2, sy + 17), line, 13, tcol, HORIZONTAL_ALIGNMENT_CENTER)

	if clash.is_empty() and phase == "playing" and not snap.waveActive:
		_draw_wave_preview(W, H)
	if _pest_card.t > 0 and phase == "playing":
		_draw_pest_card(W)
	if not h.is_empty():
		_draw_hero_bar(h, W, H)
		if phase == "playing":
			_draw_buffs(h, W, H)
	if couch and phase == "playing":
		_draw_couch(W, H)
	if emote_open and phase == "playing":
		_draw_emote_bar(W, H)
	if clash.is_empty():
		_draw_build_bar(me, W, H)
		if _eshop_on():
			_draw_endless_shop(me, H)
	else:
		if not h.is_empty() and h.get("canShop", false) and phase == "playing":
			var sr := _draw_shop(h, me, W, H)
			# keep the map in view while deciding where to go next
			var mw := 216.0
			var mh := 132.0
			if not shop_all and sr.position.y - mh - 18 >= 200:
				_draw_minimap(clash, W, H, Rect2(W - mw - 12, sr.position.y - mh - 14, mw, mh))
			elif sr.position.x - mw - 14 >= W / 2 + 258:
				_draw_minimap(clash, W, H, Rect2(sr.position.x - mw - 14, H - mh - 64, mw, mh))
		else:
			_draw_minimap(clash, W, H)
		if not h.is_empty() and h.get("dead", false) and phase == "playing":
			txt(Vector2(W / 2, H * 0.36), "💫 Knocked out! Back in %ds" % ceili(float(h.respawnT)), 30, Color("fecaca"), HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
			txt(Vector2(W / 2, H * 0.36 + 30), "A friend standing right next to you can revive you sooner. You can still shop!", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	_draw_controls(W, H)
	# --- bottom-left corner, bottom up: build bar, your towers, then messages (the cards go over them)
	var stack := _bl_top - 6.0
	if clash.is_empty() and phase == "playing" and not h.is_empty():
		stack = _draw_towers(me, stack) - 6.0
	if auto_cards and not h.is_empty() and phase == "playing" and not me.get("bot", false):
		stack = _draw_evolve(h, stack) - 6.0
	if not auto_cards and not h.is_empty() and h.pending > 0 and h.offer.size() > 0 and phase == "playing" and not me.get("bot", false):
		if cards_hidden:
			_cards_key = ""  # (they slide in again when shown)
			var label := "⭐ %d card%s waiting · C to show" % [int(h.pending), "s" if int(h.pending) > 1 else ""]
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28
			button(Rect2(W / 2 - w / 2, _hero_bar_rect(W, H).position.y - 62, w, 32), label, {"t": "show_cards"}, Color("854d0e"), 14, true)
		else:
			_draw_cards(h, W, H)

	_draw_toasts(stack)
	if _build_tip != "":
		var tw := minf(520.0, _font.get_string_size(_build_tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24)
		panel(Rect2(12, H - 146, tw, 32), Color(0.05, 0.1, 0.07, 0.97))
		txt(Vector2(24, H - 125), fit(_build_tip, tw - 22, 13), 13)

	if net_note != "":
		txt(Vector2(W / 2, H - 8), net_note, 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	if net_trouble != "":
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.45))
		var nw := _font.get_string_size(net_trouble, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 48
		panel(Rect2(W / 2 - nw / 2, H / 2 - 50, nw, 92), Color(0.06, 0.1, 0.08, 0.95), Color("fcd34d"))
		txt(Vector2(W / 2, H / 2 - 12), net_trouble, 22, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER)
		txt(Vector2(W / 2, H / 2 + 20), "Your hero is safe: a Bot Buddy plays it until you're back.", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if snap.paused and phase == "playing" and not menu_open:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35))
		txt(Vector2(W / 2, H / 2), "⏸ Paused", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
		txt(Vector2(W / 2, H / 2 + 40), "Press P to keep playing", 18, Color("d1fae5"), HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	if phase == "victory" or phase == "gameover":
		if _end_since < 0:
			_end_since = _time
			if phase == "victory":
				_throw_confetti(W, H)
		var ek := clampf((_time - _end_since) / 0.4, 0.0, 1.0)
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55 * ek))
		pop_begin(Vector2(W / 2, H / 2), 0.86 + 0.14 * ease_back(ek))
		_draw_end(phase == "victory", W, H)
		pop_end()
	else:
		_end_since = -1.0
		if menu_open:
			if _menu_since < 0:
				_menu_since = _time
			var mk := clampf((_time - _menu_since) / 0.22, 0.0, 1.0)
			pop_begin(Vector2(W / 2, H / 2), 0.92 + 0.08 * ease_back(mk))
			_draw_pause_menu(W, H)
			pop_end()
	if not menu_open:
		_menu_since = -1.0
	if show_stats and not menu_open:
		_draw_stats(W, H)
	for c in _confetti:
		# a paper square tumbling: thin when it's edge-on
		var a: float = minf(1.0, c.life * 2.0)
		draw_set_transform(c.p, c.rot * 0.3, Vector2.ONE)
		draw_rect(Rect2(-c.size / 2, -c.size * 0.35 * absf(cos(c.rot)) - 0.5, c.size, c.size * 0.7 * absf(cos(c.rot)) + 1.0), Color(c.col.r, c.col.g, c.col.b, a))
	if not _confetti.is_empty():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A friend just used their special close by and mine is ready: casting it now makes
## a Team Combo. {near (close enough now), what (the combo's name), who, left (seconds), col}
func combo_invite(h: Dictionary) -> Dictionary:
	var co: Dictionary = snap.get("comboOpen", {})
	if co.is_empty() or h.is_empty() or int(co.owner) == int(h.owner) or float(h.get("specialCd", 1.0)) > 0.05 or h.get("dead", false):
		return {}
	var friend := {}
	for x in snap.get("heroes", []):
		if int(x.id) == int(co.hero):
			friend = x
	if friend.is_empty():
		return {}
	var at := Vector2(h.x, h.y)
	if int(h.owner) == my_owner and hero_at != null:
		at = hero_at
	var d := at.distance_to(Vector2(co.x, co.y))
	if d > SimWorld.COMBO_REACH + 300.0:
		return {}
	var pair := [String(h.type), String(friend.type)]
	pair.sort()
	var named: Array = SimWorld.NAMED_COMBOS.get("%s+%s" % pair, [])
	return {"near": d <= SimWorld.COMBO_REACH, "what": String(named[1]) if not named.is_empty() else "a Team Combo",
		"who": String(_player(int(co.owner)).get("name", "your friend")).substr(0, 12), "left": float(co.left), "col": GameData.player_color(int(friend.slot))}


## The hero bar sits in the middle, nudged right if the build bar needs the room.
## With a big UI size there's no room beside it, so it sits on top of the build bar.
func _hero_bar_rect(W: float, H: float) -> Rect2:
	var x := W / 2 - 250
	if not snap.has("clash"):
		var lo := 12 + _build_bar_w() + 10
		var hi := W - 234 - 10 - 500
		if hi < lo:
			return Rect2(12, H - 108 - (36.0 if _eshop_on() else 0.0) - 8 - 80, 500, 80)
		x = clampf(x, lo, hi)
	return Rect2(x, H - 92, 500, 80)


## Endless wave 5+: the shop row above the build bar
func _eshop_on() -> bool:
	return snap.get("endless", false) and int(snap.wave) >= 5 and snap.phase == "playing" and not snap.has("clash")


func _build_bar_w() -> float:
	var n := GameData.GADGET_ORDER.size()
	return 16 + n * (_build_cell() + (6 if n <= 6 else 5))


func _build_cell() -> float:
	return 54.0 if GameData.GADGET_ORDER.size() <= 6 else 50.0


func _draw_hero_bar(h: Dictionary, W: float, H: float) -> void:
	var r := _hero_bar_rect(W, H)
	panel(r)
	_block_rects.append(r)
	_prompt_y = r.position.y - (60.0 if h.has("maxHp") else 34.0)
	if r.position.x <= 12.0:
		_bl_top = minf(_bl_top, r.position.y - 30)  # stacked on the build bar (with its buff chips above it)
	var info: Dictionary = GameData.HERO_INFO.get(h.type, {})
	var tower: Dictionary = GameData.TOWERS.get(h.type, {})
	# level badge
	var bc := Vector2(r.position.x + 40, r.position.y + 40)
	draw_circle(bc, 27, Color("ca8a04"))
	draw_circle(bc, 23, Color("facc15"))
	txt(bc + Vector2(0, -4), "LV", 11, Color("713f12"), HORIZONTAL_ALIGNMENT_CENTER)
	txt(bc + Vector2(0, 15), str(h.level), 20, Color("422006"), HORIZONTAL_ALIGNMENT_CENTER)
	# name + xp
	var x0 := r.position.x + 78
	var hero_name := String(tower.get("name", h.type))
	txt(Vector2(x0, r.position.y + 26), hero_name, 17, Color(tower.get("color", "#ffffff")))
	var tiers := "A%d · B%d" % [h.tierA, h.tierB]
	txt(Vector2(x0 + _font.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 10, r.position.y + 26), tiers, 12, Color("a7f3d0"))
	var k: float = float(h.xp) / maxf(1.0, float(h.xpNext))
	if int(_shown.get("xp_lv", h.level)) != int(h.level):
		_shown["xp"] = 0.0  # levelled up: fill the new bar from empty
	_shown["xp_lv"] = int(h.level)
	meter(Rect2(x0, r.position.y + 38, 220, 14), eased("xp", k, 7.0), Color("38bdf8"))
	txt(Vector2(x0 + 110, r.position.y + 50), "%d / %d XP" % [h.xp, h.xpNext], 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var waiting: int = GameData.path_waiting(int(h.tierA), int(h.tierB), int(h.level), int(h.pending)) if auto_cards else int(h.pending)
	if waiting > 0:
		var pulse := 0.6 + 0.4 * sin(_time * 6)
		var note := "⭐ Pick your evolution on the left!" if auto_cards else "⭐ %d card%s to pick! Press 1, 2 or 3" % [h.pending, "s" if h.pending > 1 else ""]
		txt(Vector2(x0, r.position.y + 72), note, 13, Color(1, 0.9, 0.3, pulse))
	else:
		txt(Vector2(x0, r.position.y + 72), fit(String(info.get("style", "")), r.end.x - 165 - x0, 12), 12, Color("bbf7d0"))
	# abilities
	var sp: Dictionary = info.get("special", {})
	ability(Vector2(r.end.x - 136, r.position.y + 36), 25, String(sp.get("icon", "✨")), "Q", h.specialCd, h.specialMax, {"t": "special"}, Color("a855f7"))
	ability(Vector2(r.end.x - 80, r.position.y + 36), 22, "💨", "Shift", h.dashCd, float(GameData.DASH.cooldown), {"t": "dash_ui"}, Color("22c55e"))
	if h.has("maxHp"):
		ability(Vector2(r.end.x - 30, r.position.y + 36), 18, "🏡", "B", 0.0, 1.0, {"t": "home"}, Color("0ea5e9"))
		_draw_clash_hero_extras(h, r)
	else:
		ability(Vector2(r.end.x - 30, r.position.y + 36), 18, "🏡", "H", h.homeCd, 18.0, {"t": "home"}, Color("0ea5e9"))
	var inv := combo_invite(h)
	if not inv.is_empty():
		# a friend just used their special nearby: answer it with yours for a Team Combo
		var sc := Vector2(r.end.x - 136, r.position.y + 36)
		var col: Color = inv.col
		var pulse := 0.5 + 0.5 * sin(_time * 12.0)
		if inv.near:
			draw_arc(sc, 30 + pulse * 6, 0, TAU, 40, Color(col.r, col.g, col.b, 0.95), 4, true)
		var line := ("⚡ Press Q now: %s with %s!" if inv.near else "⚡ Get close to %s for %s!") % ([inv.what, inv.who] if inv.near else [inv.who, inv.what])
		line += "  %ds" % ceili(float(inv.left))
		_prompt(r, line, Color(col.r, col.g, col.b, 0.6 + 0.4 * pulse))
	if h.has("maxHp"):
		_draw_clash_prompts(h, r)


## Chips that ask for something right now stack up above the hero panel
var _prompt_y := 0.0


func _prompt(r: Rect2, line: String, edge: Color, buttons: Array = []) -> void:
	var lw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 26
	var bws: Array = []
	for b in buttons:
		bws.append(_font.get_string_size(String(b[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22)
		lw += bws[-1] + 6
	var cr := Rect2(r.end.x - lw, _prompt_y - 30, lw, 30)
	panel(cr, Color(0.12, 0.1, 0.02, 0.94), edge, 10)
	_block_rects.append(cr)
	txt(Vector2(cr.position.x + 13, cr.position.y + 20), line, 14, Color("fef08a"))
	var x := cr.end.x - 4
	for i in range(buttons.size() - 1, -1, -1):
		x -= bws[i]
		button(Rect2(x, cr.position.y + 3, bws[i], 24), String(buttons[i][0]), buttons[i][1], buttons[i][2], 13, true)
		x -= 6
	_prompt_y -= 36


## Garden Clash asks: grow something on the plot I'm standing at; a friend
## going home to shop wants their lane covered
func _draw_clash_prompts(h: Dictionary, r: Rect2) -> void:
	var pl := plot_here()
	if not pl.is_empty():
		_prompt(r, "🌱 Grow here:", Color("86efac"), [["1 🫐 Berry Bush (heals)", {"t": "plot", "id": int(pl.id), "grow": "berry"}, Color("6b21a8")],
			["2 🌱 Spring Vine (leap)", {"t": "plot", "id": int(pl.id), "grow": "vine"}, Color("15803d")]])
	var cv := cover_request()
	if not cv.is_empty():
		var who := String(_player(int(cv.from)).get("name", "A friend")).substr(0, 12)
		_prompt(r, "🛡️ %s went home to shop" % who, Color("7dd3fc"), [["G: I'll cover the %s" % ClashWorld.LANE_NAMES[int(cv.lane)], {"t": "cover_accept", "from": int(cv.from)}, Color("1e3a5f")]])


## A claimed (ready) Garden Plot right by my hero, or {}
func plot_here() -> Dictionary:
	var h := my_hero()
	if h.is_empty() or h.get("dead", false):
		return {}
	var at: Vector2 = hero_at if hero_at != null else Vector2(h.x, h.y)
	for pl in snap.get("clash", {}).get("plots", []):
		if String(pl.state) == "ready" and at.distance_to(Vector2(pl.x, pl.y)) <= ClashWorld.PLOT_REACH + 50:
			return pl
	return {}


## A friend asked for their lane to be covered and nobody has said yes yet
func cover_request() -> Dictionary:
	var cs: Array = snap.get("clash", {}).get("covers", [])
	if cs.any(func(c): return int(c.by) == my_owner):
		return {}
	for c in cs:
		if int(c.by) < 0 and int(c.from) != my_owner:
			return c
	return {}


func _draw_build_bar(me: Dictionary, W: float, H: float) -> void:
	var n := GameData.GADGET_ORDER.size()
	var cw := _build_cell()
	var gap := 6.0 if n <= 6 else 5.0
	var r := Rect2(12, H - 108, _build_bar_w(), 96)
	panel(r)
	_block_rects.append(r)
	_build_rect = r
	var mine := 0
	for g in snap.get("gadgets", []):
		if g.owner == my_owner:
			mine += 1
	var cap := int(GameData.gadgets.limitPerPlayer)
	txt(Vector2(24, H - 88), "Build %d/%d" % [mine, cap], 12, Color("fde047") if mine >= cap else Color("bbf7d0"))
	txt(Vector2(r.end.x - 10, H - 88), "1-%d pick · F or click to build · U up · X sell" % mini(9, n), 10, Color(0.73, 0.97, 0.82, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	var acorns := int(me.get("acorns", 0))
	var hovered := ""
	var hero_mode: bool = snap.get("mutators", []).has("heroes")
	for i in n:
		var kind: String = GameData.GADGET_ORDER[i]
		if hero_mode and not GameData.GADGETS[kind].get("once", false):
			acorns = -1  # Hero Mode: only Seed Bombs (drawn greyed out)
		else:
			acorns = int(me.get("acorns", 0))
		var def: Dictionary = GameData.GADGETS[kind]
		var cr := Rect2(20 + i * (cw + gap), H - 78, cw, 58)
		var sel := kind == selected_gadget
		var afford: bool = acorns >= int(def.cost)
		var hover := cr.has_point(get_local_mouse_position())
		draw_style_box(UiKit.box(Color(0.1, 0.25, 0.15, 0.95) if sel else Color(0.04, 0.09, 0.06, 0.9), Color("fde047") if sel else Color(1, 1, 1, 0.35 if hover else 0.15), 10, 2 if sel else 1, 0), cr)
		var t: Texture2D = Sprites.gadget_tex(kind, 1, -1, int(me.get("slot", 0)))
		if t:
			# Frame the plant above its rank badge at toolbar size.
			var source := Rect2(44, 126, 137, 66) if kind == "thorns" else Rect2(65, 90, 95, 102)
			var extent := source.size * minf((cw - 8.0) / source.size.x, 36.0 / source.size.y)
			var at := cr.position + Vector2((cw - extent.x) / 2.0, 22.0 - extent.y / 2.0)
			draw_texture_rect_region(t, Rect2(at, extent), source, Color.WHITE if afford else Color(1, 1, 1, 0.45))
		txt(Vector2(cr.get_center().x, cr.end.y - 3), "%d" % int(def.cost), 12, Color("fcd34d") if afford else Color("fca5a5"), HORIZONTAL_ALIGNMENT_CENTER, -1, 3)
		txt(cr.position + Vector2(6, 13), str(i + 1), 10, Color(1, 1, 1, 0.55))
		_buttons.append([cr, {"t": "select_gadget", "kind": kind}])
		if hover:
			hovered = kind
	if hero_mode:
		txt(Vector2(r.position.x + r.size.x / 2, H - 46), "🦸 Hero Mode: Seed Bombs only", 13, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	_bl_top = minf(_bl_top, r.position.y)
	if r.has_point(get_local_mouse_position()):
		var def: Dictionary = GameData.GADGETS[hovered if hovered != "" else selected_gadget]
		_build_tip = "%s %s (%d acorns): %s" % [def.icon, def.name, int(def.cost), def.desc]


func _draw_controls(W: float, H: float) -> void:
	var x := W - 12.0
	var y := H - 56.0
	if snap.phase == "playing" and not snap.waveActive and not snap.has("clash"):
		var label := "▶ Start Wave %d  (%s)" % [int(snap.wave) + 1, "Space · 🎮 Start" if not Input.get_connected_joypads().is_empty() else "Space"]
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 34
		var pulse := 0.5 + 0.5 * sin(_time * 3.5)
		button(Rect2(x - w, y - 52, w, 44), label, {"t": "wave"}, Color("15803d").lerp(Color("16a34a"), pulse), 17, true)
	if not is_host:
		# LAN friends: the host controls pause and speed
		button(Rect2(x - 44, y, 44, 40), "🔇" if Audio.muted else "🔊", {"t": "mute"}, Color("334155"), 17, Audio.muted)
		return
	button(Rect2(x - 44, y, 44, 40), "", {"t": "pause"}, Color("334155"), 18, snap.paused)
	if snap.paused:
		UiKit.icon_play(self, Vector2(x - 22, y + 20), 18)
	else:
		UiKit.icon_pause(self, Vector2(x - 22, y + 20), 18)
	button(Rect2(x - 98, y, 48, 40), "%dx" % int(snap.speed), {"t": "speed"}, Color("334155"), 16, snap.speed > 1)
	if not snap.has("clash"):
		button(Rect2(x - 172, y, 68, 40), "Auto", {"t": "auto"}, Color("334155"), 15, snap.autoWave)
		button(Rect2(x - 222, y, 44, 40), "🔇" if Audio.muted else "🔊", {"t": "mute"}, Color("334155"), 17, Audio.muted)
	else:
		button(Rect2(x - 148, y, 44, 40), "🔇" if Audio.muted else "🔊", {"t": "mute"}, Color("334155"), 17, Audio.muted)


func _draw_cards(h: Dictionary, W: float, H: float) -> void:
	# kept small so they don't hide the fight ("Level-ups: automatic" doesn't show them at all)
	var cw := 170.0
	var ch := 140.0
	var gap := 10.0
	var n: int = h.offer.size()
	var x0 := W / 2 - (n * cw + (n - 1) * gap) / 2
	var y0 := _hero_bar_rect(W, H).position.y - ch - 34  # clear of the buff / Target chips over the hero panel
	_cards_rect = Rect2(x0, y0 - 34, n * cw + (n - 1) * gap, ch + 34)
	txt(Vector2(W / 2, y0 - 10), "⭐ Level up! Pick one (1, 2, 3)", 15, Color("fde047"), HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	button(Rect2(x0 + n * cw + (n - 1) * gap - 66, y0 - 30, 66, 22), "▾ hide (C)", {"t": "hide_cards"}, Color("334155"), 10)
	var key := str(h.offer)
	if key != _cards_key:
		_cards_key = key
		_cards_t = _time
	var free := int(h.get("rerolls", 0))
	var rl := ("🎲 New cards (R) · %d free" % free) if free > 0 else ("🎲 New cards (R) · %d🌰" % GameData.REROLL_COST)
	var can := free > 0 or int(my_player().get("acorns", 0)) >= GameData.REROLL_COST
	button(Rect2(x0, y0 - 30, 150, 22), rl, {"t": "reroll"}, Color("6d28d9") if can else Color("3f3f46"), 10)
	for i in n:
		var c: Dictionary = h.offer[i]
		var r := Rect2(x0 + i * (cw + gap), y0, cw, ch)
		var hover := r.has_point(get_local_mouse_position())
		var title := ""
		var desc := ""
		var head := ""
		var icon := "⭐"
		var col := Color("4ade80")
		if c.kind == "path":
			var path: Dictionary = GameData.TOWERS[h.type].paths[c.path]
			var tier: Dictionary = path.tiers[int(c.tier) - 1]
			title = tier.name
			desc = tier.desc
			head = "%s · Path %s, tier %d" % [path.name, c.path, int(c.tier)]
			col = Color("facc15") if c.path == "A" else Color("38bdf8")
			icon = "🅰️" if c.path == "A" else "🅱️"
		else:
			var sc: Dictionary = GameData.STAT_CARDS.get(c.id, {})
			title = sc.get("name", c.id)
			desc = sc.get("desc", "")
			icon = sc.get("icon", "⭐")
			head = "Card %d/%d" % [int(GameData.gnum(h.cards, c.id)) + 1, int(sc.get("max", 1))]
			col = Color("a78bfa")
			if sc.get("capstone", false):
				head = "✨ Rare card"
				col = Color("fbbf24")
		# new cards slide up and pop in one after another; a hovered card lifts
		var ak := clampf((_time - _cards_t - i * 0.06) / 0.32, 0.0, 1.0)
		var eb := ease_back(ak)
		var hit_r := r
		pop_begin(r.get_center(), 0.82 + 0.18 * eb, Vector2(0, (1.0 - eb) * 50.0 - 5.0 * eased("card%d" % i, 1.0 if hover else 0.0, 16.0)))
		draw_style_box(UiKit.box(Color(0.06, 0.13, 0.09, 0.95), col if hover else Color(col.r, col.g, col.b, 0.7), 12, 2, 0), r)
		draw_circle(r.position + Vector2(15, 15), 10, col)
		txt(r.position + Vector2(15, 20), str(i + 1), 13, Color("111827"), HORIZONTAL_ALIGNMENT_CENTER)
		txt(r.position + Vector2(cw / 2, 36), icon, 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		txt(r.position + Vector2(cw / 2, 58), fit(title, cw - 12, 14), 14, col.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
		txt(r.position + Vector2(cw / 2, 72), fit(head, cw - 12, 10), 10, Color("a7f3d0"), HORIZONTAL_ALIGNMENT_CENTER)
		wrap_text(r.position + Vector2(8, 88), desc, cw - 16, 11, Color("ecfdf5"), 2)
		if c.kind == "path":
			# progress along that path: ● = tiers you'll have
			var pips := ""
			for t in 4:
				pips += "●" if t < int(c.tier) else "○"
			txt(r.position + Vector2(cw - 10, 20), pips, 10, col, HORIZONTAL_ALIGNMENT_RIGHT)
		var delta := _card_delta(h, c)
		if delta != "":
			txt(r.position + Vector2(cw / 2, ch - (22 if c.kind == "path" and int(c.tier) == 3 else 9)), fit(delta, cw - 12, 10), 10, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER)
		if c.kind == "path" and int(c.tier) == 3:
			txt(r.position + Vector2(cw / 2, ch - 8), "🔒 Path %s stops at tier 2" % ("B" if c.path == "A" else "A"), 9, Color("fdba74"), HORIZONTAL_ALIGNMENT_CENTER)
		pop_end()
		_buttons.append([hit_r, {"t": "card", "i": i}])


func _draw_end(win: bool, W: float, H: float) -> void:
	var awards := _awards()
	var story: Array = snap.get("clash", {}).get("summary", [])
	var extra := (34.0 if not awards.is_empty() else 0.0) + (30.0 if not new_unlocks.is_empty() else 0.0) + (34.0 + story.size() * 22.0 if not story.is_empty() else 0.0)
	var content := extra  # what goes under the hero rows
	extra -= (4 - clampi(snap.get("players", []).size(), 1, 4)) * 28.0  # no empty rows when fewer than 4 play
	var r := Rect2(W / 2 - 300, H / 2 - 210 - extra / 2, 600, 420 + extra)
	panel(r, Color(0.05, 0.12, 0.08, 0.97), Color("fde047") if win else Color("fb7185"), 22)
	_block_rects.append(r)
	txt(Vector2(W / 2, r.position.y + 62), "🏆 Victory!" if win else "🍂 The Bloom Tree fell", 38, Color("fde047") if win else Color("fda4af"), HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
	var sub := ("You saved the garden on %s!" % _diff_name()) if win else ("You reached wave %d. Try again!" % snap.wave)
	if snap.has("clash"):
		var how := "Quick Clash on %s" % _diff_name() if snap.clash.get("quick", false) else _diff_name()
		sub = ("You smashed the Thorn Heart on %s!" % how) if win else "The pests broke the Bloom Tree. Try again!"
	txt(Vector2(W / 2, r.position.y + 96), sub, 17, Color("d1fae5"), HORIZONTAL_ALIGNMENT_CENTER)
	var y := r.position.y + 140
	txt(Vector2(r.position.x + 40, y), "Hero", 13, Color("a7f3d0"))
	var clash := snap.has("clash")
	var cols := [["Pops", 300], ["Damage", 370], ["Rivals", 460], ["Towers", 540]] if clash else [["Pops", 300], ["Damage", 370], ["Specials", 460], ["Built", 540]]
	for k in cols:
		txt(Vector2(r.position.x + k[1], y), k[0], 13, Color("a7f3d0"), HORIZONTAL_ALIGNMENT_RIGHT)
	y += 28
	for p in snap.get("players", []):
		draw_circle(Vector2(r.position.x + 48, y - 5), 7, GameData.player_color(p.slot))
		txt(Vector2(r.position.x + 62, y), String(p.name).substr(0, 18), 16)
		txt(Vector2(r.position.x + 300, y), str(p.pops), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		txt(Vector2(r.position.x + 370, y), _short(p.damage), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		txt(Vector2(r.position.x + 460, y), str(p.get("rivalKOs", 0) if clash else p.specials), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		txt(Vector2(r.position.x + 540, y), str(p.get("towersDown", 0) if clash else p.built), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 28
	var mins := int(snap.time) / 60
	var ay := r.end.y - 92 - content
	if not story.is_empty():
		# the match in three moments, in the order they happened
		ay += 4
		txt(Vector2(W / 2, ay), "📜 How it went", 14, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER)
		for i in story.size():
			ay += 22
			var it: Dictionary = story[i]
			var line := "%d:%02d   %s" % [int(it.t) / 60, int(it.t) % 60, String(it.text)]
			txt(Vector2(W / 2, ay), fit(line, r.size.x - 60, 14), 14, Color("ecfccb") if String(it.kind) != "lost" else Color("fecaca"), HORIZONTAL_ALIGNMENT_CENTER)
		ay += 30
	txt(Vector2(W / 2, ay), "Time: %d:%02d" % [mins, int(snap.time) % 60], 15, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_CENTER)
	if not awards.is_empty():
		ay += 32
		txt(Vector2(W / 2, ay), fit("   ".join(awards), r.size.x - 40, 14), 14, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER)
	if not new_unlocks.is_empty():
		ay += 30
		txt(Vector2(W / 2, ay), fit("🎉 NEW: " + ", ".join(new_unlocks), r.size.x - 40, 15), 15, Color("f0abfc"), HORIZONTAL_ALIGNMENT_CENTER, -1, 3)
	var by := r.end.y - 70
	if is_host and win and next_challenge != "":
		button(Rect2(W / 2 - 285, by, 190, 48), "Play again", {"t": "again"}, Color("1e3a5f"), 15)
		button(Rect2(W / 2 - 85, by, 220, 48), next_challenge, {"t": "next"}, Color("15803d"), 15, true)
		button(Rect2(W / 2 + 145, by, 140, 48), "Menu (Esc)", {"t": "menu"}, Color("334155"), 15)
	elif is_host:
		button(Rect2(W / 2 - 200, by, 190, 48), "Play again (Enter)", {"t": "again"}, Color("15803d"), 16)
		button(Rect2(W / 2 + 10, by, 190, 48), "Menu (Esc)", {"t": "menu"}, Color("334155"), 16)
	else:
		button(Rect2(W / 2 - 95, by, 190, 48), "Menu (Esc)", {"t": "menu"}, Color("334155"), 16)


## Team awards: everyone's good at something (support heroes too). Revives,
## combos and reactions go first, and nobody gets a second award before
## everyone who earned one has one.
func _awards() -> Array:
	var players: Array = snap.get("players", [])
	if players.size() < 2:
		return []
	var picks := [["💚 Lifesaver", "revives"], ["🤝 Combo Buddy", "combos"], ["⚡ Reaction Master", "reactions"], ["🎯 Pest Popper", "pops"], ["💥 Big Hitter", "damage"], ["🌞 Sun Gatherer", "sun"]]
	if snap.has("clash"):
		picks += [["👑 Rival Hunter", "rivalKOs"], ["🌵 Tower Smasher", "towersDown"]]
	else:
		picks += [["🏗️ Master Builder", "built"]]
	var cands: Array = []  # [label, winner]
	for pk in picks:
		var best = null
		var bv := 0.0
		for p in players:
			var v := float(p.get(pk[1], 0))
			if v > bv:
				bv = v
				best = p
		if best:
			cands.append([pk[0], best])
	var out: Array = []
	var got := {}
	for pass_i in 2:
		for c in cands:
			if out.size() >= 4 or out.has(c):
				continue
			if pass_i == 0 and got.has(c[1].id):
				continue
			out.append(c)
			got[c[1].id] = true
	return out.map(func(c): return "%s: %s" % [c[0], String(c[1].name).substr(0, 10)])


func _diff_name() -> String:
	return String(GameData.DIFFICULTIES.get(snap.difficulty, {}).get("name", snap.difficulty))


func _short(n) -> String:
	var v := float(n)
	if v >= 1000000:
		return "%.1fM" % (v / 1000000.0)
	if v >= 1000:
		return "%.1fk" % (v / 1000.0)
	return str(int(v))


func _player(id: int) -> Dictionary:
	for p in snap.get("players", []):
		if p.id == id:
			return p
	return {}


# ---------------------------------------------------------------------------
# Shared panels
# ---------------------------------------------------------------------------
func _draw_tree_panel(lives_k: float, me: Dictionary) -> void:
	var extra: bool = snap.waveActive or float(snap.get("autoIn", 0)) > 0
	var tl := Rect2(12, 12, 420 if extra else 330, 66)
	panel(tl)
	_block_rects.append(tl)
	UiKit.icon_tree(self, Vector2(36, 34), 24)
	txt(Vector2(56, 38), "Bloom Tree", 13, Color("bbf7d0"))
	var rules := ""
	for m in snap.get("mutators", []):
		rules += String(GameData.MUTATORS.get(m, {}).get("icon", ""))
	if rules != "":
		# Garden Rules in play: a little pill to the right of this panel
		var rr := Rect2(tl.end.x + 6, 12, _font.get_string_size(rules, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20, 28)
		panel(rr, Color(0.2, 0.1, 0.3, 0.85), Color("c084fc"), 10)
		txt(Vector2(rr.position.x + 10, 32), rules, 14)
		if rr.has_point(get_local_mouse_position()):
			var names: Array = snap.get("mutators", []).map(func(m): return String(GameData.MUTATORS.get(m, {}).get("name", m)))
			var tip := "Garden Rules: " + ", ".join(names)
			panel(Rect2(rr.position.x, rr.end.y + 4, _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20, 26), Color(0.05, 0.1, 0.07, 0.95))
			txt(Vector2(rr.position.x + 10, rr.end.y + 22), tip, 12)
	var shown_k := eased("lives", lives_k, 9.0)
	meter(Rect2(56, 44, 120, 14), shown_k, Color("4ade80") if lives_k > 0.5 else (Color("facc15") if lives_k > 0.25 else Color("fb7185")), Color(0, 0, 0, 0.45), eased("lives_trail", lives_k, 1.6))
	txt(Vector2(182, 57), "%d/%d" % [snap.lives, snap.maxLives], 14)
	var wave_label := ("Wave %d" % snap.wave) if snap.endless else ("Wave %d/%d" % [snap.wave, snap.maxWave])
	txt(Vector2(250, 38), wave_label, 15, Color("fde68a"))
	UiKit.acorns_text(self, Vector2(250, 60), int(round(eased("acorns", float(me.get("acorns", 0)), 12.0))), 16)
	if snap.waveActive:
		var left: int = snap.get("enemies", []).size() + int(snap.get("toSpawn", 0))
		txt(Vector2(345, 38), "Pests left", 11, Color("bbf7d0"))
		txt(Vector2(345, 60), "🐛 %d" % left, 16, Color.WHITE)
	elif snap.get("autoHold", false):
		txt(Vector2(345, 38), "Next wave", 11, Color("bbf7d0"))
		txt(Vector2(345, 60), "⭐ wait", 16, Color("fde047"))
	elif float(snap.get("autoIn", 0)) > 0:
		txt(Vector2(345, 38), "Next wave", 11, Color("bbf7d0"))
		txt(Vector2(345, 60), "⏱ %ds" % ceili(float(snap.autoIn)), 16, Color("fde047"))
	if not practice.is_empty():
		# Practice Garden: the step to do now
		var pl := String(practice.text)
		var pw := maxf(360.0, _font.get_string_size(pl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 34)
		var pr := Rect2(12, 84, pw, 58)
		var glow := 0.6 + 0.4 * sin(_time * 4.0)
		panel(pr, Color(0.06, 0.2, 0.1, 0.94), Color(0.53, 0.94, 0.67, glow))
		txt(Vector2(26, 104), "🌱 Practice · step %d of %d" % [int(practice.step), int(practice.of)], 12, Color("86efac"))
		txt(Vector2(26, 129), pl, 16, Color.WHITE)
	if snap.get("twist", "") != "":
		var tw: Dictionary = GameData.TWISTS.get(snap.twist, {})
		var line := "🌀 %s: %s" % [tw.get("name", snap.twist), tw.get("desc", "")]
		var r := Rect2(12, 84, minf(_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 26, 640), 30)
		panel(r, Color(0.23, 0.1, 0.3, 0.85), Color("e879f9"))
		txt(Vector2(24, 104), fit(line, r.size.x - 22, 12), 12, Color("f5d0fe"))


func _draw_team(W: float, _h: Dictionary) -> void:
	var heroes: Array = snap.get("heroes", [])
	var clash := snap.has("clash")
	var row := 34.0 if clash else 26.0
	var tr := Rect2(W - 232, 12, 220, 18 + heroes.size() * row)
	panel(tr)
	_block_rects.append(tr)
	var y := 34.0
	for hh in heroes:
		var pl := _player(hh.owner)
		var col: Color = GameData.player_color(hh.slot)
		draw_circle(Vector2(W - 214, y - 5), 7, col)
		var nm: String = String(pl.get("name", "?"))
		if pl.get("away", false):
			nm = "📶 " + nm
		elif pl.get("bot", false):
			nm = "🤖 " + nm
		var giftable: bool = hh.owner != my_owner and not pl.get("bot", false) and snap.phase == "playing"
		txt(Vector2(W - 200, y), nm.substr(0, 9 if giftable else 16), 14, Color.WHITE if hh.owner != my_owner else Color("fde047"))
		txt(Vector2(W - 24, y), "Lv %d" % hh.level, 13, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_RIGHT)
		if giftable:
			# send this friend 25 acorns
			var can: bool = int(my_player().get("acorns", 0)) >= 25
			button(Rect2(W - 112, y - 16, 52, 21), "🎁 25", {"t": "gift", "to": hh.owner}, Color("a16207") if can else Color("3f3f46"), 11)
		if clash:
			if hh.get("dead", false):
				txt(Vector2(W - 200, y + 14), "💫 back in %ds" % ceili(float(hh.respawnT)), 11, Color("fca5a5"))
			else:
				var k: float = float(hh.hp) / maxf(1.0, float(hh.maxHp))
				meter(Rect2(W - 200, y + 5, 176, 6), k, Color("4ade80") if k > 0.5 else (Color("facc15") if k > 0.25 else Color("ef4444")))
		y += row
	# battle feed under the team list (and under the minimap when it's showing)
	var fy := tr.end.y + 22
	if not clash and minimap_on and snap.phase == "playing":
		fy += 132.0 + 10
	for f in _feed:
		var a: float = clampf(f.t / 0.6, 0, 1)
		var w := _font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20
		panel(Rect2(W - 12 - w, fy - 17, w, 24), Color(0.04, 0.08, 0.05, 0.78 * a), Color(1, 1, 1, 0.12 * a), 8)
		txt(Vector2(W - 22, fy), f.text, 13, Color(f.col.r, f.col.g, f.col.b, a), HORIZONTAL_ALIGNMENT_RIGHT)
		fy += 28


# ---------------------------------------------------------------------------
# Garden Clash
# ---------------------------------------------------------------------------
func _draw_clash_top(cl: Dictionary, me: Dictionary, h: Dictionary, W: float) -> void:
	# your acorns & juice (top-left)
	var tl := Rect2(12, 12, 230, 52)
	panel(tl)
	_block_rects.append(tl)
	UiKit.acorns_text(self, Vector2(26, 44), int(me.get("acorns", 0)), 20)
	if not h.is_empty():
		txt(Vector2(130, 44), "🧃 %d/%d" % [int(h.get("potions", 0)), int(GameData.clash.config.maxPotions)], 18, Color("f9a8d4"))
	# the scoreboard (top-center)
	var sw := 470.0
	var x := (W - 232) / 2 - sw / 2 + 120
	var y := 10.0
	var r := Rect2(x, y, sw, 50)
	panel(r, Color(0.04, 0.08, 0.06, 0.85), Color(1, 1, 1, 0.25), 14)
	_block_rects.append(r)
	var heart := {}
	for t in cl.get("foeTowers", []):
		if t.core:
			heart = t
	var tree_k := clampf(float(snap.lives) / maxf(1.0, float(snap.maxLives)), 0, 1)
	var heart_k := clampf(float(heart.get("hp", 0)) / maxf(1.0, float(heart.get("maxHp", 1))), 0, 1)
	var ally_left := 0
	for t in cl.get("allyTowers", []):
		if (t.kind == "tower" or t.kind == "guardian") and t.hp > 0:
			ally_left += 1
	var foe_left := 0
	for t in cl.get("foeTowers", []):
		if not t.core and int(t.tier) != 3 and t.hp > 0:
			foe_left += 1
	UiKit.icon_tree(self, Vector2(x + 20, y + 20), 22)
	txt(Vector2(x + sw - 20, y + 25), "💜", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	meter(Rect2(x + 36, y + 11, 130, 10), tree_k, Color("4ade80") if tree_k > 0.35 else Color("fb7185"))
	meter(Rect2(x + sw - 166, y + 11, 130, 10), heart_k, Color("e879f9"))
	var t_max := 5 if cl.get("quick", false) else 8  # Quick Clash has one tower before each gate
	txt(Vector2(x + 36, y + 40), "Bloom Towers %d/%d" % [ally_left, t_max], 11, Color("bae6fd"))
	var heart_note := ("🛡️ Thorn Towers %d/%d" % [foe_left, t_max]) if heart.get("shield", true) else ("Thorn Towers %d/%d · HEART OPEN!" % [foe_left, t_max])
	txt(Vector2(x + sw - 36, y + 40), heart_note, 11, Color("f5d0fe"), HORIZONTAL_ALIGNMENT_RIGHT)
	var t := int(cl.get("time", 0))
	txt(Vector2(x + sw / 2, y + 22), "%d:%02d" % [t / 60, t % 60], 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	txt(Vector2(x + sw / 2, y + 40), "Sproutlings in %ds" % ceili(float(cl.get("nextWave", 0))), 10, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_CENTER)
	# rival chips
	var rivals: Array = cl.get("rivals", [])
	var cx := x + sw / 2 - rivals.size() * 122 / 2.0
	for rv in rivals:
		var def: Dictionary = GameData.ENEMIES.get(rv.kind, {})
		var chip := Rect2(cx + 4, y + 54, 114, 22)
		panel(chip, Color(0.24, 0.04, 0.06, 0.85) if rv.alive else Color(0.12, 0.12, 0.12, 0.78), Color(1, 1, 1, 0.15), 10)
		var nm: String = String(def.get("name", rv.kind))
		var label := ("👑 %s Lv%d" % [nm, int(rv.lvl)]) if rv.alive else ("💤 %s %ds" % [nm, int(rv.respawn)])
		txt(Vector2(chip.get_center().x, chip.position.y + 16), label, 10, Color("fecaca") if rv.alive else Color("a3a3a3"), HORIZONTAL_ALIGNMENT_CENTER)
		cx += 122
	if int(cl.get("toadT", 0)) > 0:
		var elder := int(cl.get("elderT", 0)) > 0
		txt(Vector2(x + sw / 2, y + 94), ("👑 Elder Toad Power %ds" % int(cl.elderT)) if elder else ("🐸 Toad Power %ds" % int(cl.toadT)), 12, Color("fde047") if elder else Color("86efac"), HORIZONTAL_ALIGNMENT_CENTER, -1, 3)


## Under the scoreboard: an announced Rival Raid. Top-left: who is covering whose
## lane. Returns where the banner can go.
func _draw_clash_status(cl: Dictionary, W: float) -> float:
	var top := 100.0
	var r: Dictionary = cl.get("raid", {})
	if not r.is_empty():
		var tower: String = {"gate": "Bloom Gate", "guardian": "Tree Guardian"}.get(String(r.kind), "Bloom Tower")
		var line := "⚔️ RAID: %s → %s %s" % [" + ".join(r.names), ClashWorld.LANE_NAMES[int(r.lane)], tower]
		line += ("  in %ds" % int(r.t)) if r.phase == "warn" else "  NOW!"
		var lw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28
		var cx := (W - 232) / 2 + 120
		var pulse := 0.5 + 0.5 * sin(_time * 7.0)
		var rr := Rect2(cx - lw / 2, top, lw, 28)
		panel(rr, Color(0.25, 0.04, 0.06, 0.92), Color(0.97, 0.4, 0.4, 0.6 + 0.4 * pulse), 10)
		txt(Vector2(cx, top + 19), line, 14, Color("fecaca"), HORIZONTAL_ALIGNMENT_CENTER)
		_block_rects.append(rr)
		top += 34
	var y := 70.0
	for c in cl.get("covers", []):
		if int(c.by) < 0:
			continue
		var by := String(_player(int(c.by)).get("name", "?")).substr(0, 10)
		var who := "you" if int(c.from) == my_owner else String(_player(int(c.from)).get("name", "?")).substr(0, 10)
		var line := "🛡️ %s holds the %s for %s · %ds" % [by if int(c.by) != my_owner else "You", ClashWorld.LANE_NAMES[int(c.lane)], who, int(c.t)]
		var lw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20
		panel(Rect2(12, y, lw, 24), Color(0.04, 0.1, 0.16, 0.85), Color("7dd3fc"), 8)
		txt(Vector2(22, y + 16), line, 12, Color("e0f2fe"))
		y += 28
	return top


## Health bar, item slots and Berry Juice under the hero panel
func _draw_clash_hero_extras(h: Dictionary, r: Rect2) -> void:
	var k: float = float(h.hp) / maxf(1.0, float(h.maxHp))
	var hr := Rect2(r.position.x, r.position.y - 26, r.size.x, 22)
	panel(hr, Color(0.04, 0.08, 0.06, 0.85), Color(1, 1, 1, 0.15), 10)
	meter(Rect2(hr.position.x + 8, hr.position.y + 6, hr.size.x - 16, 10), k, Color("4ade80") if k > 0.5 else (Color("facc15") if k > 0.25 else Color("ef4444")))
	txt(Vector2(hr.get_center().x, hr.position.y + 16), "%d / %d" % [int(h.hp), int(h.maxHp)], 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 3)
	_block_rects.append(hr)
	var items: Array = h.get("items", [])
	var n := int(GameData.clash.config.maxItems)
	var iw := 34.0
	var box_w := n * (iw + 4) + 66.0
	var x0 := r.position.x - 10 - box_w + 8
	var y0 := r.position.y + 16
	var box := Rect2(x0 - 8, y0 - 22, box_w, 70)
	panel(box)
	_block_rects.append(box)
	txt(Vector2(x0, y0 - 6), "Items" + (" (click to sell)" if h.get("canShop", false) else ""), 11, Color("bbf7d0"))
	for i in n:
		var cr := Rect2(x0 + i * (iw + 4), y0, iw, iw)
		var id: String = items[i] if i < items.size() else ""
		var info: Dictionary = GameData.clash_item(id) if id != "" else {}
		var golden: bool = info.get("golden", false)
		draw_style_box(UiKit.box(Color(0.25, 0.2, 0.04, 0.95) if golden else Color(0.04, 0.09, 0.06, 0.9), Color("facc15") if golden else Color(1, 1, 1, 0.2), 8, 2 if golden else 1, 0), cr)
		if not info.is_empty():
			txt(Vector2(cr.get_center().x, cr.get_center().y + 8), String(info.icon), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			if h.get("canShop", false):
				_buttons.append([cr, {"t": "sell_item", "i": i}])
			if cr.has_point(get_local_mouse_position()):
				var tip := "%s: %s" % [info.name, info.def.desc] + ((" · sell for %d" % int(floor(float(info.spent) * 0.6))) if h.get("canShop", false) else "")
				var tw := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24
				panel(Rect2(x0, y0 - 64, tw, 30), Color(0.05, 0.1, 0.07, 0.96))
				txt(Vector2(x0 + 12, y0 - 44), tip, 13)
	# Berry Juice
	ability(Vector2(x0 + n * (iw + 4) + 24, y0 + 16), 18, "🧃", "R %d" % int(h.get("potions", 0)), 0.0 if int(h.get("potions", 0)) > 0 else 1.0, 1.0, {"t": "potion"}, Color("db2777"))
	_draw_pinned(h, box)


## The item I pinned: how far off it is, "ready at home", or a one-press buy at the tree
func _draw_pinned(h: Dictionary, box: Rect2) -> void:
	var pin := pinned_state(h)
	if pin.is_empty():
		return
	var line := ""
	var col := Color("fde68a")
	var at_tree: bool = h.get("canShop", false)
	if pin.done:
		pinned_item = ""
		return
	elif pin.blocked != "":
		line = "📌 %s %s: %s" % [pin.icon, pin.name, pin.blocked]
		col = Color("fca5a5")
	elif not pin.afford:
		line = "📌 %s %s: %d more acorns" % [pin.icon, pin.name, int(pin.cost) - int(my_player().get("acorns", 0))]
	elif at_tree:
		var br := Rect2(box.position.x, box.position.y - 32, box.size.x, 28)
		button(br, "📌 F: buy %s %s (%d)" % [pin.icon, pin.name, int(pin.cost)], {"t": "buy_pinned"}, Color("15803d"), 13, true)
		return
	else:
		line = "📌 %s %s ready! B: go home to buy it" % [pin.icon, pin.name]
		col = Color(0.53, 0.94, 0.67, 0.75 + 0.25 * sin(_time * 5.0))
	var lw := minf(box.size.x + 120, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20)
	var cr := Rect2(box.end.x - lw, box.position.y - 28, lw, 24)
	panel(cr, Color(0.06, 0.09, 0.05, 0.9), col, 8)
	txt(Vector2(cr.position.x + 10, cr.position.y + 16), fit(line, lw - 16, 12), 12, col)
	_block_rects.append(cr)


## Can the pinned item be bought right now (at the tree, enough acorns, room for it)?
func can_buy_pinned() -> bool:
	var h := my_hero()
	var pin := pinned_state(h)
	return not pin.is_empty() and not pin.done and pin.blocked == "" and pin.afford and h.get("canShop", false)


## What the pinned item costs and whether it can be bought now
func pinned_state(h: Dictionary) -> Dictionary:
	if pinned_item == "" or h.is_empty():
		return {}
	var golden := pinned_item.ends_with("+")
	var base := pinned_item.trim_suffix("+")
	var info := GameData.clash_item(base)
	if info.is_empty():
		return {}
	var items: Array = h.get("items", [])
	var out := {"name": ("Golden " if golden else "") + String(info.def.name), "icon": String(info.icon), "done": false, "blocked": "",
		"cost": int(info.upgradeCost) if golden else int(info.def.cost), "item": base}
	if items.has(base + "+") or (not golden and items.has(base)):
		out.done = true  # bought it
	elif golden and not items.has(base):
		out.blocked = "buy the plain one first"
	elif not golden and items.size() >= int(GameData.clash.config.maxItems):
		out.blocked = "your item slots are full"
	out.afford = int(my_player().get("acorns", 0)) >= int(out.cost)
	return out


## The Bloom Tree shop: what to do next, two items picked for my hero (or
## every item), Berry Juice. Each item can be pinned (📌) to buy later. Returns its rect.
func _draw_shop(h: Dictionary, me: Dictionary, W: float, H: float) -> Rect2:
	var items: Array = h.get("items", [])
	var acorns := int(me.get("acorns", 0))
	var entries: Array = GameData.clash.itemOrder.duplicate() if shop_all else ClashWorld.recommended_buys(GameData, String(h.type), items, 2)
	entries.append("juice")
	var goal := clash_goal(snap.get("clash", {}))
	var rw := 300.0
	var rh := 44.0
	var head := 36.0 + (34.0 if goal != "" else 0.0) + (0.0 if shop_all else 20.0)
	var r := Rect2(W - rw - 12, 0, rw, head + entries.size() * rh + 34)
	r.position.y = H - 70 - r.size.y
	panel(r, Color(0.05, 0.1, 0.07, 0.93), Color("facc15"), 14)
	_block_rects.append(r)
	txt(Vector2(r.position.x + 14, r.position.y + 24), "🛒 Bloom Tree Shop", 16, Color("fde047"))
	UiKit.acorns_text(self, Vector2(r.end.x - 14, r.position.y + 24), acorns, 15, Color("fcd34d"), true)
	var y := r.position.y + 36
	if goal != "":
		var lines := wrap_lines(goal, rw - 28, 12)
		for i in mini(2, lines.size()):
			txt(Vector2(r.position.x + 14, y + 12 + i * 15), lines[i], 12, Color("bae6fd"))
		y += 34
	if not shop_all:
		var hero_name := String(GameData.TOWERS.get(String(h.type), {}).get("name", "you"))
		txt(Vector2(r.position.x + 14, y + 13), fit("Good for %s: %s" % [hero_name, ClashWorld.HERO_BUY_WHY.get(String(h.type), "")], rw - 28, 11), 11, Color("a7f3d0"))
		y += 20
	for id in entries:
		var cr := Rect2(r.position.x + 8, y, rw - 16, rh - 4)
		var name := ""
		var icon := ""
		var desc := ""
		var cost := 0
		var state := ""
		var target: String = id
		if id == "juice":
			var pd: Dictionary = GameData.clash.potion
			name = pd.name
			icon = pd.icon
			desc = "Drink with R: heals half your health"
			cost = int(pd.cost)
			if int(h.get("potions", 0)) >= int(GameData.clash.config.maxPotions):
				state = "full"
		else:
			var def: Dictionary = GameData.clash.items[id]
			name = def.name
			icon = def.icon
			desc = def.desc
			cost = int(def.cost)
			if items.has(id + "+"):
				state = "golden"
			elif items.has(id):
				var info := GameData.clash_item(id)
				cost = int(info.upgradeCost)
				name = "Golden " + name
				desc = "80% stronger " + String(def.name)
				target = id + "+"
			elif items.size() >= int(GameData.clash.config.maxItems):
				state = "full"
		var afford := acorns >= cost and state == ""
		var mouse := get_local_mouse_position()
		var pin_r := Rect2(cr.end.x - 26, cr.position.y + 8, 22, 24)
		var hover := cr.has_point(mouse) and not pin_r.has_point(mouse)
		var pinned: bool = pinned_item == target and id != "juice"
		draw_style_box(UiKit.box(Color(0.1, 0.22, 0.13, 0.95) if hover and afford else Color(0.04, 0.09, 0.06, 0.9), Color("fde047") if pinned else Color(1, 1, 1, 0.3 if hover else 0.1), 10, 2 if pinned else 1, 0), cr)
		txt(Vector2(cr.position.x + 20, cr.position.y + 28), icon, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		var right := cr.end.x - (30.0 if id != "juice" and state == "" else 10.0)
		txt(Vector2(cr.position.x + 40, cr.position.y + 17), fit(name, right - cr.position.x - 100, 14), 14, Color.WHITE if afford else Color(1, 1, 1, 0.55))
		txt(Vector2(cr.position.x + 40, cr.position.y + 33), fit(desc, right - cr.position.x - 100, 11), 11, Color("a7f3d0") if afford else Color(0.65, 0.95, 0.82, 0.5))
		if cr.has_point(mouse):
			# the whole description, beside the shop
			var tw := _font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24
			var tr := Rect2(r.position.x - tw - 8, cr.position.y + 4, tw, 30)
			panel(tr, Color(0.05, 0.1, 0.07, 0.96))
			txt(Vector2(tr.position.x + 12, tr.position.y + 20), desc, 13)
		if state == "":
			UiKit.acorns_text(self, Vector2(right, cr.position.y + 26), cost, 13, Color("fcd34d") if afford else Color("fca5a5"), true)
			_buttons.append([cr, {"t": "buy", "item": id}])
		else:
			txt(Vector2(right, cr.position.y + 26), "✨ Golden" if state == "golden" else "full", 13, Color("fcd34d"), HORIZONTAL_ALIGNMENT_RIGHT)
		if id != "juice" and state == "":
			# 📌 pin it: the hero panel counts down to it, and F buys it next time at the tree
			var ph := pin_r.has_point(mouse)
			draw_style_box(UiKit.box(Color(0.3, 0.25, 0.05, 0.95) if pinned else Color(0.08, 0.12, 0.09, 0.9), Color(1, 1, 1, 0.35 if ph else 0.12), 6, 1, 0), pin_r)
			txt(Vector2(pin_r.get_center().x, pin_r.position.y + 17), "📌", 12, Color.WHITE if pinned or ph else Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
			_buttons.append([pin_r, {"t": "pin", "item": target}])  # later buttons win: the pin is checked first
		y += rh
	button(Rect2(r.position.x + 8, y, rw - 16, 28), "◂ Just the picks for me" if shop_all else "Browse all items ▸", {"t": "shop_all"}, Color("1f2937"), 12)
	return r


## One thing worth doing right now, read from the battle: stop a raid, save a
## building, push before a gate grows back, walk with the Captain...
func clash_goal(cl: Dictionary) -> String:
	if cl.is_empty():
		return ""
	var L: Array = ClashWorld.LANE_NAMES
	var raid: Dictionary = cl.get("raid", {})
	if not raid.is_empty():
		return "⚔️ Stop the raid on the %s!" % L[int(raid.lane)]
	# one of our buildings is low and pests are at it
	for t in cl.get("allyTowers", []):
		if t.kind == "tree" or t.shield or int(t.lane) < 0 or float(t.hp) / maxf(1.0, float(t.maxHp)) > 0.45:
			continue
		for e in snap.get("enemies", []):
			var def: Dictionary = GameData.ENEMIES.get(e.type, {})
			if not def.get("structure", false) and not def.get("neutral", false) and Vector2(e.x - t.x, e.y - t.y).length() < 300:
				return "🛡️ Help the %s: your %s is at %d%%" % [L[int(t.lane)], "gate" if t.kind == "gate" else "tower", int(100.0 * float(t.hp) / maxf(1.0, float(t.maxHp)))]
	var heart := {}
	for t in cl.get("foeTowers", []):
		if t.core:
			heart = t
	if not heart.is_empty() and not heart.get("shield", true):
		return "💜 The Thorn Heart is open: everyone push in together!"
	for rg in cl.get("regrow", []):
		if rg.side == "foe":
			return "⚡ Push the %s: their gate grows back in %d:%02d" % [L[int(rg.lane)], int(rg.t) / 60, int(rg.t) % 60]
	var cap: Dictionary = cl.get("captain", {})
	if not cap.is_empty() and not cap.planted:
		return "🚩 Walk with Captain %s up the %s" % [cap.name, L[int(cap.lane)]]
	# otherwise: the pest building that's closest to falling
	var best := {}
	var bk := 2.0
	for t in cl.get("foeTowers", []):
		if t.core or t.shield or float(t.hp) <= 0 or int(t.lane) < 0:
			continue
		var k := float(t.hp) / maxf(1.0, float(t.maxHp))
		if k < bk:
			bk = k
			best = t
	if best.is_empty():
		return ""
	var what: String = {3: "gate", 4: "Thorn Guardian"}.get(int(best.tier), "Thorn Tower")
	if bk > 0.98:
		return "🌱 Walk down the %s with your Sproutlings to the %s" % [L[int(best.lane)], what]
	return "🌱 Push the %s: their %s is at %d%%" % [L[int(best.lane)], what, int(bk * 100.0)]


func _draw_minimap(cl: Dictionary, W: float, H: float, at_rect := Rect2()) -> void:
	var mw := 216.0
	var mh := 132.0
	var r := at_rect if at_rect.size.x > 0 else Rect2(W - mw - 12, H - mh - 64, mw, mh)
	minimap_rect = r
	draw_style_box(UiKit.box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.3), 8, 2, 0), r.grow(3))
	var tex: Texture2D = Sprites.tex(Sprites.atlas.maps.get(snap.map, ""))
	if tex:
		draw_texture_rect(tex, r, false, Color(1, 1, 1, 0.85))
	_block_rects.append(r)
	var k := Vector2(r.size.x / GameData.W, r.size.y / GameData.H)
	var at := func(x, y) -> Vector2: return r.position + Vector2(float(x), float(y)) * k
	for u in cl.get("allies", []):
		draw_circle(at.call(u.x, u.y), 1.8, Color("7dd3fc"))
	for t in cl.get("allyTowers", []):
		if t.hp > 0 and t.kind != "tree":
			var c: Vector2 = at.call(t.x, t.y)
			draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), Color("f9a8d4") if t.kind == "gate" else Color("38bdf8"))
	for c in cl.get("camps", []):
		if c.up:
			draw_circle(at.call(c.x, c.y), 3.2, Color("facc15"))
	for e in snap.get("enemies", []):
		var def: Dictionary = GameData.ENEMIES.get(e.type, {})
		if def.get("neutral", false):
			continue
		var c: Vector2 = at.call(e.x, e.y)
		if def.get("structure", false):
			var s2 := 5.0 if def.get("core", false) else 3.5
			draw_rect(Rect2(c - Vector2(s2, s2), Vector2(s2, s2) * 2), Color("e879f9") if def.get("core", false) else Color("f43f5e"))
		elif def.get("rival", false):
			draw_circle(c, 4.5, Color("fde047"))
			draw_circle(c, 3.2, Color("ef4444"))
		else:
			draw_circle(c, 1.8, Color("f87171"))
	for pl in cl.get("plots", []):
		var c: Vector2 = at.call(pl.x, pl.y)
		var pc: Color = {"empty": Color("a16207"), "ready": Color("fde047"), "berry": Color("a855f7"), "vine": Color("22c55e")}.get(String(pl.state), Color.WHITE)
		draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), pc)
		draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0, 0, 0, 0.6), false, 1.0)
	for f in cl.get("flags", []):
		draw_circle(at.call(f.x, f.y), 4.0, Color("fde047"))
	var raid: Dictionary = cl.get("raid", {})
	if not raid.is_empty():
		var ph := fmod(_time * 1.6, 1.0)
		draw_arc(at.call(raid.x, raid.y), 4 + ph * 9, 0, TAU, 20, Color(0.97, 0.3, 0.3, 1 - ph), 2.5, true)
	var cap: Dictionary = cl.get("captain", {})
	if not cap.is_empty() and not cap.planted:
		for u in cl.get("allies", []):
			if int(u.id) == int(cap.id):
				var c: Vector2 = at.call(u.x, u.y)
				draw_circle(c, 4.0, Color("78350f"))
				draw_circle(c, 2.8, Color("fde047"))
	for hh in snap.get("heroes", []):
		var c: Vector2 = at.call(hh.x, hh.y)
		draw_circle(c, 5.5 if hh.owner == my_owner else 4.5, Color.WHITE)
		draw_circle(c, 4.0 if hh.owner == my_owner else 3.2, GameData.player_color(hh.slot) if not hh.get("dead", false) else Color("6b7280"))


# ---------------------------------------------------------------------------
# Readability: boss bar, wave preview, new pests, buffs, pause menu, Tab stats
# ---------------------------------------------------------------------------
## Cut a string to fit a width, with "…"
func fit(s: String, width: float, size: int) -> String:
	if _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	var out := s
	while out.length() > 1 and _font.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		out = out.substr(0, out.length() - 1)
	return out.strip_edges() + "…"


## Draw one pest's first animation frame, scaled to `height` pixels, standing on `feet`
func pest_icon(type: String, feet: Vector2, height: float, mod := Color.WHITE) -> void:
	var e: Dictionary = Sprites.pest_entry(type)
	if e.is_empty():
		return
	Sprites.draw_frame(self, Sprites.tex(e.file), e, 0, feet, false, height / float(e.cell[1]) * 1.25, mod, Sprites.scale)


## Returns the y just under the bars
func _draw_boss_bar(W: float) -> float:
	var bosses: Array = []
	for e in snap.get("enemies", []):
		if GameData.ENEMIES.get(e.type, {}).get("boss", false):
			bosses.append(e)
	if bosses.is_empty():
		return 12.0
	var left := 446.0
	var right := W - 244.0
	var bw := minf(460.0, right - left)
	var y := 12.0
	for e in bosses.slice(0, 2):
		var def: Dictionary = GameData.ENEMIES[e.type]
		var r := Rect2((left + right) / 2 - bw / 2, y, bw, 50)
		var enraged: bool = e.get("enraged", false)
		var pulse := 0.5 + 0.5 * sin(_time * 8)
		panel(r, Color(0.16, 0.03, 0.06, 0.9), Color(0.97, 0.44, 0.44, 0.5 + (0.5 * pulse if enraged else 0.0)), 12)
		var k: float = float(e.hp) / maxf(1.0, float(e.maxHp))
		txt(Vector2(r.position.x + 14, y + 20), "👑 " + String(def.get("name", e.type)), 15, Color("fecaca"))
		var hp_txt := "%s / %s" % [_short(e.hp), _short(e.maxHp)]
		if enraged:
			hp_txt = "ENRAGED!  " + hp_txt
		txt(Vector2(r.end.x - 14, y + 20), hp_txt, 13, Color("fca5a5") if enraged else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		var mr := Rect2(r.position.x + 14, y + 28, bw - 28, 12)
		meter(mr, eased("boss%d" % int(e.id), k, 10.0), Color("ef4444") if enraged else Color("f97316"), Color(0, 0, 0, 0.45), eased("bosstrail%d" % int(e.id), k, 1.4))
		if e.type == "dreadblimp":  # it gets angry at half health
			draw_line(Vector2(mr.position.x + mr.size.x * 0.5, mr.position.y - 2), Vector2(mr.position.x + mr.size.x * 0.5, mr.end.y + 2), Color(1, 1, 1, 0.8), 2)
		if String(e.get("resist", "")) != "":
			var rs: Dictionary = GameData.RESISTS.get(e.resist, {})
			txt(Vector2(r.get_center().x, y + 20), "%s %s" % [rs.get("icon", ""), rs.get("name", "")], 12, Color(rs.get("color", "#ffffff")), HORIZONTAL_ALIGNMENT_CENTER)
		_block_rects.append(r)
		y += 56
	return y


## Between waves: which pests come next (and any Endless twist)
func _draw_wave_preview(W: float, H: float) -> void:
	var next := int(snap.wave) + 1
	if not snap.endless and next > int(snap.maxWave):
		return
	var n := maxi(1, snap.get("heroes", []).size())
	var twist := String(snap.get("nextTwist", ""))
	var short := String(snap.get("mode", "")) == "short"
	var key := "%d|%d|%s|%s|%s" % [next, n, snap.difficulty, twist, short]
	if _wave_cache.key != key:
		var plan: Dictionary = GameData.plan_wave(next, GameData.DIFFICULTIES.get(snap.difficulty, {}), n, bool(snap.endless), twist, short)
		var groups: Array = plan.groups.duplicate()
		if GameData.mini_boss_wave(next, bool(snap.endless), short) and not snap.get("practice", false):
			groups.append({"type": "thorntoad", "count": 1, "boss": true, "resist": ""})
		_wave_cache = {"key": key, "groups": groups}
	var groups: Array = _wave_cache.groups
	var slot := 62.0
	var w := maxf(230.0, groups.size() * slot + 20)
	# one sentence that turns the forecast into something to do
	var hint := _wave_hint(groups, next)
	var hint_lines := PackedStringArray()
	if hint != "":
		w = maxf(w, 300.0)
		hint_lines = wrap_lines(hint, w - 22, 12)
	var extra := hint_lines.size() * 16.0 + (10.0 if hint != "" else 0.0)
	var r := Rect2(W - 12 - w, H - 56 - 52 - 10 - 96 - extra, w, 92 + extra)
	panel(r, Color(0.05, 0.1, 0.07, 0.88))
	_block_rects.append(r)
	for j in hint_lines.size():
		txt(Vector2(r.position.x + 11, r.position.y + 104 + j * 16), hint_lines[j], 12, Color("fde68a") if hint.begins_with("🍂") else Color("d1fae5"))
	txt(Vector2(r.position.x + 12, r.position.y + 18), "Next: wave %d" % next, 13, Color("fde68a"))
	if twist != "":
		var tw: Dictionary = GameData.TWISTS.get(twist, {})
		txt(Vector2(r.end.x - 12, r.position.y + 18), fit("🌀 " + String(tw.get("name", twist)), w - 120, 12), 12, Color("f5d0fe"), HORIZONTAL_ALIGNMENT_RIGHT)
	var hover_type := ""
	for i in groups.size():
		var g: Dictionary = groups[i]
		var cx := r.position.x + 10 + slot * i + slot / 2
		var cell := Rect2(cx - slot / 2 + 3, r.position.y + 24, slot - 6, 62)
		draw_style_box(UiKit.box(Color(0.3, 0.05, 0.08, 0.6) if g.boss else Color(0, 0, 0, 0.25), Color(1, 0.4, 0.4, 0.6) if g.boss else Color(1, 1, 1, 0.08), 8, 1, 0), cell)
		pest_icon(g.type, Vector2(cx, r.position.y + 66), 34.0)
		txt(Vector2(cx, r.position.y + 82), ("BOSS" if g.boss else "×%d" % int(g.count)), 12, Color("fca5a5") if g.boss else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 3)
		if String(g.resist) != "":
			var rs: Dictionary = GameData.RESISTS.get(g.resist, {})
			draw_circle(Vector2(cell.end.x - 9, cell.position.y + 9), 8, Color(0.06, 0.09, 0.16, 0.9))
			txt(Vector2(cell.end.x - 9, cell.position.y + 13), String(rs.get("icon", "?")), 10, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if cell.has_point(get_local_mouse_position()):
			hover_type = g.type
			if String(g.resist) != "":
				hover_type += "|" + String(g.resist)
	if hover_type != "":
		var parts := hover_type.split("|")
		var def: Dictionary = GameData.ENEMIES.get(parts[0], {})
		var tip := String(def.get("name", parts[0]))
		if parts.size() > 1:
			var rs: Dictionary = GameData.RESISTS.get(parts[1], {})
			tip += " · %s %s: that element does half damage" % [rs.get("icon", ""), rs.get("name", "")]
		if String(def.get("desc", "")) != "":
			tip += " · " + String(def.desc)
		var tw := minf(_font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24, W - 40)
		panel(Rect2(W - 12 - tw, r.position.y - 36, tw, 30), Color(0.05, 0.1, 0.07, 0.96))
		txt(Vector2(W - tw, r.position.y - 16), fit(tip, tw - 22, 13), 13)


var _hint_cache := {"key": "", "text": ""}


## Between waves: the one thing worth doing about the next wave (or the last one's leaks)
func _wave_hint(groups: Array, next: int) -> String:
	var leaks: Array = snap.get("leaks", [])
	var team := ""
	for x in snap.get("heroes", []):
		team += "%s%d%d%d," % [x.type, int(x.tierA), int(x.tierB), x.get("cards", {}).size()]
	var key := "%d|%s|%s" % [next, str(leaks), team]
	if _hint_cache.key == key:
		return _hint_cache.text
	var text := ""
	if not leaks.is_empty():
		var l: Dictionary = leaks[0]
		var nm := String(GameData.ENEMIES.get(String(l.type), {}).get("name", l.type))
		var trail := GameData.trail_name(String(snap.map), int(l.path))
		text = "🍂 %d %s got through on %s. Build or upgrade there!" % [int(l.n), (nm + "s") if int(l.n) > 1 else nm, trail]
	if text == "":
		var camo := false
		var pierce := false
		for x in snap.get("heroes", []):
			var st: Dictionary = GameData.compute_hero_stats(x.type, x.tierA, x.tierB, x.get("cards", {}), x.level, x.get("buffs", {}), x.get("items", []))
			camo = camo or st.get("detectCamo", false)
			pierce = pierce or st.get("armorPierce", false)
		var boss := ""
		var has_camo := false
		var has_armor := false
		var resist := ""
		for g in groups:
			var def: Dictionary = GameData.ENEMIES.get(g.type, {})
			if g.boss and boss == "":
				boss = String(def.get("name", g.type))
			has_camo = has_camo or def.get("camo", false)
			has_armor = has_armor or def.get("armored", false) or def.get("lead", false)
			if String(g.get("resist", "")) != "" and resist == "":
				resist = String(g.resist)
		if boss != "":
			text = "👑 %s next! Save your specials and use them together for a Team Combo." % boss
		elif has_camo and not camo:
			text = "👀 Camo pests next: walk close to them so everyone can see them."
		elif has_armor and not pierce:
			text = "🛡️ Armored pests next: Boom Shroom, Volt Cactus and Armor Breaker crack them."
		elif resist != "":
			var rs: Dictionary = GameData.RESISTS.get(resist, {})
			text = "%s Some pests next shrug off %s: other elements hit them harder." % [rs.get("icon", ""), String(rs.get("name", resist)).to_lower()]
	_hint_cache = {"key": key, "text": text}
	return text


func _draw_pest_card(W: float) -> void:
	var def: Dictionary = GameData.ENEMIES.get(_pest_card.type, {})
	if def.is_empty():
		return
	var a := clampf(_pest_card.t / 0.6, 0, 1) * clampf((PEST_CARD_LIFE - _pest_card.t) / 0.3, 0, 1)
	var boss: bool = def.get("boss", false)
	var y := 84.0
	if not practice.is_empty():
		y = 148.0
	elif snap.get("twist", "") != "":
		y = 120.0
	var r := Rect2(12, y, 340, 80)
	panel(r, Color(0.12, 0.04, 0.06, 0.88 * a) if boss else Color(0.05, 0.1, 0.07, 0.88 * a), Color(1, 0.45, 0.45, a) if boss else Color(0.99, 0.88, 0.28, a), 12)
	pest_icon(_pest_card.type, Vector2(r.position.x + 40, r.end.y - 10), 56.0 if not boss else 62.0, Color(1, 1, 1, a))
	txt(Vector2(r.position.x + 80, r.position.y + 22), ("👑 BOSS: " if boss else "New pest: ") + String(def.get("name", "")), 14, Color(1, 0.8, 0.8, a) if boss else Color(1, 0.94, 0.54, a))
	var desc := String(def.get("desc", ""))
	if desc == "":
		desc = "A huge boss! Use your Specials together for a Team Combo, and set Target (T) to Strongest." if boss else "Watch how it moves and pick the right hero to beat it."
	draw_multiline_string(_font, r.position + Vector2(80, 40), desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 90, 12, 3, Color(1, 1, 1, a))


func _draw_buffs(h: Dictionary, W: float, H: float) -> void:
	var r := _hero_bar_rect(W, H)
	var y := r.position.y - (56.0 if h.has("maxHp") else 30.0)
	var x := r.position.x
	var chips: Array = []
	for k in h.get("buffs", {}):
		var pu: Dictionary = GameData.POWERUPS.get(k, {})
		if pu.is_empty() or float(h.buffs[k]) <= 0:
			continue
		chips.append(["%s %s %ds" % [pu.get("icon", "✨"), pu.get("name", k), ceili(float(h.buffs[k]))], Color(pu.get("color", "#fde047"))])
	if h.get("rally", false):
		chips.append(["🌞 Rally", Color("fde047")])
	for c in chips:
		var w := _font.get_string_size(c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18
		draw_style_box(UiKit.box(Color(0.05, 0.1, 0.07, 0.88), Color(c[1].r, c[1].g, c[1].b, 0.8), 10, 2, 0), Rect2(x, y, w, 24))
		txt(Vector2(x + 9, y + 17), c[0], 12, Color.WHITE)
		x += w + 6
	# targeting (Adventure / Endless)
	if not h.has("maxHp"):
		var names := {"first": "First", "strong": "Strongest", "close": "Closest", "last": "Last"}
		var label := "🎯 Target: %s (T)" % names.get(String(h.get("targetMode", "first")), "First")
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20
		button(Rect2(r.end.x - w, y, w, 24), label, {"t": "target"}, Color("1e3a5f"), 12)


func _draw_pause_menu(W: float, H: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.5))
	# two columns, so it fits on the screen at any UI size: the game on the left, settings on the right
	var r := Rect2(W / 2 - 320, H / 2 - 235, 640, 470)
	panel(r, Color(0.05, 0.12, 0.08, 0.97), Color("fde047"), 20)
	_block_rects.append(r)
	txt(Vector2(W / 2, r.position.y + 46), "⏸ Paused" if is_host else "Menu", 30, Color("fde047"), HORIZONTAL_ALIGNMENT_CENTER, -1, 5)
	if not is_host:
		txt(Vector2(W / 2, r.position.y + 70), "The game keeps going for your friends", 13, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_CENTER)
	var bw := 280.0
	var lx := r.position.x + 24
	var y := r.position.y + 92
	button(Rect2(lx, y, bw, 46), "▶ Keep playing (Esc)", {"t": "resume"}, Color("15803d"), 17)
	y += 56
	if is_host:
		button(Rect2(lx, y, bw, 46), "↻ Restart this game", {"t": "again"}, Color("1e3a5f"), 16)
		y += 56
	button(Rect2(lx, y, bw, 46), ("🔇 Sound off (M)" if Audio.muted else "🔊 Sound on (M)"), {"t": "mute"}, Color("334155"), 16)
	y += 56
	button(Rect2(lx, y, bw, 46), "🏠 Leave to the menu", {"t": "menu"}, Color("7f1d1d"), 16)
	var rx := r.end.x - 24 - bw
	var sy := r.position.y + 92
	txt(Vector2(rx, sy - 8), "Settings", 13, Color("a7f3d0"))
	var prof := Profile.load_profile()
	var rows := [
		[Profile.shake_label(float(prof.shake)), {"t": "set_shake"}],
		[Profile.dmg_label(String(prof.dmgNums)), {"t": "set_dmg"}],
		[Profile.gfx_label(String(prof.gfx)), {"t": "set_gfx"}],
		["Fullscreen: %s (F11)" % ("on" if prof.fullscreen else "off"), {"t": "fullscreen"}],
		[Profile.cards_label(auto_cards), {"t": "set_cards"}],
		[Profile.msgs_label(String(prof.msgs)), {"t": "set_msgs"}],
		[Profile.chatter_label(String(prof.chatter)), {"t": "set_chatter"}],
	]
	for row in rows:
		button(Rect2(rx, sy, bw, 36), row[0], row[1], Color("334155"), 14)
		sy += 42
	# UI size: smaller / bigger
	button(Rect2(rx, sy, 44, 36), "−", {"t": "ui_size", "d": -1}, Color("334155"), 20)
	button(Rect2(rx + bw - 44, sy, 44, 36), "+", {"t": "ui_size", "d": 1}, Color("334155"), 20)
	draw_style_box(UiKit.box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.12), 10, 1, 0), Rect2(rx + 50, sy, bw - 100, 36))
	txt(Vector2(rx + bw / 2, sy + 23), Profile.ui_scale_label(ui_scale), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	txt(Vector2(W / 2, r.end.y - 14), "Ctrl + and Ctrl − change the UI size · hold Tab in a game for stats", 11, Color(0.73, 0.97, 0.82, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


# ---------------------------------------------------------------------------
# Your towers: a list on the left. Click one to see it in the garden, then
# upgrade or sell it (your hero has to stand next to it, like with U and X).
# ---------------------------------------------------------------------------
func my_towers() -> Array:
	var out: Array = []
	for g in snap.get("gadgets", []):
		if g.owner == my_owner:
			out.append(g)
	return out


func tower_by_id(id: int) -> Dictionary:
	for g in snap.get("gadgets", []):
		if int(g.id) == id:
			return g
	return {}


func tower_near(g: Dictionary) -> bool:
	return hero_at != null and Vector2(g.x, g.y).distance_to(hero_at) <= TOWER_REACH


## Whether the next upgrade asks you to pick one of two special powers
static func tower_picks_power(g: Dictionary) -> bool:
	return int(g.level) == 2 and GameData.GADGETS[g.kind].has("branches")


## Draws the list with its bottom at `bottom`; returns its top
func _draw_towers(me: Dictionary, bottom: float) -> float:
	var towers := my_towers()
	var sel := tower_by_id(selected_tower)
	if sel.is_empty() or sel.owner != my_owner:
		selected_tower = -1
		sel = {}
	if towers.is_empty():
		return bottom
	var acorns := int(me.get("acorns", 0))
	var rw := 240.0
	var rh := 40.0
	var extra := _tower_detail_h(sel) if not sel.is_empty() else 0.0
	var total := 26.0 + towers.size() * (rh + 4) + extra + 4
	var r := Rect2(12, bottom - total, rw + 12, total)
	panel(r, Color(0.04, 0.09, 0.06, 0.8), UiKit.PANEL_EDGE, 12)
	_block_rects.append(r)
	txt(Vector2(r.position.x + 10, r.position.y + 18), "Your towers %d/%d" % [towers.size(), int(GameData.gadgets.limitPerPlayer)], 12, Color("bbf7d0"))
	txt(Vector2(r.end.x - 10, r.position.y + 18), "click one", 10, Color(0.73, 0.97, 0.82, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	var y := r.position.y + 26
	var tip := ""
	for g in towers:
		var t := _draw_tower_row(g, Rect2(r.position.x + 6, y, rw, rh), acorns)
		if t != "":
			tip = t
		y += rh + 4
		if int(g.id) == selected_tower:
			_draw_tower_detail(g, Rect2(r.position.x + 6, y - 2, rw, extra), acorns)
			y += extra
	if tip != "":
		var tw := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20
		var mp := get_local_mouse_position()
		panel(Rect2(r.end.x + 6, mp.y - 14, tw, 26), Color(0.05, 0.1, 0.07, 0.96))
		txt(Vector2(r.end.x + 16, mp.y + 4), tip, 12)
	return r.position.y


## One tower: picture, name, level, and an upgrade button. Returns a tooltip ("" = none).
func _draw_tower_row(g: Dictionary, row: Rect2, acorns: int) -> String:
	var def: Dictionary = GameData.GADGETS[g.kind]
	var sel := int(g.id) == selected_tower
	var mp := get_local_mouse_position()
	var hover := row.has_point(mp)
	var near := tower_near(g)
	draw_style_box(UiKit.box(Color(0.1, 0.25, 0.15, 0.95) if sel else Color(0.06, 0.12, 0.08, 0.9), Color("fde047") if sel else Color(1, 1, 1, 0.35 if hover else 0.12), 9, 2 if sel else 1, 0), row)
	_buttons.append([row, {"t": "tower", "id": int(g.id)}])
	var t: Texture2D = Sprites.gadget_tex(g.kind, int(g.level), int(g.branch), int(g.slot))
	if t:
		Sprites.draw_frame(self, t, Sprites.atlas.gadgets.get(g.kind, {}), 0, row.position + Vector2(20, 38), false, 0.34, Color.WHITE, Sprites.scale)
	txt(row.position + Vector2(40, 17), fit(String(def.name), 116, 13), 13, Color.WHITE)
	var pips := ""
	if not def.get("once", false):
		for i in 3:
			pips += "●" if i < int(g.level) else "○"
	if int(g.branch) >= 0:
		pips += " " + String(GameData.gadget_branch(g.kind, int(g.branch)).get("icon", ""))
	txt(row.position + Vector2(40, 33), pips + ("  · here" if near else ""), 11, Color("fde047") if near else Color("a7f3d0"))
	var br := Rect2(row.end.x - 74, row.position.y + 6, 68, row.size.y - 12)
	if def.get("once", false):
		txt(Vector2(br.get_center().x, br.position.y + 19), "one use", 11, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
		return ""
	if int(g.level) >= 3:
		txt(Vector2(br.get_center().x, br.position.y + 19), "⭐ max", 12, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER)
		return ""
	var cost := GameData.gadget_upgrade_cost(g.kind, int(g.level))
	var can := near and acorns >= cost
	button(br, "⬆ %d🌰" % cost, {"t": "tower_up", "id": int(g.id)}, Color("15803d") if can else Color("3f3f46"), 12, can)
	if br.has_point(mp):
		if not near:
			return "🚶 Walk next to it to upgrade (or click it, then Go there)"
		if acorns < cost:
			return "Not enough acorns yet: upgrading needs %d" % cost
		return "Pick its special power" if tower_picks_power(g) else "Upgrade to level %d" % (int(g.level) + 1)
	return ""


func _tower_detail_h(g: Dictionary) -> float:
	var h := 62.0
	if not GameData.GADGETS[g.kind].get("once", false) and tower_picks_power(g):
		h += 38.0
	return h


## Under the picked tower: what it does, its two special powers (at level 2), Go there and Sell
func _draw_tower_detail(g: Dictionary, r: Rect2, acorns: int) -> void:
	var def: Dictionary = GameData.GADGETS[g.kind]
	var near := tower_near(g)
	draw_style_box(UiKit.box(Color(0.03, 0.07, 0.05, 0.92), Color(0.99, 0.88, 0.28, 0.5), 9, 1, 0), r)
	var desc := String(def.get("desc", ""))
	if int(g.branch) >= 0:
		desc = String(GameData.gadget_branch(g.kind, int(g.branch)).get("desc", desc))
	txt(r.position + Vector2(8, 16), fit(desc, r.size.x - 16, 11), 11, Color("d1fae5"))
	var y := r.position.y + 24
	if not def.get("once", false) and tower_picks_power(g):
		var cost := GameData.gadget_upgrade_cost(g.kind, 2)
		var can := near and acorns >= cost
		var bw := (r.size.x - 22) / 2.0
		for i in 2:
			var b: Dictionary = def.branches[i]
			var label := "%s %s" % [b.get("icon", ""), fit(String(b.get("name", "")), bw - 34, 11)]
			button(Rect2(r.position.x + 8 + i * (bw + 6), y, bw, 32), label, {"t": "tower_up", "id": int(g.id), "branch": i}, Color("6d28d9") if can else Color("3f3f46"), 11, can)
		y += 38
	var sell := int(floor(float(g.spent) * 0.6))
	var half := (r.size.x - 22) / 2.0
	if near:
		txt(Vector2(r.position.x + 8 + half / 2, y + 21), "✓ close enough", 11, Color("86efac"), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		button(Rect2(r.position.x + 8, y, half, 30), "🚶 Go there", {"t": "tower_go", "id": int(g.id)}, Color("1e3a5f"), 12, true)
	button(Rect2(r.position.x + 14 + half, y, half, 30), "Sell +%d🌰" % sell, {"t": "tower_sell", "id": int(g.id)}, Color("7c2d12") if near else Color("3f3f46"), 12)


# ---------------------------------------------------------------------------
# "Level-ups: automatic": the hero picks its own stat cards; on path levels the
# two path upgrades wait here, in the left side bar, for you to pick one
# ---------------------------------------------------------------------------
func _draw_evolve(h: Dictionary, bottom: float) -> float:
	var waiting := GameData.path_waiting(int(h.tierA), int(h.tierB), int(h.level), int(h.pending))
	if waiting <= 0:
		return bottom
	var opts: Array = []
	for i in h.offer.size():
		if h.offer[i].kind == "path":
			opts.append(i)
	if opts.is_empty():
		return bottom
	var rw := 240.0
	var rh := 44.0
	var total := 28.0 + opts.size() * (rh + 4) + 2
	var r := Rect2(12, bottom - total, rw + 12, total)
	panel(r, Color(0.08, 0.1, 0.04, 0.9), Color(0.99, 0.88, 0.28, 0.55 + 0.45 * sin(_time * 4.0)), 12)
	_block_rects.append(r)
	var tw: Dictionary = GameData.TOWERS[h.type]
	txt(Vector2(r.position.x + 10, r.position.y + 19), fit("⭐ Evolve your %s!" % tw.name, rw - 60, 13), 13, Color("fde047"))
	if waiting > 1:
		txt(Vector2(r.end.x - 10, r.position.y + 19), "%d to pick" % waiting, 10, Color("fde68a"), HORIZONTAL_ALIGNMENT_RIGHT)
	var y := r.position.y + 28
	var tip := ""
	var mp := get_local_mouse_position()
	for i in opts:
		var c: Dictionary = h.offer[i]
		var path: Dictionary = tw.paths[c.path]
		var tier: Dictionary = path.tiers[int(c.tier) - 1]
		var col := Color("facc15") if c.path == "A" else Color("38bdf8")
		var row := Rect2(r.position.x + 6, y, rw, rh)
		var hover := row.has_point(mp)
		draw_style_box(UiKit.box(Color(0.1, 0.2, 0.12, 0.96) if hover else Color(0.06, 0.12, 0.08, 0.92), col if hover else Color(col.r, col.g, col.b, 0.55), 9, 2, 0), row)
		_buttons.append([row, {"t": "card", "i": i}])
		txt(row.position + Vector2(18, 29), "🅰️" if c.path == "A" else "🅱️", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		txt(row.position + Vector2(38, 19), fit(String(tier.name), rw - 92, 13), 13, col.lightened(0.3))
		var pips := ""
		for t in 4:
			pips += "●" if t < int(c.tier) else "○"
		txt(Vector2(row.end.x - 8, row.position.y + 18), pips, 10, col, HORIZONTAL_ALIGNMENT_RIGHT)
		txt(row.position + Vector2(38, 36), fit(String(tier.desc), rw - 46, 10), 10, Color("d1fae5"))
		if hover:
			tip = "%s (path %s, tier %d): %s" % [path.name, c.path, int(c.tier), tier.desc]
			var d := _card_delta(h, c)
			if d != "":
				tip += "  " + d
			if int(c.tier) == 3:
				tip += "  🔒 Path %s will stop at tier 2" % ("B" if c.path == "A" else "A")
		y += rh + 4
	if tip != "":
		var lines := wrap_lines(tip, 330, 12)
		var tw2 := 0.0
		for l in lines:
			tw2 = maxf(tw2, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		var tr := Rect2(r.end.x + 6, mp.y - 14, tw2 + 20, lines.size() * 16 + 10)
		panel(tr, Color(0.05, 0.1, 0.07, 0.97))
		for j in lines.size():
			txt(Vector2(tr.position.x + 10, tr.position.y + 18 + j * 16), lines[j], 12)
	return r.position.y


# ---------------------------------------------------------------------------
# Pop-up messages: a small stack in the bottom-left corner, out of the way
# ---------------------------------------------------------------------------
func _draw_toasts(bottom: float) -> void:
	var x := 12.0
	var maxw := 400.0
	var by := bottom
	if _cards_rect.size.x > 0 and _cards_rect.position.x < x + maxw + 10 and _cards_rect.position.y - 6 - _toasts.size() * 32 > 90:
		by = minf(by, _cards_rect.position.y - 6)  # above the level-up cards, when there's room
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var ink := clampf((float(t.max) - float(t.t)) / 0.2, 0, 1)  # slides up as it appears
		var a: float = clampf(t.t / 0.4, 0, 1) * ink
		var label: String = t.text + (("  ×%d" % int(t.n)) if int(t.n) > 1 else "")
		var lines := wrap_lines(label, maxw - 24, 13)
		var w := 0.0
		for l in lines:
			w = maxf(w, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
		var hh := lines.size() * 17.0 + 10.0
		by -= hh
		var yy := by + (1.0 - ink) * (1.0 - ink) * 14.0
		panel(Rect2(x, yy, w + 24, hh), Color(0.05, 0.1, 0.07, 0.86 * a), Color(t.col.r, t.col.g, t.col.b, 0.6 * a), 9)
		for j in lines.size():
			txt(Vector2(x + 12, yy + 18 + j * 17), lines[j], 13, Color(t.col.r, t.col.g, t.col.b, a))
		by -= 5


## Split text into lines that each fit `width`
func wrap_lines(s: String, width: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in s.split(" "):
		var test: String = word if line == "" else line + " " + word
		if line != "" and _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out


## Hold Tab: team scoreboard, my hero's numbers, and which reactions the team can make
func _draw_stats(W: float, H: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.45))
	var clash := snap.has("clash")
	var pw := minf(1180.0, W - 40)
	var x0 := W / 2 - pw / 2
	# 1. team
	var players: Array = snap.get("players", [])
	var tr := Rect2(x0, 40, pw, 52 + players.size() * 28)
	panel(tr, Color(0.04, 0.09, 0.06, 0.95))
	txt(Vector2(tr.position.x + 18, tr.position.y + 28), "Team", 16, Color("fde047"))
	var cols := [["Hero", 210], ["Lv", 360], ["Pops", 440], ["Damage", 540], ["Reactions", 650], ["Combos", 740]]
	cols.append(["Rivals", 830] if clash else ["Built", 830])
	cols.append(["Towers", 920] if clash else ["Sun", 920])
	for c in cols:
		txt(Vector2(tr.position.x + c[1], tr.position.y + 28), c[0], 12, Color("a7f3d0"), HORIZONTAL_ALIGNMENT_RIGHT if c[0] != "Hero" else HORIZONTAL_ALIGNMENT_LEFT)
	var y := tr.position.y + 54
	for p in players:
		var hh := {}
		for x in snap.get("heroes", []):
			if x.owner == p.id:
				hh = x
		draw_circle(Vector2(tr.position.x + 24, y - 5), 7, GameData.player_color(p.slot))
		txt(Vector2(tr.position.x + 38, y), String(p.name).substr(0, 16), 14, Color("fde047") if p.id == my_owner else Color.WHITE)
		txt(Vector2(tr.position.x + 210, y), String(GameData.TOWERS.get(p.hero, {}).get("name", p.hero)), 13, Color("bbf7d0"))
		var vals := [str(hh.get("level", 0)), str(p.pops), _short(p.damage), str(p.get("reactions", 0)), str(p.get("combos", 0)),
			str(p.get("rivalKOs", 0)) if clash else str(p.get("built", 0)), str(p.get("towersDown", 0)) if clash else _short(p.get("sun", 0))]
		for i in vals.size():
			txt(Vector2(tr.position.x + cols[i + 1][1], y), vals[i], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 28
	# 2. my hero
	var h := my_hero()
	var hr := Rect2(x0, tr.end.y + 14, 380, 250)
	panel(hr, Color(0.04, 0.09, 0.06, 0.95))
	if not h.is_empty():
		var st: Dictionary = GameData.compute_hero_stats(h.type, h.tierA, h.tierB, h.cards, h.level, h.buffs, h.get("items", []))
		var tw: Dictionary = GameData.TOWERS[h.type]
		txt(Vector2(hr.position.x + 18, hr.position.y + 28), "%s · level %d" % [tw.name, int(h.level)], 16, Color(tw.get("color", "#ffffff")))
		var paths := []
		for p in ["A", "B"]:
			var tier := int(h.tierA if p == "A" else h.tierB)
			paths.append("%s: %s" % [p, tw.paths[p].tiers[tier - 1].name if tier > 0 else "-"])
		txt(Vector2(hr.position.x + 18, hr.position.y + 50), fit("  ·  ".join(paths), hr.size.x - 36, 12), 12, Color("a7f3d0"))
		var lines := [
			["Damage", str(int(st.damage))],
			["Attacks / second", "%.2f" % GameData.gnum(st, "fireRate", 0.0)],
			["Range", str(int(st.range))],
			["Lucky (double damage)", "%d%%" % int(round(GameData.gnum(st, "critChance") * 100))],
			["Walking speed", str(int(st.moveSpeed))],
			["Special recharge", "%ds" % int(round(float(GameData.HERO_INFO[h.type].special.cooldown) * st.specialMult))],
			["Sees camo pests", "yes" if st.get("detectCamo", false) else "close up only"],
			["Breaks armor", "yes" if st.get("armorPierce", false) else "no"],
		]
		var ly := hr.position.y + 78
		for l in lines:
			txt(Vector2(hr.position.x + 18, ly), l[0], 13, Color("d1fae5"))
			txt(Vector2(hr.end.x - 18, ly), l[1], 13, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
			ly += 21
	# 3. reactions the team can make
	var rr := Rect2(hr.end.x + 14, hr.position.y, pw - hr.size.x - 14, 250)
	panel(rr, Color(0.04, 0.09, 0.06, 0.95))
	txt(Vector2(rr.position.x + 18, rr.position.y + 28), "Team reactions (✓ = your team can make it)", 16, Color("fde047"))
	var team := {}
	for x in snap.get("heroes", []):
		team[x.type] = true
	var ry := rr.position.y + 54
	for id in GameData.REACTIONS:
		var rd: Dictionary = GameData.REACTIONS[id]
		var ok := true
		for need in rd.get("heroes", []):
			if not team.has(need):
				ok = false
		var col := Color(rd.get("color", "#ffffff"))
		if not ok:
			col = Color(col.r, col.g, col.b, 0.45)
		txt(Vector2(rr.position.x + 18, ry), "%s %s %s" % ["✓" if ok else "·", rd.get("icon", ""), rd.get("name", id)], 14, col)
		txt(Vector2(rr.position.x + 190, ry), fit(String(rd.get("how", "")), rr.size.x - 210, 12), 12, Color(1, 1, 1, 0.9 if ok else 0.5))
		ry += 26


# ---------------------------------------------------------------------------
# Couch co-op: a small panel per controller player, and hero pickers for joiners
# ---------------------------------------------------------------------------
func _card_title(h: Dictionary, c: Dictionary) -> String:
	if c.kind == "path":
		var tier: Dictionary = GameData.TOWERS[h.type].paths[c.path].tiers[int(c.tier) - 1]
		return "%s %s" % ["🅰️" if c.path == "A" else "🅱️", tier.name]
	var sc: Dictionary = GameData.STAT_CARDS.get(c.id, {})
	return "%s %s" % [sc.get("icon", "⭐"), sc.get("name", c.id)]


func _draw_couch(W: float, H: float) -> void:
	var sofa: Dictionary = couch.players()
	var y := minf(H - (132.0 if snap.has("clash") else 118.0), _bl_top - 10)
	for pid in sofa:
		var p: Dictionary = sofa[pid]
		var h := {}
		for x in snap.get("heroes", []):
			if x.owner == pid:
				h = x
		if h.is_empty():
			continue
		var cards: bool = int(h.pending) > 0 and h.offer.size() > 0 and (not auto_cards or GameData.path_waiting(int(h.tierA), int(h.tierB), int(h.level), int(h.pending)) > 0)
		var ph := 96.0 if cards else 62.0
		y -= ph + 6
		_bl_top = minf(_bl_top, y)
		var r := Rect2(12, y, 310, ph)
		var col: Color = GameData.player_color(h.slot)
		panel(r, Color(0.05, 0.1, 0.07, 0.9), Color(col.r, col.g, col.b, 0.8), 12)
		_block_rects.append(r)
		txt(Vector2(r.position.x + 12, y + 20), "🎮 %s" % p.name, 14, col.lightened(0.2))
		txt(Vector2(r.end.x - 12, y + 20), "%s · Lv %d" % [GameData.TOWERS[h.type].name, int(h.level)], 12, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_RIGHT)
		if h.get("dead", false):
			txt(Vector2(r.position.x + 12, y + 46), "💫 back in %ds (stand next to them to revive!)" % ceili(float(h.respawnT)), 12, Color("fca5a5"))
		else:
			if h.has("maxHp"):
				var hk: float = float(h.hp) / maxf(1.0, float(h.maxHp))
				meter(Rect2(r.position.x + 12, y + 28, 140, 8), hk, Color("4ade80") if hk > 0.5 else Color("ef4444"))
			else:
				meter(Rect2(r.position.x + 12, y + 28, 140, 8), float(h.xp) / maxf(1.0, float(h.xpNext)), Color("38bdf8"))
			var ready: bool = float(h.specialCd) <= 0.05
			var cinv := combo_invite(h)
			if not cinv.is_empty() and cinv.near:
				txt(Vector2(r.position.x + 162, y + 37), "⚡ X now: Team Combo!", 11, Color(1, 0.94, 0.4, 0.6 + 0.4 * sin(_time * 12.0)))
			else:
				txt(Vector2(r.position.x + 162, y + 37), ("✨ X special ready!" if ready else "✨ special %ds" % ceili(float(h.specialCd))), 11, Color("e9d5ff") if ready else Color(1, 1, 1, 0.6))
			if not snap.has("clash"):
				var d: Dictionary = GameData.GADGETS[String(p.get("gadget", "sentry"))]
				txt(Vector2(r.position.x + 12, y + 54), "LB/RB tower: %s %s (%d🌰) · Y build · B upgrade" % [d.icon, d.name, int(d.cost)], 11, Color(1, 1, 1, 0.75))
			else:
				txt(Vector2(r.position.x + 12, y + 54), "RB buy next item · LB juice (%d) · B home" % int(h.get("potions", 0)), 11, Color(1, 1, 1, 0.75))
		if cards:
			var arrows := ["◀", "▲", "▶"]
			var line := ""
			for i in mini(3, h.offer.size()):
				line += "%s %s   " % [arrows[i], _card_title(h, h.offer[i])]
			draw_style_box(UiKit.box(Color(0.25, 0.2, 0.04, 0.9), Color(0, 0, 0, 0), 8, 0, 0), Rect2(r.position.x + 6, y + 62, r.size.x - 12, 28))
			txt(Vector2(r.position.x + 12, y + 81), fit("⭐ " + line.strip_edges(), r.size.x - 24, 12), 12, Color("fde047"))
	# controllers picking a hero
	var jy := 176.0
	for j in couch.joining():
		var type: String = GameData.HERO_ORDER[int(j.hero_i)]
		var r := Rect2(W / 2 - 210, jy, 420, 70)
		panel(r, Color(0.05, 0.1, 0.07, 0.95), Color("fde047"), 14)
		var icon := UiKit.hero_icon(type)
		if icon:
			draw_texture_rect(icon, Rect2(r.position.x + 10, jy + 4, 58, 62), false)
		txt(Vector2(r.position.x + 80, jy + 28), "🎮 %s: ◀  %s  ▶" % [j.name, GameData.TOWERS[type].name], 17, Color.WHITE)
		txt(Vector2(r.position.x + 80, jy + 52), "D-pad picks a hero · A to join · B to cancel", 12, Color("bbf7d0"))
		jy += 78
	# plugged-in controllers that haven't joined yet
	var pads := Input.get_connected_joypads()
	if pads.size() > couch.pads.size() and is_host and not snap.is_empty():
		var label := "🎮 Press Start on a controller to join!" if not couch.p1_pad or couch.p1_device() >= 0 else "🎮 Press Start: the first controller plays as you"
		txt(Vector2(W - 122, 34 + snap.get("heroes", []).size() * (34 if snap.has("clash") else 26) + 18), label, 12, Color(0.99, 0.88, 0.28, 0.6 + 0.4 * sin(_time * 3)), HORIZONTAL_ALIGNMENT_CENTER, -1, 3)


func _draw_emote_bar(W: float, H: float) -> void:
	var emotes: Array = GameData.cosmetics.emotes
	var bw := 92.0
	var r := Rect2(W / 2 - (emotes.size() * (bw + 6)) / 2 - 8, _hero_bar_rect(W, H).position.y - 112, emotes.size() * (bw + 6) + 10, 54)
	panel(r, Color(0.05, 0.1, 0.07, 0.95), Color("fde047"), 12)
	_block_rects.append(r)
	for i in emotes.size():
		var em: Dictionary = emotes[i]
		var label := "%d %s %s" % [i + 1, em.icon, em.text if em.text != "" else "Love"]
		button(Rect2(r.position.x + 8 + i * (bw + 6), r.position.y + 8, bw, 38), label, {"t": "emote", "id": em.id}, Color("1e3a5f"), 12)


# ---------------------------------------------------------------------------
# Adventure minimap and edge arrows
# ---------------------------------------------------------------------------
func _draw_adv_minimap(W: float) -> void:
	var mw := 216.0
	var mh := 132.0
	var top: float = 12.0 + 18 + snap.get("heroes", []).size() * 26 + 10
	var r := Rect2(W - mw - 14, top, mw, mh)
	minimap_rect = r
	_block_rects.append(r)
	draw_style_box(UiKit.box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.3), 8, 2, 0), r.grow(3))
	var tex: Texture2D = Sprites.tex(Sprites.atlas.maps.get(snap.map, ""))
	if tex:
		draw_texture_rect(tex, r, false, Color(1, 1, 1, 0.85))
	var k := Vector2(mw / GameData.W, mh / GameData.H)
	var at := func(x, y) -> Vector2: return r.position + Vector2(float(x), float(y)) * k
	var sc: Vector2 = GameData.sanctuary(snap.map)
	draw_circle(at.call(sc.x, sc.y), 6, Color("166534"))
	draw_circle(at.call(sc.x, sc.y), 4, Color("4ade80"))
	for g in snap.get("gadgets", []):
		var c: Vector2 = at.call(g.x, g.y)
		draw_rect(Rect2(c - Vector2(2.5, 2.5), Vector2(5, 5)), GameData.player_color(g.slot))
	for e in snap.get("enemies", []):
		var c: Vector2 = at.call(e.x, e.y)
		if GameData.ENEMIES.get(e.type, {}).get("boss", false):
			draw_circle(c, 5, Color("fde047"))
			draw_circle(c, 3.5, Color("ef4444"))
		elif not e.get("burrowed", false):
			draw_circle(c, 1.8, Color("f87171"))
	for ch in snap.get("chests", []):
		draw_circle(at.call(ch.x, ch.y), 4, Color("facc15"))
	for pu in snap.get("powerups", []):
		draw_circle(at.call(pu.x, pu.y), 3.5, Color("f0abfc"))
	for hh in snap.get("heroes", []):
		var c: Vector2 = at.call(hh.x, hh.y)
		draw_circle(c, 5.0 if hh.owner == my_owner else 4.0, Color.WHITE)
		draw_circle(c, 3.6 if hh.owner == my_owner else 2.8, GameData.player_color(hh.slot))
	if world:
		for pg in world.pings:
			var ph := fmod(_time * 1.6, 1.0)
			var col: Color = GameData.player_color(pg.slot)
			draw_arc(at.call(pg.p.x, pg.p.y), 3 + ph * 9, 0, TAU, 20, Color(col.r, col.g, col.b, 1 - ph), 2, true)
	txt(Vector2(r.end.x - 4, r.end.y - 4), "N", 10, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)


## Little arrows at the screen edge pointing at chests, power-ups, pings,
## bosses, and pests close to the Bloom Tree when they're off-screen
func _draw_edge_arrows(W: float, H: float) -> void:
	var xf := world.get_canvas_transform()
	var marks: Array = []  # [world pos, icon, color]
	for ch in snap.get("chests", []):
		marks.append([Vector2(ch.x, ch.y), "🎁", Color("facc15")])
	for pu in snap.get("powerups", []):
		marks.append([Vector2(pu.x, pu.y), "✨", Color("f0abfc")])
	for pg in world.pings:
		marks.append([pg.p, "📍", GameData.player_color(pg.slot)])
	var ccl: Dictionary = snap.get("clash", {})
	if not ccl.get("raid", {}).is_empty():
		marks.append([Vector2(ccl.raid.x, ccl.raid.y), "⚔️", Color("ef4444")])
	var cap: Dictionary = ccl.get("captain", {})
	if not cap.is_empty() and not cap.planted:
		for u in ccl.get("allies", []):
			if int(u.id) == int(cap.id):
				marks.append([Vector2(u.x, u.y), "🚩", Color("fde047")])
	for g in snap.get("gadgets", []):
		if int(g.id) == selected_tower:
			marks.append([Vector2(g.x, g.y), String(GameData.GADGETS[g.kind].icon), Color("fde047")])
	if not snap.has("clash"):
		var sc: Vector2 = GameData.sanctuary(snap.map)
		var danger := false
		for e in snap.get("enemies", []):
			if GameData.ENEMIES.get(e.type, {}).get("boss", false):
				marks.append([Vector2(e.x, e.y), "👑", Color("ef4444")])
			elif Vector2(e.x, e.y).distance_to(sc) < 380:
				danger = true
		if danger:
			marks.append([sc, "🌳", Color("ef4444")])
	var inset := Rect2(46, 46, W - 92, H - 92)
	var center := Vector2(W, H) / 2
	for m in marks:
		var s: Vector2 = (xf * m[0]) / _eff
		if Rect2(0, 0, W, H).grow(-10).has_point(s):
			continue
		var d: Vector2 = (s - center)
		# where the line from the middle of the screen leaves the inset box
		var t := INF
		if absf(d.x) > 0.01:
			t = minf(t, (inset.size.x / 2) / absf(d.x))
		if absf(d.y) > 0.01:
			t = minf(t, (inset.size.y / 2) / absf(d.y))
		var p := center + d * t
		var dir := d.normalized()
		var col: Color = m[2]
		var pulse := 0.75 + 0.25 * sin(_time * 6)
		draw_circle(p, 17, Color(0.05, 0.1, 0.07, 0.85))
		draw_arc(p, 17, 0, TAU, 24, Color(col.r, col.g, col.b, pulse), 2.5, true)
		var tip := p + dir * 27
		var side := dir.orthogonal() * 7
		draw_colored_polygon(PackedVector2Array([tip, p + dir * 17 + side, p + dir * 17 - side]), Color(col.r, col.g, col.b, pulse))
		txt(p + Vector2(0, 6), m[1], 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)


## The exact change a card makes, e.g. "Damage 36 → 41"
func _card_delta(h: Dictionary, c: Dictionary) -> String:
	var items: Array = h.get("items", [])
	var now: Dictionary = GameData.compute_hero_stats(h.type, h.tierA, h.tierB, h.cards, h.level, h.buffs, items)
	var nxt: Dictionary
	if c.kind == "path":
		var ta: int = h.tierA + (1 if c.path == "A" else 0)
		var tb: int = h.tierB + (1 if c.path == "B" else 0)
		nxt = GameData.compute_hero_stats(h.type, ta, tb, h.cards, h.level, h.buffs, items)
	else:
		var cards: Dictionary = h.cards.duplicate()
		cards[c.id] = GameData.gnum(cards, c.id) + 1
		nxt = GameData.compute_hero_stats(h.type, h.tierA, h.tierB, cards, h.level, h.buffs, items)
	var parts: Array = []
	for flag in [["armorPierce", "Breaks armor"], ["detectCamo", "Sees camo"]]:
		if not now.get(flag[0], false) and nxt.get(flag[0], false):
			parts.append("%s: no → yes" % flag[1])
	for f in [["burnDps", "Burn", "%d/s"], ["damage", "Damage", "%d"], ["fireRate", "Speed", "%.2f"], ["range", "Range", "%d"], ["moveSpeed", "Walk", "%d"],
			["critChance", "Lucky", "pct"], ["pickup", "Sun grab", "%d"], ["specialMult", "Special", "cd"], ["xpMult", "XP", "pct"]]:
		var a := GameData.gnum(now, f[0])
		var b := GameData.gnum(nxt, f[0])
		if absf(b - a) < 0.0001:
			continue
		var fa: String
		var fb: String
		match String(f[2]):
			"pct":
				fa = "%d%%" % int(round(a * 100))
				fb = "%d%%" % int(round(b * 100))
			"cd":
				var base := float(GameData.HERO_INFO[h.type].special.cooldown)
				fa = "%ds" % int(round(base * a))
				fb = "%ds" % int(round(base * b))
			_:
				fa = f[2] % a
				fb = f[2] % b
		parts.append("%s %s → %s" % [f[1], fa, fb])
		if parts.size() >= 2:
			break
	return " · ".join(parts)


## Endless: spend spare acorns (wave 5+)
func _draw_endless_shop(me: Dictionary, H: float) -> void:
	var acorns := int(me.get("acorns", 0))
	var y := H - 108 - 36
	var x := 12.0
	var life_at := int(snap.get("lifeShopAt", 0))
	var items := [["life", "🌳 +1 life", 250, int(snap.wave) >= life_at and int(snap.lives) < int(snap.maxLives)],
		["overclock", "⚡ Overclock %s" % (("%ds" % int(snap.overclock)) if int(snap.get("overclock", 0)) > 0 else "60s"), 100, true],
		["mystery", "🎁 Mystery", 120, true]]
	for it in items:
		var ok: bool = it[3] and acorns >= int(it[2])
		var w := 122.0
		var r := Rect2(x, y, w, 30)
		button(r, "", {"t": "eshop", "item": it[0]}, Color("14532d") if ok else Color(0.2, 0.22, 0.2), 12)
		txt(Vector2(r.position.x + 8, y + 20), it[1], 12, Color.WHITE if ok else Color(1, 1, 1, 0.5))
		UiKit.acorns_text(self, Vector2(r.end.x - 6, y + 20), int(it[2]), 11, Color("fcd34d") if ok else Color(1, 0.8, 0.8, 0.6), true)
		x += w + 4
	_block_rects.append(Rect2(12, y, x - 12, 30))
	_bl_top = minf(_bl_top, y)
