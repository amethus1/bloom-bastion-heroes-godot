#!/usr/bin/env python3
"""
Generate procedural DSP music loops (audio/music/*.wav), ambient map beds
(audio/ambience/*.wav), sound effects (audio/sfx/*.wav), and character/boss/
announcer dialog lines (audio/voice/*.wav) for Bloom Bastion Heroes.

By default this runs 100% locally and free using Python DSP synthesis for
music/ambience/SFX and macOS `say` + `afconvert` + DSP character processing
for voices. Pass `--gemini` (requires configured `gemini-api` CLI) to
generate voices with Gemini AI TTS instead.
"""

import argparse
import math
import os
import random
import struct
import subprocess
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "audio", "sfx")
VOICE_DIR = os.path.join(ROOT, "audio", "voice")
MUSIC_DIR = os.path.join(ROOT, "audio", "music")
AMB_DIR = os.path.join(ROOT, "audio", "ambience")
SR = 22050


# ---------------------------------------------------------------------------
# Low-level DSP helpers
# ---------------------------------------------------------------------------
def write_wav(path: str, samples: list[float], sr: int = SR, norm: float = 0.88, soft_clip: bool = True) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0)
    if peak < 1e-6:
        peak = 1.0
    scale = norm / peak
    pcm = bytearray()
    t_norm = math.tanh(1.15)
    for s in samples:
        v = (math.tanh(s * scale * 1.15) / t_norm) if soft_clip else max(-1.0, min(1.0, s * scale))
        iv = max(-32767, min(32767, int(v * 32767.0)))
        pcm.extend(struct.pack("<h", iv))
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(bytes(pcm))


def read_wav(path: str) -> tuple[list[float], int]:
    with wave.open(path, "rb") as wf:
        sr = wf.getframerate()
        n = wf.getnframes()
        ch = wf.getnchannels()
        raw = wf.readframes(n)
    vals = struct.unpack(f"<{n * ch}h", raw)
    if ch > 1:
        vals = [sum(vals[i : i + ch]) / ch for i in range(0, len(vals), ch)]
    return [v / 32768.0 for v in vals], sr


def env_ad(n: int, attack_s: float, decay_pow: float = 1.8, sr: int = SR) -> list[float]:
    atk = max(1, int(attack_s * sr))
    out = []
    for i in range(n):
        if i < atk:
            out.append(i / atk)
        else:
            t = (i - atk) / max(1, n - atk)
            out.append((1.0 - t) ** decay_pow)
    return out


def mix(*tracks: list[float]) -> list[float]:
    n = max((len(t) for t in tracks), default=0)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def pad(track: list[float], delay_s: float, sr: int = SR) -> list[float]:
    return [0.0] * int(delay_s * sr) + track


def lowpass(samples: list[float], alpha: float) -> list[float]:
    out = []
    y = 0.0
    for x in samples:
        y = y + alpha * (x - y)
        out.append(y)
    return out


def highpass(samples: list[float], alpha: float) -> list[float]:
    lp = lowpass(samples, alpha)
    return [x - l for x, l in zip(samples, lp)]


def sweep(dur: float, f0: float, f1: float, shape: str = "sine", decay: float = 1.8, atk: float = 0.004, amp: float = 1.0) -> list[float]:
    n = int(dur * SR)
    e = env_ad(n, atk, decay)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 * ((f1 / max(1.0, f0)) ** t)
        phase += 2.0 * math.pi * f / SR
        if shape == "sine":
            w = math.sin(phase)
        elif shape == "tri":
            w = 2.0 * abs(2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0) - 1.0
        elif shape == "saw":
            w = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
        elif shape == "square":
            w = 1.0 if math.sin(phase) >= 0 else -1.0
        else:
            w = math.sin(phase) + 0.35 * math.sin(2.0 * phase)
        out.append(w * e[i] * amp)
    return out


def noise(dur: float, decay: float = 2.0, atk: float = 0.003, lp: float = 0.5, hp: float = 0.0, amp: float = 1.0, seed: int = 1) -> list[float]:
    rng = random.Random(seed)
    n = int(dur * SR)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    if lp < 0.99:
        raw = lowpass(raw, lp)
    if hp > 0.0:
        raw = highpass(raw, hp)
    e = env_ad(n, atk, decay)
    return [raw[i] * e[i] * amp for i in range(n)]


def note_chord(freqs: list[float], dur: float, step: float = 0.06, shape: str = "warm", decay: float = 2.0) -> list[float]:
    tracks = []
    for idx, f in enumerate(freqs):
        tr = mix(
            sweep(dur, f, f, shape, decay, 0.006, 0.75),
            sweep(dur * 0.7, f * 2.0, f * 2.0, "sine", decay + 0.6, 0.006, 0.22),
        )
        tracks.append(pad(tr, idx * step))
    return mix(*tracks)


def add_looped(buf: list[float], start_s: float, clip: list[float], gain: float = 1.0) -> None:
    n = len(buf)
    s0 = int(start_s * SR)
    for i, v in enumerate(clip):
        buf[(s0 + i) % n] += v * gain


def make_seamless(samples: list[float], fade_s: float = 0.35) -> list[float]:
    n = len(samples)
    f = min(int(fade_s * SR), n // 4)
    out = samples[:]
    for i in range(f):
        k = i / f
        out[i] = samples[i] * k + samples[n - f + i] * (1.0 - k)
    return out[: n - f]


# ---------------------------------------------------------------------------
# Sound Effects Library
# ---------------------------------------------------------------------------
def build_sfx() -> int:
    sfx: dict[str, list[float]] = {}

    # Shots
    sfx["shoot_pea"] = mix(
        sweep(0.09, 520, 190, "warm", 2.2, 0.002, 0.8),
        noise(0.05, 3.0, 0.001, lp=0.35, amp=0.25, seed=2),
    )
    sfx["shoot_boom"] = mix(
        sweep(0.22, 180, 52, "sine", 1.8, 0.004, 1.0),
        noise(0.18, 2.5, 0.003, lp=0.18, amp=0.6, seed=3),
    )
    sfx["shoot_bubble"] = mix(
        sweep(0.13, 320, 760, "sine", 2.0, 0.005, 0.75),
        pad(sweep(0.07, 680, 980, "sine", 2.4, 0.004, 0.35), 0.03),
    )
    sfx["shoot_zap"] = mix(
        sweep(0.11, 1450, 320, "saw", 2.5, 0.001, 0.5),
        noise(0.10, 3.0, 0.001, lp=0.8, hp=0.25, amp=0.65, seed=5),
    )
    sfx["shoot_flame"] = mix(
        noise(0.24, 1.6, 0.02, lp=0.28, hp=0.04, amp=0.85, seed=6),
        sweep(0.18, 240, 120, "tri", 2.0, 0.01, 0.3),
    )
    sfx["shoot_frost"] = mix(
        sweep(0.18, 1200, 1900, "sine", 2.4, 0.005, 0.45),
        sweep(0.20, 1800, 2400, "sine", 2.8, 0.008, 0.3),
        noise(0.22, 2.0, 0.01, lp=0.65, hp=0.35, amp=0.35, seed=7),
    )
    sfx["shoot_beam"] = mix(
        sweep(0.24, 1600, 260, "saw", 1.9, 0.002, 0.55),
        sweep(0.22, 880, 1760, "sine", 2.2, 0.002, 0.45),
    )
    sfx["snipe"] = mix(
        sweep(0.14, 1900, 220, "saw", 2.4, 0.001, 0.6),
        noise(0.10, 2.8, 0.001, lp=0.75, hp=0.25, amp=0.7, seed=20),
    )
    sfx["solar_beam"] = mix(
        note_chord([523.25, 783.99, 1046.5, 1567.98], 0.35, 0.015, "warm", 1.8),
        sweep(0.32, 440, 880, "sine", 2.0, 0.01, 0.4),
    )
    sfx["nova_sun"] = mix(
        note_chord([587.33, 880.0, 1174.66], 0.28, 0.02, "sine", 2.2),
        sweep(0.22, 660, 1320, "sine", 2.3, 0.008, 0.3),
    )
    sfx["nova_shock"] = mix(
        sweep(0.18, 1200, 240, "saw", 2.2, 0.002, 0.45),
        noise(0.18, 2.4, 0.001, lp=0.85, hp=0.3, amp=0.7, seed=21),
    )

    # Impacts, moles, traps & pops
    sfx["pop_small"] = mix(
        sweep(0.075, 420, 860, "sine", 2.6, 0.001, 0.85),
        noise(0.03, 3.2, 0.001, lp=0.45, amp=0.25, seed=8),
    )
    sfx["pop_boss"] = mix(
        sweep(0.75, 220, 38, "sine", 1.5, 0.005, 1.0),
        noise(0.65, 1.7, 0.004, lp=0.24, amp=0.95, seed=9),
        pad(note_chord([523.25, 659.25, 783.99, 1046.5], 0.35, 0.06, "sine", 2.0), 0.14),
    )
    sfx["explosion"] = mix(
        sweep(0.36, 150, 34, "sine", 1.6, 0.003, 1.0),
        noise(0.38, 1.9, 0.002, lp=0.22, amp=0.95, seed=10),
    )
    sfx["gadget_boom"] = mix(
        sweep(0.45, 190, 32, "sine", 1.5, 0.002, 1.0),
        noise(0.42, 1.7, 0.002, lp=0.28, amp=1.0, seed=22),
        sweep(0.16, 480, 110, "tri", 2.2, 0.002, 0.45),
    )
    sfx["thunder"] = mix(
        noise(0.45, 1.5, 0.001, lp=0.55, amp=0.9, seed=11),
        sweep(0.35, 920, 70, "saw", 2.2, 0.001, 0.55),
        pad(noise(0.40, 1.4, 0.02, lp=0.14, amp=0.85, seed=12), 0.05),
    )
    sfx["mole_down"] = mix(
        sweep(0.18, 220, 85, "tri", 2.0, 0.005, 0.7),
        noise(0.20, 2.2, 0.005, lp=0.15, amp=0.75, seed=23),
    )
    sfx["mole_up"] = mix(
        sweep(0.18, 130, 340, "tri", 2.0, 0.004, 0.7),
        noise(0.16, 2.4, 0.003, lp=0.35, amp=0.65, seed=24),
    )
    sfx["bubble_trap"] = mix(
        sweep(0.16, 360, 880, "sine", 2.1, 0.004, 0.65),
        pad(note_chord([987.77, 1318.5], 0.18, 0.035, "sine", 2.5), 0.06),
    )
    sfx["spring_life"] = note_chord([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.30, 0.05, "sine", 2.2)

    # Reactions
    sfx["react_shatter"] = mix(
        sweep(0.16, 2400, 900, "tri", 2.8, 0.001, 0.6),
        noise(0.22, 2.2, 0.001, lp=0.92, hp=0.45, amp=0.85, seed=13),
        pad(sweep(0.14, 3100, 1800, "sine", 3.0, 0.002, 0.4), 0.03),
    )
    sfx["react_melt"] = mix(
        noise(0.28, 1.8, 0.008, lp=0.75, hp=0.35, amp=0.75, seed=14),
        sweep(0.18, 620, 340, "sine", 2.0, 0.005, 0.4),
    )
    sfx["react_overload"] = mix(
        sweep(0.28, 300, 48, "sine", 1.7, 0.002, 0.9),
        sweep(0.22, 1700, 380, "saw", 2.3, 0.001, 0.45),
        noise(0.28, 2.0, 0.002, lp=0.45, amp=0.75, seed=15),
    )
    sfx["react_knockout"] = mix(
        sweep(0.18, 260, 75, "sine", 2.0, 0.002, 0.95),
        note_chord([783.99, 1046.5], 0.22, 0.02, "tri", 2.5),
    )
    sfx["react_electrocute"] = mix(
        sweep(0.22, 1300, 460, "saw", 2.2, 0.002, 0.45),
        noise(0.24, 2.1, 0.002, lp=0.8, hp=0.3, amp=0.7, seed=16),
        sweep(0.18, 520, 880, "sine", 2.4, 0.01, 0.35),
    )
    sfx["react_flashfreeze"] = mix(
        note_chord([1318.5, 1760.0, 2093.0], 0.24, 0.025, "sine", 2.6),
        noise(0.18, 2.6, 0.002, lp=0.85, hp=0.5, amp=0.45, seed=17),
    )

    # Actions, pickups & progression
    sfx["dash"] = mix(
        noise(0.20, 2.1, 0.01, lp=0.45, hp=0.12, amp=0.75, seed=18),
        sweep(0.18, 260, 640, "sine", 2.0, 0.008, 0.45),
    )
    sfx["teleport"] = note_chord([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.28, 0.035, "sine", 2.4)
    sfx["sun_pickup"] = note_chord([659.25, 880.0, 1174.66], 0.18, 0.04, "sine", 2.4)
    sfx["chest_drop"] = mix(
        sweep(0.16, 220, 110, "tri", 2.2, 0.002, 0.8),
        pad(note_chord([987.77, 1318.5], 0.18, 0.04, "sine", 2.5), 0.04),
    )
    sfx["chest_open"] = note_chord([523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98], 0.36, 0.055, "warm", 2.1)
    sfx["powerup"] = mix(
        sweep(0.32, 330, 990, "warm", 1.8, 0.005, 0.6),
        note_chord([523.25, 783.99, 1046.5], 0.30, 0.05, "sine", 2.0),
    )
    sfx["level_up"] = note_chord([523.25, 659.25, 783.99, 1046.5], 0.32, 0.065, "warm", 2.0)
    sfx["card_pick"] = mix(
        sweep(0.08, 420, 740, "tri", 2.5, 0.002, 0.65),
        pad(note_chord([880.0, 1174.66], 0.18, 0.035, "sine", 2.4), 0.03),
    )
    sfx["special_cast"] = mix(
        sweep(0.36, 280, 1120, "warm", 1.7, 0.006, 0.75),
        noise(0.28, 2.0, 0.01, lp=0.6, amp=0.45, seed=19),
    )
    sfx["team_combo"] = mix(
        note_chord([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.50, 0.045, "warm", 1.8),
        sweep(0.45, 140, 420, "sine", 1.7, 0.005, 0.6),
    )

    # Towers, waves & alerts
    sfx["build"] = mix(
        sweep(0.14, 180, 90, "tri", 2.3, 0.002, 0.85),
        pad(sweep(0.12, 390, 580, "sine", 2.4, 0.004, 0.55), 0.04),
    )
    sfx["upgrade"] = note_chord([587.33, 880.0, 1174.66], 0.24, 0.055, "warm", 2.1)
    sfx["sell"] = note_chord([1174.66, 1567.98], 0.16, 0.05, "sine", 2.6)
    sfx["gadget_wake"] = note_chord([659.25, 987.77], 0.18, 0.05, "sine", 2.3)
    sfx["sleep_dust"] = note_chord([783.99, 622.25, 493.88], 0.26, 0.075, "sine", 2.2)
    sfx["wave_start"] = mix(
        sweep(0.38, 196.0, 293.66, "warm", 1.6, 0.015, 0.8),
        pad(sweep(0.32, 293.66, 392.0, "warm", 1.8, 0.015, 0.6), 0.14),
    )
    sfx["wave_clear"] = note_chord([523.25, 659.25, 783.99, 1046.5], 0.34, 0.08, "warm", 1.9)
    sfx["boss_warn"] = mix(
        sweep(0.30, 146.83, 110.0, "saw", 1.6, 0.01, 0.55),
        pad(sweep(0.38, 130.81, 92.5, "saw", 1.5, 0.01, 0.65), 0.26),
    )
    sfx["tree_hurt"] = mix(
        sweep(0.24, 240, 110, "saw", 2.0, 0.003, 0.55),
        sweep(0.24, 220, 95, "sine", 1.9, 0.003, 0.65),
    )
    sfx["dazed"] = mix(
        sweep(0.26, 620, 320, "sine", 1.8, 0.005, 0.55),
        pad(sweep(0.22, 340, 560, "sine", 2.0, 0.005, 0.45), 0.10),
    )
    sfx["victory"] = mix(
        note_chord([523.25, 659.25, 783.99, 1046.5], 0.45, 0.085, "warm", 1.8),
        pad(note_chord([783.99, 1046.5, 1318.5, 1567.98], 0.65, 0.075, "warm", 1.6), 0.38),
    )
    sfx["game_over"] = note_chord([440.0, 392.0, 349.23, 293.66], 0.45, 0.16, "warm", 1.7)
    sfx["ui_click"] = sweep(0.055, 660, 420, "sine", 3.0, 0.001, 0.7)
    sfx["error"] = mix(
        sweep(0.10, 220, 180, "tri", 2.4, 0.003, 0.65),
        pad(sweep(0.12, 180, 140, "tri", 2.2, 0.003, 0.65), 0.11),
    )

    # Garden Clash SFX
    sfx["slam_warn"] = sweep(0.32, 95, 210, "tri", 1.4, 0.02, 0.75)
    sfx["slam_hit"] = mix(
        sweep(0.35, 140, 36, "sine", 1.5, 0.002, 1.0),
        noise(0.32, 1.8, 0.002, lp=0.22, amp=0.95, seed=25),
    )
    sfx["clash_tower_fire"] = sweep(0.11, 740, 320, "tri", 2.3, 0.002, 0.65)
    sfx["struct_down"] = mix(
        sweep(0.65, 160, 34, "sine", 1.4, 0.004, 1.0),
        noise(0.60, 1.6, 0.003, lp=0.25, amp=0.95, seed=26),
        pad(note_chord([392.0, 523.25, 659.25], 0.30, 0.05, "warm", 2.0), 0.18),
    )
    sfx["hero_down"] = mix(
        sweep(0.34, 380, 110, "tri", 1.8, 0.005, 0.75),
        pad(sweep(0.24, 240, 95, "sine", 2.0, 0.01, 0.6), 0.12),
    )
    sfx["revive"] = note_chord([523.25, 659.25, 783.99, 1046.5], 0.28, 0.045, "sine", 2.2)
    sfx["golden_buy"] = mix(
        note_chord([1046.5, 1318.5, 1567.98, 2093.0], 0.32, 0.04, "sine", 2.2),
        sweep(0.14, 880, 1760, "tri", 2.4, 0.002, 0.5),
    )
    sfx["potion_drink"] = mix(
        sweep(0.16, 280, 620, "sine", 2.1, 0.01, 0.55),
        pad(note_chord([659.25, 987.77], 0.22, 0.04, "sine", 2.3), 0.08),
    )

    for name, data in sfx.items():
        write_wav(os.path.join(SFX_DIR, f"{name}.wav"), data)
    return len(sfx)


# ---------------------------------------------------------------------------
# Adaptive Looping Background Music (exact 16.0s = 8 bars @ 120 BPM)
# ---------------------------------------------------------------------------
def build_music() -> int:
    beat = 0.5  # 120 BPM
    loop_s = 16.0
    n_samples = int(loop_s * SR)

    # Chord progression: Cmaj7 - Am7 - Fmaj7 - G6 (4 bars, repeated)
    chords = [
        [261.63, 329.63, 392.00, 493.88],  # Cmaj7
        [220.00, 261.63, 329.63, 392.00],  # Am7
        [174.61, 220.00, 261.63, 329.63],  # Fmaj7
        [196.00, 246.94, 293.66, 329.63],  # G6
    ] * 2
    bass_notes = [130.81, 110.00, 87.31, 98.00] * 2

    # Gentle cozy prep track: marimba arpeggios + soft flute melody
    calm = [0.0] * n_samples
    melody = [
        (0.0, 523.25, 0.6), (1.0, 659.25, 0.6), (2.0, 587.33, 0.8),
        (4.0, 493.88, 0.6), (5.0, 523.25, 0.6), (6.0, 440.00, 0.9),
        (8.0, 392.00, 0.6), (9.0, 440.00, 0.6), (10.0, 523.25, 0.8),
        (12.0, 587.33, 0.6), (13.0, 659.25, 0.6), (14.0, 587.33, 1.0),
    ]
    for bar_i, ch in enumerate(chords):
        bar_t = bar_i * 4 * beat
        # Warm soft pad
        for f in ch:
            add_looped(calm, bar_t, sweep(1.9, f * 0.5, f * 0.5, "sine", 1.2, 0.18, 0.14))
        # Plucked marimba pattern
        for step_i in range(8):
            f = ch[step_i % len(ch)] * (2.0 if step_i % 4 == 3 else 1.0)
            add_looped(calm, bar_t + step_i * (beat * 0.5), sweep(0.32, f, f, "warm", 2.6, 0.005, 0.24))
    for t_s, freq, dur in melody:
        add_looped(calm, t_s, sweep(dur, freq, freq, "sine", 1.6, 0.04, 0.28))

    # Active wave track: adds bouncy bass + light crisp percussion + bright octave plucks
    wave_trk = [v * 0.82 for v in calm]
    kick = sweep(0.14, 120.0, 42.0, "sine", 2.2, 0.002, 0.55)
    hat = noise(0.05, 3.0, 0.001, lp=0.85, hp=0.45, amp=0.22, seed=31)
    snare = mix(noise(0.10, 2.4, 0.002, lp=0.65, hp=0.18, amp=0.30, seed=32), sweep(0.08, 220, 140, "tri", 2.6, 0.002, 0.20))
    for step_i in range(32):
        t_s = step_i * beat
        bar_i = step_i // 4
        bf = bass_notes[bar_i]
        if step_i % 2 == 0:
            add_looped(wave_trk, t_s, kick, 0.75)
            add_looped(wave_trk, t_s, sweep(0.28, bf, bf, "tri", 2.0, 0.006, 0.34))
        else:
            add_looped(wave_trk, t_s, snare, 0.55)
            add_looped(wave_trk, t_s, sweep(0.20, bf * 1.5, bf * 1.5, "tri", 2.3, 0.006, 0.22))
        add_looped(wave_trk, t_s + 0.25, hat, 0.45)

    # Boss / Clash climax track: driving C minor heroic pulse
    boss = [0.0] * n_samples
    b_chords = [
        [261.63, 311.13, 392.00],  # Cm
        [207.65, 261.63, 311.13],  # Ab
        [233.08, 293.66, 349.23],  # Bb
        [196.00, 246.94, 293.66],  # G
    ] * 2
    b_bass = [130.81, 103.83, 116.54, 98.00] * 2
    b_lead = [
        (0.0, 523.25, 0.45), (0.5, 622.25, 0.45), (1.0, 587.33, 0.45), (1.5, 523.25, 0.45),
        (2.0, 466.16, 0.65), (3.0, 392.00, 0.8),
        (4.0, 415.30, 0.45), (4.5, 523.25, 0.45), (5.0, 622.25, 0.65), (6.0, 587.33, 0.8),
    ]
    for rep in [0.0, 8.0]:
        for t_s, freq, dur in b_lead:
            add_looped(boss, rep + t_s, sweep(dur, freq, freq, "warm", 1.7, 0.012, 0.34))
    for bar_i, ch in enumerate(b_chords):
        bar_t = bar_i * 4 * beat
        bf = b_bass[bar_i]
        for sub in range(8):
            t_s = bar_t + sub * (beat * 0.5)
            add_looped(boss, t_s, sweep(0.18, bf * (1.0 if sub % 2 == 0 else 2.0), bf, "saw", 2.4, 0.004, 0.22))
            if sub % 2 == 0:
                add_looped(boss, t_s, kick, 0.8)
            if sub % 4 == 2:
                add_looped(boss, t_s, snare, 0.7)
            add_looped(boss, t_s + 0.125, hat, 0.4)
        for f in ch:
            add_looped(boss, bar_t, sweep(1.8, f, f, "tri", 1.5, 0.04, 0.16))

    write_wav(os.path.join(MUSIC_DIR, "music_calm.wav"), calm, norm=0.72)
    write_wav(os.path.join(MUSIC_DIR, "music_wave.wav"), wave_trk, norm=0.76)
    write_wav(os.path.join(MUSIC_DIR, "music_boss.wav"), boss, norm=0.78)
    return 3


# ---------------------------------------------------------------------------
# Map Ambient Beds (8.0s seamless loops)
# ---------------------------------------------------------------------------
def build_ambience() -> int:
    dur = 8.4  # trimmed to 8.0s by make_seamless
    rng = random.Random(77)

    def wind_bed(lp: float, hp: float, amp: float, seed: int) -> list[float]:
        n = int(dur * SR)
        r = random.Random(seed)
        raw = [r.uniform(-1.0, 1.0) for _ in range(n)]
        bed = lowpass(raw, lp)
        if hp > 0.0:
            bed = highpass(bed, hp)
        # Gentle slow swell
        return [bed[i] * (0.65 + 0.35 * math.sin(2.0 * math.pi * i / n * 2.0)) * amp for i in range(n)]

    # Meadow: breeze + soft cheerful birds
    meadow = wind_bed(0.06, 0.01, 0.35, 41)
    for t in [0.9, 2.3, 4.1, 6.2]:
        chirp = mix(sweep(0.09, 2100, 2900, "sine", 2.2, 0.006, 0.22), pad(sweep(0.09, 2700, 2200, "sine", 2.4, 0.006, 0.18), 0.11))
        add_looped(meadow, t, chirp)
    meadow = make_seamless(meadow)

    # River: gentle water brook murmur
    river = mix(wind_bed(0.16, 0.04, 0.45, 42), wind_bed(0.32, 0.12, 0.20, 43))
    river = make_seamless(river)

    # Courtyard: soft night crickets + faint starlight chimes
    courtyard = wind_bed(0.05, 0.01, 0.22, 44)
    for t in [0.6, 2.8, 4.9, 6.7]:
        c = mix(sweep(0.06, 3600, 3600, "sine", 2.5, 0.004, 0.12), pad(sweep(0.06, 3600, 3600, "sine", 2.5, 0.004, 0.12), 0.09))
        add_looped(courtyard, t, c)
    courtyard = make_seamless(courtyard)

    # Hollow: autumn leaf rustle
    hollow = mix(wind_bed(0.10, 0.02, 0.36, 45), wind_bed(0.28, 0.10, 0.14, 46))
    hollow = make_seamless(hollow)

    # Frosty: crisp winter wind + icy sparkle
    frosty = wind_bed(0.09, 0.025, 0.38, 47)
    for t in [1.4, 3.9, 6.4]:
        add_looped(frosty, t, sweep(0.45, 1760, 1760, "sine", 2.4, 0.04, 0.10))
    frosty = make_seamless(frosty)

    # Valley (Clash): canyon breeze + distant war-drum pulse
    valley = wind_bed(0.08, 0.015, 0.34, 48)
    for t in [0.0, 2.0, 4.0, 6.0]:
        add_looped(valley, t, sweep(0.20, 95, 55, "sine", 2.2, 0.01, 0.15))
    valley = make_seamless(valley)

    beds = {
        "amb_meadow": meadow,
        "amb_river": river,
        "amb_courtyard": courtyard,
        "amb_hollow": hollow,
        "amb_frosty": frosty,
        "amb_valley": valley,
    }
    for name, data in beds.items():
        write_wav(os.path.join(AMB_DIR, f"{name}.wav"), data, norm=0.35, soft_clip=False)
    return len(beds)


# ---------------------------------------------------------------------------
# Dialog & Voice Processing
# ---------------------------------------------------------------------------
def resample_pitch(samples: list[float], pitch_mult: float) -> list[float]:
    if abs(pitch_mult - 1.0) < 0.01:
        return samples
    n_out = int(len(samples) / pitch_mult)
    out = []
    for i in range(n_out):
        pos = i * pitch_mult
        idx = int(pos)
        frac = pos - idx
        a = samples[idx] if idx < len(samples) else 0.0
        b = samples[idx + 1] if idx + 1 < len(samples) else a
        out.append(a + (b - a) * frac)
    return out


def add_echo(samples: list[float], delay_s: float = 0.065, wet: float = 0.22, sr: int = SR) -> list[float]:
    d = int(delay_s * sr)
    out = samples + [0.0] * d
    for i in range(len(samples)):
        out[i + d] += samples[i] * wet
    return out


def trim_silence(samples: list[float], thresh: float = 0.015, pad_n: int = 800) -> list[float]:
    start = 0
    while start < len(samples) and abs(samples[start]) < thresh:
        start += 1
    end = len(samples) - 1
    while end > start and abs(samples[end]) < thresh:
        end -= 1
    start = max(0, start - pad_n)
    end = min(len(samples), end + pad_n)
    return samples[start:end] if end > start else samples


HERO_VOICE_SPECS = {
    "pea": {"speaker": "Pea Blaster", "voice": "Reed (English (US))", "rate": 202, "pitch": 1.06, "style": "cheerful upbeat young hero"},
    "sun": {"speaker": "Sun Blossom", "voice": "Samantha", "rate": 192, "pitch": 1.05, "style": "warm encouraging support"},
    "frost": {"speaker": "Frost Lotus", "voice": "Karen", "rate": 185, "pitch": 1.02, "style": "cool calm ice mage"},
    "boom": {"speaker": "Boom Shroom", "voice": "Rocko (English (US))", "rate": 182, "pitch": 0.90, "style": "jovial booming tank"},
    "volt": {"speaker": "Volt Cactus", "voice": "Eddy (English (US))", "rate": 208, "pitch": 1.07, "style": "zippy energetic spark"},
    "snap": {"speaker": "Snapdragon", "voice": "Ralph", "rate": 188, "pitch": 0.95, "echo": True, "style": "fierce fiery dragon"},
    "bubble": {"speaker": "Bubble Lily", "voice": "Moira", "rate": 198, "pitch": 1.08, "style": "playful bubbly water spirit"},
}

HERO_LINES = {
    "pea": {
        "pick": ["Pea Blaster, locked and sprouted!", "Ready to blast some pests!", "Aim true, shoot fast!"],
        "special": ["Pea storm! Take cover!", "Pods away!", "Green barrage incoming!"],
        "level": ["Growing stronger!", "Faster pods, sharper aim!", "Feeling super sprouted!"],
        "evolve": ["Full gatling bloom!", "Wait till they see these pods!"],
    },
    "sun": {
        "pick": ["Let's grow together!", "Sunshine brings out our best!", "Ready to power up the team!"],
        "special": ["Sunburst! Shine bright, everyone!", "Feel the golden warmth!", "Rise and bloom!"],
        "level": ["More sunshine for the team!", "Brighter petals every wave!", "Warming up nicely!"],
        "evolve": ["Radiant full bloom!", "Let the sun guide us!"],
    },
    "frost": {
        "pick": ["Stay cool. I've got the chill.", "Ice cold and steady.", "Let's slow this swarm down."],
        "special": ["Blizzard! Freeze right there!", "Ice storm unleashed!", "Nobody moves!"],
        "level": ["Colder and sharper!", "Frost deepens.", "Chillier by the second!"],
        "evolve": ["Absolute winter!", "Crystal perfection!"],
    },
    "boom": {
        "pick": ["Ready to make a big boom!", "Who wants fireworks?", "Stand back, I brought spores!"],
        "special": ["Mega mushroom incoming!", "Boom time!", "Big blast, coming right up!"],
        "level": ["Bigger booms ahead!", "Extra blast powder!", "Heavy artillery ready!"],
        "evolve": ["Colossal cap upgrade!", "Nothing survives this blast!"],
    },
    "volt": {
        "pick": ["Charged up and prickly!", "Let's spark things up!", "High voltage defender ready!"],
        "special": ["Thunderstorm! Feel the zap!", "Lightning strikes everywhere!", "Shocking surprise!"],
        "level": ["High voltage!", "More arcs, more power!", "Buzzing with energy!"],
        "evolve": ["Tempest power unlocked!", "Pure lightning!"],
    },
    "snap": {
        "pick": ["Time to turn up the heat!", "Smells like roasted pests!", "Watch the sparks fly!"],
        "special": ["Inferno nova!", "Burn bright!", "Feel the dragon's fire!"],
        "level": ["My flames burn hotter!", "Fiercer fire!", "Blazing ahead!"],
        "evolve": ["Phoenix power awakened!", "Unstoppable flames!"],
    },
    "bubble": {
        "pick": ["Splish splash, let's soak them!", "Bubbles ready to pop!", "Water makes lightning extra zappy!"],
        "special": ["Tidal wave! Wash them back!", "Surf's up, pests!", "Big splash incoming!"],
        "level": ["Bubbles getting bouncier!", "Refreshing upgrade!", "Making bigger waves!"],
        "evolve": ["Tidal queen power!", "Ocean surge!"],
    },
}


def _make_dialog_lines() -> list[dict]:
    lines: list[dict] = []
    for pre, cats in HERO_LINES.items():
        spec = HERO_VOICE_SPECS[pre]
        for cat, texts in cats.items():
            for idx, txt in enumerate(texts):
                lines.append({
                    "id": f"{pre}_{cat}_{idx}",
                    "voice": spec["voice"],
                    "rate": spec["rate"],
                    "pitch": spec["pitch"],
                    "echo": spec.get("echo", False),
                    "text": txt,
                    "speaker": spec["speaker"],
                })

    # Shared co-op & Clash hero quips (generic cheerful voices)
    shared = [
        {"id": "coop_wake_0", "voice": "Samantha", "rate": 195, "pitch": 1.06, "text": "Wakey wakey, tower!", "speaker": "Hero"},
        {"id": "coop_wake_1", "voice": "Reed (English (US))", "rate": 200, "pitch": 1.05, "text": "Back to work, sleepyhead!", "speaker": "Hero"},
        {"id": "clash_down_0", "voice": "Eddy (English (US))", "rate": 200, "pitch": 1.04, "text": "Whoa, I'm knocked out! Help me up!", "speaker": "Hero"},
        {"id": "clash_revive_0", "voice": "Moira", "rate": 196, "pitch": 1.06, "text": "Thanks, friend! Back in action!", "speaker": "Hero"},
        {"id": "clash_golden_0", "voice": "Samantha", "rate": 195, "pitch": 1.05, "text": "Ooh, shiny golden upgrade!", "speaker": "Hero"},
        {"id": "clash_potion_0", "voice": "Karen", "rate": 190, "pitch": 1.03, "text": "Mmm, berry juice! Much better!", "speaker": "Hero"},
    ]
    lines.extend(shared)

    # Garden Announcer
    ann = [
        ("ann_welcome", 185, 1.00, False, "Defend the Bloom Tree!"),
        ("ann_wave_0", 192, 1.02, False, "Here come the pests!"),
        ("ann_wave_1", 194, 1.02, False, "Next wave incoming! Hold your ground!"),
        ("ann_wave_2", 190, 1.01, False, "Stay sharp, garden heroes!"),
        ("ann_camo", 188, 1.00, False, "Heads up! Mist Puffs are camouflaged!"),
        ("ann_mole", 188, 1.00, False, "Watch the trails! Digger Moles are tunneling!"),
        ("ann_sleep", 190, 1.00, False, "A Snoozy Moth put a tower to sleep! Walk near to wake it!"),
        ("ann_tree_low", 194, 1.02, False, "Hold the line! Protect the Bloom Tree!"),
        ("ann_combo_0", 200, 1.05, True, "Amazing team combo!"),
        ("ann_combo_1", 202, 1.05, True, "What a team synergy!"),
        ("ann_clear_0", 192, 1.02, False, "Wave cleared! Great teamwork!"),
        ("ann_clear_1", 192, 1.03, False, "Clean sweep! Well defended!"),
        ("ann_milestone", 190, 1.04, True, "Milestone reached! Bonus cards for all!"),
        ("ann_victory", 185, 1.03, True, "Victory! The Bloom Tree is safe!"),
        ("ann_gameover", 178, 0.98, False, "The Bloom Tree fell. Let's try again!"),
        ("ann_toad_up", 190, 1.01, True, "Rumble Toad has awakened in the jungle!"),
        ("ann_toad_power", 194, 1.03, True, "Toad Power! Your Sproutlings are unstoppable!"),
        ("ann_elder_power", 192, 1.04, True, "Elder Toad Power! Smash their Thorn Heart!"),
        ("ann_gate_down", 192, 1.03, True, "Gate shattered! Super Sprouts marching!"),
        ("ann_heart_open", 194, 1.03, True, "The Thorn Heart is exposed! Attack!"),
        ("ann_tower_alert", 192, 1.00, False, "Our tower is under attack!"),
    ]
    for lid, rate, pitch, echo, txt in ann:
        lines.append({"id": lid, "voice": "Daniel", "rate": rate, "pitch": pitch, "echo": echo, "text": txt, "speaker": "Announcer"})

    # Adventure Bosses & Clash Rival Champions
    bosses = [
        ("boss_zep", "Grandpa (English (UK))", 168, 0.84, True, "Spore Zeppelin airborne! Drop the spores!", "Spore Zeppelin"),
        ("boss_monarch", "Grandpa (English (UK))", 160, 0.78, True, "I am the Dread Monarch! Your garden belongs to me!", "Dread Monarch"),
        ("boss_enrage", "Grandpa (English (UK))", 175, 0.76, True, "Enough! Feel the swarm's fury!", "Dread Monarch"),
        ("rival_brute_0", "Rocko (English (US))", 172, 0.82, True, "Sir Shellbash reporting! None shall pass my shell!", "Sir Shellbash"),
        ("rival_brute_1", "Rocko (English (US))", 176, 0.80, True, "Time for a shell slam!", "Sir Shellbash"),
        ("rival_queen_0", "Karen", 194, 1.05, True, "Queen Stinger rules this lane!", "Queen Stinger"),
        ("rival_queen_1", "Karen", 198, 1.07, True, "Taste the hive's sting!", "Queen Stinger"),
        ("rival_mole_0", "Ralph", 180, 0.90, True, "Digger Duke here! Watch below your feet!", "Digger Duke"),
        ("rival_mole_1", "Ralph", 186, 0.88, True, "Tunneling right under you!", "Digger Duke"),
        ("rival_witch_0", "Grandma (English (UK))", 180, 1.04, True, "Spore Witch brewing trouble!", "Spore Witch"),
        ("rival_witch_1", "Grandma (English (UK))", 184, 1.06, True, "Nighty-night, little sprouts!", "Spore Witch"),
    ]
    for lid, voice, rate, pitch, echo, txt, spk in bosses:
        lines.append({"id": lid, "voice": voice, "rate": rate, "pitch": pitch, "echo": echo, "text": txt, "speaker": spk})

    return lines


DIALOG_LINES = _make_dialog_lines()


def build_voices_local() -> int:
    os.makedirs(VOICE_DIR, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for line in DIALOG_LINES:
            aiff = os.path.join(tmp, f"{line['id']}.aiff")
            raw_wav = os.path.join(tmp, f"{line['id']}_raw.wav")
            out_wav = os.path.join(VOICE_DIR, f"{line['id']}.wav")
            subprocess.run(
                ["say", "-v", line["voice"], "-r", str(line["rate"]), "-o", aiff, line["text"]],
                check=True,
            )
            subprocess.run(
                ["afconvert", "-f", "WAVE", "-d", f"LEI16@{SR}", aiff, raw_wav],
                check=True,
            )
            samples, _ = read_wav(raw_wav)
            samples = trim_silence(samples)
            samples = resample_pitch(samples, line.get("pitch", 1.0))
            if line.get("echo", False):
                samples = add_echo(samples, 0.065, 0.22)
            write_wav(out_wav, samples, norm=0.90)
    return len(DIALOG_LINES)


def _split_chunk_bounds(samples: list[float], sr: int, min_sil_s: float = 0.48, thresh: float = 0.018) -> list[tuple[int, int]]:
    win = max(1, int(0.02 * sr))
    chunks: list[tuple[int, int]] = []
    in_sp = False
    s0 = 0
    sil = 0
    for i in range(0, len(samples), win):
        block = samples[i : i + win]
        pk = max((abs(v) for v in block), default=0.0)
        if pk > thresh:
            if not in_sp:
                in_sp = True
                s0 = max(0, i - int(0.04 * sr))
            sil = 0
        elif in_sp:
            sil += 1
            if sil * 0.02 >= min_sil_s:
                e0 = min(len(samples), i - sil * win + int(0.05 * sr))
                if e0 - s0 > int(0.18 * sr):
                    chunks.append((s0, e0))
                in_sp = False
    if in_sp:
        e0 = len(samples)
        if e0 - s0 > int(0.18 * sr):
            chunks.append((s0, e0))
    return chunks


def _split_segments(samples: list[float], sr: int, min_sil_s: float = 0.48, thresh: float = 0.018) -> list[list[float]]:
    return [samples[a:b] for a, b in _split_chunk_bounds(samples, sr, min_sil_s=min_sil_s, thresh=thresh)]


def _split_segments_exact(samples: list[float], sr: int, n_expected: int) -> list[list[float]]:
    if n_expected <= 1:
        return [samples] if samples else []
    for ms in (0.85, 0.78, 0.70, 0.62, 0.54, 0.48, 0.40, 0.34, 0.28):
        bounds = _split_chunk_bounds(samples, sr, min_sil_s=ms, thresh=0.018)
        if len(bounds) == n_expected:
            return [samples[a:b] for a, b in bounds]
    # Merge across the shortest gaps from fine chunks so internal sentence pauses stay together
    bounds = _split_chunk_bounds(samples, sr, min_sil_s=0.26, thresh=0.016)
    if len(bounds) < n_expected:
        bounds = _split_chunk_bounds(samples, sr, min_sil_s=0.18, thresh=0.012)
    if len(bounds) < n_expected:
        return []
    while len(bounds) > n_expected:
        best_i = min(range(len(bounds) - 1), key=lambda i: bounds[i + 1][0] - bounds[i][1])
        bounds[best_i : best_i + 2] = [(bounds[best_i][0], bounds[best_i + 1][1])]
    return [samples[a:b] for a, b in bounds]


TTS_MODELS = [
    "gemini-2.5-flash-preview-tts",
    "gemini-3.1-flash-tts-preview",
    "gemini-3.8-flash-tts",
    "gemini-3.8-flash-lite-tts",
    "gemini-2.5-pro-preview-tts",
]


def _run_gemini_tts(text: str, voice: str, out_wav: str, model_pref: str, exhausted: set[str]) -> str:
    import re
    import time

    env = os.environ.copy()
    env["PATH"] = os.path.expanduser("~/.local/bin") + ":" + env.get("PATH", "")
    candidates = TTS_MODELS if model_pref == "auto" else [model_pref] + [m for m in TTS_MODELS if m != model_pref]
    candidates = [m for m in candidates if m not in exhausted]
    if not candidates:
        raise RuntimeError("All Gemini TTS models have hit quota/permission limits.")

    for mdl in candidates:
        for attempt in range(5):
            if os.path.exists(out_wav):
                os.remove(out_wav)
            res = subprocess.run(
                ["gemini-api", "tts", text, "-m", mdl, "-v", voice, "--out", out_wav],
                capture_output=True,
                text=True,
                env=env,
            )
            if res.returncode == 0 and os.path.exists(out_wav) and os.path.getsize(out_wav) > 1000:
                return mdl
            msg = ((res.stdout or "") + "\n" + (res.stderr or "")).strip()
            daily_hit = ("per day" in msg) or ("permission_denied" in msg) or ("403" in msg)
            m = re.search(r"retry in (\d+(?:\.\d+)?)(h|m|s)", msg)
            wait_s = 22
            if m:
                val, unit = float(m.group(1)), m.group(2)
                if unit in ("h", "m") and (unit == "h" or val > 2.0):
                    daily_hit = True
                else:
                    wait_s = int(val) + 3
            if daily_hit:
                brief = msg.splitlines()[-1] if msg else "quota/auth limit"
                print(f"  Model {mdl} unavailable ({brief}); switching model...", flush=True)
                exhausted.add(mdl)
                break
            if any(k in msg for k in ("429", "rate_limit", "too_many_requests", "service_disabled", "503", "500")):
                wait_s = max(wait_s, 22 if mdl == "gemini-3.8-flash-tts" else 14 + attempt * 8)
                print(f"  Temporary API pause ({mdl}/{voice}); waiting {wait_s}s...", flush=True)
                time.sleep(wait_s)
                continue
            raise RuntimeError(f"gemini-api tts failed ({mdl}/{voice}): {msg}")
    raise RuntimeError(f"gemini-api tts failed after trying models {candidates} ({voice})")


def build_voices_gemini(model: str = "auto") -> int:
    os.makedirs(VOICE_DIR, exist_ok=True)
    voice_map = {
        "Pea Blaster": "Puck",
        "Sun Blossom": "Aoede",
        "Frost Lotus": "Kore",
        "Boom Shroom": "Fenrir",
        "Volt Cactus": "Zephyr",
        "Snapdragon": "Charon",
        "Bubble Lily": "Leda",
        "Announcer": "Orus",
        "Spore Zeppelin": "Alnilam",
        "Dread Monarch": "Enceladus",
        "Sir Shellbash": "Fenrir",
        "Queen Stinger": "Kore",
        "Digger Duke": "Charon",
        "Spore Witch": "Aoede",
        "Hero": "Puck",
    }

    # Group only missing lines by speaker (up to 12 per batch) so RPD stays minimal
    groups: dict[str, list[dict]] = {}
    already_have = 0
    for line in DIALOG_LINES:
        if os.path.exists(os.path.join(VOICE_DIR, f"{line['id']}.wav")):
            already_have += 1
        else:
            groups.setdefault(line["speaker"], []).append(line)

    batches: list[list[dict]] = []
    for _spk, items in groups.items():
        for i in range(0, len(items), 12):
            batches.append(items[i : i + 12])

    import time
    written = already_have
    exhausted: set[str] = set()
    with tempfile.TemporaryDirectory() as tmp:
        for b_idx, batch in enumerate(batches):
            spk = batch[0]["speaker"]
            vname = voice_map.get(spk, "Kore")
            prompt = " <long pause> <long pause> ".join(x["text"] for x in batch)
            batch_wav = os.path.join(tmp, f"batch_{b_idx}.wav")
            print(f"[{b_idx + 1}/{len(batches)}] {spk} ({vname}, {len(batch)} lines)...", flush=True)
            used_mdl = _run_gemini_tts(prompt, vname, batch_wav, model, exhausted)
            time.sleep(21.5 if used_mdl == "gemini-3.8-flash-tts" else 6.0)
            samples, sr = read_wav(batch_wav)
            segs = _split_segments_exact(samples, sr, len(batch))
            if len(segs) == len(batch):
                for line, seg in zip(batch, segs):
                    seg = trim_silence(seg, thresh=0.012, pad_n=int(0.03 * sr))
                    if line.get("echo", False) and line["speaker"] in ("Dread Monarch", "Spore Zeppelin"):
                        seg = add_echo(seg, 0.055, 0.16, sr)
                    write_wav(os.path.join(VOICE_DIR, f"{line['id']}.wav"), seg, sr=sr, norm=0.90)
                    written += 1
            else:
                print(f"  Split mismatch ({len(segs)} vs {len(batch)}); falling back to individual lines...", flush=True)
                for line in batch:
                    one_wav = os.path.join(tmp, f"{line['id']}.wav")
                    used_mdl = _run_gemini_tts(line["text"], vname, one_wav, model, exhausted)
                    time.sleep(21.5 if used_mdl == "gemini-3.8-flash-tts" else 6.0)
                    s1, sr1 = read_wav(one_wav)
                    s1 = trim_silence(s1, thresh=0.012, pad_n=int(0.03 * sr1))
                    if line.get("echo", False) and line["speaker"] in ("Dread Monarch", "Spore Zeppelin"):
                        s1 = add_echo(s1, 0.055, 0.16, sr1)
                    write_wav(os.path.join(VOICE_DIR, f"{line['id']}.wav"), s1, sr=sr1, norm=0.90)
                    written += 1
    return written


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gemini", action="store_true", help="Use gemini-api CLI for TTS voices")
    ap.add_argument("--tts-model", default="auto", help="Gemini TTS model or 'auto' cascade")
    ap.add_argument("--skip-voices", action="store_true", help="Only regenerate SFX, music and ambience")
    ap.add_argument("--only-voices", action="store_true", help="Only regenerate voices")
    args = ap.parse_args()
    n_sfx = 0 if args.only_voices else build_sfx()
    n_mus = 0 if args.only_voices else build_music()
    n_amb = 0 if args.only_voices else build_ambience()
    n_voice = 0 if args.skip_voices else (build_voices_gemini(args.tts_model) if args.gemini else build_voices_local())
    print(f"Generated {n_sfx} SFX, {n_mus} music stems, {n_amb} ambience beds, {n_voice} voice files")


if __name__ == "__main__":
    main()
