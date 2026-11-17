class_name WorldView
extends Node2D
## Draws the game world from a snapshot: map, towers, pests, heroes & pets,
## projectiles, Sun, chests, power-ups and effects. Positions are smoothed
## between the 30 Hz simulation ticks.

const INK := Color("1f2a1c")

var snap: Dictionary = {}
var my_owner := -1
var my_pos = null  # Vector2: my hero's predicted position (moves instantly)
var tick_alpha := 1.0
var time := 0.0
var ghost := ""  # tower preview kind

var _prev := {}
var _cur := {}
var _anim := {}  # id -> per-entity animation state
var _fx: Array = []
var _parts: Array = []
var _floats: Array = []
var _bubbles := {}  # owner_id -> {text, life, max}
var _map_id := ""
var _font: Font
var mute_audio := false

var map_sprite: Sprite2D
var camera: Camera2D
var shake := 0.0
var zoom := 1.0
var overview := false
var follow_ids: Array = []  # couch co-op: other local heroes the camera keeps on screen
var _marker := {"p": Vector2.ZERO, "t": 0.0}


func zoom_by(k: float) -> void:
	overview = false
	zoom = clampf(zoom * k, 0.6, 1.8)


func toggle_overview() -> void:
	overview = not overview
	var vp := get_viewport_rect().size
	zoom = minf(vp.x / GameData.W, vp.y / GameData.H) if overview else 1.0


func click_marker(p: Vector2) -> void:
	_marker = {"p": p, "t": 0.6}


func _ready() -> void:
	_font = UiKit.font()
	map_sprite = Sprite2D.new()
	map_sprite.centered = false
	map_sprite.z_index = -10
	add_child(map_sprite)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameData.W)
	camera.limit_bottom = int(GameData.H)
	add_child(camera)
	camera.make_current()
	Audio.dialog_line.connect(_on_dialog_line)


## Forget everything from the previous game (ids start over in a new game)
func reset() -> void:
	snap = {}
	_prev = {}
	_cur = {}
	_anim = {}
	_fx = []
	_parts = []
	_floats = []
	_bubbles = {}
	_map_id = ""
	shake = 0.0
	overview = false


func _on_dialog_line(_speaker: String, msg: String, owner_id: int, duration: float) -> void:
	if not mute_audio and owner_id >= 0 and msg != "":
		_bubbles[owner_id] = {"text": msg, "life": duration, "max": duration}


var _prune_t := 0


## Called once per simulation tick with the new snapshot
func push_snapshot(s: Dictionary) -> void:
	_prune_t += 1
	if _prune_t >= 90:
		_prune_t = 0
		var live := {}
		for e in s.get("enemies", []):
			live["e%d" % e.id] = true
		for h in s.get("heroes", []):
			live["h%d" % h.id] = true
		for u in s.get("clash", {}).get("allies", []):
			live["a%d" % u.id] = true
		for k in _anim.keys():
			if String(k).length() > 1 and String(k)[0] in ["e", "h", "a"] and String(k).substr(1).is_valid_int() and not live.has(k):
				_anim.erase(k)
	_prev = _cur
	_cur = {}
	for list in ["heroes", "enemies", "wisps"]:
		for e in s.get(list, []):
			_cur[e.id] = Vector2(e.x, e.y)
	for u in s.get("clash", {}).get("allies", []):
		_cur[u.id] = Vector2(u.x, u.y)
	snap = s
	if s.get("map", "") != _map_id:
		_map_id = s.map
		map_sprite.texture = Sprites.tex(Sprites.atlas.maps.get(_map_id, ""))
	for e in s.get("events", []):
		on_event(e)


func pos_of(id: int, fallback: Vector2) -> Vector2:
	var c: Vector2 = _cur.get(id, fallback)
	var p: Vector2 = _prev.get(id, c)
	return p.lerp(c, clampf(tick_alpha, 0.0, 1.0))


func _process(delta: float) -> void:
	time += delta
	if shake > 0:
		shake = maxf(0.0, shake - delta * 30.0)
		camera.offset = Vector2(randf() - 0.5, randf() - 0.5) * shake * 1.5
	else:
		camera.offset = Vector2.ZERO
	var want_zoom := zoom
	if overview:
		camera.position = Vector2(GameData.W, GameData.H) / 2
	elif my_pos != null and not follow_ids.is_empty():
		# couch co-op: keep everyone on screen, zooming out (not below 0.6) as they spread apart
		var box := Rect2(my_pos, Vector2.ZERO)
		for id in follow_ids:
			box = box.expand(pos_of(id, my_pos))
		camera.position = box.get_center()
		var vp := get_viewport_rect().size
		want_zoom = clampf(minf((vp.x - 260) / maxf(box.size.x, 1.0), (vp.y - 260) / maxf(box.size.y, 1.0)), 0.6, zoom)
	elif my_pos != null:
		camera.position = my_pos
	else:
		var followed := false
		for h in snap.get("heroes", []):
			if h.owner == my_owner:
				camera.position = pos_of(h.id, Vector2(h.x, h.y))
				followed = true
		if not followed:
			camera.position = GameData.sanctuary(_map_id if _map_id != "" else "meadow")
	camera.zoom = camera.zoom.lerp(Vector2(want_zoom, want_zoom), minf(1.0, delta * (4 if not follow_ids.is_empty() else 10)))
	if _marker.t > 0:
		_marker.t -= delta
	_update_fx(delta)
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------
func ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
	draw_circle(Vector2.ZERO, rx, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func ellipse_line(c: Vector2, rx: float, ry: float, col: Color, w := 2.0) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
	draw_arc(Vector2.ZERO, rx, 0.0, TAU, 40, col, w / maxf(ry / maxf(rx, 0.01), 0.3), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func text(pos: Vector2, s: String, size := 14, col := Color.WHITE, outline := 3) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w / 2.0, 0)
	if outline > 0:
		draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.7 * col.a))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func bar(c: Vector2, w: float, h: float, k: float, col: Color) -> void:
	draw_rect(Rect2(c.x - w / 2 - 1.5, c.y - 1.5, w + 3, h + 3), Color(0.06, 0.09, 0.16, 0.85))
	draw_rect(Rect2(c.x - w / 2, c.y, maxf(2.0, w * clampf(k, 0, 1)), h), col)


# ---------------------------------------------------------------------------
# Main draw
# ---------------------------------------------------------------------------
func _draw() -> void:
	if snap.is_empty():
		return
	var heroes: Array = snap.get("heroes", [])
	var clash: Dictionary = snap.get("clash", {})
	if not clash.is_empty():
		draw_fountain()
	# my range ring
	for h in heroes:
		if h.owner == my_owner and not h.get("dead", false):
			var p: Vector2 = my_pos if my_pos != null else pos_of(h.id, Vector2(h.x, h.y))
			var col: Color = GameData.player_color(h.slot)
			col.a = 0.4
			ellipse_line(p, h.range, h.range, col, 2.0)
	if _marker.t > 0:
		var k: float = _marker.t / 0.6
		ellipse_line(_marker.p, 18 * (1.4 - k * 0.4), 9 * (1.4 - k * 0.4), Color(1, 1, 1, k * 0.8), 2.5)
	for s in snap.get("spikes", []):
		draw_colored_polygon(PackedVector2Array([Vector2(s.x - 8, s.y + 5), Vector2(s.x, s.y - 9), Vector2(s.x + 8, s.y + 5)]), GameData.player_color(s.slot))
	# depth-sorted things
	var list: Array = []
	var sc: Vector2 = GameData.sanctuary(_map_id)
	list.append([sc.y + 20, "tree", null])
	for g in snap.get("gadgets", []):
		list.append([g.y, "gadget", g])
	for e in snap.get("enemies", []):
		var p := pos_of(e.id, Vector2(e.x, e.y))
		list.append([p.y + (30 if e.boss else 0), "enemy", e])
	for h in heroes:
		var p: Vector2 = my_pos if h.owner == my_owner and my_pos != null else pos_of(h.id, Vector2(h.x, h.y))
		list.append([p.y + 4, "hero", h])
	for c in snap.get("chests", []):
		list.append([c.y, "chest", c])
	for pu in snap.get("powerups", []):
		list.append([pu.y, "powerup", pu])
	for t in clash.get("allyTowers", []):
		if t.kind != "tree" and t.hp > 0:
			list.append([t.y, "bloom", t])
	for u in clash.get("allies", []):
		var p := pos_of(u.id, Vector2(u.x, u.y))
		list.append([p.y, "ally", u])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for it in list:
		match it[1]:
			"tree": draw_tree(sc)
			"gadget": draw_gadget(it[2])
			"enemy": draw_enemy(it[2])
			"hero": draw_hero(it[2])
			"chest": draw_chest(it[2])
			"powerup": draw_powerup(it[2])
			"bloom": draw_bloom_tower(it[2])
			"ally": draw_ally(it[2])
	for w in snap.get("wisps", []):
		var p := pos_of(w.id, Vector2(w.x, w.y))
		draw_circle(p, 9, Color(1, 0.6, 0.2, 0.35))
		draw_circle(p, 5, Color("fdba74"))
	draw_projectiles()
	if not clash.is_empty():
		draw_camps(clash)
		draw_clash_shots(clash)
	for s in snap.get("suns", []):
		var e: Dictionary = Sprites.atlas.get("sun", {})
		Sprites.draw_frame(self, Sprites.tex(e.get("file", "")), e, 0, Vector2(s.x, s.y + sin(time * 3 + s.x) * 3), false, 1.0, Color.WHITE, Sprites.scale)
	draw_fx()
	if ghost != "" and my_pos != null:
		# where the selected tower would go, with its real (round) range
		var spot: Dictionary = GameData.gadget_spot(_map_id, ghost, my_pos.x, my_pos.y)
		var def: Dictionary = GameData.GADGETS[ghost]
		var sp := Vector2(spot.x, spot.y)
		var col := Color(0.5, 1, 0.6, 0.55) if spot.ok else Color(1, 0.4, 0.4, 0.55)
		draw_circle(sp, def.range, Color(col.r, col.g, col.b, 0.1))
		draw_arc(sp, def.range, 0, TAU, 64, col, 2, true)
		var gt := Sprites.gadget_tex(ghost, 1, -1, 0)
		Sprites.draw_frame(self, gt, Sprites.atlas.gadgets.get(ghost, {}), 0, sp, false, 1.0, Color(1, 1, 1, 0.55) if spot.ok else Color(1, 0.5, 0.5, 0.45), Sprites.scale)
		var why := "F: build here" if spot.ok else String(spot.get("reason", "Can't build here"))
		text(sp + Vector2(0, 34), why, 13, Color("bbf7d0") if spot.ok else Color("fca5a5"), 4)
	_draw_tower_help()


func draw_tree(sc: Vector2) -> void:
	var e: Dictionary = Sprites.atlas.get("tree", {})
	var k := clampf(float(snap.lives) / maxf(1.0, float(snap.maxLives)), 0, 1)
	var hurt: float = _anim.get("tree_hurt", 0.0)
	var mod := Color(1, 1 - hurt * 0.5, 1 - hurt * 0.5) if hurt > 0 else (Color.WHITE if k > 0.35 else Color(1, 0.75, 0.75))
	var off := Vector2(sin(time * 60) * hurt * 6, 0)
	Sprites.draw_frame(self, Sprites.tex(e.get("file", "")), e, int(time * 2) % 4, sc + off, false, 1.0, mod, Sprites.scale)
	if snap.has("clash"):
		for t in snap.clash.allyTowers:
			if t.kind == "tree":
				bar(Vector2(sc.x, sc.y - 150), 120, 9, float(t.hp) / maxf(1.0, t.maxHp), Color("4ade80") if k > 0.35 else Color("fb7185"))
				if t.get("shield", false):
					shield_bubble(sc - Vector2(0, 50), 96, Color(0.49, 0.83, 0.99))


func draw_gadget(g: Dictionary) -> void:
	var t := Sprites.gadget_tex(g.kind, g.level, g.branch, g.slot)
	var e: Dictionary = Sprites.atlas.gadgets.get(g.kind, {})
	var mod := Color(1, 1, 1, 0.7) if g.get("asleep", false) else Color.WHITE
	Sprites.draw_frame(self, t, e, 0, Vector2(g.x, g.y), false, 1.0, mod, Sprites.scale)
	if g.kind == "fern":
		var r: float = GameData.GADGETS.fern.range
		var B: Dictionary = GameData.gadget_branch("fern", g.branch)
		r = GameData.gnum(B, "range", r)
		var ph := fmod(time * 0.8 + g.x * 0.003, 1.0)
		draw_arc(Vector2(g.x, g.y), r * (0.4 + ph * 0.6), 0, TAU, 48, Color(0.49, 0.83, 0.99, 0.35 * (1 - ph)), 2, true)
	if g.get("asleep", false):
		text(Vector2(g.x + 10, g.y - 60 - fmod(time * 20, 20)), "z", 16, Color("e0e7ff"))


func draw_enemy(e: Dictionary) -> void:
	var def: Dictionary = GameData.ENEMIES.get(e.type, {})
	if def.get("structure", false):
		draw_foe_building(e, def)
		return
	var entry := Sprites.pest_entry(e.type)
	if entry.is_empty():
		return
	var p := pos_of(e.id, Vector2(e.x, e.y))
	var a: Dictionary = _anim.get("e%d" % e.id, {})
	if a.is_empty():
		a = {"phase": randf(), "face": 1, "lx": p.x, "hit": 0.0}
		_anim["e%d" % e.id] = a
	if absf(p.x - a.lx) > 0.3:
		a.face = 1 if p.x > a.lx else -1
	a.lx = p.x
	var dt := get_process_delta_time()
	if not e.frozen and not e.stunned and not e.get("trapped", false):
		a.phase += dt * (0.9 if e.slowed else 1.8) * (0.6 if e.boss else 1.0)
	var S := 1.35 if e.big else 1.0
	var R: float = def.radius * S
	var flyer: bool = def.get("art", e.type) in ["wasp", "zeppelin", "dreadblimp", "camopuff", "mothmedic", "snoozemoth"]
	var feet := p + Vector2(0, R * 0.75)
	if e.burrowed:
		ellipse(feet, R * 1.05, R * 0.32, Color(0, 0, 0, 0.22))
		ellipse(p + Vector2(0, R * 0.2), R * 1.05, R * 0.5, Color("8a5a1e"))
		draw_circle(p - Vector2(0, R * 0.3), R * 0.4, Color("facc15"))
		return
	ellipse(feet, R * (0.7 if flyer else 0.95), R * (0.25 if flyer else 0.32), Color(0, 0, 0, 0.18 if flyer else 0.28))
	if def.get("minion", false) or def.get("rival", false):
		ellipse_line(feet, R * 1.05, R * 0.38, Color(0.96, 0.25, 0.37, 0.75), 2.5)
	if e.get("casting", false):
		draw_circle(p - Vector2(0, R * 0.4), R * 1.6, Color(0.94, 0.27, 0.27, 0.18 + 0.1 * sin(time * 20)))
	var alpha := 1.0
	if e.camo:
		alpha = 0.45 + sin(time * 4 + p.x) * 0.12
	if e.sheltered:
		alpha *= 0.55
	var mod := Color(1, 1, 1, alpha)
	if e.flash:
		mod = Color(1.8, 1.8, 1.8, alpha)
	var frame := int(fposmod(a.phase, 1.0) * 8) % 8
	Sprites.draw_frame(self, Sprites.tex(entry.file), entry, frame, feet, a.face < 0, S, mod, Sprites.scale)
	var top := feet.y - (R * 2.6 if flyer else R * 2.0)
	if e.frozen:
		draw_rect(Rect2(p.x - R * 1.05, top + 2, R * 2.1, feet.y - top - 2), Color(0.75, 0.9, 1.0, 0.55))
	if e.get("trapped", false):
		var br := R * 1.45
		var by := p.y - R * 0.5 + sin(time * 4 + p.x) * 3
		draw_circle(Vector2(p.x, by), br, Color(0.58, 0.77, 0.99, 0.25))
		draw_arc(Vector2(p.x, by), br, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.0, true)
	if e.stunned:
		for k in 3:
			var ang := time * 6 + k * TAU / 3
			draw_circle(Vector2(p.x + cos(ang) * R * 0.8, top - 4 + sin(ang) * 4), 3.5, Color("fde047"))
	if e.get("enraged", false):
		var pulse := 0.5 + 0.5 * sin(time * 9)
		draw_circle(p - Vector2(0, R * 0.3), R * (1.25 + 0.1 * pulse), Color(0.94, 0.27, 0.27, 0.16 + 0.1 * pulse))
		if randf() < dt * 10:
			_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.6, p.y - R * 0.2), "v": Vector2(0, -60), "life": 0.7, "max": 0.7, "size": 5.0, "col": Color("7f1d1d"), "g": 0.0})
	if e.get("frostbit", false) and randf() < dt * 10:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.5), "v": Vector2(0, 30), "life": 0.5, "max": 0.5, "size": 3.0, "col": Color("bae6fd"), "g": 60.0})
	if e.burning and randf() < dt * 14:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.6), "v": Vector2(0, -50), "life": 0.45, "max": 0.45, "size": 4.0, "col": Color("fb923c"), "g": 0.0})
	if e.get("soaked", false) and randf() < dt * 8:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.4), "v": Vector2(0, 40), "life": 0.5, "max": 0.5, "size": 2.4, "col": Color("60a5fa"), "g": 120.0})
	if e.get("poisoned", false) and randf() < dt * 7:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.2), "v": Vector2(0, -28), "life": 0.55, "max": 0.55, "size": 3.0, "col": Color("a3e635"), "g": 0.0})
	if e.slowed and not e.frozen:
		ellipse_line(feet, R * 1.05, R * 0.38, Color(0.49, 0.83, 0.99, 0.5), 2)
	if e.get("sunlit", false):
		ellipse_line(feet, R * 1.05, R * 0.4, Color(0.99, 0.88, 0.28, 0.6), 2)
	if e.get("resist", "") != "":
		var rs: Dictionary = GameData.RESISTS.get(e.resist, {})
		var bc := Vector2(p.x - R * 0.95, top + 8)
		draw_circle(bc, 9, Color(0.06, 0.09, 0.16, 0.85))
		draw_arc(bc, 9, 0, TAU, 20, Color(rs.get("color", "#ffffff")), 2.0, true)
		text(bc + Vector2(0, 4), String(rs.get("icon", "")), 10, Color.WHITE, 0)
	if def.get("rival", false):
		var k: float = float(e.hp) / float(e.maxHp)
		bar(Vector2(p.x, top - 10), 64, 7, k, Color("ef4444"))
		var tag := "👑 %s  Lv %d" % [def.get("name", ""), int(e.get("lvl", 1))]
		text(Vector2(p.x, top - 16), tag, 13, Color("fecaca"), 4)
		if e.get("fleeing", false):
			text(Vector2(p.x, top - 34), "running home!", 12, Color("fde68a"), 3)
	elif def.get("neutral", false):
		if e.get("elder", false):
			text(Vector2(p.x, top - 18), "👑 Elder %s" % def.get("name", ""), 13, Color("fde047"), 4)
		if e.hp < e.maxHp:
			bar(Vector2(p.x, top - 8), maxf(40.0, R * 1.8), 6, float(e.hp) / float(e.maxHp), Color("facc15"))
	elif e.hp < e.maxHp and not e.boss:
		var k: float = float(e.hp) / float(e.maxHp)
		var col := Color("f87171") if def.get("minion", false) else (Color("4ade80") if k > 0.5 else (Color("facc15") if k > 0.25 else Color("fb7185")))
		bar(Vector2(p.x, top - 8), maxf(26.0, R * 1.8), 5, k, col)


func draw_hero(h: Dictionary) -> void:
	var mine: bool = h.owner == my_owner and my_pos != null
	var p: Vector2 = my_pos if mine else pos_of(h.id, Vector2(h.x, h.y))
	if h.get("dead", false):
		draw_knocked_out(h, p)
		return
	var a: Dictionary = _anim.get("h%d" % h.id, {})
	if a.is_empty():
		a = {"lx": p.x, "ly": p.y, "walk": 0.0, "move": 0.0, "face": 1, "attack": 0.0, "pet": p - Vector2(30, -18), "pet_face": 1, "pet_move": 0.0}
		_anim["h%d" % h.id] = a
	var dt := maxf(get_process_delta_time(), 0.001)
	var moved := Vector2(p.x - a.lx, p.y - a.ly).length()
	a.move = lerpf(a.move, 1.0 if moved / dt > 25 else 0.0, minf(1.0, dt * 12))
	var moving: bool = a.move > 0.3
	if moving:
		a.walk += dt * 13
	if absf(p.x - a.lx) > 0.3:
		a.face = 1 if p.x > a.lx else -1
	a.lx = p.x
	a.ly = p.y
	if h.recoil > 0.3:
		a.attack = 0.18
		a.aim = h.angle
	a.attack = maxf(0.0, a.attack - dt)
	var face: int = a.face
	if a.attack > 0:
		face = 1 if cos(h.angle) >= 0 else -1
	var col: Color = GameData.player_color(h.slot)
	var giant: bool = GameData.gnum(h.buffs, "giant") > 0
	var lv_scale := (1.05 + minf(0.2, h.level * 0.008)) * (1.4 if giant else 1.0)
	# pet first (it trots along behind)
	if h.get("pet", "none") != "none":
		draw_pet(h, a, p, face)
	ellipse(p + Vector2(0, 21), 20, 7, Color(0, 0, 0, 0.3))
	ellipse_line(p + Vector2(0, 21), 24, 10, col, 3)
	if h.rally:
		draw_circle(p, 46, Color(0.99, 0.88, 0.28, 0.18))
	if GameData.gnum(h.buffs, "frenzy") > 0:
		draw_circle(p - Vector2(0, 14), 40, Color(0.98, 0.45, 0.09, 0.18))
	if h.get("recall", 0.0) > 0:
		var rk: float = h.recall
		draw_rect(Rect2(p.x - 26, p.y - 140 * rk, 52, 140 * rk + 20), Color(0.49, 0.83, 0.99, 0.18))
		draw_arc(p - Vector2(0, 20), 46, -PI / 2, -PI / 2 + TAU * rk, 40, Color("7dd3fc"), 5, true)
	var frame := 0
	if a.attack > 0:
		frame = 10
	elif moving:
		frame = 4 + int(fposmod(a.walk / TAU, 1.0) * 6) % 6
	else:
		frame = int(time * 2.0) % 4
	var entry := Sprites.hero_entry(h.type)
	var t := Sprites.hero_tex(h.type, mini(h.tierA, 4), mini(h.tierB, 4))
	var feet := p + Vector2(0, 21)
	var hurt_mod := Color(1.8, 0.6, 0.6) if h.get("hurt", false) else Color.WHITE
	Sprites.draw_frame(self, t, entry, frame, feet, face < 0, lv_scale, hurt_mod, Sprites.scale)
	var hat: String = h.get("hat", "none")
	if hat != "none" and Sprites.atlas.hats.has(hat):
		var anchor: Array = Sprites.atlas.hatAnchor.get(h.type, [0, -55, 1])
		var bob := (sin(time * 2.6) * 0.03 * 10.0) if not moving else -absf(sin(a.walk)) * 3.2
		var hp := feet + Vector2(anchor[0] * face, anchor[1] + bob) * lv_scale
		Sprites.draw_frame(self, Sprites.tex(Sprites.atlas.hats[hat].file), Sprites.atlas.hats[hat], 0, hp, face < 0, anchor[2] * lv_scale, Color.WHITE, Sprites.scale)
	if h.dazed:
		for k in 3:
			var ang := time * 7 + k * TAU / 3
			draw_circle(Vector2(p.x + cos(ang) * 16, p.y - 66 + sin(ang) * 5), 4, Color("d9f99d"))
	# name tag
	var pl := _player(h.owner)
	var name: String = ("[bot] " if pl.get("bot", false) else "") + String(pl.get("name", "Hero"))
	var ty := p.y - 64 - (lv_scale - 1.1) * 60
	var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34
	draw_rect(Rect2(p.x - tw / 2, ty - 10, tw, 20), Color(0.04, 0.08, 0.05, 0.75))
	draw_rect(Rect2(p.x - tw / 2, ty - 10, tw, 20), col, false, 1.6)
	draw_circle(Vector2(p.x - tw / 2 + 10, ty), 8, Color("facc15"))
	text(Vector2(p.x - tw / 2 + 10, ty + 4.5), str(h.level), 11, Color("422006"), 0)
	text(Vector2(p.x + 10, ty + 4.5), name, 13)
	if h.pending > 0:
		draw_circle(Vector2(p.x + tw / 2 + 9, ty + sin(time * 6) * 3), 7, Color("fde047"))
	if h.has("maxHp") and float(h.maxHp) > 0:
		var hk: float = float(h.hp) / float(h.maxHp)
		bar(Vector2(p.x, ty - 20), 60, 6, hk, Color("4ade80") if hk > 0.5 else (Color("facc15") if hk > 0.25 else Color("ef4444")))
	if _bubbles.has(h.owner):
		var bb: Dictionary = _bubbles[h.owner]
		var ba: float = clampf(float(bb.life) * 2.5, 0.0, 1.0)
		var bt: String = bb.text
		var bw := _font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18
		var by := ty - (38.0 if h.has("maxHp") and float(h.maxHp) > 0 else 24.0)
		var br := Rect2(p.x - bw / 2.0, by - 22.0, bw, 24.0)
		draw_rect(br, Color(0.05, 0.11, 0.07, 0.92 * ba))
		draw_rect(br, Color(col.r, col.g, col.b, 0.9 * ba), false, 1.8)
		text(Vector2(p.x, by - 5.0), bt, 13, Color(1, 1, 1, ba), 2)


func draw_pet(h: Dictionary, a: Dictionary, p: Vector2, face: int) -> void:
	var kind: String = h.pet
	var entry: Dictionary = Sprites.atlas.pets.get(kind, {})
	if entry.is_empty():
		return
	var dt := maxf(get_process_delta_time(), 0.001)
	var target := p + Vector2(-face * 30, 18)
	var pp: Vector2 = a.pet
	if pp.distance_to(target) > 400:
		pp = target
	var old := pp
	pp = pp.lerp(target, minf(1.0, dt * 5))
	a.pet_move = lerpf(a.pet_move, 1.0 if pp.distance_to(target) > 6 else 0.0, minf(1.0, dt * 8))
	if absf(pp.x - old.x) > 0.15:
		a.pet_face = 1 if pp.x > old.x else -1
	elif pp.distance_to(target) < 4:
		a.pet_face = face
	a.pet = pp
	var flying := kind in ["bee", "butterfly", "dragon"]
	ellipse(pp, 6 if flying else 9, 2 if flying else 3, Color(0, 0, 0, 0.2))
	var frame := (4 + int(time * 10) % 6) if a.pet_move > 0.3 else int(time * 3) % 4
	Sprites.draw_frame(self, Sprites.tex(entry.file), entry, frame, pp, a.pet_face < 0, 1.25, Color.WHITE, Sprites.scale)


func draw_chest(c: Dictionary) -> void:
	var e: Dictionary = Sprites.atlas.chests.get("big" if c.big else "small", {})
	Sprites.draw_frame(self, Sprites.tex(e.get("file", "")), e, 0, Vector2(c.x, c.y + sin(time * 3) * 2), false, 1.0, Color.WHITE, Sprites.scale)


func draw_powerup(pu: Dictionary) -> void:
	var e: Dictionary = Sprites.atlas.powerups.get(pu.kind, {})
	var blink: bool = pu.ttl < 4 and sin(time * 16) < 0
	if not blink:
		Sprites.draw_frame(self, Sprites.tex(e.get("file", "")), e, 0, Vector2(pu.x, pu.y + sin(time * 4) * 4), false, 1.0, Color.WHITE, Sprites.scale)


const PROJ_COLORS := {"pea": "4ade80", "megapea": "fde047", "thorn": "7dd3fc", "needle": "d8b4fe", "icicle": "bae6fd", "snowball": "e0f2fe",
	"bomb": "fb7185", "rocket": "fb923c", "cluster": "fda4af", "ember": "fb923c", "sunseed": "fde047", "bubble": "93c5fd"}


func draw_projectiles() -> void:
	for p in snap.get("projectiles", []):
		var k := clampf(tick_alpha, 0, 1.2) / 30.0
		var at := Vector2(p.x + p.vx * k, p.y + p.vy * k)
		var col := Color(PROJ_COLORS.get(p.kind, "ffffff"))
		var r := 6.0
		match p.kind:
			"megapea", "bomb", "rocket": r = 10.0
			"bubble": r = 8.0
			"needle", "thorn": r = 4.0
		var back := at - Vector2(p.vx, p.vy).normalized() * r * 2.2
		draw_line(back, at, Color(col.r, col.g, col.b, 0.45), r * 1.2, true)
		draw_circle(at, r * 1.8, Color(col.r, col.g, col.b, 0.18))
		if p.kind == "bubble":
			draw_circle(at, r, Color(0.58, 0.77, 0.99, 0.4))
			draw_arc(at, r, 0, TAU, 20, Color.WHITE, 1.4, true)
		else:
			draw_circle(at, r, col)
			draw_arc(at, r, 0, TAU, 16, Color(0, 0, 0, 0.45), 1.2, true)


func _player(id: int) -> Dictionary:
	for p in snap.get("players", []):
		if p.id == id:
			return p
	return {}


# ---------------------------------------------------------------------------
# Effects from events
# ---------------------------------------------------------------------------
func ring(pos: Vector2, r: float, col: Color, w := 4.0, life := 0.4) -> void:
	_fx.append({"kind": "ring", "p": pos, "r": r, "col": col, "w": w, "life": life, "max": life})


func burst(pos: Vector2, cols: Array, n: int, speed: float) -> void:
	for i in n:
		var ang := randf() * TAU
		var sp := speed * (0.4 + randf() * 0.6)
		_parts.append({"p": pos, "v": Vector2(cos(ang), sin(ang)) * sp, "life": 0.6, "max": 0.6, "size": 3.0 + randf() * 2.5, "col": Color(cols[randi() % cols.size()]), "g": 200.0})


func float_text(pos: Vector2, s: String, col: Color, size := 16, life := 1.0) -> void:
	_floats.append({"p": pos, "s": s, "col": col, "size": size, "life": life, "max": life})


func on_event(e: Dictionary) -> void:
	var pos := Vector2(e.get("x", 0), e.get("y", 0))
	if not mute_audio:
		_play_event_audio(e)
	match e.type:
		"explosion":
			var frost: bool = e.get("kind", "") == "frost"
			_fx.append({"kind": "flash", "p": pos, "r": e.radius * 0.9, "col": Color("bae6fd" if frost else "fde68a"), "life": 0.18, "max": 0.18})
			ring(pos, e.radius, Color("67e8f9" if frost else "fb923c"), 6)
			burst(pos, ["fde047", "fb923c", "ef4444"] if not frost else ["e0f2fe", "7dd3fc", "ffffff"], 16, 190)
			if e.radius > 85:
				shake = maxf(shake, 6)
		"nova":
			ring(pos, e.radius, Color(e.get("color", "#67e8f9")), 5, 0.4)
		"lightning":
			var pts := PackedVector2Array()
			for q in e.points:
				pts.append(Vector2(q[0], q[1]))
			_fx.append({"kind": "bolt", "pts": pts, "col": Color("c084fc"), "life": 0.24, "max": 0.24})
		"thunder":
			_fx.append({"kind": "bolt", "pts": PackedVector2Array([Vector2(pos.x + 30, pos.y - 400), Vector2(pos.x + 10, pos.y - 120), pos]), "col": Color("a5b4fc"), "life": 0.4, "max": 0.4})
			shake = maxf(shake, 4)
		"beam", "snipe":
			var a := Vector2(e.get("x1", pos.x), e.get("y1", pos.y))
			var b := Vector2(e.get("x2", e.get("tx", pos.x)), e.get("y2", e.get("ty", pos.y)))
			_fx.append({"kind": "beam", "a": a, "b": b, "col": Color("fde047"), "life": 0.3, "max": 0.3})
		"flame":
			var n := 36 if e.ring else 16
			for i in n:
				var ang: float = (TAU * i / n) if e.ring else e.angle + (randf() - 0.5) * e.coneAngle * 1.2
				var sp: float = e.range * (1.6 + randf() * 1.4)
				_parts.append({"p": pos + Vector2(cos(ang), sin(ang)) * 12, "v": Vector2(cos(ang), sin(ang)) * sp, "drag": 3.2, "life": 0.42, "max": 0.42, "size": 7.0 + randf() * 6, "col": Color("fb923c"), "g": 0.0})
		"enemy_pop":
			burst(pos, [e.get("color", "#a3e635"), "#ffffff"], 40 if e.boss else 12, 260 if e.boss else 130)
			ring(pos, 110 if e.boss else 26, Color.WHITE, 3, 0.25)
			if e.boss:
				shake = maxf(shake, 12)
		"sun_collected":
			float_text(pos - Vector2(0, 10), "+%d XP" % int(e.amount), Color("fde047"), 17)
			ring(pos, 34, Color("fde047"), 3, 0.3)
		"dmg":
			float_text(pos + Vector2((randf() - 0.5) * 14, 0), ("%d!" % int(e.amount)) if e.crit else str(int(e.amount)), Color("fde047") if e.crit else Color.WHITE, 18 if e.crit else 12, 0.7)
		"level_up":
			_fx.append({"kind": "pillar", "p": pos, "col": Color("fde047"), "life": 1.0, "max": 1.0})
			float_text(pos - Vector2(0, 70), "LEVEL %d!" % int(e.level), Color("fde047"), 22, 1.4)
		"hero_upgraded":
			float_text(pos - Vector2(0, 56), String(e.label), Color.WHITE, 16, 1.3)
			ring(pos, 56, Color("facc15") if e.path == "A" else Color("38bdf8"), 4, 0.4)
		"special":
			_fx.append({"kind": "flash", "p": pos, "r": 220, "col": GameData.player_color(e.slot), "life": 0.3, "max": 0.3})
			ring(pos, 260, GameData.player_color(e.slot), 10, 0.6)
			shake = maxf(shake, 8)
		"leak":
			_anim["tree_hurt"] = 0.6
			shake = maxf(shake, 5)
			float_text(pos - Vector2(0, 50), "-%d lives" % int(e.lives), Color("fb7185"), 18, 1.1)
		"reaction":
			if String(e.kind).begins_with("resist_"):
				float_text(pos - Vector2(0, 14), "RESIST", Color("cbd5e1"), 13, 0.8)
			else:
				var rd: Dictionary = GameData.REACTIONS.get(e.kind, {})
				float_text(pos - Vector2(0, 20), String(rd.get("name", e.kind)) + "!", Color(rd.get("color", "#ffffff")), 18, 1.0)
				ring(pos, 46, Color(rd.get("color", "#ffffff")), 4, 0.35)
		"dash":
			_fx.append({"kind": "beam", "a": Vector2(e.fromX, e.fromY - 10), "b": Vector2(e.x, e.y - 10), "col": GameData.player_color(e.slot), "life": 0.35, "max": 0.35})
			burst(pos, ["86efac", "4ade80", "ffffff"], 10, 120)
		"lily_wave", "tidal":
			ring(pos, e.get("range", e.get("r", 200)), Color("3b82f6"), 12, 0.5)
		"bubble_pop":
			ring(pos, e.r, Color("93c5fd"), 3, 0.3)
		"bubble_trap":
			float_text(pos - Vector2(0, 40), "TRAPPED!", Color("bfdbfe"), 14, 0.9)
		"spring_life":
			float_text(pos - Vector2(0, 70), "+1 life: Spring of Life", Color("86efac"), 15, 1.4)
		"spore_warn":
			_fx.append({"kind": "warn", "p": pos, "r": e.r, "col": Color("bef264"), "life": e.delay, "max": e.delay})
		"spore_burst":
			_fx.append({"kind": "flash", "p": pos, "r": e.r, "col": Color("bef264"), "life": 0.35, "max": 0.35})
		"hero_dazed":
			float_text(pos - Vector2(0, 70), "Dizzy!", Color("d9f99d"), 16, 1.1)
		"teleport", "hero_spawn":
			_fx.append({"kind": "pillar", "p": pos, "col": GameData.player_color(e.get("slot", 0)), "life": 0.8, "max": 0.8})
		"combo":
			float_text(pos - Vector2(0, 40), "TEAM COMBO!", Color("f0abfc"), 24, 1.6)
			ring(pos, 330, Color("f0abfc"), 10, 0.7)
			shake = maxf(shake, 10)
		"chest_open":
			burst(pos, ["fde047", "f472b6", "60a5fa", "4ade80"], 40, 260)
		"powerup_get":
			ring(pos, 60, Color("fde047"), 4, 0.4)
		"gadget_placed", "gadget_upgraded":
			_fx.append({"kind": "pillar", "p": pos, "col": Color("facc15"), "life": 0.6, "max": 0.6})
		"gadget_boom":
			shake = maxf(shake, 5)
		"solar_beam":
			_fx.append({"kind": "pillar", "p": pos, "col": Color("fde047"), "life": 0.6, "max": 0.6})
			ring(pos, 90, Color("fde047"), 6, 0.45)
		"pest_heal":
			ring(pos, e.r, Color("4ade80"), 3, 0.5)
		"sleep_dust":
			ring(pos, e.r, Color("c4b5fd"), 3, 0.6)
		"summon":
			ring(pos, 60, Color("a78bfa"), 4, 0.4)
		"mole_up":
			burst(pos, ["8a5a1e", "a16207", "facc15"], 10, 120)
		# --- Garden Clash
		"struct_down":
			var foe: bool = e.get("team", "") == "foe"
			_fx.append({"kind": "flash", "p": pos - Vector2(0, 40), "r": 160 if e.get("core", false) else 110, "col": Color("f0abfc") if foe else Color("7dd3fc"), "life": 0.35, "max": 0.35})
			ring(pos - Vector2(0, 30), 200, Color("e879f9") if foe else Color("38bdf8"), 10, 0.7)
			burst(pos - Vector2(0, 40), ["c084fc", "7e22ce", "f0abfc", "ffffff"] if foe else ["7dd3fc", "fde047", "ffffff"], 60, 320)
			float_text(pos - Vector2(0, 120), "%s %s!" % [e.get("name", ""), "smashed" if foe else "lost"], Color("f5d0fe") if foe else Color("fca5a5"), 22, 1.8)
			shake = maxf(shake, 14)
		"tower_fire":
			_fx.append({"kind": "flash", "p": pos, "r": 16, "col": Color("fde047") if e.get("team", "") == "ally" else Color("e879f9"), "life": 0.12, "max": 0.12})
		"slam_warn":
			_fx.append({"kind": "warn", "p": pos, "r": e.r, "col": Color("f87171"), "life": e.delay, "max": e.delay})
		"slam":
			ring(pos, e.r, Color("fb923c"), 8, 0.45)
			burst(pos, ["a16207", "78350f", "fde68a"], 24, 220)
			shake = maxf(shake, 7)
		"volley_warn":
			_fx.append({"kind": "beam", "a": pos, "b": Vector2(e.tx, e.ty), "col": Color("f87171"), "life": 0.35, "max": 0.35})
		"volley":
			ring(pos, 40, Color("facc15"), 4, 0.3)
		"rival_swipe":
			_fx.append({"kind": "swipe", "p": pos, "a": atan2(float(e.ty) - pos.y, float(e.tx) - pos.x), "col": Color("fde68a"), "life": 0.22, "max": 0.22})
		"hero_down":
			burst(pos, ["9ca3af", "e5e7eb", "ffffff"], 24, 200)
			float_text(pos - Vector2(0, 70), "Knocked out!", Color("fca5a5"), 18, 1.4)
		"revive":
			_fx.append({"kind": "pillar", "p": pos, "col": Color("86efac"), "life": 0.9, "max": 0.9})
			float_text(pos - Vector2(0, 80), "Revived by %s!" % e.get("by", "a friend"), Color("86efac"), 17, 1.6)
		"hero_respawn":
			_fx.append({"kind": "pillar", "p": pos, "col": GameData.player_color(e.get("slot", 0)), "life": 0.8, "max": 0.8})
		"item_bought":
			var info: Dictionary = GameData.clash_item(String(e.item))
			var label := String(info.get("icon", "🧃")) + " " + String(info.get("name", "Berry Juice"))
			float_text(pos - Vector2(0, 90), label, Color("fde047") if e.get("golden", false) else Color.WHITE, 16, 1.4)
			ring(pos, 50, Color("fde047"), 4, 0.4)
		"potion":
			ring(pos, 44, Color("f472b6"), 4, 0.5)
			burst(pos - Vector2(0, 30), ["f472b6", "fbcfe8"], 10, 90)
		"rival_spawn":
			ring(pos, 80, Color("ef4444"), 6, 0.6)
		"camp_up":
			ring(pos, 70 if e.get("epic", false) else 40, Color("facc15"), 4, 0.5)
		"gate_regrow":
			_fx.append({"kind": "pillar", "p": pos, "col": Color("c084fc") if e.side == "foe" else Color("7dd3fc"), "life": 1.0, "max": 1.0})
		"ally_pop":
			burst(pos, ["86efac", "4ade80", "ffffff"], 8, 110)
		"tree_hit":
			_anim["tree_hurt"] = maxf(float(_anim.get("tree_hurt", 0.0)), 0.25)


func _play_event_audio(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"shot":
			match String(e.get("kind", "")):
				"pea": Audio.play_sfx("shoot_pea", -9.0, 0.08, 70)
				"boom": Audio.play_sfx("shoot_boom", -5.0, 0.06, 100)
				"bubble": Audio.play_sfx("shoot_bubble", -7.0, 0.08, 85)
		"explosion":
			Audio.play_sfx("explosion", -4.0, 0.08, 70)
		"nova":
			Audio.play_sfx("shoot_frost", -5.0, 0.08, 120)
		"lightning":
			Audio.play_sfx("shoot_zap", -4.0, 0.09, 80)
		"thunder":
			Audio.play_sfx("thunder", -2.0, 0.06, 110)
		"beam", "snipe":
			Audio.play_sfx("shoot_beam", -4.0, 0.06, 90)
		"flame":
			Audio.play_sfx("shoot_flame", -6.0, 0.08, 140)
		"enemy_pop":
			if e.get("boss", false):
				Audio.play_sfx("pop_boss", 0.0, 0.02, 200)
			else:
				Audio.play_sfx("pop_small", -5.0, 0.10, 65)
		"sun_collected":
			Audio.play_sfx("sun_pickup", -3.0, 0.06, 90)
		"level_up":
			Audio.play_sfx("level_up", -1.0, 0.02, 200)
		"special":
			Audio.play_sfx("special_cast", -1.0, 0.04, 150)
			if e.has("heroType"):
				Audio.say_hero(String(e.heroType), "special", int(e.get("owner", -1)))
		"leak", "tree_hit":
			Audio.play_sfx("tree_hurt", -1.0, 0.04, 180)
		"reaction":
			var kind := String(e.get("kind", ""))
			if not kind.begins_with("resist_") and kind != "sunlit":
				Audio.play_sfx("react_" + kind, -2.0, 0.05, 140)
		"dash":
			Audio.play_sfx("dash", -2.0, 0.07, 100)
		"teleport", "hero_respawn":
			Audio.play_sfx("teleport", -2.0, 0.04, 200)
		"lily_wave", "tidal":
			Audio.play_sfx("shoot_bubble", -2.0, 0.05, 140)
		"hero_dazed":
			Audio.play_sfx("dazed", -2.0, 0.04, 250)
		"combo":
			Audio.play_sfx("team_combo", 1.0, 0.0, 400)
			Audio.say("ann_combo", -1, true)
		"chest_drop":
			Audio.play_sfx("chest_drop", -2.0, 0.04, 150)
		"chest_open":
			Audio.play_sfx("chest_open", 0.0, 0.02, 200)
		"powerup_get":
			Audio.play_sfx("powerup", -1.0, 0.03, 150)
		"gadget_placed":
			Audio.play_sfx("build", -2.0, 0.05, 100)
		"gadget_upgraded":
			Audio.play_sfx("upgrade", -1.0, 0.04, 120)
		"gadget_sold":
			Audio.play_sfx("sell", -2.0, 0.04, 120)
		"gadget_wake":
			Audio.play_sfx("gadget_wake", -2.0, 0.04, 250)
		"sleep_dust":
			Audio.play_sfx("sleep_dust", -3.0, 0.04, 400)
		"boss_enrage":
			Audio.play_sfx("boss_warn", 0.0, 0.02, 500)
			Audio.say("boss_enrage", -1, true)
		"struct_down", "slam":
			Audio.play_sfx("explosion", -2.0, 0.05, 120)
		"volley":
			Audio.play_sfx("shoot_pea", -3.0, 0.06, 120)
		"hero_down":
			Audio.play_sfx("tree_hurt", 0.0, 0.03, 250)
		"revive", "potion":
			Audio.play_sfx("powerup", -2.0, 0.04, 200)
		"item_bought":
			Audio.play_sfx("upgrade", -2.0, 0.03, 150)
		"rival_spawn":
			Audio.play_sfx("boss_warn", -2.0, 0.03, 500)


func _update_fx(dt: float) -> void:
	if _anim.has("tree_hurt"):
		_anim.tree_hurt = maxf(0.0, _anim.tree_hurt - dt)
	for k in _bubbles.keys():
		_bubbles[k].life -= dt
		if _bubbles[k].life <= 0:
			_bubbles.erase(k)
	for f in _fx:
		f.life -= dt
	_fx = _fx.filter(func(f): return f.life > 0)
	for p in _parts:
		p.life -= dt
		p.v.y += p.g * dt
		if p.has("drag"):
			p.v *= maxf(0.0, 1.0 - p.drag * dt)
		p.p += p.v * dt
	_parts = _parts.filter(func(p): return p.life > 0)
	for f in _floats:
		f.life -= dt
		f.p.y -= 30 * dt
	_floats = _floats.filter(func(f): return f.life > 0)
	if _parts.size() > 1500:
		_parts = _parts.slice(_parts.size() - 1500)


func draw_fx() -> void:
	for f in _fx:
		var k: float = 1.0 - f.life / f.max
		match f.kind:
			"ring":
				var r: float = f.r * (0.15 + 0.85 * (1.0 - pow(1.0 - k, 3)))
				var c: Color = f.col
				c.a = 1.0 - k
				draw_arc(f.p, r, 0, TAU, 48, c, f.w * (1 - k) + 1, true)
			"flash":
				var c: Color = f.col
				c.a = 0.45 * (1 - k)
				draw_circle(f.p, f.r, c)
			"bolt":
				var c: Color = f.col
				c.a = 1 - k
				var jag := PackedVector2Array()
				for i in f.pts.size() - 1:
					var a: Vector2 = f.pts[i]
					var b: Vector2 = f.pts[i + 1]
					jag.append(a)
					var n := (b - a).orthogonal().normalized()
					for s in [0.33, 0.66]:
						jag.append(a.lerp(b, s) + n * (randf() - 0.5) * 18)
				jag.append(f.pts[f.pts.size() - 1])
				draw_polyline(jag, Color(1, 1, 1, c.a), 2, true)
				draw_polyline(jag, Color(c.r, c.g, c.b, c.a * 0.6), 6, true)
			"beam":
				var c: Color = f.col
				c.a = 1 - k
				draw_line(f.a, f.b, Color(c.r, c.g, c.b, c.a * 0.4), 16 * (1 - k * 0.5), true)
				draw_line(f.a, f.b, Color(1, 1, 1, c.a), 3, true)
			"pillar":
				var c: Color = f.col
				c.a = 0.35 * (1 - k)
				draw_rect(Rect2(f.p.x - 22, f.p.y - 200 * (0.4 + k), 44, 200 * (0.4 + k) + 20), c)
			"swipe":
				var c: Color = f.col
				c.a = 1 - k
				draw_arc(f.p, 46, f.a - 1.0, f.a + 1.0, 16, c, 6 * (1 - k) + 1, true)
			"warn":
				var c: Color = f.col
				c.a = 0.4 + sin(time * 18) * 0.25
				ellipse_line(f.p, f.r, f.r * 0.6, c, 3)
				ellipse(f.p, f.r * k, f.r * 0.6 * k, Color(c.r, c.g, c.b, 0.12))
	for p in _parts:
		var c: Color = p.col
		c.a = clampf(p.life / p.max, 0, 1)
		draw_circle(p.p, p.size * (0.5 + 0.5 * c.a), c)
	for f in _floats:
		var c: Color = f.col
		c.a = clampf(f.life / f.max * 1.5, 0, 1)
		text(f.p, f.s, f.size, c, 4)


# ---------------------------------------------------------------------------
# Garden Clash
# ---------------------------------------------------------------------------
const SHOT_STYLE := {"pea": ["86efac", 5], "pumpkin": ["fb923c", 8], "bloom": ["fde047", 7], "treebolt": ["fef08a", 9],
	"sting": ["facc15", 5], "bigsting": ["fb923c", 8], "spore": ["bef264", 7], "thorn": ["e879f9", 7],
	"heartbolt": ["f0abfc", 10], "shell": ["cbd5e1", 8], "spit": ["93c5fd", 7]}
## where each building's health bar sits, and how big its shield dome is
const BUILDING_LOOK := {"tower": [-98.0, 70.0, 56.0], "guardian": [-112.0, 80.0, 62.0], "gate": [-92.0, 74.0, 58.0],
	"thorntower": [-98.0, 70.0, 56.0], "thornguard": [-112.0, 80.0, 62.0], "thorngate": [-92.0, 74.0, 58.0], "thornheart": [-120.0, 130.0, 92.0]}


func draw_fountain() -> void:
	var sc: Vector2 = GameData.sanctuary(_map_id)
	var r: float = GameData.clash.config.fountainRadius
	var n := 48
	for i in n:
		if i % 2 == 0:
			var a0 := TAU * i / n + time * 0.08
			draw_arc(sc, r, a0, a0 + TAU / n, 4, Color(0.22, 0.74, 0.97, 0.45), 2.5, true)


func shield_bubble(c: Vector2, r: float, col: Color) -> void:
	var pulse := 0.5 + sin(time * 3) * 0.5
	draw_circle(c, r, Color(col.r, col.g, col.b, 0.12 + pulse * 0.06))
	var n := 28
	for i in n:
		if i % 2 == 0:
			var a0 := TAU * i / n + time * 0.6
			draw_arc(c, r, a0, a0 + TAU / n, 4, Color(col.r, col.g, col.b, 0.55 + pulse * 0.3), 2, true)


func _building(kind: String, pos: Vector2, hp_k: float, flash: bool, mod := Color.WHITE) -> void:
	var e: Dictionary = Sprites.atlas.get("structures", {}).get(kind, {})
	if e.is_empty():
		return
	var ph := int(time * 4 + pos.x * 0.01) % 6
	var frame := (ph if ph < 4 else 6 - ph) + (4 if hp_k < 0.5 else 0)
	Sprites.draw_frame(self, Sprites.tex(e.file), e, frame, pos, false, 1.0, Color(1.7, 1.7, 1.7) if flash else mod, Sprites.scale)


func draw_bloom_tower(t: Dictionary) -> void:
	var pos := Vector2(t.x, t.y)
	var k: float = float(t.hp) / maxf(1.0, t.maxHp)
	_building(t.kind, pos, k, t.get("flash", false))
	var look: Array = BUILDING_LOOK.get(t.kind, [-98.0, 70.0, 56.0])
	if t.get("shield", false):
		shield_bubble(pos - Vector2(0, 34), look[2], Color(0.49, 0.83, 0.99))
	bar(pos + Vector2(0, look[0]), look[1], 7, k, Color("38bdf8"))


func draw_foe_building(e: Dictionary, def: Dictionary) -> void:
	var pos := pos_of(e.id, Vector2(e.x, e.y))
	var k: float = float(e.hp) / maxf(1.0, e.maxHp)
	_building(e.type, pos, k, e.get("flash", false))
	var look: Array = BUILDING_LOOK.get(e.type, [-98.0, 70.0, 56.0])
	if e.sheltered:
		shield_bubble(pos - Vector2(0, 26 if def.get("core", false) else 34), look[2], Color(0.77, 0.71, 0.99))
	bar(pos + Vector2(0, look[0]), look[1], 9 if def.get("core", false) else 7, k, Color("e879f9") if def.get("core", false) else Color("f43f5e"))


func draw_ally(u: Dictionary) -> void:
	var entry := Sprites.pest_entry(u.kind)
	if entry.is_empty():
		return
	var p := pos_of(u.id, Vector2(u.x, u.y))
	var a: Dictionary = _anim.get("a%d" % u.id, {})
	if a.is_empty():
		a = {"phase": randf(), "face": 1, "lx": p.x}
		_anim["a%d" % u.id] = a
	if absf(p.x - a.lx) > 0.3:
		a.face = 1 if p.x > a.lx else -1
	a.lx = p.x
	a.phase += get_process_delta_time() * 1.8
	var def: Dictionary = GameData.clash.allies.get(u.kind, {})
	var S := 1.3 if u.get("big", false) else 1.0
	var R: float = float(def.get("radius", 16)) * S
	var feet := p + Vector2(0, R * 0.75)
	ellipse(feet, R * 0.95, R * 0.32, Color(0, 0, 0, 0.25))
	ellipse_line(feet, R * 1.05, R * 0.38, Color(0.22, 0.74, 0.97, 0.8), 2.5)
	if u.get("big", false):
		draw_circle(p - Vector2(0, R * 0.3), R * 1.5, Color(0.29, 0.87, 0.5, 0.16))
	var frame := int(fposmod(a.phase, 1.0) * 8) % 8
	Sprites.draw_frame(self, Sprites.tex(entry.file), entry, frame, feet, a.face < 0, S, Color(1.7, 1.7, 1.7) if u.get("flash", false) else Color.WHITE, Sprites.scale)
	if u.hp < u.maxHp:
		bar(Vector2(p.x, feet.y - R * 2.1 - 6), maxf(22.0, R * 1.7), 4, float(u.hp) / float(u.maxHp), Color("38bdf8"))


func draw_knocked_out(h: Dictionary, p: Vector2) -> void:
	var entry := Sprites.hero_entry(h.type)
	var t := Sprites.hero_tex(h.type, mini(h.tierA, 4), mini(h.tierB, 4))
	ellipse(p + Vector2(0, 21), 22, 8, Color(0, 0, 0, 0.3))
	Sprites.draw_frame(self, t, entry, 0, p + Vector2(0, 21), false, 0.9, Color(0.55, 0.6, 0.65, 0.5), Sprites.scale)
	var col: Color = GameData.player_color(h.slot)
	ellipse_line(p + Vector2(0, 21), float(GameData.clash.config.reviveRadius), float(GameData.clash.config.reviveRadius) * 0.45, Color(col.r, col.g, col.b, 0.5), 2)
	var rv: float = h.get("revive", 0.0)
	if rv > 0:
		draw_arc(p - Vector2(0, 20), 40, -PI / 2, -PI / 2 + TAU * rv, 40, Color("86efac"), 6, true)
	text(Vector2(p.x, p.y - 70), "💫 %ds" % ceili(float(h.get("respawnT", 0))), 16, Color.WHITE, 4)


func draw_camps(clash: Dictionary) -> void:
	for c in clash.get("camps", []):
		if c.up or int(c.respawn) <= 0:
			continue
		var def: Dictionary = GameData.ENEMIES.get(c.kind, {})
		var s := "%s%s back in %ds" % ["Elder " if c.get("elder", false) else "", def.get("name", ""), int(c.respawn)]
		text(Vector2(c.x, c.y + 4), s, 12, Color(1, 1, 1, 0.85), 3)


func draw_clash_shots(clash: Dictionary) -> void:
	var k := clampf(tick_alpha, 0, 1.2) / 30.0
	for s in clash.get("shots", []):
		var at := Vector2(s.x + s.vx * k, s.y + s.vy * k)
		var st: Array = SHOT_STYLE.get(s.kind, ["ffffff", 5])
		var c := Color(st[0])
		var r: float = st[1]
		var dir := Vector2(s.vx, s.vy).normalized()
		draw_line(at - dir * r * 3, at, Color(c.r, c.g, c.b, 0.4), r * 1.1, true)
		draw_circle(at, r * 2.2, Color(c.r, c.g, c.b, 0.2))
		if s.kind == "thorn":
			var n := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([at + dir * 10, at - dir * 7 + n * 5, at - dir * 4, at - dir * 7 - n * 5]), Color("c084fc"))
		elif s.kind == "sting" or s.kind == "bigsting":
			var m := 1.6 if s.kind == "bigsting" else 1.0
			var n := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([at + dir * 12 * m, at + n * 3 * m, at - dir * 7 * m, at - n * 3 * m]), Color("facc15"))
			draw_line(at - dir * 2 * m + n * 3 * m, at - dir * 2 * m - n * 3 * m, Color("1c1917"), 2 * m)
		else:
			draw_circle(at, r * 0.75, c)
			draw_circle(at - Vector2(r, r) * 0.2, r * 0.28, Color(1, 1, 1, 0.8))


# ---------------------------------------------------------------------------
# Tower help: my nearest tower's upgrade/sell prompt, and range on hover
# ---------------------------------------------------------------------------
func _tower_range(g: Dictionary) -> float:
	var def: Dictionary = GameData.GADGETS.get(g.kind, {})
	return GameData.gnum(GameData.gadget_branch(g.kind, int(g.branch)), "range", GameData.gnum(def, "range", 100))


func _draw_tower_help() -> void:
	if snap.has("clash") or snap.get("phase", "") != "playing":
		return
	var mouse := get_global_mouse_position()
	for g in snap.get("gadgets", []):
		if Vector2(g.x, g.y).distance_to(mouse) < 34:
			var col: Color = GameData.player_color(g.slot)
			draw_arc(Vector2(g.x, g.y), _tower_range(g), 0, TAU, 64, Color(col.r, col.g, col.b, 0.7), 2, true)
	if my_pos == null:
		return
	var near := {}
	var bd := 110.0
	for g in snap.get("gadgets", []):
		if g.owner != my_owner:
			continue
		var d := Vector2(g.x, g.y).distance_to(my_pos)
		if d <= bd:
			bd = d
			near = g
	if near.is_empty():
		return
	var gp := Vector2(near.x, near.y)
	var def: Dictionary = GameData.GADGETS[near.kind]
	draw_arc(gp, _tower_range(near), 0, TAU, 64, Color(0.99, 0.88, 0.28, 0.55), 2, true)
	draw_arc(gp + Vector2(0, 6), 30, 0, TAU, 32, Color("fde047"), 3, true)
	var acorns := 0
	for p in snap.get("players", []):
		if p.id == my_owner:
			acorns = int(p.acorns)
	var lv := "Lv %d%s" % [int(near.level), "" if int(near.branch) < 0 else ("A" if int(near.branch) == 0 else "B")]
	var up := ""
	if def.get("once", false):
		up = ""
	elif int(near.level) >= 3:
		up = "max level"
	else:
		var cost := GameData.gadget_upgrade_cost(near.kind, int(near.level))
		up = ("U/Y pick a power %d🌰" if int(near.level) == 2 and def.has("branches") else "U upgrade %d🌰") % cost
		if acorns < cost:
			up += " (need more)"
	var line := "%s %s · %s%sX sell +%d🌰" % [def.icon, lv, up, " · " if up != "" else "", int(floor(float(near.spent) * 0.6))]
	text(gp + Vector2(0, -92), line, 13, Color("fef9c3"), 4)
