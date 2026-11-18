class_name Couch
extends Node
## Couch co-op: up to 3 more players on game controllers, playing on this
## computer (solo games and LAN hosts). Press Start or A on a controller during
## a game, pick a hero with the D-pad, and press A to jump in.
##
## Controller buttons (Xbox names; PlayStation: A=Cross, B=Circle, X=Square, Y=Triangle)
##   Left stick  walk          A  Leaf Leap          X  special
##   Y   build (Adventure) / Berry Juice (Clash)     B  upgrade tower / go home (Clash)
##   LB/RB  pick a tower  (Clash: LB juice, RB buy the next item at the tree)
##   D-pad ◀ ▲ ▶  pick card 1 / 2 / 3       ▼  home
##   Back  sell tower     R3  targeting
##   Start  start the next wave (when the green button shows), otherwise the menu

const DEADZONE := 0.25
const FIRST_ID := 11  # couch players are 11..14 (bots are 100+, LAN friends are big numbers)
const NAMES := ["Player 2", "Player 3", "Player 4", "Player 5"]
const HATS := ["cap", "party", "wizard", "propeller"]
const PETS := ["bee", "bunny", "snail", "froggy"]

var main: Node
## device -> {"pid": id (main.my_id for P1), "state": "join"|"play", "hero_i", "gadget", "arm": {id, until}}
var pads := {}
var p1_pad := false  # profile option: the first controller plays as P1


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed)


func reset() -> void:
	pads.clear()


## Couch players (not P1) in this game: pid -> pad state
func players() -> Dictionary:
	var out := {}
	for dev in pads:
		var p: Dictionary = pads[dev]
		if p.state == "play" and p.pid != main.my_id:
			out[p.pid] = p
	return out


func joining() -> Array:
	var out: Array = []
	for dev in pads:
		if pads[dev].state == "join":
			out.append(pads[dev])
	return out


func p1_device() -> int:
	for dev in pads:
		if pads[dev].pid == main.my_id and pads[dev].state == "play":
			return dev
	return -1


## P1's left stick (when a controller plays as P1)
func p1_stick() -> Vector2:
	var dev := p1_device()
	return _stick(dev) if dev >= 0 else Vector2.ZERO


func _stick(dev: int) -> Vector2:
	var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
	return Vector2.ZERO if v.length() < DEADZONE else v.limit_length(1.0)


func _on_joy_changed(device: int, connected: bool) -> void:
	if connected or not pads.has(device):
		return
	var p: Dictionary = pads[device]
	pads.erase(device)
	if p.state == "play" and p.pid != main.my_id and main.host:
		main.host.sim.remove_player(p.pid)
		main.hud.toast("🎮 %s's controller was unplugged" % p.name, Color("fca5a5"))


func _can_couch() -> bool:
	return main.playing and main.host != null and not main.attract and not main.snap.is_empty() and main.snap.phase == "playing"


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	var b := (event as InputEventJoypadButton).button_index
	var dev := event.device
	if not main.playing or main.snap.is_empty():
		return
	if not pads.has(dev):
		if b != JOY_BUTTON_START and b != JOY_BUTTON_A:
			return
		if p1_pad and p1_device() < 0:
			pads[dev] = {"pid": main.my_id, "state": "play", "name": "P1", "gadget": "sentry", "arm": {}}
			main.hud.toast("🎮 Controller connected: it plays as you", Color("bbf7d0"), 2.5)
		elif not _can_couch():
			if main.net:
				main.hud.toast("🎮 Controllers can join on the computer that hosts the game", Color("fca5a5"), 3.0)
			return
		else:
			pads[dev] = {"pid": -1, "state": "join", "hero_i": _free_hero_index(), "name": NAMES[mini(players().size(), 3)], "gadget": "sentry", "arm": {}, "device": dev}
		get_viewport().set_input_as_handled()
		return
	var p: Dictionary = pads[dev]
	get_viewport().set_input_as_handled()
	if p.state == "join":
		match b:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
				p.hero_i = posmod(p.hero_i - 1, GameData.HERO_ORDER.size())
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER:
				p.hero_i = posmod(p.hero_i + 1, GameData.HERO_ORDER.size())
			JOY_BUTTON_A, JOY_BUTTON_START:
				_join(dev)
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				pads.erase(dev)
		return
	if b == JOY_BUTTON_START:
		if main.hud.menu_open:
			main.close_pause_menu()
		elif main.wave_ready():
			main.send({"t": "wave"})  # "Ready!": the same as Space or the green button
		else:
			main.open_pause_menu()
		return
	if main.hud.menu_open or main.snap.paused:
		if main.hud.menu_open and b == JOY_BUTTON_B:
			main.close_pause_menu()
		return
	if p.pid == main.my_id:
		_p1_button(b, p)
	else:
		_couch_button(b, p)


func _join(dev: int) -> void:
	var p: Dictionary = pads[dev]
	if not _can_couch():
		pads.erase(dev)
		return
	var sim: SimWorld = main.host.sim
	if sim.players.size() >= 4:
		for pid in sim.players.keys():
			if sim.players[pid].is_bot:
				main.hud.toast("%s takes over from %s" % [p.name, sim.players[pid].name], Color("86efac"))
				sim.remove_player(pid)
				break
	if sim.players.size() >= 4:
		main.hud.toast("🎮 The team is full (4 players)", Color("fca5a5"))
		pads.erase(dev)
		return
	var pid := FIRST_ID
	while sim.players.has(pid):
		pid += 1
	var k := pid - FIRST_ID
	p.pid = pid
	p.state = "play"
	p.hero = GameData.HERO_ORDER[p.hero_i]
	p.hat = HATS[k % HATS.size()]
	p.pet = PETS[k % PETS.size()]
	main.host.add_player(pid, p.name, p.hero, false, p.hat, p.pet)
	main.hud.toast("🎮 %s joined as %s!" % [p.name, GameData.TOWERS[p.hero].name], Color("86efac"), 3.0)


func _free_hero_index() -> int:
	var used := {}
	for x in main.snap.get("heroes", []):
		used[x.type] = true
	for i in GameData.HERO_ORDER.size():
		if not used.has(GameData.HERO_ORDER[i]):
			return i
	return 0


## A controller playing as P1 uses the same actions as the keyboard
func _p1_button(b: int, p: Dictionary) -> void:
	var clash: bool = main.snap.has("clash")
	match b:
		JOY_BUTTON_A: main.dash()
		JOY_BUTTON_X: main.send({"t": "special"})
		JOY_BUTTON_Y:
			if clash:
				main.send({"t": "potion"})
			elif main.clock < main.branch_arm_until:
				main.upgrade_key(1)
			else:
				main.send({"t": "plant", "kind": main.selected_gadget})
				main.ghost_until = main.clock + 1.2
		JOY_BUTTON_B:
			if clash:
				main.send({"t": "home"})
			else:
				main.upgrade_key(0)
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			if clash:
				_clash_buy(main.my_id, b == JOY_BUTTON_RIGHT_SHOULDER)
			else:
				var i := GameData.GADGET_ORDER.find(main.selected_gadget)
				var step := 1 if b == JOY_BUTTON_RIGHT_SHOULDER else -1
				main.pick_gadget(GameData.GADGET_ORDER[posmod(i + step, GameData.GADGET_ORDER.size())])
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT:
			main.send({"t": "card", "i": {JOY_BUTTON_DPAD_LEFT: 0, JOY_BUTTON_DPAD_UP: 1, JOY_BUTTON_DPAD_RIGHT: 2}[b]})
		JOY_BUTTON_DPAD_DOWN:
			main.send({"t": "home"})
		JOY_BUTTON_BACK:
			if not clash:
				main.send({"t": "sell"})
		JOY_BUTTON_RIGHT_STICK:
			if not clash:
				main.cycle_target()


func _couch_button(b: int, p: Dictionary) -> void:
	var pid: int = p.pid
	var sim: SimWorld = main.host.sim
	var h = sim.hero_of(pid)
	if h == null:
		return
	var clash: bool = main.snap.has("clash")
	var act := func(a: Dictionary): main.host.apply(pid, a)
	match b:
		JOY_BUTTON_A:
			var v := _stick(p.device if p.has("device") else -1)
			if v == Vector2.ZERO:
				v = Vector2(h.facing, 0)
			act.call({"t": "dash", "dx": v.x, "dy": v.y})
		JOY_BUTTON_X:
			act.call({"t": "special"})
		JOY_BUTTON_Y:
			if clash:
				act.call({"t": "potion"})
			elif not p.arm.is_empty() and main.clock < p.arm.until:
				act.call({"t": "upgrade", "id": p.arm.id, "branch": 1})
				p.arm = {}
			else:
				act.call({"t": "plant", "kind": p.gadget})
		JOY_BUTTON_B:
			if clash:
				act.call({"t": "home"})
			elif not p.arm.is_empty() and main.clock < p.arm.until:
				act.call({"t": "upgrade", "id": p.arm.id, "branch": 0})
				p.arm = {}
			else:
				act.call({"t": "upgrade"})
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			if clash:
				_clash_buy(pid, b == JOY_BUTTON_RIGHT_SHOULDER)
			else:
				var i := GameData.GADGET_ORDER.find(String(p.gadget))
				p.gadget = GameData.GADGET_ORDER[posmod(i + (1 if b == JOY_BUTTON_RIGHT_SHOULDER else -1), GameData.GADGET_ORDER.size())]
				var d: Dictionary = GameData.GADGETS[p.gadget]
				main.hud.toast("%s: %s %s selected (%d acorns). Y builds it." % [p.name, d.icon, d.name, int(d.cost)], Color("bbf7d0"), 2.0)
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT:
			act.call({"t": "card", "i": {JOY_BUTTON_DPAD_LEFT: 0, JOY_BUTTON_DPAD_UP: 1, JOY_BUTTON_DPAD_RIGHT: 2}[b]})
		JOY_BUTTON_DPAD_DOWN:
			act.call({"t": "home"})
		JOY_BUTTON_BACK:
			if not clash:
				act.call({"t": "sell"})
		JOY_BUTTON_RIGHT_STICK:
			if not clash:
				var modes := ["first", "strong", "close", "last"]
				var nxt: String = modes[(modes.find(String(h.target_mode)) + 1) % modes.size()]
				act.call({"t": "target", "mode": nxt})
				main.hud.toast("%s: 🎯 shoots %s first" % [p.name, {"first": "the front pest", "strong": "the toughest pest", "close": "the closest pest", "last": "the last pest"}[nxt]], Color("bae6fd"), 2.0)


## Garden Clash shop on a controller: RB buys the pinned item or the shop's pick for this hero, LB a Berry Juice
func _clash_buy(pid: int, item: bool) -> void:
	if not item:
		if pid == main.my_id:
			main.send({"t": "buy", "item": "juice"})
		else:
			main.host.apply(pid, {"t": "buy", "item": "juice"})
		return
	if pid == main.my_id and main.hud.can_buy_pinned() and main.buy_pinned():
		return  # player 1 pinned something in the shop
	var h := {}
	for x in main.snap.get("heroes", []):
		if x.owner == pid:
			h = x
	# the shop's first pick for this hero, then Golden upgrades
	var picks := ClashWorld.recommended_buys(GameData, String(h.get("type", "")), h.get("items", []), 1)
	if picks.is_empty():
		return
	var pick: String = picks[0]
	if pid == main.my_id:
		main.send({"t": "buy", "item": pick})
	else:
		main.host.apply(pid, {"t": "buy", "item": pick})


## Events for couch players (P1's own events are handled in main.gd)
func on_event(e: Dictionary) -> void:
	var pid := int(e.get("owner", -999))
	var mine := players()
	if not mine.has(pid):
		return
	var p: Dictionary = mine[pid]
	match String(e.type):
		"gadget_fail":
			main.hud.toast("%s: %s" % [p.name, e.reason], Color("fca5a5"), 2.5)
		"gadget_choose":
			var d: Dictionary = GameData.GADGETS[e.kind]
			p.arm = {"id": int(e.id), "until": main.clock + 5.0}
			main.hud.toast("%s: pick a power! B = %s %s, Y = %s %s" % [p.name, d.branches[0].icon, d.branches[0].name, d.branches[1].icon, d.branches[1].name], Color("fde047"), 5.0)
		"level_up":
			main.hud.toast("%s reached level %d! D-pad picks a card" % [p.name, int(e.level)], Color("fde047"), 2.5)


# ---------------------------------------------------------------------------
# Walking (every frame, straight into the local simulation)
# ---------------------------------------------------------------------------
func _process(dt: float) -> void:
	if not _can_couch() or main.snap.paused or main.hud.menu_open:
		return
	var sim: SimWorld = main.host.sim
	for dev in pads:
		var p: Dictionary = pads[dev]
		p.device = dev
		if p.state != "play" or p.pid == main.my_id:
			continue
		var h = sim.hero_of(p.pid)
		if h == null or h.get("dead", false):
			continue
		var v := _stick(dev)
		if v == Vector2.ZERO:
			continue
		var step: float = sim.hero_stats(h).moveSpeed * sim.speed_mult * dt * v.length()
		var at := Vector2(h.x, h.y)
		var n := at + v.normalized() * step
		if not GameData.is_walkable(sim.map_id, n.x, n.y):
			if GameData.is_walkable(sim.map_id, n.x, at.y):
				n = Vector2(n.x, at.y)
			elif GameData.is_walkable(sim.map_id, at.x, n.y):
				n = Vector2(at.x, n.y)
			else:
				continue
		main.host.apply(p.pid, {"t": "move", "x": n.x, "y": n.y})
