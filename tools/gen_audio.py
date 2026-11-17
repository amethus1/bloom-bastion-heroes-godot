#!/usr/bin/env python3
"""
Generate procedural DSP sound effects (audio/sfx/*.wav) and character/announcer
dialog lines (audio/voice/*.wav) for Bloom Bastion Heroes.

By default this runs 100% locally and free using Python DSP synthesis for SFX
and macOS `say` + `afconvert` + DSP character processing for voices.
If `--gemini` is passed and `gemini-api` CLI is configured, voice lines can
also be generated with Gemini AI TTS.
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
SR = 22050


# ---------------------------------------------------------------------------
# Low-level DSP helpers
# ---------------------------------------------------------------------------
def write_wav(path: str, samples: list[float], sr: int = SR, norm: float = 0.88) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0)
    if peak < 1e-6:
        peak = 1.0
    scale = norm / peak
    pcm = bytearray()
    for s in samples:
        v = math.tanh(s * scale * 1.15) / math.tanh(1.15)
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

    # Impacts & pops
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
    sfx["thunder"] = mix(
        noise(0.45, 1.5, 0.001, lp=0.55, amp=0.9, seed=11),
        sweep(0.35, 920, 70, "saw", 2.2, 0.001, 0.55),
        pad(noise(0.40, 1.4, 0.02, lp=0.14, amp=0.85, seed=12), 0.05),
    )

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

    for name, data in sfx.items():
        write_wav(os.path.join(SFX_DIR, f"{name}.wav"), data)
    return len(sfx)


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


DIALOG_LINES: list[dict] = [
    # Pea Blaster
    {"id": "pea_pick", "voice": "Reed (English (US))", "rate": 200, "pitch": 1.06, "text": "Pea Blaster, locked and sprouted!", "speaker": "Pea Blaster"},
    {"id": "pea_special", "voice": "Reed (English (US))", "rate": 215, "pitch": 1.08, "text": "Pea storm! Take cover!", "speaker": "Pea Blaster"},
    {"id": "pea_level", "voice": "Reed (English (US))", "rate": 205, "pitch": 1.07, "text": "Growing stronger!", "speaker": "Pea Blaster"},

    # Sun Blossom
    {"id": "sun_pick", "voice": "Samantha", "rate": 190, "pitch": 1.05, "text": "Let's grow together!", "speaker": "Sun Blossom"},
    {"id": "sun_special", "voice": "Samantha", "rate": 198, "pitch": 1.07, "text": "Sunburst! Shine bright, everyone!", "speaker": "Sun Blossom"},
    {"id": "sun_level", "voice": "Samantha", "rate": 195, "pitch": 1.06, "text": "More sunshine for the team!", "speaker": "Sun Blossom"},

    # Frost Lotus
    {"id": "frost_pick", "voice": "Karen", "rate": 182, "pitch": 1.02, "text": "Stay cool. I've got the chill.", "speaker": "Frost Lotus"},
    {"id": "frost_special", "voice": "Karen", "rate": 192, "pitch": 1.04, "text": "Blizzard! Freeze right there!", "speaker": "Frost Lotus"},
    {"id": "frost_level", "voice": "Karen", "rate": 188, "pitch": 1.03, "text": "Colder and sharper!", "speaker": "Frost Lotus"},

    # Boom Shroom
    {"id": "boom_pick", "voice": "Rocko (English (US))", "rate": 180, "pitch": 0.90, "text": "Ready to make a big boom!", "speaker": "Boom Shroom"},
    {"id": "boom_special", "voice": "Rocko (English (US))", "rate": 190, "pitch": 0.88, "text": "Mega mushroom incoming!", "speaker": "Boom Shroom"},
    {"id": "boom_level", "voice": "Rocko (English (US))", "rate": 185, "pitch": 0.91, "text": "Bigger booms ahead!", "speaker": "Boom Shroom"},

    # Volt Cactus
    {"id": "volt_pick", "voice": "Eddy (English (US))", "rate": 205, "pitch": 1.06, "text": "Charged up and prickly!", "speaker": "Volt Cactus"},
    {"id": "volt_special", "voice": "Eddy (English (US))", "rate": 215, "pitch": 1.09, "text": "Thunderstorm! Feel the zap!", "speaker": "Volt Cactus"},
    {"id": "volt_level", "voice": "Eddy (English (US))", "rate": 210, "pitch": 1.07, "text": "High voltage!", "speaker": "Volt Cactus"},

    # Snapdragon
    {"id": "snap_pick", "voice": "Ralph", "rate": 185, "pitch": 0.95, "echo": True, "text": "Time to turn up the heat!", "speaker": "Snapdragon"},
    {"id": "snap_special", "voice": "Ralph", "rate": 195, "pitch": 0.93, "echo": True, "text": "Inferno nova!", "speaker": "Snapdragon"},
    {"id": "snap_level", "voice": "Ralph", "rate": 190, "pitch": 0.96, "text": "My flames burn hotter!", "speaker": "Snapdragon"},

    # Bubble Lily
    {"id": "bubble_pick", "voice": "Moira", "rate": 196, "pitch": 1.08, "text": "Splish splash, let's soak them!", "speaker": "Bubble Lily"},
    {"id": "bubble_special", "voice": "Moira", "rate": 205, "pitch": 1.10, "text": "Tidal wave! Wash them back!", "speaker": "Bubble Lily"},
    {"id": "bubble_level", "voice": "Moira", "rate": 200, "pitch": 1.08, "text": "Bubbles getting bouncier!", "speaker": "Bubble Lily"},

    # Garden Announcer
    {"id": "ann_welcome", "voice": "Daniel", "rate": 185, "pitch": 1.0, "text": "Defend the Bloom Tree!", "speaker": "Announcer"},
    {"id": "ann_wave", "voice": "Daniel", "rate": 192, "pitch": 1.02, "text": "Here come the pests!", "speaker": "Announcer"},
    {"id": "ann_camo", "voice": "Daniel", "rate": 188, "pitch": 1.0, "text": "Heads up! Mist Puffs are camouflaged!", "speaker": "Announcer"},
    {"id": "ann_mole", "voice": "Daniel", "rate": 188, "pitch": 1.0, "text": "Watch the trails! Digger Moles are tunneling!", "speaker": "Announcer"},
    {"id": "ann_sleep", "voice": "Daniel", "rate": 190, "pitch": 1.0, "text": "A Snoozy Moth put a tower to sleep! Walk near to wake it!", "speaker": "Announcer"},
    {"id": "ann_combo", "voice": "Daniel", "rate": 200, "pitch": 1.05, "echo": True, "text": "Amazing team combo!", "speaker": "Announcer"},
    {"id": "ann_clear", "voice": "Daniel", "rate": 192, "pitch": 1.02, "text": "Wave cleared! Great teamwork!", "speaker": "Announcer"},
    {"id": "ann_milestone", "voice": "Daniel", "rate": 190, "pitch": 1.04, "echo": True, "text": "Milestone reached! Bonus cards for all!", "speaker": "Announcer"},
    {"id": "ann_victory", "voice": "Daniel", "rate": 185, "pitch": 1.03, "echo": True, "text": "Victory! The Bloom Tree is safe!", "speaker": "Announcer"},
    {"id": "ann_gameover", "voice": "Daniel", "rate": 178, "pitch": 0.98, "text": "The Bloom Tree fell. Let's try again!", "speaker": "Announcer"},

    # Bosses
    {"id": "boss_zep", "voice": "Grandpa (English (UK))", "rate": 168, "pitch": 0.84, "echo": True, "text": "Spore Zeppelin airborne! Drop the spores!", "speaker": "Spore Zeppelin"},
    {"id": "boss_monarch", "voice": "Grandpa (English (UK))", "rate": 160, "pitch": 0.78, "echo": True, "text": "I am the Dread Monarch! Your garden belongs to me!", "speaker": "Dread Monarch"},
    {"id": "boss_enrage", "voice": "Grandpa (English (UK))", "rate": 175, "pitch": 0.76, "echo": True, "text": "Enough! Feel the swarm's fury!", "speaker": "Dread Monarch"},
]


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


def build_voices_gemini() -> int:
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
    }
    for line in DIALOG_LINES:
        out_wav = os.path.join(VOICE_DIR, f"{line['id']}.wav")
        vname = voice_map.get(line["speaker"], "Kore")
        subprocess.run(
            ["gemini-api", "tts", line["text"], "-v", vname, "--out", out_wav],
            check=True,
        )
    return len(DIALOG_LINES)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gemini", action="store_true", help="Use gemini-api CLI for TTS voices")
    args = ap.parse_args()
    n_sfx = build_sfx()
    n_voice = build_voices_gemini() if args.gemini else build_voices_local()
    print(f"Generated {n_sfx} SFX files in {SFX_DIR}")
    print(f"Generated {n_voice} voice files in {VOICE_DIR}")


if __name__ == "__main__":
    main()
