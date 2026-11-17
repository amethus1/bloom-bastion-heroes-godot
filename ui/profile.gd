class_name Profile
extends RefCounted
## The local save profile: your name, favourite hero, hat, pet, last game
## settings and a few records. Stored in user://profile.cfg.

const PATH := "user://profile.cfg"


static func defaults() -> Dictionary:
	return {"name": "Player", "hero": "peashooter", "hat": "none", "pet": "none", "map": "meadow", "diff": "normal",
		"gameMode": "adventure", "bots": 1, "address": "", "games": 0, "wins": 0, "bestEndless": 0,
		"muted": false, "sfxVol": 0.85, "voiceVol": 0.95, "padP1": false}


static func load_profile() -> Dictionary:
	var d := defaults()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in d:
			d[k] = cf.get_value("profile", k, d[k])
	if not GameData.HERO_ORDER.has(d.hero):
		d.hero = "peashooter"
	return d


static func save_profile(d: Dictionary) -> void:
	var cf := ConfigFile.new()
	for k in defaults():
		if d.has(k):
			cf.set_value("profile", k, d[k])
	cf.save(PATH)


## Called when a game ends to keep simple records
static func record_game(win: bool, endless: bool, wave: int) -> Dictionary:
	var d := load_profile()
	d.games = int(d.games) + 1
	if win:
		d.wins = int(d.wins) + 1
	if endless:
		d.bestEndless = maxi(int(d.bestEndless), wave)
	save_profile(d)
	return d
