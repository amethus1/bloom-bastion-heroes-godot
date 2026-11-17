class_name LanFinder
extends Node
## Listens for LAN game beacons (UDP broadcast) so players can see games on
## the same Wi-Fi without typing addresses.

signal games_changed

const STALE := 4.0

var udp := PacketPeerUDP.new()
var games := {}  # ip -> {name, players, max, port, inGame, seen}
var listening := false
var _t := 0.0


func start() -> bool:
	stop()
	listening = udp.bind(NetHost.BEACON_PORT) == OK
	return listening


func stop() -> void:
	if listening:
		udp.close()
	listening = false
	games.clear()


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if not listening:
		return
	_t += delta
	var changed := false
	while udp.get_available_packet_count() > 0:
		var pkt := udp.get_packet()
		var ip := udp.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY or d.get("game", "") != NetHost.GAME_ID:
			continue
		if not games.has(ip):
			changed = true
		d.seen = _t
		games[ip] = d
	for ip in games.keys():
		if _t - float(games[ip].seen) > STALE:
			games.erase(ip)
			changed = true
	if changed:
		games_changed.emit()
