class_name NetClient
extends Node
## LAN client: connects to a host, sends this player's actions and receives
## lobby updates and game snapshots.

signal lobby_changed

var main: Node
var peer: ENetMultiplayerPeer
var mp: SceneMultiplayer
var cfg: Dictionary = {}
var lobby: Array = []
var host_cfg: Dictionary = {}
var my_id := 0
var in_game := false
var status := "Connecting…"
var failed := false
var packets := 0


func join(c: Dictionary) -> void:
	cfg = c
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(String(c.address), NetHost.PORT)
	if err != OK:
		status = "Could not reach %s" % c.address
		failed = true
		return
	mp = SceneMultiplayer.new()
	mp.root_path = get_path()
	mp.multiplayer_peer = peer
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(func(): _fail("Could not connect to %s. Is the host's game open?" % c.address))
	mp.server_disconnected.connect(func(): _fail("The host closed the game."))
	mp.peer_packet.connect(_on_packet)
	status = "Connecting to %s…" % c.address


func close() -> void:
	if peer:
		peer.close()
	peer = null
	mp = null


func players_for_menu() -> Array:
	return lobby


func _process(_delta: float) -> void:
	if mp:
		mp.poll()


func _fail(why: String) -> void:
	print("[lan] ", why)
	status = why
	failed = true
	lobby = []
	lobby_changed.emit()
	if in_game:
		in_game = false
		# never tear the connection down from inside its own poll() callback
		main.call_deferred("show_menu")
		main.menu.call_deferred("show_error", why)


func _send(d: Dictionary, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0) -> void:
	if mp and peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		mp.send_bytes(NetCommon.encode(d), 1, mode, channel)


func send_action(a: Dictionary) -> void:
	if a.get("t", "") == "move":
		_send({"m": "act", "a": a}, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)
	else:
		_send({"m": "act", "a": a})


func pick_hero(hero: String) -> void:
	cfg.hero = hero
	_send({"m": "pick", "hero": hero})


func _on_connected() -> void:
	my_id = mp.get_unique_id()
	status = "Connected! Waiting for the host to start…"
	_send({"m": "hello", "ver": NetHost.VERSION, "name": cfg.get("name", "Player"), "hero": cfg.get("hero", "peashooter"), "hat": cfg.get("hat", "none"), "pet": cfg.get("pet", "none")})
	lobby_changed.emit()


func _on_packet(_id: int, bytes: PackedByteArray) -> void:
	packets += 1
	var d := NetCommon.decode(bytes)
	match String(d.get("m", "")):
		"welcome":
			my_id = int(d.id)
		"refuse":
			_fail(String(d.get("why", "The host said no.")))
			call_deferred("close")
		"lobby":
			lobby = d.get("players", [])
			host_cfg = d.get("cfg", {})
			lobby_changed.emit()
		"start":
			in_game = true
			status = "Playing!"
			main.start_remote(my_id)
		"snap":
			if in_game and typeof(d.get("s")) == TYPE_DICTIONARY:
				main._on_snapshot(d.s)
		"ev":
			if in_game and typeof(d.get("e")) == TYPE_ARRAY:
				main.handle_events(d.e)
		"bye":
			_fail("The host closed the game.")
