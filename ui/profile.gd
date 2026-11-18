class_name Profile
extends RefCounted
## The local save profile: your name, favourite hero, hat, pet, last game
## settings and a few records. Stored in user://profile.cfg.

## Tests and screenshot runs use their own file so they never touch your real profile
static var path := "user://profile.cfg"


static func defaults() -> Dictionary:
	return {"name": "Player", "hero": "peashooter", "hat": "none", "pet": "none", "map": "meadow", "diff": "normal",
		"gameMode": "adventure", "bots": 1, "address": "", "games": 0, "wins": 0, "bestEndless": 0,
		"muted": false, "sfxVol": 0.85, "musicVol": 0.65, "voiceVol": 0.95, "dialogMode": "all", "padP1": false,
		"shake": 1.0, "dmgNums": "all", "fullscreen": false, "gfx": "fancy", "uiScale": 0.8, "msgs": "fewer", "chatter": "some", "autoCards": true,
		"hats": [], "pets": [], "unlockAll": false, "unlocksStarted": false, "medals": {}, "kidAssist": false, "tipsSeen": [], "clientKey": "", "mutators": [], "guideSeen": [], "practiceDone": false}


static func load_profile() -> Dictionary:
	var d := defaults()
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for k in d:
			d[k] = cf.get_value("profile", k, d[k])
		if not cf.has_section_key("profile", "chatter"):
			# the old 3-step "Hero chatter" setting: keep "off" and "key moments"
			d.chatter = {"off": "off", "key": "few"}.get(String(d.dialogMode), "some")
	if not GameData.HERO_ORDER.has(d.hero):
		d.hero = "peashooter"
	if not d.unlocksStarted:
		# hats & pets became unlockable: keep whatever you were already wearing
		d.unlocksStarted = true
		d.hats = [d.hat]
		d.pets = [d.pet]
		save_profile(d)
	return d


## A random id for this computer, so a LAN host can give you your hero back
## if your Wi-Fi drops and you join again
static func client_key() -> String:
	var d := load_profile()
	if String(d.clientKey) == "":
		var c := Crypto.new()
		d.clientKey = c.generate_random_bytes(9).hex_encode()
		save_profile(d)
	return String(d.clientKey)


## Free items, things you've earned, or everything with "Unlock everything" on
static func is_unlocked(d: Dictionary, kind: String, id: String) -> bool:
	if d.get("unlockAll", false):
		return true
	for x in GameData.cosmetics[kind]:
		if x.id == id and x.get("free", false):
			return true
	return Array(d.get(kind, [])).has(id)


## Returns true if it was new
static func unlock(kind: String, id: String) -> bool:
	var d := load_profile()
	var have: Array = Array(d.get(kind, []))
	if have.has(id):
		return false
	have.append(id)
	d[kind] = have
	save_profile(d)
	return true


static func save_profile(d: Dictionary) -> void:
	var cf := ConfigFile.new()
	for k in defaults():
		if d.has(k):
			cf.set_value("profile", k, d[k])
	cf.save(path)


## Settings live in the profile too: screen shake, damage numbers, fullscreen
static func set_value(key: String, value) -> Dictionary:
	var d := load_profile()
	d[key] = value
	save_profile(d)
	return d


static func next_shake(v: float) -> float:
	return 0.5 if v > 0.75 else (0.0 if v > 0.25 else 1.0)


static func next_dmg(v: String) -> String:
	return {"all": "big", "big": "off", "off": "all"}.get(v, "all")


static func shake_label(v: float) -> String:
	return "Screen shake: %s" % ("100%" if v > 0.75 else ("50%" if v > 0.25 else "off"))


static func gfx_label(v: String) -> String:
	return "Graphics: %s" % ("simple (faster)" if v == "simple" else "fancy")


static func dmg_label(v: String) -> String:
	return "Damage numbers: %s" % {"all": "all", "big": "big hits only", "off": "off"}.get(v, "all")


static func next_vol(v: float) -> float:
	return 0.65 if v > 0.8 else (0.35 if v > 0.5 else (0.0 if v > 0.1 else 1.0))


static func vol_label(prefix: String, v: float) -> String:
	return "%s: %s" % [prefix, "off" if v < 0.05 else ("%d%%" % int(round(v * 100)))]


## How chatty the announcer and heroes are (voices, subtitles and speech bubbles)
const CHATTER := [["lots", "Lots"], ["some", "Some"], ["few", "Big moments only"], ["off", "Off"]]
## How many pop-up messages and big banners show up
const MSGS := [["all", "All"], ["fewer", "Fewer"], ["fewest", "Only important ones"]]
## In-game buttons and panels (1.0 = the old size)
const UI_SCALES := [0.6, 0.7, 0.8, 0.9, 1.0, 1.15, 1.3]


static func _next_of(list: Array, v: String) -> String:
	for i in list.size():
		if String(list[i][0]) == v:
			return String(list[(i + 1) % list.size()][0])
	return String(list[0][0])


static func _name_of(list: Array, v: String) -> String:
	for x in list:
		if String(x[0]) == v:
			return String(x[1])
	return v


static func next_chatter(v: String) -> String:
	return _next_of(CHATTER, v)


static func chatter_label(v: String) -> String:
	return "Hero chatter: %s" % _name_of(CHATTER, v).to_lower()


static func next_msgs(v: String) -> String:
	return _next_of(MSGS, v)


static func msgs_label(v: String) -> String:
	return "Messages: %s" % _name_of(MSGS, v).to_lower()


## The UI size one step bigger (+1) or smaller (-1), from the nearest step
static func step_ui_scale(v: float, dir: int) -> float:
	var best := 0
	for i in UI_SCALES.size():
		if absf(UI_SCALES[i] - v) < absf(UI_SCALES[best] - v):
			best = i
	return UI_SCALES[clampi(best + dir, 0, UI_SCALES.size() - 1)]


static func cards_label(auto: bool) -> String:
	return "Level-ups: %s" % ("automatic" if auto else "pick every card")


static func ui_scale_label(v: float) -> String:
	return "UI size: %d%%" % int(round(v * 100))


const MEDAL_LEVEL := {"easy": 1, "normal": 2, "hard": 3, "nightmare": 4}
const MEDAL_ICON := ["", "🥉", "🥈", "🥇", "💎"]
const MEDAL_NAME := ["", "won on Easy", "won on Normal", "won on Hard", "won on Nightmare"]


## Called when a game ends to keep simple records
static func record_game(win: bool, endless: bool, wave: int, map_id := "", diff := "", game_mode := "") -> Dictionary:
	var d := load_profile()
	d.games = int(d.games) + 1
	if win:
		d.wins = int(d.wins) + 1
		# medals: the hardest difficulty you've won each Adventure map on
		if game_mode == "adventure" and map_id != "":
			var m: Dictionary = d.get("medals", {})
			m[map_id] = maxi(int(m.get(map_id, 0)), MEDAL_LEVEL.get(diff, 0))
			d.medals = m
	if endless:
		d.bestEndless = maxi(int(d.bestEndless), wave)
	save_profile(d)
	return d
