#!/usr/bin/env python3
"""Healing item and hand-action sounds for Block Royale, synthesized from
filtered noise.

  bandage_wrap.wav   cloth bandage pulled and wrapped (one pass)
  kit_zip_open.wav   medkit zipper opening
  kit_zip_close.wav  medkit zipper closing
  syringe_click.wav  syringe cap off / plunger click
  syringe_inject.wav short pressurised hiss
  can_open.wav       can tab crack and fizz
  gulp.wav           one swallow
  drink_ahh.wav      satisfied breath out
  can_crush.wav      empty can crumpled in the fist
  bandage_tear.wav   strip torn off the roll
  grenade_pin.wav    pin drawn out of a grenade, ring clink
  throw_whoosh.wav   arm swinging through a throw

Run: python3 tools/heal_synth.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gen")


def bp(x, f0, f1, order=2):
    b, a = signal.butter(order, [f0 / (SR / 2), f1 / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(attack, 1e-5)) * np.exp(-t / decay)


def bandage(seed):
    rng = np.random.default_rng(seed)
    n = int(0.75 * SR)
    t = np.arange(n) / SR
    # Fabric: band-limited noise with a slow tug envelope and grainy crackle.
    cloth = bp(rng.normal(0, 1, n), 900, 6000) * (np.sin(np.pi * t / t[-1]) ** 1.5)
    grain = np.zeros(n)
    for _ in range(90):
        s = rng.integers(0, n - 300)
        grain[s:s + 300] += hp(rng.normal(0, 1, 300), 3000) * np.exp(-np.arange(300) / 60) * rng.uniform(0.2, 0.6)
    return cloth * 0.6 + grain * 0.5


def zipper(seed, closing):
    rng = np.random.default_rng(seed)
    n = int(0.55 * SR)
    out = np.zeros(n)
    teeth = 34
    for i in range(teeth):
        f = i / teeth
        pos = f if not closing else f ** 0.8
        s = int(pos * (n - 900))
        click = bp(rng.normal(0, 1, 600), 2000, 9000) * np.exp(-np.arange(600) / 70)
        out[s:s + 600] += click * rng.uniform(0.6, 1.0)
    out += bp(rng.normal(0, 1, n), 1500, 5000) * 0.15
    return out


def click(seed):
    rng = np.random.default_rng(seed)
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    snap = bp(rng.normal(0, 1, n), 2500, 10000) * env(n, 0.0005, 0.006)
    body = np.sin(2 * np.pi * 1900 * t) * env(n, 0.0005, 0.01) * 0.4
    return snap + body


def inject(seed):
    rng = np.random.default_rng(seed)
    n = int(0.5 * SR)
    hiss = bp(rng.normal(0, 1, n), 3000, 11000) * env(n, 0.03, 0.18)
    return hiss


def can_open(seed):
    rng = np.random.default_rng(seed)
    n = int(0.9 * SR)
    crack = bp(rng.normal(0, 1, n), 1500, 9000) * env(n, 0.0005, 0.012) * 1.6
    pssht = hp(rng.normal(0, 1, n), 2500) * env(n, 0.01, 0.16) * 0.7
    fizz = np.zeros(n)
    for _ in range(140):
        s = rng.integers(int(0.05 * SR), n - 200)
        fizz[s:s + 200] += hp(rng.normal(0, 1, 200), 5000) * np.exp(-np.arange(200) / 30) * rng.uniform(0.05, 0.2)
    return crack + pssht + fizz * np.linspace(1, 0.1, n)


def gulp(seed):
    rng = np.random.default_rng(seed)
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 180 + 260 * np.exp(-t * 18)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.01, 0.07)
    wet = lp(rng.normal(0, 1, n), 1200) * env(n, 0.005, 0.05) * 0.5
    return tone + wet


def ahh(seed):
    rng = np.random.default_rng(seed)
    n = int(0.8 * SR)
    t = np.arange(n) / SR
    breath = bp(rng.normal(0, 1, n), 400, 3000) * np.sin(np.pi * t / t[-1]) ** 2
    vowel = (np.sin(2 * np.pi * 140 * t) * 0.3 + np.sin(2 * np.pi * 750 * t) * 0.12) * np.sin(np.pi * t / t[-1]) ** 3
    return breath * 0.7 + vowel * 0.5


def crush(seed):
    rng = np.random.default_rng(seed)
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # Thin aluminium buckling: a run of sharp ringing creaks.
    for i in range(16):
        s = int(rng.uniform(0.0, 0.32) * SR)
        ln = int(0.05 * SR)
        tt = np.arange(ln) / SR
        ring = sum(np.sin(2 * np.pi * rng.uniform(1800, 6500) * tt + rng.uniform(0, 6)) for _ in range(3))
        ping = ring * np.exp(-tt * rng.uniform(60, 140)) + bp(rng.normal(0, 1, ln), 2500, 12000) * np.exp(-tt * 200)
        out[s:s + ln] += ping[: n - s] * rng.uniform(0.3, 1.0)
    return out * np.exp(-t * 3.0)


def tear(seed):
    rng = np.random.default_rng(seed)
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    # Fibres snapping in quick succession under a soft cloth rasp.
    rasp = bp(rng.normal(0, 1, n), 1500, 8000) * np.sin(np.pi * np.minimum(t / 0.28, 1.0)) ** 2
    snaps = np.zeros(n)
    for _ in range(60):
        s = int(rng.uniform(0.0, 0.27) * SR)
        snaps[s:s + 120] += hp(rng.normal(0, 1, 120), 4000) * np.exp(-np.arange(120) / 18) * rng.uniform(0.3, 1.0)
    return rasp * 0.5 + snaps * 0.7


def pin(seed):
    rng = np.random.default_rng(seed)
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    # Steel pin scraping out of the fuse, then the ring clinks.
    s0 = int(0.02 * SR)
    ln = int(0.09 * SR)
    scrape = np.zeros(n)
    scrape[s0:s0 + ln] = bp(rng.normal(0, 1, ln), 3000, 11000) * np.sin(np.linspace(0, np.pi, ln)) * 0.5
    ring = np.zeros(n)
    c = int(0.12 * SR)
    tt = t[: n - c]
    for f in (2900, 4650, 7100):
        ring[c:] += np.sin(2 * np.pi * f * tt + rng.uniform(0, 6)) * np.exp(-tt * rng.uniform(25, 45))
    click = bp(rng.normal(0, 1, n), 1500, 9000) * env(n, 0.0003, 0.004)
    return scrape + ring * 0.35 + click * 0.8


def whoosh(seed):
    rng = np.random.default_rng(seed)
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    # Air past a swinging arm: band-passed noise with a rising, falling sweep.
    x = rng.normal(0, 1, n)
    out = np.zeros(n)
    k = 256
    for i in range(0, n - k, k):
        f = 300 + 1500 * np.sin(np.pi * min(1.0, i / n * 1.4)) ** 2
        out[i:i + k] = bp(x[i:i + k + 0], f, f * 2.2)[:k]
    return lp(out, 4000) * np.sin(np.pi * np.minimum(t / 0.3, 1.0)) ** 2


def write(name, x, peak=0.7):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    write("bandage_wrap", bandage(1), 0.5)
    write("kit_zip_open", zipper(2, False), 0.55)
    write("kit_zip_close", zipper(3, True), 0.55)
    write("syringe_click", click(4), 0.5)
    write("syringe_inject", inject(5), 0.4)
    write("can_open", can_open(6), 0.6)
    write("gulp", gulp(7), 0.6)
    write("drink_ahh", ahh(8), 0.45)
    write("can_crush", crush(9), 0.5)
    write("bandage_tear", tear(10), 0.5)
    write("grenade_pin", pin(11), 0.5)
    write("throw_whoosh", whoosh(12), 0.45)
    print("healing sounds written")


if __name__ == "__main__":
    main()
