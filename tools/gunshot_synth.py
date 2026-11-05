#!/usr/bin/env python3
"""Gunshot sounds for Block Royale, built from the physics of a shot.

Heard from the shooter, a shot is:
  * the sear/hammer letting go (a tiny metal click)
  * the muzzle blast: a Friedlander pressure wave, a near-instant rise and a
    decay through zero into suction. Its length scales with the cartridge, and
    that length is what makes a rifle crack and a shotgun boom
  * the propellant gas: a slower second pressure wave and turbulent roar
  * the supersonic bullet's N-wave (rifles)
  * the action cycling: bolt carrier unlocking and chambering, receiver ring
  * the world answering: ground bounce, nearby surfaces, and a long tail
    whose high end dies first (convolved with a generated impulse response)
Then it is compressed and clipped like a close-mic'd recording.

Writes (assets/audio/gen):
  shot_<snd>_<1..4>.wav  close shot variations, shot_<snd>.wav the first one
  shot_<snd>_far.wav     the same gun across the valley
  tail_<env>.wav         surroundings layered on top at runtime

Run: python3 tools/gunshot_synth.py
"""
import numpy as np

import dsp
from dsp import secs, white, lp, hp, filt, place

# td: blast duration (ms); gas: slow-wave strength; crack: N-wave; mech: action
# loudness; carrier: bolt carrier ring (Hz); auto: has a reciprocating bolt;
# boom: low-end weight; bright: top-end; tail: echo strength.
GUNS = {
    "ak":      dict(td=0.55, gas=0.55, gas_td=6.0, crack=0.8, mech=0.55, carrier=1350, auto=True, boom=1.10, bright=0.85, tail=1.00),
    "rifle":   dict(td=0.42, gas=0.45, gas_td=4.5, crack=1.0, mech=0.45, carrier=1750, auto=True, boom=0.95, bright=1.05, tail=0.95),
    "smg":     dict(td=0.30, gas=0.35, gas_td=3.2, crack=0.0, mech=0.75, carrier=2300, auto=True, boom=0.70, bright=0.95, tail=0.70),
    "pistol":  dict(td=0.32, gas=0.40, gas_td=3.5, crack=0.0, mech=0.60, carrier=2600, auto=True, boom=0.75, bright=1.00, tail=0.75),
    "shotgun": dict(td=0.85, gas=0.85, gas_td=9.0, crack=0.0, mech=0.30, carrier=1100, auto=False, boom=1.35, bright=0.70, tail=1.15),
    "lmg":     dict(td=0.48, gas=0.50, gas_td=5.0, crack=0.9, mech=0.55, carrier=1250, auto=True, boom=1.05, bright=0.90, tail=1.00),
    "dmr":     dict(td=0.60, gas=0.55, gas_td=6.5, crack=1.0, mech=0.45, carrier=1500, auto=True, boom=1.15, bright=0.95, tail=1.15),
    "sniper":  dict(td=0.75, gas=0.65, gas_td=8.0, crack=1.15, mech=0.15, carrier=1200, auto=False, boom=1.40, bright=0.90, tail=1.40),
}


def _blast(rng, g, scale=1.0):
    """Dry muzzle blast + gas, ~0.25 s."""
    n = secs(0.3)
    x = np.zeros(n)
    td = g["td"] * 0.001 * scale
    p = dsp.friedlander(secs(0.03), td, b=1.7, neg=0.55)
    # Turbulent texture on the main wave (the blast is not a perfect pulse).
    tex = 1.0 + 0.35 * lp(white(len(p), rng), 9000)
    x[:len(p)] += p * tex
    gas = dsp.friedlander(secs(0.2), g["gas_td"] * 0.001 * scale, b=1.25, neg=0.9) * g["gas"]
    x[secs(0.0004):secs(0.0004) + len(gas)] += gas[: n - secs(0.0004)]
    roar_n = secs(0.22)
    roar = lp(dsp.pink(roar_n, rng), 2600 * g["bright"], 2) * dsp.env_ad(roar_n, 0.0006, 0.022 * scale * (0.8 + g["boom"] * 0.4))
    x[:roar_n] += roar * 0.22 * g["gas"]
    return x


def _crack(rng, g):
    n = secs(0.004)
    t = dsp.tvec(n)
    dur = 0.00035
    nw = np.where(t < dur, 1.0 - 2.0 * t / dur, 0.0)
    return hp(nw, 900) * 0.9 * g["crack"]


def _action(rng, g, cls):
    """Bolt carrier slamming back and forward, receiver ringing."""
    n = secs(0.16)
    x = np.zeros(n)
    sear = dsp.strike(rng, secs(0.03), 3800, dsp.BAR, 0.006, hard=0.25, bright=7000, ring=0.3)
    place(x, sear, 0.0)
    if g["auto"]:
        back = dsp.strike(rng, secs(0.06), g["carrier"], dsp.PLATE, 0.012, hard=0.7, bright=5000, body=0.5, body_f=420, ring=0.22)
        fwd = dsp.strike(rng, secs(0.07), g["carrier"] * 1.12, dsp.PLATE, 0.016, hard=0.9, bright=5500, body=0.6, body_f=380, ring=0.22)
        slide = dsp.friction(rng, secs(0.018), 2200, 1500, rough=0.6) * 0.25
        place(x, slide, 0.010)
        place(x, back, 0.016 + rng.uniform(0, 0.004))
        place(x, fwd, 0.046 + rng.uniform(0, 0.006))
    ring = dsp.modal(rng, g["carrier"] * 0.62, dsp.SHELL, n, 0.025) * 0.08
    x += ring
    # From the shooter's seat the action sits well under the blast.
    return x * g["mech"] * 0.32


def _outdoor_ir(rng, tail_k, length=1.6):
    early = [(0.0042, 0.55), (0.011, 0.32), (0.027, 0.24), (0.046, 0.18), (0.083, 0.12), (0.14, 0.09)]
    return dsp.impulse_response(rng, length, 1.4 * tail_k, 0.35 * tail_k, early, density=1.0, pre=0.01)


def close_shot(cls, seed):
    g = GUNS[cls]
    rng = np.random.default_rng(seed)
    n = secs(1.5)
    dry = np.zeros(n)
    place(dry, _action(rng, g, cls), 0.0)
    t0 = 0.0035
    blast = _blast(rng, g, 1.0 + rng.uniform(-0.06, 0.06))
    place(dry, blast, t0)
    if g["crack"] > 0:
        place(dry, _crack(rng, g), t0 - 0.0006)
    # Ground bounce right under the muzzle (shooter's ears are 1.5 m up).
    place(dry, lp(blast, 6000) * 0.45, t0 + 0.0045)
    # Tone: weight in the lows, bite in the presence band.
    dry = filt(dry, "ls", 110, 0.8, 5.0 * g["boom"])
    dry = filt(dry, "peak", 2800, 0.9, 2.5 * g["bright"])
    dry = hp(dry, 28)
    wet = dsp.convolve(dry, _outdoor_ir(rng, g["tail"]), wet=0.32 * g["tail"], dry=1.0)
    wet = dsp.fit(wet, n)
    # Recorded gunfire is squashed: fast compressor, then a clipper.
    wet = wet / (np.max(np.abs(wet)) + 1e-9)
    wet = dsp.compress(wet, thresh_db=-15.0, ratio=3.0, attack=0.0004, release=0.06, makeup_db=4.0)
    wet = dsp.soft_clip(wet, 1.6)
    return wet


def far_shot(cls, seed):
    """The same gun a few hundred metres off: air has eaten the top end, the
    crack is gone, and the valley rolls the boom back for seconds."""
    g = GUNS[cls]
    rng = np.random.default_rng(seed + 1000)
    n = secs(4.0)
    dry = np.zeros(n)
    blast = _blast(rng, g, 1.8)
    blast = lp(blast, 900 * g["bright"], 2)
    place(dry, blast, 0.0)
    early = [(0.21, 0.42), (0.38, 0.34), (0.62, 0.28), (0.9, 0.22), (1.25, 0.17), (1.7, 0.12), (2.2, 0.08)]
    ir = dsp.impulse_response(rng, 3.6, 3.2 * g["tail"], 0.9 * g["tail"], early, density=1.4, pre=0.08)
    wet = dsp.fit(dsp.convolve(dry, ir, wet=0.9, dry=0.8), n)
    wet = lp(wet, 1800)
    wet = wet / (np.max(np.abs(wet)) + 1e-9)
    wet = dsp.compress(wet, thresh_db=-16.0, ratio=3.0, attack=0.004, release=0.3, makeup_db=6.0)
    return dsp.soft_clip(wet, 1.2)


def env_tail(kind, seed):
    """The surroundings' answer alone (no direct sound), layered at runtime."""
    rng = np.random.default_rng(seed)
    if kind == "field":
        early = [(0.24, 0.5), (0.55, 0.35), (0.95, 0.25), (1.4, 0.16)]
        ir = dsp.impulse_response(rng, 2.8, 2.6, 0.7, early, 0.8, 0.12)
        f_lp = 1500
    elif kind == "forest":
        early = [(0.03, 0.4), (0.06, 0.35), (0.1, 0.3), (0.16, 0.25), (0.24, 0.2)]
        ir = dsp.impulse_response(rng, 2.0, 1.4, 0.45, early, 1.2, 0.02)
        f_lp = 2600
    elif kind == "town":
        early = [(0.018, 0.6), (0.035, 0.5), (0.06, 0.45), (0.1, 0.35), (0.17, 0.28), (0.26, 0.2)]
        ir = dsp.impulse_response(rng, 1.8, 1.2, 0.4, early, 1.1, 0.01)
        f_lp = 3800
    else:  # indoors: dense, bright, short and loud
        early = [(0.003, 0.8), (0.006, 0.7), (0.01, 0.62), (0.015, 0.5), (0.022, 0.42)]
        ir = dsp.impulse_response(rng, 0.9, 0.55, 0.22, early, 1.6, 0.0)
        f_lp = 6000
    ir[: secs(0.002)] = 0.0  # no direct sound
    burst = dsp.friedlander(secs(0.03), 0.0006, 1.6, 0.6) + lp(white(secs(0.03), rng), 2000) * dsp.env_ad(secs(0.03), 0.0005, 0.006) * 0.3
    x = lp(dsp.convolve(burst, ir, wet=1.0, dry=0.0), f_lp)
    return dsp.soft_clip(x / (np.max(np.abs(x)) + 1e-9), 1.3)


def main():
    for i, cls in enumerate(GUNS):
        for v in range(4):
            x = close_shot(cls, 100 * i + v)
            loud = {"sniper": -12.5, "shotgun": -13.0, "dmr": -13.5, "smg": -15.0, "pistol": -15.0}.get(cls, -14.0)
            dsp.write("shot_%s_%d" % (cls, v + 1), x, 0.95, rms=loud)
            if v == 0:
                dsp.write("shot_" + cls, x, 0.95, rms=loud)
        dsp.write("shot_%s_far" % cls, far_shot(cls, i), 0.85, rms=-12.0)
    for j, kind in enumerate(["field", "forest", "town", "indoor"]):
        dsp.write("tail_" + kind, env_tail(kind, 900 + j), 0.75, rms=-18.0)
    print("gunshots written")


if __name__ == "__main__":
    main()
