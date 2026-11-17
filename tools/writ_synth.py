#!/usr/bin/env python3
"""Writs, Embers and Wayshrines for Block Royale.

  writ_take.wav     parchment torn off the board, the wax seal cracking, a low horn
  writ_done.wav     a church bell tolling twice over the island
  writ_fail.wav     a dull drum and a falling horn
  writ_ping.wav     a soft double tick when the hunt circle moves
  ember.wav         embers into your purse: a warm glassy chime
  beacon_light.wav  pitch catching in an iron brazier: whoomph and crackle
  shrine_buy.wav    coins on stone and a low resonant hum

Run: python3 tools/writ_synth.py
"""
import numpy as np

import dsp

SR = dsp.SR
BELL = [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011]  # minor-third church bell partials


def horn(rng, f, dur, bend=0.0):
    n = dsp.secs(dur)
    t = dsp.tvec(n)
    fr = f * (1.0 + bend * t / dur) * (1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * t))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    x = np.zeros(n)
    for k, a in enumerate([1.0, 0.55, 0.32, 0.2, 0.11, 0.06]):
        x += np.sin(ph * (k + 1)) * a
    x += dsp.bp(dsp.white(n, rng), f * 3.0, 1.5) * 0.04
    env = np.minimum(1.0, t / 0.09) * np.minimum(1.0, (dur - t) / (dur * 0.45))
    return dsp.lp(x * np.clip(env, 0, 1), 2200.0, 2)


def bell(rng, f0, dur, hard=1.0):
    n = dsp.secs(dur)
    x = dsp.strike(rng, n, f0, BELL, decay=dur * 0.45, hard=hard, bright=5000.0, body=0.4, body_f=180.0, ring=0.9)
    # Hum note under the strike, longest of all.
    x += np.sin(2 * np.pi * f0 * 0.5 * dsp.tvec(n)) * np.exp(-dsp.tvec(n) / (dur * 0.6)) * 0.35
    return x


def space(rng, x, big=1.0, wet=0.35):
    ir = dsp.impulse_response(rng, 2.2 * big, 1.8 * big, 0.7 * big, density=0.7)
    return dsp.convolve(x, ir, wet=wet, dry=1.0)


def writ_take(rng):
    out = np.zeros(dsp.secs(2.2))
    # Parchment tearing off a nail.
    rip = dsp.friction(rng, dsp.secs(0.22), 1500, 3800, rough=0.7, q=1.2)
    dsp.place(out, rip * 0.6, 0.0)
    # Wax seal cracking: two brittle snaps.
    for at in (0.24, 0.27):
        c = dsp.strike(rng, dsp.secs(0.05), 2400.0, dsp.PLATE, 0.012, hard=0.8, bright=7000.0)
        dsp.place(out, c * 0.5, at)
    dsp.place(out, horn(rng, 98.0, 1.5) * 0.55, 0.32)
    dsp.place(out, horn(rng, 147.0, 1.3) * 0.3, 0.36)
    return dsp.fade(space(rng, out, 1.0, 0.3), 0.001, 0.2)


def writ_done(rng):
    out = np.zeros(dsp.secs(5.0))
    dsp.place(out, bell(rng, 330.0, 4.2), 0.0)
    dsp.place(out, bell(rng, 330.0, 3.6, 0.8) * 0.8, 0.95)
    return dsp.fade(space(rng, out, 1.6, 0.45), 0.001, 0.6)


def writ_fail(rng):
    out = np.zeros(dsp.secs(2.6))
    n = dsp.secs(0.6)
    drum = dsp.lp(dsp.white(n, rng), 160.0, 2) * dsp.env_ad(n, 0.002, 0.12) * 2.0
    drum += np.sin(2 * np.pi * 62.0 * dsp.tvec(n)) * dsp.env_ad(n, 0.002, 0.2)
    dsp.place(out, drum, 0.0)
    dsp.place(out, horn(rng, 110.0, 1.6, bend=-0.22) * 0.5, 0.12)
    return dsp.fade(space(rng, out, 1.2, 0.35), 0.001, 0.3)


def writ_ping(rng):
    out = np.zeros(dsp.secs(0.9))
    for at, f in ((0.0, 1320.0), (0.12, 1760.0)):
        n = dsp.secs(0.4)
        x = dsp.modal(rng, f, [1.0, 2.76, 5.4], n, 0.09, amps=[1.0, 0.25, 0.08])
        dsp.place(out, x * 0.6, at)
    return dsp.fade(space(rng, out, 0.6, 0.25), 0.001, 0.1)


def ember(rng):
    n = dsp.secs(0.9)
    x = dsp.modal(rng, 1567.0, [1.0, 2.0, 3.01, 4.2], n, 0.25, amps=[1.0, 0.4, 0.18, 0.08])
    x += dsp.modal(rng, 2093.0, [1.0, 2.0, 3.0], n, 0.18, amps=[0.6, 0.2, 0.08])
    # A breath of fire under it.
    x += dsp.bp(dsp.pink(n, rng), 900.0, 0.8) * dsp.env_ad(n, 0.02, 0.18) * 0.12
    return dsp.fade(space(rng, x, 0.5, 0.2), 0.001, 0.15)


def beacon_light(rng):
    n = dsp.secs(3.2)
    t = dsp.tvec(n)
    whoomph = dsp.lp(dsp.brown(n, rng), 380.0, 2) * dsp.env_ad(n, 0.12, 0.5) * 1.4
    roar = dsp.bp(dsp.pink(n, rng), 700.0, 0.5) * np.minimum(1.0, t / 0.3) * np.exp(-t / 2.2) * 0.5
    crack = dsp.grains(rng, n, 70, 1800.0, 5200.0, dur_ms=(0.3, 1.5), amp=(0.1, 0.6))
    crack *= np.minimum(1.0, t / 0.4)
    x = whoomph + roar + crack * 0.35
    return dsp.fade(x, 0.002, 0.6)


def shrine_buy(rng):
    out = np.zeros(dsp.secs(2.2))
    for i in range(5):
        c = dsp.strike(rng, dsp.secs(0.3), rng.uniform(2500, 3400), dsp.SHELL, 0.08, hard=0.6, bright=8000.0)
        dsp.place(out, c * 0.5, 0.02 + i * rng.uniform(0.04, 0.08))
    n = dsp.secs(1.8)
    hum = np.sin(2 * np.pi * 110.0 * dsp.tvec(n)) + 0.4 * np.sin(2 * np.pi * 165.0 * dsp.tvec(n))
    dsp.place(out, hum * dsp.env_ad(n, 0.25, 0.6) * 0.3, 0.2)
    return dsp.fade(space(rng, out, 0.9, 0.3), 0.001, 0.3)


def main():
    rng = np.random.default_rng(7171)
    dsp.write("writ_take", writ_take(rng), peak=0.8)
    dsp.write("writ_done", writ_done(rng), peak=0.85)
    dsp.write("writ_fail", writ_fail(rng), peak=0.8)
    dsp.write("writ_ping", writ_ping(rng), peak=0.6)
    dsp.write("ember", ember(rng), peak=0.6)
    dsp.write("beacon_light", beacon_light(rng), peak=0.8)
    dsp.write("shrine_buy", shrine_buy(rng), peak=0.75)


if __name__ == "__main__":
    main()
