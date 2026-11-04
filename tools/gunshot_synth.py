#!/usr/bin/env python3
"""Gunshot sounds for Block Royale, synthesized from physical layers.

A real gunshot heard from the shooter's position is several overlapping
events: the action cycling (bolt, hammer), the muzzle blast (a very short,
very loud broadband pressure wave with a low "thump" body), the supersonic
bullet crack, the gas/port ring, and then the environment answering, a
first ground/wall slap a few milliseconds later and a long rolling tail as
the sound reflects off hills, trees and buildings.

For every gun class this writes:
  shot_<class>_<n>.wav  close shot, several variations (picked at random)
  shot_<class>.wav      first variation (fallback name)
  shot_<class>_far.wav  the same gun heard from hundreds of metres:
                        thudding boom, no crack, long echo tail
  tail_<env>.wav        environment tails layered on top of close shots
                        (open field, forest, town, indoors)

Run: python3 tools/gunshot_synth.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gen")


def bq(kind, f, q=0.707, g=0.0):
    w = 2 * np.pi * f / SR
    a = np.sin(w) / (2 * q)
    c = np.cos(w)
    A = 10 ** (g / 40)
    if kind == "lp":
        b, aa = [(1 - c) / 2, 1 - c, (1 - c) / 2], [1 + a, -2 * c, 1 - a]
    elif kind == "hp":
        b, aa = [(1 + c) / 2, -(1 + c), (1 + c) / 2], [1 + a, -2 * c, 1 - a]
    elif kind == "bp":
        b, aa = [a, 0, -a], [1 + a, -2 * c, 1 - a]
    else:
        b, aa = [1 + a * A, -2 * c, 1 - a * A], [1 + a / A, -2 * c, 1 - a / A]
    return np.array(b) / aa[0], np.array(aa) / aa[0]


def f(x, kind, fr, q=0.707, g=0.0):
    b, a = bq(kind, fr, q, g)
    return signal.lfilter(b, a, x)


def env_exp(n, tau, attack=0.0002):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(attack, 1e-6)) * np.exp(-t / tau)


def noise(n, rng):
    return rng.normal(0, 1, n)


# Character of each gun class.
GUNS = {
    #           blast  body_hz body_tau crack mech  ring_hz  tail  bright
    "ak":      (1.00,   78,   0.050,   0.85, 0.55, 1650,   1.00, 0.85),
    "rifle":   (0.95,   92,   0.040,   0.95, 0.45, 2100,   0.95, 1.00),
    "smg":     (0.75,  120,   0.028,   0.25, 0.65, 2600,   0.70, 0.90),
    "pistol":  (0.80,  110,   0.032,   0.20, 0.50, 2300,   0.75, 0.95),
    "shotgun": (1.15,   62,   0.075,   0.00, 0.60, 1200,   1.15, 0.70),
    "lmg":     (1.00,   82,   0.045,   0.90, 0.50, 1800,   1.00, 0.85),
    "dmr":     (1.05,   72,   0.060,   1.00, 0.45, 1500,   1.15, 0.90),
    "sniper":  (1.25,   58,   0.090,   1.10, 0.35, 1100,   1.40, 0.80),
}


def close_shot(cls, seed):
    blast, body_hz, body_tau, crack, mech, ring_hz, tail_k, bright = GUNS[cls]
    rng = np.random.default_rng(seed)
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # 1. Action: a tiny mechanical click just before / at the blast.
    m = int(0.012 * SR)
    click = f(noise(m, rng), "bp", 3200 + rng.uniform(-300, 300), 2.0) * env_exp(m, 0.0025) * 0.35 * mech
    out[:m] += click
    # 2. Muzzle blast: N-wave-ish pressure spike, broadband and clipped hard.
    d0 = int(0.0015 * SR)
    bl = int(0.09 * SR)
    burst = noise(bl, rng)
    burst = f(burst, "hp", 300) * 0.8 + f(burst, "lp", 2500) * 0.6
    burst *= env_exp(bl, 0.010 * (1.2 if cls in ("shotgun", "sniper") else 1.0), 0.0003)
    nwave = np.zeros(bl)
    k = int(0.0018 * SR)
    nwave[:k] = np.linspace(1, -0.6, k)
    burst += nwave * 2.5
    out[d0:d0 + bl] += np.tanh(burst * 3.0 * blast) * blast
    # 3. Body: the chest-thump low end with a quick pitch drop.
    bn = int(0.4 * SR)
    tb = np.arange(bn) / SR
    fr = body_hz * (1 + 1.3 * np.exp(-tb * 60))
    ph = np.cumsum(fr) / SR
    body = np.sin(2 * np.pi * ph) * env_exp(bn, body_tau, 0.0008)
    body += 0.4 * np.sin(2 * np.pi * ph * 0.5) * env_exp(bn, body_tau * 1.6, 0.001)
    out[d0:d0 + bn] += np.tanh(body * 1.8) * 0.9 * blast
    # 4. Supersonic crack: very short, very bright snap.
    if crack > 0:
        cn = int(0.02 * SR)
        cr = f(noise(cn, rng), "hp", 3500) * env_exp(cn, 0.0022, 0.0001)
        out[d0:d0 + cn] += cr * 1.4 * crack * bright
    # 5. Gas / receiver ring: metallic resonance after the blast.
    rn = int(0.25 * SR)
    ring = f(noise(rn, rng), "bp", ring_hz, 8.0) * env_exp(rn, 0.04) * 0.6
    ring += f(noise(rn, rng), "bp", ring_hz * 1.7, 10.0) * env_exp(rn, 0.03) * 0.35
    out[d0:d0 + rn] += ring * 0.5 * blast
    # 6. First reflection off the ground, then a short outdoor slap.
    for delay, gain, lp in [(0.006, 0.45, 5000), (0.018, 0.28, 3500), (0.047, 0.18, 2500), (0.09, 0.12, 1800)]:
        s = int((delay + rng.uniform(-0.002, 0.002)) * SR)
        refl = f(out[:n - s], "lp", lp) * gain
        out[s:] += refl
    # 7. Short ambient tail (environment tails are layered on top at runtime).
    tn = int(1.2 * SR)
    tail = f(f(noise(tn, rng), "lp", 900 * bright), "hp", 120)
    tail *= env_exp(tn, 0.22 * tail_k, 0.03) * 0.14 * blast
    out[int(0.03 * SR):int(0.03 * SR) + tn] += tail
    # Master: tilt EQ per gun, soft limiter.
    out = f(out, "hp", 40)
    out = f(out, "peak", 120, 1.0, 3.0)
    out = f(out, "peak", 3000, 1.0, 2.0 * bright)
    out = out / (np.max(np.abs(out)) + 1e-9)
    out = np.tanh(out * 2.4) / np.tanh(2.4)
    return out[:int(1.3 * SR)]


def far_shot(cls, seed):
    """The same gun across the valley: a dull boom and a long rolling echo."""
    blast, body_hz, body_tau, crack, mech, ring_hz, tail_k, bright = GUNS[cls]
    rng = np.random.default_rng(seed + 1000)
    n = int(3.6 * SR)
    out = np.zeros(n)
    bn = int(0.35 * SR)
    tb = np.arange(bn) / SR
    boom = np.sin(2 * np.pi * np.cumsum(body_hz * 0.8 * (1 + 0.5 * np.exp(-tb * 30))) / SR) * env_exp(bn, body_tau * 2.5, 0.004)
    boom += f(noise(bn, rng), "lp", 700) * env_exp(bn, 0.03, 0.002) * 1.2
    out[:bn] += boom * blast
    # Rolling thunder: many late reflections, getting darker and sparser.
    for i in range(14):
        delay = 0.12 + i * rng.uniform(0.12, 0.26)
        s = int(delay * SR)
        if s + bn >= n:
            break
        g = 0.55 * np.exp(-i * 0.28) * rng.uniform(0.6, 1.0)
        out[s:s + bn] += f(boom, "lp", 900 * np.exp(-i * 0.12)) * g
    roll = f(f(noise(n, rng), "lp", 400), "hp", 50) * env_exp(n, 0.9 * tail_k, 0.15) * 0.22 * blast
    out += roll
    out = f(out, "lp", 2200)
    out = np.tanh(out * 1.2)
    return out


def env_tail(kind, seed):
    """Reflections layered over close shots depending on surroundings."""
    rng = np.random.default_rng(seed)
    if kind == "field":
        n, taus, lp, density = int(2.6 * SR), [0.9], 700, [(0.25, 0.5), (0.6, 0.35), (1.1, 0.22)]
    elif kind == "forest":
        n, taus, lp, density = int(1.8 * SR), [0.45], 1500, [(0.05, 0.4), (0.12, 0.35), (0.2, 0.3), (0.31, 0.25)]
    elif kind == "town":
        n, taus, lp, density = int(1.6 * SR), [0.35], 2400, [(0.03, 0.6), (0.07, 0.5), (0.11, 0.45), (0.19, 0.3), (0.26, 0.25)]
    else:  # indoors: dense, bright, short and loud
        n, taus, lp, density = int(0.8 * SR), [0.16], 4200, [(0.004, 0.8), (0.009, 0.7), (0.015, 0.6), (0.024, 0.5)]
    out = np.zeros(n)
    hit = f(noise(int(0.05 * SR), rng), "lp", lp) * env_exp(int(0.05 * SR), 0.012)
    for d, g in density:
        s = int(d * SR)
        out[s:s + len(hit)] += hit * g
    out += f(f(noise(n, rng), "lp", lp * 0.6), "hp", 90) * env_exp(n, taus[0], 0.02) * 0.35
    return np.tanh(out * 1.5)


def write(name, x, peak=0.92):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, cls in enumerate(GUNS):
        for v in range(4):
            x = close_shot(cls, 100 * i + v)
            write("shot_%s_%d" % (cls, v + 1), x)
            if v == 0:
                write("shot_" + cls, x)
        write("shot_%s_far" % cls, far_shot(cls, i), 0.8)
    for j, kind in enumerate(["field", "forest", "town", "indoor"]):
        write("tail_" + kind, env_tail(kind, 900 + j), 0.7)
    print("gunshots written")


if __name__ == "__main__":
    main()
