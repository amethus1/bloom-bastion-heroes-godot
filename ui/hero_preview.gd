class_name HeroPreview
extends Control
## A live, animated look at your hero wearing the chosen hat, with the pet
## trotting alongside (title screen). Idles for 2 seconds, walks for 2.

var hero := "peashooter"
var hat := "none"
var pet := "none"
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size / 2
	draw_circle(c, minf(size.x, size.y) * 0.48, Color(0.3, 0.6, 0.35, 0.25))
	var k := size.y / 150.0  # sprite scale for this box
	var feet := Vector2(size.x * 0.56, size.y - 20 * k)
	var walking := fmod(_t, 4.0) > 2.0
	var bob := -absf(sin(_t * 13)) * 3.0 if walking else sin(_t * 2.6) * 0.3
	# shadow
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.33))
	draw_circle(Vector2.ZERO, 26 * k, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# pet (behind, a little to the left)
	var pe: Dictionary = Sprites.atlas.get("pets", {}).get(pet, {})
	if not pe.is_empty():
		var pframe := (4 + int(_t * 10) % 6) if walking else int(_t * 3) % 4
		var flying := pet in ["bee", "butterfly", "dragon"]
		var pp := feet + Vector2(-58 * k, (-10 if flying else 4) * k + (sin(_t * 5) * 4 * k if flying else 0.0))
		Sprites.draw_frame(self, Sprites.tex(pe.file), pe, pframe, pp, false, 1.15 * k, Color.WHITE, Sprites.scale)
	# hero
	var he: Dictionary = Sprites.hero_entry(hero)
	var frame := (4 + int(_t * 10) % 6) if walking else int(_t * 2.5) % 4
	Sprites.draw_frame(self, Sprites.hero_tex(hero, 0, 0), he, frame, feet, false, 1.15 * k, Color.WHITE, Sprites.scale)
	# hat
	var ha: Dictionary = Sprites.atlas.get("hats", {}).get(hat, {})
	if not ha.is_empty():
		var anchor: Array = Sprites.atlas.hatAnchor.get(hero, [0, -55, 1])
		var hp := feet + Vector2(anchor[0], anchor[1] + bob) * 1.15 * k
		Sprites.draw_frame(self, Sprites.tex(ha.file), ha, 0, hp, false, anchor[2] * 1.15 * k, Color.WHITE, Sprites.scale)
