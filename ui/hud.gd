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
var _wave_cache := {"key": "", "groups": []}


func _ready() -> void:
	_font = UiKit.font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Audio.dialog_line.connect(_on_dialog_line)


func _on_dialog_line(speaker: String, text: String, owner_id: int, duration: float) -> void:
	if owner_id < 0 and text != "":
		_subtitle = {"speaker": speaker, "text": text, "t": duration, "max": duration}


func toast(msg: String, col := Color.WHITE, life := 3.5) -> void:
	_toasts.append({"text": msg, "col": col, "t": life, "max": life})
	if _toasts.size() > 4:
		_toasts.pop_front()


var _feed: Array = []


## The battle feed (Garden Clash): who smashed what, who got knocked out
func feed(text: String, col := Color.WHITE) -> void:
	_feed.append({"text": text, "col": col, "t": 7.0})
	if _feed.size() > 6:
		_feed.pop_front()


## A "new pest!" warning card (first time a pest type or boss shows up)
func pest_card(type: String) -> void:
	_pest_card = {"type": type, "t": 7.0}


func over_build_bar() -> bool:
	return _build_rect.has_point(get_local_mouse_position())


func banner(text: String, sub := "", col := Color("fde047"), life := 2.6) -> void:
	_banner = {"text": text, "sub": sub, "t": life, "col": col, "max": life}


func _process(delta: float) -> void:
	_time += delta
	for t in _toasts:
		t.t -= delta
	_toasts = _toasts.filter(func(t): return t.t > 0)
	_pest_card.t = maxf(0.0, _pest_card.t - delta)
	for f in _feed:
		f.t -= delta
	_feed = _feed.filter(func(f): return f.t > 0)
	_banner.t = maxf(0.0, _banner.t - delta)
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


func meter(r: Rect2, k: float, col: Color, back := Color(0, 0, 0, 0.45)) -> void:
	draw_style_box(UiKit.box(back, Color(0, 0, 0, 0), int(r.size.y / 2), 0, 0), r)
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
	_buttons.clear()
	_block_rects.clear()
	if snap.is_empty():
		return
	var W := get_viewport_rect().size.x
	var H := get_viewport_rect().size.y
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

	# --- banner
	if _banner.t > 0:
		var a: float = clampf(_banner.t / 0.5, 0, 1) * clampf((_banner.max - _banner.t) / 0.25 + 0.2, 0, 1)
		var c: Color = _banner.col
		c.a = a
		txt(Vector2(W / 2, 120), _banner.text, 40, c, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
		if _banner.sub != "":
			txt(Vector2(W / 2, 152), _banner.sub, 18, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, -1, 5)
	if _subtitle.t > 0:
		var sa: float = clampf(_subtitle.t / 0.4, 0, 1) * clampf((_subtitle.max - _subtitle.t) / 0.18 + 0.2, 0, 1)
		var is_foe: bool = _subtitle.speaker in ["Spore Zeppelin", "Dread Monarch", "Sir Shellbash", "Queen Stinger", "Digger Duke", "Spore Witch"]
		var badge := "👑 " if is_foe else "🎙️ "
		var line := "%s%s: \"%s\"" % [badge, _subtitle.speaker, _subtitle.text]
		var sw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28
		var sy := 178.0 if _banner.t > 0 else 22.0
		var edge := Color(0.97, 0.44, 0.44, 0.75 * sa) if is_foe else Color(0.99, 0.88, 0.28, 0.65 * sa)
		var tcol := Color(1.0, 0.85, 0.85, sa) if is_foe else Color(0.99, 0.96, 0.82, sa)
		panel(Rect2(W / 2 - sw / 2, sy, sw, 28), Color(0.04, 0.09, 0.06, 0.88 * sa), edge, 10)
		txt(Vector2(W / 2, sy + 19), line, 14, tcol, HORIZONTAL_ALIGNMENT_CENTER)

	if clash.is_empty() and phase == "playing":
		_draw_boss_bar(W)
		if not snap.waveActive:
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
		if snap.get("endless", false) and int(snap.wave) >= 5 and phase == "playing":
			_draw_endless_shop(me, H)
	else:
		if not h.is_empty() and h.get("canShop", false) and phase == "playing":
			_draw_shop(h, me, W, H)
		else:
			_draw_minimap(clash, W, H)
		if not h.is_empty() and h.get("dead", false) and phase == "playing":
			txt(Vector2(W / 2, H * 0.36), "💫 Knocked out! Back in %ds" % ceili(float(h.respawnT)), 30, Color("fecaca"), HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
			txt(Vector2(W / 2, H * 0.36 + 30), "A friend standing right next to you can revive you sooner. You can still shop!", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	_draw_controls(W, H)
	if not h.is_empty() and h.pending > 0 and h.offer.size() > 0 and phase == "playing" and not me.get("bot", false):
		if cards_hidden:
			var label := "⭐ %d card%s waiting · C to show" % [int(h.pending), "s" if int(h.pending) > 1 else ""]
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28
			button(Rect2(W / 2 - w / 2, H - 92 - 62, w, 32), label, {"t": "show_cards"}, Color("854d0e"), 14, true)
		else:
			_draw_cards(h, W, H)

	# --- toasts
	var ty := H - 150.0 - (190.0 if not h.is_empty() and h.pending > 0 else 0.0)
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var a: float = clampf(t.t / 0.4, 0, 1)
		var w := _font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 30
		panel(Rect2(W / 2 - w / 2, ty - 22, w, 32), Color(0.05, 0.1, 0.07, 0.86 * a), Color(t.col.r, t.col.g, t.col.b, 0.6 * a), 10)
		txt(Vector2(W / 2, ty - 1), t.text, 15, Color(t.col.r, t.col.g, t.col.b, a), HORIZONTAL_ALIGNMENT_CENTER)
		ty -= 38

	if net_note != "":
		txt(Vector2(W / 2, H - 8), net_note, 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	if snap.paused and phase == "playing" and not menu_open:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35))
		txt(Vector2(W / 2, H / 2), "⏸ Paused", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
		txt(Vector2(W / 2, H / 2 + 40), "Press P to keep playing", 18, Color("d1fae5"), HORIZONTAL_ALIGNMENT_CENTER, -1, 4)
	if phase == "victory" or phase == "gameover":
		_draw_end(phase == "victory", W, H)
	elif menu_open:
		_draw_pause_menu(W, H)
	if show_stats and not menu_open:
		_draw_stats(W, H)


func _draw_hero_bar(h: Dictionary, W: float, H: float) -> void:
	var r := Rect2(W / 2 - 250, H - 92, 500, 80)
	panel(r)
	_block_rects.append(r)
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
	meter(Rect2(x0, r.position.y + 38, 220, 14), k, Color("38bdf8"))
	txt(Vector2(x0 + 110, r.position.y + 50), "%d / %d XP" % [h.xp, h.xpNext], 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if h.pending > 0:
		var pulse := 0.6 + 0.4 * sin(_time * 6)
		txt(Vector2(x0, r.position.y + 72), "⭐ %d card%s to pick! Press 1, 2 or 3" % [h.pending, "s" if h.pending > 1 else ""], 13, Color(1, 0.9, 0.3, pulse))
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


func _draw_build_bar(me: Dictionary, W: float, H: float) -> void:
	var n := GameData.GADGET_ORDER.size()
	var cw := 54.0
	var r := Rect2(12, H - 108, 16 + n * (cw + 6), 96)
	panel(r)
	_block_rects.append(r)
	_build_rect = r
	var mine := 0
	for g in snap.get("gadgets", []):
		if g.owner == my_owner:
			mine += 1
	var cap := int(GameData.gadgets.limitPerPlayer)
	txt(Vector2(24, H - 88), "Build %d/%d" % [mine, cap], 12, Color("fde047") if mine >= cap else Color("bbf7d0"))
	txt(Vector2(r.end.x - 10, H - 88), "1-6 pick · F build · U up · X sell", 10, Color(0.73, 0.97, 0.82, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	var acorns := int(me.get("acorns", 0))
	var hovered := ""
	for i in n:
		var kind: String = GameData.GADGET_ORDER[i]
		var def: Dictionary = GameData.GADGETS[kind]
		var cr := Rect2(20 + i * (cw + 6), H - 78, cw, 58)
		var sel := kind == selected_gadget
		var afford: bool = acorns >= int(def.cost)
		var hover := cr.has_point(get_local_mouse_position())
		draw_style_box(UiKit.box(Color(0.1, 0.25, 0.15, 0.95) if sel else Color(0.04, 0.09, 0.06, 0.9), Color("fde047") if sel else Color(1, 1, 1, 0.35 if hover else 0.15), 10, 2 if sel else 1, 0), cr)
		var t: Texture2D = Sprites.gadget_tex(kind, 1, -1, 0)
		var e: Dictionary = Sprites.atlas.gadgets.get(kind, {})
		if t:
			Sprites.draw_frame(self, t, e, 0, cr.position + Vector2(cw / 2, 40), false, 0.34, Color.WHITE if afford else Color(1, 1, 1, 0.45), Sprites.scale)
		txt(Vector2(cr.get_center().x, cr.end.y - 3), "%d" % int(def.cost), 12, Color("fcd34d") if afford else Color("fca5a5"), HORIZONTAL_ALIGNMENT_CENTER, -1, 3)
		txt(cr.position + Vector2(6, 13), str(i + 1), 10, Color(1, 1, 1, 0.55))
		_buttons.append([cr, {"t": "select_gadget", "kind": kind}])
		if hover:
			hovered = kind
	if r.has_point(get_local_mouse_position()):
		var def: Dictionary = GameData.GADGETS[hovered if hovered != "" else selected_gadget]
		var tip := "%s %s (%d acorns): %s" % [def.icon, def.name, int(def.cost), def.desc]
		var w := minf(520.0, _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24)
		panel(Rect2(12, H - 146, w, 32), Color(0.05, 0.1, 0.07, 0.95))
		txt(Vector2(24, H - 125), tip, 13, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, w - 20)


func _draw_controls(W: float, H: float) -> void:
	var x := W - 12.0
	var y := H - 56.0
	if snap.phase == "playing" and not snap.waveActive and not snap.has("clash"):
		var label := "▶ Start Wave %d  (Space)" % (int(snap.wave) + 1)
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
	var cw := 210.0
	var ch := 184.0
	var n: int = h.offer.size()
	var x0 := W / 2 - (n * cw + (n - 1) * 14) / 2
	var y0 := H - 104 - ch - 12
	txt(Vector2(W / 2, y0 - 12), "⭐ LEVEL UP! Pick one (1, 2, 3 or click)", 20, Color("fde047"), HORIZONTAL_ALIGNMENT_CENTER, -1, 5)
	button(Rect2(x0 + n * cw + (n - 1) * 14 - 70, y0 - 34, 70, 24), "▾ hide (C)", {"t": "hide_cards"}, Color("334155"), 11)
	for i in n:
		var c: Dictionary = h.offer[i]
		var r := Rect2(x0 + i * (cw + 14), y0, cw, ch)
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
		var lift := -6.0 if hover else 0.0
		r.position.y += lift
		draw_style_box(UiKit.box(Color(0.06, 0.13, 0.09, 0.97), col if hover else Color(col.r, col.g, col.b, 0.7), 16, 3, 0), r)
		draw_circle(r.position + Vector2(20, 20), 13, col)
		txt(r.position + Vector2(20, 26), str(i + 1), 16, Color("111827"), HORIZONTAL_ALIGNMENT_CENTER)
		txt(r.position + Vector2(cw / 2, 46), icon, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		txt(r.position + Vector2(cw / 2, 74), title, 17, col.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
		txt(r.position + Vector2(cw / 2, 92), head, 11, Color("a7f3d0"), HORIZONTAL_ALIGNMENT_CENTER)
		wrap_text(r.position + Vector2(10, 112), desc, cw - 20, 13, Color("ecfdf5"), 2)
		if c.kind == "path":
			# progress along that path: ● = tiers you'll have
			var pips := ""
			for t in 4:
				pips += "●" if t < int(c.tier) else "○"
			txt(r.position + Vector2(cw - 14, 26), pips, 12, col, HORIZONTAL_ALIGNMENT_RIGHT)
		var delta := _card_delta(h, c)
		if delta != "":
			txt(r.position + Vector2(cw / 2, ch - (28 if c.kind == "path" and int(c.tier) == 3 else 12)), fit(delta, cw - 16, 12), 12, Color("fde68a"), HORIZONTAL_ALIGNMENT_CENTER)
		if c.kind == "path" and int(c.tier) == 3:
			txt(r.position + Vector2(cw / 2, ch - 10), "🔒 Path %s will stop at tier 2" % ("B" if c.path == "A" else "A"), 11, Color("fdba74"), HORIZONTAL_ALIGNMENT_CENTER)
		_buttons.append([r, {"t": "card", "i": i}])


func _draw_end(win: bool, W: float, H: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
	var awards := _awards()
	var extra := (34.0 if not awards.is_empty() else 0.0) + (30.0 if not new_unlocks.is_empty() else 0.0)
	var r := Rect2(W / 2 - 300, H / 2 - 210 - extra / 2, 600, 420 + extra)
	panel(r, Color(0.05, 0.12, 0.08, 0.97), Color("fde047") if win else Color("fb7185"), 22)
	_block_rects.append(r)
	txt(Vector2(W / 2, r.position.y + 62), "🏆 Victory!" if win else "🍂 The Bloom Tree fell", 38, Color("fde047") if win else Color("fda4af"), HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
	var sub := ("You saved the garden on %s!" % _diff_name()) if win else ("You reached wave %d. Try again!" % snap.wave)
	if snap.has("clash"):
		sub = ("You smashed the Thorn Heart on %s!" % _diff_name()) if win else "The pests broke the Bloom Tree. Try again!"
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
	var ay := r.end.y - 92 - extra
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


## Team awards: everyone's good at something (support heroes too)
func _awards() -> Array:
	var players: Array = snap.get("players", [])
	if players.size() < 2:
		return []
	var out: Array = []
	var picks := [["🎯 Pest Popper", "pops"], ["💥 Big Hitter", "damage"], ["⚡ Reaction Master", "reactions"], ["🌞 Sun Gatherer", "sun"]]
	if snap.has("clash"):
		picks += [["👑 Rival Hunter", "rivalKOs"], ["🌵 Tower Smasher", "towersDown"], ["💚 Lifesaver", "revives"]]
	else:
		picks += [["🏗️ Master Builder", "built"], ["🤝 Combo Buddy", "combos"]]
	for pk in picks:
		var best = null
		var bv := 0.0
		for p in players:
			var v := float(p.get(pk[1], 0))
			if v > bv:
				bv = v
				best = p
		if best:
			out.append("%s: %s" % [pk[0], String(best.name).substr(0, 10)])
	return out.slice(0, 4)


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
	meter(Rect2(56, 44, 120, 14), lives_k, Color("4ade80") if lives_k > 0.5 else (Color("facc15") if lives_k > 0.25 else Color("fb7185")))
	txt(Vector2(182, 57), "%d/%d" % [snap.lives, snap.maxLives], 14)
	var wave_label := ("Wave %d" % snap.wave) if snap.endless else ("Wave %d/%d" % [snap.wave, snap.maxWave])
	txt(Vector2(250, 38), wave_label, 15, Color("fde68a"))
	UiKit.acorns_text(self, Vector2(250, 60), int(me.get("acorns", 0)), 16)
	if snap.waveActive:
		var left: int = snap.get("enemies", []).size() + int(snap.get("toSpawn", 0))
		txt(Vector2(345, 38), "Pests left", 11, Color("bbf7d0"))
		txt(Vector2(345, 60), "🐛 %d" % left, 16, Color.WHITE)
	elif float(snap.get("autoIn", 0)) > 0:
		txt(Vector2(345, 38), "Next wave", 11, Color("bbf7d0"))
		txt(Vector2(345, 60), "⏱ %ds" % ceili(float(snap.autoIn)), 16, Color("fde047"))
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
		if pl.get("bot", false):
			nm = "🤖 " + nm
		txt(Vector2(W - 200, y), nm.substr(0, 16), 14, Color.WHITE if hh.owner != my_owner else Color("fde047"))
		txt(Vector2(W - 24, y), "Lv %d" % hh.level, 13, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_RIGHT)
		if clash:
			if hh.get("dead", false):
				txt(Vector2(W - 200, y + 14), "💫 back in %ds" % ceili(float(hh.respawnT)), 11, Color("fca5a5"))
			else:
				var k: float = float(hh.hp) / maxf(1.0, float(hh.maxHp))
				meter(Rect2(W - 200, y + 5, 176, 6), k, Color("4ade80") if k > 0.5 else (Color("facc15") if k > 0.25 else Color("ef4444")))
		y += row
	# battle feed under the team list
	var fy := tr.end.y + 22
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
	txt(Vector2(x + 36, y + 40), "Bloom Towers %d/8" % ally_left, 11, Color("bae6fd"))
	var heart_note := ("🛡️ Thorn Towers %d/8" % foe_left) if heart.get("shield", true) else ("Thorn Towers %d/8 · HEART OPEN!" % foe_left)
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


func _draw_shop(h: Dictionary, me: Dictionary, W: float, H: float) -> void:
	var order: Array = GameData.clash.itemOrder
	var rows := order.size() + 1
	var rw := 300.0
	var rh := 44.0
	var r := Rect2(W - rw - 12, H - 70 - rows * rh - 40, rw, rows * rh + 36)
	panel(r, Color(0.05, 0.1, 0.07, 0.93), Color("facc15"), 14)
	_block_rects.append(r)
	txt(Vector2(r.position.x + 14, r.position.y + 24), "🛒 Bloom Tree Shop", 16, Color("fde047"))
	UiKit.acorns_text(self, Vector2(r.end.x - 14, r.position.y + 24), int(me.get("acorns", 0)), 15, Color("fcd34d"), true)
	var items: Array = h.get("items", [])
	var acorns := int(me.get("acorns", 0))
	var y := r.position.y + 36
	var entries: Array = order.duplicate()
	entries.append("juice")
	for id in entries:
		var cr := Rect2(r.position.x + 8, y, rw - 16, rh - 4)
		var name := ""
		var icon := ""
		var desc := ""
		var cost := 0
		var state := ""
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
			elif items.size() >= int(GameData.clash.config.maxItems):
				state = "full"
		var afford := acorns >= cost and state == ""
		var hover := cr.has_point(get_local_mouse_position())
		draw_style_box(UiKit.box(Color(0.1, 0.22, 0.13, 0.95) if hover and afford else Color(0.04, 0.09, 0.06, 0.9), Color(1, 1, 1, 0.3 if hover else 0.1), 10, 1, 0), cr)
		txt(Vector2(cr.position.x + 20, cr.position.y + 28), icon, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		txt(Vector2(cr.position.x + 40, cr.position.y + 17), name, 14, Color.WHITE if afford else Color(1, 1, 1, 0.55))
		txt(Vector2(cr.position.x + 40, cr.position.y + 33), desc.substr(0, 34), 11, Color("a7f3d0") if afford else Color(0.65, 0.95, 0.82, 0.5))
		if state == "":
			UiKit.acorns_text(self, Vector2(cr.end.x - 10, cr.position.y + 26), cost, 13, Color("fcd34d") if afford else Color("fca5a5"), true)
		else:
			txt(Vector2(cr.end.x - 10, cr.position.y + 26), "✨ Golden" if state == "golden" else "full", 13, Color("fcd34d"), HORIZONTAL_ALIGNMENT_RIGHT)
		if state == "":
			_buttons.append([cr, {"t": "buy", "item": id}])
		y += rh


func _draw_minimap(cl: Dictionary, W: float, H: float) -> void:
	var mw := 216.0
	var mh := 132.0
	var r := Rect2(W - mw - 12, H - mh - 64, mw, mh)
	minimap_rect = r
	draw_style_box(UiKit.box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.3), 8, 2, 0), r.grow(3))
	var tex: Texture2D = Sprites.tex(Sprites.atlas.maps.get(snap.map, ""))
	if tex:
		draw_texture_rect(tex, r, false, Color(1, 1, 1, 0.85))
	_block_rects.append(r)
	var k := Vector2(mw / GameData.W, mh / GameData.H)
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


func _draw_boss_bar(W: float) -> void:
	var bosses: Array = []
	for e in snap.get("enemies", []):
		if GameData.ENEMIES.get(e.type, {}).get("boss", false):
			bosses.append(e)
	if bosses.is_empty():
		return
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
		meter(mr, k, Color("ef4444") if enraged else Color("f97316"))
		if e.type == "dreadblimp":  # it gets angry at half health
			draw_line(Vector2(mr.position.x + mr.size.x * 0.5, mr.position.y - 2), Vector2(mr.position.x + mr.size.x * 0.5, mr.end.y + 2), Color(1, 1, 1, 0.8), 2)
		if String(e.get("resist", "")) != "":
			var rs: Dictionary = GameData.RESISTS.get(e.resist, {})
			txt(Vector2(r.get_center().x, y + 20), "%s %s" % [rs.get("icon", ""), rs.get("name", "")], 12, Color(rs.get("color", "#ffffff")), HORIZONTAL_ALIGNMENT_CENTER)
		_block_rects.append(r)
		y += 56


## Between waves: which pests come next (and any Endless twist)
func _draw_wave_preview(W: float, H: float) -> void:
	var next := int(snap.wave) + 1
	if not snap.endless and next > int(snap.maxWave):
		return
	var n := maxi(1, snap.get("heroes", []).size())
	var twist := String(snap.get("nextTwist", ""))
	var key := "%d|%d|%s|%s" % [next, n, snap.difficulty, twist]
	if _wave_cache.key != key:
		var plan: Dictionary = GameData.plan_wave(next, GameData.DIFFICULTIES.get(snap.difficulty, {}), n, bool(snap.endless), twist)
		_wave_cache = {"key": key, "groups": plan.groups}
	var groups: Array = _wave_cache.groups
	var slot := 62.0
	var w := maxf(230.0, groups.size() * slot + 20)
	var r := Rect2(W - 12 - w, H - 56 - 52 - 10 - 96, w, 92)
	panel(r, Color(0.05, 0.1, 0.07, 0.88))
	_block_rects.append(r)
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


func _draw_pest_card(W: float) -> void:
	var def: Dictionary = GameData.ENEMIES.get(_pest_card.type, {})
	if def.is_empty():
		return
	var a := clampf(_pest_card.t / 0.6, 0, 1) * clampf((7.0 - _pest_card.t) / 0.3, 0, 1)
	var boss: bool = def.get("boss", false)
	var r := Rect2(12, 128, 400, 104)
	panel(r, Color(0.12, 0.04, 0.06, 0.92 * a) if boss else Color(0.05, 0.1, 0.07, 0.92 * a), Color(1, 0.45, 0.45, a) if boss else Color(0.99, 0.88, 0.28, a), 14)
	pest_icon(_pest_card.type, Vector2(r.position.x + 50, r.end.y - 14), 72.0 if not boss else 80.0, Color(1, 1, 1, a))
	txt(Vector2(r.position.x + 100, r.position.y + 26), ("👑 BOSS: " if boss else "New pest: ") + String(def.get("name", "")), 16, Color(1, 0.8, 0.8, a) if boss else Color(1, 0.94, 0.54, a))
	var desc := String(def.get("desc", ""))
	if desc == "":
		desc = "A huge boss! Use your Specials together for a Team Combo, and set Target (T) to Strongest." if boss else "Watch how it moves and pick the right hero to beat it."
	draw_multiline_string(_font, r.position + Vector2(100, 48), desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 112, 13, 3, Color(1, 1, 1, a))


func _draw_buffs(h: Dictionary, W: float, H: float) -> void:
	var r := Rect2(W / 2 - 250, H - 92, 500, 80)
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
	var r := Rect2(W / 2 - 190, H / 2 - 270, 380, 540)
	panel(r, Color(0.05, 0.12, 0.08, 0.97), Color("fde047"), 20)
	_block_rects.append(r)
	txt(Vector2(W / 2, r.position.y + 48), "⏸ Paused" if is_host else "Menu", 32, Color("fde047"), HORIZONTAL_ALIGNMENT_CENTER, -1, 5)
	if not is_host:
		txt(Vector2(W / 2, r.position.y + 74), "The game keeps going for your friends", 13, Color("bbf7d0"), HORIZONTAL_ALIGNMENT_CENTER)
	var y := r.position.y + 96
	button(Rect2(W / 2 - 140, y, 280, 46), "▶ Keep playing (Esc)", {"t": "resume"}, Color("15803d"), 17)
	y += 56
	if is_host:
		button(Rect2(W / 2 - 140, y, 280, 46), "↻ Restart this game", {"t": "again"}, Color("1e3a5f"), 16)
		y += 56
	button(Rect2(W / 2 - 140, y, 280, 46), ("🔇 Sound off (M)" if Audio.muted else "🔊 Sound on (M)"), {"t": "mute"}, Color("334155"), 16)
	y += 56
	var prof := Profile.load_profile()
	button(Rect2(W / 2 - 140, y, 280, 40), Profile.shake_label(float(prof.shake)), {"t": "set_shake"}, Color("334155"), 14)
	y += 48
	button(Rect2(W / 2 - 140, y, 280, 40), Profile.dmg_label(String(prof.dmgNums)), {"t": "set_dmg"}, Color("334155"), 14)
	y += 48
	button(Rect2(W / 2 - 140, y, 280, 40), "Fullscreen: %s (F11)" % ("on" if prof.fullscreen else "off"), {"t": "fullscreen"}, Color("334155"), 14)
	y += 56
	button(Rect2(W / 2 - 140, y, 280, 46), "🏠 Leave to the menu", {"t": "menu"}, Color("7f1d1d"), 16)
	txt(Vector2(W / 2, r.end.y - 14), "Hold Tab in a game for stats and the reaction guide", 11, Color(0.73, 0.97, 0.82, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


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
	var y := H - (132.0 if snap.has("clash") else 118.0)
	for pid in sofa:
		var p: Dictionary = sofa[pid]
		var h := {}
		for x in snap.get("heroes", []):
			if x.owner == pid:
				h = x
		if h.is_empty():
			continue
		var cards: bool = int(h.pending) > 0 and h.offer.size() > 0
		var ph := 96.0 if cards else 62.0
		y -= ph + 6
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
	var r := Rect2(W / 2 - (emotes.size() * (bw + 6)) / 2 - 8, H - 92 - 112, emotes.size() * (bw + 6) + 10, 54)
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
		var s: Vector2 = xf * m[0]
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
