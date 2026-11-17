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
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Arial Rounded MT Bold", "Avenir Next", "Nunito", "Segoe UI", "Helvetica Neue", "sans-serif"])
		f.font_weight = 700
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		# colour emoji first, so icons like the sword and shield aren't grey text glyphs
		var emoji := SystemFont.new()
		emoji.font_names = PackedStringArray(["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"])
		f.fallbacks = [emoji]
		_font = f
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
	var t := frame_tex(e.get("variants", {}).get("%d%d" % [a, b], e.get("variants", {}).get("00", "")), e, 0)
	if t:  # crop to the hero itself (the cell has room for big upgrades)
		var s := Sprites.scale
		t.region = Rect2(t.region.position + Vector2(24, 30) * s, Vector2(72, 80) * s)
	return t
