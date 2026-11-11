#!/usr/bin/env python3
"""Wildlife for Block Royale: birdsong in the woods and gulls on the coast.

  bird_<n>.wav   one bird call each: whistles, trills, chirps (6 variations)
  gull_<n>.wav   a gull's cry over the shore (3 variations)

Each call is a few frequency-modulated partials with a quick attack, the way
a syrinx sounds: a strong fundamental, a weaker octave, no noise to speak of.

Run: python3 tools/nature_synth.py
"""
import os

import numpy as np

import dsp

SR = dsp.SR
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gen")


def note(f_curve, amp_curve, harm=(1.0, 0.18, 0.05)):
    """A voiced syllable following a frequency curve (Hz per sample)."""
    ph = 2 * np.pi * np.cumsum(f_curve) / SR
    out = np.zeros(len(f_curve))
    for k, a in enumerate(harm):
        out += np.sin(ph * (k + 1)) * a
    return out * amp_curve


def shape(n, attack=0.008, release=0.03):
    t = np.arange(n) / SR
    d = n / SR
    a = np.minimum(1.0, t / attack) * np.minimum(1.0, (d - t) / release)
    return np.clip(a, 0.0, 1.0)


def whistle(rng, f0, f1, dur, vib=0.0, vib_f=30.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n) * (1.0 + vib * np.sin(2 * np.pi * vib_f * t))
    return note(f, shape(n))


def trill(rng, f_mid, rate, dur, depth):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f_mid * (1.0 + depth * np.sin(2 * np.pi * rate * t))
    amp = shape(n) * (0.6 + 0.4 * np.abs(np.sin(np.pi * rate * t)))
    return note(f, amp)


def song(seed, parts):
    rng = np.random.default_rng(seed)
    out = np.zeros(int(4.0 * SR))
    at = 0.05
    for p in parts:
        kind = p[0]
        if kind == "w":
            x = whistle(rng, *p[1:])
        elif kind == "t":
            x = trill(rng, *p[1:])
        else:
            at += p[1]
            continue
        dsp.place(out, x * rng.uniform(0.8, 1.0), at)
        at += len(x) / SR + rng.uniform(0.02, 0.06)
    out = out[: int((at + 0.3) * SR)]
    # A touch of woodland: a short, soft reflection tail.
    ir = dsp.impulse_response(rng, 0.6, 0.5, 0.25, density=0.6)
    out = dsp.convolve(out, ir, wet=0.18, dry=1.0)
    return dsp.trim_silence(dsp.fade(out, 0.002, 0.08))


def gull(seed):
    rng = np.random.default_rng(seed)
    out = np.zeros(int(3.0 * SR))
    at = 0.05
    calls = rng.integers(2, 5)
    for i in range(calls):
        dur = rng.uniform(0.18, 0.32) if i else rng.uniform(0.35, 0.5)
        n = int(dur * SR)
        t = np.arange(n) / SR
        f0 = rng.uniform(900, 1150)
        # Up and then falling away: the "kee-ow".
        f = f0 * (1.0 + 0.5 * np.sin(np.pi * np.minimum(1.0, t / dur * 1.3)) - 0.25 * t / dur)
        amp = shape(n, 0.02, 0.06)
        x = note(f, amp, harm=(1.0, 0.55, 0.35, 0.22, 0.12))
        # Hoarse: a little noise riding on it.
        x += dsp.bp(dsp.white(n, rng), 2200.0, 1.2) * amp * 0.25
        dsp.place(out, x, at)
        at += dur + rng.uniform(0.06, 0.14)
    out = out[: int((at + 0.4) * SR)]
    ir = dsp.impulse_response(rng, 1.0, 0.9, 0.5, density=0.4)
    out = dsp.convolve(out, ir, wet=0.25, dry=1.0)
    return dsp.trim_silence(dsp.fade(out, 0.002, 0.1))


def main():
    songs = [
        # Two clear falling whistles and a quick trill.
        [("w", 3600, 2900, 0.22), ("p", 0.08), ("w", 3500, 2800, 0.2), ("t", 4200, 38, 0.35, 0.12)],
        # A rising "sweet" call, repeated.
        [("w", 2400, 3900, 0.14), ("p", 0.05), ("w", 2400, 3900, 0.14), ("p", 0.05), ("w", 2500, 4100, 0.18)],
        # A fast run of chirps.
        [("w", 5200, 4300, 0.05)] * 2 + [("w", 5000, 4100, 0.05)] * 3 + [("w", 4600, 3600, 0.09)],
        # A long trill.
        [("t", 3800, 26, 0.9, 0.08)],
        # Warbled phrase.
        [("w", 3000, 3400, 0.12, 0.05, 22), ("w", 3800, 3100, 0.1), ("w", 2900, 3600, 0.16, 0.04, 30), ("t", 4400, 45, 0.25, 0.1)],
        # Two-note "tee-oo", like a tit.
        [("w", 4400, 4300, 0.12), ("w", 3100, 3000, 0.14), ("p", 0.07), ("w", 4400, 4300, 0.12), ("w", 3100, 3000, 0.14)],
    ]
    for i, s in enumerate(songs):
        dsp.write("bird_%d" % (i + 1), song(100 + i, s), out_dir=OUT, peak=0.7)
    for i in range(3):
        dsp.write("gull_%d" % (i + 1), gull(200 + i), out_dir=OUT, peak=0.7)


if __name__ == "__main__":
    main()
