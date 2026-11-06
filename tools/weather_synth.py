#!/usr/bin/env python3
"""Weather sounds for Block Royale, synthesized.

  rain_loop.wav  a seamless rain bed: countless drops on leaves, grass and
                 roofs (granular), a soft hiss and the low body of heavy rain
  thunder.wav    a crack overhead rolling away into a long rumble

Run: python3 tools/weather_synth.py
"""
import numpy as np

import dsp
from dsp import secs, white, pink, lp, hp, bp, place


def rain(rng):
    n = secs(10.0)
    t = dsp.tvec(n)
    x = np.zeros(n)
    # The bed: a hiss with slow gusts.
    gust = 0.7 + 0.3 * np.sin(2 * np.pi * t / 7.0) * np.sin(2 * np.pi * t / 3.1 + 1.0)
    x += bp(pink(n, rng), 3500, 0.5) * 0.35 * gust
    x += lp(dsp.brown(n, rng), 400) * 0.25 * gust
    # Drops: thousands of tiny ticks of different sizes.
    for k in range(9000):
        ln = int(rng.uniform(0.0004, 0.004) * dsp.SR)
        s = rng.integers(0, n - ln)
        f = rng.uniform(1500, 9000) if rng.random() < 0.8 else rng.uniform(500, 1500)
        g = bp(white(ln, rng), f, 3.0) * np.exp(-np.arange(ln) / (ln * 0.25))
        x[s:s + ln] += g * rng.uniform(0.05, 0.4)
    x = hp(x, 80)
    f = secs(1.0)
    x[:f] = x[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    return x[:n - f]


def thunder(rng):
    n = secs(7.0)
    x = np.zeros(n)
    # The crack: a sharp, bright tear.
    cr = secs(0.25)
    place(x, hp(white(cr, rng), 900) * dsp.env_ad(cr, 0.002, 0.05) * 1.2, 0.0)
    place(x, dsp.friedlander(secs(0.3), 0.012, 1.2, 0.8) * 1.5, 0.0)
    # Rolling rumble: many low bursts, spreading out and darkening.
    for k in range(40):
        at = rng.random() ** 1.6 * 5.5
        ln = secs(rng.uniform(0.3, 1.2))
        b = lp(dsp.brown(ln, rng), rng.uniform(80, 260), 2) * np.sin(np.linspace(0, np.pi, ln))
        place(x, b * rng.uniform(0.3, 1.0) * (1.0 - at / 7.0), at)
    ir = dsp.impulse_response(rng, 3.0, 3.5, 1.0, [(0.2, 0.4), (0.6, 0.3), (1.3, 0.2)], 1.0, 0.05)
    y = dsp.fit(dsp.convolve(x, ir, wet=0.5, dry=1.0), n)
    return lp(y, 3000)


def main():
    rng = np.random.default_rng(2024)
    dsp.write("rain_loop", rain(rng), 0.7, rms=-20.0)
    dsp.write("thunder", thunder(rng), 0.9, rms=-12.0)
    print("weather sounds written")


if __name__ == "__main__":
    main()
