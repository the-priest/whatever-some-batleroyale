#!/usr/bin/env python3
"""Original heavy metal soundtrack for Block Royale, synthesized from scratch.

Everything here is generated: no samples, no third-party recordings, so the
tracks belong to the project. Run:  python3 tools/metal_synth.py
Writes assets/music/*.ogg (needs numpy, scipy and ffmpeg with libvorbis).
"""
import os
import subprocess
import sys

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


# ----------------------------------------------------------------- filters --

def biquad(kind, f, q=0.707, gain_db=0.0):
    w = 2 * np.pi * f / SR
    a = np.sin(w) / (2 * q)
    c = np.cos(w)
    A = 10 ** (gain_db / 40)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        aa = [1 + a, -2 * c, 1 - a]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        aa = [1 + a, -2 * c, 1 - a]
    elif kind == "bp":
        b = [a, 0, -a]
        aa = [1 + a, -2 * c, 1 - a]
    elif kind == "peak":
        b = [1 + a * A, -2 * c, 1 - a * A]
        aa = [1 + a / A, -2 * c, 1 - a / A]
    else:
        raise ValueError(kind)
    return np.array(b) / aa[0], np.array(aa) / aa[0]


def filt(x, kind, f, q=0.707, gain_db=0.0):
    b, a = biquad(kind, f, q, gain_db)
    return signal.lfilter(b, a, x)


def saw(freq, n, phase=0.0):
    """Band-limited-ish sawtooth via 2x oversampling and decimation."""
    t = (np.arange(n * 2) / (SR * 2)) * freq + phase
    s = 2.0 * (t - np.floor(t + 0.5))
    return signal.resample_poly(s, 1, 2)


def square(freq, n, phase=0.0):
    t = (np.arange(n * 2) / (SR * 2)) * freq + phase
    s = np.sign(np.sin(2 * np.pi * t))
    return signal.resample_poly(s, 1, 2)


# ------------------------------------------------------------------ guitar --

def amp_sim(x, gain=18.0, tight=True):
    """Distortion and speaker-cabinet response of a high-gain amp."""
    if tight:
        x = filt(x, "hp", 140)  # tighten the low end before the gain
    x = filt(x, "peak", 900, 0.8, 6.0)
    y = np.tanh(x * gain + 0.15) - np.tanh(0.15)
    y = np.tanh(y * 2.2)
    # 4x12 cab: low thump, scooped mids, presence, then the speaker roll-off.
    y = filt(y, "hp", 75)
    y = filt(y, "peak", 110, 1.0, 3.0)
    y = filt(y, "peak", 650, 0.9, -4.5)
    y = filt(y, "peak", 2600, 1.2, 3.5)
    y = filt(y, "lp", 5200, 0.8)
    y = filt(y, "lp", 6500, 0.6)
    return y


def chord_dry(root, n, kind, detune, rng):
    """Raw (pre-amp) power chord or single note signal."""
    f = midi(root) * (1 + detune)
    ph = rng.random()
    if kind == "n":  # single note
        x = saw(f, n, ph) + 0.4 * saw(f * 2.002, n, ph)
    else:
        x = saw(f, n, ph) + 0.85 * saw(f * 1.4983, n, rng.random()) + 0.55 * saw(f * 2.0, n, rng.random())
    t = np.arange(n) / SR
    if kind == "m":  # palm mute: fast decay, darker
        env = np.exp(-t * 30.0) * 0.8 + 0.06
        x = filt(x, "lp", 900, 0.7)
    else:
        env = np.minimum(1.0, t / 0.004) * (0.85 + 0.15 * np.exp(-t * 6.0))
    rel = min(n, int(0.012 * SR))
    env[-rel:] *= np.linspace(1, 0, rel)
    return x * env


def render_guitar(events, total, detune, timing_jitter, seed, gain=18.0):
    rng = np.random.default_rng(seed)
    dry = np.zeros(total)
    for (start, length, root, kind) in events:
        s = int(start * SR + rng.normal(0, timing_jitter) * SR)
        s = max(0, s)
        n = int(length * SR)
        if s + n > total or n < 8:
            continue
        dry[s:s + n] += chord_dry(root, n, kind, detune, rng)
    return amp_sim(dry * 0.6, gain)


def render_bass(events, total):
    out = np.zeros(total)
    for (start, length, root, kind) in events:
        s = int(start * SR)
        n = int(length * SR)
        if s + n > total or n < 8:
            continue
        f = midi(root - 12)
        t = np.arange(n) / SR
        x = np.sin(2 * np.pi * f * t) + 0.45 * saw(f, n) * 0.6
        env = np.minimum(1, t / 0.003) * (np.exp(-t * 9.0) * 0.5 + 0.5 if kind == "m" else 1.0)
        rel = min(n, int(0.01 * SR))
        env[-rel:] *= np.linspace(1, 0, rel)
        out[s:s + n] += x * env
    out = np.tanh(out * 1.6)
    out = filt(out, "lp", 1400)
    out = filt(out, "hp", 38)
    return out * 0.45


def render_lead(notes, total, seed):
    """Screaming lead: detuned saws, vibrato, high gain, stereo delay."""
    rng = np.random.default_rng(seed)
    dry = np.zeros(total)
    for (start, length, note) in notes:
        s = int(start * SR)
        n = int(length * SR)
        if s + n > total or n < 8:
            continue
        t = np.arange(n) / SR
        f = midi(note)
        vib = 1 + 0.009 * np.sin(2 * np.pi * 5.6 * t) * np.minimum(1, t / 0.25)
        # Slight scoop into the note, like a bend.
        bend = 1 - 0.03 * np.exp(-t * 28)
        ph = np.cumsum(f * vib * bend) / SR
        x = 2.0 * (ph - np.floor(ph + 0.5)) + 0.5 * np.sign(np.sin(2 * np.pi * ph * 1.003))
        env = np.minimum(1, t / 0.006) * (0.75 + 0.25 * np.exp(-t * 3))
        rel = min(n, int(0.03 * SR))
        env[-rel:] *= np.linspace(1, 0, rel)
        dry[s:s + n] += x * env
    wet = amp_sim(dry * 0.5, 30.0, tight=False)
    wet = filt(wet, "peak", 1800, 1.0, 3.0)
    return wet * 0.5


def delay(x, seconds, fb=0.32, mix=0.28):
    d = int(seconds * SR)
    y = x.copy()
    for k in range(1, 4):
        if d * k < len(x):
            y[d * k:] += x[:-d * k] * (fb ** k) * mix / fb
    return y


# ------------------------------------------------------------------- drums --

def kick():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 52 + 140 * np.exp(-t * 38)
    ph = np.cumsum(f) / SR
    body = np.sin(2 * np.pi * ph) * np.exp(-t * 9)
    click = np.random.default_rng(1).normal(0, 1, n) * np.exp(-t * 420) * 0.6
    click = filt(click, "hp", 2500)
    return np.tanh((body + click) * 1.8) * 0.95


def snare():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 26) + 0.5 * np.sin(2 * np.pi * 330 * t) * np.exp(-t * 34)
    nz = np.random.default_rng(2).normal(0, 1, n)
    nz = filt(nz, "bp", 3800, 0.6) * np.exp(-t * 15) * 1.6 + filt(nz, "hp", 6000) * np.exp(-t * 22) * 0.8
    return np.tanh((tone * 0.9 + nz * 0.8) * 1.4) * 0.85


def hat(open_=False):
    n = int((0.32 if open_ else 0.07) * SR)
    t = np.arange(n) / SR
    nz = np.random.default_rng(3).normal(0, 1, n)
    x = filt(filt(nz, "hp", 7500), "peak", 10000, 1.5, 5)
    return x * np.exp(-t * (9 if open_ else 60)) * 0.32


def crash():
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    nz = np.random.default_rng(4).normal(0, 1, n)
    x = filt(nz, "hp", 4200) + 0.5 * filt(nz, "bp", 6500, 0.7)
    return x * np.exp(-t * 1.9) * np.minimum(1, t / 0.002) * 0.36


def tom(f):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    fr = f * (1 + 0.6 * np.exp(-t * 30))
    ph = np.cumsum(fr) / SR
    return np.tanh(np.sin(2 * np.pi * ph) * np.exp(-t * 7) * 1.5) * 0.7


DRUMS = {}


def drum(name):
    if not DRUMS:
        DRUMS.update({"k": kick(), "s": snare(), "h": hat(), "o": hat(True), "c": crash(),
                      "t1": tom(190), "t2": tom(140), "t3": tom(100)})
    return DRUMS[name]


def place(buf, sample, at, gain=1.0):
    s = int(at * SR)
    if s >= len(buf):
        return
    e = min(len(buf), s + len(sample))
    buf[s:e] += sample[:e - s] * gain


# ------------------------------------------------------------ arrangement --

class Song:
    def __init__(self, bpm, seed):
        self.bpm = bpm
        self.step = 60.0 / bpm / 4.0  # 16th note
        self.t = 0.0
        self.gtr = []
        self.lead = []
        self.drums = []
        self.rng = np.random.default_rng(seed)
        self.seed = seed

    def bar(self, riff, beat, fill=False, crash_on_one=False, lead=None):
        """riff: list of (step, len_steps, midi, kind) for one bar of 16 steps.
        beat: drum pattern name."""
        st = self.step
        for (s, ln, note, kind) in riff:
            self.gtr.append((self.t + s * st, ln * st * 0.97, note, kind))
        pat = BEATS[beat]
        for i in range(16):
            for k, line in pat.items():
                if line[i] != ".":
                    vel = 1.0 if line[i].isupper() or line[i] == "x" else 0.6
                    self.drums.append((self.t + i * st, k, vel * (0.9 + 0.1 * self.rng.random())))
        if crash_on_one:
            self.drums.append((self.t, "c", 1.0))
        if fill:
            for i, k in zip(range(8, 16), ["t1", "t1", "t2", "t2", "t3", "t3", "s", "s"]):
                self.drums.append((self.t + i * st, k, 0.9))
        if lead:
            for (s, ln, note) in lead:
                self.lead.append((self.t + s * st, ln * st, note))
        self.t += 16 * st

    def render(self):
        total = int((self.t + 3.0) * SR)
        gl = render_guitar(self.gtr, total, -0.0025, 0.004, self.seed + 1)
        gr = render_guitar(self.gtr, total, 0.0028, 0.004, self.seed + 2)
        bass = render_bass(self.gtr, total)
        ld = render_lead(self.lead, total, self.seed + 3) if self.lead else np.zeros(total)
        dl = delay(ld, self.step * 3, 0.35, 0.35)
        dr = delay(ld, self.step * 4, 0.35, 0.3)
        kit = np.zeros(total)
        overhead = np.zeros(total)
        for (at, k, vel) in self.drums:
            smp = drum(k)
            if k in ("h", "o", "c"):
                place(overhead, smp, at, vel)
            else:
                place(kit, smp, at, vel)
        # Room: a short, dense reverb tail on the snare and toms.
        room = signal.fftconvolve(kit, _room_ir(), mode="full")[:total] * 0.12
        drums_bus = kit + room + overhead
        overhead *= 0.75
        drums_bus = kit + room + overhead
        left = gl * 0.48 + gr * 0.12 + bass + drums_bus * 0.62 + ld * 0.36 + dl * 0.22
        right = gr * 0.48 + gl * 0.12 + bass + drums_bus * 0.62 + ld * 0.36 + dr * 0.22
        # Pan the hats a little right, toms across.
        right += overhead * 0.08
        mix = np.stack([left, right], axis=1)
        mix = filt(filt(mix.T, "hp", 42).T.T, "hp", 42).T
        # A touch more bite in the upper mids where guitars and snare live.
        mix = filt(mix.T, "peak", 2200, 0.9, 2.5).T
        mix = filt(mix.T, "peak", 60, 1.0, -3.0).T
        # Bus compression (soft knee) and a limiter.
        peak = np.max(np.abs(mix))
        mix /= peak
        mix = np.tanh(mix * 1.6) / np.tanh(1.6)
        mix *= 0.93 / np.max(np.abs(mix))
        # Fade in/out.
        fi = int(0.05 * SR)
        mix[:fi] *= np.linspace(0, 1, fi)[:, None]
        fo = int(2.5 * SR)
        mix[-fo:] *= np.linspace(1, 0, fo)[:, None]
        return mix


_IR = None


def _room_ir():
    global _IR
    if _IR is None:
        n = int(0.6 * SR)
        t = np.arange(n) / SR
        nz = np.random.default_rng(9).normal(0, 1, n)
        _IR = filt(nz, "lp", 5000) * np.exp(-t * 9.0) * 0.5
    return _IR


BEATS = {
    # k = kick, s = snare, h = closed hat, o = open hat / ride
    "rock": {"k": "x.....x.x.......", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
    "drive": {"k": "x.x.x.x.x.x.x.x.", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
    "double": {"k": "xxxxxxxxxxxxxxxx", "s": "....x.......x...", "o": "x...x...x...x..."},
    "blast": {"k": "x.x.x.x.x.x.x.x.", "s": ".x.x.x.x.x.x.x.x", "o": "x.x.x.x.x.x.x.x."},
    "half": {"k": "x.....x...x.....", "s": "........x.......", "o": "x...x...x...x..."},
    "gallop": {"k": "x..xx..xx..xx..x", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
    "intro": {"k": "x...............", "s": "................", "o": "x.......x......."},
}


def chug(root, pattern, accents):
    """16-step riff: 'm' palm-mutes on the root in `pattern`, open chords from accents."""
    out = []
    i = 0
    while i < 16:
        c = pattern[i]
        if c == "m":
            out.append((i, 1, root, "m"))
            i += 1
        elif c in accents:
            note, ln = accents[c]
            out.append((i, ln, note, "o"))
            i += ln
        else:
            i += 1
    return out


def scale_run(start_step, notes, step_len=1):
    return [(start_step + i * step_len, step_len, n) for i, n in enumerate(notes)]


# --------------------------------------------------------------- the songs --

def song_iron_tide():
    """Fast thrash in E: galloping verse, big open chorus, shred solo."""
    E = 40  # low E (E2)
    s = Song(176, 11)
    riff_a = chug(E, "mmm.A...mmm.B...", {"A": (E + 3, 4), "B": (E + 5, 4)})
    riff_b = chug(E, "m.mmm.mmC...D...", {"C": (E + 7, 4), "D": (E + 6, 4)})
    chorus = [(0, 8, E, "o"), (8, 8, E + 8, "o")]
    chorus2 = [(0, 8, E + 5, "o"), (8, 4, E + 3, "o"), (12, 4, E + 2, "o")]
    intro_r = [(0, 16, E, "o")]
    for i in range(2):
        s.bar(intro_r, "intro", crash_on_one=True)
    for rep in range(3):
        for i in range(4):
            s.bar(riff_a, "gallop", crash_on_one=(i == 0))
            s.bar(riff_b, "gallop", fill=(i == 3))
        for i in range(4):
            s.bar(chorus, "drive", crash_on_one=True)
            s.bar(chorus2, "drive", fill=(i == 3))
    # Solo over the chorus progression.
    pent = [52, 55, 57, 59, 62, 64, 67, 69, 71, 74, 76]
    solo = []
    for i in range(8):
        r = np.random.default_rng(100 + i)
        line = [int(pent[min(len(pent) - 1, max(0, 4 + int(r.integers(-3, 5))))]) for _ in range(16)]
        if i % 2 == 1:
            line[-4:] = [76, 76, 76, 76]
        solo.append(scale_run(0, line))
    for i in range(8):
        s.bar(chorus if i % 2 == 0 else chorus2, "double", crash_on_one=(i % 2 == 0), lead=solo[i])
    for i in range(4):
        s.bar(riff_a, "gallop", crash_on_one=(i == 0))
        s.bar(riff_b, "gallop", fill=(i == 3))
    s.bar([(0, 16, E, "o")], "intro", crash_on_one=True)
    return s


def song_stormkeep():
    """Mid-tempo crusher in drop D: heavy groove, half-time breakdown."""
    D = 38
    s = Song(132, 22)
    groove = chug(D, "mm.mm.A.mm.mB...", {"A": (D + 3, 2), "B": (D + 1, 4)})
    groove2 = chug(D, "mm.mm.A.mm.mC...", {"A": (D + 3, 2), "C": (D + 6, 4)})
    big = [(0, 6, D, "o"), (6, 2, D + 3, "o"), (8, 6, D + 5, "o"), (14, 2, D + 6, "o")]
    big2 = [(0, 6, D + 7, "o"), (6, 2, D + 6, "o"), (8, 8, D + 5, "o")]
    breakdown = chug(D, "m..m..m.m..m.m..", {})
    melody = [(0, 4, 62), (4, 4, 65), (8, 6, 69), (14, 2, 67)]
    melody2 = [(0, 4, 65), (4, 4, 64), (8, 8, 62)]
    s.bar([(0, 16, D, "o")], "intro", crash_on_one=True)
    s.bar([(0, 16, D + 1, "o")], "intro", crash_on_one=True)
    for rep in range(2):
        for i in range(4):
            s.bar(groove, "rock", crash_on_one=(i == 0))
            s.bar(groove2, "rock", fill=(i == 3))
        for i in range(4):
            s.bar(big, "drive", crash_on_one=True, lead=melody)
            s.bar(big2, "drive", fill=(i == 3), lead=melody2)
    for i in range(8):
        s.bar(breakdown, "half", crash_on_one=(i % 2 == 0))
    for i in range(4):
        s.bar(big, "double", crash_on_one=True, lead=melody)
        s.bar(big2, "double", lead=melody2)
    s.bar([(0, 16, D, "o")], "intro", crash_on_one=True)
    return s


def song_skyreach():
    """Epic power metal in C#: double-kick drive, soaring harmonised lead."""
    Cs = 37 + 12  # C#3
    s = Song(160, 33)
    prog = [Cs, Cs - 4, Cs - 2, Cs - 5]  # i - VI - VII - V (ish)
    drive = lambda r: [(i, 1, r, "m" if i % 4 else "o") for i in range(16)]
    hook = [[(0, 4, 68), (4, 4, 71), (8, 4, 73), (12, 4, 76)],
            [(0, 6, 75), (6, 2, 73), (8, 8, 71)],
            [(0, 4, 73), (4, 4, 71), (8, 4, 69), (12, 4, 68)],
            [(0, 12, 68), (12, 4, 66)]]
    for r in prog:
        s.bar([(0, 16, r, "o")], "intro", crash_on_one=True)
    for rep in range(4):
        for i, r in enumerate(prog):
            s.bar(drive(r), "double", crash_on_one=(i == 0))
        for i, r in enumerate(prog):
            s.bar([(0, 8, r, "o"), (8, 8, r, "o")], "double", crash_on_one=True, lead=hook[i])
        for i, r in enumerate(prog):
            s.bar(drive(r), "blast" if rep == 2 else "drive", crash_on_one=(i == 0), fill=(i == 3))
    for i, r in enumerate(prog):
        s.bar([(0, 8, r, "o"), (8, 8, r, "o")], "double", crash_on_one=True, lead=hook[i])
    s.bar([(0, 16, Cs, "o")], "intro", crash_on_one=True)
    return s


def song_highfalls():
    """Dark, heavy and slow-building in B: doom intro into a thrash finale."""
    B = 35 + 12  # B2
    s = Song(100, 44)
    doom = [(0, 8, B, "o"), (8, 4, B + 1, "o"), (12, 4, B - 2, "o")]
    doom2 = [(0, 8, B + 3, "o"), (8, 8, B + 1, "o")]
    for i in range(4):
        s.bar(doom, "half", crash_on_one=True)
        s.bar(doom2, "half")
    # Double time.
    fast = Song(184, 45)
    fast.t = s.t
    fast.gtr, fast.lead, fast.drums = s.gtr, s.lead, s.drums
    tremolo = lambda r: [(i, 1, r, "n") for i in range(16)]
    riff = chug(B, "mmmm.A..mmmm.C..", {"A": (B + 1, 3), "C": (B + 3, 3)})
    for rep in range(4):
        for i in range(4):
            fast.bar(riff, "drive", crash_on_one=(i == 0))
            fast.bar(tremolo(B + 7 + (i % 2)), "blast", fill=(i == 3))
    lead = [[(0, 4, 71), (4, 4, 74), (8, 8, 78)], [(0, 4, 76), (4, 4, 74), (8, 8, 71)]]
    for i in range(8):
        fast.bar(doom if i % 2 == 0 else doom2, "double", crash_on_one=(i % 2 == 0), lead=lead[i % 2])
    fast.bar([(0, 16, B, "o")], "intro", crash_on_one=True)
    return fast


def song_graveblade():
    """Relentless: blast beats, tremolo picking, a crushing half-time drop."""
    B = 35 + 12
    s = Song(196, 55)
    trem = lambda r: [(i, 1, r, "n") for i in range(16)]
    prog = [B, B + 1, B - 2, B + 3]
    chugs = chug(B, "mmmmmmmmA...C...", {"A": (B + 6, 4), "C": (B + 5, 4)})
    drop = chug(B - 2, "m...m..m..m.m...", {})
    for r in [B, B + 1]:
        s.bar([(0, 16, r, "o")], "intro", crash_on_one=True)
    for rep in range(3):
        for i, r in enumerate(prog):
            s.bar(trem(r + 12), "blast", crash_on_one=(i == 0))
        for i in range(4):
            s.bar(chugs, "double", crash_on_one=(i == 0), fill=(i == 3))
        for i in range(4):
            s.bar(drop, "half", crash_on_one=(i % 2 == 0))
    wail = [[(0, 8, 78), (8, 8, 76)], [(0, 8, 74), (8, 8, 73)], [(0, 8, 71), (8, 8, 74)], [(0, 16, 71)]]
    for i, r in enumerate(prog):
        s.bar([(0, 16, r, "o")], "double", crash_on_one=True, lead=wail[i])
    s.bar([(0, 16, B, "o")], "intro", crash_on_one=True)
    return s


SONGS = [
    ("iron_tide", "IRON TIDE", song_iron_tide),
    ("stormkeep", "STORMKEEP", song_stormkeep),
    ("skyreach", "SKYREACH", song_skyreach),
    ("highfalls", "HIGHFALLS", song_highfalls),
    ("graveblade", "GRAVEBLADE", song_graveblade),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for key, title, fn in SONGS:
        if only and key not in only:
            continue
        song = fn()
        mix = song.render()
        wav = os.path.join(OUT, key + ".wav")
        data = (mix * 32767).astype(np.int16)
        import wave
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(data.tobytes())
        ogg = os.path.join(OUT, key + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5",
                        "-metadata", "title=" + title, "-metadata", "artist=Block Royale", ogg], check=True)
        os.remove(wav)
        print("%s  %d:%02d" % (title, int(song.t) // 60, int(song.t) % 60))


if __name__ == "__main__":
    main()
