class_name NetHost
extends Node
## LAN host: runs the real game (through GameHost) and talks to up to 3 other
## computers over ENet. Channel 0 is reliable (lobby, actions); channel 1 is
## unreliable-ordered (walking, snapshots at 20 Hz). A UDP beacon announces
## the game so others can find it.

signal lobby_changed

const PORT := 24680
const BEACON_PORT := 24681
const GAME_ID := "bloom-bastion-heroes-godot"
const VERSION := 1
const SNAP_INTERVAL := 0.05
## Events that change what a player sees or can do: sent reliably (a lost
## snapshot packet only loses cosmetic effects like sparks and numbers)
const RELIABLE_EVENTS := ["game_started", "wave_start", "wave_clear", "milestone", "victory", "game_over", "level_up",
	"hero_upgraded", "chest_drop", "chest_open", "gadget_placed", "gadget_upgraded", "gadget_sold", "gadget_choose",
	"gadget_fail", "powerup_get", "combo", "special", "teleport", "dash", "hero_spawn", "boss_enrage", "spring_life",
	"clash_start", "struct_down", "hero_down", "revive", "hero_respawn", "rival_spawn", "rival_down", "camp_up",
	"camp_down", "gate_regrow", "tower_alert", "item_bought", "item_sold", "potion", "recall_start", "recall_cancel",
	"emote", "ping", "eshop"]

var main: Node
var peer: ENetMultiplayerPeer
var mp: SceneMultiplayer
var cfg: Dictionary = {}
var lobby: Array = []  # remote players: {id, name, hero, hat, pet}
var host: GameHost
var in_game := false
var status := ""

var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0
var _snap_t := 0.0
var _events: Array = []
var _last: Dictionary = {}


func open(c: Dictionary) -> bool:
	cfg = c
	peer = ENetMultiplayerPeer.new()
	if String(c.get("bind", "")) != "":
		peer.set_bind_ip(String(c.bind))  # tests bind to 127.0.0.1 only
	if peer.create_server(PORT, 3) != OK:
		return false
	mp = SceneMultiplayer.new()
	mp.root_path = get_path()
	mp.multiplayer_peer = peer
	mp.peer_connected.connect(_on_connected)
	mp.peer_disconnected.connect(_on_disconnected)
	mp.peer_packet.connect(_on_packet)
	_beacon.set_broadcast_enabled(true)
	status = "Waiting for friends on this Wi-Fi… They press Join LAN Game, or type your address."
	return true


func close() -> void:
	if mp and peer:
		_send_all({"m": "bye"})
		peer.close()
	peer = null
	mp = null
	_beacon.close()


static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func players_for_menu() -> Array:
	var out: Array = [{"id": 1, "name": cfg.get("name", "Host"), "hero": cfg.get("hero", "peashooter"), "hat": cfg.get("hat", "none"), "pet": cfg.get("pet", "none"), "host": true, "ready": true}]
	out.append_array(lobby)
	return out


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if mp == null:
		return
	mp.poll()
	_beacon_t -= delta
	if _beacon_t <= 0:
		_beacon_t = 1.0
		var info := JSON.stringify({"game": GAME_ID, "ver": VERSION, "name": "%s's garden" % cfg.get("name", "Host"),
			"players": 1 + lobby.size(), "max": 4, "port": PORT, "inGame": in_game, "map": cfg.get("map", "meadow"),
			"diff": cfg.get("diff", "normal"), "mode": cfg.get("gameMode", "adventure"), "wave": host.sim.wave if host and in_game else 0}).to_utf8_buffer()
		for dest in ["255.255.255.255", "127.0.0.1"]:
			_beacon.set_dest_address(dest, BEACON_PORT)
			_beacon.put_packet(info)
	if in_game and host:
		_snap_t -= delta
		if _snap_t <= 0 and not _last.is_empty():
			_snap_t = SNAP_INTERVAL
			var s := _last.duplicate()
			var fx: Array = []
			var key: Array = []
			for e in _events:
				(key if String(e.get("type", "")) in RELIABLE_EVENTS else fx).append(e)
			_events = []
			s.events = fx
			if not key.is_empty():
				_send_all({"m": "ev", "e": key})
			_send_all({"m": "snap", "s": s}, true, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)


func attach_host(h: GameHost) -> void:
	host = h
	host.snapshot_ready.connect(_on_host_snapshot)
	in_game = true


func _on_host_snapshot(s: Dictionary) -> void:
	_last = s
	_events.append_array(s.get("events", []))
	if _events.size() > 400:
		_events = _events.slice(_events.size() - 400)


## Host pressed Start in the lobby
func start_game() -> void:
	main.start_local(cfg, false, lobby)
	_send_all({"m": "start"})
	_send_lobby()


## The host changing its own hero/hat/pet, or the game settings, in the lobby
func ready_count() -> Array:
	var n := 0
	for p in lobby:
		if p.get("ready", false):
			n += 1
	return [n, lobby.size()]


func set_my_pick(key: String, value: String) -> void:
	cfg[key] = value
	_send_lobby()


func set_option(key: String, value) -> void:
	cfg[key] = value
	_send_lobby()


func restart() -> void:
	start_game()


# ---------------------------------------------------------------------------
func _send(id: int, d: Dictionary, compress := false, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0) -> void:
	if mp:
		mp.send_bytes(NetCommon.encode(d, compress), id, mode, channel)


func _send_all(d: Dictionary, compress := false, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0) -> void:
	if mp and not lobby.is_empty():
		mp.send_bytes(NetCommon.encode(d, compress), 0, mode, channel)


func _send_lobby() -> void:
	_send_all({"m": "lobby", "players": players_for_menu(), "cfg": {"map": cfg.map, "diff": cfg.diff, "gameMode": cfg.gameMode, "bots": cfg.bots}, "inGame": in_game})
	lobby_changed.emit()


func _on_connected(id: int) -> void:
	status = "A friend is connecting…"
	lobby_changed.emit()


func _on_disconnected(id: int) -> void:
	for p in lobby:
		if p.id == id:
			lobby.erase(p)
			if host:
				host.sim.remove_player(id)
				main.hud.toast("%s left the game" % p.name, Color("fca5a5"))
			break
	_send_lobby()


func _on_packet(id: int, bytes: PackedByteArray) -> void:
	var d := NetCommon.decode(bytes)
	match String(d.get("m", "")):
		"hello":
			if int(d.get("ver", 0)) != VERSION:
				_send(id, {"m": "refuse", "why": "That computer has a different version of the game."})
				return
			if lobby.size() >= 3:
				_send(id, {"m": "refuse", "why": "This game is full (4 players)."})
				return
			var hero := String(d.get("hero", "peashooter"))
			if not GameData.HERO_ORDER.has(hero):
				hero = "peashooter"
			var p := {"id": id, "name": NetCommon.clean_name(String(d.get("name", ""))), "hero": hero, "hat": String(d.get("hat", "none")), "pet": String(d.get("pet", "none")), "ready": false}
			lobby.append(p)
			_send(id, {"m": "welcome", "id": id})
			status = "%s joined!" % p.name
			if in_game and host and host.sim.phase == "playing":
				if host.sim.players.size() >= 4:
					# the game is full: the new friend takes over from a Bot Buddy
					for pid in host.sim.players.keys():
						if host.sim.players[pid].is_bot:
							main.hud.toast("%s takes over from %s" % [p.name, host.sim.players[pid].name], Color("86efac"))
							host.sim.remove_player(pid)
							break
				if host.sim.players.size() >= 4:
					lobby.erase(p)
					_send(id, {"m": "refuse", "why": "This game is full (4 players)."})
					return
				host.add_player(id, p.name, p.hero, false, p.hat, p.pet)
				_send(id, {"m": "start"})
				main.hud.toast("%s joined the game!" % p.name, Color("86efac"))
			_send_lobby()
		"act":
			if host and in_game and typeof(d.get("a")) == TYPE_DICTIONARY:
				var a: Dictionary = d.a
				if String(a.get("t", "")) in ["pause", "speed", "auto"]:
					return  # only the host controls the game speed
				host.apply(id, a)
		"ready":
			for p in lobby:
				if p.id == id:
					p.ready = bool(d.get("on", false))
			_send_lobby()
		"pick":
			for p in lobby:
				if p.id != id:
					continue
				if GameData.HERO_ORDER.has(String(d.get("hero", ""))):
					p.hero = String(d.hero)
				for k in ["hat", "pet"]:
					if d.has(k):
						p[k] = String(d[k])
			_send_lobby()
