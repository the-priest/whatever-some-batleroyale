#!/usr/bin/env python3
"""Water sounds for Block Royale: splashes, swim strokes, surfacing gasp and
an underwater ambience loop, synthesized from filtered noise.

  splash_big.wav      falling or jumping into deep water
  splash_small.wav    wading in / small splash
  swim_stroke_<n>.wav arm strokes at the surface (3 variations)
  gasp.wav            coming up for air
  underwater_loop.wav muffled pressure rumble with bubbles (loops)

Run: python3 tools/water_synth.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gen")


def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, f0, f1, order=2):
    b, a = signal.butter(order, [f0 / (SR / 2), f1 / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(attack, 1e-5)) * np.exp(-t / decay)


def bubbles(n, rng, rate, f_lo, f_hi, amp):
    """Rising sine chirps: the 'blub' of air bubbles."""
    out = np.zeros(n)
    count = int(rate * n / SR)
    for _ in range(count):
        s = rng.integers(0, max(1, n - 4000))
        ln = rng.integers(800, 3500)
        f0 = rng.uniform(f_lo, f_hi)
        t = np.arange(ln) / SR
        f = f0 * (1 + 3.0 * t / (ln / SR))
        ph = 2 * np.pi * np.cumsum(f) / SR
        out[s:s + ln] += np.sin(ph) * np.exp(-t * 40) * amp * rng.uniform(0.4, 1.0)
    return out


def splash(seed, big):
    rng = np.random.default_rng(seed)
    n = int((1.6 if big else 0.8) * SR)
    x = rng.normal(0, 1, n)
    # Impact: a bright slap, then a hissing spray shower that darkens.
    slap = hp(x, 900) * env(n, 0.002, 0.03 if big else 0.02)
    spray = bp(rng.normal(0, 1, n), 1500, 9000) * env(n, 0.02, 0.35 if big else 0.18) * 0.5
    body = lp(rng.normal(0, 1, n), 400) * env(n, 0.005, 0.12 if big else 0.06) * (1.6 if big else 0.8)
    plop = np.sin(2 * np.pi * np.cumsum(np.linspace(140, 60, n)) / SR) * env(n, 0.003, 0.08) * (0.9 if big else 0.4)
    b = bubbles(n, rng, 40 if big else 18, 300, 900, 0.25)
    y = slap * 0.9 + spray + body + plop + b * np.linspace(1, 0.2, n)
    return y


def stroke(seed):
    rng = np.random.default_rng(seed)
    n = int(0.55 * SR)
    x = rng.normal(0, 1, n)
    # Hand entering the water, a sloshing pull, droplets falling back.
    entry = bp(x, 700, 5000) * env(n, 0.01, 0.05) * 0.8
    pull = lp(rng.normal(0, 1, n), 900) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.5
    drops = np.zeros(n)
    for _ in range(14):
        s = rng.integers(int(0.15 * SR), n - 2000)
        ln = 1200
        t = np.arange(ln) / SR
        drops[s:s + ln] += np.sin(2 * np.pi * rng.uniform(1200, 2600) * t) * np.exp(-t * 90) * rng.uniform(0.1, 0.3)
    return entry + pull + drops


def gasp(seed):
    rng = np.random.default_rng(seed)
    n = int(0.7 * SR)
    x = rng.normal(0, 1, n)
    breath = bp(x, 500, 3200) * env(n, 0.06, 0.22)
    # A little vowel formant so it reads as a breath, not wind.
    t = np.arange(n) / SR
    form = np.sin(2 * np.pi * 820 * t) * 0.15 + np.sin(2 * np.pi * 1300 * t) * 0.08
    drip = hp(rng.normal(0, 1, n), 2500) * env(n, 0.001, 0.05) * 0.4
    return breath * (1.0 + form) + drip


def underwater_loop(seed):
    rng = np.random.default_rng(seed)
    n = int(6.0 * SR)
    rumble = lp(rng.normal(0, 1, n), 180, 4) * 2.0
    wash = lp(rng.normal(0, 1, n), 600) * (0.6 + 0.4 * np.sin(np.linspace(0, 2 * np.pi * 3, n)))
    b = bubbles(n, rng, 5, 200, 600, 0.35)
    y = rumble + wash * 0.4 + b
    # Crossfade the ends so it loops without a click.
    fade = int(0.3 * SR)
    y[:fade] = y[:fade] * np.linspace(0, 1, fade) + y[-fade:] * np.linspace(1, 0, fade)
    return y[: n - fade]


def write(name, x, peak=0.85):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    write("splash_big", splash(1, True))
    write("splash_small", splash(2, False), 0.6)
    for i in range(3):
        write("swim_stroke_%d" % (i + 1), stroke(10 + i), 0.5)
    write("gasp", gasp(20), 0.55)
    write("underwater_loop", underwater_loop(30), 0.6)
    print("water sounds written")


if __name__ == "__main__":
    main()
