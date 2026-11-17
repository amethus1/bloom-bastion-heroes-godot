class_name SaveGame
extends RefCounted
## Save & resume for solo Adventure / Endless runs: the game saves itself
## after every cleared wave, and the title screen offers "Continue".
## One save slot, stored in user://autosave.save (binary, no objects).

static var path := "user://autosave.save"
const VERSION := 1
## Everything a game between waves needs (no pests are out then)
const KEYS := ["map_id", "difficulty_id", "mode", "endless", "wave", "max_wave", "lives", "max_lives", "game_time",
	"current_twist", "twist_plan", "wave_hp_boost", "sky_sun_t", "powerup_cd", "gold_chests", "perfect_streak",
	"lives_at_wave_start", "overclock_t", "life_bought_wave", "boss_chests", "players", "heroes", "gadgets", "spikes",
	"wisps", "chests", "powerups", "suns", "mutators", "_next_id"]


## Called after a wave is cleared. Returns true if it saved.
static func save(sim: SimWorld, cfg: Dictionary, run_id: int) -> bool:
	if sim.is_clash() or sim.phase != "playing" or sim.wave_active or sim.practice:
		return false
	var state := {}
	for k in KEYS:
		var v = sim.get(k)
		state[k] = v.duplicate(true) if v is Dictionary or v is Array else v
	for h in state.heroes:
		h._st = null
	for p in state.players.values():
		p.erase("brain")
	state.features = sim.features.list.duplicate(true)
	var c := {}
	for k in ["map", "diff", "gameMode", "hero", "name", "hat", "pet", "bots"]:
		if cfg.has(k):
			c[k] = cfg[k]
	var data := {"v": VERSION, "run": run_id, "cfg": c, "state": state, "when": Time.get_datetime_string_from_system(false, true)}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data, false)
	return true


## The saved game, or {} if there is none (or it's from an older version)
static func info() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var(false)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) != VERSION or typeof(d.get("state")) != TYPE_DICTIONARY:
		return {}
	return d


## One line for the title screen: "Sunny Meadow · Normal · wave 7 of 25"
static func describe(d: Dictionary, data: GameDataLib) -> String:
	var st: Dictionary = d.state
	var map_name := String(data.maps.maps.get(String(st.map_id), {}).get("name", String(st.map_id)))
	var diff_name := String(data.DIFFICULTIES.get(String(st.difficulty_id), {}).get("name", String(st.difficulty_id)))
	var who := ""
	for h in st.get("heroes", []):
		if int(h.owner) == 1:
			who = "%s Lv %d · " % [String(data.TOWERS.get(String(h.type), {}).get("name", h.type)), int(h.level)]
	if bool(st.endless):
		return "%s%s · %s · Endless wave %d" % [who, map_name, diff_name, int(st.wave)]
	return "%s%s · %s · wave %d of %d" % [who, map_name, diff_name, int(st.wave), int(st.max_wave)]


static func clear(run_id := -1) -> void:
	if run_id >= 0:
		var d := info()
		if not d.is_empty() and int(d.get("run", -2)) != run_id:
			return  # a different game's save: keep it
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Put a saved game back into a fresh sim (players come from the save)
static func restore(sim: SimWorld, d: Dictionary) -> void:
	var st: Dictionary = d.state
	sim.players.clear()
	sim.start(String(st.map_id), String(st.difficulty_id), String(st.mode))
	for k in KEYS:
		if st.has(k):
			sim.set(k, st[k])
	sim.features.list = st.get("features", sim.features.list)
	for p in sim.players.values():
		if int(p.id) != 1:
			p.is_bot = true  # couch friends from last time: Bot Buddies play them now
	sim.wave_active = false
	sim.auto_wave = false
	sim.events.clear()
	sim.ev({"type": "game_resumed", "wave": sim.wave})
