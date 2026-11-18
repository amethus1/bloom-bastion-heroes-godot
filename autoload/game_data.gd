class_name GameDataLib
extends Node
## All game data (exported from the original JS version as JSON) plus the
## rules that live in functions: walking & pathfinding, hero stats, upgrade
## cards, waves, resistances, tower spots. Autoloaded as `GameData`.

const TILE := 60
const COLS := 36
const ROWS := 22
const W := 2160.0
const H := 1320.0
const VIEW_W := 1200.0
const VIEW_H := 720.0
const BRAMBLE_RADIUS := 150.0

var meta: Dictionary
var heroes: Dictionary
var elements: Dictionary
var enemies: Dictionary
var waves: Dictionary
var maps: Dictionary
var gadgets: Dictionary
var clash: Dictionary
var cosmetics: Dictionary
var difficulties: Dictionary

var HERO_ORDER: Array = []
var TOWERS: Dictionary = {}
var HERO_INFO: Dictionary = {}
var HERO_ELEMENT: Dictionary = {}
var HERO_POWER: Dictionary = {}
var TIER_LEVELS: Array = []
var STAT_CARDS: Dictionary = {}
var STAT_CARD_ORDER: Array = []
var ENEMIES: Dictionary = {}
var REACTIONS: Dictionary = {}
var RESISTS: Dictionary = {}
var RESIST_ORDER: Array = []
var RESIST_MULT := 0.5
var DIFFICULTIES: Dictionary = {}
var TWISTS: Dictionary = {}
var TWIST_ORDER: Array = []
var GADGETS: Dictionary = {}
var GADGET_ORDER: Array = []
var PLAYER_COLORS: Array = []
var POWERUPS: Dictionary = {}
var DASH: Dictionary = {}
## Rare cards for heroes from level 12 on, when the plain stat cards get samey
## (new in this version; they show up among the stat cards with a gold edge)
const CAPSTONE_LEVEL := 12
const CAPSTONES := {
	"catalyst": {"id": "catalyst", "name": "Catalyst Mastery", "icon": "⚗️", "desc": "Reactions you set off hit 30% harder", "max": 1, "capstone": true},
	"echo": {"id": "echo", "name": "Echo Shot", "icon": "🔁", "desc": "15% of your hits echo onto a nearby pest (60% damage)", "max": 1, "capstone": true},
	"acornmagnet": {"id": "acornmagnet", "name": "Acorn Magnet", "icon": "🌰", "desc": "Pests you pop drop 50% more acorns", "max": 1, "capstone": true},
	"roots": {"id": "roots", "name": "Guardian Roots", "icon": "🌳", "desc": "Your towers near your hero fire 15% faster", "max": 1, "capstone": true},
}
const REROLL_COST := 30  # acorns, once the free rerolls are used up
## Optional "Garden Rules" picked before an Adventure / Endless game
const MUTATORS := {
	"twists": {"name": "Oops! All Twists", "icon": "🌀", "desc": "Every wave from wave 3 has a surprise twist."},
	"heroes": {"name": "Hero Mode", "icon": "🦸", "desc": "No towers (Seed Bombs only), but heroes earn 60% more XP, hit 25% harder and use specials more often."},
	"chaos": {"name": "Reaction Chaos", "icon": "⚗️", "desc": "Elemental reactions (Shatter, Melt, Electrocute...) are 50% stronger."},
	"turbo": {"name": "Turbo Garden", "icon": "⏩", "desc": "Heroes walk 40% faster, shots fly 40% faster, and pests come quicker."},
}
const MUTATOR_ORDER := ["twists", "heroes", "chaos", "turbo"]
## Garden Guide tips for pests whose data has no description
const PEST_TIPS := {
	"sprout": "The most common pest. Any hero or tower pops it.",
	"wasp": "Very fast! Frost Ferns, Bubble Lily and other slows help catch it.",
	"beetle": "Armored shell: shrugs off part of every hit, so big hits work best.",
	"camopuff": "Camo: only heroes and towers that can see Camo can hit it (Keen Eyes card, Sniper Sunflower, Sun Blossom's light, Sap Pitcher).",
	"nutknight": "Armored, with a shield that halves damage. Armor Breaker cards and blast cut through.",
	"ironpod": "Lead shell: most attacks barely scratch it. Use blast (Boom Shroom, Puffball Mortar) or armor-piercing hits.",
	"zeppelin": "Wave 10 boss. Drops spore clouds on heroes: step out of the circle! Bursts into beetles and wasps.",
	"dreadblimp": "The big boss. Gets ENRAGED at half health and calls helpers. Everyone focus fire!",
	"slugling": "Tiny and quick: what a Splitter Slug turns into.",
}
## Pests in the Garden Guide's pest book (Adventure and Endless), in the order you meet them
const GUIDE_PESTS := ["sprout", "wasp", "beetle", "camopuff", "goldbug", "nutknight", "slug", "slugling", "puffcap", "mothmedic",
	"zeppelin", "mole", "snoozemoth", "ironpod", "thorntoad", "dreadblimp"]


## Hero elements that set off a reaction together (for the lobby's "Great Team Combo!" badge)
const TEAM_REACTIONS := [["ice", "blast", "❄️💥 SHATTER"], ["ice", "fire", "❄️🔥 MELT"], ["shock", "water", "⚡💧 ELECTROCUTE"],
	["ice", "water", "❄️💧 FLASH FREEZE"], ["shock", "fire", "⚡🔥 OVERLOAD"]]


## Which reactions a team of heroes can set off together
func team_reactions(hero_types: Array) -> Array:
	var els := {}
	for t in hero_types:
		els[String(HERO_ELEMENT.get(String(t), ""))] = true
	var out: Array = []
	for r in TEAM_REACTIONS:
		if els.has(r[0]) and els.has(r[1]):
			out.append(r[2])
	if els.has("sun") and els.size() > 1:
		out.append("☀️ SUNLIT")
	return out

# per-map caches: blocked tiles, path tiles, pest entries
var _blocked: Dictionary = {}
var _path_tiles: Dictionary = {}
var _entries: Dictionary = {}

var loaded := false


func _init() -> void:
	load_all()


func _read(name: String) -> Dictionary:
	var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
	if f == null:
		push_error("Missing data file: %s" % name)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func load_all() -> void:
	if loaded:
		return
	meta = _read("meta")
	heroes = _read("heroes")
	elements = _read("elements")
	enemies = _read("enemies")
	waves = _read("waves")
	maps = _read("maps")
	gadgets = _read("gadgets")
	clash = _read("clash")
	cosmetics = _read("cosmetics")
	difficulties = _read("difficulties")
	HERO_ORDER = heroes.order
	TOWERS = heroes.heroes
	HERO_INFO = heroes.info
	HERO_ELEMENT = heroes.element
	HERO_POWER = heroes.power
	TIER_LEVELS = heroes.tierLevels
	STAT_CARDS = heroes.statCards
	STAT_CARD_ORDER = heroes.statCardOrder
	for id in CAPSTONES:
		STAT_CARDS[id] = CAPSTONES[id]
	DASH = heroes.dash
	ENEMIES = enemies.enemies
	REACTIONS = elements.reactions
	RESISTS = elements.resists
	RESIST_ORDER = elements.resistOrder
	RESIST_MULT = float(elements.resistMult)
	DIFFICULTIES = difficulties.adventure
	TWISTS = difficulties.endless.twists
	TWIST_ORDER = difficulties.endless.twistOrder
	GADGETS = gadgets.gadgets
	GADGET_ORDER = gadgets.order
	PLAYER_COLORS = meta.playerColors
	POWERUPS = cosmetics.powerups
	for id in maps.maps:
		var m: Dictionary = maps.maps[id]
		var b := {}
		for t in m.waterTiles + m.rockTiles:
			b[Vector2i(int(t[0]), int(t[1]))] = true
		_blocked[id] = b
		var pt := {}
		for k in m.pathTiles:
			var parts: PackedStringArray = String(k).split(",")
			pt[Vector2i(int(parts[0]), int(parts[1]))] = true
		_path_tiles[id] = pt
		var es: Array = []
		for e in m.entries:
			es.append(Vector2(e.x, e.y))
		_entries[id] = es
	loaded = true


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
static func gnum(d: Dictionary, key: String, def := 0.0) -> float:
	var v = d.get(key, def)
	if v == null or v is bool:
		return def if v == null else (1.0 if v else 0.0)
	return float(v)


func color(hex: String) -> Color:
	return Color.html(hex)


func player_color(slot: int) -> Color:
	return Color.html(PLAYER_COLORS[slot % PLAYER_COLORS.size()].hex)


func map(id: String) -> Dictionary:
	return maps.maps.get(id, maps.maps.meadow)


func sanctuary(map_id: String) -> Vector2:
	var c = map(map_id).sanctuaryCenter
	return Vector2(c.x, c.y)


func path_points(map_id: String, index: int) -> PackedVector2Array:
	var paths: Array = map(map_id).paths
	var p: Array = paths[index % paths.size()]
	var out := PackedVector2Array()
	for g in p:
		out.append(Vector2((g[0] + 0.5) * TILE, (g[1] + 0.5) * TILE))
	return out


func is_path_tile(map_id: String, c: int, r: int) -> bool:
	return _path_tiles.get(map_id, {}).has(Vector2i(c, r))


func is_blocked_tile(map_id: String, c: int, r: int) -> bool:
	return _blocked.get(map_id, {}).has(Vector2i(c, r))


# ---------------------------------------------------------------------------
# Walking & pathfinding (same rules as the JS version)
# ---------------------------------------------------------------------------
func in_brambles(map_id: String, x: float, y: float, extra := 0.0) -> bool:
	var r := BRAMBLE_RADIUS + extra
	for e in _entries.get(map_id, []):
		if (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y) < r * r:
			return true
	return false


func is_walkable(map_id: String, x: float, y: float) -> bool:
	if x < 14 or y < 14 or x > W - 14 or y > H - 14:
		return false
	if is_blocked_tile(map_id, int(floor(x / TILE)), int(floor(y / TILE))):
		return false
	return not in_brambles(map_id, x, y)


func line_walkable(map_id: String, x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := Vector2(x0, y0).distance_to(Vector2(x1, y1))
	var steps := int(ceil(d / 8.0))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var x := x0 + (x1 - x0) * t
		var y := y0 + (y1 - y0) * t
		if not is_walkable(map_id, x, y) or not is_walkable(map_id, x + 10, y) or not is_walkable(map_id, x - 10, y) \
				or not is_walkable(map_id, x, y + 10) or not is_walkable(map_id, x, y - 10):
			return false
	return true


func _free_tile(map_id: String, c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < COLS and r < ROWS and not is_blocked_tile(map_id, c, r) \
		and not in_brambles(map_id, (c + 0.5) * TILE, (r + 0.5) * TILE, 12)


## Click-to-walk route around water & rocks (A* on the tile grid, then smoothed)
func find_path(map_id: String, sx: float, sy: float, tx: float, ty: float) -> Array:
	if line_walkable(map_id, sx, sy, tx, ty):
		return [Vector2(tx, ty)]
	var sc := int(floor(sx / TILE))
	var sr := int(floor(sy / TILE))
	var ec := int(floor(tx / TILE))
	var er := int(floor(ty / TILE))
	if not _free_tile(map_id, ec, er):
		var best := Vector3i(-1, -1, 999)
		for dr in range(-3, 4):
			for dc in range(-3, 4):
				if _free_tile(map_id, ec + dc, er + dr) and absi(dc) + absi(dr) < best.z:
					best = Vector3i(ec + dc, er + dr, absi(dc) + absi(dr))
		if best.z == 999:
			return []
		ec = best.x
		er = best.y
		tx = (ec + 0.5) * TILE
		ty = (er + 0.5) * TILE
	sc = clampi(sc, 0, COLS - 1)
	sr = clampi(sr, 0, ROWS - 1)
	var n := COLS * ROWS
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var start := sr * COLS + sc
	var goal := er * COLS + ec
	var open: Array = [start]
	g[start] = 0.0
	var found := false
	var guard := 0
	while open.size() > 0 and guard < 5000:
		guard += 1
		var bi := 0
		var bf := INF
		for i in open.size():
			var a: int = open[i]
			var f: float = g[a] + Vector2(a % COLS - ec, a / COLS - er).length()
			if f < bf:
				bf = f
				bi = i
		var cur: int = open[bi]
		open.remove_at(bi)
		if cur == goal:
			found = true
			break
		closed[cur] = 1
		var cc := cur % COLS
		var cr := cur / COLS
		for dr in [-1, 0, 1]:
			for dc in [-1, 0, 1]:
				if dc == 0 and dr == 0:
					continue
				var nc: int = cc + dc
				var nr: int = cr + dr
				if not _free_tile(map_id, nc, nr):
					continue
				if dc != 0 and dr != 0 and (not _free_tile(map_id, cc + dc, cr) or not _free_tile(map_id, cc, cr + dr)):
					continue
				var ni := nr * COLS + nc
				if closed[ni] == 1:
					continue
				var ng := g[cur] + (1.414 if dc != 0 and dr != 0 else 1.0)
				if ng < g[ni]:
					g[ni] = ng
					came[ni] = cur
					if not open.has(ni):
						open.append(ni)
	if not found:
		return [Vector2(tx, ty)]
	var tiles: Array = []
	var at := goal
	while at != -1:
		tiles.append(at)
		at = came[at]
	tiles.reverse()
	var pts: Array = []
	for t in tiles:
		pts.append(Vector2((t % COLS + 0.5) * TILE, (t / COLS + 0.5) * TILE))
	pts[pts.size() - 1] = Vector2(tx, ty)
	var out: Array = []
	var ax := sx
	var ay := sy
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not line_walkable(map_id, ax, ay, pts[j].x, pts[j].y):
			j -= 1
		out.append(pts[j])
		ax = pts[j].x
		ay = pts[j].y
		i = j + 1
	return out


## Closest point on any trail (and how far it is)
func nearest_path_point(map_id: String, x: float, y: float) -> Dictionary:
	var best := {}
	for path in map(map_id).paths:
		for i in path.size() - 1:
			var a := Vector2((path[i][0] + 0.5) * TILE, (path[i][1] + 0.5) * TILE)
			var b := Vector2((path[i + 1][0] + 0.5) * TILE, (path[i + 1][1] + 0.5) * TILE)
			var p := Geometry2D.get_closest_point_to_segment(Vector2(x, y), a, b)
			var d := p.distance_to(Vector2(x, y))
			if best.is_empty() or d < best.d:
				best = {"x": p.x, "y": p.y, "d": d}
	return best


# ---------------------------------------------------------------------------
# Heroes: stats, cards, XP
# ---------------------------------------------------------------------------
func compute_tower_stats(type: String, tier_a: int, tier_b: int) -> Dictionary:
	if not TOWERS.has(type):
		return {}
	var def: Dictionary = TOWERS[type]
	var s: Dictionary = def.baseStats.duplicate(true)
	var apply := func(eff: Dictionary) -> void:
		for k in eff:
			var v = eff[k]
			match k:
				"rangeMult": s.range = s.range * v
				"fireRateMult": s.fireRate = s.fireRate * v
				"projSpeedMult": s.projSpeed = gnum(s, "projSpeed", 400) * v
				"damageMult": s.damage = s.damage * v
				"damageAdd": s.damage = s.damage + v
				"pierceAdd": s.pierce = gnum(s, "pierce", 1) + v
				"sunIntervalMult": s.sunInterval = s.sunInterval * v
				"sunAmountAdd": s.sunAmount = s.sunAmount + v
				"buffSpeedAdd": s.buffSpeed = s.buffSpeed + v
				"buffDamageAdd": s.buffDamage = s.buffDamage + v
				"buffPierceAdd": s.buffPierce = s.buffPierce + v
				"slowAdd": s.slowAmount = minf(0.8, s.slowAmount + v)
				"slowDurationAdd": s.slowDuration = s.slowDuration + v
				"splashMult": s.splashRadius = s.splashRadius * v
				"chainCountAdd": s.chainCount = s.chainCount + v
				"burnDpsAdd": s.burnDps = gnum(s, "burnDps") + v
				"burnDurationAdd": s.burnDuration = gnum(s, "burnDuration", 2.5) + v
				"coneAngleAdd": s.coneAngle = s.coneAngle + v
				_: s[k] = v
	for i in tier_a:
		apply.call(def.paths.A.tiers[i].effects)
	for i in tier_b:
		apply.call(def.paths.B.tiers[i].effects)
	s.range = round(s.range)
	s.damage = round(gnum(s, "damage"))
	return s


## Garden Clash, the full match or ⚡ Quick Clash
static func clash_mode(mode) -> bool:
	return String(mode) == "clash" or String(mode) == "quickclash"


func clash_item(id: String) -> Dictionary:
	var golden := id.ends_with("+")
	var base := id.substr(0, id.length() - 1) if golden else id
	if not clash.items.has(base):
		return {}
	var def: Dictionary = clash.items[base]
	var up: float = round(float(def.cost) * 1.5)
	return {"def": def, "id": id, "baseId": def.id, "golden": golden, "mult": 1.8 if golden else 1.0, "name": ("Golden " if golden else "") + String(def.name),
		"icon": def.icon, "upgradeCost": up, "spent": float(def.cost) + (up if golden else 0.0)}


func compute_hero_stats(type: String, tier_a: int, tier_b: int, cards: Dictionary = {}, level := 1, buffs: Dictionary = {}, items: Array = []) -> Dictionary:
	var s := compute_tower_stats(type, tier_a, tier_b)
	if s.is_empty():
		return s
	var c := cards
	var b := buffs
	var lv: int = maxi(1, level)
	var growth: float = 1.0 + HERO_POWER.growth * (lv - 1)
	var it := {"dmg": 0.0, "hp": 0.0, "speed": 0.0, "range": 0.0, "haste": 0.0, "steal": 0.0, "charge": 0.0, "regen": 0.0}
	for id in items:
		var info := clash_item(id)
		if info.is_empty():
			continue
		for k in it:
			it[k] += gnum(info.def, k) * info.mult
	var clash_buff := (1.25 if gnum(b, "ember") > 0 else 1.0) * (1.2 if gnum(b, "toad") > 0 or gnum(b, "elder") > 0 else 1.0)
	var power: float = (1.0 + 0.15 * gnum(c, "power")) * (1.6 if gnum(b, "giant") > 0 else 1.0) * (1.0 + it.dmg) * clash_buff
	var mul: float = HERO_POWER.damage * growth * power
	s.damage = round(gnum(s, "damage") * mul)
	var haste: float = 1.0 + 0.12 * gnum(c, "haste") + it.haste + (0.15 if gnum(b, "dew") > 0 else 0.0)
	if gnum(s, "fireRate") > 0:
		s.fireRate = s.fireRate * haste
	s.range = round(s.range * HERO_POWER.range * (1.0 + 0.1 * gnum(c, "reach") + it.range))
	if gnum(s, "emberRange") > 0:
		s.emberRange = round(s.emberRange * (1.0 + 0.1 * gnum(c, "reach") + it.range))
	s.moveSpeed = HERO_POWER.moveSpeed * (1.0 + 0.12 * gnum(c, "feet") + it.speed)
	s.pickup = HERO_POWER.pickup * (1.0 + 0.4 * gnum(c, "magnet"))
	s.critChance = gnum(s, "critChance") + 0.08 * gnum(c, "crit")
	s.specialMult = maxf(0.35, (1.0 - 0.15 * gnum(c, "charge")) * (1.0 - it.charge))
	var cfg: Dictionary = clash.config
	s.maxHp = round((cfg.heroHp + cfg.heroHpPerLevel * (lv - 1)) * gnum(cfg.heroHpMult, type, 1.0) + it.hp)
	s.lifeSteal = it.steal
	s.regen = it.regen
	s.spiritAura = 0.1 * gnum(c, "spirit")
	s.xpMult = 1.0 + 0.2 * gnum(c, "wisdom")
	if gnum(c, "camo") > 0:
		s.detectCamo = true
	if gnum(c, "pierce") > 0:
		s.armorPierce = true
	for k in ["pulseDamage", "spikeDamage", "overloadSplash"]:
		if gnum(s, k) > 0:
			s[k] = round(s[k] * mul)
	for k in ["burnDps", "frostDot"]:
		if gnum(s, k) > 0:
			s[k] = s[k] * mul
	if gnum(s, "sunInterval") > 0:
		s.sunInterval = s.sunInterval / (1.0 + 0.12 * gnum(c, "haste"))
	if gnum(b, "giant") > 0:
		s.range = round(s.range * 1.2)
	if gnum(b, "zoom") > 0:
		s.moveSpeed *= 1.7
	if gnum(b, "frenzy") > 0:
		if gnum(s, "fireRate") > 0:
			s.fireRate *= 1.85
		if gnum(s, "pulseInterval") > 0:
			s.pulseInterval /= 1.6
		if gnum(s, "sunInterval") > 0:
			s.sunInterval /= 1.5
	return s


## Which path (evolution) cards a hero may be offered right now
## Automatic level-ups: on these levels the hero waits for you to pick a path
## upgrade (A or B, from the panel on the left); every other level picks a card by itself
const PATH_LEVELS := [2, 4, 6, 8, 11, 14]


## How many of a hero's waiting level-up cards are saved for a path upgrade the player picks
func path_waiting(tier_a: int, tier_b: int, level: int, pending: int) -> int:
	if pending <= 0 or path_card_options(tier_a, tier_b, level).is_empty():
		return 0
	var earned := 0
	for l in PATH_LEVELS:
		if level >= l:
			earned += 1
	return clampi(earned - tier_a - tier_b, 0, pending)


## A kid-friendly name for a trail: where it starts ("the trail from the top-left")
func trail_name(map_id: String, index: int) -> String:
	var n: int = map(map_id).paths.size()
	var pts := path_points(map_id, index)
	if n <= 1 or pts.is_empty():
		return "the trail"
	var d := pts[0] - Vector2(W / 2.0, H / 2.0)
	var v := "top" if d.y < -H * 0.15 else ("bottom" if d.y > H * 0.15 else "")
	var h := "left" if d.x < -W * 0.15 else ("right" if d.x > W * 0.15 else "")
	var side := v + ("-" if v != "" and h != "" else "") + h
	return "the trail from the %s" % side if side != "" else "the middle trail"


func path_card_options(tier_a: int, tier_b: int, level: int) -> Array:
	var out: Array = []
	for path in ["A", "B"]:
		var tier := tier_a if path == "A" else tier_b
		var other := tier_b if path == "A" else tier_a
		var max_allowed := 2 if other >= 3 else 4
		if tier < max_allowed and level >= int(TIER_LEVELS[tier]):
			out.append({"kind": "path", "path": path, "tier": tier + 1})
	return out


func xp_to_next(level: int) -> float:
	return round(30.0 + 24.0 * pow(level, 1.55))


# ---------------------------------------------------------------------------
# Waves (same lists as the JS version; Endless keeps going past 60)
# ---------------------------------------------------------------------------
func wave_spec(n: int) -> Array:
	var g: Array = []
	var add := func(type: String, count: int, interval: float, delay: float) -> void:
		g.append({"type": type, "count": count, "interval": interval, "delay": delay})
	match n:
		1: add.call("sprout", 10, 0.95, 0)
		2:
			add.call("sprout", 14, 0.8, 0); add.call("wasp", 4, 0.9, 5)
		3:
			add.call("sprout", 14, 0.7, 0); add.call("beetle", 5, 1.2, 3)
		4:
			add.call("wasp", 12, 0.65, 0); add.call("beetle", 6, 1.0, 4)
		5:
			add.call("sprout", 16, 0.5, 0); add.call("camopuff", 8, 0.9, 3); add.call("beetle", 6, 0.9, 6)
		6:
			add.call("beetle", 12, 0.85, 0); add.call("nutknight", 4, 1.6, 4)
		7:
			add.call("slug", 5, 1.4, 6); add.call("wasp", 18, 0.45, 0); add.call("camopuff", 12, 0.65, 3)
		8:
			add.call("puffcap", 5, 1.3, 3); add.call("nutknight", 8, 1.2, 0); add.call("ironpod", 4, 1.8, 5)
		9:
			add.call("mothmedic", 3, 2.5, 4); add.call("beetle", 16, 0.55, 0); add.call("camopuff", 14, 0.55, 2); add.call("ironpod", 6, 1.4, 6)
		10:
			add.call("slug", 6, 1.2, 2); add.call("beetle", 12, 0.6, 0); add.call("zeppelin", 1, 1.0, 5)
		_:
			var sc := maxi(1, n - 9)
			add.call("wasp", mini(40, 12 + sc * 2), 0.35, 0)
			add.call("beetle", mini(35, 10 + sc * 2), 0.45, 1.5)
			if n >= 11: add.call("camopuff", mini(28, 8 + sc * 2), 0.45, 2.5)
			if n >= 12: add.call("nutknight", mini(24, 5 + sc), 0.8, 3.5)
			if n >= 13: add.call("ironpod", mini(22, 4 + sc), 0.9, 5)
			add.call("slug", mini(16, 3 + sc), 0.9, 3)
			if n >= 12: add.call("puffcap", mini(14, 2 + sc), 0.9, 4)
			if n >= 13: add.call("mothmedic", mini(8, 1 + sc / 2), 2.2, 6)
			if n >= 11: add.call("mole", mini(16, 2 + sc), 1.0, 2)
			if n >= 12: add.call("snoozemoth", mini(6, 1 + sc / 3), 3.0, 5)
			if n % 5 == 0 and n < 20: add.call("zeppelin", n / 7, 4.0, 6)
			if n == 20:
				add.call("zeppelin", 2, 4.5, 4); add.call("dreadblimp", 1, 1.0, 10)
			if n >= 25 and n % 5 == 0: add.call("dreadblimp", mini(4, maxi(1, (n - 15) / 5)), 5.5, 7)
			if n > 30 and n % 10 == 5: add.call("zeppelin", mini(4, n / 20), 4.0, 4)
	return g


## Elite groups resist one element (same hash as the JS version, so previews match)
func group_resist(wave: int, group_index: int, type: String) -> String:
	if wave < 9 or (ENEMIES.has(type) and ENEMIES[type].get("boss", false)) or type == "goldbug":
		return ""
	var M := 0xFFFFFFFF
	var h := ((wave * 2654435761) & M) ^ ((group_index * 40503) & M) ^ ((type.length() * 9973) & M) ^ ((type.unicode_at(0) * 31) & M)
	h &= M
	h = ((h ^ (h >> 15)) * 2246822519) & M
	h = ((h ^ (h >> 13)) * 3266489917) & M
	h = (h ^ (h >> 16)) & M
	var chance := 22 if wave < 15 else (30 if wave < 25 else 38)
	if h % 100 >= chance:
		return ""
	return RESIST_ORDER[(h / 100) % RESIST_ORDER.size()]


func endless_ramp(wave: int, diff: Dictionary) -> Dictionary:
	var over := maxi(0, wave - int(difficulties.endless.rampStart))
	var base := 1.03 if diff.has("waveExp") else 1.1
	return {"hp": pow(base, over), "speed": 1.0 + minf(0.45, over * 0.012), "count": 1.0 + minf(1.2, over * 0.035)}


func is_twist_wave(wave: int) -> bool:
	if wave < 8:
		return false
	if wave > 50:
		return true
	if wave > 30:
		return wave % 2 == 0
	return wave % 3 == 2


## Final pest groups for a wave (counts scaled for the team; huge waves capped)
## Wave 13 (between the first Spore Zeppelin and the double one; in Endless also
## every 10 waves after) brings the Thornback Toad mini-boss
static func mini_boss_wave(wave: int, endless: bool, short := false) -> bool:
	if short:
		return wave == SHORT_WAVES.size()  # the Short Adventure's finale
	return wave == 13 or (endless and wave > 13 and wave % 10 == 3)


## Short Adventure: six waves with a beginning, one new trick each, and the
## Thornback Toad as the finale. [type, count, seconds apart, start delay]
const SHORT_WAVES := [
	[["sprout", 18, 0.8, 0.0], ["sprout", 10, 0.45, 17.0]],
	[["sprout", 16, 0.7, 0.0], ["wasp", 10, 0.7, 6.0], ["wasp", 8, 0.35, 19.0]],
	[["sprout", 14, 0.7, 0.0], ["camopuff", 8, 1.0, 4.0], ["camopuff", 8, 0.55, 16.0]],
	[["beetle", 10, 1.2, 0.0], ["wasp", 12, 0.5, 8.0], ["sprout", 14, 0.45, 15.0]],
	[["sprout", 24, 0.45, 0.0], ["beetle", 9, 1.1, 4.0], ["camopuff", 9, 0.8, 9.0], ["wasp", 16, 0.35, 15.0]],
	[["sprout", 18, 0.55, 0.0], ["beetle", 10, 1.1, 3.0], ["wasp", 12, 0.45, 14.0], ["camopuff", 8, 0.7, 20.0]],
]
## ...and the new pest each wave shows a card for
const SHORT_INTRO := {2: "wasp", 3: "camopuff", 4: "beetle", 6: "thorntoad"}
const SHORT_ACORNS := 150  # enough to try a tower's level-3 special power


func short_spec(n: int) -> Array:
	var out: Array = []
	for g in SHORT_WAVES[clampi(n - 1, 0, SHORT_WAVES.size() - 1)]:
		out.append({"type": g[0], "count": g[1], "interval": g[2], "delay": g[3]})
	return out


func plan_wave(wave: int, diff: Dictionary, hero_count: int, endless: bool, twist: String, short := false) -> Dictionary:
	var mult := 1.0 + gnum(diff, "teamCount") * (maxi(1, hero_count) - 1)
	if endless:
		mult *= endless_ramp(wave, {}).count
	var tw: Dictionary = TWISTS.get(twist, {})
	if tw.has("countMult"):
		mult *= tw.countMult
	var groups: Array = []
	var spec := short_spec(wave) if short else wave_spec(wave)
	for gi in spec.size():
		var g: Dictionary = spec[gi]
		var boss: bool = ENEMIES.has(g.type) and ENEMIES[g.type].get("boss", false)
		var count: int = g.count if boss else maxi(1, int(round(g.count * mult)))
		groups.append({"type": g.type, "count": count, "delay": g.delay, "interval": g.interval if boss else g.interval * g.count / count, "boss": boss, "resist": group_resist(wave, gi, g.type)})
	var total := 0
	for g in groups:
		if not g.boss:
			total += g.count
	var hp_boost := 1.0
	if total > 300:
		var f := 300.0 / total
		hp_boost = 1.0 / f
		for g in groups:
			if g.boss:
				continue
			var c := maxi(1, int(round(g.count * f)))
			g.interval = g.interval * g.count / c
			g.count = c
	return {"groups": groups, "hpBoost": hp_boost}


# ---------------------------------------------------------------------------
# Towers & traps
# ---------------------------------------------------------------------------
func gadget_upgrade_cost(kind: String, level: int) -> int:
	var def: Dictionary = GADGETS.get(kind, {})
	return int(round(gnum(def, "cost") * (1.0 if level <= 1 else 2.2)))


func gadget_branch(kind: String, branch: int) -> Dictionary:
	var def: Dictionary = GADGETS.get(kind, {})
	if branch < 0 or not def.has("branches") or branch >= def.branches.size():
		return {}
	return def.branches[branch]


## Where a tower/trap goes if the hero stands at (x, y)
func gadget_spot(map_id: String, kind: String, x: float, y: float) -> Dictionary:
	var def: Dictionary = GADGETS.get(kind, {})
	if def.is_empty():
		return {"ok": false, "x": x, "y": y, "reason": "Unknown building"}
	var snap := nearest_path_point(map_id, x, y)
	var gx := x
	var gy := y
	if def.get("onPath", false):
		if snap.is_empty() or snap.d > 110:
			return {"ok": false, "x": x, "y": y, "reason": "Walk right next to a path to set a %s!" % def.name}
		gx = snap.x
		gy = snap.y
	elif not snap.is_empty() and snap.d < 48:
		var pref := atan2(y - snap.y, x - snap.x)
		var dirs: Array = []
		for k in 8:
			dirs.append(k / 8.0 * TAU)
		if snap.d > 1:
			dirs.sort_custom(func(a, b): return absf(angle_difference(pref, a)) < absf(angle_difference(pref, b)))
		var placed := false
		for a in dirs:
			var tx: float = x + cos(a) * (55 - snap.d)
			var ty: float = y + sin(a) * (55 - snap.d)
			if is_walkable(map_id, tx, ty) and nearest_path_point(map_id, tx, ty).d >= 45:
				gx = tx
				gy = ty
				placed = true
				break
		if not placed:
			return {"ok": false, "x": x, "y": y, "reason": "No room for a %s here. Step away from the path a little." % def.name}
	if not def.get("onPath", false) and not is_walkable(map_id, gx, gy):
		return {"ok": false, "x": gx, "y": gy, "reason": "Can't build on water or rocks!"}
	if in_brambles(map_id, gx, gy, 40):
		return {"ok": false, "x": gx, "y": gy, "reason": "Too close to the pest burrow!"}
	if sanctuary(map_id).distance_to(Vector2(gx, gy)) < 90:
		return {"ok": false, "x": gx, "y": gy, "reason": "Too close to the tree!"}
	return {"ok": true, "x": gx, "y": gy}
