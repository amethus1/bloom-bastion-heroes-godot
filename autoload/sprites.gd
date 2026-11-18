extends Node
## Painted sprite sheets and their frame layouts (art/atlas.json).
## Autoloaded as `Sprites`. Every sheet is drawn at 1/scale (they are rendered
## at 1.5x for crisp edges).

var atlas: Dictionary = {}
var scale := 1.5
var _tex: Dictionary = {}


func _init() -> void:
	var f := FileAccess.open("res://art/atlas.json", FileAccess.READ)
	if f:
		atlas = JSON.parse_string(f.get_as_text())
		scale = float(atlas.get("scale", 1.5))


func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex.has(path):
		var full := "res://art/" + path
		if _warming.has(full):
			_warming.erase(full)
			_tex[path] = ResourceLoader.load_threaded_get(full)  # waits only if it's still loading
		else:
			_tex[path] = load(full) if ResourceLoader.exists(full) else null
	return _tex[path]


var _warming := {}


## Start loading every pest, tower and building sheet on a background thread
## (called at the title screen), so a new kind of pest walking on screen
## mid-fight never makes the game stutter while its picture loads.
func warm_up() -> void:
	if not _warming.is_empty() or _tex.size() > 40 or not _has_screen():
		return
	var files: Array = []
	for group in ["pests", "structures"]:
		for k in atlas.get(group, {}):
			var e = atlas[group][k]
			if e is Dictionary and e.has("file"):
				files.append(e.file)
	for k in atlas.get("gadgets", {}):
		var e = atlas.gadgets[k]
		if e is Dictionary:
			for v in e.get("looks", {}).values():
				files.append(v)
			if e.has("file"):
				files.append(e.file)
	for f in files:
		var full := "res://art/" + String(f)
		if not _tex.has(f) and not _warming.has(full) and ResourceLoader.exists(full):
			if ResourceLoader.load_threaded_request(full, "Texture2D") == OK:
				_warming[full] = true


## Start loading one sheet in the background now, so it's ready the moment it's
## needed (a hero's next evolution)
func prefetch(path: String) -> void:
	if path == "" or _tex.has(path) or not _has_screen():
		return
	var full := "res://art/" + path
	if _warming.has(full) or not ResourceLoader.exists(full):
		return
	if ResourceLoader.load_threaded_request(full, "Texture2D") == OK:
		_warming[full] = true


## Tests and servers run with no screen: nothing to get ready early there, and the
## stand-in renderer they use can trip over pictures made on another thread
static func _has_screen() -> bool:
	return DisplayServer.get_name() != "headless"


func _exit_tree() -> void:
	finish_warm_up()  # quitting while sheets are still loading would leak them


## Collect anything still loading in the background (before quitting)
func finish_warm_up() -> void:
	for full in _warming.keys():
		ResourceLoader.load_threaded_get(full)
	_warming.clear()


## Draw frame `i` of a sheet entry ({cell, origin}) with its origin at `pos`.
## `lean` tilts the top sideways while the feet stay put (swaying plants).
static func draw_frame(ci: CanvasItem, t: Texture2D, entry: Dictionary, i: int, pos: Vector2, flip := false, size := 1.0, mod := Color.WHITE, s := 1.5, stretch := Vector2.ONE, lean := 0.0) -> void:
	if t == null:
		return
	var cw: float = ceil(entry.cell[0] * s)
	var ch: float = ceil(entry.cell[1] * s)
	var src := Rect2(cw * i, 0, cw, ch)
	var k := size / s
	if lean != 0.0:
		var sx := (-k if flip else k) * stretch.x
		var sy := k * stretch.y
		ci.draw_set_transform_matrix(Transform2D(Vector2(sx, 0), Vector2(-sin(lean) * sy, cos(lean) * sy), pos))
	else:
		ci.draw_set_transform(pos, 0.0, Vector2((-k if flip else k) * stretch.x, k * stretch.y))
	ci.draw_texture_rect_region(t, Rect2(-entry.origin[0] * s, -entry.origin[1] * s, cw, ch), src, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func hero_entry(type: String) -> Dictionary:
	return atlas.get("heroes", {}).get(type, {})


func hero_tex(type: String, tier_a: int, tier_b: int) -> Texture2D:
	var e := hero_entry(type)
	var key := "%d%d" % [tier_a, tier_b]
	return tex(e.get("variants", {}).get(key, e.get("variants", {}).get("00", "")))


## Hat offsets are relative to the feet, in sheet pixels, for each animation frame.
func hero_hat_offset(type: String, tier_a: int, tier_b: int, frame: int) -> Vector2:
	var layouts: Dictionary = hero_entry(type).get("layout", {})
	var layout: Dictionary = layouts.get("%d%d" % [tier_a, tier_b], layouts.get("00", {}))
	var offsets: Array = layout.get("hat", [])
	if frame >= 0 and frame * 2 + 1 < offsets.size():
		return Vector2(offsets[frame * 2], offsets[frame * 2 + 1]) / scale
	var anchor: Array = atlas.hatAnchor.get(type, [0, -55, 1])
	return Vector2(anchor[0], anchor[1])


func pest_entry(type: String) -> Dictionary:
	return atlas.get("pests", {}).get(type, {})


func gadget_tex(kind: String, level: int, branch: int, slot: int) -> Texture2D:
	var e: Dictionary = atlas.get("gadgets", {}).get(kind, {})
	var key := "%d%s_s%d" % [level, "" if branch < 0 else ("a" if branch == 0 else "b"), slot]
	return tex(e.get("looks", {}).get(key, ""))
