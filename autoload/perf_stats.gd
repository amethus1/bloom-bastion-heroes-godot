class_name PerfStats
extends RefCounted
## Tiny timing helper for --perflog: PerfStats.add("sim", usec)

static var on := false  # turned on by --perflog; otherwise add() does nothing
static var totals := {}


static func add(key: String, usec: int) -> void:
	if on:
		totals[key] = int(totals.get(key, 0)) + usec


static func take() -> Dictionary:
	var out := totals
	totals = {}
	return out
