class_name UiKit
extends RefCounted
## Shared look: one rounded bold font, panel/button styles and a theme.

static var _font: Font
static var _theme: Theme

const GREEN := Color("4ade80")
const GREEN_DARK := Color("166534")
const GOLD := Color("facc15")
const PANEL := Color(0.05, 0.1, 0.07, 0.86)
const PANEL_EDGE := Color(0.53, 0.94, 0.67, 0.35)


static func font() -> Font:
	if _font == null:
		# colour emoji first, so icons like the sword and shield aren't grey text glyphs
		var emoji := SystemFont.new()
		emoji.font_names = PackedStringArray(["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"])
		if OS.get_name() == "macOS" and not OS.get_cmdline_user_args().has("--bundled-font"):
			# Macs have a rounded bold font built in
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Arial Rounded MT Bold", "Avenir Next", "Nunito", "Helvetica Neue", "sans-serif"])
			f.font_weight = 700
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			f.fallbacks = [emoji]
			_font = f
		else:
			# Windows and Linux: the rounded font that comes with the game
			# (Nunito, SIL Open Font License: fonts/OFL.txt)
			var nf: FontFile = load("res://fonts/Nunito.ttf")
			nf.fallbacks = [emoji]
			var fv := FontVariation.new()
			fv.base_font = nf
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
			fv.fallbacks = [emoji]
			_font = fv
	return _font


static func box(bg: Color, edge: Color = Color(0, 0, 0, 0), radius := 12, border := 2, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border if edge.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	t.set_stylebox("normal", "Button", box(Color("15803d"), Color("4ade80"), 14, 2, 10))
	t.set_stylebox("hover", "Button", box(Color("16a34a"), Color("bbf7d0"), 14, 2, 10))
	t.set_stylebox("pressed", "Button", box(Color("166534"), Color("facc15"), 14, 3, 10))
	t.set_stylebox("disabled", "Button", box(Color(0.2, 0.25, 0.22, 0.8), Color(1, 1, 1, 0.1), 14, 2, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color("fde047"), 14, 2, 10))
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color("fef9c3"))
	for k in ["normal", "hover", "pressed", "focus"]:
		var sb := box(Color(0.08, 0.16, 0.11, 0.95), Color(0.53, 0.94, 0.67, 0.5 if k != "hover" else 0.9), 10, 2, 8)
		t.set_stylebox(k, "OptionButton", sb)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.06, 0.13, 0.09, 0.98), Color("4ade80"), 10, 2, 6))
	t.set_stylebox("hover", "PopupMenu", box(Color("15803d"), Color(0, 0, 0, 0), 6, 0, 4))
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.07, 0.05, 0.95), Color(0.53, 0.94, 0.67, 0.5), 10, 2, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), Color("fde047"), 10, 2, 8))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, PANEL_EDGE, 18, 2, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, PANEL_EDGE, 18, 2, 18))
	t.set_color("font_color", "Label", Color("ecfdf5"))
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("normal", "ItemList", box(Color(0.03, 0.07, 0.05, 0.9), Color(0.53, 0.94, 0.67, 0.4), 10, 2, 6))
	t.set_stylebox("selected", "ItemList", box(Color("15803d"), Color(0, 0, 0, 0), 6, 0, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color("15803d"), Color("fde047"), 6, 2, 4))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.1, 0.07, 0.95), Color("4ade80"), 8, 1, 8))
	_theme = t
	return t


## A small texture of one sprite frame (for menus and the HUD)
static func frame_tex(file: String, entry: Dictionary, frame := 0) -> AtlasTexture:
	var t: Texture2D = Sprites.tex(file)
	if t == null or entry.is_empty():
		return null
	var s := Sprites.scale
	var a := AtlasTexture.new()
	a.atlas = t
	a.region = Rect2(ceil(entry.cell[0] * s) * frame, 0, ceil(entry.cell[0] * s), ceil(entry.cell[1] * s))
	return a


static func hero_icon(type: String, a := 0, b := 0) -> AtlasTexture:
	var e: Dictionary = Sprites.hero_entry(type)
	var key := "%d%d" % [a, b]
	var t := frame_tex(e.get("variants", {}).get(key, e.get("variants", {}).get("00", "")), e, 0)
	var layouts: Dictionary = e.get("layout", {})
	var layout: Dictionary = layouts.get(key, layouts.get("00", {}))
	if t and layout.has("portrait"):
		var rect: Array = layout.portrait
		t.region = Rect2(rect[0], rect[1], rect[2], rect[3])
	return t


# ---------------------------------------------------------------------------
# Drawn HUD icons: the ones on screen all the time look the same on every
# computer (emoji fonts differ between macOS, Windows and Linux)
# ---------------------------------------------------------------------------
static func icon_acorn(ci: CanvasItem, c: Vector2, s: float) -> void:
	var k := s / 20.0
	ci.draw_set_transform(c + Vector2(0, 2 * k), 0.0, Vector2(1.0, 1.15))
	ci.draw_circle(Vector2.ZERO, 7.5 * k, Color("92400e"))
	ci.draw_circle(Vector2(-2.5, -2) * k, 3 * k, Color(1, 1, 1, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_set_transform(c + Vector2(0, -4 * k), 0.0, Vector2(1.0, 0.55))
	ci.draw_circle(Vector2.ZERO, 8.5 * k, Color("a16207"))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 4:
		ci.draw_line(c + Vector2(-7 + i * 4.5, -6.5) * k, c + Vector2(-5.5 + i * 4.5, -2) * k, Color("713f12"), 1.2 * k)
	ci.draw_line(c + Vector2(0, -8.5) * k, c + Vector2(1.5, -12) * k, Color("713f12"), 2 * k)


static func icon_tree(ci: CanvasItem, c: Vector2, s: float) -> void:
	var k := s / 22.0
	ci.draw_rect(Rect2(c + Vector2(-2.5, 1) * k, Vector2(5, 10) * k), Color("854d0e"))
	for b in [[Vector2(0, -5), 8.5], [Vector2(-6, -1), 6.5], [Vector2(6, -1), 6.5], [Vector2(0, -10), 6.0]]:
		ci.draw_circle(c + b[0] * k, b[1] * k, Color("16a34a"))
	ci.draw_circle(c + Vector2(-2, -8) * k, 2.2 * k, Color("f9a8d4"))
	ci.draw_circle(c + Vector2(4, -3) * k, 2.0 * k, Color("f9a8d4"))
	ci.draw_circle(c + Vector2(0, -3) * k, 2.4 * k, Color("f43f5e"))


static func icon_pause(ci: CanvasItem, c: Vector2, s: float, col := Color.WHITE) -> void:
	ci.draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.38), Vector2(s * 0.22, s * 0.76)), col)
	ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.38), Vector2(s * 0.22, s * 0.76)), col)


static func icon_play(ci: CanvasItem, c: Vector2, s: float, col := Color.WHITE) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.4), c + Vector2(s * 0.4, 0), c + Vector2(-s * 0.3, s * 0.4)]), col)


## "🌰 123" as a drawn acorn + number; returns the width used
static func acorns_text(ci: CanvasItem, pos: Vector2, n: int, size := 16, col := Color("fcd34d"), right := false) -> float:
	var f := font()
	var label := str(n)
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var total := size + 4 + w
	var x := pos.x - total if right else pos.x
	icon_acorn(ci, Vector2(x + size * 0.5, pos.y - size * 0.35), size)
	ci.draw_string(f, Vector2(x + size + 4, pos.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return total
