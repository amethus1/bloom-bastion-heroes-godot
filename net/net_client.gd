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
## Wi-Fi dropped in the middle of a game: keep trying to get back in (the host
## keeps your hero for you)
const RETRIES := 20
const RETRY_EVERY := 2.5
var reconnecting := false
var _tries := 0
var _retry_t := 0.0
var _key := ""


func join(c: Dictionary) -> void:
	cfg = c
	_key = Profile.client_key()
	_connect()


func _connect() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(String(cfg.address), NetHost.PORT)
	if err != OK:
		peer = null
		if reconnecting:
			_retry_t = RETRY_EVERY  # the network isn't back yet: try again soon
			main.hud.net_trouble = "📶 Lost the host. Reconnecting… (try %d of %d)" % [_tries + 1, RETRIES]
			return
		status = "Could not reach %s" % cfg.address
		failed = true
		return
	mp = SceneMultiplayer.new()
	mp.root_path = get_path()
	mp.multiplayer_peer = peer
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(func(): _dropped("Could not connect to %s. Is the host's game open?" % cfg.address))
	mp.server_disconnected.connect(func(): _dropped("Lost the connection to the host."))
	mp.peer_packet.connect(_on_packet)
	if not reconnecting:
		status = "Connecting to %s…" % cfg.address


## The connection went away. In a game, try again for a while (Wi-Fi blips);
## in the lobby, just say so.
func _dropped(why: String) -> void:
	if (in_game or reconnecting) and _tries < RETRIES:
		if not reconnecting:
			print("[lan] lost the host; reconnecting")
		reconnecting = true
		_retry_t = RETRY_EVERY
		main.hud.net_trouble = "📶 Lost the host. Reconnecting… (try %d of %d)" % [_tries + 1, RETRIES]
		call_deferred("_drop_peer")
		return
	main.hud.net_trouble = ""
	reconnecting = false
	_fail(why)


func _drop_peer() -> void:
	if peer:
		peer.close()
	peer = null
	mp = null


## Test-only (--dropat): pretend the Wi-Fi went away for a moment
func simulate_drop() -> void:
	_drop_peer()
	_dropped("test drop")


func close() -> void:
	if peer:
		peer.close()
	peer = null
	mp = null


func players_for_menu() -> Array:
	return lobby


func _process(delta: float) -> void:
	if mp:
		mp.poll()
	elif reconnecting:
		_retry_t -= delta
		if _retry_t <= 0:
			_tries += 1
			if _tries > RETRIES:
				reconnecting = false
				main.hud.net_trouble = ""
				_fail("Lost the connection to the host.")
			else:
				_connect()


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
	set_my_pick("hero", hero)


var is_ready_now := false


func set_ready(on: bool) -> void:
	is_ready_now = on
	_send({"m": "ready", "on": on})


func set_my_pick(key: String, value: String) -> void:
	cfg[key] = value
	_send({"m": "pick", key: value})


func _on_connected() -> void:
	my_id = mp.get_unique_id()
	if not reconnecting:
		status = "Connected! Waiting for the host to start…"
	_send({"m": "hello", "ver": NetHost.VERSION, "name": cfg.get("name", "Player"), "hero": cfg.get("hero", "peashooter"), "hat": cfg.get("hat", "none"), "pet": cfg.get("pet", "none"), "key": _key})
	lobby_changed.emit()


func _on_packet(_id: int, bytes: PackedByteArray) -> void:
	packets += 1
	var d := NetCommon.decode(bytes)
	match String(d.get("m", "")):
		"welcome":
			my_id = int(d.id)
			if reconnecting:
				# back on the network: the host sends "start" if our hero is still in its game
				get_tree().create_timer(5.0).timeout.connect(func():
					if reconnecting and mp:
						reconnecting = false
						main.hud.net_trouble = ""
						_fail("Back on the network, but the host's game has ended."))
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
			if reconnecting:
				reconnecting = false
				_tries = 0
				main.hud.net_trouble = ""
				main.hud.toast("📶 Back in the game!", Color("86efac"))
			main.start_remote(my_id)
		"snap":
			if in_game and typeof(d.get("s")) == TYPE_DICTIONARY:
				main._on_snapshot(d.s)
		"ev":
			if in_game and typeof(d.get("e")) == TYPE_ARRAY:
				main.handle_events(d.e)
		"bye":
			_fail("The host closed the game.")
