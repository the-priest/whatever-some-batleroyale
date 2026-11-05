#!/usr/bin/env python3
"""The Warden's sounds (anti-cheat enforcer), synthesized.

  warden_drone.wav    seamless loop: a sub-bass groan under detuned,
                      beating low voices and a cold wind, slowly breathing
  warden_whisper.wav  breathy, sibilant whispering that never quite forms words
  warden_scream.wav   the jumpscare: a tearing, rising shriek of several
                      voices over a roar, distorted (peak kept under full scale)

Run: python3 tools/horror_synth.py
"""
import numpy as np

import dsp
from dsp import secs, white, pink, lp, hp, bp, filt, place

SR = dsp.SR


def saw(f, n, phase=0.0):
    ph = np.cumsum(np.broadcast_to(f, (n,)) / SR) + phase
    return 2.0 * (ph - np.floor(ph + 0.5))


def formant(x, freqs, qs, gains):
    return sum(bp(x, f, q) * g for f, q, g in zip(freqs, qs, gains))


def drone(rng):
    n = secs(8.0)
    t = dsp.tvec(n)
    x = np.zeros(n)
    # Sub groan with a slow, uneven breath.
    breath = 0.6 + 0.4 * np.sin(2 * np.pi * t / 8.0) ** 2
    x += np.sin(2 * np.pi * 36.0 * t + 0.6 * np.sin(2 * np.pi * 0.25 * t)) * 0.7 * breath
    # Detuned low voices beating against each other (a minor second apart).
    for f, g in [(55.0, 0.35), (58.3, 0.3), (82.4, 0.18), (87.3, 0.15)]:
        v = saw(f * (1 + 0.004 * np.sin(2 * np.pi * rng.uniform(0.05, 0.2) * t)), n)
        x += lp(v, 420, 2) * g
    # Cold wind and a distant metallic ring.
    wind = dsp.sweep_bp(white(n, rng), 600, 1400, 3.0) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 4.0 + 1.0)) * 0.25
    x += wind
    ring = dsp.modal(rng, 311.0, dsp.PLATE, n, 2.5) * 0.04
    x += ring
    x = lp(x, 2500)
    # Seamless loop: crossfade the tail into the head.
    f = secs(0.8)
    x[:f] = x[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    return x[:n - f]


def whisper(rng):
    n = secs(2.6)
    x = np.zeros(n)
    at = 0.05
    while at < 2.3:
        ln = secs(rng.uniform(0.12, 0.35))
        src = white(ln, rng)
        if rng.random() < 0.4:
            # "sss" / "shh"
            syl = bp(src, rng.uniform(4500, 7000), 1.5) * 0.7
        else:
            # Breathy vowel: formants on noise.
            f1, f2 = rng.uniform(350, 750), rng.uniform(900, 2200)
            syl = formant(src, [f1, f2, 2800], [6, 8, 8], [1.0, 0.7, 0.3])
        syl *= np.sin(np.linspace(0, np.pi, ln)) ** 1.5
        place(x, syl * rng.uniform(0.5, 1.0), at)
        at += ln / SR + rng.uniform(0.02, 0.18)
    # Reverse-style swell: a long reverb tail feels like it comes from all around.
    ir = dsp.impulse_response(rng, 1.4, 1.2, 0.8, [(0.02, 0.4), (0.05, 0.3)], 1.4)
    y = dsp.fit(dsp.convolve(x, ir, wet=0.6, dry=0.7), n + secs(0.8))
    return hp(y, 250)


def scream(rng):
    n = secs(1.6)
    t = dsp.tvec(n)
    x = np.zeros(n)
    env = np.minimum(1.0, t / 0.025) * np.exp(-np.maximum(0.0, t - 0.9) / 0.25)
    # Several shrieking voices, pitch tearing upward with a ragged vibrato.
    for k in range(5):
        f0 = rng.uniform(380, 620)
        rise = f0 * (1.0 + 1.1 * (1 - np.exp(-t * 3.0)))
        vib = 1.0 + 0.03 * np.sin(2 * np.pi * rng.uniform(6, 11) * t) + 0.015 * white(n, rng) * 0.3
        v = saw(rise * vib, n, rng.random())
        v = formant(v, [rng.uniform(800, 1100), rng.uniform(1900, 2600), 3400], [4, 6, 8], [1.0, 0.8, 0.5])
        x += v * rng.uniform(0.5, 1.0)
    # Breath noise and a deep roar underneath.
    x += bp(white(n, rng), 3000, 0.8) * 0.45
    roar = lp(saw(70 * (1 + 0.3 * np.sin(2 * np.pi * 9 * t)), n), 600, 2) + lp(dsp.brown(n, rng), 300) * 0.8
    x = x / (np.max(np.abs(x)) + 1e-9) + roar * 0.6
    # Impact at the start: the lunge.
    place(x, dsp.friedlander(secs(0.08), 0.004, 1.2, 0.8) * 1.5, 0.0)
    x *= env
    # Distortion: torn, but the peak stays below full scale.
    x = np.tanh(x * 2.2)
    ir = dsp.impulse_response(rng, 1.0, 0.8, 0.4, [(0.01, 0.4), (0.03, 0.3)], 1.0)
    return dsp.fit(dsp.convolve(x, ir, wet=0.25, dry=1.0), n + secs(0.4))


def main():
    rng = np.random.default_rng(666)
    dsp.write("warden_drone", drone(rng), 0.8, rms=-17.0)
    dsp.write("warden_whisper", whisper(rng), 0.8, rms=-20.0)
    dsp.write("warden_scream", scream(rng), 0.9, rms=-11.0)
    print("horror sounds written")


if __name__ == "__main__":
    main()
