class_name GameHost
extends Node
## Runs the authoritative simulation at a fixed 30 Hz and applies player
## actions. Used for solo play and by the LAN host (net_host.gd forwards the
## snapshots to the other computers).

signal snapshot_ready(s: Dictionary)

var sim: SimWorld
var acc := 0.0
var running := false


func _init(clash := false) -> void:
	sim = ClashWorld.new(GameData) if clash else SimWorld.new(GameData)


func add_player(id: int, name: String, hero: String, bot := false, hat := "none", pet := "none") -> void:
	sim.add_player(id, name, hero, bot, hat, pet)


func start(map: String, difficulty: String, mode: String) -> void:
	sim.start(map, difficulty, mode)
	acc = 0.0
	running = true
	_emit()


## Every action a player can send (from this computer or over the LAN)
func apply(pid: int, a: Dictionary) -> void:
	if not sim.players.has(pid):
		return
	match String(a.get("t", "")):
		"move": sim.move_hero(pid, float(a.x), float(a.y))
		"dash": sim.dash(pid, float(a.dx), float(a.dy))
		"home": sim.teleport_home(pid)
		"wave": sim.start_wave()
		"card": sim.pick_card(pid, int(a.i))
		"special": sim.use_special(pid)
		"plant": sim.plant(pid, String(a.kind))
		"upgrade": sim.upgrade_gadget(pid, int(a.get("id", -1)), int(a.get("branch", -1)))
		"sell": sim.sell_gadget(pid)
		"pause": sim.paused = not sim.paused
		"speed": sim.speed_mult = 2.0 if sim.speed_mult < 1.5 else 1.0
		"auto": sim.auto_wave = not sim.auto_wave
		"target": sim.set_target_mode(pid, String(a.get("mode", "first")))
		"emote": sim.emote(pid, String(a.get("id", "")))
		"ping": sim.ping(pid, float(a.get("x", 0)), float(a.get("y", 0)))
		"eshop": sim.endless_shop(pid, String(a.get("item", "")))
		# Garden Clash
		"buy":
			if sim is ClashWorld:
				sim.buy(pid, String(a.get("item", "")))
		"sell_item":
			if sim is ClashWorld:
				sim.sell_item(pid, int(a.get("i", -1)))
		"potion":
			if sim is ClashWorld:
				sim.potion(pid)


func _process(delta: float) -> void:
	if not running:
		return
	acc += minf(delta, 0.25)
	var n := 0
	while acc >= SimWorld.TICK and n < 8:
		acc -= SimWorld.TICK
		n += 1
		var t0 := Time.get_ticks_usec()
		sim.step(SimWorld.TICK)
		var t1 := Time.get_ticks_usec()
		_emit()
		PerfStats.add("sim", t1 - t0)
		PerfStats.add("snapshot+view", Time.get_ticks_usec() - t1)
	if sim.phase != "playing":
		running = false


func _emit() -> void:
	var s := sim.snapshot()
	sim.events.clear()
	snapshot_ready.emit(s)


func alpha() -> float:
	return acc / SimWorld.TICK
