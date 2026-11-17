class_name SimWorld
extends RefCounted
## The whole Adventure / Endless game as pure data: no drawing, no nodes.
## The host runs step() at a fixed 30 Hz; snapshot() is what gets drawn and
## sent to the other players. Ported from server/gameEngine.js.

const TICK := 1.0 / 30.0

var D: GameDataLib  # GameData (autoload or a loaded instance)

var map_id := "meadow"
var difficulty_id := "normal"
var mode := "adventure"  # adventure | endless
var endless := false
var auto_wave := false
var speed_mult := 1.0
var paused := false

var phase := "lobby"  # lobby | playing | victory | gameover
var wave := 0
var max_wave := 25
var wave_active := false
var wave_timer := 0.0
var auto_wave_countdown := 0.0
var lives := 40
var max_lives := 40
var game_time := 0.0
var current_twist := ""
var twist_plan := {}
var wave_hp_boost := 1.0
var sky_sun_t := 7.5
var powerup_cd := 8.0
var last_special := {}
var react_fx := {}

var players := {}  # id -> player dict
var heroes: Array = []
var enemies: Array = []
var projectiles: Array = []
var suns: Array = []
var gadgets: Array = []
var spikes: Array = []
var wisps: Array = []
var chests: Array = []
var powerups: Array = []
var pending_fx: Array = []
var spawn_queue: Array = []
var events: Array = []

var _next_id := 1
var _paths: Array = []  # PackedVector2Array per trail


func _init(data: GameDataLib) -> void:
	D = data


func gen_id() -> int:
	_next_id += 1
	return _next_id


func ev(e: Dictionary) -> void:
	events.append(e)


static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))


func diff() -> Dictionary:
	return D.DIFFICULTIES.get(difficulty_id, D.DIFFICULTIES.normal)


# ---------------------------------------------------------------------------
# Players & start
# ---------------------------------------------------------------------------
func add_player(id: int, name: String, hero_type: String, is_bot := false, hat := "none", pet := "none") -> Dictionary:
	var used := {}
	for p in players.values():
		used[p.slot] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	var p := {"id": id, "name": name, "slot": slot, "hero_type": hero_type, "hat": hat, "pet": pet, "is_bot": is_bot,
		"acorns": 60, "acorn_frac": 0.0, "pops": 0, "damage": 0, "specials": 0, "reactions": 0, "gadgets_planted": 0,
		"combos": 0, "chests": 0, "powerups": 0, "sun": 0, "ready": is_bot}
	players[id] = p
	if phase == "playing":
		spawn_hero(p, true)
	return p


func remove_player(id: int) -> void:
	var h = hero_of(id)
	if h:
		heroes.erase(h)
		wisps = wisps.filter(func(w): return w.tower != h.id)
	players.erase(id)


func start(map: String, difficulty: String, game_mode: String) -> void:
	map_id = map if D.maps.maps.has(map) and not D.maps.maps[map].get("clash", false) else "meadow"
	difficulty_id = difficulty if D.DIFFICULTIES.has(difficulty) else "normal"
	mode = game_mode
	endless = mode == "endless"
	var d := diff()
	wave = 0
	max_wave = int(d.maxWave)
	lives = int(d.startLives)
	max_lives = lives
	wave_active = false
	heroes.clear(); enemies.clear(); projectiles.clear(); suns.clear(); gadgets.clear(); spikes.clear()
	wisps.clear(); chests.clear(); powerups.clear(); pending_fx.clear(); spawn_queue.clear(); events.clear()
	twist_plan.clear()
	current_twist = ""
	game_time = 0.0
	_paths.clear()
	for i in D.map(map_id).paths.size():
		_paths.append(D.path_points(map_id, i))
	for p in players.values():
		p.acorns = 60
		for k in ["pops", "damage", "specials", "reactions", "gadgets_planted", "combos", "chests", "powerups", "sun"]:
			p[k] = 0
		spawn_hero(p, false)
	phase = "playing"
	ev({"type": "game_started"})


func home_spot(slot: int) -> Vector2:
	var sc: Vector2 = D.sanctuary(map_id)
	var c := Vector2(D.W / 2, D.H / 2)
	var dvec := c - sc
	var dl := dvec.length()
	var offs := [Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1)]
	var o: Vector2 = offs[slot % 4]
	var p := sc + dvec / maxf(dl, 1.0) * 110.0 + o * 34.0
	if dl < 10:
		p = sc + o * 90.0
	return Vector2(clampf(p.x, 40, D.W - 40), clampf(p.y, 40, D.H - 40))


func spawn_hero(p: Dictionary, mid_game: bool) -> void:
	if hero_of(p.id):
		return
	var at := home_spot(p.slot)
	var h := {"id": gen_id(), "owner": p.id, "slot": p.slot, "type": p.hero_type if D.TOWERS.has(p.hero_type) else "peashooter",
		"x": at.x, "y": at.y, "tierA": 0, "tierB": 0, "cards": {}, "level": 1, "xp": 0.0, "pending": 0, "bonus": 0, "offer": [],
		"target_mode": "first", "pops": 0, "cooldown": 0.3, "angle": 0.0, "shots": 0, "sun_t": 3.5, "pulse_t": 1.5, "beam_t": 4.0,
		"recoil": 0.0, "special_cd": 5.0, "rally_t": 0.0, "home_cd": 0.0, "dash_cd": 0.0, "dazed_t": 0.0, "daze_resist": 0.0,
		"buffs": {}, "facing": 1, "moved_t": 0.0, "spring_t": 40.0, "_st": null}
	if mid_game and heroes.size() > 0:
		var avg := 0.0
		for o in heroes:
			avg += o.level
		h.level = maxi(1, int(round(avg / heroes.size())) - 1)
		h.pending = h.level - 1
	heroes.append(h)
	ensure_offer(h)
	ev({"type": "hero_spawn", "x": h.x, "y": h.y, "slot": p.slot})


func hero_of(pid: int):
	for h in heroes:
		if h.owner == pid:
			return h
	return null


func hero_stats(h: Dictionary) -> Dictionary:
	if h._st == null:
		h._st = D.compute_hero_stats(h.type, h.tierA, h.tierB, h.cards, h.level, h.buffs, h.get("items", []))
	return h._st


# ---------------------------------------------------------------------------
# Player actions (local or from the network)
# ---------------------------------------------------------------------------
func move_hero(pid: int, x: float, y: float) -> void:
	var h = hero_of(pid)
	if h == null or h.get("dead", false) or not D.is_walkable(map_id, x, y):
		return
	var d := dist(h.x, h.y, x, y)
	if d > 260:  # ignore teleport-sized jumps (except right after a dash/teleport)
		return
	if d > 0.4:
		if absf(x - h.x) > 0.3:
			h.facing = 1 if x > h.x else -1
		h.moved_t = 0.16
	h.x = x
	h.y = y


func dash(pid: int, dx: float, dy: float) -> void:
	var h = hero_of(pid)
	if h == null or h.dash_cd > 0 or h.get("dead", false):
		return
	var v := Vector2(dx, dy)
	if v.length() < 0.01:
		return
	v = v.normalized()
	var from := Vector2(h.x, h.y)
	var to := from
	var d := 10.0
	while d <= D.DASH.dist:
		var n: Vector2 = from + v * d
		if not D.is_walkable(map_id, n.x, n.y):
			break
		to = n
		d += 10.0
	if to.distance_to(from) < 25:
		return
	h.x = to.x
	h.y = to.y
	h.dash_cd = float(D.DASH.cooldown)
	if absf(v.x) > 0.2:
		h.facing = 1 if v.x > 0 else -1
	ev({"type": "dash", "owner": pid, "slot": h.slot, "fromX": from.x, "fromY": from.y, "x": to.x, "y": to.y})


func teleport_home(pid: int) -> void:
	var h = hero_of(pid)
	if h == null or h.home_cd > 0:
		return
	var s := home_spot(h.slot)
	ev({"type": "teleport", "owner": pid, "slot": h.slot, "fromX": h.x, "fromY": h.y, "x": s.x, "y": s.y})
	h.x = s.x
	h.y = s.y
	h.home_cd = 18.0


func start_wave() -> void:
	if phase == "playing" and not wave_active:
		start_next_wave()


# ---------------------------------------------------------------------------
# XP, levels, cards
# ---------------------------------------------------------------------------
func xp_needed(level: int) -> float:
	var d := diff()
	var n := maxi(1, heroes.size())
	return round(D.xp_to_next(level) * D.gnum(d, "xpCost", 1.0) * (1.0 + D.gnum(d, "teamXp") * (n - 1)))


func grant_xp(pid: int, amount: float) -> void:
	var h = hero_of(pid)
	if h == null or amount <= 0:
		return
	h.xp += amount * hero_stats(h).xpMult
	while h.xp >= xp_needed(h.level) and h.level < max_level():
		h.xp -= xp_needed(h.level)
		h.level += 1
		h.pending += 1
		h._st = null
		ev({"type": "level_up", "x": h.x, "y": h.y, "slot": h.slot, "level": h.level, "owner": h.owner})
	if h.level >= max_level():
		h.xp = minf(h.xp, xp_needed(h.level))
	ensure_offer(h)


## Overridden by Garden Clash (ClashWorld)
func max_level() -> int:
	return 99


func is_clash() -> bool:
	return false


func clash_foe_act(_e: Dictionary, _dt: float) -> void:
	pass


func damage_mult(_e: Dictionary, _tower: int) -> float:
	return 1.0


func on_hero_hit(_e: Dictionary, _tower: int, _owner: int, _final: float, _opts: Dictionary) -> void:
	pass


func ensure_offer(h: Dictionary) -> void:
	if h.offer.size() > 0 or h.pending <= 0:
		return
	var st := hero_stats(h)
	var opts: Array = D.path_card_options(h.tierA, h.tierB, h.level)
	var base: Dictionary = D.compute_tower_stats(h.type, h.tierA, h.tierB)
	var ids: Array = []
	for id in D.STAT_CARD_ORDER:
		var c: Dictionary = D.STAT_CARDS[id]
		if D.gnum(h.cards, id) >= c.max:
			continue
		if id == "camo" and base.get("detectCamo", false):
			continue
		if id == "pierce" and (base.get("armorPierce", false) or h.type == "boomshroom" or h.type == "voltcactus"):
			continue
		if id == "charge" and st.specialMult <= 0.46:
			continue
		ids.append(id)
	ids.shuffle()
	while opts.size() < 3 and ids.size() > 0:
		opts.append({"kind": "stat", "id": ids.pop_front()})
	if opts.is_empty():
		opts.append({"kind": "stat", "id": "power"})
	h.offer = opts


func pick_card(pid: int, index: int) -> void:
	var h = hero_of(pid)
	if h == null or h.pending <= 0 or index < 0 or index >= h.offer.size():
		return
	var card: Dictionary = h.offer[index]
	var label := ""
	if card.kind == "path":
		var still := false
		for o in D.path_card_options(h.tierA, h.tierB, h.level):
			if o.path == card.path:
				still = true
		if not still:
			return
		if card.path == "A":
			h.tierA += 1
		else:
			h.tierB += 1
		label = D.TOWERS[h.type].paths[card.path].tiers[(h.tierA if card.path == "A" else h.tierB) - 1].name
	else:
		h.cards[card.id] = D.gnum(h.cards, card.id) + 1
		label = D.STAT_CARDS[card.id].name
	h._st = null
	h.pending -= 1
	h.bonus = mini(h.bonus, h.pending)
	h.offer = []
	sync_wisps(h)
	ensure_offer(h)
	ev({"type": "hero_upgraded", "x": h.x, "y": h.y, "slot": h.slot, "label": label, "path": card.get("path", ""), "owner": pid})


# ---------------------------------------------------------------------------
# Waves
# ---------------------------------------------------------------------------
func plan_twist(w: int) -> String:
	if not endless or not D.is_twist_wave(w):
		return ""
	if not twist_plan.has(w):
		var prev: String = twist_plan.get(w - 1, twist_plan.get(w - 2, twist_plan.get(w - 3, "")))
		var options: Array = D.TWIST_ORDER.filter(func(t): return t != prev and w >= D.gnum(D.TWISTS[t], "minWave"))
		twist_plan[w] = options[randi() % options.size()]
	return twist_plan[w]


func start_next_wave() -> void:
	wave += 1
	wave_active = true
	wave_timer = 0.0
	auto_wave_countdown = 0.0
	spawn_queue.clear()
	var npaths := _paths.size()
	var cursor := wave % npaths
	current_twist = plan_twist(wave)
	var plan: Dictionary = D.plan_wave(wave, diff(), heroes.size(), endless, current_twist)
	wave_hp_boost = plan.hpBoost
	for g in plan.groups:
		for i in g.count:
			spawn_queue.append({"type": g.type, "at": g.delay + i * g.interval, "path": cursor % npaths, "resist": g.resist})
			cursor += 1
	if wave >= 3 and (wave % 10 == 5 or randf() < 0.35):
		spawn_queue.append({"type": "goldbug", "at": 3 + randf() * 8, "path": randi() % npaths, "resist": ""})
	spawn_queue.sort_custom(func(a, b): return a.at < b.at)
	ev({"type": "wave_start", "wave": wave, "twist": current_twist, "endless": endless})


func spawn_enemy(type: String, path_index: int, seg := 0, seg_t := 0.0, at = null, resist := "") -> void:
	var def: Dictionary = D.ENEMIES.get(type, {})
	if def.is_empty():
		return
	var d := diff()
	var n_players := maxi(1, players.size())
	var team_ramp := minf(1.0, 0.25 + wave * 0.075)
	var team_part: float = (n_players - 1) * D.gnum(d, "teamHp", 0.6) + maxi(0, n_players - 2) * D.gnum(d, "teamHpBig", 0.3)
	var coop: float = 0.8 + team_part * team_ramp
	var wave_scale := 1.0
	if d.has("waveExp"):
		wave_scale = pow(1.0 + float(d.waveExp), maxi(0, wave - 3))
	elif wave > 12:
		wave_scale = 1.0 + (wave - 12) * D.gnum(d, "waveGrowth", 0.14)
	var ramp: Dictionary = D.endless_ramp(wave, d) if endless else {"hp": 1.0, "speed": 1.0}
	var tw: Dictionary = D.TWISTS.get(current_twist, {})
	var boss: bool = def.get("boss", false)
	var twist_hp: float = 1.0 if boss else D.gnum(tw, "hpMult", 1.0) * wave_hp_boost
	var max_hp: float = round(def.hp * d.hpMult * coop * wave_scale * ramp.hp * twist_hp)
	var pts: PackedVector2Array = _paths[path_index % _paths.size()]
	var pos: Vector2 = at if at != null else pts[0]
	var big: bool = tw.get("big", false) and not boss
	enemies.append({"id": gen_id(), "type": type, "path": path_index % _paths.size(), "seg": seg, "t": seg_t, "progress": seg + seg_t,
		"x": pos.x, "y": pos.y, "angle": 0.0, "hp": max_hp, "max_hp": max_hp,
		"speed": def.speed * d.speedMult * D.gnum(D.map(map_id), "pestSpeed", 1.0) * (1.0 + D.gnum(d, "teamSpeed") * (maxi(1, heroes.size()) - 1) * team_ramp) * ramp.speed * D.gnum(tw, "speedMult", 1.0),
		"radius": def.radius * (1.35 if big else 1.0), "big": big, "twist_armor": D.gnum(tw, "armor"), "regen": D.gnum(tw, "regen"),
		"reward": maxf(4, round(def.reward * d.rewardMult)), "lives": int(def.get("lives", 1)),
		"camo": def.get("camo", false) or (tw.get("camo", false) and not boss), "armored": def.get("armored", false),
		"shielded": def.get("shielded", false), "lead": def.get("lead", false), "boss": boss,
		"slow": 0.0, "slow_t": 0.0, "freeze_t": 0.0, "stun_t": 0.0, "brittle": 0.0, "burn_dps": 0.0, "burn_t": 0.0, "burn_owner": -1, "burn_tower": -1,
		"frost_dps": 0.0, "frost_t": 0.0, "frost_owner": -1, "frost_tower": -1,
		"flash": 0.0, "sheltered": D.in_brambles(map_id, pos.x, pos.y), "resist": "" if boss else resist, "chill_t": 0.0, "sunlit_t": 0.0,
		"sticky_t": 0.0, "sticky": 0.0, "poison_t": 0.0, "poison_dps": 0.0, "poison_acc": 0.0, "poison_owner": -1, "poison_tower": -1,
		"burrows": def.get("burrows", false), "burrowed": false, "dug": 0.0, "shaken_t": 0.0,
		"freeze_res": 0.0, "stun_res": 0.0, "soak_t": 0.0, "trap_t": 0.0, "trap_res": 0.0, "abil_t": -1.0, "heal_t": 0.0, "enraged": false})


# ---------------------------------------------------------------------------
# Main tick
# ---------------------------------------------------------------------------
## One fixed 30 Hz step. At 2x speed this runs two normal-size ticks, so
## everything (damage-over-time rounding included) works exactly like 1x.
func step(real_dt: float) -> void:
	if phase != "playing" or paused:
		return
	var n := maxi(1, int(round(speed_mult)))
	for i in n:
		if phase != "playing":
			break
		tick(real_dt * speed_mult / n, real_dt / n)


func tick(dt: float, real_dt: float) -> void:
	game_time += dt
	for h in heroes:
		for k in ["special_cd", "rally_t", "home_cd", "dash_cd", "dazed_t", "daze_resist", "moved_t"]:
			if h[k] > 0:
				h[k] = maxf(0.0, h[k] - (dt if k != "moved_t" else real_dt))
		for k in h.buffs.keys():
			h.buffs[k] -= dt
			if h.buffs[k] <= 0:
				h.buffs.erase(k)
				h._st = null
				ev({"type": "buff_end", "buff": k, "owner": h.owner, "x": h.x, "y": h.y})
	update_bots(dt)
	update_suns(dt, real_dt)
	if wave_active:
		wave_timer += dt
		while spawn_queue.size() > 0 and spawn_queue[0].at <= wave_timer:
			var s: Dictionary = spawn_queue.pop_front()
			spawn_enemy(s.type, s.path, 0, 0.0, null, s.resist)
		update_spring(dt)
	update_chests(dt)
	update_powerups(dt)
	update_gadgets(dt)
	update_enemies(dt)
	update_pending(dt)
	var auras := compute_auras()
	update_heroes(dt, auras)
	update_projectiles(dt)
	update_wisps(dt)
	update_spikes(dt)
	enemies = enemies.filter(func(e): return e.hp > 0)
	if lives <= 0:
		lives = 0
		phase = "gameover"
		ev({"type": "game_over"})
		return
	if wave_active and spawn_queue.is_empty() and enemies.is_empty():
		wave_active = false
		var bonus := 15.0 + wave * 6
		var acorn_bonus := int(round(10 + wave * 1.5))
		for p in players.values():
			grant_xp(p.id, bonus)
			p.acorns += acorn_bonus
		ev({"type": "wave_clear", "wave": wave, "bonus": bonus, "acorns": acorn_bonus})
		if endless and wave % 10 == 0:
			lives = mini(max_lives, lives + 5)
			for h in heroes:
				h.pending += 1
				h.bonus += 1
				ensure_offer(h)
			ev({"type": "milestone", "wave": wave})
		if not endless and wave >= max_wave:
			phase = "victory"
			ev({"type": "victory"})
			return
		if auto_wave:
			auto_wave_countdown = 2.5
	if not wave_active and auto_wave and wave > 0:
		auto_wave_countdown -= real_dt
		if auto_wave_countdown <= 0:
			start_next_wave()


# ---------------------------------------------------------------------------
# Sun orbs, chests, power-ups
# ---------------------------------------------------------------------------
func add_sun(x: float, y: float, amount: float, owner := -1, share := 0.4, auto := false, sky := false) -> void:
	suns.append({"id": gen_id(), "x": clampf(x, 30, D.W - 30), "y": clampf(y, 30, D.H - 30), "amount": amount, "owner": owner,
		"share": share, "auto": auto, "age": 0.0, "ttl": 12.0 if not sky else 11.0, "sky": sky})


func update_suns(dt: float, real_dt: float) -> void:
	for i in range(suns.size() - 1, -1, -1):
		var s: Dictionary = suns[i]
		s.age += real_dt
		s.ttl -= real_dt
		var taker := -1
		if s.age > 0.35:
			for h in heroes:
				if not h.get("dead", false) and dist(h.x, h.y, s.x, s.y) <= hero_stats(h).pickup:
					taker = h.owner
					break
		if taker < 0 and s.auto and s.age >= 1.1:
			taker = s.owner
		if taker >= 0:
			suns.remove_at(i)
			award_sun(taker, s)
		elif s.ttl <= 0:
			suns.remove_at(i)
	if wave_active:
		sky_sun_t -= dt
		if sky_sun_t <= 0:
			sky_sun_t = 9.5 / sqrt(maxi(1, heroes.size()))
			var spot := Vector2(120 + randf() * (D.W - 240), 100 + randf() * (D.H - 200))
			if heroes.size() > 0:
				var h: Dictionary = heroes[randi() % heroes.size()]
				for k in 12:
					var a := randf() * TAU
					var r := 120 + randf() * 260
					var p := Vector2(clampf(h.x + cos(a) * r, 60, D.W - 60), clampf(h.y + sin(a) * r, 60, D.H - 60))
					if D.is_walkable(map_id, p.x, p.y):
						spot = p
						break
			add_sun(spot.x, spot.y, 25, -1, 0.4, false, true)


func award_sun(pid: int, s: Dictionary) -> void:
	var p = players.get(pid)
	if p == null:
		return
	p.sun += s.amount
	grant_xp(pid, s.amount)
	if s.share > 0:
		for o in players.values():
			if o.id != pid:
				grant_xp(o.id, round(s.amount * s.share))
	ev({"type": "sun_collected", "x": s.x, "y": s.y, "amount": s.amount, "slot": p.slot})


func spawn_chest(x: float, y: float, big: bool) -> void:
	var p := Vector2(x, y)
	if not D.is_walkable(map_id, p.x, p.y):
		for r in range(30, 240, 30):
			var ok := false
			for a in 8:
				var t := Vector2(x + cos(a / 8.0 * TAU) * r, y + sin(a / 8.0 * TAU) * r)
				if D.is_walkable(map_id, t.x, t.y):
					p = t
					ok = true
					break
			if ok:
				break
	chests.append({"id": gen_id(), "x": p.x, "y": p.y, "ttl": 28.0, "big": big})
	ev({"type": "chest_drop", "x": p.x, "y": p.y, "big": big})


func update_chests(dt: float) -> void:
	for i in range(chests.size() - 1, -1, -1):
		var c: Dictionary = chests[i]
		c.ttl -= dt
		var opener = null
		for h in heroes:
			if not h.get("dead", false) and dist(h.x, h.y, c.x, c.y) <= 58:
				opener = players.get(h.owner)
				break
		if opener:
			chests.remove_at(i)
			opener.chests += 1
			var bonus := 2 if c.big else 1
			for h in heroes:
				h.pending += bonus
				h.bonus += bonus
				ensure_offer(h)
			ev({"type": "chest_open", "x": c.x, "y": c.y, "slot": opener.slot, "name": opener.name, "bonus": bonus})
		elif c.ttl <= 0:
			chests.remove_at(i)
			ev({"type": "chest_gone", "x": c.x, "y": c.y})


func maybe_drop_powerup(e: Dictionary) -> void:
	if powerup_cd > 0 or powerups.size() >= 3:
		return
	var def: Dictionary = D.ENEMIES.get(e.type, {})
	var chance := 1.0 if e.boss else 0.03 + minf(0.05, D.gnum(def, "reward", 10) / 1200.0)
	if randf() > chance or D.in_brambles(map_id, e.x, e.y, 20):
		return
	var pool: Array = []
	var weights := {"giant": 3, "zoom": 2, "frenzy": 3, "magnet": 2, "heart": 2}
	for id in D.cosmetics.powerupOrder:
		if id == "heart" and (lives >= max_lives - 1 or is_clash()):
			continue
		for k in weights.get(id, 1):
			pool.append(id)
	spawn_powerup(e.x, e.y, pool[randi() % pool.size()])
	powerup_cd = 9 + randf() * 6


func spawn_powerup(x: float, y: float, kind: String) -> void:
	var p := Vector2(clampf(x, 40, D.W - 40), clampf(y, 40, D.H - 40))
	powerups.append({"id": gen_id(), "kind": kind, "x": p.x, "y": p.y, "ttl": 16.0})
	ev({"type": "powerup_drop", "kind": kind, "x": p.x, "y": p.y})


func update_powerups(dt: float) -> void:
	if powerup_cd > 0:
		powerup_cd -= dt
	for i in range(powerups.size() - 1, -1, -1):
		var pu: Dictionary = powerups[i]
		pu.ttl -= dt
		var taker = null
		for h in heroes:
			if not h.get("dead", false) and dist(h.x, h.y, pu.x, pu.y) <= 52:
				taker = h
				break
		if taker:
			powerups.remove_at(i)
			apply_powerup(taker, pu)
		elif pu.ttl <= 0:
			powerups.remove_at(i)
			ev({"type": "powerup_gone", "x": pu.x, "y": pu.y})


func apply_powerup(h: Dictionary, pu: Dictionary) -> void:
	var def: Dictionary = D.POWERUPS.get(pu.kind, {})
	var p = players.get(h.owner)
	if def.is_empty() or p == null:
		return
	p.powerups += 1
	var shared := 0
	if def.get("instant", false):
		if pu.kind == "magnet":
			for s in suns.duplicate():
				award_sun(p.id, s)
			suns.clear()
			for o in players.values():
				grant_xp(o.id, 20 + wave * 3)
		elif pu.kind == "heart":
			lives = mini(max_lives, lives + 3)
	else:
		for o in heroes:
			if o != h and dist(o.x, o.y, h.x, h.y) > float(D.cosmetics.powerupShareRadius):
				continue
			o.buffs[pu.kind] = maxf(D.gnum(o.buffs, pu.kind), def.dur)
			o._st = null
			if o != h:
				shared += 1
	ev({"type": "powerup_get", "kind": pu.kind, "x": pu.x, "y": pu.y, "slot": p.slot, "name": p.name, "owner": p.id, "shared": shared})


# ---------------------------------------------------------------------------
# Towers & traps
# ---------------------------------------------------------------------------
func tower_scale() -> float:
	var d := diff()
	if d.has("waveExp"):
		return pow(1.0 + float(d.waveExp) * 0.9, maxi(0, wave - 3))
	return 1.0 + (wave - 12) * D.gnum(d, "waveGrowth", 0.14) if wave > 12 else 1.0


func gadget_fail(pid: int, reason: String) -> void:
	ev({"type": "gadget_fail", "owner": pid, "reason": reason})


func plant(pid: int, kind: String) -> void:
	var def: Dictionary = D.GADGETS.get(kind, {})
	var h = hero_of(pid)
	var p = players.get(pid)
	if def.is_empty() or h == null:
		return
	var spot: Dictionary = D.gadget_spot(map_id, kind, h.x, h.y)
	for g in gadgets:
		if g.owner == pid and g.kind == kind and dist(g.x, g.y, spot.x, spot.y) < 60 and not def.get("once", false):
			upgrade_gadget(pid, g.id, -1)
			return
	if not spot.ok:
		gadget_fail(pid, spot.reason)
		return
	for g in gadgets:
		if dist(g.x, g.y, spot.x, spot.y) < 46:
			gadget_fail(pid, "There is already something built here. Move a little!")
			return
	if gadgets.filter(func(g): return g.owner == pid).size() >= int(D.gadgets.limitPerPlayer):
		gadget_fail(pid, "You already have %d towers & traps. Upgrade or sell one." % int(D.gadgets.limitPerPlayer))
		return
	if p.acorns < def.cost:
		gadget_fail(pid, "Not enough acorns: %s costs %d" % [def.name, int(def.cost)])
		return
	p.acorns -= int(def.cost)
	p.gadgets_planted += 1
	gadgets.append({"id": gen_id(), "kind": kind, "owner": pid, "slot": p.slot, "x": spot.x, "y": spot.y, "level": 1, "branch": -1,
		"spent": int(def.cost), "cd": 0.6 if def.get("once", false) else 0.4, "angle": -PI / 2, "sleep_t": 0.0, "wake_t": 0.0, "pulses": 0})
	ev({"type": "gadget_placed", "owner": pid, "kind": kind, "x": spot.x, "y": spot.y, "slot": p.slot})


func my_gadget_near(pid: int, reach := 110.0):
	var h = hero_of(pid)
	if h == null:
		return null
	var best = null
	var bd := reach
	for g in gadgets:
		if g.owner != pid:
			continue
		var d := dist(g.x, g.y, h.x, h.y)
		if d <= bd:
			bd = d
			best = g
	return best


func upgrade_gadget(pid: int, id := -1, branch := -1) -> void:
	var g = null
	if id >= 0:
		for x in gadgets:
			if x.id == id and x.owner == pid:
				g = x
	else:
		g = my_gadget_near(pid)
	if g == null:
		gadget_fail(pid, "Stand next to one of your towers to upgrade it.")
		return
	var def: Dictionary = D.GADGETS[g.kind]
	var p = players[pid]
	if def.get("once", false) or g.level >= 3:
		gadget_fail(pid, "That %s can't be upgraded any more." % def.name)
		return
	var picking: bool = g.level == 2 and def.has("branches")
	if picking and branch < 0:
		ev({"type": "gadget_choose", "owner": pid, "kind": g.kind, "id": g.id})
		return
	var cost: int = D.gadget_upgrade_cost(g.kind, g.level)
	if p.acorns < cost:
		gadget_fail(pid, "Not enough acorns: upgrading needs %d" % cost)
		return
	p.acorns -= cost
	g.spent += cost
	g.level += 1
	if picking:
		g.branch = branch
	var b: Dictionary = D.gadget_branch(g.kind, g.branch)
	ev({"type": "gadget_upgraded", "owner": pid, "kind": g.kind, "x": g.x, "y": g.y, "level": g.level, "slot": p.slot, "branch": b.get("name", ""), "branchIcon": b.get("icon", "")})


func sell_gadget(pid: int) -> void:
	var g = my_gadget_near(pid)
	if g == null:
		gadget_fail(pid, "Stand next to one of your towers to sell it.")
		return
	var refund := int(floor(g.spent * 0.6))
	players[pid].acorns += refund
	gadgets.erase(g)
	ev({"type": "gadget_sold", "owner": pid, "kind": g.kind, "x": g.x, "y": g.y, "refund": refund})


func gadget_target(g: Dictionary, range: float, see_camo := false, skip := {}):
	var best = null
	var bp := -INF
	for e in enemies:
		if e.hp <= 0 or e.sheltered or skip.has(e.id):
			continue
		var d := dist(e.x, e.y, g.x, g.y)
		if d > range or (e.camo and not see_camo and d > 130):
			continue
		if e.progress > bp:
			bp = e.progress
			best = e
	return best


func update_gadgets(dt: float) -> void:
	var scale := tower_scale()
	for i in range(gadgets.size() - 1, -1, -1):
		var g: Dictionary = gadgets[i]
		var def: Dictionary = D.GADGETS[g.kind]
		if g.wake_t > 0:
			g.wake_t -= dt
		if g.sleep_t > 0:
			g.sleep_t -= dt
			for h in heroes:
				if dist(h.x, h.y, g.x, g.y) < 75:
					g.sleep_t = 0.0
					g.wake_t = 2.5
					ev({"type": "gadget_wake", "x": g.x, "y": g.y, "owner": h.owner})
					break
			continue
		var lv: float = D.gadgets.levelMult[g.level - 1]
		var B: Dictionary = D.gadget_branch(g.kind, g.branch)
		var range: float = D.gnum(B, "range", def.get("range", 100))
		var dmg_mult: float = D.gnum(B, "dmgMult", 1.0)
		g.cd -= dt
		if g.cd > 0:
			continue
		match g.kind:
			"thorns":
				g.cd = 0.25
				var dmg := maxf(1, round(def.dps * lv * scale * 0.25))
				for e in enemies:
					if e.hp <= 0 or e.sheltered or dist(e.x, e.y, g.x, g.y) > range:
						continue
					apply_damage(e, dmg, g.owner, g.id, {"armorPierce": true, "isDot": true, "element": "leaf"})
					if B.has("snare"):
						e.sticky = maxf(e.sticky if e.sticky_t > 0 else 0.0, B.snare)
						e.sticky_t = maxf(e.sticky_t, 0.4)
					if B.has("poison"):
						e.poison_dps = maxf(e.poison_dps if e.poison_t > 0 else 0.0, def.dps * lv * scale * 0.7)
						e.poison_t = B.poison
						e.poison_owner = g.owner
						e.poison_tower = g.id
			"bomb":
				var near := false
				for e in enemies:
					if e.hp > 0 and not e.sheltered and dist(e.x, e.y, g.x, g.y) < 40:
						near = true
						break
				if not near:
					continue
				var dmg: float = round(def.dmg * scale)
				shake_moles(g.x, g.y, range)
				for e in enemies:
					if e.hp > 0 and dist(e.x, e.y, g.x, g.y) <= range:
						apply_damage(e, round(dmg * 0.6) if e.boss else dmg, g.owner, g.id, {"armorPierce": true})
				gadgets.remove_at(i)
				ev({"type": "gadget_boom", "x": g.x, "y": g.y})
				ev({"type": "explosion", "x": g.x, "y": g.y, "radius": range, "kind": "boom"})
			"fern":
				var hit: Array = enemies.filter(func(e): return e.hp > 0 and not e.sheltered and dist(e.x, e.y, g.x, g.y) <= range)
				if hit.is_empty():
					g.cd = 0.2
					continue
				g.cd = 1.0 / def.rate
				g.pulses += 1
				var slow: float = D.gnum(B, "slowL3", def.slow[g.level - 1])
				var chill: float = D.gnum(B, "chill", 1.4)
				var freeze: float = B.freeze if B.has("freezeEvery") and g.pulses % int(B.freezeEvery) == 0 else 0.0
				var dmg := maxf(1, round(def.dmg * lv * scale * dmg_mult))
				for e in hit:
					apply_damage(e, dmg, g.owner, g.id, {"armorPierce": true})
					if e.resist == "ice" or e.hp <= 0:
						continue
					e.slow = maxf(e.slow, slow)
					e.slow_t = maxf(e.slow_t, chill)
					e.chill_t = maxf(e.chill_t, chill)
					if freeze > 0:
						try_freeze(e, freeze)
				ev({"type": "nova", "x": g.x, "y": g.y, "radius": range, "color": "#f0f9ff" if freeze > 0 else "#7dd3fc"})
			_:
				var target = gadget_target(g, range, B.get("seeCamo", false))
				if target == null:
					continue
				g.cd = 1.0 / D.gnum(B, "rate", def.rate)
				g.angle = atan2(target.y - g.y, target.x - g.x)
				var dmg := maxf(1, round(def.dmg * lv * scale * dmg_mult))
				if g.kind == "sentry" and B.get("seeCamo", false):
					ev({"type": "snipe", "x": g.x, "y": g.y - 22, "tx": target.x, "ty": target.y})
					apply_damage(target, dmg, g.owner, g.id, {"armorPierce": true})
				elif g.kind == "sentry":
					var targets: Array = [target]
					var shots := int(D.gnum(B, "shots", 1))
					if shots > 1:
						var skip := {target.id: true}
						while targets.size() < shots:
							var t2 = gadget_target(g, range, false, skip)
							if t2 == null:
								break
							targets.append(t2)
							skip[t2.id] = true
						while targets.size() < shots:
							targets.append(target)
					for k in targets.size():
						var t: Dictionary = targets[k]
						var a := atan2(t.y - g.y, t.x - g.x) + ((k - 1) * 0.12 if targets.size() > 1 else 0.0)
						add_projectile({"kind": "pea", "owner": g.owner, "tower": g.id, "x": g.x + ((k - 1) * 12 if targets.size() > 1 else 0), "y": g.y - 16,
							"vx": cos(a) * 540, "vy": sin(a) * 540, "target": t.id, "homing": true, "damage": dmg, "ttl": 1.2, "radius": 7.0, "detectCamo": true})
					ev({"type": "shot", "kind": "pea", "x": g.x, "y": g.y, "angle": g.angle})
				elif g.kind == "mortar":
					add_projectile({"kind": "bomb", "owner": g.owner, "tower": g.id, "x": g.x, "y": g.y - 14, "vx": cos(g.angle) * 330, "vy": sin(g.angle) * 330,
						"target": target.id, "homing": true, "damage": dmg, "ttl": 2.0, "radius": 11.0, "splash": D.gnum(B, "splash", def.splash),
						"armorMult": 1.5, "stun": D.gnum(B, "stun"), "cluster": int(D.gnum(B, "cluster")), "armorPierce": true, "detectCamo": true})
					ev({"type": "shot", "kind": "boom", "x": g.x, "y": g.y, "angle": g.angle})
				elif g.kind == "zap":
					var chains := int(D.gnum(B, "chainsL3", def.chains[g.level - 1]))
					chain_lightning(g, target, dmg, chains, 140.0 if chains > 5 else 120.0, 0.0, true)
					if B.has("stun") and target.hp > 0:
						try_stun(target, B.stun)


func shake_moles(x: float, y: float, r: float) -> void:
	for e in enemies:
		if not e.burrowed or e.hp <= 0 or dist(x, y, e.x, e.y) > r + 20:
			continue
		e.burrowed = false
		e.shaken_t = 2.5
		e.sheltered = D.in_brambles(map_id, e.x, e.y)
		ev({"type": "mole_up", "x": e.x, "y": e.y, "shaken": true})


# ---------------------------------------------------------------------------
# Pests
# ---------------------------------------------------------------------------
func try_freeze(e: Dictionary, dur: float) -> bool:
	if e.resist == "ice" or e.freeze_res > 0 or e.freeze_t > 0:
		return false
	var d := dur * (0.4 if e.boss else 1.0)
	e.freeze_t = d
	e.freeze_res = d + maxf(3.0, d * 1.6)
	return true


func try_stun(e: Dictionary, dur: float) -> bool:
	if e.stun_res > 0 or e.stun_t > 0:
		return false
	var d := dur * (0.5 if e.boss else 1.0)
	e.stun_t = d
	e.stun_res = d + maxf(2.0, d * 1.6)
	return true


func try_trap(e: Dictionary, dur: float) -> bool:
	if e.boss or e.get("structure", false) or e.trap_res > 0 or e.trap_t > 0:
		return false
	var d := dur * (0.5 if e.get("rival", false) else 1.0)
	e.trap_t = d
	e.trap_res = d + 3.0
	ev({"type": "bubble_trap", "x": e.x, "y": e.y})
	return true


func soak(e: Dictionary, dur: float) -> void:
	if e.get("structure", false):
		return
	e.soak_t = maxf(e.soak_t, dur)


func update_enemies(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if i >= enemies.size():
			continue
		var e: Dictionary = enemies[i]
		if e.hp <= 0:
			continue
		if e.flash > 0:
			e.flash = maxf(0, e.flash - dt)
		if e.get("structure", false):
			# buildings (Garden Clash) can't be frozen or stunned
			e.freeze_t = 0.0
			e.stun_t = 0.0
		if e.regen > 0 and e.hp < e.max_hp and e.burn_t <= 0 and e.get("frost_t", 0.0) <= 0:
			e.hp = minf(e.max_hp, e.hp + e.max_hp * e.regen * dt)
		for k in ["chill_t", "sunlit_t", "sticky_t", "freeze_res", "stun_res", "soak_t", "trap_res"]:
			if e[k] > 0:
				e[k] -= dt
		if e.resist == "ice":
			e.freeze_t = 0.0
			e.slow = 0.0
		if e.burn_t > 0 and e.burn_dps > 0:
			e.burn_t -= dt
			apply_damage(e, e.burn_dps * dt, e.burn_owner, e.burn_tower, {"armorPierce": true, "isDot": true})
			if e.hp <= 0:
				continue
		if e.get("frost_t", 0.0) > 0 and e.frost_dps > 0:
			# Frostbite: its own damage-over-time, so it never replaces a burn
			e.frost_t -= dt
			apply_damage(e, e.frost_dps * dt, e.frost_owner, e.frost_tower, {"armorPierce": true, "isDot": true})
			if e.hp <= 0:
				continue
		if e.poison_t > 0:
			e.poison_t -= dt
			e.poison_acc += e.poison_dps * dt
			if e.poison_acc >= 3 or e.poison_t <= 0:
				var pd: float = e.poison_acc
				e.poison_acc = 0.0
				if pd >= 1:
					apply_damage(e, pd, e.poison_owner, e.poison_tower, {"armorPierce": true, "isDot": true, "element": "leaf"})
				if e.hp <= 0:
					continue
		if e.slow_t > 0:
			e.slow_t -= dt
			if e.slow_t <= 0:
				e.slow = 0.0
				e.brittle = 0.0
		if e.trap_t > 0:
			e.trap_t -= dt
			continue
		if e.freeze_t > 0:
			e.freeze_t -= dt
			continue
		if e.stun_t > 0:
			e.stun_t -= dt
			continue
		if e.get("clash", false):
			clash_foe_act(e, dt)
			continue
		enemy_powers(e, dt)
		var pts: PackedVector2Array = _paths[e.path]
		var slow := maxf(e.slow, e.sticky if e.sticky_t > 0 else 0.0)
		var speed: float = e.speed * (1.0 - minf(slow, 0.35 if e.boss else 0.55)) * (1.35 if e.enraged else 1.0)
		var left: float = speed * dt
		while left > 0 and e.seg < pts.size() - 1:
			var a := pts[e.seg]
			var b := pts[e.seg + 1]
			var L := a.distance_to(b)
			if L < 0.001:
				e.seg += 1
				e.t = 0.0
				continue
			var rest: float = (1.0 - e.t) * L
			if left >= rest:
				left -= rest
				e.seg += 1
				e.t = 0.0
				e.x = b.x
				e.y = b.y
			else:
				e.t += left / L
				left = 0.0
				e.x = a.x + (b.x - a.x) * e.t
				e.y = a.y + (b.y - a.y) * e.t
			e.angle = atan2(b.y - a.y, b.x - a.x)
		e.progress = e.seg + e.t
		if e.burrows:
			mole_dig(e, speed * dt - left, dt)
		e.sheltered = e.burrowed or D.in_brambles(map_id, e.x, e.y)
		if e.seg >= pts.size() - 1:
			lives -= e.lives
			ev({"type": "leak", "x": e.x, "y": e.y, "lives": e.lives})
			e.hp = 0.0


func mole_dig(e: Dictionary, moved: float, dt: float) -> void:
	e.dug += moved
	if e.shaken_t > 0:
		e.shaken_t -= dt
		return
	var ph: float = e.dug - 240.0
	var under := ph > 0 and fmod(ph, 620.0) < 320.0
	if under != e.burrowed:
		e.burrowed = under
		ev({"type": "mole_down" if under else "mole_up", "x": e.x, "y": e.y})


func enemy_powers(e: Dictionary, dt: float) -> void:
	var def: Dictionary = D.ENEMIES.get(e.type, {})
	if def.has("heals"):
		e.heal_t -= dt
		if e.heal_t <= 0:
			e.heal_t = 0.5
			var any := false
			for o in enemies:
				if o.id == e.id or o.hp <= 0 or o.boss or o.hp >= o.max_hp or dist(o.x, o.y, e.x, e.y) > def.healRadius:
					continue
				o.hp = minf(o.max_hp, o.hp + o.max_hp * def.heals * 0.5)
				any = true
			if any:
				ev({"type": "pest_heal", "x": e.x, "y": e.y, "r": def.healRadius})
	if def.has("sleepDust") and not e.sheltered:
		e.abil_t = (1.2 if e.abil_t < 0 else e.abil_t) - dt
		if e.abil_t <= 0:
			var n := 0
			for g in gadgets:
				if g.wake_t > 0 or dist(g.x, g.y, e.x, e.y) > def.sleepDust:
					continue
				g.sleep_t = maxf(g.sleep_t, 3.2)
				n += 1
			e.abil_t = 3.0 if n > 0 else 0.4
			if n > 0:
				ev({"type": "sleep_dust", "x": e.x, "y": e.y, "r": def.sleepDust})
	if e.type == "zeppelin" and not e.sheltered:
		e.abil_t = (4.0 if e.abil_t < 0 else e.abil_t) - dt
		if e.abil_t <= 0:
			e.abil_t = 6.5
			var near: Array = heroes.filter(func(h): return dist(h.x, h.y, e.x, e.y) < 560)
			if near.size() > 0:
				var h: Dictionary = near[randi() % near.size()]
				pending_fx.append({"t": 1.3, "kind": "spore", "x": h.x, "y": h.y, "r": 105.0})
				ev({"type": "spore_warn", "x": h.x, "y": h.y, "r": 105, "delay": 1.3, "fromX": e.x, "fromY": e.y})
	if e.type == "dreadblimp" and not e.sheltered:
		if not e.enraged and e.hp < e.max_hp * 0.5:
			e.enraged = true
			ev({"type": "boss_enrage", "x": e.x, "y": e.y, "name": def.name})
		e.abil_t = (5.0 if e.abil_t < 0 else e.abil_t) - dt
		if e.abil_t <= 0:
			e.abil_t = 6.0 if e.enraged else 9.0
			for k in 3:
				spawn_enemy("nutknight" if k == 1 else "beetle", e.path, e.seg, e.t, Vector2(e.x + (k - 1) * 22, e.y + (14 if k % 2 else -14)))
			ev({"type": "summon", "x": e.x, "y": e.y})


func update_pending(dt: float) -> void:
	var keep: Array = []
	for fx in pending_fx:
		fx.t -= dt
		if fx.t > 0:
			keep.append(fx)
		elif fx.kind == "spore":
			daze_cloud(fx.x, fx.y, fx.r, 1.6)
	pending_fx = keep


func daze_cloud(x: float, y: float, r: float, dur: float) -> void:
	for h in heroes:
		if h.daze_resist > 0 or dist(h.x, h.y, x, y) > r:
			continue
		h.dazed_t = dur
		h.daze_resist = dur + 2.2
		ev({"type": "hero_dazed", "x": h.x, "y": h.y, "owner": h.owner})
	ev({"type": "spore_burst", "x": x, "y": y, "r": r})


# ---------------------------------------------------------------------------
# Damage, elements & reactions
# ---------------------------------------------------------------------------
func element_of(tower_id: int) -> String:
	for h in heroes:
		if h.id == tower_id:
			return D.HERO_ELEMENT.get(h.type, "")
	for g in gadgets:
		if g.id == tower_id:
			return D.GADGETS[g.kind].get("element", "")
	return ""


func reaction_fx(kind: String, e: Dictionary) -> void:
	if game_time - float(react_fx.get(kind, -1.0)) < 0.3:
		return
	react_fx[kind] = game_time
	ev({"type": "reaction", "kind": kind, "x": e.x, "y": e.y - e.radius})


func reaction_mult(e: Dictionary, el: String, raw: float, owner: int, tower: int, opts: Dictionary) -> float:
	if el == "" or opts.get("isDot", false) or opts.get("noReact", false):
		return 1.0
	var chilled: bool = e.freeze_t > 0 or e.chill_t > 0
	var mult := 1.0
	var reaction := ""
	if el == "blast" and chilled:
		reaction = "shatter"
	elif el == "fire" and chilled:
		reaction = "melt"
		e.freeze_t = 0.0
		e.chill_t = 0.0
	elif el == "shock" and e.soak_t > 0:
		reaction = "electrocute"
		e.soak_t = 0.0
	elif el == "ice" and e.soak_t > 0:
		reaction = "flashfreeze"
		e.soak_t = 0.0
		if e.resist != "ice":
			try_freeze(e, 1.2)
	elif el == "shock" and e.burn_t > 0:
		reaction = "overload"
	elif el == "leaf" and e.stun_t > 0:
		reaction = "knockout"
	if reaction != "":
		mult *= float(D.REACTIONS[reaction].mult)
		if reaction == "overload" or reaction == "electrocute":
			for o in enemies:
				if o.id == e.id or o.hp <= 0 or dist(o.x, o.y, e.x, e.y) > 80:
					continue
				apply_damage(o, round(raw * 0.6), owner, tower, {"armorPierce": true, "element": "blast", "noReact": true})
		var p = players.get(owner)
		if p:
			p.reactions += 1
		reaction_fx(reaction, e)
	if el == "sun":
		e.sunlit_t = 3.0
		e.camo = false
	elif e.sunlit_t > 0:
		mult *= float(D.REACTIONS.sunlit.mult)
	return mult


func apply_damage(e: Dictionary, raw: float, owner: int, tower: int, opts: Dictionary = {}) -> void:
	if e.hp <= 0 or e.sheltered:
		return
	var dmg := raw
	var el: String = opts.get("element", element_of(tower))
	dmg *= reaction_mult(e, el, raw, owner, tower, opts)
	if el != "" and e.resist == el:
		dmg *= D.RESIST_MULT
		if not opts.get("isDot", false):
			reaction_fx("resist_" + el, e)
	var ap: bool = opts.get("armorPierce", false)
	if e.lead and not ap:
		dmg *= 0.35
	if e.shielded and not ap:
		dmg *= 0.5
	if e.twist_armor > 0 and not ap:
		dmg *= e.twist_armor
	if e.brittle > 0:
		dmg *= 1.0 + e.brittle
	if e.trap_t > 0:
		dmg *= 1.25
	dmg *= damage_mult(e, tower)
	var final := maxf(1.0, round(dmg))
	e.hp -= final
	if not opts.get("isDot", false):
		e.flash = 0.12
	var p = players.get(owner)
	if p:
		p.damage += final
	for h in heroes:
		if h.id == tower:
			h.pops += final
	if e.get("clash", false) and tower >= 0:
		on_hero_hit(e, tower, owner, final, opts)
	if not opts.get("isDot", false) and (opts.get("crit", false) or final >= 25):
		ev({"type": "dmg", "x": e.x, "y": e.y - e.radius, "amount": final, "crit": opts.get("crit", false)})
	if e.hp <= 0:
		on_defeated(e, owner)


func on_defeated(e: Dictionary, killer_id: int) -> void:
	var killer = players.get(killer_id)
	if killer:
		killer.pops += 1
		grant_xp(killer_id, e.reward)
		killer.acorn_frac += 25.0 if e.boss else (1.5 if e.reward >= 40 else 0.4)
		var whole := int(floor(killer.acorn_frac))
		killer.acorn_frac -= whole
		killer.acorns += whole
	var assist := maxf(1, round(e.reward * D.gnum(diff(), "assistShare", 0.3)))
	for p in players.values():
		if p.id != killer_id:
			grant_xp(p.id, assist)
	var def: Dictionary = D.ENEMIES.get(e.type, {})
	if def.has("dazeCloud"):
		daze_cloud(e.x, e.y, def.dazeCloud, 1.2)
	if def.get("treasure", false) or e.boss:
		spawn_chest(e.x, e.y, e.boss)
	else:
		maybe_drop_powerup(e)
	if def.has("spawnOnDeath"):
		var kids: Array = def.spawnOnDeath
		for idx in kids.size():
			var off := (idx - kids.size() / 2.0) * 14
			spawn_enemy(kids[idx], e.path, e.seg, e.t, Vector2(e.x + off, e.y + (-8 if idx % 2 == 0 else 8)), e.resist)
	ev({"type": "enemy_pop", "x": e.x, "y": e.y, "color": def.get("color", "#A3E635"), "boss": e.boss, "reward": e.reward, "kind": e.type})


# ---------------------------------------------------------------------------
# Heroes fighting
# ---------------------------------------------------------------------------
func compute_auras() -> Dictionary:
	var out := {}
	for h in heroes:
		var a := {"speed": 0.0, "damage": 0.0, "pierce": 0, "reveal": false, "synergy": false}
		for o in heroes:
			if o.id == h.id or o.get("dead", false):
				continue
			var os := hero_stats(o)
			var d := dist(h.x, h.y, o.x, o.y)
			if o.type == "sunblossom" and d <= os.range:
				a.speed = maxf(a.speed, D.gnum(os, "buffSpeed"))
				a.damage = maxf(a.damage, D.gnum(os, "buffDamage"))
				a.pierce = maxi(a.pierce, int(D.gnum(os, "buffPierce")))
				if os.get("revealCamo", false):
					a.reveal = true
				a.synergy = true
			if os.spiritAura > 0 and d <= 220:
				a.damage += os.spiritAura
			if D.gnum(os, "mistAura") > 0 and d <= os.range:
				a.speed = maxf(a.speed, os.mistAura)
		if a.synergy:
			a.speed += 0.05
		if h.rally_t > 0:
			a.speed += 0.5
		out[h.id] = a
	return out


func can_see(t: Dictionary, st: Dictionary, aura: Dictionary, e: Dictionary) -> bool:
	if e.sheltered:
		return false
	if not e.camo:
		return true
	if st.get("detectCamo", false) or aura.reveal:
		return true
	return dist(t.x, t.y, e.x, e.y) <= 130


func pick_target(t: Dictionary, st: Dictionary, aura: Dictionary, custom_range := 0.0):
	var r: float = custom_range if custom_range > 0 else st.range
	var best = null
	var low: bool = t.target_mode == "last" or t.target_mode == "close"
	var bv := INF if low else -INF
	for e in enemies:
		if e.hp <= 0 or not can_see(t, st, aura, e):
			continue
		var d := dist(t.x, t.y, e.x, e.y)
		if d > r + e.radius * 0.5:
			continue
		var v: float = e.progress
		if t.target_mode == "strong":
			v = e.hp + (10000.0 if e.boss else 0.0)
		elif t.target_mode == "close":
			v = d
		if (low and v < bv) or (not low and v > bv):
			bv = v
			best = e
	return best


func add_projectile(p: Dictionary) -> void:
	p.id = gen_id()
	if not p.has("hit"):
		p.hit = {}
	if not p.has("pierce"):
		p.pierce = 1
	projectiles.append(p)


func update_heroes(dt: float, auras: Dictionary) -> void:
	for t in heroes:
		if t.recoil > 0:
			t.recoil = maxf(0.0, t.recoil - dt * 4)
		if t.get("dead", false):
			continue
		var st := hero_stats(t)
		var aura: Dictionary = auras.get(t.id, {"speed": 0.0, "damage": 0.0, "pierce": 0, "reveal": false})
		if t.type == "sunblossom":
			sunblossom_extras(t, st, dt)
		if t.dazed_t > 0:
			continue
		t.cooldown -= dt
		if t.cooldown > 0:
			continue
		var rate: float = D.gnum(st, "fireRate", 1.0) * (1.0 + aura.speed)
		var crit: bool = t.type != "peashooter" and randf() < st.critChance
		var dmg: float = round(st.damage * (1.0 + aura.damage) * (2.0 if crit else 1.0))
		var see: bool = st.get("detectCamo", false) or aura.reveal
		var target = pick_target(t, st, aura, D.gnum(st, "emberRange") if t.type == "snapdragon" and D.gnum(st, "emberRange") > 0 else 0.0)
		if target == null:
			continue
		t.cooldown = 1.0 / rate
		t.shots += 1
		t.recoil = 1.0
		t.angle = atan2(target.y - t.y, target.x - t.x)
		match t.type:
			"peashooter":
				if st.get("beamMode", false):
					railgun(t, st, dmg, int(D.gnum(st, "pierce", 1)) + aura.pierce)
				else:
					var mega: bool = D.gnum(st, "megaPeaEvery") > 0 and t.shots % int(st.megaPeaEvery) == 0
					var count := int(D.gnum(st, "burst", 1))
					for b in count:
						var a: float = t.angle + (0.0 if count == 1 else (b - (count - 1) / 2.0) * 0.11)
						var c2: bool = randf() < st.critChance
						add_projectile({"kind": "megapea" if mega else ("thorn" if st.get("armorPierce", false) else "pea"), "owner": t.owner, "tower": t.id,
							"x": t.x + cos(a) * 20, "y": t.y + sin(a) * 20, "vx": cos(a) * st.projSpeed, "vy": sin(a) * st.projSpeed,
							"damage": round(dmg * (2.6 if mega else 1.0) * (2.0 if c2 else 1.0)), "pierce": int(D.gnum(st, "pierce", 1)) + aura.pierce + (2 if mega else 0),
							"ttl": 1.5, "radius": 12.0 if mega else 7.0, "armorPierce": st.get("armorPierce", false) or mega, "knockback": D.gnum(st, "knockback", 26) if mega else 0.0,
							"crit": c2, "detectCamo": see})
				ev({"type": "shot", "kind": "pea", "x": t.x, "y": t.y, "angle": t.angle})
			"sunblossom":
				add_projectile({"kind": "sunseed", "owner": t.owner, "tower": t.id, "x": t.x, "y": t.y, "vx": cos(t.angle) * st.projSpeed, "vy": sin(t.angle) * st.projSpeed,
					"target": target.id, "homing": true, "damage": dmg, "pierce": 1 + aura.pierce, "ttl": 1.4, "radius": 8.0, "armorPierce": st.get("armorPierce", false),
					"crit": crit, "detectCamo": see or st.get("revealCamo", false)})
				ev({"type": "shot", "kind": "pea", "x": t.x, "y": t.y, "angle": t.angle})
			"frostlotus":
				var any := false
				for e in enemies:
					if e.hp > 0 and can_see(t, st, aura, e) and dist(t.x, t.y, e.x, e.y) <= st.range:
						any = true
						apply_frost(e, st, dmg, t.owner, t.id)
				if any:
					ev({"type": "nova", "x": t.x, "y": t.y, "radius": st.range, "color": "#67E8F9"})
				var shards := int(D.gnum(st, "shardCount"))
				if shards > 0:
					var n := 0
					for e in enemies:
						if n >= shards:
							break
						if e.hp <= 0 or not can_see(t, st, aura, e) or dist(t.x, t.y, e.x, e.y) > st.range * 1.15:
							continue
						n += 1
						var a := atan2(e.y - t.y, e.x - t.x)
						var snow: bool = st.get("splashSnowball", false)
						add_projectile({"kind": "snowball" if snow else "icicle", "owner": t.owner, "tower": t.id, "x": t.x, "y": t.y, "vx": cos(a) * 430, "vy": sin(a) * 430,
							"target": e.id, "homing": true, "damage": round(dmg * 0.85), "ttl": 1.6, "radius": 11.0 if snow else 7.0, "splash": 58.0 if snow else 0.0,
							"slowAmount": st.slowAmount, "slowDuration": st.slowDuration, "brittle": D.gnum(st, "brittleBonus"), "frostDot": D.gnum(st, "frostDot"), "detectCamo": see})
			"boomshroom":
				add_projectile({"kind": "rocket" if D.gnum(st, "bossMult", 1) > 1.5 else "bomb", "owner": t.owner, "tower": t.id, "x": t.x, "y": t.y,
					"vx": cos(t.angle) * st.projSpeed, "vy": sin(t.angle) * st.projSpeed, "target": target.id, "homing": true, "damage": dmg, "ttl": 1.8, "radius": 11.0,
					"splash": st.splashRadius, "armorMult": D.gnum(st, "armorMult", 1.5), "bossMult": D.gnum(st, "bossMult", 1.0), "stun": D.gnum(st, "stunDuration"),
					"shrapnel": int(D.gnum(st, "shrapnel")), "cluster": int(D.gnum(st, "clusterCount")), "burnDps": D.gnum(st, "burnDps"), "armorPierce": true, "detectCamo": see})
				ev({"type": "shot", "kind": "boom", "x": t.x, "y": t.y, "angle": t.angle})
			"voltcactus":
				chain_lightning(t, target, dmg, int(st.chainCount), st.chainRange, D.gnum(st, "overloadSplash"), see)
				if D.gnum(st, "thunderEvery") > 0 and t.shots % int(st.thunderEvery) == 0:
					var heavy = target
					for e in enemies:
						if e.hp > 0 and dist(t.x, t.y, e.x, e.y) <= st.range * 1.25 and e.hp > heavy.hp:
							heavy = e
					apply_damage(heavy, round(dmg * 2.8), t.owner, t.id, {"armorPierce": true})
					try_stun(heavy, 0.55)
					ev({"type": "thunder", "x": heavy.x, "y": heavy.y})
				var ring := int(D.gnum(st, "needleRing"))
				for k in ring:
					var a := TAU * k / ring
					add_projectile({"kind": "needle", "owner": t.owner, "tower": t.id, "x": t.x, "y": t.y, "vx": cos(a) * 440, "vy": sin(a) * 440,
						"homing": st.get("homingNeedles", false), "damage": round(dmg * 0.75), "pierce": 2, "ttl": 0.9, "radius": 6.0, "armorPierce": true, "detectCamo": see})
				if D.gnum(st, "dropSpikes") > 0 and wave_active and spikes.filter(func(s): return s.tower == t.id).size() < 5 + int(st.dropSpikes) * 2:
					drop_spike(t, st)
			"snapdragon":
				var in_flame: bool = dist(t.x, t.y, target.x, target.y) <= st.range + 15
				var ring_fire: bool = st.get("ringOfFire", false)
				if in_flame or ring_fire:
					for e in enemies:
						if e.hp <= 0 or not can_see(t, st, aura, e) or dist(t.x, t.y, e.x, e.y) > st.range + e.radius:
							continue
						if ring_fire or absf(angle_difference(t.angle, atan2(e.y - t.y, e.x - t.x))) <= st.coneAngle * 0.65:
							if st.get("stripCamo", false):
								e.camo = false
							apply_damage(e, dmg, t.owner, t.id, {"armorPierce": st.get("armorPierce", false)})
							e.burn_dps = maxf(e.burn_dps, st.burnDps)
							e.burn_t = maxf(e.burn_t, st.burnDuration)
							e.burn_owner = t.owner
							e.burn_tower = t.id
					ev({"type": "flame", "x": t.x, "y": t.y, "angle": t.angle, "range": st.range, "coneAngle": st.coneAngle, "ring": ring_fire})
				if D.gnum(st, "emberRange") > 0:
					add_projectile({"kind": "ember", "owner": t.owner, "tower": t.id, "x": t.x + cos(t.angle) * 16, "y": t.y + sin(t.angle) * 16,
						"vx": cos(t.angle) * 420, "vy": sin(t.angle) * 420, "target": target.id, "homing": true, "damage": round(dmg * 0.9), "pierce": 2, "ttl": 1.4,
						"radius": 9.0, "burnDps": st.burnDps, "burnDuration": st.burnDuration, "stripCamo": st.get("stripCamo", false), "armorPierce": st.get("armorPierce", false), "detectCamo": see})
			"bubblelily":
				if D.gnum(st, "waveEvery") > 0 and t.shots % int(st.waveEvery) == 0:
					lily_wave(t, st, dmg)
				fire_bubble(t, Vector2(t.x, t.y - 18), target, dmg, st, see, int(D.gnum(st, "bounce")), {})
				ev({"type": "shot", "kind": "bubble", "x": t.x, "y": t.y, "angle": t.angle})


func sunblossom_extras(t: Dictionary, st: Dictionary, dt: float) -> void:
	if wave_active:
		t.sun_t -= dt
		if t.sun_t <= 0:
			t.sun_t = st.sunInterval
			var a := randf() * TAU
			var r := 70 + randf() * 50
			add_sun(t.x + cos(a) * r, t.y + sin(a) * r, st.sunAmount, t.owner, maxf(0.5, D.gnum(st, "shareRatio")), st.get("autoCollect", false))
	if D.gnum(st, "pulseDamage") > 0:
		t.pulse_t -= dt
		if t.pulse_t <= 0:
			t.pulse_t = D.gnum(st, "pulseInterval", 2.2)
			var hit := false
			for e in enemies:
				if e.hp > 0 and dist(t.x, t.y, e.x, e.y) <= st.range:
					hit = true
					if st.get("revealCamo", false):
						e.camo = false
					apply_damage(e, st.pulseDamage, t.owner, t.id, {"armorPierce": true})
			if hit:
				ev({"type": "nova", "x": t.x, "y": t.y, "radius": st.range, "color": "#FDE047"})
	if st.get("solarBeam", false) and wave_active and enemies.size() > 0:
		t.beam_t -= dt
		if t.beam_t <= 0:
			t.beam_t = 4.5
			var strongest = null
			for e in enemies:
				if e.hp > 0 and (strongest == null or e.hp > strongest.hp):
					strongest = e
			if strongest:
				apply_damage(strongest, round(110 * (1 + 0.05 * (t.level - 1))), t.owner, t.id, {"armorPierce": true})
				ev({"type": "solar_beam", "x": strongest.x, "y": strongest.y})


func apply_frost(e: Dictionary, st: Dictionary, dmg: float, owner: int, tower: int) -> void:
	if dmg > 0:
		apply_damage(e, dmg, owner, tower, {"armorPierce": true})
	if e.resist == "ice":
		return
	e.chill_t = maxf(e.chill_t, D.gnum(st, "slowDuration", 2))
	e.slow = maxf(e.slow, st.slowAmount)
	e.slow_t = maxf(e.slow_t, st.slowDuration)
	e.brittle = maxf(e.brittle, D.gnum(st, "brittleBonus"))
	if D.gnum(st, "frostDot") > 0:
		e.frost_dps = maxf(e.get("frost_dps", 0.0), st.frostDot)
		e.frost_t = maxf(e.get("frost_t", 0.0), 2.5)
		e.frost_owner = owner
		e.frost_tower = tower
	if D.gnum(st, "freezeChance") > 0 and randf() < st.freezeChance:
		try_freeze(e, st.freezeDuration * (0.35 if e.boss else 1.0))


func railgun(t: Dictionary, st: Dictionary, dmg: float, pierce: int) -> void:
	var dir := Vector2(cos(t.angle), sin(t.angle))
	var L: float = st.range * 1.35
	var hits: Array = []
	for e in enemies:
		if e.hp <= 0:
			continue
		var v := Vector2(e.x - t.x, e.y - t.y)
		var proj := v.dot(dir)
		if proj < 0 or proj > L:
			continue
		if absf(v.cross(dir)) <= e.radius + 14:
			hits.append([proj, e])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(pierce, hits.size()):
		var c: bool = randf() < st.critChance
		apply_damage(hits[i][1], round(dmg * (1.8 if c else 1.0)), t.owner, t.id, {"armorPierce": true, "crit": c})
	ev({"type": "beam", "x1": t.x, "y1": t.y, "x2": t.x + dir.x * L, "y2": t.y + dir.y * L, "slot": t.slot})


func chain_lightning(t: Dictionary, first: Dictionary, dmg: float, chains: int, chain_range: float, overload: float, see: bool) -> void:
	var pts: Array = [[t.x, t.y]]
	var hit := {}
	var cur = first
	var d := dmg
	for hop in chains:
		if cur == null:
			break
		hit[cur.id] = true
		pts.append([cur.x, cur.y])
		apply_damage(cur, round(d), t.owner, t.id, {"armorPierce": true})
		var nxt = null
		var bd := chain_range
		for e in enemies:
			if e.hp <= 0 or hit.has(e.id) or e.sheltered or (e.camo and not see and dist(t.x, t.y, e.x, e.y) > 130):
				continue
			var dd := dist(cur.x, cur.y, e.x, e.y)
			if dd <= bd:
				bd = dd
				nxt = e
		if nxt == null and overload > 0:
			for e in enemies:
				if e.hp > 0 and dist(cur.x, cur.y, e.x, e.y) <= 68:
					apply_damage(e, overload, t.owner, t.id, {"armorPierce": true})
			ev({"type": "nova", "x": cur.x, "y": cur.y, "radius": 68, "color": "#C084FC"})
		cur = nxt
		d *= 0.88
	ev({"type": "lightning", "points": pts})


func drop_spike(t: Dictionary, st: Dictionary) -> void:
	var cands: Array = []
	for key in D.map(map_id).pathTiles:
		var parts: PackedStringArray = String(key).split(",")
		var p := Vector2((int(parts[0]) + 0.5) * D.TILE, (int(parts[1]) + 0.5) * D.TILE)
		if p.distance_to(Vector2(t.x, t.y)) <= st.range + 20:
			cands.append(p + Vector2(randf() - 0.5, randf() - 0.5) * 18)
	if cands.is_empty():
		return
	var s: Vector2 = cands[randi() % cands.size()]
	spikes.append({"id": gen_id(), "tower": t.id, "owner": t.owner, "slot": t.slot, "x": s.x, "y": s.y, "damage": D.gnum(st, "spikeDamage", 28), "charges": 4, "ttl": 25.0})


func fire_bubble(t: Dictionary, from: Vector2, target: Dictionary, dmg: float, st: Dictionary, see: bool, bounce: int, hit: Dictionary) -> void:
	var a := atan2(target.y - from.y, target.x - from.x)
	add_projectile({"kind": "bubble", "owner": t.owner, "tower": t.id, "x": from.x, "y": from.y, "vx": cos(a) * st.projSpeed, "vy": sin(a) * st.projSpeed,
		"target": target.id, "homing": true, "damage": dmg, "ttl": 1.6, "radius": 10.0, "soak": D.gnum(st, "soakDuration", 3), "bslow": D.gnum(st, "bubbleSlow"),
		"pop": D.gnum(st, "popSplash"), "trap": D.gnum(st, "trapChance"), "trapDur": D.gnum(st, "trapDuration"), "bounce": bounce, "hit": hit.duplicate(), "detectCamo": see, "st": st})


func bubble_pop(p: Dictionary, e: Dictionary) -> void:
	soak(e, p.soak)
	if p.bslow > 0 and e.resist != "ice" and not e.get("structure", false):
		e.slow = maxf(e.slow, p.bslow)
		e.slow_t = maxf(e.slow_t, 1.5)
	if p.pop > 0:
		for o in enemies:
			if o.id == e.id or o.hp <= 0 or o.sheltered or dist(o.x, o.y, e.x, e.y) > p.pop:
				continue
			apply_damage(o, round(p.damage * 0.6), p.owner, p.tower, {"noReact": true})
			soak(o, p.soak)
		ev({"type": "bubble_pop", "x": e.x, "y": e.y, "r": p.pop})
	if p.trap > 0 and e.hp > 0 and randf() < p.trap:
		try_trap(e, p.trapDur)
	if p.bounce > 0:
		var nxt = null
		var bd := 190.0
		for o in enemies:
			if o.id == e.id or o.hp <= 0 or o.sheltered or o.get("neutral", false) or p.hit.has(o.id):
				continue
			var d := dist(o.x, o.y, e.x, e.y)
			if d < bd:
				bd = d
				nxt = o
		var t = null
		for h in heroes:
			if h.id == p.tower:
				t = h
		if nxt and t:
			fire_bubble(t, Vector2(e.x, e.y), nxt, round(p.damage * 0.8), p.st, true, p.bounce - 1, p.hit)


func lily_wave(t: Dictionary, st: Dictionary, dmg: float) -> void:
	var r: float = st.range * 1.1
	for e in enemies:
		if e.hp <= 0 or e.sheltered or e.get("neutral", false) or dist(t.x, t.y, e.x, e.y) > r:
			continue
		if absf(angle_difference(t.angle, atan2(e.y - t.y, e.x - t.x))) > 0.75:
			continue
		apply_damage(e, round(dmg * 1.2), t.owner, t.id)
		soak(e, D.gnum(st, "soakDuration", 3))
		push_back(e, D.gnum(st, "pushback", 60), Vector2(t.x, t.y))
	ev({"type": "lily_wave", "x": t.x, "y": t.y, "angle": t.angle, "range": r})


## Push a pest back along its trail (bosses only a little)
func push_back(e: Dictionary, px: float, _from := Vector2.ZERO) -> void:
	if e.hp <= 0 or e.sheltered:
		return
	if e.boss:
		px *= 0.35
	var pts: PackedVector2Array = _paths[e.path]
	var left := px
	while left > 0 and e.seg < pts.size() - 1:
		var L := pts[e.seg].distance_to(pts[e.seg + 1])
		var back: float = e.t * L
		if left <= back:
			e.t -= left / maxf(L, 0.001)
			left = 0.0
		else:
			left -= back
			if e.seg == 0:
				e.t = 0.0
				break
			e.seg -= 1
			e.t = 1.0
	var a := pts[e.seg]
	var b := pts[mini(e.seg + 1, pts.size() - 1)]
	e.x = a.x + (b.x - a.x) * e.t
	e.y = a.y + (b.y - a.y) * e.t
	e.progress = e.seg + e.t


func set_target_mode(pid: int, target_mode: String) -> void:
	var h = hero_of(pid)
	if h and target_mode in ["first", "last", "strong", "close"]:
		h.target_mode = target_mode


func sync_wisps(h: Dictionary) -> void:
	wisps = wisps.filter(func(w): return w.tower != h.id)
	var st := hero_stats(h)
	var n := int(D.gnum(st, "wispCount"))
	for i in n:
		wisps.append({"id": gen_id(), "tower": h.id, "owner": h.owner, "slot": h.slot, "orbit": TAU * i / n, "x": h.x, "y": h.y, "cd": 0.0,
			"damage": round(st.damage * 0.9), "burnDps": D.gnum(st, "burnDps", 12), "range": D.gnum(st, "emberRange", 280)})


func update_wisps(dt: float) -> void:
	for w in wisps:
		var t = null
		for h in heroes:
			if h.id == w.tower:
				t = h
		if t == null:
			continue
		if t.get("dead", false):  # knocked out (Garden Clash): the wisps wait
			w.x = t.x
			w.y = t.y
			continue
		var wst := hero_stats(t)  # current stats, so level-ups and buffs count right away
		w.damage = round(wst.damage * 0.9)
		w.burnDps = D.gnum(wst, "burnDps", 12)
		w.range = D.gnum(wst, "emberRange", 280)
		w.orbit += dt * 2.6
		var home := Vector2(t.x + cos(w.orbit) * 34, t.y + sin(w.orbit) * 34)
		if w.cd > 0:
			w.cd -= dt
		var target = null
		for e in enemies:
			if e.hp > 0 and not e.sheltered and dist(t.x, t.y, e.x, e.y) <= w.range and (target == null or e.progress > target.progress):
				target = e
		if target:
			var v := Vector2(target.x - w.x, target.y - w.y)
			var d := v.length()
			if d > 4:
				var s := minf(d, 290 * dt) / d
				w.x += v.x * s
				w.y += v.y * s
			if d <= target.radius + 14 and w.cd <= 0:
				w.cd = 0.55
				target.camo = false
				apply_damage(target, w.damage, w.owner, w.tower, {"armorPierce": true})
				target.burn_dps = maxf(target.burn_dps, w.burnDps)
				target.burn_t = maxf(target.burn_t, 2.5)
				target.burn_owner = w.owner
				target.burn_tower = w.tower
		else:
			w.x += (home.x - w.x) * minf(1.0, dt * 8)
			w.y += (home.y - w.y) * minf(1.0, dt * 8)


func update_spikes(dt: float) -> void:
	for i in range(spikes.size() - 1, -1, -1):
		var s: Dictionary = spikes[i]
		s.ttl -= dt
		if s.ttl <= 0 or s.charges <= 0:
			spikes.remove_at(i)
			continue
		for e in enemies:
			if e.hp > 0 and dist(s.x, s.y, e.x, e.y) <= e.radius + 14:
				apply_damage(e, s.damage, s.owner, s.tower, {"armorPierce": true})
				s.charges -= 1
				if s.charges <= 0:
					break


func update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		if i >= projectiles.size():
			continue
		var p: Dictionary = projectiles[i]
		p.ttl -= dt
		if p.ttl <= 0:
			projectiles.remove_at(i)
			continue
		if p.get("homing", false):
			var tgt = null
			if p.has("target"):
				for e in enemies:
					if e.id == p.target and e.hp > 0:
						tgt = e
						break
			if tgt == null and p.kind == "needle":
				for e in enemies:
					if e.hp > 0 and not p.hit.has(e.id) and dist(p.x, p.y, e.x, e.y) < 160:
						tgt = e
						break
			if tgt:
				var cur := atan2(p.vy, p.vx)
				var want := atan2(tgt.y - p.y, tgt.x - p.x)
				var sp := Vector2(p.vx, p.vy).length()
				var na := cur + clampf(angle_difference(cur, want), -8 * dt, 8 * dt)
				p.vx = cos(na) * sp
				p.vy = sin(na) * sp
		p.x += p.vx * dt
		p.y += p.vy * dt
		if p.x < -60 or p.x > D.W + 60 or p.y < -60 or p.y > D.H + 60:
			projectiles.remove_at(i)
			continue
		var remove := false
		var splashy: bool = p.kind in ["bomb", "rocket", "snowball", "cluster"]
		for e in enemies:
			if e.hp <= 0 or p.hit.has(e.id):
				continue
			if e.camo and not p.get("detectCamo", false):
				var near := false
				for h in heroes:
					if h.id == p.tower and dist(h.x, h.y, e.x, e.y) <= 130:
						near = true
				if not near:
					continue
			if e.burrowed and not splashy:
				continue
			if dist(p.x, p.y, e.x, e.y) <= e.radius + p.radius:
				p.hit[e.id] = true
				if splashy:
					splash(p)
					remove = true
					break
				apply_damage(e, p.damage, p.owner, p.tower, {"armorPierce": p.get("armorPierce", false), "crit": p.get("crit", false)})
				if D.gnum(p, "knockback") > 0 and not e.boss:
					e.t = maxf(0.0, e.t - 0.14)
				if D.gnum(p, "burnDps") > 0:
					e.burn_dps = maxf(e.burn_dps, p.burnDps)
					e.burn_t = maxf(e.burn_t, D.gnum(p, "burnDuration", 2.5))
					e.burn_owner = p.owner
					e.burn_tower = p.tower
				if p.get("stripCamo", false):
					e.camo = false
				if p.kind == "icicle":
					apply_frost(e, {"slowAmount": p.slowAmount, "slowDuration": p.slowDuration, "brittleBonus": p.brittle, "frostDot": p.frostDot}, 0, p.owner, p.tower)
				if p.kind == "bubble":
					bubble_pop(p, e)
				p.pierce -= 1
				if p.pierce <= 0:
					remove = true
					break
		if remove and i < projectiles.size() and projectiles[i] == p:
			projectiles.remove_at(i)


func splash(p: Dictionary) -> void:
	var r: float = D.gnum(p, "splash", 68)
	shake_moles(p.x, p.y, r)
	for e in enemies:
		if e.hp <= 0 or dist(p.x, p.y, e.x, e.y) > r + e.radius * 0.5:
			continue
		var dmg: float = p.damage
		if (e.armored or e.shielded or e.lead) and D.gnum(p, "armorMult") > 0:
			dmg *= p.armorMult
		if e.boss and D.gnum(p, "bossMult") > 0:
			dmg *= p.bossMult
		apply_damage(e, round(dmg), p.owner, p.tower, {"armorPierce": true})
		if D.gnum(p, "stun") > 0:
			try_stun(e, p.stun * (0.35 if e.boss else 1.0))
		if D.gnum(p, "slowAmount") > 0 and e.resist != "ice":
			e.chill_t = maxf(e.chill_t, D.gnum(p, "slowDuration", 2.2))
			e.slow = maxf(e.slow, p.slowAmount)
			e.slow_t = maxf(e.slow_t, D.gnum(p, "slowDuration", 2.2))
			e.brittle = maxf(e.brittle, D.gnum(p, "brittle"))
		if D.gnum(p, "burnDps") > 0:
			e.burn_dps = maxf(e.burn_dps, p.burnDps)
			e.burn_t = maxf(e.burn_t, 3.0)
			e.burn_owner = p.owner
			e.burn_tower = p.tower
	for s in int(D.gnum(p, "shrapnel")):
		var a := TAU * s / int(p.shrapnel)
		add_projectile({"kind": "thorn", "owner": p.owner, "tower": p.tower, "x": p.x, "y": p.y, "vx": cos(a) * 430, "vy": sin(a) * 430,
			"damage": round(p.damage * 0.38), "pierce": 2, "ttl": 0.45, "radius": 5.0, "armorPierce": true, "detectCamo": true})
	for c in int(D.gnum(p, "cluster")):
		var a := TAU * c / int(p.cluster) + randf() * 0.4
		add_projectile({"kind": "cluster", "owner": p.owner, "tower": p.tower, "x": p.x + cos(a) * 14, "y": p.y + sin(a) * 14, "vx": cos(a) * 180, "vy": sin(a) * 180,
			"damage": round(p.damage * 0.55), "ttl": 0.32, "radius": 8.0, "splash": r * 0.6, "armorMult": D.gnum(p, "armorMult", 1.4), "armorPierce": true, "detectCamo": true})
	ev({"type": "explosion", "x": p.x, "y": p.y, "radius": r, "kind": "frost" if p.kind == "snowball" else "boom"})


func update_spring(dt: float) -> void:
	for h in heroes:
		if not hero_stats(h).get("springLife", false):
			continue
		h.spring_t -= dt
		if h.spring_t <= 0:
			h.spring_t = 40.0
			if lives < max_lives:
				lives += 1
				ev({"type": "spring_life", "x": h.x, "y": h.y, "owner": h.owner})


# ---------------------------------------------------------------------------
# Specials & team combos
# ---------------------------------------------------------------------------
func use_special(pid: int) -> void:
	var h = hero_of(pid)
	if h == null or h.special_cd > 0 or h.get("dead", false):
		return
	var st := hero_stats(h)
	h.special_cd = float(D.HERO_INFO[h.type].special.cooldown) * st.specialMult
	var dmg: float = st.damage
	var near := func(r: float) -> Array:
		return enemies.filter(func(e): return e.hp > 0 and not e.sheltered and dist(h.x, h.y, e.x, e.y) <= r)
	match h.type:
		"peashooter":
			for i in 24:
				var a := TAU * i / 24
				add_projectile({"kind": "megapea", "owner": pid, "tower": h.id, "x": h.x, "y": h.y, "vx": cos(a) * 560, "vy": sin(a) * 560,
					"damage": round(dmg * 1.6), "pierce": 4, "ttl": 0.9, "radius": 11.0, "armorPierce": true, "detectCamo": true, "knockback": 20.0})
		"sunblossom":
			for e in near.call(260):
				apply_damage(e, round(dmg * 3), pid, h.id, {"armorPierce": true})
			for o in heroes:
				if dist(o.x, o.y, h.x, h.y) <= 320:
					o.rally_t = 6.0
			for i in 3:
				var a := TAU * i / 3
				add_sun(h.x + cos(a) * 60, h.y + sin(a) * 60, 20 + h.level * 2, -1, 0.5, false, true)
		"frostlotus":
			for e in near.call(280):
				apply_damage(e, dmg, pid, h.id, {"armorPierce": true})
				e.freeze_t = maxf(e.freeze_t, 0.9 if e.boss else 2.5)
				e.slow = maxf(e.slow, 0.5)
				e.slow_t = maxf(e.slow_t, 5.0)
				e.brittle = maxf(e.brittle, D.gnum(st, "brittleBonus") + 0.2)
		"boomshroom":
			var pool: Array = near.call(st.range * 1.8)
			pool.sort_custom(func(a, b): return a.hp > b.hp)
			var c := Vector2(h.x, h.y) if pool.is_empty() else Vector2(pool[0].x, pool[0].y)
			for e in enemies:
				if e.hp <= 0 or dist(c.x, c.y, e.x, e.y) > 150:
					continue
				var d2: float = dmg * 5 * (D.gnum(st, "bossMult", 1.0) if e.boss else 1.0) * (1.5 if e.armored or e.lead or e.shielded else 1.0)
				apply_damage(e, round(d2), pid, h.id, {"armorPierce": true})
				e.stun_t = maxf(e.stun_t, 0.5 if e.boss else 1.2)
			ev({"type": "explosion", "x": c.x, "y": c.y, "radius": 150, "kind": "boom"})
		"voltcactus":
			var pool: Array = near.call(340)
			pool.sort_custom(func(a, b): return a.hp > b.hp)
			for e in pool.slice(0, 8):
				apply_damage(e, round(dmg * 3), pid, h.id, {"armorPierce": true})
				e.stun_t = maxf(e.stun_t, 0.4 if e.boss else 1.0)
				ev({"type": "thunder", "x": e.x, "y": e.y})
		"snapdragon":
			for e in near.call(230):
				e.camo = false
				apply_damage(e, round(dmg * 2.5), pid, h.id, {"armorPierce": true})
				e.burn_dps = maxf(e.burn_dps, D.gnum(st, "burnDps", 9) * 2.5)
				e.burn_t = maxf(e.burn_t, 5.0)
				e.burn_owner = pid
				e.burn_tower = h.id
			ev({"type": "flame", "x": h.x, "y": h.y, "angle": 0.0, "range": 230, "coneAngle": TAU, "ring": true})
		"bubblelily":
			for e in near.call(320):
				apply_damage(e, round(dmg * 2), pid, h.id, {"armorPierce": true})
				soak(e, 4.0)
				push_back(e, 140.0, Vector2(h.x, h.y))
			ev({"type": "tidal", "x": h.x, "y": h.y, "r": 320})
	ev({"type": "special", "heroType": h.type, "x": h.x, "y": h.y, "slot": h.slot, "owner": pid})
	players[pid].specials += 1
	check_combo(h)


func check_combo(h: Dictionary) -> void:
	var last := last_special
	last_special = {"hero": h.id, "owner": h.owner, "t": game_time, "x": h.x, "y": h.y}
	if last.is_empty() or last.owner == h.owner or game_time - last.t > 3 or dist(last.x, last.y, h.x, h.y) > 450:
		return
	var other = null
	for o in heroes:
		if o.id == last.hero:
			other = o
	if other == null:
		return
	last_special = {}
	var m := Vector2((h.x + other.x) / 2, (h.y + other.y) / 2)
	var dmg: float = (hero_stats(h).damage + hero_stats(other).damage) * 4
	for e in enemies:
		if e.hp > 0 and not e.sheltered and dist(m.x, m.y, e.x, e.y) <= 330:
			apply_damage(e, round(dmg * 0.6 if e.boss else dmg), h.owner, h.id, {"armorPierce": true})
	for o in heroes:
		o.special_cd = maxf(0.0, o.special_cd - 4)
	players[h.owner].combos += 1
	players[other.owner].combos += 1
	ev({"type": "combo", "x": m.x, "y": m.y, "slots": [other.slot, h.slot], "heroes": [other.type, h.type]})


# ---------------------------------------------------------------------------
# Bot Buddies (Adventure): chase pests, grab Sun, build towers
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
			p.brain = {"path": [], "pt": 0.0, "tx": -999.0, "ty": -999.0, "card_t": 1.2, "build_t": 2.0, "built": 0, "pref": "A" if randf() < 0.5 else "B"}
		var b: Dictionary = p.brain
		var idx := k
		k += 1
		if h.pending > 0 and h.offer.size() > 0:
			b.card_t -= dt
			if b.card_t <= 0:
				b.card_t = 1.0 + randf()
				var pick := -1
				for i in h.offer.size():
					if h.offer[i].kind == "path" and h.offer[i].path == b.pref:
						pick = i
				if pick < 0:
					for i in h.offer.size():
						if h.offer[i].kind == "path":
							pick = i
				pick_card(p.id, maxi(0, pick))
		if h.special_cd <= 0:
			var near := 0
			var big := false
			for e in enemies:
				if e.hp > 0 and not e.sheltered and dist(e.x, e.y, h.x, h.y) < 220:
					near += 1
					big = big or e.boss
			if near >= 3 or big:
				use_special(p.id)
		var st := hero_stats(h)
		var target := Vector2.INF
		for s in suns:
			if dist(s.x, s.y, h.x, h.y) < 190:
				target = Vector2(s.x, s.y)
		if target == Vector2.INF:
			for c in chests:
				target = Vector2(c.x, c.y)
		if target == Vector2.INF:
			var lead = null
			var own = null
			var my_path := idx % maxi(1, _paths.size())
			for e in enemies:
				if e.hp <= 0 or e.sheltered:
					continue
				if lead == null or e.progress > lead.progress:
					lead = e
				if e.path == my_path and (own == null or e.progress > own.progress):
					own = e
			var chase = own if own else lead
			if chase:
				var v := Vector2(chase.x - h.x, chase.y - h.y)
				var want := minf(st.range * 0.55, 120.0)
				target = Vector2(chase.x, chase.y) - v.normalized() * want if v.length() > want else Vector2(h.x, h.y)
			else:
				var hs := home_spot(p.slot)
				var c := Vector2(D.W / 2, D.H / 2)
				target = hs + (c - hs).normalized() * 160.0
		_bot_walk(h, b, target, st.moveSpeed * dt)
		b.build_t -= dt
		if b.build_t <= 0:
			b.build_t = 2.0
			var mine: Array = gadgets.filter(func(g): return g.owner == p.id)
			var near_path: Dictionary = D.nearest_path_point(map_id, h.x, h.y)
			var order := ["sentry", "fern", "mortar", "zap", "thorns"]
			var kind: String = order[b.built % order.size()]
			if mine.size() < 4 and near_path.d < 100 and p.acorns >= D.GADGETS[kind].cost + 20:
				var before := gadgets.size()
				plant(p.id, kind)
				if gadgets.size() > before:
					b.built += 1
			else:
				mine.sort_custom(func(a, c): return a.level < c.level)
				for g in mine:
					if g.level < 3 and not D.GADGETS[g.kind].get("once", false) and p.acorns >= D.gadget_upgrade_cost(g.kind, g.level) + 30:
						upgrade_gadget(p.id, g.id, randi() % 2)
						break


func _bot_walk(h: Dictionary, b: Dictionary, target: Vector2, step: float) -> void:
	b.pt -= TICK
	if b.pt <= 0 or Vector2(b.tx, b.ty).distance_to(target) > 40:
		b.path = D.find_path(map_id, h.x, h.y, target.x, target.y)
		b.tx = target.x
		b.ty = target.y
		b.pt = 0.6
	var wp: Vector2 = b.path[0] if b.path.size() > 0 else target
	while b.path.size() > 1 and wp.distance_to(Vector2(h.x, h.y)) < 6:
		b.path.pop_front()
		wp = b.path[0]
	var v := wp - Vector2(h.x, h.y)
	var d := v.length()
	if d < 3:
		return
	var n := Vector2(h.x, h.y) + v / d * minf(d, step)
	if D.is_walkable(map_id, n.x, n.y):
		if absf(n.x - h.x) > 0.3:
			h.facing = 1 if n.x > h.x else -1
		h.x = n.x
		h.y = n.y
		h.moved_t = 0.16
	else:
		b.pt = 0.0


# ---------------------------------------------------------------------------
# What gets drawn and sent to the other players
# ---------------------------------------------------------------------------
func snapshot() -> Dictionary:
	var hs: Array = []
	for h in heroes:
		var st := hero_stats(h)
		hs.append({"id": h.id, "owner": h.owner, "slot": h.slot, "type": h.type, "x": h.x, "y": h.y, "tierA": h.tierA, "tierB": h.tierB,
			"level": h.level, "xp": floor(h.xp), "xpNext": xp_needed(h.level), "cards": h.cards, "offer": h.offer, "pending": h.pending, "bonus": h.bonus,
			"specialCd": snappedf(h.special_cd, 0.1), "specialMax": snappedf(float(D.HERO_INFO[h.type].special.cooldown) * st.specialMult, 0.1),
			"dashCd": snappedf(h.dash_cd, 0.1), "homeCd": snappedf(h.home_cd, 0.1), "rally": h.rally_t > 0, "dazed": h.dazed_t > 0,
			"buffs": h.buffs, "moving": h.moved_t > 0, "facing": h.facing, "range": st.range, "angle": snappedf(h.angle, 0.01),
			"recoil": snappedf(h.recoil, 0.01), "pops": h.pops, "targetMode": h.target_mode,
			"hat": players[h.owner].hat if players.has(h.owner) else "none", "pet": players[h.owner].pet if players.has(h.owner) else "none"})
	var es: Array = []
	for e in enemies:
		es.append({"id": e.id, "type": e.type, "x": roundf(e.x), "y": roundf(e.y), "hp": maxf(0, round(e.hp)), "maxHp": e.max_hp, "camo": e.camo,
			"frozen": e.freeze_t > 0, "stunned": e.stun_t > 0, "slowed": e.slow_t > 0, "burning": e.burn_t > 0, "frostbit": e.get("frost_t", 0.0) > 0, "enraged": e.get("enraged", false), "flash": e.flash > 0,
			"sheltered": e.sheltered, "big": e.big, "resist": e.resist, "sunlit": e.sunlit_t > 0, "burrowed": e.burrowed,
			"poisoned": e.poison_t > 0, "soaked": e.soak_t > 0, "trapped": e.trap_t > 0, "boss": e.boss})
	var ps: Array = []
	for p in projectiles:
		ps.append({"id": p.id, "kind": p.kind, "x": roundf(p.x), "y": roundf(p.y), "vx": roundf(p.vx), "vy": roundf(p.vy)})
	var pl: Array = []
	for p in players.values():
		pl.append({"id": p.id, "name": p.name, "slot": p.slot, "hero": p.hero_type, "bot": p.is_bot, "acorns": p.acorns, "pops": p.pops,
			"damage": p.damage, "specials": p.specials, "reactions": p.reactions, "built": p.gadgets_planted, "hat": p.hat, "pet": p.pet,
			"combos": p.get("combos", 0), "sun": p.get("sun", 0), "chests": p.get("chests", 0)})
	var gs: Array = []
	for g in gadgets:
		gs.append({"id": g.id, "kind": g.kind, "x": roundf(g.x), "y": roundf(g.y), "slot": g.slot, "owner": g.owner, "level": g.level,
			"branch": g.branch, "angle": snappedf(g.angle, 0.01), "asleep": g.sleep_t > 0, "spent": g.spent})
	return {"phase": phase, "map": map_id, "difficulty": difficulty_id, "mode": mode, "endless": endless, "wave": wave, "maxWave": max_wave,
		"waveActive": wave_active, "lives": lives, "maxLives": max_lives, "twist": current_twist, "paused": paused, "speed": speed_mult,
		"autoWave": auto_wave, "time": game_time, "players": pl, "heroes": hs, "enemies": es, "projectiles": ps, "gadgets": gs,
		"toSpawn": spawn_queue.size(), "autoIn": snappedf(auto_wave_countdown, 0.1) if auto_wave and not wave_active and wave > 0 else 0.0,
		"nextTwist": plan_twist(wave + 1) if endless and not wave_active and phase == "playing" else "",
		"suns": suns.map(func(s): return {"id": s.id, "x": roundf(s.x), "y": roundf(s.y), "amount": s.amount, "sky": s.sky}),
		"chests": chests.map(func(c): return {"id": c.id, "x": roundf(c.x), "y": roundf(c.y), "big": c.big}),
		"powerups": powerups.map(func(p): return {"id": p.id, "kind": p.kind, "x": roundf(p.x), "y": roundf(p.y), "ttl": p.ttl}),
		"spikes": spikes.map(func(s): return {"id": s.id, "x": roundf(s.x), "y": roundf(s.y), "slot": s.slot}),
		"wisps": wisps.map(func(w): return {"id": w.id, "x": roundf(w.x), "y": roundf(w.y), "slot": w.slot}),
		"events": events.duplicate()}
