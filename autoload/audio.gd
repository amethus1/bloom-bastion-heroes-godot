extends Node
## Sound effects (global + 2D spatial), adaptive looping music, per-map ambient
## beds, multi-variant character voices, voice ducking, and dialog subtitles.
## Autoloaded as `Audio`. Safely no-ops in headless test runs.

signal dialog_line(speaker: String, text: String, owner_id: int, duration: float)

const GLOBAL_POOL := 12
const SPATIAL_POOL := 16

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
	# Pea Blaster
	"pea_pick_0": ["Pea Blaster", "Pea Blaster, locked and sprouted!"],
	"pea_pick_1": ["Pea Blaster", "Ready to blast some pests!"],
	"pea_pick_2": ["Pea Blaster", "Aim true, shoot fast!"],
	"pea_special_0": ["Pea Blaster", "Pea storm! Take cover!"],
	"pea_special_1": ["Pea Blaster", "Pods away!"],
	"pea_special_2": ["Pea Blaster", "Green barrage incoming!"],
	"pea_level_0": ["Pea Blaster", "Growing stronger!"],
	"pea_level_1": ["Pea Blaster", "Faster pods, sharper aim!"],
	"pea_level_2": ["Pea Blaster", "Feeling super sprouted!"],
	"pea_evolve_0": ["Pea Blaster", "Full gatling bloom!"],
	"pea_evolve_1": ["Pea Blaster", "Wait till they see these pods!"],
	# Sun Blossom
	"sun_pick_0": ["Sun Blossom", "Let's grow together!"],
	"sun_pick_1": ["Sun Blossom", "Sunshine brings out our best!"],
	"sun_pick_2": ["Sun Blossom", "Ready to power up the team!"],
	"sun_special_0": ["Sun Blossom", "Sunburst! Shine bright, everyone!"],
	"sun_special_1": ["Sun Blossom", "Feel the golden warmth!"],
	"sun_special_2": ["Sun Blossom", "Rise and bloom!"],
	"sun_level_0": ["Sun Blossom", "More sunshine for the team!"],
	"sun_level_1": ["Sun Blossom", "Brighter petals every wave!"],
	"sun_level_2": ["Sun Blossom", "Warming up nicely!"],
	"sun_evolve_0": ["Sun Blossom", "Radiant full bloom!"],
	"sun_evolve_1": ["Sun Blossom", "Let the sun guide us!"],
	# Frost Lotus
	"frost_pick_0": ["Frost Lotus", "Stay cool. I've got the chill."],
	"frost_pick_1": ["Frost Lotus", "Ice cold and steady."],
	"frost_pick_2": ["Frost Lotus", "Let's slow this swarm down."],
	"frost_special_0": ["Frost Lotus", "Blizzard! Freeze right there!"],
	"frost_special_1": ["Frost Lotus", "Ice storm unleashed!"],
	"frost_special_2": ["Frost Lotus", "Nobody moves!"],
	"frost_level_0": ["Frost Lotus", "Colder and sharper!"],
	"frost_level_1": ["Frost Lotus", "Frost deepens."],
	"frost_level_2": ["Frost Lotus", "Chillier by the second!"],
	"frost_evolve_0": ["Frost Lotus", "Absolute winter!"],
	"frost_evolve_1": ["Frost Lotus", "Crystal perfection!"],
	# Boom Shroom
	"boom_pick_0": ["Boom Shroom", "Ready to make a big boom!"],
	"boom_pick_1": ["Boom Shroom", "Who wants fireworks?"],
	"boom_pick_2": ["Boom Shroom", "Stand back, I brought spores!"],
	"boom_special_0": ["Boom Shroom", "Mega mushroom incoming!"],
	"boom_special_1": ["Boom Shroom", "Boom time!"],
	"boom_special_2": ["Boom Shroom", "Big blast, coming right up!"],
	"boom_level_0": ["Boom Shroom", "Bigger booms ahead!"],
	"boom_level_1": ["Boom Shroom", "Extra blast powder!"],
	"boom_level_2": ["Boom Shroom", "Heavy artillery ready!"],
	"boom_evolve_0": ["Boom Shroom", "Colossal cap upgrade!"],
	"boom_evolve_1": ["Boom Shroom", "Nothing survives this blast!"],
	# Volt Cactus
	"volt_pick_0": ["Volt Cactus", "Charged up and prickly!"],
	"volt_pick_1": ["Volt Cactus", "Let's spark things up!"],
	"volt_pick_2": ["Volt Cactus", "High voltage defender ready!"],
	"volt_special_0": ["Volt Cactus", "Thunderstorm! Feel the zap!"],
	"volt_special_1": ["Volt Cactus", "Lightning strikes everywhere!"],
	"volt_special_2": ["Volt Cactus", "Shocking surprise!"],
	"volt_level_0": ["Volt Cactus", "High voltage!"],
	"volt_level_1": ["Volt Cactus", "More arcs, more power!"],
	"volt_level_2": ["Volt Cactus", "Buzzing with energy!"],
	"volt_evolve_0": ["Volt Cactus", "Tempest power unlocked!"],
	"volt_evolve_1": ["Volt Cactus", "Pure lightning!"],
	# Snapdragon
	"snap_pick_0": ["Snapdragon", "Time to turn up the heat!"],
	"snap_pick_1": ["Snapdragon", "Smells like roasted pests!"],
	"snap_pick_2": ["Snapdragon", "Watch the sparks fly!"],
	"snap_special_0": ["Snapdragon", "Inferno nova!"],
	"snap_special_1": ["Snapdragon", "Burn bright!"],
	"snap_special_2": ["Snapdragon", "Feel the dragon's fire!"],
	"snap_level_0": ["Snapdragon", "My flames burn hotter!"],
	"snap_level_1": ["Snapdragon", "Fiercer fire!"],
	"snap_level_2": ["Snapdragon", "Blazing ahead!"],
	"snap_evolve_0": ["Snapdragon", "Phoenix power awakened!"],
	"snap_evolve_1": ["Snapdragon", "Unstoppable flames!"],
	# Bubble Lily
	"bubble_pick_0": ["Bubble Lily", "Splish splash, let's soak them!"],
	"bubble_pick_1": ["Bubble Lily", "Bubbles ready to pop!"],
	"bubble_pick_2": ["Bubble Lily", "Water makes lightning extra zappy!"],
	"bubble_special_0": ["Bubble Lily", "Tidal wave! Wash them back!"],
	"bubble_special_1": ["Bubble Lily", "Surf's up, pests!"],
	"bubble_special_2": ["Bubble Lily", "Big splash incoming!"],
	"bubble_level_0": ["Bubble Lily", "Bubbles getting bouncier!"],
	"bubble_level_1": ["Bubble Lily", "Refreshing upgrade!"],
	"bubble_level_2": ["Bubble Lily", "Making bigger waves!"],
	"bubble_evolve_0": ["Bubble Lily", "Tidal queen power!"],
	"bubble_evolve_1": ["Bubble Lily", "Ocean surge!"],
	# Shared co-op & Clash hero quips
	"coop_wake_0": ["Hero", "Wakey wakey, tower!"],
	"coop_wake_1": ["Hero", "Back to work, sleepyhead!"],
	"clash_down_0": ["Hero", "Whoa, I'm knocked out! Help me up!"],
	"clash_revive_0": ["Hero", "Thanks, friend! Back in action!"],
	"clash_golden_0": ["Hero", "Ooh, shiny golden upgrade!"],
	"clash_potion_0": ["Hero", "Mmm, berry juice! Much better!"],
	# Garden Announcer
	"ann_welcome": ["Announcer", "Defend the Bloom Tree!"],
	"ann_wave_0": ["Announcer", "Here come the pests!"],
	"ann_wave_1": ["Announcer", "Next wave incoming! Hold your ground!"],
	"ann_wave_2": ["Announcer", "Stay sharp, garden heroes!"],
	"ann_camo": ["Announcer", "Heads up! Mist Puffs are camouflaged!"],
	"ann_mole": ["Announcer", "Watch the trails! Digger Moles are tunneling!"],
	"ann_sleep": ["Announcer", "A Snoozy Moth put a tower to sleep! Walk near to wake it!"],
	"ann_tree_low": ["Announcer", "Hold the line! Protect the Bloom Tree!"],
	"ann_combo_0": ["Announcer", "Amazing team combo!"],
	"ann_combo_1": ["Announcer", "What a team synergy!"],
	"ann_clear_0": ["Announcer", "Wave cleared! Great teamwork!"],
	"ann_clear_1": ["Announcer", "Clean sweep! Well defended!"],
	"ann_milestone": ["Announcer", "Milestone reached! Bonus cards for all!"],
	"ann_victory": ["Announcer", "Victory! The Bloom Tree is safe!"],
	"ann_gameover": ["Announcer", "The Bloom Tree fell. Let's try again!"],
	"ann_toad_up": ["Announcer", "Rumble Toad has awakened in the jungle!"],
	"ann_toad_power": ["Announcer", "Toad Power! Your Sproutlings are unstoppable!"],
	"ann_elder_power": ["Announcer", "Elder Toad Power! Smash their Thorn Heart!"],
	"ann_gate_down": ["Announcer", "Gate shattered! Super Sprouts marching!"],
	"ann_heart_open": ["Announcer", "The Thorn Heart is exposed! Attack!"],
	"ann_tower_alert": ["Announcer", "Our tower is under attack!"],
	# Bosses & Rivals
	"boss_zep": ["Spore Zeppelin", "Spore Zeppelin airborne! Drop the spores!"],
	"boss_monarch": ["Dread Monarch", "I am the Dread Monarch! Your garden belongs to me!"],
	"boss_enrage": ["Dread Monarch", "Enough! Feel the swarm's fury!"],
	"rival_brute_0": ["Sir Shellbash", "Sir Shellbash reporting! None shall pass my shell!"],
	"rival_brute_1": ["Sir Shellbash", "Time for a shell slam!"],
	"rival_queen_0": ["Queen Stinger", "Queen Stinger rules this lane!"],
	"rival_queen_1": ["Queen Stinger", "Taste the hive's sting!"],
	"rival_mole_0": ["Digger Duke", "Digger Duke here! Watch below your feet!"],
	"rival_mole_1": ["Digger Duke", "Tunneling right under you!"],
	"rival_witch_0": ["Spore Witch", "Spore Witch brewing trouble!"],
	"rival_witch_1": ["Spore Witch", "Nighty-night, little sprouts!"],
}

const DIALOG_VARIANTS := {
	"coop_wake": ["coop_wake_0", "coop_wake_1"],
	"clash_down": ["clash_down_0"],
	"clash_revive": ["clash_revive_0"],
	"clash_golden": ["clash_golden_0"],
	"clash_potion": ["clash_potion_0"],
	"ann_wave": ["ann_wave_0", "ann_wave_1", "ann_wave_2"],
	"ann_combo": ["ann_combo_0", "ann_combo_1"],
	"ann_clear": ["ann_clear_0", "ann_clear_1"],
	"rival_brute": ["rival_brute_0", "rival_brute_1"],
	"rival_queen": ["rival_queen_0", "rival_queen_1"],
	"rival_mole": ["rival_mole_0", "rival_mole_1"],
	"rival_witch": ["rival_witch_0", "rival_witch_1"],
}

var muted := false
var sfx_volume := 0.85
var music_volume := 0.65
var voice_volume := 0.95
var dialog_mode := "all"  # all | key | off
var enabled := true

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _spatial_pool: Array[AudioStreamPlayer2D] = []
var _spatial_idx := 0
var _voice_player: AudioStreamPlayer
var _music_calm: AudioStreamPlayer
var _music_wave: AudioStreamPlayer
var _music_boss: AudioStreamPlayer
var _ambience: AudioStreamPlayer

var _streams := {}
var _cooldowns := {}  # key -> last played msec
var _last_variant := {}  # base_id -> last variant id
var _last_voice_ms := -10000
var _voice_cd_ms := 1300

var _music_state := "menu"
var _cur_map := ""
var _mix_calm := 0.55
var _mix_wave := 0.0
var _mix_boss := 0.0
var _mix_amb := 0.0
var _duck := 1.0  # voice ducking multiplier

var _bus_music := -1
var _bus_amb := -1
var _bus_sfx := -1
var _bus_voice := -1


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	apply_settings()
	if not enabled:
		return
	_setup_buses()
	for i in GLOBAL_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	for i in SPATIAL_POOL:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = 1750.0
		p2.attenuation = 1.45
		p2.panning_strength = 0.85
		add_child(p2)
		_spatial_pool.append(p2)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Voice"
	add_child(_voice_player)
	_music_calm = _make_music_player("music_calm")
	_music_wave = _make_music_player("music_wave")
	_music_boss = _make_music_player("music_boss")
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	_sync_bus_volumes()


func _make_music_player(id: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.stream = _load_wav("music/" + id, true)
	p.volume_db = -60.0
	add_child(p)
	if p.stream:
		p.play()
	return p


func _setup_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.8
		lim.threshold_db = -2.0
		AudioServer.add_bus_effect(0, lim)
	_bus_music = _ensure_bus("Music")
	_bus_amb = _ensure_bus("Ambience")
	_bus_sfx = _ensure_bus("SFX")
	_bus_voice = _ensure_bus("Voice")


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func apply_settings() -> void:
	var cfg := Profile.load_profile()
	muted = bool(cfg.get("muted", false))
	sfx_volume = float(cfg.get("sfxVol", 0.85))
	music_volume = float(cfg.get("musicVol", 0.65))
	voice_volume = float(cfg.get("voiceVol", 0.95))
	dialog_mode = String(cfg.get("dialogMode", "all"))
	if enabled:
		_sync_bus_volumes()


func _sync_bus_volumes() -> void:
	if not enabled:
		return
	var master_mute := muted
	AudioServer.set_bus_mute(0, master_mute)
	if _bus_music >= 0:
		AudioServer.set_bus_volume_db(_bus_music, linear_to_db(maxf(0.0001, music_volume * _duck * 0.42)))
		AudioServer.set_bus_mute(_bus_music, music_volume < 0.02)
	if _bus_amb >= 0:
		AudioServer.set_bus_volume_db(_bus_amb, linear_to_db(maxf(0.0001, music_volume * _duck * 0.28)))
		AudioServer.set_bus_mute(_bus_amb, music_volume < 0.02)
	if _bus_sfx >= 0:
		var sfx_duck := lerpf(0.75, 1.0, (_duck - 0.55) / 0.45)
		AudioServer.set_bus_volume_db(_bus_sfx, linear_to_db(maxf(0.0001, sfx_volume * clampf(sfx_duck, 0.72, 1.0))))
		AudioServer.set_bus_mute(_bus_sfx, sfx_volume < 0.02)
	if _bus_voice >= 0:
		AudioServer.set_bus_volume_db(_bus_voice, linear_to_db(maxf(0.0001, voice_volume)))
		AudioServer.set_bus_mute(_bus_voice, voice_volume < 0.02 or dialog_mode == "off")


func _process(delta: float) -> void:
	if not enabled:
		return
	var targets := {"calm": 0.0, "wave": 0.0, "boss": 0.0, "amb": 0.0}
	match _music_state:
		"menu":
			targets = {"calm": 0.55, "wave": 0.0, "boss": 0.0, "amb": 0.0}
		"calm":
			targets = {"calm": 1.0, "wave": 0.0, "boss": 0.0, "amb": 0.75}
		"wave":
			targets = {"calm": 0.0, "wave": 1.0, "boss": 0.0, "amb": 0.55}
		"boss":
			targets = {"calm": 0.0, "wave": 0.0, "boss": 1.0, "amb": 0.45}
	var rate := minf(1.0, delta * 2.2)
	_mix_calm = lerpf(_mix_calm, targets.calm, rate)
	_mix_wave = lerpf(_mix_wave, targets.wave, rate)
	_mix_boss = lerpf(_mix_boss, targets.boss, rate)
	_mix_amb = lerpf(_mix_amb, targets.amb, rate)
	_apply_stem_gain(_music_calm, _mix_calm)
	_apply_stem_gain(_music_wave, _mix_wave)
	_apply_stem_gain(_music_boss, _mix_boss)
	_apply_stem_gain(_ambience, _mix_amb)
	var talking := _voice_player != null and _voice_player.playing
	var want_duck := 0.55 if talking else 1.0
	_duck = lerpf(_duck, want_duck, minf(1.0, delta * (9.0 if talking else 3.5)))
	_sync_bus_volumes()


func _apply_stem_gain(p: AudioStreamPlayer, k: float) -> void:
	if p == null or p.stream == null:
		return
	if k < 0.01:
		p.volume_db = -60.0
	else:
		p.volume_db = linear_to_db(k)


## Stop everything on exit so no sound streams are left playing when the app closes
func _exit_tree() -> void:
	for c in get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer2D:
			c.stop()
			c.stream = null


func set_music_state(state: String, map_id := "") -> void:
	_music_state = state
	if not enabled:
		return
	if _music_calm and _music_calm.stream and not _music_calm.playing:
		_music_calm.play()
		if _music_wave and _music_wave.stream:
			_music_wave.play()
		if _music_boss and _music_boss.stream:
			_music_boss.play()
	if map_id != "" and map_id != _cur_map:
		_cur_map = map_id
		if _ambience:
			var st := _load_wav("ambience/amb_" + map_id, true)
			_ambience.stream = st
			if st:
				_ambience.play()
			else:
				_ambience.stop()
	elif map_id == "" and state == "menu" and _ambience and _ambience.playing:
		_cur_map = ""


func _load_wav(rel: String, loop := false) -> AudioStream:
	if _streams.has(rel):
		return _streams[rel]
	var res_path := "res://audio/" + rel + ".wav"
	var st: AudioStream = null
	if ResourceLoader.exists(res_path):
		st = load(res_path)
	elif FileAccess.file_exists(res_path):
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(res_path))
	if st is AudioStreamWAV and loop:
		var wav := st as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
	_streams[rel] = st
	return st


func toggle_mute() -> bool:
	muted = not muted
	Profile.set_value("muted", muted)
	if muted and _voice_player:
		_voice_player.stop()
	_sync_bus_volumes()
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
	p.volume_db = volume_db_offset
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	p.play()


func play_sfx_at(id: String, world_pos: Vector2, is_mine := true, volume_db_offset := 0.0, pitch_jitter := 0.07, cooldown_ms := 55) -> void:
	if not enabled or muted or sfx_volume <= 0.01:
		return
	var cd_key := "%s_%s" % [id, "m" if is_mine else "o"]
	var now := Time.get_ticks_msec()
	if now - int(_cooldowns.get(cd_key, -10000)) < cooldown_ms:
		return
	var st := _load_wav("sfx/" + id)
	if st == null or _spatial_pool.is_empty():
		return
	_cooldowns[cd_key] = now
	var p2 := _spatial_pool[_spatial_idx]
	_spatial_idx = (_spatial_idx + 1) % _spatial_pool.size()
	p2.global_position = world_pos
	p2.stream = st
	p2.volume_db = volume_db_offset + (1.5 if is_mine else -3.5)
	p2.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	p2.play()


func _pick_variant(id_or_base: String) -> String:
	if DIALOG_TEXT.has(id_or_base):
		return id_or_base
	var pool: Array = DIALOG_VARIANTS.get(id_or_base, [])
	if pool.is_empty():
		var idx := 0
		while DIALOG_TEXT.has("%s_%d" % [id_or_base, idx]):
			pool.append("%s_%d" % [id_or_base, idx])
			idx += 1
	if pool.is_empty():
		return id_or_base
	if pool.size() == 1:
		return String(pool[0])
	var last := String(_last_variant.get(id_or_base, ""))
	var cands := pool.filter(func(x): return String(x) != last)
	var picked := String(cands[randi() % cands.size()])
	_last_variant[id_or_base] = picked
	return picked


func say(id_or_base: String, owner_id := -1, priority := false, is_routine := false) -> void:
	if dialog_mode == "off" or (dialog_mode == "key" and is_routine and not priority):
		return
	var vid := _pick_variant(id_or_base)
	var meta: Array = DIALOG_TEXT.get(vid, [])
	var speaker: String = meta[0] if meta.size() > 0 else ""
	var text: String = meta[1] if meta.size() > 1 else ""
	var now := Time.get_ticks_msec()
	if not priority and now - _last_voice_ms < _voice_cd_ms:
		return
	var dur := 2.4
	if enabled and not muted and voice_volume > 0.01 and _voice_player:
		var st := _load_wav("voice/" + vid)
		if st:
			if _voice_player.playing and not priority:
				return
			_voice_player.stream = st
			_voice_player.play()
			dur = maxf(1.8, st.get_length() + 0.4)
	_last_voice_ms = now
	if text != "":
		dialog_line.emit(speaker, text, owner_id, dur)


func say_hero(hero_type: String, suffix: String, owner_id := -1, priority := false) -> void:
	var pre: String = HERO_VOICE_PREFIX.get(hero_type, "")
	if pre != "":
		say("%s_%s" % [pre, suffix], owner_id, priority, suffix == "level")
