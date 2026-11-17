extends Node
## Sprite sheets exported from the original game's renderer (art/atlas.json).
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
		_tex[path] = load(full) if ResourceLoader.exists(full) else null
	return _tex[path]


## Draw frame `i` of a sheet entry ({cell, origin}) with its origin at `pos`.
static func draw_frame(ci: CanvasItem, t: Texture2D, entry: Dictionary, i: int, pos: Vector2, flip := false, size := 1.0, mod := Color.WHITE, s := 1.5) -> void:
	if t == null:
		return
	var cw: float = ceil(entry.cell[0] * s)
	var ch: float = ceil(entry.cell[1] * s)
	var src := Rect2(cw * i, 0, cw, ch)
	var k := size / s
	ci.draw_set_transform(pos, 0.0, Vector2(-k if flip else k, k))
	ci.draw_texture_rect_region(t, Rect2(-entry.origin[0] * s, -entry.origin[1] * s, cw, ch), src, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func hero_entry(type: String) -> Dictionary:
	return atlas.get("heroes", {}).get(type, {})


func hero_tex(type: String, tier_a: int, tier_b: int) -> Texture2D:
	var e := hero_entry(type)
	var key := "%d%d" % [tier_a, tier_b]
	return tex(e.get("variants", {}).get(key, e.get("variants", {}).get("00", "")))


func pest_entry(type: String) -> Dictionary:
	return atlas.get("pests", {}).get(type, {})


func gadget_tex(kind: String, level: int, branch: int, slot: int) -> Texture2D:
	var e: Dictionary = atlas.get("gadgets", {}).get(kind, {})
	var key := "%d%s_s%d" % [level, "" if branch < 0 else ("a" if branch == 0 else "b"), slot]
	return tex(e.get("looks", {}).get(key, ""))
