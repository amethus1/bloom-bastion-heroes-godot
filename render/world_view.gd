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
var ghost_at = null  # where the mouse aims it (null: at my hero's feet)
var picked_tower := -1  # the tower picked in "Your towers": ringed, with its range showing

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
var shake_mult := 1.0  # settings: screen shake 100% / 50% / off
var pings: Array = []  # {p, kind, slot, name, t}
var _emotes := {}  # owner -> {icon, text, t}
const PING_LOOK := {"look": ["👀", "Look here!"], "chest": ["🎁", "Chest!"], "powerup": ["✨", "Power-up!"], "wake": ["💤", "Wake this tower!"],
	"pests": ["🐛", "Pests here!"], "rival": ["👑", "Rival!"], "tower": ["🌵", "Attack this!"]}
var dmg_mode := "all"  # settings: damage numbers all / big / off
var snap_dt := 1.0 / 30.0  # time between snapshots: 1/30 s here, about 1/20 s on a LAN friend's computer
var _marker := {"p": Vector2.ZERO, "t": 0.0}
const SLIDE_TIME := 0.14
var _slide := Vector2.ZERO  # my hero's dash: how far behind its new spot it's still drawn
var _slide_t := 0.0
var fancy := true  # settings: Graphics "fancy" (cloud shadows, shimmering water, glowing light) or "simple"
var lights: Node2D  # glows and sparks, drawn with additive blending on top of the world
var _ground_mat: ShaderMaterial
var _snap_cam := true  # jump the camera straight to the hero (new game) instead of gliding across the map
var _tags: Array = []  # name tags placed this frame (so two heroes' tags don't overlap)
var _lit_shots: Array = []  # [where, colour, size] of every shot drawn this frame, for its glow


## Draws WorldView's light on its own canvas item, so it can use additive blending
class LightLayer extends Node2D:
	var world: WorldView

	func _draw() -> void:
		world.draw_lights(self)


func zoom_by(k: float) -> void:
	overview = false
	zoom = clampf(zoom * k, 0.6, 1.8)


func toggle_overview() -> void:
	overview = not overview
	var vp := get_viewport_rect().size
	zoom = minf(vp.x / GameData.W, vp.y / GameData.H) if overview else 1.0


## My hero leapt: its real spot jumps at once (so walking and building stay exact),
## but draw it zipping there over a moment instead of blinking across
func slide_from(from: Vector2, to: Vector2) -> void:
	if from.distance_to(to) < 500:
		_slide = from - to
		_slide_t = SLIDE_TIME


## Where to draw my own hero (my_pos plus what's left of a dash slide)
func _me():
	if my_pos == null or _slide_t <= 0:
		return my_pos
	var k := _slide_t / SLIDE_TIME
	return my_pos + _slide * (k * k)


func click_marker(p: Vector2) -> void:
	_marker = {"p": p, "t": 0.6}


func _ready() -> void:
	_font = UiKit.font()
	shapes_tex()
	map_sprite = Sprite2D.new()
	map_sprite.centered = false
	map_sprite.z_index = -10
	add_child(map_sprite)
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://render/ground.gdshader")
	_ground_mat.set_shader_parameter("noise", noise_tex())
	_ground_mat.set_shader_parameter("world_size", Vector2(GameData.W, GameData.H))
	lights = LightLayer.new()
	lights.world = self
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	lights.material = add
	add_child(lights)
	set_fancy(fancy)
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


## Graphics setting: "fancy" adds cloud shadows, shimmering water and glowing
## light; "simple" is lighter work for an old computer
func set_fancy(on: bool) -> void:
	fancy = on
	if map_sprite:
		map_sprite.material = _ground_mat if on else null
	if lights:
		lights.visible = on


static var _noise: Texture2D


## Soft seamless noise (clouds and water ripples), made once
static func noise_tex() -> Texture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.011
		fn.fractal_octaves = 3
		fn.seed = 7
		var img := fn.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


## Forget everything from the previous game (ids start over in a new game)
func reset() -> void:
	_snap_cam = true
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
	remote_interp = false
	_slide_t = 0.0
	_hist = []
	_play_t = -1.0
	_ha = {}
	_hb = {}


func _on_dialog_line(_speaker: String, msg: String, owner_id: int, duration: float) -> void:
	if not mute_audio and owner_id >= 0 and msg != "":
		_bubbles[owner_id] = {"text": msg, "life": duration, "max": duration}


var _prune_t := 0

## LAN friends: snapshots come about 20 times a second, never quite evenly over
## Wi-Fi. Blending only the last two stutters whenever one is late, so keep a
## short history stamped with game time and show everyone else ~2 snapshots in
## the past, sliding between whichever two snapshots surround that moment.
var remote_interp := false
var _hist: Array = []  # [game time, {id: Vector2}]
var _play_t := -1.0
var _ha := {}
var _hb := {}
var _hk := 1.0
var _hi := 0


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
		for g in s.get("gadgets", []):
			live["g%d" % g.id] = true
		for k in _anim.keys():
			if String(k).length() > 1 and String(k)[0] in ["e", "h", "a", "g"] and String(k).substr(1).is_valid_int() and not live.has(k):
				_anim.erase(k)
	_prev = _cur
	_cur = {}
	for list in ["heroes", "enemies", "wisps"]:
		for e in s.get(list, []):
			_cur[e.id] = Vector2(e.x, e.y)
	for u in s.get("clash", {}).get("allies", []):
		_cur[u.id] = Vector2(u.x, u.y)
	if remote_interp:
		for pr in s.get("projectiles", []):
			_cur[pr.id] = Vector2(pr.x, pr.y)
		var t := float(s.get("time", 0.0))
		if not _hist.is_empty() and (t < float(_hist[-1][0]) - 0.001 or s.get("map", "") != snap.get("map", "")):
			_hist.clear()  # a new game started
			_play_t = -1.0
		if _hist.is_empty() or t > float(_hist[-1][0]) + 0.0001:
			_hist.append([t, _cur])
		else:
			_hist[-1] = [t, _cur]  # same moment (paused): keep the newest
		while _hist.size() > 16:
			_hist.pop_front()
	if not snap.is_empty() and s.get("map", "") == snap.get("map", "") and int(s.get("lives", 0)) > int(snap.get("lives", 0)) and not s.has("clash"):
		var sc0: Vector2 = GameData.sanctuary(s.map)
		burst(sc0 - Vector2(0, 80), ["f9a8d4", "fbcfe8", "fde047", "ffffff"], 30, 200)
		float_text(sc0 - Vector2(0, 170), "🌸 +%d" % (int(s.lives) - int(snap.lives)), Color("f9a8d4"), 18, 1.2)
	snap = s
	if s.get("map", "") != _map_id:
		_map_id = s.map
		map_sprite.texture = Sprites.tex(Sprites.atlas.maps.get(_map_id, ""))
		_water = null
		if AMBIENT.get(_map_id, "") == "sparkle":
			_water = _water_map(map_sprite.texture)
	for e in s.get("events", []):
		on_event(e)


func pos_of(id: int, fallback: Vector2) -> Vector2:
	if remote_interp and not _ha.is_empty():
		var hp = _hist_pos(id)
		return hp if hp != null else _cur.get(id, fallback)
	var c: Vector2 = _cur.get(id, fallback)
	var p: Vector2 = _prev.get(id, c)
	return p.lerp(c, clampf(tick_alpha, 0.0, 1.0))


## Where `id` was at the moment being shown (LAN friends). Something that only
## appeared after that moment waits where it first showed up (or, with
## `early` off, isn't shown yet: null).
func _hist_pos(id: int, early := true):
	var a = _ha.get(id)
	var b = _hb.get(id)
	if a != null and b != null:
		return (a as Vector2).lerp(b, _hk)
	if b != null:
		return b
	if a != null:
		return a
	if early:
		for j in range(_hi + 2, _hist.size()):
			if _hist[j][1].has(id):
				return _hist[j][1][id]
	return null


## Move the shown moment along smoothly, keeping it ~2 snapshots behind the newest
func _update_interp(delta: float) -> void:
	if not remote_interp or _hist.size() < 2:
		_ha = {}
		return
	var latest: float = _hist[-1][0]
	var spd: float = 0.0 if snap.get("paused", false) else float(snap.get("speed", 1.0))
	var delay := clampf(snap_dt * 2.2, 0.07, 0.25) * maxf(spd, 1.0)
	var target := latest - delay
	if _play_t < 0 or absf(_play_t - target) > 0.6 * maxf(spd, 1.0):
		_play_t = target  # far off (just joined, or a long hiccup): jump straight there
	elif spd > 0:
		_play_t += delta * spd
		_play_t += (target - _play_t) * minf(1.0, delta * 2.0)  # ease toward the target, no jumps
	_play_t = clampf(_play_t, float(_hist[0][0]), latest)
	var i := _hist.size() - 2
	while i > 0 and float(_hist[i][0]) > _play_t:
		i -= 1
	_hi = i
	_ha = _hist[i][1]
	_hb = _hist[i + 1][1]
	_hk = clampf((_play_t - float(_hist[i][0])) / maxf(float(_hist[i + 1][0]) - float(_hist[i][0]), 0.0001), 0.0, 1.0)


func _process(delta: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(delta)
	PerfStats.add("world update" , Time.get_ticks_usec() - _pt0)


func _process_inner(delta: float) -> void:
	time += delta
	_update_interp(delta)
	_slide_t = maxf(0.0, _slide_t - delta)
	if shake > 0:
		shake = maxf(0.0, shake - delta * 30.0)
		camera.offset = Vector2(randf() - 0.5, randf() - 0.5) * shake * 1.5 * shake_mult
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
	if _snap_cam and (my_pos != null or _has_hero(my_owner)):
		# a new game: start right on my hero (no swoop across the map from where the last one ended)
		_snap_cam = false
		camera.zoom = Vector2(want_zoom, want_zoom)
		camera.reset_smoothing()
	if _marker.t > 0:
		_marker.t -= delta
	_update_fx(delta)
	_update_ambient(delta)
	queue_redraw()
	if lights.visible:
		lights.queue_redraw()  # after the world, so it lights up this frame's shots


func _has_hero(owner: int) -> bool:
	for h in snap.get("heroes", []):
		if h.owner == owner:
			return true
	return false


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------
## One small texture holds a solid disc, a soft glow, two rings and a white
## square. Every dot, shadow, ring, glow, bar and trail is drawn as a piece of it,
## so the GPU can draw hundreds of them in one go (plain circles cost one draw
## call each, which got slow with hundreds of pests on screen).
const SH_DISC := Rect2(0, 0, 64, 64)  # disc of radius 30
const SH_SOFT := Rect2(64, 0, 64, 64)  # glow fading out to radius 31
const SH_RING := Rect2(128, 0, 64, 64)  # thin ring at radius 28.5
const SH_RING2 := Rect2(192, 0, 64, 64)  # thicker ring (for small circles)
const SH_DOT := Rect2(256, 0, 16, 16)  # disc of radius 7 (sharper when tiny)
const SH_WHITE := Rect2(258, 26, 4, 4)
static var _shapes: Texture2D


static func shapes_tex() -> Texture2D:
	if _shapes == null:
		var img := Image.create(288, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		for y in 64:
			for x in 64:
				var d := Vector2(x + 0.5 - 32, y + 0.5 - 32).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(30.5 - d, 0, 1)))
				var g := clampf(1.0 - d / 31.0, 0, 1)
				img.set_pixel(64 + x, y, Color(1, 1, 1, g * g))
				img.set_pixel(128 + x, y, Color(1, 1, 1, clampf(2.6 - absf(d - 28.5), 0, 1)))
				img.set_pixel(192 + x, y, Color(1, 1, 1, clampf(4.6 - absf(d - 26.5), 0, 1)))
		for y in 16:
			for x in 16:
				var d := Vector2(x + 0.5 - 8, y + 0.5 - 8).length()
				img.set_pixel(256 + x, y, Color(1, 1, 1, clampf(7.5 - d, 0, 1)))
		img.fill_rect(Rect2i(256, 24, 8, 8), Color.WHITE)
		_shapes = ImageTexture.create_from_image(img)
	return _shapes


func disc(c: Vector2, r: float, col: Color) -> void:
	if r <= 6.0:
		var h := r * 8.0 / 7.0
		draw_texture_rect_region(_shapes, Rect2(c.x - h, c.y - h, h * 2, h * 2), SH_DOT, col)
	else:
		var h := r * 32.0 / 30.0
		draw_texture_rect_region(_shapes, Rect2(c.x - h, c.y - h, h * 2, h * 2), SH_DISC, col)


func glow(c: Vector2, r: float, col: Color) -> void:
	var h := r * 32.0 / 31.0
	draw_texture_rect_region(_shapes, Rect2(c.x - h, c.y - h, h * 2, h * 2), SH_SOFT, col)


func ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var hx := rx * 32.0 / 30.0
	var hy := ry * 32.0 / 30.0
	draw_texture_rect_region(_shapes, Rect2(c.x - hx, c.y - hy, hx * 2, hy * 2), SH_DISC, col)


func ellipse_line(c: Vector2, rx: float, ry: float, col: Color, w := 2.0) -> void:
	if maxf(rx, ry) > 64.0:
		draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 40, col, w / maxf(ry / maxf(rx, 0.01), 0.3), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var thick := minf(rx, ry) < 16.0
	var k := 32.0 / (26.5 if thick else 28.5)
	draw_texture_rect_region(_shapes, Rect2(c.x - rx * k, c.y - ry * k, rx * k * 2, ry * k * 2), SH_RING2 if thick else SH_RING, col)


## A thick line drawn as a stretched oval (soft rounded ends, batches with the rest)
func streak(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	var L := d.length() + w
	draw_set_transform((a + b) / 2, d.angle(), Vector2.ONE)
	draw_texture_rect_region(_shapes, Rect2(-L / 2, -w / 2, L, w), SH_DISC, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A straight line as a thin white bar (batches with the rest)
func seg(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	draw_set_transform(a, d.angle(), Vector2.ONE)
	draw_texture_rect_region(_shapes, Rect2(0, -w / 2, d.length(), w), SH_WHITE, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func box(r: Rect2, col: Color) -> void:
	draw_texture_rect_region(_shapes, r, SH_WHITE, col)



var _defer_text := false
var _text_queue: Array = []


func text(pos: Vector2, s: String, size := 14, col := Color.WHITE, outline := 3) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w / 2.0, 0)
	if _defer_text:
		_text_queue.append([p, s, size, col, outline])
		return
	if outline > 0:
		draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.7 * col.a))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Draw queued text: every outline first, then every letter (fewer GPU switches)
func _flush_text() -> void:
	_defer_text = false
	for q in _text_queue:
		if q[4] > 0:
			draw_string_outline(_font, q[0], q[1], HORIZONTAL_ALIGNMENT_LEFT, -1, q[2], q[4], Color(0, 0, 0, 0.7 * q[3].a))
	for q in _text_queue:
		draw_string(_font, q[0], q[1], HORIZONTAL_ALIGNMENT_LEFT, -1, q[2], q[3])
	_text_queue.clear()


## A health bar; `trail` (if more than k) shows in pale what was just lost
func bar(c: Vector2, w: float, h: float, k: float, col: Color, trail := -1.0) -> void:
	box(Rect2(c.x - w / 2 - 1.5, c.y - 1.5, w + 3, h + 3), Color(0.06, 0.09, 0.16, 0.85))
	if trail > k + 0.01:
		box(Rect2(c.x - w / 2, c.y, w * clampf(trail, 0, 1), h), Color(1, 0.96, 0.86, 0.8))
	box(Rect2(c.x - w / 2, c.y, maxf(2.0, w * clampf(k, 0, 1)), h), col)


# ---------------------------------------------------------------------------
# Main draw
# ---------------------------------------------------------------------------
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_world()
	PerfStats.add("world draw", Time.get_ticks_usec() - t0)


func _draw_world() -> void:
	if snap.is_empty():
		return
	_tags.clear()
	var heroes: Array = snap.get("heroes", [])
	var clash: Dictionary = snap.get("clash", {})
	if not clash.is_empty():
		draw_fountain()
	# my range ring
	for h in heroes:
		if h.owner == my_owner and not h.get("dead", false):
			var p: Vector2 = _me() if my_pos != null else pos_of(h.id, Vector2(h.x, h.y))
			var col: Color = GameData.player_color(h.slot)
			col.a = 0.4
			ellipse_line(p, h.range, h.range, col, 2.0)
	if _marker.t > 0:
		var k: float = _marker.t / 0.6
		ellipse_line(_marker.p, 18 * (1.4 - k * 0.4), 9 * (1.4 - k * 0.4), Color(1, 1, 1, k * 0.8), 2.5)
	_draw_features()
	if not clash.is_empty():
		draw_plots(clash)
		draw_flags(clash)
		_draw_raid(clash)
	for s in snap.get("spikes", []):
		_draw_shot(2, Vector2(s.x, s.y - 2), Vector2.UP, 8.0, GameData.player_color(s.slot).lightened(0.35))
	# depth-sorted things (anything well off screen is skipped)
	var vr := _view_rect().grow(160)
	var list: Array = []
	var sc: Vector2 = GameData.sanctuary(_map_id)
	list.append([sc.y + 20, "tree", null, sc])
	for g in snap.get("gadgets", []):
		if vr.has_point(Vector2(g.x, g.y)):
			list.append([g.y, "gadget", g, null])
	var foes: Array = []
	for e in snap.get("enemies", []):
		var p := pos_of(e.id, Vector2(e.x, e.y))
		if vr.has_point(p) or e.boss:
			list.append([p.y + (30 if e.boss else 0), "enemy", e, p])
			foes.append([e, p])
	for h in heroes:
		var p: Vector2 = _me() if h.owner == my_owner and my_pos != null else pos_of(h.id, Vector2(h.x, h.y))
		list.append([p.y + 4, "hero", h, p])
	for c in snap.get("chests", []):
		if vr.has_point(Vector2(c.x, c.y)):
			list.append([c.y, "chest", c, null])
	for pu in snap.get("powerups", []):
		if vr.has_point(Vector2(pu.x, pu.y)):
			list.append([pu.y, "powerup", pu, null])
	for t in clash.get("allyTowers", []):
		if t.kind != "tree" and t.hp > 0:
			list.append([t.y, "bloom", t, null])
	for u in clash.get("allies", []):
		var p := pos_of(u.id, Vector2(u.x, u.y))
		if vr.has_point(p):
			list.append([p.y, "ally", u, p])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for f in foes:
		draw_enemy_ground(f[0], f[1])
	for it in list:
		match it[1]:
			"tree": draw_tree(it[3])
			"gadget": draw_gadget(it[2])
			"enemy": draw_enemy(it[2], it[3])
			"hero": draw_hero(it[2])
			"chest": draw_chest(it[2])
			"powerup": draw_powerup(it[2])
			"bloom": draw_bloom_tower(it[2])
			"ally": draw_ally(it[2])
	_defer_text = true
	for f in foes:
		draw_enemy_over(f[0], f[1])
	_flush_text()
	if not clash.is_empty():
		_draw_tower_locks()
	for w in snap.get("wisps", []):
		var p := pos_of(w.id, Vector2(w.x, w.y))
		glow(p, 12, Color(1, 0.6, 0.2, 0.6))
		_draw_shot(8, p, Vector2.UP, 5.0)
	draw_projectiles()
	if not clash.is_empty():
		draw_camps(clash)
		draw_clash_shots(clash)
	for s in snap.get("suns", []):
		var e: Dictionary = Sprites.atlas.get("sun", {})
		Sprites.draw_frame(self, Sprites.tex(e.get("file", "")), e, 0, Vector2(s.x, s.y + sin(time * 3 + s.x) * 3), false, 1.0, Color.WHITE, Sprites.scale)
		text(Vector2(s.x, s.y + 19), "+%d" % int(s.amount), 11, Color("ffe7a0"), 2)
	draw_fx()
	_draw_ambient()
	_draw_pings()
	_draw_combo_ring()
	if ghost != "" and my_pos != null:
		# where the selected tower would go, with its real (round) range
		var gp: Vector2 = ghost_at if ghost_at != null else my_pos
		if ghost_at != null:
			ellipse_line(_me(), SimWorld.AIM_REACH, SimWorld.AIM_REACH, Color(1, 1, 1, 0.18), 2.0)  # how far from my hero I can build
		var def: Dictionary = GameData.GADGETS[ghost]
		var out := build_outcome(ghost, gp)
		var sp: Vector2 = out.at
		var col := Color(0.5, 1, 0.6, 0.55) if out.ok else Color(1, 0.4, 0.4, 0.55)
		var why: String = out.text
		if out.ok:
			why = ("Click or F: " if ghost_at != null else "F: ") + why
		if not out.up.is_empty():
			# it would upgrade the tower that's already here, not build a new one
			var up := Vector2(out.up.x, out.up.y)
			draw_arc(up + Vector2(0, 6), 34, 0, TAU, 32, Color(0.99, 0.88, 0.28, 0.9) if out.ok else Color(1, 0.45, 0.45, 0.8), 3, true)
			draw_arc(up, _tower_range(out.up), 0, TAU, 64, Color(0.99, 0.88, 0.28, 0.5), 2, true)
			sp = up
		else:
			disc(sp, def.range, Color(col.r, col.g, col.b, 0.1))
			draw_arc(sp, def.range, 0, TAU, 64, col, 2, true)
			var gt := Sprites.gadget_tex(ghost, 1, -1, 0)
			Sprites.draw_frame(self, gt, Sprites.atlas.gadgets.get(ghost, {}), 0, sp, false, 1.0, Color(1, 1, 1, 0.55) if out.ok else Color(1, 0.5, 0.5, 0.45), Sprites.scale)
		text(sp + Vector2(0, 34), why, 13, Color("bbf7d0") if out.ok else Color("fca5a5"), 4)
	_draw_tower_help()


## A friend just used their special and mine is ready: the circle to stand in for a
## Team Combo, its edge running down like a timer
func _draw_combo_ring() -> void:
	var co: Dictionary = snap.get("comboOpen", {})
	if co.is_empty() or int(co.owner) == my_owner:
		return
	var me := {}
	var friend := {}
	for h in snap.get("heroes", []):
		if h.owner == my_owner:
			me = h
		if int(h.id) == int(co.hero):
			friend = h
	if me.is_empty() or friend.is_empty() or float(me.get("specialCd", 1.0)) > 0.05 or me.get("dead", false):
		return
	var c := Vector2(co.x, co.y)
	var col: Color = GameData.player_color(int(friend.slot))
	var k := clampf(float(co.left) / SimWorld.COMBO_TIME, 0.0, 1.0)
	disc(c, SimWorld.COMBO_REACH, Color(col.r, col.g, col.b, 0.05 + 0.03 * sin(time * 9.0)))
	draw_arc(c, SimWorld.COMBO_REACH, -PI / 2, -PI / 2 + TAU * k, 96, Color(col.r, col.g, col.b, 0.75), 4, true)


## What F (or a click) would really do here, checked in the same order the game
## checks it, so the preview never promises something else:
## {"ok", "text", "at": where it goes, "up": the tower it would upgrade instead ({} if none)}
func build_outcome(kind: String, gp: Vector2) -> Dictionary:
	var def: Dictionary = GameData.GADGETS[kind]
	var spot: Dictionary = GameData.gadget_spot(_map_id, kind, gp.x, gp.y)
	var at := Vector2(spot.x, spot.y)
	var acorns := 0
	for p in snap.get("players", []):
		if p.id == my_owner:
			acorns = int(p.acorns)
	var res := {"ok": false, "text": "", "at": at, "up": {}}
	if snap.get("mutators", []).has("heroes") and not def.get("once", false):
		res.text = "Hero Mode: no towers this game"
		return res
	var mine: Array = snap.get("gadgets", []).filter(func(g): return g.owner == my_owner)
	for g in mine:
		if g.kind == kind and not def.get("once", false) and Vector2(g.x, g.y).distance_to(at) < 60:
			res.up = g
			if int(g.level) >= 3:
				res.text = "This %s is already max level" % def.name
				return res
			var cost := GameData.gadget_upgrade_cost(kind, int(g.level))
			var what := "Pick a special power for this %s" % def.name if int(g.level) == 2 and def.has("branches") else "Upgrade this %s to level %d" % [def.name, int(g.level) + 1]
			res.ok = acorns >= cost
			res.text = ("⬆ %s · %d🌰" % [what, cost]) if res.ok else ("⬆ %s needs %d🌰 (you have %d)" % [what, cost, acorns])
			return res
	if not spot.ok:
		res.text = String(spot.get("reason", "Can't build here"))
		return res
	for g in snap.get("gadgets", []):
		if Vector2(g.x, g.y).distance_to(at) < 46:
			res.text = "Something is already built here. Move a little!"
			return res
	var cap := int(GameData.gadgets.limitPerPlayer)
	if mine.size() >= cap:
		res.text = "Tower limit reached · %d/%d (upgrade or sell one)" % [mine.size(), cap]
		return res
	if acorns < int(def.cost):
		res.text = "%s needs %d🌰 (you have %d)" % [def.name, int(def.cost), acorns]
		return res
	res.ok = true
	res.text = "Build %s · %d🌰" % [def.name, int(def.cost)]
	return res


func draw_tree(sc: Vector2) -> void:
	var e: Dictionary = Sprites.atlas.get("tree", {})
	var k := clampf(float(snap.lives) / maxf(1.0, float(snap.maxLives)), 0, 1)
	var hurt: float = _anim.get("tree_hurt", 0.0)
	var mod := Color(1, 1 - hurt * 0.5, 1 - hurt * 0.5) if hurt > 0 else (Color.WHITE if k > 0.35 else Color(1, 0.75, 0.75))
	mod.a = _see_through("tree", sc, 100.0, 150.0, sc.y + 20)
	var off := Vector2(sin(time * 60) * hurt * 6, 0)
	Sprites.draw_frame(self, Sprites.tex(e.get("file", "")), e, int(time * 2) % 4, sc + off, false, 1.0, mod, Sprites.scale)
	# a hurt tree drops petals
	if not snap.has("clash") and k < 0.5 and randf() < get_process_delta_time() * (2.0 + (0.5 - k) * 14.0):
		_parts.append({"p": sc + Vector2((randf() - 0.5) * 90, -120 + randf() * 40), "v": Vector2(18 + randf() * 20, 30), "life": 2.2, "max": 2.2, "size": 3.5, "col": Color("f9a8d4"), "g": 25.0})
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
	# pop up when built, bounce when upgraded
	var key := "g%d" % g.id
	var look := "%s/%s" % [g.level, g.branch]
	var an: Dictionary = _anim.get(key, {})
	if an.is_empty():
		an = {"t": time, "look": look, "new": true}
		_anim[key] = an
	elif an.look != look:
		an.merge({"t": time, "look": look, "new": false}, true)
	var shots := int(g.get("shots", 0))
	if an.has("shots") and int(an.shots) != shots:
		an.fire = time
	an.shots = shots
	var k := clampf((time - float(an.t)) / 0.35, 0.0, 1.0)
	var st := Vector2.ONE
	if k < 1.0:
		var sy := _ease_back(k) if an.new else 1.0 + 0.2 * sin(k * PI) * (1.0 - k)
		st = Vector2(1.0 + (1.0 - sy) * 0.6, sy)
	else:
		# firing: a quick squash down and a springy bounce back
		var fk := (time - float(an.get("fire", -9.0))) / 0.3
		if fk < 1.0:
			var sy := 1.0 - 0.13 * (1.0 - fk) * cos(fk * 7.0)
			st = Vector2(1.0 + (1.0 - sy) * 0.7, sy)
	# plants sway a little in the breeze (not while asleep)
	var sway := 0.0 if g.get("asleep", false) or g.kind == "bomb" else sin(time * 1.7 + g.x * 0.013) * 0.035
	Sprites.draw_frame(self, t, e, 0, Vector2(g.x, g.y), false, 1.0, mod, Sprites.scale, st, sway)
	if g.kind == "fern":
		var r: float = GameData.GADGETS.fern.range
		var B: Dictionary = GameData.gadget_branch("fern", g.branch)
		r = GameData.gnum(B, "range", r)
		var ph := fmod(time * 0.8 + g.x * 0.003, 1.0)
		draw_arc(Vector2(g.x, g.y), r * (0.4 + ph * 0.6), 0, TAU, 48, Color(0.49, 0.83, 0.99, 0.35 * (1 - ph)), 2, true)
	if g.get("asleep", false):
		text(Vector2(g.x + 10, g.y - 60 - fmod(time * 20, 20)), "z", 16, Color("e0e7ff"))


## 0 -> 1 with a little overshoot at the end (things popping into place)
static func _ease_back(k: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)


## Turn to face where it's walking, using its smoothed sideways speed so tiny
## wobbles (rounding, walking almost straight up or down) don't flip the picture
## back and forth every frame. `quick` is how fast it reacts (heroes turn faster).
static func face_toward(a: Dictionary, x: float, dt: float, quick: float) -> void:
	a.vx = lerpf(float(a.get("vx", 0.0)), (x - float(a.lx)) / maxf(dt, 0.001), minf(1.0, dt * quick))
	if a.vx > 6:
		a.face = 1
	elif a.vx < -6:
		a.face = -1
	a.lx = x


const FLYERS := ["wasp", "zeppelin", "dreadblimp", "camopuff", "mothmedic", "snoozemoth"]


## Each pest is drawn in three layers, each layer for every pest at once:
## ground (shadow, rings at its feet, auras), body (the sprite) and overlay
## (health bar, status pips, badges). Same-looking pieces in a row draw much faster.
func _enemy_anim(e: Dictionary, p: Vector2) -> Dictionary:
	var a: Dictionary = _anim.get("e%d" % e.id, {})
	if a.is_empty():
		a = {"phase": randf(), "face": 1, "lx": p.x, "vx": 0.0, "hit": 0.0, "born": time}
		_anim["e%d" % e.id] = a
	return a


func draw_enemy_ground(e: Dictionary, p: Vector2) -> void:
	var def: Dictionary = GameData.ENEMIES.get(e.type, {})
	if def.get("structure", false) or e.burrowed:
		return
	var S := 1.35 if e.big else 1.0
	var R: float = def.radius * S
	var flyer: bool = def.get("art", e.type) in FLYERS
	var feet := p + Vector2(0, R * 0.75)
	var a := _enemy_anim(e, p)
	var grow := clampf((time - float(a.born)) / 0.25, 0.0, 1.0)
	ellipse(feet, R * (0.7 if flyer else 0.95) * grow, R * (0.25 if flyer else 0.32) * grow, Color(0, 0, 0, 0.18 if flyer else 0.28))
	if def.get("minion", false) or def.get("rival", false):
		ellipse_line(feet, R * 1.05, R * 0.38, Color(0.96, 0.25, 0.37, 0.75), 2.5)
	if e.slowed and not e.frozen:
		ellipse_line(feet, R * 1.05, R * 0.38, Color(0.49, 0.83, 0.99, 0.5), 2)
	if e.get("sunlit", false):
		ellipse_line(feet, R * 1.05, R * 0.4, Color(0.99, 0.88, 0.28, 0.6), 2)
	if def.has("sleepDust"):
		ellipse_line(feet, float(def.sleepDust), float(def.sleepDust) * 0.6, Color(0.77, 0.71, 0.99, 0.3 + 0.15 * sin(time * 3)), 2)
	if e.get("casting", false):
		glow(p - Vector2(0, R * 0.4), R * 1.9, Color(0.94, 0.27, 0.27, 0.3 + 0.15 * sin(time * 20)))
	if e.get("enraged", false):
		var pulse := 0.5 + 0.5 * sin(time * 9)
		glow(p - Vector2(0, R * 0.3), R * (1.5 + 0.1 * pulse), Color(0.94, 0.27, 0.27, 0.3 + 0.15 * pulse))


func draw_enemy(e: Dictionary, p: Vector2) -> void:
	var def: Dictionary = GameData.ENEMIES.get(e.type, {})
	if def.get("structure", false):
		draw_foe_building(e, def)
		return
	var entry := Sprites.pest_entry(e.type)
	if entry.is_empty():
		return
	var a := _enemy_anim(e, p)
	var dt := maxf(get_process_delta_time(), 0.001)
	face_toward(a, p.x, dt, 8.0)
	if not e.frozen and not e.stunned and not e.get("trapped", false):
		a.phase += dt * (0.9 if e.slowed else 1.8) * (0.6 if e.boss else 1.0)
	var S := 1.35 if e.big else 1.0
	var R: float = def.radius * S
	var flyer: bool = def.get("art", e.type) in FLYERS
	var feet := p + Vector2(0, R * 0.75)
	if e.burrowed:
		ellipse(feet, R * 1.05, R * 0.32, Color(0, 0, 0, 0.22))
		ellipse(p + Vector2(0, R * 0.2), R * 1.05, R * 0.5, Color("8a5a1e"))
		disc(p - Vector2(0, R * 0.3), R * 0.4, Color("facc15"))
		if randf() < dt * 12:
			_parts.append({"p": p + Vector2((randf() - 0.5) * R * 1.6, 0), "v": Vector2((randf() - 0.5) * 70, -60 - randf() * 50), "life": 0.5, "max": 0.5, "size": 3.0, "col": Color("a16207") if randf() < 0.5 else Color("78350f"), "g": 300.0})
		return
	var alpha := 1.0
	if e.camo:
		alpha = 0.45 + sin(time * 4 + p.x) * 0.12
	if e.sheltered:
		alpha *= 0.55
	# new pests pop in: a quick fade and grow instead of appearing out of nowhere
	var born := clampf((time - float(a.born)) / 0.25, 0.0, 1.0)
	alpha *= born
	var mod := Color(1, 1, 1, alpha)
	if entry.has("tint"):
		mod = Color(float(entry.tint[0]), float(entry.tint[1]), float(entry.tint[2]), alpha)
	if e.flash:
		mod = Color(1.8, 1.8, 1.8, alpha)
	var frame := int(fposmod(a.phase, 1.0) * 8) % 8
	# a solid hit squashes it for a moment (then it springs back)
	if e.flash and not a.get("flashed", false):
		a.hit = 1.0
	a.flashed = e.flash
	a.hit = maxf(0.0, float(a.hit) - dt * 6.0)
	var squash := Vector2.ONE
	if a.hit > 0:
		var q: float = a.hit * a.hit * (0.5 if e.boss else 1.0)
		squash = Vector2(1.0 + 0.16 * q, 1.0 - 0.14 * q)
	Sprites.draw_frame(self, Sprites.tex(entry.file), entry, frame, feet, a.face < 0, S * (0.6 + 0.4 * ease(born, 0.5)), mod, Sprites.scale, squash)
	if e.frozen:
		var top := feet.y - (R * 2.6 if flyer else R * 2.0)
		var cy := (top + feet.y) / 2
		var hw := R * 1.15
		var hh := (feet.y - top) / 2 + 4
		var ice := PackedVector2Array([Vector2(p.x, cy - hh), Vector2(p.x + hw, cy - hh * 0.45), Vector2(p.x + hw * 0.9, cy + hh * 0.6),
			Vector2(p.x, cy + hh), Vector2(p.x - hw * 0.9, cy + hh * 0.6), Vector2(p.x - hw, cy - hh * 0.45)])
		draw_colored_polygon(ice, Color(0.75, 0.9, 1.0, 0.5))
		ice.append(ice[0])
		draw_polyline(ice, Color(1, 1, 1, 0.85), 2)
	if e.get("enraged", false) and randf() < dt * 10:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.6, p.y - R * 0.2), "v": Vector2(0, -60), "life": 0.7, "max": 0.7, "size": 5.0, "col": Color("7f1d1d"), "g": 0.0})
	if e.get("frostbit", false) and randf() < dt * 10:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.5), "v": Vector2(0, 30), "life": 0.5, "max": 0.5, "size": 3.0, "col": Color("bae6fd"), "g": 60.0})
	if e.burning and randf() < dt * 14:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.6), "v": Vector2(0, -50), "life": 0.45, "max": 0.45, "size": 4.0, "col": Color("fb923c"), "g": 0.0})
	if e.get("soaked", false) and randf() < dt * 8:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.4), "v": Vector2(0, 40), "life": 0.5, "max": 0.5, "size": 2.4, "col": Color("60a5fa"), "g": 120.0})
	if e.get("poisoned", false) and randf() < dt * 7:
		_parts.append({"p": Vector2(p.x + (randf() - 0.5) * R * 1.4, p.y - R * 0.2), "v": Vector2(0, -28), "life": 0.55, "max": 0.55, "size": 3.0, "col": Color("a3e635"), "g": 0.0})


## A pest someone right-clicked: a turning gold crosshair
func _draw_mark(p: Vector2, R: float) -> void:
	var c := p + Vector2(0, -R * 0.4)
	var rr := R * 1.2 + 8 + sin(time * 6) * 2
	ellipse_line(c, rr, rr, Color(1, 0.85, 0.2, 0.9), 2.5)
	for k in 4:
		var a := time * 1.5 + k * TAU / 4
		var d := Vector2(cos(a), sin(a))
		seg(c + d * (rr - 6), c + d * (rr + 8), 3.0, Color(1, 0.35, 0.2, 0.95))


func draw_enemy_over(e: Dictionary, p: Vector2) -> void:
	var def: Dictionary = GameData.ENEMIES.get(e.type, {})
	if e.get("marked", false):
		_draw_mark(p, float(def.get("radius", 20)) * (1.35 if e.get("big", false) else 1.0))
	if def.get("structure", false) or e.burrowed:
		return
	var S := 1.35 if e.big else 1.0
	var R: float = def.radius * S
	if e.type == "thorntoad":
		# thorny back
		var tc := p + Vector2(0, R * 0.15)
		for k in 6:
			var ta := deg_to_rad(-150.0 + k * 24.0)
			var dv := Vector2(cos(ta), sin(ta) * 0.8)
			seg(tc + dv * R * 0.7, tc + dv * (R * 0.7 + 13.0), 5.0, Color("3f2a12"))
			seg(tc + dv * (R * 0.7 + 6.0), tc + dv * (R * 0.7 + 13.0), 2.5, Color("d9f99d"))
	var flyer: bool = def.get("art", e.type) in FLYERS
	var feet := p + Vector2(0, R * 0.75)
	var top := feet.y - (R * 2.6 if flyer else R * 2.0)
	if e.get("trapped", false):
		var br := R * 1.45
		var by := p.y - R * 0.5 + sin(time * 4 + p.x) * 3
		disc(Vector2(p.x, by), br, Color(0.58, 0.77, 0.99, 0.25))
		ellipse_line(Vector2(p.x, by), br, br, Color(1, 1, 1, 0.85), 2.0)
	if e.stunned:
		for k in 3:
			var ang := time * 6 + k * TAU / 3
			disc(Vector2(p.x + cos(ang) * R * 0.8, top - 4 + sin(ang) * 4), 3.5, Color("fde047"))
	if e.get("resist", "") != "":
		var rs: Dictionary = GameData.RESISTS.get(e.resist, {})
		var bc := Vector2(p.x - R * 0.95, top + 8)
		disc(bc, 9, Color(0.06, 0.09, 0.16, 0.85))
		ellipse_line(bc, 9, 9, Color(rs.get("color", "#ffffff")), 2.0)
		text(bc + Vector2(0, 4), String(rs.get("icon", "")), 10, Color.WHITE, 0)
	# little coloured pips: soaked, sunlit, frostbite, poisoned, bubble-trapped
	var n := 0
	for pip in [["soaked", "60a5fa"], ["sunlit", "fde047"], ["frostbit", "e0f2fe"], ["poisoned", "a3e635"], ["trapped", "c4b5fd"], ["sapped", "f59e0b"], ["guarded", "4d7c0f"]]:
		if e.get(pip[0], false):
			var pc := Vector2(p.x + R * 0.95 - n * 9, top + 8)
			disc(pc, 4.5, Color(0.06, 0.09, 0.16, 0.85))
			disc(pc, 3.2, Color(pip[1]))
			n += 1
	# Healer Moth: green tethers to the pests it's healing
	if def.has("heals"):
		for o in snap.get("enemies", []):
			if o.id != e.id and o.hp < o.maxHp and not GameData.ENEMIES.get(o.type, {}).get("boss", false) and Vector2(o.x, o.y).distance_to(p) <= float(def.healRadius):
				seg(p, pos_of(o.id, Vector2(o.x, o.y)), 2.0, Color(0.53, 0.94, 0.67, 0.35 + 0.2 * sin(time * 6)))
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
		# the bar slides down, leaving a pale strip of what was just lost
		var a: Dictionary = _anim.get("e%d" % e.id, {})
		var dt := get_process_delta_time()
		var hk: float = a.get("hpk", 1.0)
		hk = k if k > hk else lerpf(hk, k, minf(1.0, dt * 14.0))  # healing jumps up, damage slides down
		a.hpk = hk
		a.hpt = maxf(lerpf(float(a.get("hpt", 1.0)), k, minf(1.0, dt * 2.2)), hk)
		bar(Vector2(p.x, top - 8), maxf(26.0, R * 1.8), 5, hk, col, a.hpt)


func draw_hero(h: Dictionary) -> void:
	var mine: bool = h.owner == my_owner and my_pos != null
	var p: Vector2 = _me() if mine else pos_of(h.id, Vector2(h.x, h.y))
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
	face_toward(a, p.x, dt, 25.0)
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
		disc(p, 46, Color(0.99, 0.88, 0.28, 0.18))
	if GameData.gnum(h.buffs, "frenzy") > 0:
		disc(p - Vector2(0, 14), 40, Color(0.98, 0.45, 0.09, 0.18))
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
	var look := "%s%d%d" % [h.type, h.tierA, h.tierB]
	if a.get("look", "") != look:
		# get its next evolutions loading now, so evolving never stutters
		a.look = look
		var vars: Dictionary = entry.get("variants", {})
		Sprites.prefetch(String(vars.get("%d%d" % [mini(h.tierA + 1, 4), mini(h.tierB, 4)], "")))
		Sprites.prefetch(String(vars.get("%d%d" % [mini(h.tierA, 4), mini(h.tierB + 1, 4)], "")))
	var feet := p + Vector2(0, 21)
	var hurt_mod := Color(1.8, 0.6, 0.6) if h.get("hurt", false) else Color.WHITE
	Sprites.draw_frame(self, t, entry, frame, feet, face < 0, lv_scale, hurt_mod, Sprites.scale)
	var hat: String = h.get("hat", "none")
	if hat != "none" and Sprites.atlas.hats.has(hat):
		var anchor: Array = Sprites.atlas.hatAnchor.get(h.type, [0, -55, 1])
		var offset := Sprites.hero_hat_offset(h.type, mini(h.tierA, 4), mini(h.tierB, 4), frame)
		var hp := feet + Vector2(offset.x * face, offset.y) * lv_scale
		Sprites.draw_frame(self, Sprites.tex(Sprites.atlas.hats[hat].file), Sprites.atlas.hats[hat], 0, hp, face < 0, anchor[2] * lv_scale, Color.WHITE, Sprites.scale)
	if h.dazed:
		for k in 3:
			var ang := time * 7 + k * TAU / 3
			disc(Vector2(p.x + cos(ang) * 16, p.y - 66 + sin(ang) * 5), 4, Color("d9f99d"))
	# name tag
	var pl := _player(h.owner)
	var name: String = ("[bot] " if pl.get("bot", false) else "") + String(pl.get("name", "Hero"))
	var ty := p.y - 64 - (lv_scale - 1.1) * 60
	var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34
	# heroes standing together: stack their name tags instead of piling them up
	var tag := Rect2(p.x - tw / 2, ty - 10, tw, 20)
	for i in 4:
		var clear := true
		for r in _tags:
			if (r as Rect2).intersects(tag):
				clear = false
				break
		if clear:
			break
		ty -= 23
		tag.position.y -= 23
	_tags.append(tag)
	draw_rect(Rect2(p.x - tw / 2, ty - 10, tw, 20), Color(0.04, 0.08, 0.05, 0.75))
	draw_rect(Rect2(p.x - tw / 2, ty - 10, tw, 20), col, false, 1.6)
	disc(Vector2(p.x - tw / 2 + 10, ty), 8, Color("facc15"))
	text(Vector2(p.x - tw / 2 + 10, ty + 4.5), str(h.level), 11, Color("422006"), 0)
	text(Vector2(p.x + 10, ty + 4.5), name, 13)
	if h.pending > 0:
		disc(Vector2(p.x + tw / 2 + 9, ty + sin(time * 6) * 3), 7, Color("fde047"))
	if _emotes.has(int(h.owner)):
		var em: Dictionary = _emotes[int(h.owner)]
		var ea: float = clampf(em.t / 0.4, 0, 1)
		var label: String = em.icon + ("  " + em.text if em.text != "" else "")
		var bw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 22
		var by := ty - 52
		draw_style_box(UiKit.box(Color(1, 1, 1, 0.95 * ea), Color(col.r, col.g, col.b, ea), 12, 2, 0), Rect2(p.x - bw / 2, by - 16, bw, 30))
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - 7, by + 13), Vector2(p.x + 7, by + 13), Vector2(p.x, by + 22)]), Color(1, 1, 1, 0.95 * ea))
		text(Vector2(p.x, by + 5), label, 16, Color(0.1, 0.12, 0.1, ea), 0)
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


const SHOTS := preload("res://art/world/shots.png")
const SHOT_FRAMES := {"pea": 0, "megapea": 1, "thorn": 2, "needle": 3, "icicle": 4,
	"snowball": 5, "bomb": 6, "cluster": 6, "rocket": 7, "ember": 8, "sunseed": 9, "bubble": 10}
const CLASH_SHOT_FRAMES := {"pea": 0, "pumpkin": 11, "bloom": 9, "treebolt": 1,
	"sting": 9, "bigsting": 1, "spore": 0, "thorn": 3, "heartbolt": 6, "shell": 11, "spit": 10}


func _draw_shot(frame: int, at: Vector2, velocity: Vector2, radius: float, mod := Color.WHITE) -> void:
	var diameter := radius * 2.8
	draw_set_transform(at, velocity.angle(), Vector2.ONE)
	draw_texture_rect_region(SHOTS, Rect2(-diameter / 2.0, -diameter / 2.0, diameter, diameter),
		Rect2(frame * 64, 0, 64, 64), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_projectiles() -> void:
	_lit_shots.clear()
	var vr := _view_rect().grow(30)
	var k := clampf(tick_alpha, 0, 1.2) * snap_dt
	var lan := remote_interp and not _ha.is_empty()
	for p in snap.get("projectiles", []):
		var at := Vector2(p.x + p.vx * k, p.y + p.vy * k)
		if lan:
			var hp = _hist_pos(p.id, false)
			if hp == null:
				continue  # fired after the moment being shown
			at = hp
		if not vr.has_point(at):
			continue
		var col := Color(PROJ_COLORS.get(p.kind, "ffffff"))
		var r := 6.0
		match p.kind:
			"megapea", "bomb", "rocket": r = 10.0
			"bubble": r = 8.0
			"needle", "thorn": r = 4.0
		var back := at - Vector2(p.vx, p.vy).normalized() * r * 2.2
		streak(back, at, r * 1.2, Color(col.r, col.g, col.b, 0.45))
		if fancy:
			_lit_shots.append([at, col, r])
		else:
			glow(at, r * 2.2, Color(col.r, col.g, col.b, 0.35))
		_draw_shot(SHOT_FRAMES.get(p.kind, 0), at, Vector2(p.vx, p.vy), r)


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


## Bits flying out from a spot. `lit` ones glow a little (sparks; not dirt or dust).
func burst(pos: Vector2, cols: Array, n: int, speed: float, lit := true) -> void:
	for i in n:
		var ang := randf() * TAU
		var sp := speed * (0.4 + randf() * 0.6)
		_parts.append({"p": pos, "v": Vector2(cos(ang), sin(ang)) * sp, "life": 0.6, "max": 0.6, "size": 3.0 + randf() * 2.5, "col": Color(cols[randi() % cols.size()]), "g": 200.0, "lit": lit})


## A pest popping: a soft cloud of puffs and a few twinkling stars
func poof(pos: Vector2, R: float, big: bool) -> void:
	var n := 9 if big else 5
	for i in n:
		var ang := TAU * i / n + randf() * 0.6
		var d := Vector2(cos(ang), sin(ang) * 0.6)
		_parts.append({"p": pos + d * R * 0.35, "v": d * (40.0 + randf() * 50.0) * (1.6 if big else 1.0) + Vector2(0, -25), "drag": 3.0, "g": -30.0,
			"life": 0.55, "max": 0.55, "size": R * 0.45, "grow": R * (0.9 if big else 0.7), "col": Color(1, 1, 1, 0.7)})
	for i in (6 if big else 3):
		var ang := randf() * TAU
		_parts.append({"p": pos + Vector2(cos(ang), sin(ang)) * R * 0.5, "v": Vector2(cos(ang), sin(ang) - 0.8) * (60.0 + randf() * 60.0), "drag": 2.0, "g": 40.0,
			"life": 0.6, "max": 0.6, "size": 5.0 + randf() * 3.0, "star": true, "col": Color("fef9c3")})


## Words and numbers that pop up, rise quickly, slow down and fade
func float_text(pos: Vector2, s: String, col: Color, size := 16, life := 1.0, drift := 0.0) -> void:
	_floats.append({"p": pos, "s": s, "col": col, "size": size, "life": life, "max": life, "v": Vector2(drift, -34.0 / life - 62.0)})


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
		"echo":
			var eb := Vector2(float(e.get("x2", pos.x)), float(e.get("y2", pos.y)))
			_fx.append({"kind": "beam", "a": pos, "b": eb, "col": Color("c4b5fd"), "life": 0.22, "max": 0.22})
			ring(eb, 20, Color("ddd6fe"), 3, 0.25)
		"mark":
			ring(pos, 40, Color("fbbf24"), 4, 0.35)
		"gift":
			if float(e.get("x", 0)) > 0:
				float_text(pos - Vector2(0, 64), "🎁 +%d 🌰" % int(e.get("amount", 0)), Color("fde68a"), 16, 1.3)
				burst(pos - Vector2(0, 40), ["fde68a", "f59e0b", "ffffff"], 12, 120)
		"pot_grow":
			burst(pos - Vector2(0, 30), ["f9a8d4", "fde047", "86efac"], 8, 90)
			if int(e.get("owner", -1)) == my_owner:
				float_text(pos - Vector2(0, 58), "+%d 🌰" % int(e.get("acorns", 0)), Color("fcd34d"), 14, 0.9)
		"sap":
			ring(pos, float(e.get("radius", 70)), Color("f59e0b"), 4, 0.4)
		"toad_stomp":
			ring(pos, float(e.get("r", 170)), Color("a3e635"), 8, 0.5)
			ring(pos, float(e.get("r", 170)) * 0.6, Color("65a30d"), 5, 0.4)
			shake = maxf(shake, 7)
			burst(pos + Vector2(0, 20), ["a16207", "78350f", "65a30d"], 18, 200, false)
		"gust":
			var gr := float(e.get("radius", 170))
			ring(pos, gr, Color(0.9, 0.97, 1.0, 0.9), 6, 0.45)
			for i in 14:
				var ang := TAU * i / 14.0 + randf() * 0.3
				_parts.append({"p": pos + Vector2(cos(ang), sin(ang)) * 20, "v": Vector2(cos(ang), sin(ang)) * gr * 2.2, "drag": 2.6, "life": 0.5, "max": 0.5,
					"size": 5.0 + randf() * 4, "col": Color(0.88, 0.96, 1.0, 0.8), "g": 0.0})
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
			if not e.get("structure", false) and not Sprites.pest_entry(String(e.get("kind", ""))).is_empty():
				var an: Dictionary = _anim.get("e%d" % int(e.get("id", -1)), {})
				var def: Dictionary = GameData.ENEMIES.get(String(e.kind), {})
				var at := pos_of(int(e.get("id", -1)), pos) if e.has("id") else pos
				_fx.append({"kind": "ghost", "p": at + Vector2(0, float(def.get("radius", 14)) * 0.75), "type": String(e.kind),
					"face": int(an.get("face", 1)), "frame": int(fposmod(float(an.get("phase", 0.0)), 1.0) * 8) % 8, "life": 0.2, "max": 0.2})
			burst(pos, [e.get("color", "#a3e635"), "#ffffff"], 40 if e.boss else 12, 260 if e.boss else 130)
			ring(pos, 110 if e.boss else 26, Color.WHITE, 3, 0.25)
			if not e.get("structure", false):
				poof(pos, float(GameData.ENEMIES.get(String(e.get("kind", "")), {}).get("radius", 16)), bool(e.boss))
			if e.boss:
				shake = maxf(shake, 12)
		"sun_collected":
			float_text(pos - Vector2(0, 10), "+%d XP" % int(e.amount), Color("fde047"), 17)
			ring(pos, 34, Color("fde047"), 3, 0.3)
		"dmg":
			if dmg_mode == "off" or (dmg_mode == "big" and not e.get("crit", false) and float(e.amount) < 200):
				return
			float_text(pos + Vector2((randf() - 0.5) * 14, 0), ("%d!" % int(e.amount)) if e.crit else str(int(e.amount)), Color("fde047") if e.crit else Color.WHITE, 18 if e.crit else 12, 0.7, (randf() - 0.5) * 70)
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
			var perk_cols: Array = {"frostlotus": ["bae6fd", "e0f2fe", "ffffff"], "snapdragon": ["fb923c", "f97316", "fde047"], "bubblelily": ["93c5fd", "60a5fa", "ffffff"],
				"voltcactus": ["c084fc", "e9d5ff", "fde047"], "boomshroom": ["fb7185", "fde047", "f97316"], "sunblossom": ["fde047", "facc15", "ffffff"]}.get(String(e.get("perk", "")), ["86efac", "4ade80", "ffffff"])
			burst(pos, perk_cols, 16, 150)
			if String(e.get("perk", "")) in ["snapdragon", "bubblelily", "voltcactus", "boomshroom"]:
				ring(pos, 110 if e.perk != "boomshroom" else 80, Color(perk_cols[0]), 4, 0.35)
		"spring":
			# the Spring Vine flings a hero down the lane
			burst(pos, ["86efac", "4ade80", "bbf7d0"], 14, 170)
			ring(pos, 60, Color("86efac"), 4, 0.35)
			float_text(pos - Vector2(0, 50), "BOING!", Color("bbf7d0"), 16, 0.9)
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
			var named := String(e.get("id", "")) != ""
			var cc: String = {"cryo": "bae6fd", "storm": "c084fc", "flare": "fb923c", "hail": "e0f2fe", "thunderboom": "fde047",
				"glacier": "7dd3fc", "firecracker": "f472b6", "sunny": "fde047"}.get(String(e.get("id", "")), "f0abfc")
			float_text(pos - Vector2(0, 40), String(e.get("name", "TEAM COMBO!")), Color(cc), 26 if named else 24, 1.8)
			ring(pos, 330, Color(cc), 10, 0.7)
			if named:
				ring(pos, 200, Color.WHITE, 6, 0.5)
				burst(pos, [cc, "ffffff", "fde047"], 50, 320)
			shake = maxf(shake, 12 if named else 10)
		"chest_open":
			burst(pos, ["fde047", "f472b6", "60a5fa", "4ade80"], 40, 260)
		"powerup_get":
			ring(pos, 60, Color("fde047"), 4, 0.4)
		"gadget_placed", "gadget_upgraded":
			_fx.append({"kind": "pillar", "p": pos, "col": Color("facc15"), "life": 0.6, "max": 0.6})
		"gadget_boom":
			shake = maxf(shake, 5)
		"feature":
			match String(e.kind):
				"sunflower":
					burst(pos - Vector2(0, 20), ["fde047", "facc15", "ffffff"], 18, 160)
					Audio.play_sfx("sun_pickup", -2.0, 0.05, 200)
				"lilypad":
					ring(pos, 50, Color("86efac"), 4, 0.4)
					float_text(pos - Vector2(0, 50), "💨 Speedy!", Color("bbf7d0"), 14, 1.0)
					Audio.play_sfx("dash", -3.0, 0.05, 200)
				"obelisk":
					_fx.append({"kind": "flash", "p": pos, "r": e.r, "col": Color("c4b5fd"), "life": 0.4, "max": 0.4})
					ring(pos, e.r, Color("a78bfa"), 10, 0.7)
					burst(pos - Vector2(0, 60), ["e9d5ff", "a78bfa", "ffffff"], 50, 340)
					float_text(pos - Vector2(0, 110), "✨ STARLIGHT BLAST!", Color("e9d5ff"), 20, 1.6)
					shake = maxf(shake, 9)
					Audio.play_sfx("thunder", 0.0, 0.03, 300)
				"leafpile":
					ring(pos, e.r, Color("fb923c"), 4, 0.5)
					burst(pos, ["ea580c", "f59e0b", "b45309", "dc2626"], 30, 200, false)
					Audio.play_sfx("sleep_dust", -3.0, 0.05, 200)
				"geyser":
					ring(pos, e.r, Color("bae6fd"), 6, 0.5)
					for i in 24:
						var ang := randf() * TAU
						_parts.append({"p": pos, "v": Vector2(cos(ang) * 60, -180 - randf() * 120), "life": 0.9, "max": 0.9, "size": 4.0 + randf() * 3, "col": Color("e0f2fe"), "g": 260.0})
					Audio.play_sfx("shoot_frost", -3.0, 0.05, 200)
		"sun_heal":
			ring(pos, 120, Color("fde047"), 6, 0.6)
			_fx.append({"kind": "pillar", "p": pos, "col": Color("fef08a"), "life": 0.9, "max": 0.9})
			float_text(pos - Vector2(0, 80), "☀️ Healing sunbeam!" if e.get("clash", false) else "☀️ +1 Bloom Tree life", Color("fde047"), 16, 1.4)
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
			burst(pos, ["8a5a1e", "a16207", "facc15"], 10, 120, false)
		"emote":
			var em := {}
			for x in GameData.cosmetics.emotes:
				if x.id == e.id:
					em = x
			if not em.is_empty():
				_emotes[int(e.owner)] = {"icon": em.icon, "text": em.text, "t": 2.6}
			Audio.play_sfx("ui_click", -2.0, 0.1, 60)
		"ping":
			pings.append({"p": pos, "kind": String(e.kind), "slot": int(e.slot), "name": String(e.get("name", "")), "t": 4.0})
			if pings.size() > 8:
				pings.pop_front()
			Audio.play_sfx("card_pick", -2.0, 0.05, 150)
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
			burst(pos, ["a16207", "78350f", "fde68a"], 24, 220, false)
			shake = maxf(shake, 7)
		"volley_warn":
			_fx.append({"kind": "beam", "a": pos, "b": Vector2(e.tx, e.ty), "col": Color("f87171"), "life": 0.35, "max": 0.35})
		"volley":
			ring(pos, 40, Color("facc15"), 4, 0.3)
		"rival_swipe":
			_fx.append({"kind": "swipe", "p": pos, "a": atan2(float(e.ty) - pos.y, float(e.tx) - pos.x), "col": Color("fde68a"), "life": 0.22, "max": 0.22})
		"hero_down":
			burst(pos, ["9ca3af", "e5e7eb", "ffffff"], 24, 200, false)
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
	var pos := Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	var has_pos := e.has("x") and e.has("y")
	var owner_id := int(e.get("owner", -999))
	var mine: bool = owner_id == my_owner or owner_id == -999
	var play_pos := func(id: String, db := 0.0, jit := 0.07, cd := 55) -> void:
		if has_pos:
			Audio.play_sfx_at(id, pos, mine, db, jit, cd)
		else:
			Audio.play_sfx(id, db, jit, cd)
	match String(e.get("type", "")):
		"shot":
			match String(e.get("kind", "")):
				"pea": play_pos.call("shoot_pea", -9.0, 0.08, 70)
				"boom": play_pos.call("shoot_boom", -5.0, 0.06, 100)
				"bubble": play_pos.call("shoot_bubble", -7.0, 0.08, 85)
		"explosion":
			play_pos.call("explosion", -4.0, 0.08, 70)
		"gust":
			play_pos.call("dash", -3.0, 0.1, 150)
		"toad_stomp":
			play_pos.call("slam_hit", -2.0, 0.05, 300)
		"sap":
			play_pos.call("bubble_trap", -9.0, 0.1, 300)
		"pot_grow":
			play_pos.call("sun_pickup", -10.0, 0.1, 400)
		"echo":
			play_pos.call("shoot_bubble", -10.0, 0.1, 120)
		"nova":
			var nc := String(e.get("color", "")).to_upper()
			if nc == "#FDE047":
				play_pos.call("nova_sun", -4.0, 0.06, 140)
			elif nc == "#C084FC":
				play_pos.call("nova_shock", -4.0, 0.08, 110)
			else:
				play_pos.call("shoot_frost", -5.0, 0.08, 120)
		"lightning":
			play_pos.call("shoot_zap", -4.0, 0.09, 80)
		"thunder":
			play_pos.call("thunder", -2.0, 0.06, 110)
		"beam":
			var bpos := Vector2(float(e.get("x1", pos.x)), float(e.get("y1", pos.y)))
			Audio.play_sfx_at("shoot_beam", bpos, mine, -4.0, 0.06, 90)
		"snipe":
			play_pos.call("snipe", -3.0, 0.05, 90)
		"solar_beam":
			play_pos.call("solar_beam", -2.0, 0.04, 150)
		"flame":
			play_pos.call("shoot_flame", -6.0, 0.08, 140)
		"enemy_pop":
			if e.get("boss", false):
				Audio.play_sfx("pop_boss", 0.0, 0.02, 200)
			else:
				play_pos.call("pop_small", -5.0, 0.10, 65)
		"sun_collected":
			play_pos.call("sun_pickup", -3.0, 0.06, 90)
		"level_up":
			Audio.play_sfx("level_up", -1.0, 0.02, 200)
		"special":
			play_pos.call("special_cast", -1.0, 0.04, 150)
			if e.has("heroType"):
				Audio.say_hero(String(e.heroType), "special", owner_id)
		"leak", "tree_hit":
			Audio.play_sfx("tree_hurt", -1.0, 0.04, 180)
		"reaction":
			var kind := String(e.get("kind", ""))
			if not kind.begins_with("resist_") and kind != "sunlit":
				play_pos.call("react_" + kind, -2.0, 0.05, 140)
		"dash":
			play_pos.call("dash", -2.0, 0.07, 100)
		"teleport", "hero_respawn":
			play_pos.call("teleport", -2.0, 0.04, 200)
		"lily_wave", "tidal":
			play_pos.call("shoot_bubble", -2.0, 0.05, 140)
		"bubble_trap":
			play_pos.call("bubble_trap", -2.0, 0.05, 160)
		"spring_life":
			Audio.play_sfx("spring_life", -1.0, 0.03, 300)
		"mole_down":
			play_pos.call("mole_down", -4.0, 0.07, 160)
		"mole_up":
			play_pos.call("mole_up", -3.0, 0.07, 160)
		"hero_dazed":
			play_pos.call("dazed", -2.0, 0.04, 250)
		"combo":
			Audio.play_sfx("team_combo", 1.0, 0.0, 400)
			Audio.say("ann_combo", -1, true)
		"chest_drop":
			play_pos.call("chest_drop", -2.0, 0.04, 150)
		"chest_open":
			Audio.play_sfx("chest_open", 0.0, 0.02, 200)
		"powerup_get":
			play_pos.call("powerup", -1.0, 0.03, 150)
		"gadget_placed":
			play_pos.call("build", -2.0, 0.05, 100)
		"gadget_upgraded":
			play_pos.call("upgrade", -1.0, 0.04, 120)
		"gadget_sold":
			play_pos.call("sell", -2.0, 0.04, 120)
		"gadget_boom":
			play_pos.call("gadget_boom", 0.0, 0.05, 100)
		"gadget_wake":
			play_pos.call("gadget_wake", -2.0, 0.04, 250)
			if mine:
				Audio.say("coop_wake", owner_id)
		"sleep_dust":
			play_pos.call("sleep_dust", -3.0, 0.04, 400)
		"boss_enrage":
			Audio.play_sfx("boss_warn", 0.0, 0.02, 500)
			Audio.say("boss_enrage", -1, true)
		"struct_down":
			Audio.play_sfx("struct_down", 0.0, 0.03, 200)
		"tower_fire":
			play_pos.call("clash_tower_fire", -7.0, 0.08, 120)
		"slam_warn":
			play_pos.call("slam_warn", -2.0, 0.04, 200)
		"slam":
			play_pos.call("slam_hit", -1.0, 0.05, 150)
		"volley":
			play_pos.call("shoot_pea", -3.0, 0.06, 120)
		"hero_down":
			play_pos.call("hero_down", -1.0, 0.03, 250)
			if mine:
				Audio.say("clash_down", owner_id)
		"revive":
			play_pos.call("revive", -1.0, 0.03, 200)
			Audio.say("clash_revive", int(e.get("owner", -1)))
		"potion":
			play_pos.call("potion_drink", -2.0, 0.04, 200)
			if mine:
				Audio.say("clash_potion", owner_id)
		"item_bought":
			if e.get("golden", false):
				Audio.play_sfx("golden_buy", 0.0, 0.02, 150)
				if mine:
					Audio.say("clash_golden", owner_id)
			else:
				Audio.play_sfx("upgrade", -2.0, 0.03, 150)
		"rival_spawn":
			Audio.play_sfx("boss_warn", -2.0, 0.03, 500)
			var rk := String(e.get("kind", ""))
			if rk != "":
				Audio.say(rk, -1, false)


func _update_fx(dt: float) -> void:
	for pg in pings:
		pg.t -= dt
	pings = pings.filter(func(pg): return pg.t > 0)
	for k in _emotes.keys():
		_emotes[k].t -= dt
		if _emotes[k].t <= 0:
			_emotes.erase(k)
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
		f.p += f.v * dt
		f.v *= maxf(0.0, 1.0 - 3.0 * dt)
	_floats = _floats.filter(func(f): return f.life > 0)
	if _parts.size() > 900:
		_parts = _parts.slice(_parts.size() - 900)
	if _floats.size() > 80:
		_floats = _floats.slice(_floats.size() - 80)


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
				c.a = (0.35 if fancy else 0.7) * (1 - k)
				glow(f.p, f.r * 1.15, c)
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
				if not fancy:  # (Fancy draws it as a column of light instead)
					var c: Color = f.col
					c.a = 0.35 * (1 - k)
					draw_rect(Rect2(f.p.x - 22, f.p.y - 200 * (0.4 + k), 44, 200 * (0.4 + k) + 20), c)
			"swipe":
				var c: Color = f.col
				c.a = 1 - k
				draw_arc(f.p, 46, f.a - 1.0, f.a + 1.0, 16, c, 6 * (1 - k) + 1, true)
			"ghost":
				var ent := Sprites.pest_entry(f.type)
				Sprites.draw_frame(self, Sprites.tex(ent.get("file", "")), ent, f.frame, f.p, f.face < 0, 1.0 + 0.35 * k, Color(2.2, 2.2, 2.2, 1.0 - k), Sprites.scale)
			"warn":
				var c: Color = f.col
				c.a = 0.4 + sin(time * 18) * 0.25
				ellipse_line(f.p, f.r, f.r * 0.6, c, 3)
				ellipse(f.p, f.r * k, f.r * 0.6 * k, Color(c.r, c.g, c.b, 0.12))
	var vr := _view_rect()
	for p in _parts:
		if vr.has_point(p.p):
			var c: Color = p.col
			var left := clampf(p.life / p.max, 0, 1)
			if p.has("grow"):
				# a puff of smoke: swells and fades
				c.a *= left * left
				glow(p.p, p.size + p.grow * (1.0 - left), c)
			elif p.has("star"):
				continue  # (drawn with the light)
			else:
				c.a = left
				disc(p.p, p.size * (0.5 + 0.5 * left), c)
	_defer_text = true
	for f in _floats:
		if vr.has_point(f.p):
			var c: Color = f.col
			c.a = clampf(f.life / f.max * 1.5, 0, 1)
			# numbers pop up a little bigger, then settle
			var pop := 1.0 + 0.35 * clampf((f.life / f.max - 0.8) / 0.2, 0, 1)
			text(f.p, f.s, int(f.size * pop), c, 4)
	_flush_text()


# ---------------------------------------------------------------------------
# Light (Graphics: Fancy). Drawn on the LightLayer with additive blending, so
# shots, sparks, magic and fireflies really glow.
# ---------------------------------------------------------------------------
const MUZZLE := {"sentry": "bef264", "mortar": "fdba74", "zap": "d8b4fe", "fern": "bae6fd", "pot": "fde68a", "sap": "fbbf24", "gust": "e0f2fe"}


func _lglow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var h := r * 32.0 / 31.0
	ci.draw_texture_rect_region(_shapes, Rect2(c.x - h, c.y - h, h * 2, h * 2), SH_SOFT, col)


## A soft glowing bar from a to b (beams, lightning)
func _lbeam(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	ci.draw_set_transform((a + b) / 2, d.angle(), Vector2.ONE)
	ci.draw_texture_rect_region(_shapes, Rect2(-(d.length() + w) / 2, -w / 2, d.length() + w, w), SH_SOFT, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A four-pointed twinkle
func _lstar(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for d in [Vector2(r, 0), Vector2(0, r)]:
		ci.draw_set_transform(c, d.angle(), Vector2.ONE)
		ci.draw_texture_rect_region(_shapes, Rect2(-r, -r * 0.16, r * 2, r * 0.32), SH_DISC, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_lglow(ci, c, r * 0.9, Color(col.r, col.g, col.b, col.a * 0.5))


func draw_lights(ci: CanvasItem) -> void:
	if snap.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var vr := _view_rect()
	# the Bloom Tree's soft magic
	if not snap.has("clash"):
		var sc: Vector2 = GameData.sanctuary(_map_id)
		var k := clampf(float(snap.get("lives", 1)) / maxf(1.0, float(snap.get("maxLives", 1))), 0, 1)
		_lglow(ci, sc - Vector2(0, 95), 120 + sin(time * 1.3) * 8, Color(1.0, 0.75, 0.88, (0.07 + 0.05 * k) * (1.0 + 0.25 * sin(time * 1.3))))
	for s in _lit_shots:
		var col: Color = s[1]
		_lglow(ci, s[0], s[2] * 3.4, Color(col.r, col.g, col.b, 0.42))
	for w in snap.get("wisps", []):
		_lglow(ci, pos_of(w.id, Vector2(w.x, w.y)), 24, Color(1, 0.55, 0.15, 0.45))
	# towers light up as they fire
	for g in snap.get("gadgets", []):
		var an: Dictionary = _anim.get("g%d" % g.id, {})
		var fk := (time - float(an.get("fire", -9.0))) / 0.2
		if fk < 1.0 and MUZZLE.has(g.kind):
			var mc := Color(MUZZLE[g.kind])
			var ang: float = g.angle
			var mp := Vector2(g.x, g.y - 34) + (Vector2(cos(ang), sin(ang) * 0.6) * 16 if g.kind in ["sentry", "mortar"] else Vector2.ZERO)
			_lglow(ci, mp, 34 * (1.0 - fk * 0.5), Color(mc.r, mc.g, mc.b, 0.7 * (1.0 - fk)))
	# pests on fire, raging or sunlit
	for e in snap.get("enemies", []):
		if not (e.burning or e.get("enraged", false) or e.get("sunlit", false)):
			continue
		var p := pos_of(e.id, Vector2(e.x, e.y))
		if not vr.has_point(p):
			continue
		var R: float = float(GameData.ENEMIES.get(e.type, {}).get("radius", 16)) * (1.35 if e.big else 1.0)
		var flick := 0.8 + 0.2 * sin(time * 17 + p.x)
		if e.burning:
			_lglow(ci, p - Vector2(0, R * 0.5), R * 1.7, Color(1.0, 0.5, 0.15, 0.3 * flick))
		elif e.get("enraged", false):
			_lglow(ci, p - Vector2(0, R * 0.4), R * 1.8, Color(1.0, 0.2, 0.15, 0.22 * flick))
		else:
			_lglow(ci, p - Vector2(0, R * 0.4), R * 1.6, Color(1.0, 0.85, 0.3, 0.14))
	# Sun orbs, power-ups and chests: a warm pulse
	for s in snap.get("suns", []):
		_lglow(ci, Vector2(s.x, s.y - 12 + sin(time * 3 + s.x) * 3), 48 + sin(time * 4 + s.x) * 5, Color(1.0, 0.8, 0.3, 0.34))
	for pu in snap.get("powerups", []):
		_lglow(ci, Vector2(pu.x, pu.y - 16 + sin(time * 4) * 4), 42 + sin(time * 5) * 6, Color(0.95, 0.85, 0.45, 0.3))
	for c in snap.get("chests", []):
		_lglow(ci, Vector2(c.x, c.y - 14), 54 if c.big else 40, Color(1.0, 0.8, 0.35, 0.2 + 0.08 * sin(time * 3)))
	# effects
	for f in _fx:
		var k: float = 1.0 - f.life / f.max
		match f.kind:
			"flash":
				var c: Color = f.col
				_lglow(ci, f.p, f.r * (0.85 + 0.35 * k), Color(c.r, c.g, c.b, 0.45 * (1 - k)))
			"pillar":
				# a column of light that rises and fades
				var c: Color = f.col
				var a := (1.0 - k) * minf(1.0, k * 8.0 + 0.25)
				var hgt := 230.0 * (0.55 + 0.45 * k)
				ci.draw_texture_rect_region(_shapes, Rect2(f.p.x - 46, f.p.y - hgt * 1.1, 92, hgt * 1.4), SH_SOFT, Color(c.r, c.g, c.b, 0.55 * a))
				ci.draw_texture_rect_region(_shapes, Rect2(f.p.x - 14, f.p.y - hgt * 1.25, 28, hgt * 1.5), SH_SOFT, Color(1, 1, 1, 0.5 * a))
				_lglow(ci, f.p, 60, Color(c.r, c.g, c.b, 0.5 * a))
			"bolt":
				var c: Color = f.col
				for i in f.pts.size() - 1:
					_lbeam(ci, f.pts[i], f.pts[i + 1], 30, Color(c.r, c.g, c.b, 0.55 * (1 - k)))
			"beam":
				var c: Color = f.col
				_lbeam(ci, f.a, f.b, 34 * (1 - k * 0.5), Color(c.r, c.g, c.b, 0.5 * (1 - k)))
			"ring":
				if f.w >= 6:  # big blasts: a soft glow fills the ring for a moment
					var c: Color = f.col
					_lglow(ci, f.p, f.r * 0.8 * (0.3 + 0.7 * k), Color(c.r, c.g, c.b, 0.25 * (1 - k) * (1 - k)))
	for p in _parts:
		if not vr.has_point(p.p):
			continue
		var left := clampf(p.life / p.max, 0, 1)
		if p.has("star"):
			var tw := 0.6 + 0.4 * sin(time * 30 + p.p.x)
			_lstar(ci, p.p, p.size * (0.4 + 0.6 * left) * tw, Color(p.col.r, p.col.g, p.col.b, left))
		elif p.get("lit", false):
			_lglow(ci, p.p, p.size * 3.2, Color(p.col.r, p.col.g, p.col.b, 0.2 * left))
	# ambient life
	match _amb_kind:
		"firefly":
			for a in _amb:
				var blink := 0.5 + 0.5 * sin(a.ph * 3.0 + a.rot * 5)
				_lglow(ci, a.p, 16 * a.s, Color(0.75, 1.0, 0.35, 0.45 * blink))
		"pollen":
			for a in _amb:
				_lglow(ci, a.p, 7 * a.s, Color(1.0, 0.92, 0.5, 0.16))
		"sparkle":
			for a in _amb:
				var k: float = clampf(a.life, 0, 1) * clampf(3.0 - a.life, 0, 1)
				if k > 0.05:
					_lstar(ci, a.p, 6.0 * a.s * k, Color(0.85, 0.95, 1.0, 0.7 * k))
	PerfStats.add("light draw", Time.get_ticks_usec() - t0)


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
	disc(c, r, Color(col.r, col.g, col.b, 0.12 + pulse * 0.06))
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
	var c: Color = Color(1.7, 1.7, 1.7) if flash else mod
	var origin: Array = e.get("origin", [75, 125])
	c.a *= _see_through("b%d_%d" % [roundi(pos.x), roundi(pos.y)], pos, float(origin[0]) * 0.8, float(origin[1]), pos.y)
	Sprites.draw_frame(self, Sprites.tex(e.file), e, frame, pos, false, 1.0, c, Sprites.scale)


## Something big (the Bloom Tree, a tower, a Thorn building) fades to see-through
## while a hero stands behind it, so you never lose your hero. `base` is where it
## stands, it reaches `half_w` to each side and `height` up, and it's drawn after
## anything whose depth is less than `sort_y`. Returns the alpha to draw it with.
func _see_through(key: String, base: Vector2, half_w: float, height: float, sort_y: float) -> float:
	var behind := false
	for h in snap.get("heroes", []):
		if h.get("dead", false):
			continue
		var p: Vector2 = _me() if h.owner == my_owner and my_pos != null else pos_of(h.id, Vector2(h.x, h.y))
		# drawn before it (hero depth is p.y + 4), and its body overlaps the picture
		if p.y + 4 < sort_y and p.y > base.y - height - 10 and absf(p.x - base.x) < half_w + 12:
			behind = true
			break
	var k := "see_" + key
	var a: float = _anim.get(k, 1.0)
	a = move_toward(a, 0.42 if behind else 1.0, get_process_delta_time() * 4.0)
	if a >= 1.0:
		_anim.erase(k)
	else:
		_anim[k] = a
	return a


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
		disc(p - Vector2(0, R * 0.3), R * 1.5, Color(0.29, 0.87, 0.5, 0.16))
	var frame := int(fposmod(a.phase, 1.0) * 8) % 8
	Sprites.draw_frame(self, Sprites.tex(entry.file), entry, frame, feet, a.face < 0, S, Color(1.7, 1.7, 1.7) if u.get("flash", false) else Color.WHITE, Sprites.scale)
	if u.hp < u.maxHp:
		bar(Vector2(p.x, feet.y - R * 2.1 - 6), maxf(22.0, R * 1.7), 4, float(u.hp) / float(u.maxHp), Color("38bdf8"))
	if u.has("cap"):
		# a Captain: a little banner on a pole, and its name
		var top := feet + Vector2(-R * 0.9, -R * 2.6 - 18)
		draw_line(feet + Vector2(-R * 0.9, -R * 0.4), top, Color("78350f"), 2.5)
		var wave_k := sin(time * 6.0 + u.id) * 3.0
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(20, 5 + wave_k * 0.3), top + Vector2(0, 12)]), Color("fde047"))
		text(feet + Vector2(0, -R * 2.6 - 28), "🚩 " + String(u.cap), 12, Color("fef9c3"), 3)


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


## Garden Plots: a patch of soil by each lane. Stand on an empty one to claim it,
## then grow a Berry Bush (heals friends close by) or a Spring Vine (a leap down the lane).
func draw_plots(clash: Dictionary) -> void:
	for pl in clash.get("plots", []):
		var c := Vector2(pl.x, pl.y)
		if not _view_rect().grow(300).has_point(c):
			continue
		var st := String(pl.state)
		var lost: float = pl.get("lost", 0.0)
		ellipse(c + Vector2(0, 4), 50, 24, Color(0.36, 0.22, 0.1, 0.85))
		ellipse(c + Vector2(0, 2), 42, 19, Color(0.48, 0.3, 0.14, 0.95))
		for i in 3:
			draw_line(c + Vector2(-28 + i * 6, -6 + i * 6), c + Vector2(28 + i * 6 - 12, -6 + i * 6), Color(0.33, 0.2, 0.09, 0.8), 2.0)
		match st:
			"empty":
				# a little sign; a ring fills up while someone claims it
				draw_line(c + Vector2(30, 8), c + Vector2(30, -30), Color("78350f"), 3)
				draw_rect(Rect2(c + Vector2(16, -44), Vector2(30, 18)), Color("a16207"))
				text(c + Vector2(31, -30), "🌱", 12, Color.WHITE, 0)
				if float(pl.claim) > 0.01:
					draw_arc(c, 56, -PI / 2, -PI / 2 + TAU * float(pl.claim), 40, Color("86efac"), 5, true)
					text(c + Vector2(0, 46), "Claiming…", 13, Color("bbf7d0"), 3)
			"ready":
				var pulse := 0.5 + 0.5 * sin(time * 5.0)
				draw_arc(c, 56, 0, TAU, 40, Color(0.99, 0.88, 0.28, 0.5 + 0.5 * pulse), 4, true)
				for i in 5:
					var a := time * 1.5 + TAU * i / 5.0
					disc(c + Vector2(cos(a) * 30, sin(a) * 12 - 6), 3, Color(1, 1, 0.7, 0.8))
				text(c + Vector2(0, 46), "Grow: 1 🫐 Berry · 2 🌱 Vine", 13, Color("fde68a"), 3)
			"berry":
				ellipse_line(c, BERRY_R, BERRY_R, Color(0.75, 0.4, 0.95, 0.3), 2.0)
				for b in [[-14, -14, 16], [12, -16, 15], [0, -28, 15], [-4, -8, 14]]:
					disc(c + Vector2(b[0], b[1]), b[2], Color("15803d"))
				for b in [[-14, -14, 12], [12, -16, 11], [0, -28, 11]]:
					disc(c + Vector2(b[0] - 2, b[1] - 3), b[2] * 0.7, Color("22c55e"))
				for b in [[-18, -16], [-8, -22], [6, -26], [14, -12], [2, -10], [-12, -6], [18, -20]]:
					disc(c + Vector2(b[0], b[1]), 3.6, Color("a855f7"))
			"vine":
				# a coiled spring of vine with leaves
				for i in 4:
					draw_arc(c + Vector2(0, -6 - i * 9), 16 - i * 2, 0, TAU, 20, Color("16a34a"), 4, true)
				disc(c + Vector2(-14, -40), 6, Color("4ade80"))
				disc(c + Vector2(13, -44), 6, Color("4ade80"))
				text(c + Vector2(0, 46), "Spring Vine: step on it!", 12, Color("bbf7d0"), 3)
		if lost > 0.01:
			draw_arc(c, 62, -PI / 2, -PI / 2 + TAU * lost, 40, Color("f87171"), 4, true)
			text(c + Vector2(0, 64), "Pests are trampling it!", 12, Color("fca5a5"), 3)


const BERRY_R := 230.0


## A Sproutling Captain's rally flag: Sproutlings close by hit harder and take less damage
func draw_flags(clash: Dictionary) -> void:
	for f in clash.get("flags", []):
		var c := Vector2(f.x, f.y)
		var k := clampf(float(f.t) / 20.0, 0.0, 1.0)
		ellipse_line(c, 280, 280, Color(0.99, 0.88, 0.28, 0.25 + 0.15 * sin(time * 4.0)), 2.0)
		draw_line(c + Vector2(0, 10), c + Vector2(0, -70), Color("78350f"), 4)
		var w := sin(time * 5.0) * 4.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -70), c + Vector2(34, -60 + w * 0.4), c + Vector2(0, -48)]), Color(0.99, 0.88, 0.28, 0.6 + 0.4 * k))
		text(c + Vector2(0, -80), "🚩 %s's rally flag" % String(f.name), 12, Color("fef9c3"), 3)


## A Rival Raid: the tower they're coming for pulses red, and the raiders wear a red ring
func _draw_raid(clash: Dictionary) -> void:
	var r: Dictionary = clash.get("raid", {})
	if r.is_empty():
		return
	var c := Vector2(r.x, r.y)
	var pulse := 0.5 + 0.5 * sin(time * 7.0)
	ellipse_line(c, 120 + pulse * 10, 60 + pulse * 5, Color(0.97, 0.3, 0.3, 0.5 + 0.4 * pulse), 4.0)
	text(c + Vector2(0, 60), ("⚔️ RAID in %ds!" % int(r.t)) if r.phase == "warn" else "⚔️ RAID!", 16, Color("fecaca"), 4)
	for e in snap.get("enemies", []):
		if e.get("raiding", false):
			var p := pos_of(e.id, Vector2(e.x, e.y))
			ellipse_line(p + Vector2(0, 18), 34, 14, Color(0.97, 0.3, 0.3, 0.8), 3.0)


## A Thorn Tower locked on a hero: a line from the tower, and 1, 2, then 3
## warning thorns over the hero (each shot in a row hurts more)
func _draw_tower_locks() -> void:
	for e in snap.get("enemies", []):
		var lock := int(e.get("lock", -1))
		if lock < 0:
			continue
		var hero := {}
		for h in snap.get("heroes", []):
			if int(h.id) == lock and not h.get("dead", false):
				hero = h
		if hero.is_empty():
			continue
		var hp: Vector2 = _me() if hero.owner == my_owner and my_pos != null else pos_of(hero.id, Vector2(hero.x, hero.y))
		var from := Vector2(e.x, e.y - (50 if e.get("core", false) else 52))
		var n := mini(int(e.get("streak", 0)) + 1, 3)
		var pulse := 0.5 + 0.5 * sin(time * (8.0 + n * 3.0))
		var col := Color(0.97, 0.25 + 0.1 * (3 - n), 0.35, 0.55 + 0.35 * pulse)
		# a dashed line, marching toward the hero
		var d := hp - Vector2(0, 30) - from
		var L := d.length()
		var step := 22.0
		var off := fmod(time * 60.0, step)
		var i := off
		while i < L - 8:
			draw_line(from + d / L * i, from + d / L * minf(i + 11, L), col, 3.5)
			i += step
		var top := hp + Vector2(0, -92)
		for k in n:
			var x := (k - (n - 1) / 2.0) * 16.0
			draw_colored_polygon(PackedVector2Array([top + Vector2(x - 6, 6), top + Vector2(x + 6, 6), top + Vector2(x, -10)]), Color(0.97, 0.3, 0.4, 0.75 + 0.25 * pulse))
		if n >= 3 and hero.owner == my_owner:
			text(top + Vector2(0, -16), "Step back!", 14, Color("fecaca"), 4)


func draw_camps(clash: Dictionary) -> void:
	for c in clash.get("camps", []):
		if c.up or int(c.respawn) <= 0:
			continue
		var def: Dictionary = GameData.ENEMIES.get(c.kind, {})
		var s := "%s%s back in %ds" % ["Elder " if c.get("elder", false) else "", def.get("name", ""), int(c.respawn)]
		text(Vector2(c.x, c.y + 4), s, 12, Color(1, 1, 1, 0.85), 3)


func draw_clash_shots(clash: Dictionary) -> void:
	var k := clampf(tick_alpha, 0, 1.2) * snap_dt
	for s in clash.get("shots", []):
		var at := Vector2(s.x + s.vx * k, s.y + s.vy * k)
		var st: Array = SHOT_STYLE.get(s.kind, ["ffffff", 5])
		var c := Color(st[0])
		var r: float = st[1]
		var dir := Vector2(s.vx, s.vy).normalized()
		draw_line(at - dir * r * 3, at, Color(c.r, c.g, c.b, 0.4), r * 1.1, true)
		disc(at, r * 2.2, Color(c.r, c.g, c.b, 0.2))
		_draw_shot(CLASH_SHOT_FRAMES.get(s.kind, 0), at, dir, r, Color.WHITE.lerp(c, 0.3))


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
		if int(g.id) == picked_tower:
			var gp := Vector2(g.x, g.y)
			disc(gp, _tower_range(g), Color(0.99, 0.88, 0.28, 0.07))
			draw_arc(gp, _tower_range(g), 0, TAU, 64, Color(0.99, 0.88, 0.28, 0.65), 2, true)
			draw_arc(gp + Vector2(0, 6), 34, 0, TAU, 32, Color(1, 1, 1, 0.6 + 0.4 * sin(time * 5.0)), 3, true)
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


func _draw_pings() -> void:
	for pg in pings:
		var col: Color = GameData.player_color(pg.slot)
		var ph := fmod(time * 1.6, 1.0)
		var a: float = clampf(pg.t / 0.6, 0, 1)
		draw_arc(pg.p, 14 + ph * 46, 0, TAU, 40, Color(col.r, col.g, col.b, (1 - ph) * a), 4, true)
		disc(pg.p, 10, Color(col.r, col.g, col.b, 0.8 * a))
		var look: Array = PING_LOOK.get(pg.kind, PING_LOOK.look)
		draw_line(pg.p, pg.p - Vector2(0, 46), Color(col.r, col.g, col.b, 0.8 * a), 3, true)
		text(pg.p - Vector2(0, 52), "%s %s" % [look[0], look[1]], 15, Color(1, 1, 1, a), 4)
		text(pg.p - Vector2(0, 70), pg.name, 11, Color(col.r, col.g, col.b, a), 3)


## Tier 3 / 4 evolution: a golden burst
func evolve_fx(p: Vector2, tier: int) -> void:
	_fx.append({"kind": "pillar", "p": p, "col": Color("fde047"), "life": 1.4, "max": 1.4})
	ring(p, 120 if tier >= 4 else 90, Color("fde047"), 8, 0.7)
	ring(p, 60, Color.WHITE, 5, 0.5)
	burst(p - Vector2(0, 30), ["fde047", "facc15", "ffffff", "fef08a"], 40 if tier >= 4 else 26, 240)
	shake = maxf(shake, 4)


## The map's little gimmicks (sunflowers, lily pads, the obelisk, leaf piles, geysers)
const FEATURE_ART := {
	"sunflower": preload("res://art/world/sunflower.png"), "lilypad": preload("res://art/world/lilypad.png"),
	"obelisk": preload("res://art/world/obelisk.png"), "leafpile": preload("res://art/world/leafpile.png"),
	"geyser": preload("res://art/world/geyser.png"),
}
const FEATURE_WIDTH := {"sunflower": 47.0, "lilypad": 60.0, "obelisk": 70.0, "leafpile": 58.0, "geyser": 52.0}


func _draw_features() -> void:
	for f in snap.get("features", []):
		var kind := String(f.kind)
		var tex: Texture2D = FEATURE_ART.get(kind)
		if tex == null:
			continue
		var p := Vector2(f.x, f.y)
		var k := clampf(f.ready, 0, 1)
		var ready := k >= 0.999
		var bottom := 9.0
		var width := float(FEATURE_WIDTH[kind])
		match kind:
			"sunflower", "leafpile":
				width *= lerpf(0.64, 1.0, k)
			"lilypad":
				bottom = 18.0
				if ready:
					ellipse_line(p, 36, 19, Color(0.73, 0.97, 0.82, 0.4 + 0.3 * sin(time * 5)), 2)
			"obelisk":
				if ready:
					glow(p - Vector2(0, 36), 46, Color(0.77, 0.71, 0.99, 0.18 + 0.12 * sin(time * 6)))
				bar(p + Vector2(0, 18), 50, 5, k, Color("a78bfa"))
				if ready:
					text(p + Vector2(0, -84), "✨ Stand here!", 13, Color("e9d5ff"), 3)
		var extent := tex.get_size() * (width / tex.get_width())
		draw_texture_rect(tex, Rect2(p + Vector2(-width / 2.0, bottom - extent.y), extent), false,
			Color("a0a18a").lerp(Color.WHITE, k))
		if kind == "geyser" and k > 0.85:
			for i in 3:
				var a := time * 6 + i * 2.1
				disc(p + Vector2(cos(a) * 8, -18 - fmod(time * 30 + i * 10, 30)), 3, Color(0.88, 0.95, 1.0, 0.7))
		if kind == "sunflower" and ready:
			glow(p - Vector2(0, 23), 25, Color(1.0, 0.82, 0.22, 0.13 + 0.07 * sin(time * 4)))


# ---------------------------------------------------------------------------
# Ambient life: pollen, sparkles, fireflies, falling leaves, snow, petals
# ---------------------------------------------------------------------------
const AMBIENT := {"meadow": "pollen", "river": "sparkle", "courtyard": "firefly", "hollow": "leaf", "frosty": "snow", "valley": "petal"}
var _amb: Array = []
var _amb_kind := ""


func _view_rect() -> Rect2:
	var vp := get_viewport_rect().size / maxf(0.1, camera.zoom.x)
	return Rect2(camera.get_screen_center_position() - vp / 2, vp).grow(40)


var _water: Image  # a small copy of the map, to find water (river sparkles twinkle on it)


## A tenth-size copy of the map picture (null if it can't be read, e.g. no screen)
static func _water_map(t: Texture2D) -> Image:
	if t == null:
		return null
	var img := t.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed() and img.decompress() != OK:
		return null
	img.resize(maxi(1, img.get_width() / 10), maxi(1, img.get_height() / 10), Image.INTERPOLATE_BILINEAR)
	return img


## Is there water here? (the same clearly-blue test as the ground shader)
func _is_water(p: Vector2) -> bool:
	if _water == null:
		return true
	var x := int(p.x / GameData.W * _water.get_width())
	var y := int(p.y / GameData.H * _water.get_height())
	if x < 0 or y < 0 or x >= _water.get_width() or y >= _water.get_height():
		return false
	var c := _water.get_pixel(x, y)
	return c.b - c.r > 0.26 and c.r < 0.5 and c.b >= c.g - 0.01


func _amb_new(kind: String, r: Rect2, anywhere: bool) -> Dictionary:
	var p := Vector2(r.position.x + randf() * r.size.x, r.position.y + randf() * r.size.y)
	if kind == "sparkle" and _water != null:
		# glints on the water only (none showing if there's no water in view)
		var found := false
		for i in 8:
			if _is_water(p):
				found = true
				break
			p = Vector2(r.position.x + randf() * r.size.x, r.position.y + randf() * r.size.y)
		if not found:
			return {"p": p, "ph": 0.0, "s": 0.0, "rot": 0.0, "life": 0.0}
	if not anywhere and kind in ["leaf", "snow", "petal"]:
		p.y = r.position.y - randf() * 30
	return {"p": p, "ph": randf() * TAU, "s": 0.6 + randf() * 0.8, "rot": randf() * TAU, "life": 1.0 + randf() * 2.0}


func _update_ambient(dt: float) -> void:
	if _map_id == "":
		return
	var kind: String = AMBIENT.get(_map_id, "pollen")
	var r := _view_rect()
	var want: int = {"snow": 110, "leaf": 34, "petal": 30, "firefly": 36, "sparkle": 40, "pollen": 60}.get(kind, 50)
	if kind != _amb_kind:
		_amb_kind = kind
		_amb.clear()
	while _amb.size() < want:
		_amb.append(_amb_new(kind, r, true))
	for a in _amb:
		a.ph += dt
		match kind:
			"pollen":
				a.p += Vector2(14 + sin(a.ph * 1.3) * 8, -6 + cos(a.ph) * 6) * a.s * dt
			"snow":
				a.p += Vector2(sin(a.ph * 1.1) * 18, 46 * a.s) * dt
			"leaf", "petal":
				a.p += Vector2(22 + sin(a.ph * 1.7) * 26, 34 * a.s) * dt
				a.rot += dt * 2.0 * a.s
			"firefly":
				a.p += Vector2(cos(a.ph * 0.7 + a.rot) * 18, sin(a.ph * 0.9) * 14) * dt
			"sparkle":
				a.life -= dt
		var out: bool = not r.has_point(a.p)
		if out or (kind == "sparkle" and a.life <= 0):
			var fresh := _amb_new(kind, r, kind in ["sparkle", "firefly", "pollen"])
			a.p = fresh.p
			a.life = fresh.life
			a.s = fresh.s


func _draw_ambient() -> void:
	for a in _amb:
		match _amb_kind:
			"pollen":
				disc(a.p, 2.2 * a.s, Color(1.0, 0.95, 0.6, 0.55))
			"snow":
				disc(a.p, 2.4 * a.s, Color(1, 1, 1, 0.85))
			"leaf":
				var col: Color = [Color("ea580c"), Color("dc2626"), Color("f59e0b")][int(a.s * 10) % 3]
				var d: Vector2 = Vector2(cos(a.rot), sin(a.rot)) * 5 * a.s
				streak(a.p - d * 0.5, a.p + d * 0.5, 5 * a.s, Color(col.r, col.g, col.b, 0.85))
			"petal":
				var d: Vector2 = Vector2(cos(a.rot), sin(a.rot)) * 4 * a.s
				streak(a.p - d * 0.5, a.p + d * 0.5, 5 * a.s, Color(0.98, 0.66, 0.83, 0.85))
			"firefly":
				var blink := 0.5 + 0.5 * sin(a.ph * 3.0 + a.rot * 5)
				if not fancy:
					glow(a.p, 9 * a.s, Color(0.85, 1.0, 0.45, 0.3 * blink))
				disc(a.p, 2.2 * a.s, Color(0.95, 1.0, 0.6, 0.9 * blink))
			"sparkle":
				if fancy:
					continue  # (twinkles with the light)
				var k: float = clampf(a.life, 0, 1) * clampf(3.0 - a.life, 0, 1)
				var sz: float = 4.0 * a.s * k
				seg(a.p - Vector2(sz, 0), a.p + Vector2(sz, 0), 1.5, Color(1, 1, 1, 0.8 * k))
				seg(a.p - Vector2(0, sz), a.p + Vector2(0, sz), 1.5, Color(1, 1, 1, 0.8 * k))
