#!/usr/bin/env python3
"""Procedural sound effects for Zelda-BR, in an N64 adventure tone:
warm bell chimes for items/UI, airy whooshes, woody knocks, soft low-passed
thuds, a touch of room reverb. All original, generated from scratch.

Usage:  python3 make_sfx.py <project_root>
Writes mono 16-bit WAVs to <project_root>/assets/audio/sfx/<category>/
and regenerates <project_root>/data/registry/sounds.tres.
Tweak a recipe below, rerun, and Godot picks up the new files.
"""
import os
import sys
import wave
import numpy as np

SR = 44100
RNG = np.random.default_rng(1998)


# ------------------------------------------------------------------ basics
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return RNG.uniform(-1, 1, int(dur * SR))


def env_ad(n, attack, decay, curve=4.0):
    """Attack (s) then exponential-ish decay over `decay` seconds."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-curve * np.clip(t - attack, 0, None) / max(decay, 1e-4))
    return a * d


def fft_filter(x, lo=None, hi=None, order=2):
    """Zero-phase band shaping (smooth Butterworth-like magnitude)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.ones_like(f)
    if hi is not None:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    if lo is not None:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * g, n)


def svf_sweep(x, f0, f1, q=2.0, curve=1.0):
    """State-variable bandpass with a centre frequency sweeping f0 -> f1."""
    n = len(x)
    k = (np.arange(n) / max(n - 1, 1)) ** curve
    fc = f0 * (f1 / f0) ** k
    g = np.tan(np.pi * np.clip(fc, 20, SR * 0.45) / SR)
    r = 1.0 / q
    out = np.zeros(n)
    s1 = s2 = 0.0
    for i in range(n):
        gi = g[i]
        hp = (x[i] - (r + gi) * s1 - s2) / (1 + r * gi + gi * gi)
        bp = gi * hp + s1
        s1 = gi * hp + bp
        lp = gi * bp + s2
        s2 = gi * bp + lp
        out[i] = bp
    return out


def tone(freq, dur, kind="sine", fm_ratio=0.0, fm_index=0.0, fm_decay=8.0):
    t = t_axis(dur)
    if callable(freq):
        f = freq(t)
    else:
        f = np.full_like(t, float(freq))
    mod = 0.0
    if fm_index:
        mod = fm_index * np.exp(-fm_decay * t) * np.sin(2 * np.pi * f * fm_ratio * t)
    ph = 2 * np.pi * np.cumsum(f) / SR + mod
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "square":
        return np.tanh(3 * np.sin(ph))
    raise ValueError(kind)


def bell(freq, dur, bright=1.0, decay=None):
    """Glassy N64-style chime: FM sine + soft octave partial."""
    decay = decay or dur
    n = int(dur * SR)
    x = tone(freq, dur, fm_ratio=3.5, fm_index=1.2 * bright, fm_decay=10)
    x += 0.25 * tone(freq * 2.0, dur, fm_ratio=1.0, fm_index=0.3)
    x += 0.10 * tone(freq * 3.01, dur)
    return x * env_ad(n, 0.003, decay, 5.0)


def thump(freq0, freq1, dur, decay=None):
    """Pitch-dropping low body hit."""
    f = lambda t: freq1 + (freq0 - freq1) * np.exp(-t * 40)
    n = int(dur * SR)
    return tone(f, dur) * env_ad(n, 0.002, decay or dur, 6.0)


def modal(freqs, dur, decays, amps=None):
    """Sum of decaying resonant modes (wood / stone knocks)."""
    t = t_axis(dur)
    amps = amps or [1.0] * len(freqs)
    x = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        x += a * np.sin(2 * np.pi * f * t + RNG.uniform(0, 6.28)) * np.exp(-t / d)
    return x


def pluck(freq, dur, damp=0.996, bright=0.5):
    """Karplus-Strong string."""
    n = int(dur * SR)
    p = max(2, int(SR / freq))
    buf = RNG.uniform(-1, 1, p)
    buf = fft_filter(np.tile(buf, 4), hi=2000 + 8000 * bright)[:p]
    out = np.zeros(n)
    for i in range(n):
        j = i % p
        out[i] = buf[j]
        buf[j] = damp * 0.5 * (buf[j] + buf[(j + 1) % p])
    return out


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    end = min(len(dst), i + len(src))
    if end > i:
        dst[i:end] += gain * src[: end - i]
    return dst


def silence(dur):
    return np.zeros(int(dur * SR))


def reverb(x, wet=0.15, length=0.6, damp=3000):
    """Small warm room: convolve with filtered decaying noise."""
    ir_n = int(length * SR)
    ir = RNG.uniform(-1, 1, ir_n) * np.exp(-6 * np.arange(ir_n) / ir_n)
    ir = fft_filter(ir, hi=damp)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    y = np.concatenate([x, np.zeros(ir_n)])
    n = len(y) + ir_n
    wetsig = np.fft.irfft(np.fft.rfft(y, n) * np.fft.rfft(ir, n), n)[: len(y)]
    return y + wet * wetsig


def finish(x, peak=0.89, hi=11000, tail_fade=0.01, verb=0.12, verb_len=0.5):
    """N64 warmth: gentle low-pass, light room, normalise, trim silence."""
    x = np.asarray(x, dtype=float)
    if verb:
        x = reverb(x, verb, verb_len)
    if hi:
        x = fft_filter(x, hi=hi, order=1)
    x -= np.mean(x)
    # trim trailing near-silence
    thr = 10 ** (-60 / 20) * np.max(np.abs(x) + 1e-9)
    nz = np.nonzero(np.abs(x) > thr)[0]
    if len(nz):
        x = x[: nz[-1] + 1]
    fade = int(tail_fade * SR)
    if fade and len(x) > fade:
        x[-fade:] *= np.linspace(1, 0, fade)
    x[: 32] *= np.linspace(0, 1, min(32, len(x)))
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(
    ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name):
    """'E5' -> Hz"""
    return NOTE[name[:-1]] * 2 ** (int(name[-1]) - 4)


# ------------------------------------------------------------------ recipes
def footstep_grass(v):
    d = 0.22
    x = silence(d)
    crunch = fft_filter(noise(d), lo=1800, hi=7000) * env_ad(int(d * SR), 0.004, 0.09, 5)
    # granular blade rustle: a few tiny clicks
    for _ in range(6):
        place(x, fft_filter(noise(0.012), lo=3000) * env_ad(int(0.012 * SR), 0.001, 0.01),
              RNG.uniform(0.0, 0.07), RNG.uniform(0.2, 0.5))
    place(x, crunch, 0, 0.6)
    place(x, thump(140, 70, 0.1), 0, 0.5 + 0.1 * v)
    return finish(x, peak=0.6, hi=8000, verb=0.05)


def footstep_stone(v):
    d = 0.2
    x = silence(d)
    tick = fft_filter(noise(0.03), lo=1500) * env_ad(int(0.03 * SR), 0.0005, 0.02, 6)
    ping = modal([780 + 60 * v, 1310 + 80 * v, 2150], 0.12, [0.02, 0.012, 0.008], [0.5, 0.3, 0.2])
    place(x, tick, 0, 0.8)
    place(x, ping, 0, 0.5)
    place(x, thump(160, 90, 0.08), 0, 0.5)
    return finish(x, peak=0.6, hi=9000, verb=0.10)


def footstep_wood(v):
    d = 0.25
    x = silence(d)
    body = modal([190 + 15 * v, 420 + 20 * v, 760, 1180], 0.2, [0.05, 0.03, 0.018, 0.01],
                 [1.0, 0.6, 0.35, 0.2])
    place(x, body, 0, 0.7)
    place(x, fft_filter(noise(0.015), lo=1000, hi=6000) * env_ad(int(0.015 * SR), 0.0005, 0.01), 0, 0.5)
    return finish(x, peak=0.6, hi=7000, verb=0.10)


def footstep_straw(v):
    d = 0.25
    x = fft_filter(noise(d), lo=900, hi=5000) * env_ad(int(d * SR), 0.004, 0.12, 4)
    place(x, thump(120, 65, 0.1), 0, 0.5)
    return finish(x, peak=0.55, hi=7000, verb=0.05)


def jump(v):
    d = 0.22
    air = svf_sweep(noise(d), 500, 1800 + 200 * v, q=1.5) * env_ad(int(d * SR), 0.03, 0.14, 3)
    x = silence(d)
    place(x, air, 0, 1.0)
    place(x, footstep_grass(v)[: int(0.1 * SR)], 0, 0.5)
    return finish(x, peak=0.6, hi=8000, verb=0.05)


def land(v, heavy=False):
    d = 0.35 if heavy else 0.22
    x = silence(d)
    place(x, thump(110 if heavy else 150, 50, d, d * 0.7), 0, 1.0)
    dirt = fft_filter(noise(d), lo=600, hi=5000) * env_ad(int(d * SR), 0.002, 0.08 if not heavy else 0.16, 4)
    place(x, dirt, 0, 0.5 if not heavy else 0.8)
    if heavy:  # little pebble scatter
        for _ in range(5):
            place(x, modal([RNG.uniform(1800, 3200)], 0.05, [0.01]), RNG.uniform(0.04, 0.16), 0.15)
    return finish(x, peak=0.75 if heavy else 0.6, hi=6000, verb=0.08)


def roll(v):
    d = 0.5
    n = int(d * SR)
    rust = fft_filter(noise(d), lo=300, hi=2500)
    t = t_axis(d)
    wob = 0.55 + 0.45 * np.sin(2 * np.pi * (7 + v) * t) ** 2
    x = rust * wob * env_ad(n, 0.04, 0.35, 3)
    place(x, thump(130, 60, 0.12), 0.02, 0.6)
    place(x, thump(110, 55, 0.12), 0.3, 0.35)
    return finish(x, peak=0.55, hi=5000, verb=0.05)


def hop(v):
    d = 0.18
    air = svf_sweep(noise(d), 900, 2400, q=1.8) * env_ad(int(d * SR), 0.01, 0.12, 3)
    return finish(air, peak=0.5, hi=8000, verb=0.05)


def backflip(v):
    d = 0.45
    x = silence(d)
    place(x, svf_sweep(noise(0.2), 600, 2200, q=1.8) * env_ad(int(0.2 * SR), 0.01, 0.16, 3), 0, 1)
    place(x, svf_sweep(noise(0.22), 2000, 700, q=1.8) * env_ad(int(0.22 * SR), 0.03, 0.15, 3), 0.17, 0.8)
    return finish(x, peak=0.55, hi=8000, verb=0.05)


def ledge_grab(v):
    d = 0.2
    x = silence(d)
    slap = fft_filter(noise(0.02), lo=800, hi=6000) * env_ad(int(0.02 * SR), 0.0005, 0.015, 5)
    place(x, slap, 0, 1)
    place(x, thump(220, 120, 0.08), 0, 0.5)
    place(x, fft_filter(noise(0.12), lo=400, hi=2500) * env_ad(int(0.12 * SR), 0.01, 0.08), 0.03, 0.3)
    return finish(x, peak=0.6, hi=7000, verb=0.08)


def climb(v):
    d = 0.4
    n = int(d * SR)
    x = fft_filter(noise(d), lo=300, hi=3000) * env_ad(n, 0.05, 0.3, 3)
    place(x, ledge_grab(v)[: int(0.15 * SR)], 0, 0.5)
    place(x, thump(120, 60, 0.1), 0.28, 0.4)
    return finish(x, peak=0.5, hi=6000, verb=0.05)


def bonk(v):
    d = 0.9
    x = silence(d)
    place(x, thump(120, 55, 0.25), 0, 1.0)
    place(x, modal([210, 460, 900], 0.2, [0.05, 0.03, 0.015], [0.8, 0.5, 0.3]), 0, 0.6)
    # dizzy twinkle: two small falling chimes
    place(x, bell(hz("A6"), 0.3, 0.6, 0.25), 0.18, 0.18)
    place(x, bell(hz("E6"), 0.35, 0.6, 0.3), 0.3, 0.16)
    return finish(x, peak=0.7, hi=8000, verb=0.15)


def bow_draw(v):
    d = 0.55
    n = int(d * SR)
    t = t_axis(d)
    creak_rate = 35 + 25 * t / d               # friction stick-slip speeds up
    pulses = (np.sin(2 * np.pi * np.cumsum(creak_rate) / SR) > 0.92).astype(float)
    creak = svf_sweep(pulses + 0.15 * noise(d), 700, 1400, q=6)
    stretch = fft_filter(noise(d), lo=1500, hi=4000) * 0.15
    x = (creak + stretch) * env_ad(n, 0.08, 0.5, 1.5)
    return finish(x, peak=0.45, hi=6000, verb=0.05)


def bow_fire(v):
    d = 0.5
    x = silence(d)
    s = pluck(98 + 6 * v, 0.4, damp=0.985, bright=0.7)
    place(x, s * env_ad(len(s), 0.001, 0.25, 4), 0, 0.8)
    place(x, svf_sweep(noise(0.25), 2500, 800, q=1.5) * env_ad(int(0.25 * SR), 0.005, 0.2, 4), 0, 0.7)
    place(x, thump(200, 100, 0.06), 0, 0.3)
    return finish(x, peak=0.7, hi=9000, verb=0.08)


def arrow_hit(v):
    d = 0.4
    x = silence(d)
    place(x, modal([170, 360, 640], 0.12, [0.04, 0.02, 0.01], [1, 0.5, 0.3]), 0, 0.8)
    place(x, fft_filter(noise(0.02), lo=1200) * env_ad(int(0.02 * SR), 0.0005, 0.012), 0, 0.6)
    t = t_axis(0.35)
    quiver = np.sin(2 * np.pi * 310 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t)) * np.exp(-t / 0.09)
    place(x, quiver, 0.015, 0.35)
    return finish(x, peak=0.65, hi=8000, verb=0.1)


def target_hit(v):
    d = 0.35
    x = silence(d)
    place(x, thump(150, 70, 0.15), 0, 0.9)
    place(x, fft_filter(noise(0.2), lo=1000, hi=6000) * env_ad(int(0.2 * SR), 0.002, 0.09, 4), 0, 0.7)
    for _ in range(4):
        place(x, fft_filter(noise(0.01), lo=2500) * env_ad(int(0.01 * SR), 0.0005, 0.008),
              RNG.uniform(0.01, 0.08), 0.3)
    return finish(x, peak=0.65, hi=8000, verb=0.08)


def boomerang_throw(v):
    d = 0.3
    x = svf_sweep(noise(d), 700, 2600, q=2.5) * env_ad(int(d * SR), 0.02, 0.22, 3)
    return finish(x, peak=0.55, hi=9000, verb=0.05)


def boomerang_spin(v):
    """Seamless loop: whoosh pulses at an integer number per loop."""
    d = 0.5
    n = int(d * SR)
    t = np.arange(n) / SR
    pulses = 6                                   # 12 per second
    am = 0.15 + 0.85 * (0.5 + 0.5 * np.cos(2 * np.pi * pulses * t / d)) ** 3
    base = np.fft.irfft(np.fft.rfft(RNG.uniform(-1, 1, n)) *
                        np.exp(-((np.fft.rfftfreq(n, 1 / SR) - 1500) / 700) ** 2), n)  # periodic noise
    x = base * am
    x = x / np.max(np.abs(x)) * 0.5
    return x  # no finish(): keep it exactly loopable


def boomerang_catch(v):
    d = 0.2
    x = silence(d)
    place(x, modal([520, 1100, 1900], 0.15, [0.03, 0.015, 0.008], [1, 0.5, 0.3]), 0, 0.8)
    place(x, ledge_grab(v)[: int(0.06 * SR)], 0, 0.4)
    return finish(x, peak=0.55, hi=8000, verb=0.08)


def weapon_draw(v):
    d = 0.3
    x = silence(d)
    place(x, svf_sweep(noise(0.18), 1200, 3500, q=2) * env_ad(int(0.18 * SR), 0.03, 0.12, 3), 0, 0.7)
    place(x, modal([680, 1450], 0.1, [0.02, 0.01]), 0.15, 0.4)
    return finish(x, peak=0.5, hi=9000, verb=0.08)


def weapon_holster(v):
    d = 0.3
    x = silence(d)
    place(x, svf_sweep(noise(0.18), 3000, 1000, q=2) * env_ad(int(0.18 * SR), 0.03, 0.12, 3), 0, 0.7)
    place(x, thump(260, 140, 0.08), 0.15, 0.5)
    return finish(x, peak=0.45, hi=8000, verb=0.08)


def item_get():
    """Weapon pickup: rising pentatonic sparkle + held shimmer chord."""
    notes = ["D5", "F#5", "A5", "D6"]
    x = silence(1.3)
    for i, nm in enumerate(notes):
        place(x, bell(hz(nm), 0.6, 1.0, 0.5), i * 0.075, 0.5)
    for nm in ["A5", "D6", "F#6"]:
        place(x, bell(hz(nm), 1.0, 0.4, 0.9), 0.32, 0.28)
    for k in range(8):  # sparkles
        place(x, bell(hz("A6") * RNG.uniform(1.0, 1.6), 0.12, 0.3, 0.1), 0.35 + k * 0.06, 0.08)
    return finish(x, peak=0.75, hi=10000, verb=0.25, verb_len=1.0)


def item_ammo():
    x = silence(0.5)
    place(x, bell(hz("A5"), 0.3, 0.8, 0.25), 0, 0.6)
    place(x, bell(hz("E6"), 0.4, 0.8, 0.35), 0.07, 0.6)
    return finish(x, peak=0.65, hi=10000, verb=0.2, verb_len=0.8)


def item_pickup_far():
    x = bell(hz("E6"), 0.3, 0.5, 0.25)
    return finish(x, peak=0.5, hi=8000, verb=0.15)


def ui_hover(v):
    x = bell(hz(["G5", "A5"][v % 2]) , 0.12, 0.3, 0.07)
    place(x, modal([2600], 0.03, [0.005]), 0, 0.2)   # tiny wooden tick
    return finish(x, peak=0.35, hi=9000, verb=0.08, verb_len=0.3)


def ui_select():
    x = silence(0.4)
    place(x, bell(hz("D6"), 0.2, 0.8, 0.15), 0, 0.6)
    place(x, bell(hz("A6"), 0.3, 0.8, 0.25), 0.06, 0.6)
    return finish(x, peak=0.55, hi=10000, verb=0.15, verb_len=0.5)


def ui_back():
    x = silence(0.4)
    place(x, bell(hz("A5"), 0.2, 0.6, 0.15), 0, 0.6)
    place(x, bell(hz("D5"), 0.3, 0.6, 0.25), 0.07, 0.6)
    return finish(x, peak=0.5, hi=9000, verb=0.15, verb_len=0.5)


def ui_error():
    x = silence(0.3)
    for i in range(2):
        b = tone(hz("C3"), 0.09, "square") * env_ad(int(0.09 * SR), 0.002, 0.08, 2)
        place(x, fft_filter(b, hi=1500), i * 0.11, 0.5)
    return finish(x, peak=0.45, hi=4000, verb=0.05)


def ui_match_start():
    """Short adventure fanfare (original motif)."""
    x = silence(2.2)
    seq = [("G4", 0.0), ("C5", 0.12), ("D5", 0.24), ("G5", 0.36)]
    for nm, at in seq:
        b = tone(hz(nm), 0.3, "tri") * env_ad(int(0.3 * SR), 0.005, 0.25, 3)
        place(x, b, at, 0.35)
        place(x, bell(hz(nm) * 2, 0.4, 0.5, 0.3), at, 0.2)
    for nm in ["C5", "E5", "G5", "C6"]:  # resolving chord
        place(x, tone(hz(nm), 1.4, "tri") * env_ad(int(1.4 * SR), 0.02, 1.2, 3), 0.55, 0.18)
        place(x, bell(hz(nm) * 2, 1.4, 0.4, 1.2), 0.55, 0.12)
    return finish(x, peak=0.7, hi=9000, verb=0.3, verb_len=1.2)


def amb_field():
    """20 s seamless loop: soft wind + sparse original bird calls."""
    d = 20.0
    n = int(d * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(RNG.uniform(-1, 1, n))
    shape = 1 / np.sqrt(1 + (f / 500) ** 2) / np.sqrt(1 + (120 / np.maximum(f, 1)) ** 4)
    wind = np.fft.irfft(spec * shape, n)                    # circular = loops cleanly
    swell = 0.55 + 0.25 * np.sin(2 * np.pi * 1 * t / d) + 0.2 * np.sin(2 * np.pi * 3 * t / d + 1.3)
    x = wind / np.max(np.abs(wind)) * swell * 0.5
    # bird calls placed away from the loop seam
    for at in [1.6, 4.9, 6.1, 9.8, 13.2, 14.0, 17.1]:
        call = silence(0.6)
        base = RNG.uniform(2400, 3600)
        k = RNG.integers(2, 4)
        for j in range(k):
            dur = RNG.uniform(0.06, 0.12)
            sweep = RNG.uniform(-0.35, 0.45)
            fq = lambda tt, b=base, s=sweep, du=dur: b * (1 + s * tt / du)
            chirp = tone(fq, dur, fm_ratio=0.02, fm_index=0.5) * env_ad(int(dur * SR), 0.01, dur, 3)
            place(call, chirp, j * RNG.uniform(0.1, 0.16), 1.0)
        place(x, reverb(call, 0.3, 0.7)[: len(call) + int(0.5 * SR)], at, 0.12)
    x = fft_filter(x, hi=9000, order=1)
    return x / np.max(np.abs(x)) * 0.6


# ------------------------------------------------------------------ catalogue
# id: (folder, filename stem, generator, variants, settings)
# settings: bus, volume_db, pitch (min,max), max_distance, max_voices, loop, spatial
SFX = 1

# ---------------------------------------------------------------- world / elements
def wood_hit(v):
    d = 0.3
    x = silence(d)
    place(x, modal([210 + 15 * v, 470, 880], 0.2, [0.06, 0.03, 0.015], [1, 0.45, 0.2]), 0, 0.9)
    place(x, fft_filter(noise(0.03), lo=900, hi=5000) * env_ad(int(0.03 * SR), 0.0005, 0.02), 0, 0.5)
    return finish(x, peak=0.6, hi=7500, verb=0.08)


def wood_break(v):
    d = 0.8
    x = silence(d)
    place(x, thump(160, 60, 0.3), 0, 0.8)
    for i in range(9):
        at = RNG.uniform(0.0, 0.35)
        place(x, modal([RNG.uniform(250, 600), RNG.uniform(700, 1300)], 0.12, [0.03, 0.015]), at, RNG.uniform(0.3, 0.6))
    place(x, fft_filter(noise(0.5), lo=500, hi=4000) * env_ad(int(0.5 * SR), 0.003, 0.25, 3), 0, 0.5)
    return finish(x, peak=0.75, hi=8000, verb=0.14)


def ice_hit(v):
    d = 0.5
    x = silence(d)
    place(x, bell(hz("E6") * (1 + 0.04 * v), 0.4, bright=1.4, decay=0.12), 0, 0.5)
    place(x, fft_filter(noise(0.02), lo=3000) * env_ad(int(0.02 * SR), 0.0003, 0.01), 0, 0.6)
    return finish(x, peak=0.55, hi=11000, verb=0.15)


def ice_shatter(v):
    d = 1.1
    x = silence(d)
    place(x, fft_filter(noise(0.6), lo=2500) * env_ad(int(0.6 * SR), 0.001, 0.25, 4), 0, 0.7)
    for i in range(14):
        at = RNG.uniform(0.0, 0.5)
        place(x, bell(RNG.uniform(1800, 4200), 0.35, bright=1.6, decay=0.08), at, RNG.uniform(0.15, 0.35))
    place(x, thump(220, 120, 0.15), 0, 0.4)
    return finish(x, peak=0.75, hi=12000, verb=0.2, verb_len=0.7)


def fire_ignite(v):
    d = 0.7
    x = svf_sweep(noise(d), 300, 1600, q=1.5) * env_ad(int(d * SR), 0.06, 0.5, 3)
    place(x, thump(110, 60, 0.3), 0, 0.4)
    return finish(x, peak=0.6, hi=7000, verb=0.1)


def fire_loop(v):
    """4 s seamless crackle loop."""
    d = 4.0
    n = int(d * SR)
    base = fft_filter(noise(d), lo=150, hi=1200) * 0.18
    x = base.copy()
    for i in range(70):
        at = RNG.uniform(0, d - 0.03)
        pop = fft_filter(noise(0.012), lo=1500, hi=7000) * env_ad(int(0.012 * SR), 0.0003, 0.008)
        place(x, pop, at, RNG.uniform(0.15, 0.6))
    fade = int(0.25 * SR)
    ramp = np.linspace(0, 1, fade)
    x[:fade] = x[:fade] * ramp + x[n - fade:] * (1 - ramp)
    x = x[:n - fade]
    return finish(x, peak=0.5, hi=8000, verb=0.0, tail_fade=0.0)


def fire_extinguish(v):
    d = 0.9
    x = fft_filter(noise(d), lo=2500, hi=9000) * env_ad(int(d * SR), 0.02, 0.6, 2)
    return finish(x, peak=0.5, hi=10000, verb=0.08)



# ---------------------------------------------------------------- sword & shield
def sword_swing(v):
    d = 0.32
    x = svf_sweep(noise(d), 600 + 150 * v, 3200, q=3.0) * env_ad(int(d * SR), 0.03, 0.22, 3)
    return finish(x, peak=0.55, hi=10000, verb=0.04)


def sword_hit(v):
    d = 0.45
    x = silence(d)
    place(x, fft_filter(noise(0.05), lo=2000, hi=9000) * env_ad(int(0.05 * SR), 0.0005, 0.03), 0, 0.7)
    place(x, thump(180, 90, 0.12), 0, 0.6)
    place(x, bell(hz("A5") * (1 + 0.05 * v), 0.3, bright=0.6, decay=0.07), 0.005, 0.18)
    return finish(x, peak=0.7, hi=9500, verb=0.08)


def sword_spin(v):
    d = 0.8
    x = silence(d)
    for k in range(3):
        seg = svf_sweep(noise(0.3), 500, 3500, q=3.0) * env_ad(int(0.3 * SR), 0.04, 0.2, 3)
        place(x, seg, k * 0.18, 0.8 - 0.15 * k)
    place(x, bell(hz("E6"), 0.6, bright=1.2, decay=0.2), 0.0, 0.25)
    return finish(x, peak=0.7, hi=11000, verb=0.12)


def sword_charge(v):
    d = 0.8
    t = t_axis(d)
    f = 400 + 900 * t / d
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25 * env_ad(int(d * SR), 0.2, 0.7, 1.5)
    x += fft_filter(noise(d), lo=3000) * 0.08 * (t / d)
    return finish(x, peak=0.45, hi=10000, verb=0.1)


def sword_charged(v):
    d = 0.6
    x = silence(d)
    place(x, bell(hz("B6"), 0.55, bright=1.5, decay=0.18), 0, 0.5)
    place(x, bell(hz("E7"), 0.45, bright=1.5, decay=0.14), 0.05, 0.35)
    return finish(x, peak=0.5, hi=12000, verb=0.2)


def shield_block(v):
    d = 0.5
    x = silence(d)
    place(x, modal([520 + 30 * v, 1180, 2050, 3100], 0.45, [0.12, 0.08, 0.05, 0.03], [1, 0.6, 0.4, 0.25]), 0, 0.7)
    place(x, fft_filter(noise(0.03), lo=1500) * env_ad(int(0.03 * SR), 0.0005, 0.02), 0, 0.6)
    return finish(x, peak=0.7, hi=11000, verb=0.12)


def shield_bash(v):
    d = 0.35
    x = silence(d)
    place(x, thump(140, 60, 0.2), 0, 0.9)
    place(x, modal([300, 690], 0.2, [0.05, 0.03]), 0, 0.4)
    return finish(x, peak=0.65, hi=7000, verb=0.06)


CATALOGUE = [
    ("player.footstep.grass", "player", "step_grass", footstep_grass, 4, dict(volume_db=-6, pitch=(0.9, 1.1), max_distance=30, max_voices=6)),
    ("player.footstep.stone", "player", "step_stone", footstep_stone, 4, dict(volume_db=-6, pitch=(0.92, 1.08), max_distance=30, max_voices=6)),
    ("player.footstep.wood", "player", "step_wood", footstep_wood, 4, dict(volume_db=-5, pitch=(0.92, 1.08), max_distance=30, max_voices=6)),
    ("player.footstep.straw", "player", "step_straw", footstep_straw, 3, dict(volume_db=-6, pitch=(0.9, 1.1), max_distance=30, max_voices=6)),
    ("player.jump", "player", "jump", jump, 2, dict(volume_db=-6, pitch=(0.95, 1.08), max_distance=35)),
    ("player.land", "player", "land", land, 2, dict(volume_db=-4, pitch=(0.92, 1.05), max_distance=35)),
    ("player.land_heavy", "player", "land_heavy", lambda v: land(v, True), 2, dict(volume_db=-1, pitch=(0.92, 1.03), max_distance=50)),
    ("player.roll", "player", "roll", roll, 2, dict(volume_db=-4, pitch=(0.93, 1.07), max_distance=35)),
    ("player.sidehop", "player", "sidehop", hop, 2, dict(volume_db=-5, pitch=(0.95, 1.1), max_distance=30)),
    ("player.backflip", "player", "backflip", backflip, 1, dict(volume_db=-4, pitch=(0.95, 1.05), max_distance=30)),
    ("player.ledge_grab", "player", "ledge_grab", ledge_grab, 2, dict(volume_db=-4, pitch=(0.93, 1.07), max_distance=30)),
    ("player.climb", "player", "climb", climb, 2, dict(volume_db=-5, pitch=(0.93, 1.07), max_distance=30)),
    ("player.bonk", "player", "bonk", bonk, 1, dict(volume_db=-2, pitch=(0.97, 1.03), max_distance=40)),
    ("weapon.draw", "weapons", "draw", weapon_draw, 2, dict(volume_db=-6, pitch=(0.95, 1.05), max_distance=25)),
    ("weapon.holster", "weapons", "holster", weapon_holster, 2, dict(volume_db=-7, pitch=(0.95, 1.05), max_distance=25)),
    ("bow.draw", "weapons", "bow_draw", bow_draw, 2, dict(volume_db=-5, pitch=(0.96, 1.04), max_distance=30)),
    ("bow.fire", "weapons", "bow_fire", bow_fire, 3, dict(volume_db=-2, pitch=(0.95, 1.05), max_distance=60, max_voices=6)),
    ("arrow.hit", "weapons", "arrow_hit", arrow_hit, 3, dict(volume_db=-3, pitch=(0.92, 1.08), max_distance=50, max_voices=8)),
    ("boomerang.throw", "weapons", "boomerang_throw", boomerang_throw, 2, dict(volume_db=-4, pitch=(0.95, 1.05), max_distance=40)),
    ("boomerang.spin", "weapons", "boomerang_spin", boomerang_spin, 1, dict(volume_db=-8, pitch=(1.0, 1.0), max_distance=35, loop=True)),
    ("boomerang.catch", "weapons", "boomerang_catch", boomerang_catch, 1, dict(volume_db=-4, pitch=(0.96, 1.04), max_distance=30)),
    ("target.hit", "world", "target_hit", target_hit, 3, dict(volume_db=-2, pitch=(0.9, 1.1), max_distance=50, max_voices=8)),
    ("item.get", "items", "item_get", lambda v: item_get(), 1, dict(bus="UI", volume_db=-4, spatial=False)),
    ("item.ammo", "items", "item_ammo", lambda v: item_ammo(), 1, dict(bus="UI", volume_db=-5, spatial=False)),
    ("item.pickup_far", "items", "item_pickup_far", lambda v: item_pickup_far(), 1, dict(volume_db=-8, max_distance=25)),
    ("ui.hover", "ui", "hover", ui_hover, 2, dict(bus="UI", volume_db=-10, pitch=(0.99, 1.01), spatial=False, max_voices=2)),
    ("ui.select", "ui", "select", lambda v: ui_select(), 1, dict(bus="UI", volume_db=-6, spatial=False)),
    ("ui.back", "ui", "back", lambda v: ui_back(), 1, dict(bus="UI", volume_db=-6, spatial=False)),
    ("ui.error", "ui", "error", lambda v: ui_error(), 1, dict(bus="UI", volume_db=-8, spatial=False)),
    ("ui.match_start", "ui", "match_start", lambda v: ui_match_start(), 1, dict(bus="UI", volume_db=-5, spatial=False)),
    ("amb.field", "ambience", "field_loop", lambda v: amb_field(), 1, dict(bus="Ambience", volume_db=-10, spatial=False, loop=True)),
    # world / elements (keep new sounds at the end so the shared RNG leaves older sounds unchanged)
    ("wood.hit", "world", "wood_hit", wood_hit, 2, dict(volume_db=-3, pitch=(0.92, 1.08), max_distance=45, max_voices=6)),
    ("wood.break", "world", "wood_break", wood_break, 1, dict(volume_db=-1, pitch=(0.92, 1.05), max_distance=60)),
    ("ice.hit", "world", "ice_hit", ice_hit, 2, dict(volume_db=-4, pitch=(0.95, 1.05), max_distance=45, max_voices=6)),
    ("ice.shatter", "world", "ice_shatter", ice_shatter, 1, dict(volume_db=-1, pitch=(0.95, 1.05), max_distance=60)),
    ("fire.ignite", "world", "fire_ignite", fire_ignite, 1, dict(volume_db=-3, pitch=(0.9, 1.1), max_distance=40, max_voices=6)),
    ("fire.loop", "world", "fire_loop", fire_loop, 1, dict(volume_db=-9, pitch=(1.0, 1.0), max_distance=20, max_voices=8, loop=True)),
    ("fire.extinguish", "world", "fire_extinguish", fire_extinguish, 1, dict(volume_db=-4, pitch=(0.95, 1.05), max_distance=35)),
    ("sword.swing", "weapons", "sword_swing", sword_swing, 3, dict(volume_db=-4, pitch=(0.94, 1.06), max_distance=35, max_voices=6)),
    ("sword.hit", "weapons", "sword_hit", sword_hit, 2, dict(volume_db=-2, pitch=(0.93, 1.07), max_distance=45, max_voices=8)),
    ("sword.spin", "weapons", "sword_spin", sword_spin, 1, dict(volume_db=-2, pitch=(0.97, 1.03), max_distance=45)),
    ("sword.charge", "weapons", "sword_charge", sword_charge, 1, dict(volume_db=-6, pitch=(1.0, 1.0), max_distance=25)),
    ("sword.charged", "weapons", "sword_charged", sword_charged, 1, dict(volume_db=-5, pitch=(1.0, 1.0), max_distance=25)),
    ("shield.block", "weapons", "shield_block", shield_block, 2, dict(volume_db=-2, pitch=(0.95, 1.05), max_distance=45, max_voices=6)),
    ("shield.bash", "weapons", "shield_bash", shield_bash, 1, dict(volume_db=-3, pitch=(0.95, 1.05), max_distance=35)),
]


def tres_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return f"{v}.0"
    return f'&"{v}"'


def main(root):
    ext, subs, entries = [], [], []
    ext.append('[ext_resource type="Script" path="res://data/registry/sound_registry.gd" id="1_reg"]')
    ext.append('[ext_resource type="Script" path="res://data/audio/sound_def.gd" id="2_def"]')
    eid = 3
    for si, (sid, folder, stem, gen, variants, s) in enumerate(CATALOGUE):
        refs = []
        for v in range(variants):
            fname = f"{stem}_{v + 1}.wav" if variants > 1 else f"{stem}.wav"
            rel = f"assets/audio/sfx/{folder}/{fname}"
            write_wav(os.path.join(root, rel), gen(v))
            ext.append(f'[ext_resource type="AudioStream" path="res://{rel}" id="{eid}_snd"]')
            refs.append(f'ExtResource("{eid}_snd")')
            eid += 1
        lines = [f'[sub_resource type="Resource" id="sd_{si}"]', 'script = ExtResource("2_def")',
                 f'streams = Array[AudioStream]([{", ".join(refs)}])']
        pitch = s.get("pitch", (0.95, 1.05))
        lines.append(f'volume_db = {float(s.get("volume_db", 0))}')
        lines.append(f'pitch_min = {float(pitch[0])}')
        lines.append(f'pitch_max = {float(pitch[1])}')
        lines.append(f'bus = &"{s.get("bus", "SFX")}"')
        lines.append(f'spatial = {tres_value(s.get("spatial", True))}')
        lines.append(f'max_distance = {float(s.get("max_distance", 40))}')
        lines.append(f'max_voices = {int(s.get("max_voices", 4))}')
        lines.append(f'loop = {tres_value(s.get("loop", False))}')
        subs.append("\n".join(lines))
        entries.append(f'"{sid}": SubResource("sd_{si}")')
        print(f"  {sid:26s} {variants} file(s)")
    out = [f'[gd_resource type="Resource" load_steps={len(ext) + len(subs) + 1} format=3]', ""]
    out += ext + [""]
    for s in subs:
        out += [s, ""]
    out += ["[resource]", 'script = ExtResource("1_reg")',
            "sounds = Dictionary[String, Resource]({\n" + ",\n".join(entries) + "\n})", ""]
    with open(os.path.join(root, "data/registry/sounds.tres"), "w", newline="\n") as f:
        f.write("\n".join(out))
    print("wrote data/registry/sounds.tres")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
