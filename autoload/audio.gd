extends Node
## Sound effects, character voice lines, and dialog subtitle dispatch.
## Autoloaded as `Audio`. Safely no-ops in headless test runs.

signal dialog_line(speaker: String, text: String, owner_id: int, duration: float)

const POOL_SIZE := 16

const HERO_VOICE_PREFIX := {
	"peashooter": "pea",
	"sunblossom": "sun",
	"frostlotus": "frost",
	"boomshroom": "boom",
	"voltcactus": "volt",
	"snapdragon": "snap",
	"bubblelily": "bubble",
}

const DIALOG_TEXT := {
	"pea_pick": ["Pea Blaster", "Pea Blaster, locked and sprouted!"],
	"pea_special": ["Pea Blaster", "Pea storm! Take cover!"],
	"pea_level": ["Pea Blaster", "Growing stronger!"],
	"sun_pick": ["Sun Blossom", "Let's grow together!"],
	"sun_special": ["Sun Blossom", "Sunburst! Shine bright, everyone!"],
	"sun_level": ["Sun Blossom", "More sunshine for the team!"],
	"frost_pick": ["Frost Lotus", "Stay cool. I've got the chill."],
	"frost_special": ["Frost Lotus", "Blizzard! Freeze right there!"],
	"frost_level": ["Frost Lotus", "Colder and sharper!"],
	"boom_pick": ["Boom Shroom", "Ready to make a big boom!"],
	"boom_special": ["Boom Shroom", "Mega mushroom incoming!"],
	"boom_level": ["Boom Shroom", "Bigger booms ahead!"],
	"volt_pick": ["Volt Cactus", "Charged up and prickly!"],
	"volt_special": ["Volt Cactus", "Thunderstorm! Feel the zap!"],
	"volt_level": ["Volt Cactus", "High voltage!"],
	"snap_pick": ["Snapdragon", "Time to turn up the heat!"],
	"snap_special": ["Snapdragon", "Inferno nova!"],
	"snap_level": ["Snapdragon", "My flames burn hotter!"],
	"bubble_pick": ["Bubble Lily", "Splish splash, let's soak them!"],
	"bubble_special": ["Bubble Lily", "Tidal wave! Wash them back!"],
	"bubble_level": ["Bubble Lily", "Bubbles getting bouncier!"],
	"ann_welcome": ["Announcer", "Defend the Bloom Tree!"],
	"ann_wave": ["Announcer", "Here come the pests!"],
	"ann_camo": ["Announcer", "Heads up! Mist Puffs are camouflaged!"],
	"ann_mole": ["Announcer", "Watch the trails! Digger Moles are tunneling!"],
	"ann_sleep": ["Announcer", "A Snoozy Moth put a tower to sleep! Walk near to wake it!"],
	"ann_combo": ["Announcer", "Amazing team combo!"],
	"ann_clear": ["Announcer", "Wave cleared! Great teamwork!"],
	"ann_milestone": ["Announcer", "Milestone reached! Bonus cards for all!"],
	"ann_victory": ["Announcer", "Victory! The Bloom Tree is safe!"],
	"ann_gameover": ["Announcer", "The Bloom Tree fell. Let's try again!"],
	"boss_zep": ["Spore Zeppelin", "Spore Zeppelin airborne! Drop the spores!"],
	"boss_monarch": ["Dread Monarch", "I am the Dread Monarch! Your garden belongs to me!"],
	"boss_enrage": ["Dread Monarch", "Enough! Feel the swarm's fury!"],
}

var muted := false
var sfx_volume := 0.85
var voice_volume := 0.95
var enabled := true

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _voice_player: AudioStreamPlayer
var _streams := {}
var _cooldowns := {}  # id -> last played msec
var _last_voice_ms := -10000
var _voice_cd_ms := 1400


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	var cfg := Profile.load_profile()
	muted = bool(cfg.get("muted", false))
	sfx_volume = float(cfg.get("sfxVol", 0.85))
	voice_volume = float(cfg.get("voiceVol", 0.95))
	if not enabled:
		return
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)


func _load_wav(rel: String) -> AudioStream:
	if _streams.has(rel):
		return _streams[rel]
	var res_path := "res://audio/" + rel + ".wav"
	var st: AudioStream = null
	if ResourceLoader.exists(res_path):
		st = load(res_path)
	elif FileAccess.file_exists(res_path):
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(res_path))
	_streams[rel] = st
	return st


func toggle_mute() -> bool:
	muted = not muted
	var cfg := Profile.load_profile()
	cfg.muted = muted
	Profile.save_profile(cfg)
	if muted and _voice_player:
		_voice_player.stop()
	return muted


func play_sfx(id: String, volume_db_offset := 0.0, pitch_jitter := 0.06, cooldown_ms := 55) -> void:
	if not enabled or muted or sfx_volume <= 0.01:
		return
	var now := Time.get_ticks_msec()
	if now - int(_cooldowns.get(id, -10000)) < cooldown_ms:
		return
	var st := _load_wav("sfx/" + id)
	if st == null or _sfx_pool.is_empty():
		return
	_cooldowns[id] = now
	var p := _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = st
	p.volume_db = linear_to_db(clampf(sfx_volume, 0.001, 1.0)) + volume_db_offset
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	p.play()


func say(id: String, owner_id := -1, priority := false) -> void:
	var meta: Array = DIALOG_TEXT.get(id, [])
	var speaker: String = meta[0] if meta.size() > 0 else ""
	var text: String = meta[1] if meta.size() > 1 else ""
	var now := Time.get_ticks_msec()
	if not priority and now - _last_voice_ms < _voice_cd_ms:
		return
	var dur := 2.4
	if enabled and not muted and voice_volume > 0.01 and _voice_player:
		var st := _load_wav("voice/" + id)
		if st:
			if _voice_player.playing and not priority:
				return
			_voice_player.stream = st
			_voice_player.volume_db = linear_to_db(clampf(voice_volume, 0.001, 1.0))
			_voice_player.play()
			dur = maxf(1.8, st.get_length() + 0.4)
	_last_voice_ms = now
	if text != "":
		dialog_line.emit(speaker, text, owner_id, dur)


func say_hero(hero_type: String, suffix: String, owner_id := -1, priority := false) -> void:
	var pre: String = HERO_VOICE_PREFIX.get(hero_type, "")
	if pre != "":
		say("%s_%s" % [pre, suffix], owner_id, priority)
