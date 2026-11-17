class_name ClashWorld
extends SimWorld
## GARDEN CLASH: the three-lane battle mode (port of server/clash.js and the
## Clash part of server/bots.js).
## Your Sproutlings and Bloom Towers vs the pest army, its Thorn Towers and
## rival pest champions. Pest-side units (minions, rivals, Thorn buildings,
## the Thorn Heart, jungle monsters) live in `enemies`, so every hero attack,
## special and reaction already works on them. Your side (Sproutlings, Bloom
## Towers, the Bloom Tree) lives in `cl`.

const LANE_SETS := {1: [1], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 1]}
const BOT_BUY := ["sword", "bark", "sandals", "bow", "rose", "acorn"]
const SHIELD_NAMES := {"gate": "Bloom Gate", "guardian": "Tree Guardian", "tower": "Bloom Tower"}

var C: Dictionary
var FOES: Dictionary
var ALLIES: Dictionary
var cl: Dictionary = {}
var _shot_id := 0
## how often Sproutlings & pest minions look for a new target (seconds);
## 0 = every tick like the browser version (slower to simulate)
var retarget_every := 0.2


func _init(data: GameDataLib) -> void:
	super(data)
	C = D.clash.config
	FOES = D.clash.foes
	ALLIES = D.clash.allies


func is_clash() -> bool:
	return true


func max_level() -> int:
	return int(C.maxLevel)


func xp_needed(level: int) -> float:
	return round(D.xp_to_next(level) * float(C.xpCost))


func cdiff() -> Dictionary:
	return D.clash.difficulty.get(difficulty_id, D.clash.difficulty.normal)


func team_size() -> int:
	return maxi(1, heroes.size())


static func mirror(x: float, y: float) -> Vector2:
	return Vector2(GameDataLib.W - x, GameDataLib.H - y)


# ---------------------------------------------------------------------------
# Lanes
# ---------------------------------------------------------------------------
## Walk `move` pixels along a lane; returns what is left over at the end
static func step_path(u: Dictionary, pts: PackedVector2Array, move: float) -> float:
	while move > 0 and u.seg < pts.size() - 1:
		var a := pts[u.seg]
		var b := pts[u.seg + 1]
		var L := maxf(0.001, a.distance_to(b))
		var left: float = (1.0 - u.t) * L
		if move >= left:
			move -= left
			u.seg += 1
			u.t = 0.0
		else:
			u.t += move / L
			move = 0.0
	return move


## A point on a lane (x, y, angle), shifted sideways by `off`
static func path_point(pts: PackedVector2Array, seg: int, t: float, off: float) -> Vector3:
	var i := mini(seg, pts.size() - 1)
	var a := pts[i]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var d := b - a
	if i >= pts.size() - 1:
		d = a - pts[pts.size() - 2]
	var L := maxf(1.0, d.length())
	var k := 0.0 if i >= pts.size() - 1 else t
	return Vector3(a.x + (b.x - a.x) * k + (-d.y / L) * off, a.y + (b.y - a.y) * k + (d.x / L) * off, atan2(d.y, d.x))


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func start(_map: String, difficulty: String, _game_mode: String) -> void:
	map_id = String(C.mapId)
	difficulty_id = difficulty if D.clash.difficulty.has(difficulty) else "normal"
	mode = "clash"
	endless = false
	wave = 0
	max_wave = 0
	lives = 100
	max_lives = 100
	heroes.clear(); enemies.clear(); projectiles.clear(); suns.clear(); gadgets.clear(); spikes.clear(); marked.clear()
	wisps.clear(); chests.clear(); powerups.clear(); pending_fx.clear(); spawn_queue.clear(); events.clear()
	current_twist = ""
	game_time = 0.0
	_paths.clear()
	for i in D.map(map_id).paths.size():
		_paths.append(D.path_points(map_id, i))
	for p in players.values():
		for k in ["pops", "damage", "specials", "reactions", "gadgets_planted", "combos", "chests", "powerups", "sun",
				"knockouts", "revives", "last_hits", "rival_kos", "towers_down", "items_bought"]:
			p[k] = 0
		p.acorns = 300
		p.acorn_frac = 0.0
		spawn_hero(p, false)
	phase = "playing"
	setup_clash()
	ev({"type": "game_started", "mode": "clash"})


func spawn_hero(p: Dictionary, mid_game: bool) -> void:
	super.spawn_hero(p, mid_game)
	for k in ["knockouts", "revives", "last_hits", "rival_kos", "towers_down", "items_bought"]:
		if not p.has(k):
			p[k] = 0
	var h = hero_of(p.id)
	if h and not h.has("items"):
		h.merge({"items": [], "potions": 0, "dead": false, "respawn_t": 0.0, "revive_t": 0.0, "reviver": -1, "recall_t": 0.0,
			"recall_from": Vector2.ZERO, "hurt_t": 0.0, "last_hurt_at": -99.0, "hp": -1.0, "last_max_hp": 0.0})
		if mid_game and phase == "playing":
			p.acorns = maxi(int(p.acorns), 300)


func setup_clash() -> void:
	var CD := cdiff()
	var n := team_size()
	var ally_base := Vector2(C.allyBase.x, C.allyBase.y)
	var foe_base := Vector2(C.foeBase.x, C.foeBase.y)
	var lanes: Array = []
	for path in D.map(map_id).paths:
		var foe := PackedVector2Array()
		for tile in path:
			foe.append(Vector2((float(tile[0]) + 0.5) * D.TILE, (float(tile[1]) + 0.5) * D.TILE))
		var ally := foe.duplicate()
		ally.reverse()
		ally.insert(0, ally_base + (ally[0] - ally_base) * 0.45)
		foe.insert(0, foe_base + (foe[0] - foe_base) * 0.45)
		lanes.append({"foe": foe, "ally": ally})
	cl = {"time": 0.0, "wave_t": float(C.firstWave), "lanes": lanes, "allies": [], "ally_towers": [], "shots": [], "pending": [],
		"camps": [], "rivals": [], "super_ally": [false, false, false], "super_foe": [false, false, false], "toad_t": 0.0,
		"foe_towers_down": 0, "ally_towers_down": 0, "rival_kos": 0, "rival_lvl_t": 60.0, "regrow": [], "elder_t": 0.0,
		"spawn_q": [], "power": 0.0, "hp_index": 1.0, "p_minion": 1.0, "p_rival": 1.0, "p_camp": 1.0, "p_struct": 1.0,
		"avg_level": 1.0, "power_acc": 0.0, "foe_guard_open": false, "ally_guard_open": false}
	for c in D.clash.camps:
		cl.camps.append({"id": c.id, "kind": c.kind, "x": float(c.x), "y": float(c.y), "count": int(c.count),
			"respawn_t": float(FOES[c.kind].firstAt), "alive": 0, "elder": false})
	var struct_mult := struct_hp_mult()
	for t in C.allyTowers:
		_add_ally_tower("tower", int(t.lane), int(t.tier), t.x, t.y, float(C.towerRange), 30.0)
	for g in C.gates:
		_add_ally_tower("gate", int(g.lane), 3, g.x, g.y, 0.0, 34.0)
	for g in C.guardians:
		_add_ally_tower("guardian", -1, 4, g.x, g.y, float(C.towerRange), 30.0)
	var sc: Vector2 = D.sanctuary(map_id)
	var tree_hp: float = round(float(C.coreHp) * float(CD.allyTower))
	cl.ally_towers.append({"id": gen_id(), "kind": "tree", "lane": -1, "tier": 5, "x": sc.x, "y": sc.y - 10, "hp": tree_hp, "max_hp": tree_hp,
		"range": float(C.coreRange), "cd": 1.0, "radius": 52.0, "flash": 0.0, "shield": false, "angle": 0.0, "alert_at": -99.0})
	for t in C.allyTowers:
		_add_foe_building("thorntower", 2 - int(t.lane), int(t.tier), t.x, t.y, _hp_for(int(t.tier)) * struct_mult, float(C.towerRange))
	for g in C.gates:
		_add_foe_building("thorngate", 2 - int(g.lane), 3, g.x, g.y, _hp_for(3) * struct_mult, 0.0)
	for g in C.guardians:
		_add_foe_building("thornguard", -1, 4, g.x, g.y, _hp_for(4) * struct_mult, float(C.towerRange))
	var heart := make_foe("thornheart", float(C.foeBase.x), float(C.foeBase.y), round(float(C.coreHp) * struct_mult))
	heart.range = float(C.coreRange)
	heart.lane = -1
	heart.tier = 5
	enemies.append(heart)
	update_shields()
	# Rival pest champions: one per hero, plus extras on harder difficulties
	var extra := int(D.gnum(CD, "soloRivals")) if n == 1 else int(D.gnum(CD, "extraRivals"))
	var order: Array = D.clash.rivalOrder.duplicate()
	var count := clampi(n + extra, 1, mini(int(CD.maxRivals), order.size()))
	var lanes_for: Array = LANE_SETS.get(count, [0, 1, 2])
	order.shuffle()  # a different mix of rivals every game
	for i in count:
		cl.rivals.append({"kind": order[i], "lane": lanes_for[i], "alive": false, "respawn_t": 14.0 + i * 2, "id": -1, "lvl": 1, "first": true})
	wave_active = true  # sky Sun drops keep working
	sync_tree_lives()
	ev({"type": "clash_start"})


func _hp_for(tier: int) -> float:
	match tier:
		1: return float(C.towerHp)
		2: return float(C.towerHp) * 1.3
		3: return float(C.gateHp)
	return float(C.guardianHp)


func _add_ally_tower(kind: String, lane: int, tier: int, x, y, range: float, radius: float) -> void:
	var hp: float = round(_hp_for(tier) * float(cdiff().allyTower))
	cl.ally_towers.append({"id": gen_id(), "kind": kind, "lane": lane, "tier": tier, "x": float(x), "y": float(y), "hp": hp, "max_hp": hp,
		"range": range, "cd": 1.0, "radius": radius, "flash": 0.0, "shield": false, "angle": 0.0, "alert_at": -99.0})


func _add_foe_building(type: String, lane: int, tier: int, x0, y0, hp: float, range: float) -> Dictionary:
	var m := mirror(float(x0), float(y0))
	var e := make_foe(type, m.x, m.y, round(hp))
	e.lane = lane
	e.tier = tier
	e.range = range
	enemies.append(e)
	return e


## Pest building health for this difficulty and team size (big teams get extra)
func struct_hp_mult() -> float:
	var CD := cdiff()
	var n := team_size()
	return float(CD.structHp) * (1.0 + D.gnum(CD, "teamStruct", 0.5) * (n - 1) + D.gnum(CD, "teamStructBig") * maxi(0, n - 2))


## Bark: divides the damage buildings take (it thickens as the heroes grow)
func bark(side: String) -> float:
	return float(cl.get("p_minion", 1.0)) if side == "ally" else float(cl.get("p_struct", 1.0))


## A pest-side unit, shaped like a normal pest so every hero attack works on it
func make_foe(type: String, x: float, y: float, hp: float) -> Dictionary:
	var def: Dictionary = FOES[type]
	return {"id": gen_id(), "type": type, "clash": true, "structure": def.get("structure", false), "core": def.get("core", false),
		"rival": def.get("rival", false), "neutral": def.get("neutral", false), "minion": def.get("minion", false),
		"path": 0, "seg": 0, "t": 0.0, "progress": 0.0, "x": x, "y": y, "angle": 0.0, "hp": hp, "max_hp": hp,
		"speed": D.gnum(def, "speed"), "radius": float(def.radius), "big": false, "twist_armor": 0.0, "regen": 0.0,
		"reward": D.gnum(def, "xp"), "lives": 0, "camo": false, "armored": def.get("armored", false), "shielded": false,
		"lead": false, "boss": false, "slow": 0.0, "slow_t": 0.0, "freeze_t": 0.0, "stun_t": 0.0, "brittle": 0.0,
		"burn_dps": 0.0, "burn_t": 0.0, "burn_owner": -1, "burn_tower": -1, "flash": 0.0, "sheltered": false, "resist": "",
		"chill_t": 0.0, "sunlit_t": 0.0, "sticky_t": 0.0, "sticky": 0.0, "poison_t": 0.0, "poison_dps": 0.0, "poison_acc": 0.0,
		"poison_owner": -1, "poison_tower": -1, "burrows": false, "burrowed": false, "dug": 0.0, "shaken_t": 0.0,
		"freeze_res": 0.0, "stun_res": 0.0, "soak_t": 0.0, "trap_t": 0.0, "trap_res": 0.0, "abil_t": -1.0, "heal_t": 0.0, "enraged": false,
		"cd": 0.5 + randf() * 0.5, "dmg": D.gnum(def, "dmg"), "rate": D.gnum(def, "rate", 1.0), "range": D.gnum(def, "range", 50.0),
		"lane": 0, "off": 0.0, "tier": 0, "at_end": false, "acorns": D.gnum(def, "acorns"), "lvl": 0, "state": "", "elder": false,
		"anchor_seg": 0, "anchor_t": 0.0, "casting": 0.0, "hit_hero_at": -99.0, "cast_hero": -1, "cast_x": 0.0, "cast_y": 0.0,
		"aggro": -1, "resetting": false, "home": Vector2(x, y), "camp": "", "streak": 0, "streak_id": -1, "retarget": randf() * 0.2, "tgt": {}}


# ---------------------------------------------------------------------------
# Shields, power, regrowing gates
# ---------------------------------------------------------------------------
## Each building is shielded until the one in front of it falls:
## outer tower -> inner tower -> gate -> (any gate down) guardians -> (both down) base.
## A lane whose enemy gate is down sends Super minions.
func update_shields() -> void:
	var foe_s: Array = enemies.filter(func(e): return e.structure and e.hp > 0)
	var ally_s: Array = cl.ally_towers.filter(func(t): return t.hp > 0)
	for l in 3:
		if not cl.foe_guard_open and not foe_s.any(func(o): return o.tier == 3 and o.lane == l):
			cl.foe_guard_open = true
		if not cl.ally_guard_open and not ally_s.any(func(o): return o.tier == 3 and o.lane == l):
			cl.ally_guard_open = true
	for e in foe_s:
		e.sheltered = _shielded(foe_s, e, cl.foe_guard_open)
	for t in ally_s:
		t.shield = _shielded(ally_s, t, cl.ally_guard_open)
	for l in 3:
		cl.super_ally[l] = not foe_s.any(func(o): return o.tier == 3 and o.lane == l)
		cl.super_foe[l] = not ally_s.any(func(o): return o.tier == 3 and o.lane == l)


func _shielded(list: Array, s: Dictionary, guard_open: bool) -> bool:
	match int(s.tier):
		2: return list.any(func(o): return o.tier == 1 and o.lane == s.lane)
		3: return list.any(func(o): return o.tier == 2 and o.lane == s.lane)
		4:
			if guard_open:
				return false
			for l in 3:
				if not list.any(func(o): return o.tier == 3 and o.lane == l):
					return false
			return true
		5: return list.any(func(o): return o.tier == 4)
	return false


## How strong are the heroes now, compared to brand-new level 1 heroes?
## The same formula for every hero type (level, tiers, items, boost cards).
func power_update() -> void:
	var X: Dictionary = C.power
	var p := 0.0
	var hp := 0.0
	var lv := 0.0
	for h in heroes:
		var it_dmg := 0.0
		var it_haste := 0.0
		for id in h.get("items", []):
			var info: Dictionary = D.clash_item(id)
			if not info.is_empty():
				it_dmg += D.gnum(info.def, "dmg") * info.mult
				it_haste += D.gnum(info.def, "haste") * info.mult
		var c: Dictionary = h.cards
		p += (1.0 + 0.045 * (h.level - 1)) * pow(1.35, h.tierA + h.tierB) * (1.0 + it_dmg) * (1.0 + it_haste) * (1.0 + 0.15 * D.gnum(c, "power")) * (1.0 + 0.12 * D.gnum(c, "haste"))
		hp += hero_stats(h).maxHp / float(C.heroHp)
		lv += h.level
	var n := maxf(1.0, heroes.size())
	var P := maxf(1.0, p / n)
	var H := maxf(1.0, hp / n)
	var first: bool = cl.power <= 0
	cl.power = P if first else cl.power + (P - cl.power) * 0.3
	cl.hp_index = H if first else cl.hp_index + (H - cl.hp_index) * 0.3
	cl.p_minion = pow(cl.power, float(X.minion))
	cl.p_rival = pow(cl.power, float(X.rival))
	cl.p_camp = pow(cl.power, float(X.camp))
	cl.p_struct = pow(cl.power, float(X.struct))
	cl.avg_level = lv / n


## Knocked-down gates grow back after a while
func regrow(dt: float) -> void:
	for r in cl.regrow:
		r.t -= dt
	var ready: Array = cl.regrow.filter(func(r): return r.t <= 0)
	if ready.is_empty():
		return
	cl.regrow = cl.regrow.filter(func(r): return r.t > 0)
	for r in ready:
		var g = null
		for x in C.gates:
			if int(x.lane) == (r.lane if r.side == "ally" else 2 - r.lane):
				g = x
		if g == null:
			continue
		if r.side == "ally":
			_add_ally_tower("gate", r.lane, 3, g.x, g.y, 0.0, 34.0)
			ev({"type": "gate_regrow", "side": "ally", "lane": r.lane, "x": float(g.x), "y": float(g.y)})
		else:
			var e := _add_foe_building("thorngate", r.lane, 3, g.x, g.y, float(C.gateHp) * struct_hp_mult(), 0.0)
			ev({"type": "gate_regrow", "side": "foe", "lane": r.lane, "x": e.x, "y": e.y})


func sync_tree_lives() -> void:
	max_lives = 100
	lives = 0
	for t in cl.ally_towers:
		if t.kind == "tree":
			lives = maxi(0, ceili(t.hp / t.max_hp * 100.0))


# ---------------------------------------------------------------------------
# Main tick
# ---------------------------------------------------------------------------
func tick(dt: float, real_dt: float) -> void:
	game_time += dt
	for h in heroes:
		h.special_cd = maxf(0.0, h.special_cd - dt * (2.0 if D.gnum(h.buffs, "dew") > 0 else 1.0))
		for k in ["rally_t", "home_cd", "dash_cd", "dazed_t", "daze_resist"]:
			if h[k] > 0:
				h[k] = maxf(0.0, h[k] - dt)
		if h.moved_t > 0:
			h.moved_t = maxf(0.0, h.moved_t - real_dt)
		for k in h.buffs.keys():
			h.buffs[k] -= dt
			if h.buffs[k] <= 0:
				h.buffs.erase(k)
				h._st = null
				ev({"type": "buff_end", "buff": k, "owner": h.owner, "x": h.x, "y": h.y})
	clash_heroes(dt)
	update_bots(dt)
	update_suns(dt, real_dt)
	update_chests(dt)
	update_powerups(dt)
	clash_update(dt)
	update_marks(dt)
	update_enemies(dt)
	update_pending(dt)
	var auras := compute_auras()
	update_heroes(dt, auras)
	update_projectiles(dt)
	update_wisps(dt)
	update_spikes(dt)
	for e in enemies:
		if e.hp <= 0:
			e.tgt = {}  # no reference cycles left behind
	enemies = enemies.filter(func(e): return e.hp > 0)
	check_end()


func clash_update(dt: float) -> void:
	cl.time += dt
	cl.power_acc -= dt
	if cl.power_acc <= 0 or cl.power <= 0:
		cl.power_acc = 1.0
		power_update()
	cl.toad_t = maxf(0.0, cl.toad_t - dt)
	cl.elder_t = maxf(0.0, cl.elder_t - dt)
	# Sproutling waves from both bases
	cl.wave_t -= dt
	if cl.wave_t <= 0:
		cl.wave_t = float(C.waveEvery)
		spawn_wave()
	for s in cl.spawn_q:
		s.t -= dt
	while cl.spawn_q.size() > 0 and cl.spawn_q[0].t <= 0:
		var s: Dictionary = cl.spawn_q.pop_front()
		if s.team == "ally":
			spawn_ally(s.kind, s.lane, s.idx)
		else:
			spawn_foe_minion(s.kind, s.lane, s.idx)
	# Rival champions come back after a while
	cl.rival_lvl_t -= dt
	for r in cl.rivals:
		if r.alive:
			continue
		r.respawn_t -= dt
		if r.respawn_t <= 0:
			spawn_rival(r)
	if cl.rival_lvl_t <= 0:
		cl.rival_lvl_t = 45.0
		for e in enemies:
			if e.rival and e.hp > 0:
				level_rival(e)
	# Jungle camps
	for camp in cl.camps:
		if camp.alive > 0:
			continue
		camp.respawn_t -= dt
		if camp.respawn_t <= 0:
			spawn_camp(camp)
	# Passive acorns for everyone
	for p in players.values():
		p.acorn_frac += float(C.passiveAcorns) * dt
		if p.acorn_frac >= 1:
			var whole := int(floor(p.acorn_frac))
			p.acorn_frac -= whole
			p.acorns += whole
	regrow(dt)
	update_shields()
	allies_act(dt)
	ally_towers_act(dt)
	shots_act(dt)
	clash_pending(dt)
	for u in cl.allies:
		if u.hp <= 0:
			u.tgt = null  # no reference cycles left behind
	cl.allies = cl.allies.filter(func(u): return u.hp > 0)
	cl.ally_towers = cl.ally_towers.filter(func(t): return t.hp > 0 or t.kind == "tree")
	sync_tree_lives()


func wave_scale(team: String) -> Dictionary:
	var w := wave
	var CD := cdiff()
	var n := team_size()
	var pm: float = cl.p_minion
	if team == "ally":
		return {"hp": (1.0 + 0.02 * w) * pm, "dmg": (1.0 + 0.015 * w) * pm}
	# the pest army grows a little faster: lanes without a hero slowly get pushed back
	var team2: float = 1.0 + float(CD.teamHp) * (n - 1)
	return {"hp": (1.0 + 0.026 * w) * pm * float(CD.foeHp) * team2, "dmg": (1.0 + 0.02 * w) * pm * float(CD.foeDmg) * (1.0 + 0.08 * (n - 1))}


func spawn_wave() -> void:
	wave += 1
	var siege := wave % 3 == 0
	for lane in 3:
		var ally_kinds := ["budling", "budling", "budling", "peapod", "peapod"]
		var foe_kinds := ["grunt", "grunt", "grunt", "stinger", "stinger"]
		if siege:
			ally_kinds.append("pumpkin")
			foe_kinds.append("shellcart")
		for i in ally_kinds.size():
			cl.spawn_q.append({"t": i * 0.55, "team": "ally", "kind": ally_kinds[i], "lane": lane, "idx": i})
		for i in foe_kinds.size():
			cl.spawn_q.append({"t": i * 0.55, "team": "foe", "kind": foe_kinds[i], "lane": lane, "idx": i})
	cl.spawn_q.sort_custom(func(a, b): return a.t < b.t)
	ev({"type": "clash_wave", "wave": wave, "siege": siege})


func spawn_ally(kind: String, lane: int, idx: int) -> void:
	if cl.allies.size() >= 90:
		return
	var def: Dictionary = ALLIES[kind]
	var sc := wave_scale("ally")
	var hp_m := 1.0
	var dmg_m := 1.0
	var big := false
	if cl.super_ally[lane] and kind == "budling":
		hp_m *= 2.2
		dmg_m *= 1.8
		big = true
	if cl.toad_t > 0:
		hp_m *= 2.0 if cl.elder_t > 0 else 1.5
		dmg_m *= 1.8 if cl.elder_t > 0 else 1.4
		big = true
	var pts: PackedVector2Array = cl.lanes[lane].ally
	var hp: float = round(def.hp * sc.hp * hp_m)
	cl.allies.append({"id": gen_id(), "kind": kind, "lane": lane, "seg": 0, "t": 0.0, "off": ((idx % 3) - 1) * 13.0 + (randf() - 0.5) * 6,
		"x": pts[0].x, "y": pts[0].y, "angle": 0.0, "hp": hp, "max_hp": hp, "dmg": def.dmg * sc.dmg * dmg_m, "range": float(def.range),
		"rate": float(def.rate), "speed": float(def.speed), "radius": def.radius * (1.3 if big else 1.0), "ranged": def.get("ranged", false),
		"siege": def.get("siege", false), "big": big, "cd": 0.3, "flash": 0.0, "at_end": false, "retarget": randf() * 0.2, "tgt": null})


func spawn_foe_minion(kind: String, lane: int, idx: int) -> void:
	if enemies.filter(func(e): return e.minion).size() >= 90:
		return
	var def: Dictionary = FOES[kind]
	var sc := wave_scale("foe")
	var big: bool = cl.super_foe[lane] and kind == "grunt"
	var pts: PackedVector2Array = cl.lanes[lane].foe
	var e := make_foe(kind, pts[0].x, pts[0].y, round(def.hp * sc.hp * (2.2 if big else 1.0)))
	e.lane = lane
	e.off = ((idx % 3) - 1) * 13.0 + (randf() - 0.5) * 6
	e.dmg = def.dmg * sc.dmg * (1.8 if big else 1.0)
	e.big = big
	if big:
		e.radius = def.radius * 1.35
	e.reward = round(def.xp * (1.0 + 0.04 * wave))
	e.acorns = float(def.acorns) + floor(wave / 4.0)
	enemies.append(e)


func rival_level() -> int:
	var lv := 1.0
	if heroes.size() > 0:
		lv = 0.0
		for h in heroes:
			lv += h.level
		lv /= heroes.size()
	return maxi(1, int(round(lv)) + int(cdiff().rivalLv))


func rival_stats(kind: String, lvl: int) -> Dictionary:
	var def: Dictionary = FOES[kind]
	var CD := cdiff()
	var n := team_size()
	var ahead: float = lvl - float(cl.avg_level)
	return {"hp": round(def.hp * float(cl.p_rival) * (1.0 + 0.05 * ahead) * float(CD.rivalHp) * (1.0 + 0.12 * (n - 1))),
		# rival hits take about the same bite out of a hero's health all game long
		"dmg": def.dmg * float(cl.hp_index) * (1.0 + 0.05 * ahead) * float(CD.rivalDmg)}


func spawn_rival(slot: Dictionary) -> void:
	var lvl := rival_level()
	var st := rival_stats(slot.kind, lvl)
	var def: Dictionary = FOES[slot.kind]
	var e := make_foe(slot.kind, float(C.foeBase.x) - 50, float(C.foeBase.y) + 50, st.hp)
	e.lane = slot.lane
	e.lvl = lvl
	e.dmg = st.dmg
	e.state = "lane"
	e.abil_t = 3.0 + randf() * 2
	e.reward = 70.0 + 16 * lvl
	e.acorns = 60.0
	slot.alive = true
	slot.id = e.id
	slot.lvl = lvl
	enemies.append(e)
	ev({"type": "rival_spawn", "kind": slot.kind, "name": def.name, "x": e.x, "y": e.y, "lvl": lvl, "first": slot.first})
	slot.first = false


## Rivals keep up with the heroes' levels while they're out
func level_rival(e: Dictionary) -> void:
	var lvl := maxi(e.lvl, rival_level())
	var st := rival_stats(e.type, lvl)
	if st.hp <= e.max_hp and lvl == e.lvl:
		return
	var ratio: float = e.hp / e.max_hp
	e.max_hp = st.hp
	e.hp = maxf(1.0, round(st.hp * ratio))
	e.dmg = st.dmg
	e.lvl = lvl
	e.reward = 70.0 + 16 * lvl


func spawn_camp(camp: Dictionary) -> void:
	var def: Dictionary = FOES[camp.kind]
	var n := team_size()
	var elder: bool = def.get("epic", false) and cl.time >= float(C.elderAt)
	var hp: float = round(def.hp * float(cl.p_camp) * (1.0 + 0.25 * (n - 1)) * (2.2 if elder else 1.0))
	for i in camp.count:
		var a := float(i) / maxf(1.0, camp.count) * TAU
		var r := 34.0 if camp.count > 1 else 0.0
		var e := make_foe(camp.kind, camp.x + cos(a) * r, camp.y + sin(a) * r, hp)
		e.home = Vector2(e.x, e.y)
		e.camp = camp.id
		e.dmg = def.dmg * float(cl.hp_index) * (1.5 if elder else 1.0)
		if elder:
			e.elder = true
			e.big = true
			e.radius = def.radius * 1.3
		e.abil_t = 4.0
		e.reward = round(def.xp * (1.0 + 0.05 * wave) * (2.0 if elder else 1.0))
		e.acorns = float(def.acorns) * (2.0 if elder else 1.0)
		e.angle = PI
		enemies.append(e)
	camp.alive = camp.count
	camp.elder = elder
	ev({"type": "camp_up", "kind": camp.kind, "name": ("Elder " if elder else "") + String(def.name), "x": camp.x, "y": camp.y, "epic": def.get("epic", false), "elder": elder})


# ---------------------------------------------------------------------------
# Targeting helpers. A ref is {t: foe|ally|tower|hero, id}
# ---------------------------------------------------------------------------
func shoot(from: Vector2, ref: Dictionary, kind: String, dmg: float, o: Dictionary = {}) -> void:
	var tgt = resolve(ref)
	if tgt == null:
		return
	var sp: float = o.get("speed", 520.0)
	var ang := atan2(tgt.y - from.y, tgt.x - from.x)
	var muzzle: float = o.get("muzzle", 14.0)
	_shot_id += 1
	cl.shots.append({"id": _shot_id, "kind": kind, "team": o.get("team", "foe"), "x": from.x + cos(ang) * muzzle,
		"y": from.y + sin(ang) * muzzle - float(o.get("lift", 0.0)), "vx": cos(ang) * sp, "vy": sin(ang) * sp, "speed": sp,
		"ref": ref, "obj": tgt, "dmg": dmg, "struct_mult": o.get("structMult", 1.0), "src": o.get("src", ""), "ttl": 2.5, "straight": false})


static func alive(kind: String, obj: Dictionary) -> bool:
	return not obj.dead if kind == "hero" else obj.hp > 0


func resolve(ref: Dictionary):
	var id: int = ref.id
	match String(ref.t):
		"foe":
			for e in enemies:
				if e.id == id:
					return e if e.hp > 0 else null
		"ally":
			for u in cl.allies:
				if u.id == id:
					return u if u.hp > 0 else null
		"tower":
			for t in cl.ally_towers:
				if t.id == id:
					return t if t.hp > 0 else null
		"hero":
			for h in heroes:
				if h.id == id:
					return h if not h.dead else null
	return null


## Buildings shrug off most minion hits: heroes are the real tower breakers
func hit(ref: Dictionary, target: Dictionary, dmg: float, o: Dictionary = {}) -> void:
	var sm: float = o.get("structMult", 1.0)
	match String(ref.t):
		"foe": apply_damage(target, maxf(1.0, round(dmg * (sm if target.structure else 1.0))), -1, -1, {"armorPierce": true, "noReact": true})
		"ally": hurt_ally(target, dmg)
		"tower": hurt_ally_tower(target, dmg * sm)
		"hero": hurt_hero(target, dmg, String(o.get("src", "")))


## Is (x, y) inside one of your towers' range (and that tower isn't busy with
## pest minions)? Rivals and their friends don't like walking in there.
func tower_danger(x: float, y: float, pad := 0.0) -> bool:
	for t in cl.ally_towers:
		if t.hp <= 0 or dist(x, y, t.x, t.y) > t.range + pad:
			continue
		var busy := 0
		for e in enemies:
			if e.minion and e.hp > 0 and dist(e.x, e.y, t.x, t.y) <= t.range:
				busy += 1
				if busy >= 2:
					break
		if busy < 2:
			return true
	return false


## Targets for pest minions & buildings, in priority order: {ref, obj} or {}
func foe_target(e: Dictionary, range: float, heroes_ok: bool) -> Dictionary:
	var best := {}
	var bd := INF
	for u in cl.allies:
		if u.hp <= 0:
			continue
		var d: float = dist(e.x, e.y, u.x, u.y) - u.radius * 0.5
		if d <= range and d < bd:
			bd = d
			best = {"ref": {"t": "ally", "id": u.id}, "obj": u}
	if not best.is_empty():
		return best
	if heroes_ok:
		for h in heroes:
			if h.dead:
				continue
			var d: float = dist(e.x, e.y, h.x, h.y) - 10
			if d <= range and d < bd:
				bd = d
				best = {"ref": {"t": "hero", "id": h.id}, "obj": h}
		if not best.is_empty():
			return best
	if e.structure:
		return {}
	for t in cl.ally_towers:
		if t.hp <= 0 or t.shield:
			continue
		var d: float = dist(e.x, e.y, t.x, t.y) - t.radius * 0.6
		if d <= range and d < bd:
			bd = d
			best = {"ref": {"t": "tower", "id": t.id}, "obj": t}
	return best


## Targets for your Sproutlings & towers: pest minions & rivals, then buildings
func ally_target(u: Dictionary, range: float, prefer_rival: bool):
	var best = null
	var bd := INF
	var structure = null
	var sd := INF
	var rival = null
	for e in enemies:
		if e.neutral or e.hp <= 0 or e.sheltered or not e.get("clash", false):
			continue
		var d: float = dist(u.x, u.y, e.x, e.y) - e.radius * 0.5
		if d > range:
			continue
		if e.structure:
			if d < sd:
				sd = d
				structure = e
			continue
		if prefer_rival and e.rival and cl.time - float(e.hit_hero_at) < 2.5:
			rival = e
		if d < bd:
			bd = d
			best = e
	if rival:
		return rival
	return best if best else structure


# ---------------------------------------------------------------------------
# Your side: Sproutlings & Bloom Towers
# ---------------------------------------------------------------------------
func allies_act(dt: float) -> void:
	for u in cl.allies:
		if u.hp <= 0:
			continue
		if u.flash > 0:
			u.flash -= dt
		u.cd -= dt
		# re-check targets 5 times a second (right away if the last one is gone)
		u.retarget -= dt
		var target = u.tgt
		if target != null and (target.hp <= 0 or target.sheltered or dist(u.x, u.y, target.x, target.y) - target.radius * 0.5 > u.range + 4):
			target = null
			u.retarget = 0.0
		if u.retarget <= 0:
			u.retarget = retarget_every
			target = ally_target(u, u.range + 4, false)
		u.tgt = target
		if target:
			if u.cd <= 0:
				u.cd = 1.0 / u.rate
				var ref := {"t": "foe", "id": target.id}
				if u.ranged:
					shoot(Vector2(u.x, u.y), ref, "pumpkin" if u.siege else "pea", u.dmg, {"team": "ally", "speed": 420.0 if u.siege else 560.0, "structMult": 0.8 if u.siege else 0.35, "lift": 8.0})
				else:
					hit(ref, target, u.dmg, {"structMult": 0.35})
				u.angle = atan2(target.y - u.y, target.x - u.x)
			continue
		var pts: PackedVector2Array = cl.lanes[u.lane].ally
		if not u.at_end:
			var left := step_path(u, pts, u.speed * dt)
			var p := path_point(pts, u.seg, u.t, u.off)
			u.x = p.x
			u.y = p.y
			u.angle = p.z
			if left > 0 or u.seg >= pts.size() - 1:
				u.at_end = true
		else:
			# march right up to the Thorn Heart
			for heart in enemies:
				if heart.core and heart.hp > 0:
					var d := dist(u.x, u.y, heart.x, heart.y)
					if d > heart.radius + u.range * 0.6:
						u.x += (heart.x - u.x) / d * u.speed * dt
						u.y += (heart.y - u.y) / d * u.speed * dt


func ally_towers_act(dt: float) -> void:
	for t in cl.ally_towers:
		if t.hp <= 0:
			continue
		if t.flash > 0:
			t.flash -= dt
		if t.kind == "gate":
			continue  # gates don't shoot
		t.cd -= dt
		if t.cd > 0:
			continue
		var target = ally_target(t, t.range, true)
		if target == null:
			t.cd = 0.2
			continue
		var tree: bool = t.kind == "tree"
		t.cd = 0.85 if tree else 1.1
		t.angle = atan2(target.y - t.y, target.x - t.x)
		var dmg: float = (170.0 if tree else 115.0) * (1.0 + 0.015 * wave) * (float(cl.p_rival) * 0.7 if target.rival else float(cl.p_minion)) * D.gnum(cdiff(), "allyTowerDmg", 1.0)
		var muzzle := Vector2(t.x, t.y - (40 if tree else 46))
		shoot(muzzle, {"t": "foe", "id": target.id}, "treebolt" if tree else "bloom", dmg, {"team": "ally", "speed": 640.0, "muzzle": 6.0})
		ev({"type": "tower_fire", "x": muzzle.x, "y": muzzle.y, "team": "ally"})


func hurt_ally(u: Dictionary, dmg: float) -> void:
	if u.hp <= 0:
		return
	u.hp -= dmg
	u.flash = 0.12
	if u.hp <= 0:
		u.hp = 0.0
		ev({"type": "ally_pop", "x": u.x, "y": u.y, "kind": u.kind})


func hurt_ally_tower(t: Dictionary, dmg: float) -> void:
	if t.hp <= 0 or t.shield:
		return
	t.hp -= dmg / bark("ally")
	t.flash = 0.12
	# Nobody around? Tell the team a building is under attack.
	if cl.time - float(t.alert_at) > 20 and not heroes.any(func(h): return not h.dead and dist(h.x, h.y, t.x, t.y) < 650):
		t.alert_at = cl.time
		ev({"type": "tower_alert", "x": t.x, "y": t.y, "kind": t.kind, "lane": t.lane})
	if t.kind == "tree":
		ev({"type": "tree_hit", "x": t.x, "y": t.y})
		t.hp = maxf(0.0, t.hp)
		return
	if t.hp <= 0:
		t.hp = 0.0
		cl.ally_towers_down += 1
		if t.kind == "gate":
			cl.regrow.append({"side": "ally", "lane": t.lane, "t": float(C.gateRegrow) * D.gnum(cdiff(), "regrow", 1.0)})
		ev({"type": "struct_down", "team": "ally", "x": t.x, "y": t.y, "lane": t.lane, "tier": t.tier, "kind": t.kind, "name": SHIELD_NAMES.get(t.kind, "Bloom Tower")})


# ---------------------------------------------------------------------------
# Heroes: health, knock-outs, revives, recall, the fountain, shop, potions
# ---------------------------------------------------------------------------
func hurt_hero(h: Dictionary, dmg: float, src := "") -> void:
	if h.dead or dmg <= 0:
		return
	h.hp -= dmg
	h.hurt_t = 0.18
	h.last_hurt_at = cl.time
	if h.recall_t > 0:
		h.recall_t = 0.0
		ev({"type": "recall_cancel", "owner": h.owner, "x": h.x, "y": h.y})
	if h.hp <= 0:
		hero_down(h, src)


func hero_down(h: Dictionary, src: String) -> void:
	h.hp = 0.0
	h.dead = true
	# knock-outs last longer later in the battle
	h.respawn_t = clampf(5.0 + h.level * 1.1 + cl.time / 120.0, 6.0, 40.0) * float(cdiff().respawn)
	h.recall_t = 0.0
	h.dazed_t = 0.0
	for k in ["ember", "dew", "juice"]:
		h.buffs.erase(k)
	h._st = null
	var p = players.get(h.owner)
	if p:
		p.knockouts += 1
	ev({"type": "hero_down", "owner": h.owner, "slot": h.slot, "x": h.x, "y": h.y, "name": p.name if p else "A hero", "by": src, "respawn": ceili(h.respawn_t)})


func clash_heroes(dt: float) -> void:
	var tree: Vector2 = D.sanctuary(map_id)
	for h in heroes:
		var st := hero_stats(h)
		if h.hp < 0:
			h.hp = st.maxHp
			h.last_max_hp = st.maxHp
		if h.last_max_hp != st.maxHp:
			# leveling up or buying health also fills up that much health
			if h.last_max_hp > 0 and st.maxHp > h.last_max_hp and not h.dead:
				h.hp += st.maxHp - h.last_max_hp
			h.last_max_hp = st.maxHp
		if h.hurt_t > 0:
			h.hurt_t -= dt
		if h.dead:
			h.respawn_t -= dt
			# A friend standing right next to you brings you back faster than waiting!
			var helper = null
			for o in heroes:
				if o.id != h.id and not o.dead and dist(o.x, o.y, h.x, h.y) <= float(C.reviveRadius):
					helper = o
					break
			if helper:
				h.revive_t += dt
				h.reviver = helper.owner
				if h.revive_t >= float(C.reviveTime) and h.respawn_t > 0:
					h.dead = false
					h.hp = st.maxHp * float(C.reviveHp)
					h.revive_t = 0.0
					h.respawn_t = 0.0
					var rp = players.get(helper.owner)
					var me = players.get(h.owner)
					if rp:
						rp.revives += 1
					ev({"type": "revive", "owner": h.owner, "slot": h.slot, "x": h.x, "y": h.y, "by": rp.name if rp else "", "name": me.name if me else "", "byId": helper.owner})
					ev({"type": "teleport", "owner": h.owner, "slot": h.slot, "fromX": h.x, "fromY": h.y, "x": h.x, "y": h.y})
					continue
			elif h.revive_t > 0:
				h.revive_t = maxf(0.0, h.revive_t - dt * 2)
			if h.respawn_t <= 0:
				var spot := home_spot(h.slot)
				h.dead = false
				h.hp = st.maxHp
				h.x = spot.x
				h.y = spot.y
				h.special_cd = minf(h.special_cd, 3.0)
				ev({"type": "teleport", "owner": h.owner, "slot": h.slot, "fromX": spot.x, "fromY": spot.y, "x": spot.x, "y": spot.y})
				ev({"type": "hero_respawn", "owner": h.owner, "slot": h.slot, "x": spot.x, "y": spot.y})
			continue
		# healing: fountain, regen items, berry juice, Bubble Lily's mist, and a little rest regen
		var heal: float = st.maxHp * D.gnum(st, "regen")
		var mist := 0.0
		for o in heroes:
			if o.dead or o.type != "bubblelily":
				continue
			var os := hero_stats(o)
			if D.gnum(os, "healAura") > 0 and dist(o.x, o.y, h.x, h.y) <= os.range:
				mist = maxf(mist, os.healAura)
		heal += st.maxHp * mist
		if dist(h.x, h.y, tree.x, tree.y) <= float(C.fountainRadius):
			heal += st.maxHp * 0.16
		elif cl.time - float(h.last_hurt_at) > 5:
			heal += st.maxHp * 0.008
		if D.gnum(h.buffs, "juice") > 0:
			heal += st.maxHp * float(D.clash.potion.heal) / float(D.clash.potion.dur)
		if heal > 0:
			h.hp = minf(st.maxHp, h.hp + heal * dt)
		h.hp = minf(h.hp, st.maxHp)
		# recall: stand still for 3 seconds to go home
		if h.recall_t > 0:
			if Vector2(h.x, h.y).distance_to(h.recall_from) > 16:
				h.recall_t = 0.0
				ev({"type": "recall_cancel", "owner": h.owner, "x": h.x, "y": h.y})
			else:
				h.recall_t -= dt
				if h.recall_t <= 0:
					h.recall_t = 0.0
					var spot := home_spot(h.slot)
					ev({"type": "teleport", "owner": h.owner, "slot": h.slot, "fromX": h.x, "fromY": h.y, "x": spot.x, "y": spot.y})
					h.x = spot.x
					h.y = spot.y


## H / B: stand still for 3 seconds to go home
func teleport_home(pid: int) -> void:
	var h = hero_of(pid)
	if h == null or h.dead or h.recall_t > 0:
		return
	var tree: Vector2 = D.sanctuary(map_id)
	if dist(h.x, h.y, tree.x, tree.y) < 200:
		return
	h.recall_t = float(C.recallTime)
	h.recall_from = Vector2(h.x, h.y)
	ev({"type": "recall_start", "owner": h.owner, "slot": h.slot, "x": h.x, "y": h.y, "dur": h.recall_t})


func plant(pid: int, _kind: String, _at := Vector2.INF) -> void:
	gadget_fail(pid, "In Garden Clash you buy items at your Bloom Tree instead of building towers!")


func can_shop(h) -> bool:
	if h == null:
		return false
	if h.dead:
		return true
	var tree: Vector2 = D.sanctuary(map_id)
	return dist(h.x, h.y, tree.x, tree.y) <= float(C.shopRadius)


func buy(pid: int, item_id: String) -> void:
	var h = hero_of(pid)
	var p = players.get(pid)
	if h == null or p == null:
		return
	if not can_shop(h):
		gadget_fail(pid, "Walk back to your Bloom Tree to shop (or press H to recall).")
		return
	var potion: Dictionary = D.clash.potion
	if item_id == potion.id:
		if h.potions >= int(C.maxPotions):
			gadget_fail(pid, "You can carry %d Berry Juices." % int(C.maxPotions))
			return
		if p.acorns < int(potion.cost):
			gadget_fail(pid, "Not enough acorns: Berry Juice costs %d" % int(potion.cost))
			return
		p.acorns -= int(potion.cost)
		h.potions += 1
		ev({"type": "item_bought", "owner": pid, "item": "juice", "x": h.x, "y": h.y})
		return
	var info: Dictionary = D.clash_item(item_id)
	if info.is_empty() or info.golden:
		return
	var def: Dictionary = info.def
	# Already have it? Then buying it again makes it GOLDEN.
	var have := -1
	for i in h.items.size():
		if h.items[i] == def.id or h.items[i] == def.id + "+":
			have = i
	if have >= 0:
		if String(h.items[have]).ends_with("+"):
			gadget_fail(pid, "Your %s is already Golden!" % def.name)
			return
		if p.acorns < int(info.upgradeCost):
			gadget_fail(pid, "Not enough acorns: Golden %s costs %d" % [def.name, int(info.upgradeCost)])
			return
		p.acorns -= int(info.upgradeCost)
		h.items[have] = def.id + "+"
		h._st = null
		ev({"type": "item_bought", "owner": pid, "item": def.id + "+", "golden": true, "x": h.x, "y": h.y, "slot": h.slot})
		return
	if h.items.size() >= int(C.maxItems):
		gadget_fail(pid, "Your %d item slots are full. Sell one first, or make one Golden." % int(C.maxItems))
		return
	if p.acorns < int(def.cost):
		gadget_fail(pid, "Not enough acorns: %s costs %d" % [def.name, int(def.cost)])
		return
	p.acorns -= int(def.cost)
	h.items.append(def.id)
	h._st = null
	p.items_bought += 1
	ev({"type": "item_bought", "owner": pid, "item": def.id, "x": h.x, "y": h.y, "slot": h.slot})


func sell_item(pid: int, index: int) -> void:
	var h = hero_of(pid)
	if h == null or index < 0 or index >= h.items.size():
		return
	if not can_shop(h):
		gadget_fail(pid, "Walk back to your Bloom Tree to sell items.")
		return
	var info: Dictionary = D.clash_item(h.items[index])
	h.items.remove_at(index)
	h._st = null
	var refund := int(floor(D.gnum(info, "spent") * 0.6))
	players[pid].acorns += refund
	ev({"type": "item_sold", "owner": pid, "item": info.get("id", ""), "refund": refund})


func potion(pid: int) -> void:
	var h = hero_of(pid)
	if h == null or h.dead or h.potions <= 0:
		return
	if h.hp >= hero_stats(h).maxHp - 1:
		gadget_fail(pid, "Your health is already full!")
		return
	h.potions -= 1
	h.buffs.juice = float(D.clash.potion.dur)
	ev({"type": "potion", "owner": pid, "x": h.x, "y": h.y})


func use_special(pid: int) -> void:
	var h = hero_of(pid)
	var ready: bool = h != null and h.special_cd <= 0 and not h.dead
	super.use_special(pid)
	if ready and h.type == "bubblelily":
		for o in heroes:
			if not o.dead and dist(o.x, o.y, h.x, h.y) <= 320:
				o.hp = minf(hero_stats(o).maxHp, o.hp + hero_stats(o).maxHp * 0.12)


## Called from apply_damage when a hero hits a pest-side unit
func on_hero_hit(e: Dictionary, tower: int, owner: int, final: float, opts: Dictionary) -> void:
	var h = null
	for x in heroes:
		if x.id == tower:
			h = x
	if h == null or h.dead:
		return
	if e.neutral and e.aggro < 0:
		e.aggro = h.id
		for o in enemies:
			if o.get("camp", "") == e.camp and o.aggro < 0:
				o.aggro = h.id
	var st := hero_stats(h)
	if D.gnum(st, "lifeSteal") > 0:
		h.hp = minf(st.maxHp, h.hp + final * st.lifeSteal * (0.5 if opts.get("isDot", false) else 1.0))
	if D.gnum(h.buffs, "ember") > 0 and not opts.get("isDot", false) and not e.structure:
		e.burn_dps = maxf(e.burn_dps, st.damage * 0.3)
		e.burn_t = maxf(e.burn_t, 2.5)
		e.burn_owner = owner
		e.burn_tower = tower


## Thorn bark: heroes do half damage to pest buildings (double with Elder Toad Power)
func damage_mult(e: Dictionary, tower: int) -> float:
	if not e.get("structure", false):
		return 1.0
	var m := 1.0 / bark("foe")
	if tower >= 0:
		for h in heroes:
			if h.id == tower:
				m *= float(C.heroStructMult) * (2.0 if D.gnum(h.buffs, "elder") > 0 else 1.0)
	return m


## Heroes pick their own targets in the lanes: rivals first, then minions,
## then buildings. Jungle monsters only when you walk right up to them.
func pick_target(t: Dictionary, st: Dictionary, _aura: Dictionary, custom_range := 0.0):
	var r: float = custom_range if custom_range > 0 else st.range
	if not marked.is_empty():
		var m = marked_target(t.x, t.y, r, func(_e): return true)
		if m != null:
			return m
	var best = null
	var best_score := INF
	for e in enemies:
		if e.hp <= 0 or e.sheltered:
			continue
		var d := dist(t.x, t.y, e.x, e.y)
		if d > r + e.radius * 0.5:
			continue
		if e.get("neutral", false) and e.aggro < 0 and d > 175:
			continue
		var score: float = d + (-140.0 if e.get("rival", false) else 0.0) + (520.0 if e.get("structure", false) else 0.0) + (260.0 if e.get("neutral", false) else 0.0)
		if score < best_score:
			best_score = score
			best = e
	return best


## Rivals are shoved straight away; minions back along their lane
func push_back(e: Dictionary, px: float, from := Vector2.ZERO) -> void:
	if e.hp <= 0 or e.get("structure", false) or e.get("neutral", false) or e.sheltered:
		return
	if e.boss:
		px *= 0.35
	if e.get("rival", false):
		var d := maxf(1.0, dist(from.x, from.y, e.x, e.y))
		for k in 6:
			move_free(e, e.x + (e.x - from.x) / d * 200, e.y + (e.y - from.y) / d * 200, px * 0.6 / 6)
		return
	if not e.get("clash", false):
		super.push_back(e, px, from)
		return
	var pts: PackedVector2Array = cl.lanes[e.lane].foe
	var left := px
	while left > 0 and e.seg < pts.size() - 1:
		var L := maxf(1.0, pts[e.seg].distance_to(pts[e.seg + 1]))
		var back: float = e.t * L
		if left <= back:
			e.t -= left / L
			left = 0.0
		else:
			left -= back
			if e.seg == 0:
				e.t = 0.0
				break
			e.seg -= 1
			e.t = 1.0
	var p := path_point(pts, e.seg, e.t, e.off)
	e.x = p.x
	e.y = p.y
	e.progress = e.seg + e.t
	e.at_end = false


# ---------------------------------------------------------------------------
# Pest side (called from update_enemies for every pest-side unit)
# ---------------------------------------------------------------------------
func clash_foe_act(e: Dictionary, dt: float) -> void:
	e.cd -= dt
	if e.structure:
		structure_act(e)
		return
	if e.rival:
		rival_act(e, dt)
		return
	if e.neutral:
		neutral_act(e, dt)
		return
	# minion: re-check targets 5 times a second (right away if the last one is gone)
	e.retarget -= dt
	var target: Dictionary = e.tgt
	if not target.is_empty() and (not alive(target.ref.t, target.obj) or dist(e.x, e.y, target.obj.x, target.obj.y) > e.range + 4 + float(target.obj.get("radius", 10.0))):
		target = {}
		e.retarget = 0.0
	if e.retarget <= 0:
		e.retarget = retarget_every
		target = foe_target(e, e.range + 4, true)
	e.tgt = target
	if not target.is_empty():
		if e.cd <= 0:
			e.cd = 1.0 / e.rate
			var def: Dictionary = FOES[e.type]
			if def.get("ranged", false):
				var siege: bool = def.get("siege", false)
				shoot(Vector2(e.x, e.y), target.ref, "shell" if siege else "sting", e.dmg, {"team": "foe", "speed": 420.0 if siege else 540.0, "structMult": 0.8 if siege else 0.35, "lift": 10.0, "src": def.name})
			else:
				hit(target.ref, target.obj, e.dmg, {"src": def.name, "structMult": 0.35})
			e.angle = atan2(target.obj.y - e.y, target.obj.x - e.x)
		return
	var pts: PackedVector2Array = cl.lanes[e.lane].foe
	var slow := maxf(e.slow, e.sticky if e.sticky_t > 0 else 0.0)
	var speed: float = e.speed * (1.0 - minf(slow, 0.55))
	if not e.at_end:
		var left := step_path(e, pts, speed * dt)
		var p := path_point(pts, e.seg, e.t, e.off)
		e.x = p.x
		e.y = p.y
		e.angle = p.z
		e.progress = e.seg + e.t
		if left > 0 or e.seg >= pts.size() - 1:
			e.at_end = true
	else:
		for t in cl.ally_towers:
			if t.kind == "tree":
				var d := dist(e.x, e.y, t.x, t.y)
				if d > t.radius + e.range * 0.6:
					e.x += (t.x - e.x) / d * speed * dt
					e.y += (t.y - e.y) / d * speed * dt


func structure_act(e: Dictionary) -> void:
	if e.hp <= 0 or e.range <= 0 or e.cd > 0:
		return  # gates don't shoot
	var target := foe_target(e, e.range, true)
	if target.is_empty():
		e.cd = 0.2
		e.streak_id = -1
		return
	e.cd = 0.95 if e.core else 1.15
	var dmg: float
	if target.ref.t == "hero":
		# Thorn Towers hit heroes harder with every shot in a row
		if e.streak_id == target.obj.id:
			e.streak = mini(4, e.streak + 1)
		else:
			e.streak = 0
			e.streak_id = target.obj.id
		# a share of the hero's health, so towers stay scary all game
		dmg = hero_stats(target.obj).maxHp * (0.1 if e.core else 0.075) * (1.0 + 0.35 * e.streak) * float(cdiff().foeDmg)
	else:
		e.streak_id = -1
		dmg = (180.0 if e.core else 125.0) * (1.0 + 0.015 * wave) * float(cl.p_minion)
	var name: String = FOES[e.type].name
	var muzzle := Vector2(e.x, e.y - (50 if e.core else 52))
	shoot(muzzle, target.ref, "heartbolt" if e.core else "thorn", dmg, {"team": "foe", "speed": 600.0, "muzzle": 4.0, "src": name})
	ev({"type": "tower_fire", "x": muzzle.x, "y": muzzle.y, "team": "foe", "atHero": target.obj.owner if target.ref.t == "hero" else -1})


func move_free(e: Dictionary, tx: float, ty: float, step_len: float) -> bool:
	var d := dist(e.x, e.y, tx, ty)
	if d < 1:
		return false
	var k := minf(step_len, d) / d
	var nx: float = e.x + (tx - e.x) * k
	var ny: float = e.y + (ty - e.y) * k
	e.angle = atan2(ty - e.y, tx - e.x)
	if D.is_walkable(map_id, nx, ny):
		e.x = nx
		e.y = ny
	elif D.is_walkable(map_id, nx, e.y):
		e.x = nx
	elif D.is_walkable(map_id, e.x, ny):
		e.y = ny
	else:
		return false
	return true


func rival_act(e: Dictionary, dt: float) -> void:
	var def: Dictionary = FOES[e.type]
	var slow := maxf(e.slow, e.sticky if e.sticky_t > 0 else 0.0)
	var speed: float = e.speed * (1.0 - minf(slow, 0.5))
	e.abil_t -= dt
	if e.casting > 0:
		e.casting -= dt
		if e.burrowed:
			# tunneling toward its target, fast and untouchable
			for h in heroes:
				if h.id == e.cast_hero and not h.dead:
					move_free(e, h.x, h.y, e.speed * 2.3 * dt)
		if e.casting <= 0:
			rival_cast(e)
		return
	var base := Vector2(C.foeBase.x, C.foeBase.y)
	# Low on health: run home to heal
	if e.state == "lane" and e.hp < e.max_hp * 0.28:
		e.state = "retreat"
		ev({"type": "rival_flee", "name": def.name, "x": e.x, "y": e.y})
	if e.state == "retreat" or e.state == "heal":
		if dist(e.x, e.y, base.x, base.y) > 150:
			if not move_free(e, base.x, base.y, speed * 1.1 * dt):
				var p0: Vector2 = cl.lanes[e.lane].foe[0]
				move_free(e, p0.x, p0.y, speed * dt)
		else:
			e.state = "heal"
		if e.state == "heal":
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.14 * dt)
			if e.hp >= e.max_hp * 0.98:
				e.state = "lane"
				e.anchor_seg = 0
				e.anchor_t = 0.0
		return
	# Pick a target: heroes it can safely reach, then Sproutlings, then towers
	var target := {}
	var bd := INF
	for h in heroes:
		if h.dead:
			continue
		var d := dist(e.x, e.y, h.x, h.y)
		if d > e.range + 170 or d >= bd:
			continue
		if d > e.range and tower_danger(h.x, h.y, 10):
			continue
		bd = d
		target = {"ref": {"t": "hero", "id": h.id}, "obj": h, "r": 12.0}
	if target.is_empty():
		for u in cl.allies:
			if u.hp <= 0:
				continue
			var d := dist(e.x, e.y, u.x, u.y)
			if d > e.range + 70 or d >= bd:
				continue
			if d > e.range and tower_danger(u.x, u.y, 10):
				continue
			bd = d
			target = {"ref": {"t": "ally", "id": u.id}, "obj": u, "r": float(u.radius)}
	if target.is_empty() and e.hp > e.max_hp * 0.5:
		for t in cl.ally_towers:
			if t.hp <= 0:
				continue
			if dist(e.x, e.y, t.x, t.y) > e.range + t.radius * 0.6 or tower_danger(t.x, t.y, -t.range + 1):
				continue
			target = {"ref": {"t": "tower", "id": t.id}, "obj": t, "r": float(t.radius)}
			break
	# Specials
	if e.abil_t <= 0:
		var ability: String = def.get("ability", "")
		var reach := 150.0 if ability == "slam" else (300.0 if ability == "volley" else (420.0 if ability == "burrow" else 320.0))
		var closest = null
		var cd := INF
		for h in heroes:
			var d := dist(h.x, h.y, e.x, e.y)
			if not h.dead and d <= reach and d < cd:
				cd = d
				closest = h
		if closest:
			rival_start_cast(e, closest)
			return
	if not target.is_empty():
		var obj: Dictionary = target.obj
		var d := dist(e.x, e.y, obj.x, obj.y)
		if d <= e.range + target.r * 0.5:
			if e.cd <= 0:
				e.cd = 1.0 / e.rate
				e.angle = atan2(obj.y - e.y, obj.x - e.x)
				if target.ref.t == "hero":
					e.hit_hero_at = cl.time
				if def.get("melee", false):
					hit(target.ref, obj, e.dmg, {"src": def.name, "structMult": 0.6})
					ev({"type": "rival_swipe", "x": e.x, "y": e.y, "tx": obj.x, "ty": obj.y})
				else:
					shoot(Vector2(e.x, e.y), target.ref, "sting" if def.get("ability", "") == "volley" else "spore", e.dmg, {"team": "foe", "speed": 560.0, "lift": 20.0, "src": def.name, "structMult": 0.6})
			return
		move_free(e, obj.x, obj.y, speed * dt)
		return
	# No fight: walk the lane with the pest minions, stopping before your towers
	var pts: PackedVector2Array = cl.lanes[e.lane].foe
	var front := -1.0
	for m in enemies:
		if m.minion and m.lane == e.lane and m.hp > 0 and m.progress > front:
			front = m.progress
	var anchor_prog: float = e.anchor_seg + e.anchor_t
	var hold_at := front - 0.25 if front >= 0 else 1.2
	if anchor_prog < hold_at:
		var probe := {"seg": e.anchor_seg, "t": e.anchor_t}
		step_path(probe, pts, speed * dt)
		var p := path_point(pts, probe.seg, probe.t, 0.0)
		if not tower_danger(p.x, p.y, 20):
			e.anchor_seg = probe.seg
			e.anchor_t = probe.t
	var ap := path_point(pts, e.anchor_seg, e.anchor_t, -18.0)
	if dist(e.x, e.y, ap.x, ap.y) > 6:
		move_free(e, ap.x, ap.y, speed * dt)


func rival_start_cast(e: Dictionary, h: Dictionary) -> void:
	var def: Dictionary = FOES[e.type]
	e.abil_t = float(def.abilityCd)
	e.cast_x = h.x
	e.cast_y = h.y
	e.cast_hero = h.id
	match String(def.get("ability", "")):
		"slam":
			e.casting = 0.75
			ev({"type": "slam_warn", "x": e.x, "y": e.y, "r": 140, "delay": 0.75})
		"volley":
			e.casting = 0.35
			ev({"type": "volley_warn", "x": e.x, "y": e.y, "tx": h.x, "ty": h.y})
		"burrow":
			e.casting = 1.5
			e.burrowed = true
			e.sheltered = true
			ev({"type": "mole_down", "x": e.x, "y": e.y, "rival": true})
		_:
			e.casting = 0.2
			cl.pending.append({"t": 1.15, "kind": "spores", "x": h.x, "y": h.y, "r": 105.0, "dmg": e.dmg * 2.0, "src": def.name})
			ev({"type": "spore_warn", "x": h.x, "y": h.y, "r": 105, "delay": 1.15, "fromX": e.x, "fromY": e.y})


func rival_cast(e: Dictionary) -> void:
	var def: Dictionary = FOES[e.type]
	match String(def.get("ability", "")):
		"burrow":
			# pop up right under the hero!
			e.burrowed = false
			e.sheltered = false
			ev({"type": "mole_up", "x": e.x, "y": e.y, "rival": true})
			slam(e.x, e.y, 115, e.dmg * 2.1, def.name, 0.8)
		"slam":
			slam(e.x, e.y, 140, e.dmg * 2.2, def.name, 1.0)
		"volley":
			var tx: float = e.cast_x
			var ty: float = e.cast_y
			for h in heroes:
				if h.id == e.cast_hero and not h.dead:
					tx = h.x
					ty = h.y
			var base_a := atan2(ty - e.y, tx - e.x)
			for off in [-0.3, 0.0, 0.3]:
				var a: float = base_a + off
				_shot_id += 1
				cl.shots.append({"id": _shot_id, "kind": "bigsting", "team": "foe", "straight": true, "x": e.x + cos(a) * 20,
					"y": e.y + sin(a) * 20 - 20, "vx": cos(a) * 470, "vy": sin(a) * 470, "dmg": e.dmg * 1.6, "ttl": 0.8,
					"radius": 14.0, "src": def.name, "hit": {}, "speed": 470.0})
			ev({"type": "volley", "x": e.x, "y": e.y})


## A ground slam: hurts heroes & Sproutlings nearby and makes heroes dizzy
func slam(x: float, y: float, r: float, dmg: float, src: String, daze: float) -> void:
	for h in heroes:
		if h.dead or dist(h.x, h.y, x, y) > r + 14:
			continue
		hurt_hero(h, dmg, src)
		if daze > 0 and not h.dead and h.daze_resist <= 0:
			h.dazed_t = daze
			h.daze_resist = daze + 2
			ev({"type": "hero_dazed", "x": h.x, "y": h.y, "owner": h.owner})
	for u in cl.allies:
		if u.hp > 0 and dist(u.x, u.y, x, y) <= r + u.radius:
			hurt_ally(u, dmg * 0.7)
	ev({"type": "slam", "x": x, "y": y, "r": r})


func clash_pending(dt: float) -> void:
	var keep: Array = []
	for p in cl.pending:
		p.t -= dt
		if p.t > 0:
			keep.append(p)
			continue
		if p.kind == "spores":
			for h in heroes:
				if h.dead or dist(h.x, h.y, p.x, p.y) > p.r:
					continue
				hurt_hero(h, p.dmg, p.src)
				if not h.dead and h.daze_resist <= 0:
					h.dazed_t = 1.3
					h.daze_resist = 3.3
					ev({"type": "hero_dazed", "x": h.x, "y": h.y, "owner": h.owner})
			for u in cl.allies:
				if u.hp > 0 and dist(u.x, u.y, p.x, p.y) <= p.r:
					hurt_ally(u, p.dmg * 0.6)
			ev({"type": "spore_burst", "x": p.x, "y": p.y, "r": p.r})
		elif p.kind == "pound":
			slam(p.x, p.y, p.r, p.dmg, p.src, 0.8)
	cl.pending = keep


## Jungle monsters: sleepy until you hit them, then they chase you a little
func neutral_act(e: Dictionary, dt: float) -> void:
	var def: Dictionary = FOES[e.type]
	var h = null
	if e.aggro >= 0:
		for x in heroes:
			if x.id == e.aggro:
				h = x
		if h == null or h.dead or Vector2(h.x, h.y).distance_to(e.home) > 460:
			# lost them: walk home and heal up
			e.aggro = -1
			e.resetting = true
			h = null
	if e.resetting or h == null:
		if Vector2(e.x, e.y).distance_to(e.home) > 4:
			move_free(e, e.home.x, e.home.y, e.speed * 1.4 * dt)
		else:
			e.resetting = false
		e.hp = minf(e.max_hp, e.hp + e.max_hp * (0.25 if e.resetting else 0.05) * dt)
		return
	if def.get("epic", false):
		e.abil_t -= dt
		if e.abil_t <= 0 and dist(h.x, h.y, e.x, e.y) < 170:
			e.abil_t = 6.0
			cl.pending.append({"t": 0.7, "kind": "pound", "x": e.x, "y": e.y, "r": 150.0, "dmg": e.dmg * 1.6, "src": def.name})
			ev({"type": "slam_warn", "x": e.x, "y": e.y, "r": 150, "delay": 0.7})
	if dist(e.x, e.y, h.x, h.y) <= e.range + 12:
		if e.cd <= 0:
			e.cd = 1.0 / e.rate
			e.angle = atan2(h.y - e.y, h.x - e.x)
			if def.get("ranged", false):
				shoot(Vector2(e.x, e.y), {"t": "hero", "id": h.id}, "spit", e.dmg, {"team": "foe", "speed": 480.0, "lift": 10.0, "src": def.name})
			else:
				hurt_hero(h, e.dmg, def.name)
		return
	move_free(e, h.x, h.y, e.speed * dt)


# ---------------------------------------------------------------------------
# Shots (both teams)
# ---------------------------------------------------------------------------
func shots_act(dt: float) -> void:
	var keep: Array = []
	for s in cl.shots:
		s.ttl -= dt
		if s.ttl <= 0:
			continue
		if s.straight:
			# dodgeable stingers: hit the first hero or Sproutling they touch
			s.x += s.vx * dt
			s.y += s.vy * dt
			var got := false
			for h in heroes:
				if h.dead or s.hit.has(h.id) or dist(h.x, h.y - 14, s.x, s.y) > s.radius + 18:
					continue
				s.hit[h.id] = true
				hurt_hero(h, s.dmg, s.src)
				got = true
				break
			if not got:
				for u in cl.allies:
					if u.hp <= 0 or dist(u.x, u.y, s.x, s.y) > s.radius + u.radius:
						continue
					hurt_ally(u, s.dmg * 0.6)
					got = true
					break
			if not got:
				keep.append(s)
			continue
		var tgt: Dictionary = s.obj
		if not alive(s.ref.t, tgt):
			continue
		var ty: float = tgt.y - (14.0 if s.ref.t == "hero" else (30.0 if s.ref.t == "tower" else 0.0))
		var d := dist(s.x, s.y, tgt.x, ty)
		var step_len: float = s.speed * dt
		if d <= step_len + 8:
			hit(s.ref, tgt, s.dmg, {"structMult": s.struct_mult, "src": s.src})
			if s.kind == "pumpkin" or s.kind == "shell":
				ev({"type": "explosion", "x": tgt.x, "y": tgt.y, "radius": 34, "kind": "boom", "small": true})
			continue
		s.vx = (tgt.x - s.x) / d * s.speed
		s.vy = (ty - s.y) / d * s.speed
		s.x += s.vx * dt
		s.y += s.vy * dt
		keep.append(s)
	cl.shots = keep


# ---------------------------------------------------------------------------
# Defeats, rewards, the end
# ---------------------------------------------------------------------------
func on_defeated(e: Dictionary, killer_id: int) -> void:
	if not e.get("clash", false):
		super.on_defeated(e, killer_id)
		return
	var def: Dictionary = FOES[e.type]
	var killer = players.get(killer_id)
	if killer:
		killer.pops += 1
	if e.minion:
		# Last hit: full XP & acorns. Heroes close by share the XP.
		if killer:
			grant_xp(killer_id, e.reward)
			killer.acorns += int(round(e.acorns))
			killer.last_hits += 1
		for h in _near(e, 720):
			if h.owner == killer_id:
				continue
			grant_xp(h.owner, e.reward * 0.65)
			players[h.owner].acorn_frac += e.acorns * 0.25
		maybe_drop_powerup(e)
	elif e.rival:
		var slot = null
		for r in cl.rivals:
			if r.id == e.id:
				slot = r
		if slot:
			slot.alive = false
			slot.id = -1
			slot.respawn_t = clampf(12.0 + 1.3 * e.lvl, 12.0, 42.0) * float(cdiff().respawn)
		cl.rival_kos += 1
		if killer:
			killer.rival_kos += 1
		for p in players.values():
			grant_xp(p.id, e.reward)
			p.acorns += int(round(e.acorns if p.id == killer_id else e.acorns * 0.5))
		ev({"type": "rival_down", "kind": e.type, "name": def.name, "x": e.x, "y": e.y, "by": killer.name if killer else "",
			"slot": killer.slot if killer else -1, "back": ceili(slot.respawn_t) if slot else 0})
		spawn_powerup(e.x, e.y, ["giant", "frenzy", "zoom"][randi() % 3])
	elif e.structure:
		if e.core:
			ev({"type": "struct_down", "team": "foe", "x": e.x, "y": e.y, "core": true, "kind": "core", "name": def.name, "by": killer.name if killer else ""})
			return
		cl.foe_towers_down += 1
		if killer:
			killer.towers_down += 1
		for p in players.values():
			grant_xp(p.id, D.gnum(def, "xp") * (1.0 + 0.04 * wave))
			p.acorns += int(D.gnum(def, "acorns"))
		var kind := "gate" if e.tier == 3 else ("guardian" if e.tier == 4 else "tower")
		if kind == "gate":
			cl.regrow.append({"side": "foe", "lane": e.lane, "t": float(C.gateRegrow) * D.gnum(cdiff(), "regrow", 1.0)})
		update_shields()
		var heart_open := kind == "guardian" and not enemies.any(func(o): return o.get("structure", false) and o.hp > 0 and o.tier == 4)
		ev({"type": "struct_down", "team": "foe", "x": e.x, "y": e.y, "lane": e.lane, "tier": e.tier, "kind": kind, "name": def.name, "by": killer.name if killer else "", "heart_open": heart_open})
	elif e.neutral:
		for camp in cl.camps:
			if camp.id == e.camp:
				camp.alive = maxi(0, camp.alive - 1)
				if camp.alive == 0:
					camp.respawn_t = D.gnum(def, "elderRespawn", def.respawn) if e.elder else float(def.respawn)
		var kh = hero_of(killer_id) if killer else null
		if kh == null:
			var near := _near(e, 600)
			kh = near[0] if near.size() > 0 else null
		var kp = players.get(kh.owner) if kh else null
		if kp:
			grant_xp(kp.id, e.reward)
			kp.acorns += int(round(e.acorns))
		for h in _near(e, 700):
			if kh and h.id == kh.id:
				continue
			grant_xp(h.owner, e.reward * 0.6)
			players[h.owner].acorns += int(round(e.acorns * 0.4))
		var buff: String = def.get("buff", "")
		if buff == "toad":
			var b := "elder" if e.elder else "toad"
			var dur: float = D.POWERUPS[b].dur
			cl.toad_t = dur
			if e.elder:
				cl.elder_t = dur
			for h in heroes:
				h.buffs[b] = dur
				h._st = null
				grant_xp(h.owner, e.reward * 0.5)
				players[h.owner].acorns += 150 if e.elder else 60
			ev({"type": "powerup_get", "kind": b, "x": e.x, "y": e.y, "slot": kp.slot if kp else 0, "name": kp.name if kp else "Your team",
				"owner": kp.id if kp else -1, "shared": heroes.size() - 1})
		elif buff != "" and kh:
			kh.buffs[buff] = float(D.POWERUPS[buff].dur)
			kh._st = null
			ev({"type": "powerup_get", "kind": buff, "x": e.x, "y": e.y, "slot": kh.slot, "name": kp.name if kp else "", "owner": kh.owner, "shared": 0})
		ev({"type": "camp_down", "kind": e.type, "name": def.name, "x": e.x, "y": e.y, "epic": def.get("epic", false), "elder": e.elder})
	ev({"type": "enemy_pop", "id": e.id, "x": e.x, "y": e.y, "color": def.get("color", "#A3E635"), "boss": e.rival or def.get("epic", false), "reward": e.reward, "kind": e.type, "structure": e.structure})


func _near(e: Dictionary, r: float) -> Array:
	return heroes.filter(func(h): return not h.dead and dist(h.x, h.y, e.x, e.y) <= r)


func check_end() -> void:
	var heart_alive := false
	for e in enemies:
		if e.get("core", false) and e.hp > 0:
			heart_alive = true
	if not heart_alive:
		phase = "victory"
		ev({"type": "victory", "clash": true})
	elif lives <= 0:
		lives = 0
		phase = "gameover"
		ev({"type": "game_over", "clash": true})


# ---------------------------------------------------------------------------
# Bot Buddies in Garden Clash: push a lane with the Sproutlings, recall when
# hurt, shop at the tree, revive friends, defend buildings
# ---------------------------------------------------------------------------
func update_bots(dt: float) -> void:
	var k := 0
	for p in players.values():
		if not p.is_bot:
			continue
		var h = hero_of(p.id)
		if h == null:
			continue
		if not p.has("brain"):
			p.brain = {"path": [], "pt": 0.0, "tx": -999.0, "ty": -999.0, "card_t": 1.2, "pref": "A" if randf() < 0.5 else "B",
				"mode": "lane", "lane": -1, "lane_t": 0.0, "defend": -1, "defend_t": 0.0}
		var b: Dictionary = p.brain
		b.index = k
		k += 1
		if h.pending > 0 and h.offer.size() > 0 and not p.has("away"):
			b.card_t -= dt
			if b.card_t <= 0:
				b.card_t = 1.0 + randf()
				var pick := -1
				for i in h.offer.size():
					if pick < 0 and h.offer[i].kind == "path" and h.offer[i].path == b.pref:
						pick = i
				for i in h.offer.size():
					if pick < 0 and h.offer[i].kind == "path":
						pick = i
				for i in h.offer.size():
					if pick < 0 and h.offer[i].kind == "stat" and h.offer[i].id != "magnet" and h.offer[i].id != "wisdom":
						pick = i
				pick_card(p.id, maxi(0, pick))
		if h.dead:
			continue
		_bot_special(p, h)
		_bot_clash(p, h, b, dt)


func _bot_special(p: Dictionary, h: Dictionary) -> void:
	if h.special_cd > 0:
		return
	var near := 0
	var big := false
	for e in enemies:
		if e.hp <= 0 or e.sheltered or e.get("neutral", false):
			continue
		var d := dist(e.x, e.y, h.x, h.y)
		if d < 220:
			near += 1
		if d < 300 and (e.boss or e.get("rival", false)):
			big = true
	if near >= 3 or big:
		use_special(p.id)


func _bot_clash(p: Dictionary, h: Dictionary, b: Dictionary, dt: float) -> void:
	var st := hero_stats(h)
	var tree: Vector2 = D.sanctuary(map_id)
	var at_base := dist(h.x, h.y, tree.x, tree.y) < float(C.shopRadius) - 30
	var hp_k: float = h.hp / maxf(1.0, st.maxHp)
	var step_len: float = st.moveSpeed * dt
	if at_base and not p.has("away"):  # a dropped LAN friend's acorns wait for them
		_bot_shop(p, h)
	if hp_k < 0.45 and h.potions > 0 and D.gnum(h.buffs, "juice") <= 0:
		potion(p.id)
	if b.mode == "home" and at_base and hp_k > 0.95:
		b.mode = "lane"
	if b.mode != "home" and hp_k < 0.3:
		b.mode = "home"
	var next := _bot_next_item(h)
	if b.mode != "home" and not at_base and not next.is_empty() and p.acorns >= next.cost + 250 and hp_k < 0.8:
		b.mode = "home"
	# lane choice: the lane with the fewest heroes (re-checked now and then)
	b.lane_t -= dt
	if b.lane < 0 or b.lane_t <= 0:
		b.lane_t = 25.0
		var count := [0, 0, 0]
		for o in heroes:
			if o.id == h.id or o.dead:
				continue
			count[_nearest_lane(o.x, o.y)] += 1
		if b.lane < 0:
			b.lane = [1, 0, 2][b.index % 3]
		var lo: int = count.min()
		if count[b.lane] > lo:
			b.lane = count.find(lo)
	if b.mode == "home":
		if h.recall_t > 0:
			return  # stand still while recalling
		if not at_base and cl.time - float(h.last_hurt_at) > 1.5:
			teleport_home(p.id)
			if h.recall_t > 0:
				return
		_bot_walk(h, b, tree + Vector2(60, -60), step_len)
		return
	# defend a building the pests are attacking (closest bot goes)
	b.defend_t -= dt
	if b.defend_t <= 0:
		b.defend_t = 1.0
		b.defend = -1
		for t in cl.ally_towers:
			if t.hp <= 0 or t.shield:
				continue
			var n := 0
			for e in enemies:
				if (e.minion or e.rival) and e.hp > 0 and dist(e.x, e.y, t.x, t.y) < 330:
					n += 1
			if n < 3:
				continue
			var closer := heroes.any(func(o): return o.id != h.id and not o.dead and dist(o.x, o.y, t.x, t.y) < dist(h.x, h.y, t.x, t.y))
			if not closer:
				b.defend = t.id
				break
	var target := _bot_pickup(h)
	if target != Vector2.INF and target.distance_to(Vector2(h.x, h.y)) > 260:
		target = Vector2.INF
	# revive a knocked-out friend close by (if it's not too dangerous there)
	var down = null
	for o in heroes:
		if not o.dead or not (o.respawn_t > float(C.reviveTime) or o.revive_t > 0) or dist(o.x, o.y, h.x, h.y) >= 650:
			continue
		var risky := false
		for e in enemies:
			if (e.minion or e.rival or (e.structure and e.range > 0)) and e.hp > 0 and dist(e.x, e.y, o.x, o.y) < maxf(260.0, e.range + 30):
				risky = true
				break
		if not risky:
			down = o
			break
	if down and hp_k > 0.4:
		if dist(down.x, down.y, h.x, h.y) < float(C.reviveRadius) - 25:
			return  # stay put until they're back up
		target = Vector2(down.x + 20, down.y + 10)
	var defend = resolve({"t": "tower", "id": b.defend}) if b.defend >= 0 else null
	if target == Vector2.INF and defend:
		var foe = null
		for e in enemies:
			if (e.minion or e.rival) and e.hp > 0 and (foe == null or dist(e.x, e.y, defend.x, defend.y) < dist(foe.x, foe.y, defend.x, defend.y)):
				foe = e
		target = Vector2((foe.x + defend.x) / 2, (foe.y + defend.y) / 2) if foe else Vector2(defend.x, defend.y)
	if target == Vector2.INF:
		# stay a little behind the furthest Sproutling in my lane
		var lead = null
		for u in cl.allies:
			if u.lane == b.lane and (lead == null or u.seg + u.t > lead.seg + lead.t):
				lead = u
		var rival = null
		for e in enemies:
			if e.get("rival", false) and e.hp > 0 and not e.sheltered and dist(e.x, e.y, h.x, h.y) < st.range + 60:
				rival = e
				break
		if lead:
			var d := dist(lead.x, lead.y, h.x, h.y)
			var want := minf(st.range * 0.75, 140.0)
			target = Vector2(lead.x - (lead.x - h.x) / d * want, lead.y - (lead.y - h.y) / d * want) if d > want else Vector2(h.x, h.y)
		else:
			var tw = null
			for t in cl.ally_towers:
				if t.lane == b.lane and t.hp > 0 and (tw == null or t.tier < tw.tier):
					tw = t
			target = Vector2(tw.x, tw.y) if tw else tree + Vector2(100, -100)
		if rival and st.range > 150:
			var a := atan2(h.y - rival.y, h.x - rival.x)
			target = Vector2(rival.x + cos(a) * st.range * 0.85, rival.y + sin(a) * st.range * 0.85)
		# don't stand under a Thorn Tower unless Sproutlings are tanking it
		if _bot_tower_danger(target.x, target.y):
			target = Vector2(h.x - (target.x - h.x) * 0.3, h.y - (target.y - h.y) * 0.3)
	_bot_walk(h, b, target, step_len)


func _nearest_lane(x: float, y: float) -> int:
	var best := 0
	var bd := INF
	for i in cl.lanes.size():
		for pt in cl.lanes[i].foe:
			var d := dist(pt.x, pt.y, x, y)
			if d < bd:
				bd = d
				best = i
	return best


func _bot_tower_danger(x: float, y: float) -> bool:
	for e in enemies:
		if not e.get("structure", false) or e.hp <= 0 or e.range <= 0 or dist(e.x, e.y, x, y) > e.range + 30:
			continue
		var busy := 0
		for u in cl.allies:
			if dist(u.x, u.y, e.x, e.y) <= e.range:
				busy += 1
		if busy < 2 or e.sheltered:
			return true
	return false


## Grab nearby Sun, power-ups and treasure chests first
func _bot_pickup(h: Dictionary) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for s in suns:
		var d := dist(s.x, s.y, h.x, h.y)
		if d < 190 and d < bd:
			bd = d
			best = Vector2(s.x, s.y)
	for pu in powerups:
		var d := dist(pu.x, pu.y, h.x, h.y) - 40
		if d < 260 and d < bd:
			bd = d
			best = Vector2(pu.x, pu.y)
	return best


## Next thing to buy: new items first, then Golden upgrades
func _bot_next_item(h: Dictionary) -> Dictionary:
	var items: Array = h.items
	for id in BOT_BUY:
		if not items.has(id) and not items.has(id + "+") and items.size() < int(C.maxItems):
			return {"id": id, "cost": int(D.clash.items[id].cost)}
	for id in BOT_BUY:
		if items.has(id):
			return {"id": id, "cost": int(D.clash_item(id).upgradeCost)}
	return {}


func _bot_shop(p: Dictionary, h: Dictionary) -> void:
	for k in 3:
		var next := _bot_next_item(h)
		if next.is_empty() or p.acorns < next.cost:
			break
		buy(p.id, next.id)
	if h.potions < 2 and h.items.size() >= 2 and p.acorns >= int(D.clash.potion.cost):
		buy(p.id, D.clash.potion.id)


# ---------------------------------------------------------------------------
# What gets drawn and sent to the other players
# ---------------------------------------------------------------------------
func snapshot() -> Dictionary:
	var s := super.snapshot()
	for o in s.players:
		var p = players.get(o.id)
		if p:
			o.rivalKOs = p.rival_kos
			o.towersDown = p.towers_down
			o.knockouts = p.knockouts
			o.revives = p.revives
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		var o: Dictionary = s.heroes[i]
		o.hp = maxf(0.0, round(h.hp))
		o.maxHp = hero_stats(h).maxHp
		o.dead = h.dead
		o.respawnT = snappedf(h.respawn_t, 0.1) if h.dead else 0.0
		o.revive = snappedf(h.revive_t / float(C.reviveTime), 0.01) if h.dead else 0.0
		o.recall = snappedf(1.0 - h.recall_t / float(C.recallTime), 0.01) if h.recall_t > 0 else 0.0
		o.items = h.items
		o.potions = h.potions
		o.hurt = h.hurt_t > 0
		o.canShop = can_shop(h)
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if not e.get("clash", false):
			continue
		var o: Dictionary = s.enemies[i]
		o.angle = snappedf(e.angle, 0.01)
		o.lvl = e.lvl
		o.tier = e.tier
		o.elder = e.elder
		o.aggro = e.aggro >= 0
		o.fleeing = e.rival and e.state != "lane"
		o.casting = e.casting > 0
		o.lane = e.lane
	s.clash = payload()
	return s


func payload() -> Dictionary:
	var towers: Array = []
	for t in cl.ally_towers:
		towers.append({"id": t.id, "kind": t.kind, "lane": t.lane, "tier": t.tier, "x": roundf(t.x), "y": roundf(t.y),
			"hp": maxf(0.0, round(t.hp)), "maxHp": t.max_hp, "flash": t.flash > 0, "shield": t.shield, "angle": snappedf(t.angle, 0.01)})
	var foe_towers: Array = []
	for e in enemies:
		if e.get("structure", false):
			foe_towers.append({"lane": e.lane, "tier": e.tier, "core": e.core, "hp": maxf(0.0, round(e.hp)), "maxHp": e.max_hp, "shield": e.sheltered})
	var allies: Array = []
	for u in cl.allies:
		allies.append({"id": u.id, "kind": u.kind, "x": roundf(u.x), "y": roundf(u.y), "hp": maxf(0.0, round(u.hp)), "maxHp": u.max_hp,
			"big": u.big, "flash": u.flash > 0})
	var shots: Array = []
	for sh in cl.shots:
		shots.append({"id": sh.id, "kind": sh.kind, "team": sh.team, "x": roundf(sh.x), "y": roundf(sh.y), "vx": roundf(sh.vx), "vy": roundf(sh.vy)})
	var camps: Array = []
	for c in cl.camps:
		var epic: bool = FOES[c.kind].get("epic", false)
		camps.append({"id": c.id, "kind": c.kind, "x": roundf(c.x), "y": roundf(c.y), "up": c.alive > 0,
			"elder": c.elder if c.alive > 0 else (epic and cl.time + c.respawn_t >= float(C.elderAt)), "respawn": 0 if c.alive > 0 else ceili(c.respawn_t)})
	var rivals: Array = []
	for r in cl.rivals:
		var e = resolve({"t": "foe", "id": r.id}) if r.alive else null
		rivals.append({"kind": r.kind, "lane": r.lane, "alive": e != null, "lvl": e.lvl if e else r.lvl, "hp": maxf(0.0, round(e.hp)) if e else 0.0,
			"maxHp": e.max_hp if e else 1.0, "respawn": 0 if e else ceili(maxf(0.0, r.respawn_t)), "state": e.state if e else "down"})
	var regrow_out: Array = []
	for r in cl.regrow:
		regrow_out.append({"side": r.side, "lane": r.lane, "t": ceili(r.t)})
	return {"time": int(cl.time), "nextWave": snappedf(cl.wave_t, 0.1), "toadT": ceili(cl.toad_t), "elderT": ceili(cl.elder_t),
		"bark": snappedf(bark("foe"), 0.01), "power": snappedf(maxf(1.0, cl.power), 0.01), "regrow": regrow_out,
		"superAlly": cl.super_ally.duplicate(), "superFoe": cl.super_foe.duplicate(), "foeTowersDown": cl.foe_towers_down,
		"allyTowersDown": cl.ally_towers_down, "rivalKOs": cl.rival_kos, "allyTowers": towers, "foeTowers": foe_towers,
		"allies": allies, "shots": shots, "camps": camps, "rivals": rivals}
