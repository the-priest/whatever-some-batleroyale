#!/usr/bin/env python3
"""Gunshot sounds for Block Royale, built the way game gunfire is designed:
layers, each doing one job, glued together and squashed hard.

  snap   the first millisecond: a broadband click that makes it a gunshot
  bark   the muzzle blast's character: noise through a few resonant bands
         (the gun's "voice"), a fast decay with a short ringing tail
  body   low-mid boom under the bark
  punch  the sub kick you feel: a sine dropping in pitch
  action bolt carrier back and forward, sear click (your own gun mostly)
  space  ground bounce, nearby surfaces, a short outdoor decay

Three distances for other people's guns, chosen and crossfaded at runtime:
  shot_<snd>_<1..4>   close (up to ~150 m): the full shot, mono
  shot_<snd>_far      a few hundred metres: the high end eaten by the air,
                      a softer pop and the valley rolling it back for seconds
  shot_<snd>_vfar     across the island: a dull thump inside its own echo
and one for your own: shot_<snd>_fp_<1..3>, the close shot in wide stereo with
the action right in your hands.

tail_<env>.wav are the surroundings' answer alone (field, forest, town,
indoors), in stereo, layered at runtime around the listener.

Run: python3 tools/gunshot_synth.py
"""
import numpy as np

import dsp
from dsp import secs, white, lp, hp, filt, place

# bark: resonant bands (Hz) and their gains; dec: bark decay (s); body: low
# boom level, its low-pass and decay; punch: sub kick level, start and end
# pitch, decay; snap: transient level; mech: action loudness; carrier: bolt
# metal pitch; auto: reciprocating bolt; tail: outdoor space; drive: how hard
# it is squashed.
GUNS = {
    "ak":      dict(bark=(620, 1300, 2600, 5000), bg=(1.0, 0.95, 0.62, 0.3), dec=0.017, body=0.95, body_f=480, body_dec=0.075,
                    punch=0.8, p0=155, p1=46, p_dec=0.075, snap=0.85, mech=0.75, carrier=1350, auto=True, tail=1.0, drive=2.4),
    "rifle":   dict(bark=(780, 1650, 3300, 6200), bg=(0.85, 1.0, 0.75, 0.38), dec=0.012, body=0.72, body_f=560, body_dec=0.06,
                    punch=0.62, p0=170, p1=52, p_dec=0.06, snap=1.0, mech=0.7, carrier=1750, auto=True, tail=0.95, drive=2.3),
    "smg":     dict(bark=(950, 2100, 4100, 7200), bg=(0.75, 1.0, 0.8, 0.42), dec=0.0085, body=0.48, body_f=650, body_dec=0.045,
                    punch=0.38, p0=190, p1=62, p_dec=0.045, snap=0.9, mech=0.9, carrier=2300, auto=True, tail=0.75, drive=2.1),
    "pistol":  dict(bark=(880, 1950, 3900, 6800), bg=(0.85, 1.0, 0.72, 0.36), dec=0.0095, body=0.55, body_f=600, body_dec=0.05,
                    punch=0.45, p0=180, p1=58, p_dec=0.05, snap=1.0, mech=0.75, carrier=2600, auto=True, tail=0.8, drive=2.2),
    "shotgun": dict(bark=(420, 900, 1900, 3800), bg=(1.0, 0.9, 0.55, 0.25), dec=0.03, body=1.15, body_f=380, body_dec=0.12,
                    punch=1.0, p0=130, p1=40, p_dec=0.11, snap=0.7, mech=0.35, carrier=1100, auto=False, tail=1.15, drive=2.6),
    "lmg":     dict(bark=(600, 1250, 2500, 4800), bg=(1.0, 0.95, 0.6, 0.28), dec=0.018, body=1.0, body_f=470, body_dec=0.08,
                    punch=0.85, p0=150, p1=45, p_dec=0.08, snap=0.85, mech=0.8, carrier=1250, auto=True, tail=1.05, drive=2.5),
    "dmr":     dict(bark=(700, 1450, 2900, 5600), bg=(1.0, 0.95, 0.7, 0.33), dec=0.021, body=1.0, body_f=470, body_dec=0.09,
                    punch=0.9, p0=150, p1=44, p_dec=0.09, snap=1.0, mech=0.6, carrier=1500, auto=True, tail=1.2, drive=2.5),
    "sniper":  dict(bark=(560, 1150, 2350, 4600), bg=(1.0, 0.95, 0.65, 0.3), dec=0.028, body=1.2, body_f=420, body_dec=0.12,
                    punch=1.05, p0=140, p1=40, p_dec=0.12, snap=1.0, mech=0.2, carrier=1200, auto=False, tail=1.45, drive=2.7),
}


def _env(n, attack, dec, tail_k=0.0, tail_dec=0.0):
    t = dsp.tvec(n)
    a = np.minimum(1.0, t / max(attack, 1e-5))
    e = np.exp(-t / dec)
    if tail_k > 0.0:
        e = e + tail_k * np.exp(-t / tail_dec)
    return a * e


def _snap(rng, g):
    n = secs(0.006)
    x = hp(white(n, rng), 1800, 2) * _env(n, 0.00005, 0.00045)
    x[0] += 0.6
    return x * g["snap"]


def _bark(rng, g, k=1.0, dec_k=1.0):
    """The gun's voice: a noise burst through its resonant bands."""
    n = secs(0.45)
    src = white(n, rng)
    x = np.zeros(n)
    for f, gain in zip(g["bark"], g["bg"]):
        f2 = f * k * rng.uniform(0.96, 1.04)
        # Equal gain per band, not per Hz: a constant-Q band of noise
        # carries more energy the higher it sits.
        x += filt(src, "bp", f2, 1.35) * gain * np.sqrt(700.0 / f2)
    dec = g["dec"] * dec_k * rng.uniform(0.9, 1.1)
    x *= _env(n, 0.00025, dec, 0.14, dec * 5.5)
    return np.tanh(x * 2.2)


def _body(rng, g, dec_k=1.0):
    n = secs(0.6)
    x = hp(lp(dsp.pink(n, rng), g["body_f"], 2), 85, 2) * _env(n, 0.0012, g["body_dec"] * dec_k, 0.18, g["body_dec"] * 3.0 * dec_k)
    return x * g["body"] * 2.2


def _punch(rng, g):
    n = secs(0.5)
    t = dsp.tvec(n)
    p0 = g["p0"] * rng.uniform(0.95, 1.05)
    f = g["p1"] + (p0 - g["p1"]) * np.exp(-t / 0.022)
    ph = 2 * np.pi * np.cumsum(f) / dsp.SR
    x = np.sin(ph) * _env(n, 0.0008, g["p_dec"])
    return np.tanh(x * 1.6) * g["punch"]


def _action(rng, g):
    """Bolt carrier slamming back and forward, receiver ringing."""
    n = secs(0.18)
    x = np.zeros(n)
    sear = dsp.strike(rng, secs(0.03), 3800, dsp.BAR, 0.006, hard=0.25, bright=7000, ring=0.3)
    place(x, sear, 0.0)
    if g["auto"]:
        back = dsp.strike(rng, secs(0.06), g["carrier"], dsp.PLATE, 0.012, hard=0.75, bright=5500, body=0.5, body_f=420, ring=0.25)
        fwd = dsp.strike(rng, secs(0.07), g["carrier"] * 1.12, dsp.PLATE, 0.016, hard=0.95, bright=6000, body=0.6, body_f=380, ring=0.25)
        slide = dsp.friction(rng, secs(0.018), 2200, 1500, rough=0.6) * 0.3
        place(x, slide, 0.010)
        place(x, back, 0.017 + rng.uniform(0, 0.004))
        place(x, fwd, 0.048 + rng.uniform(0, 0.006))
        x += dsp.modal(rng, g["carrier"] * 0.62, dsp.SHELL, n, 0.03) * 0.1
    return x * g["mech"]


def _norm(x, win_s):
    k = max(1, secs(win_s))
    return x / (np.sqrt(np.mean(x[:k] ** 2)) + 1e-9)


# Layer levels (linear, against each layer's own RMS over its first few
# tens of milliseconds): the bark leads, the body and punch sit under it.
MIX = dict(snap=0.55, bark=1.0, body=0.32, punch=0.42)


def _dry(rng, g, mech=0.0, mix=None):
    """Snap, bark, body and punch, glued: the shot with no space around it."""
    m = dict(MIX, **(mix or {}))
    n = secs(0.7)
    x = np.zeros(n)
    t0 = 0.002
    snap = _snap(rng, g)
    place(x, snap / (np.max(np.abs(snap)) + 1e-9) * m["snap"] * g["snap"], t0)
    place(x, _norm(_bark(rng, g), 0.02) * m["bark"], t0)
    place(x, _norm(_body(rng, g), 0.06) * m["body"] * g["body"], t0 + 0.0004)
    place(x, _norm(_punch(rng, g), 0.06) * m["punch"] * g["punch"], t0 + 0.0006)
    if mech > 0.0:
        a = _action(rng, g)
        place(x, a / (np.max(np.abs(a)) + 1e-9) * 0.5 * mech * g["mech"], 0.0)
    x = hp(x, 32, 2)
    # Squash like a close-mic'd recording, then saturate: dense and loud.
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = dsp.compress(x, thresh_db=-20.0, ratio=4.0, attack=0.0003, release=0.05, makeup_db=6.0)
    return dsp.soft_clip(x, g["drive"])


def _space_ir(rng, g, stereo, length=1.1):
    early = [(0.0045, 0.5), (0.012, 0.28), (0.031, 0.22), (0.055, 0.17), (0.09, 0.13), (0.15, 0.09)]
    return dsp.impulse_response(rng, length, 1.1 * g["tail"], 0.3 * g["tail"], early, density=1.2, pre=0.008, stereo=stereo)


def close_shot(cls, seed):
    g = GUNS[cls]
    rng = np.random.default_rng(seed)
    dry = _dry(rng, g, mech=0.35)
    wet = dsp.convolve(dry, _space_ir(rng, g, False), wet=0.3 * g["tail"], dry=1.0)
    wet = dsp.fit(wet, secs(1.2))
    wet = filt(wet, "peak", 3000, 0.8, 2.0)
    wet = wet / (np.max(np.abs(wet)) + 1e-9)
    return dsp.soft_clip(dsp.compress(wet, -14.0, 3.0, 0.0005, 0.08, 3.0), 1.4)


def fp_shot(cls, seed):
    """Your own gun: the same shot with the action in your hands and the
    reflections spread around you."""
    g = GUNS[cls]
    rng = np.random.default_rng(seed + 5000)
    dry = _dry(rng, g, mech=1.0)
    ir = _space_ir(rng, g, True, 1.3)
    wet = dsp.convolve(dry, ir, wet=0.34 * g["tail"], dry=1.0)
    wet = np.stack([dsp.fit(wet[0], secs(1.4)), dsp.fit(wet[1], secs(1.4))])
    wet = np.stack([filt(c, "peak", 3000, 0.8, 2.0) for c in wet])
    wet = filt_st(wet, "ls", 90, 0.8, 1.0)
    wet = wet / (np.max(np.abs(wet)) + 1e-9)
    return dsp.soft_clip(dsp.compress(wet, -14.0, 3.0, 0.0005, 0.08, 3.0), 1.4)


def filt_st(x, kind, f, q, gdb):
    return np.stack([filt(c, kind, f, q, gdb) for c in x])


def _distant(cls, seed, lp_f, smear_ms, wet_k, rt, n_secs, tag):
    g = GUNS[cls]
    rng = np.random.default_rng(seed)
    n = secs(n_secs)
    src = np.zeros(secs(0.8))
    # Far off the bark is lower and longer (the high partials are gone and
    # the pressure wave has spread), the body carries, no snap or action.
    place(src, _norm(_bark(rng, g, k=0.8, dec_k=1.8), 0.03), 0.0)
    place(src, _norm(_body(rng, g, dec_k=1.3), 0.08) * 0.45 * g["body"], 0.0)
    place(src, _norm(_punch(rng, g), 0.08) * 0.2 * g["punch"], 0.0)
    # Air absorption: highs go first, then the upper mids.
    src = lp(src, lp_f, 2)
    src = filt(src, "hs", lp_f * 0.45, 0.7, -6.0)
    # The front is no longer a wall: it swells in over a few milliseconds.
    src *= np.minimum(1.0, dsp.tvec(len(src)) / (smear_ms * 0.001))
    # The valley answers: hills and treelines at a few hundred metres roll it
    # back for seconds, each echo darker and more smeared than the last.
    early = [(0.004, 0.55), (0.16, 0.5), (0.31, 0.42), (0.52, 0.36), (0.78, 0.3), (1.05, 0.25),
             (1.4, 0.2), (1.85, 0.15), (2.4, 0.1)]
    ir = dsp.impulse_response(rng, n_secs - 0.3, rt * g["tail"], rt * 0.3 * g["tail"], early, density=1.6, pre=0.06)
    x = dsp.fit(dsp.convolve(src, ir, wet=wet_k, dry=1.0), n)
    x = lp(x, lp_f * 1.3)
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = dsp.compress(x, thresh_db=-18.0, ratio=3.0, attack=0.003, release=0.25, makeup_db=6.0)
    return dsp.soft_clip(x, 1.3)


def far_shot(cls, seed):
    return _distant(cls, seed + 1000, 2600, 2.5, 0.85, 2.6, 3.6, "far")


def vfar_shot(cls, seed):
    return _distant(cls, seed + 2000, 1000, 7.0, 1.3, 3.2, 4.2, "vfar")


def env_tail(kind, seed):
    """The surroundings' answer alone (no direct sound), in stereo."""
    rng = np.random.default_rng(seed)
    if kind == "field":
        early = [(0.22, 0.5), (0.48, 0.4), (0.8, 0.3), (1.2, 0.2), (1.7, 0.13)]
        ir = dsp.impulse_response(rng, 2.8, 2.4, 0.7, early, 0.9, 0.1, stereo=True)
        f_lp = 1800
    elif kind == "forest":
        early = [(0.03, 0.45), (0.055, 0.4), (0.09, 0.35), (0.14, 0.3), (0.21, 0.24), (0.3, 0.18)]
        ir = dsp.impulse_response(rng, 2.1, 1.5, 0.45, early, 1.3, 0.02, stereo=True)
        f_lp = 2800
    elif kind == "town":
        early = [(0.016, 0.6), (0.032, 0.52), (0.055, 0.46), (0.09, 0.38), (0.15, 0.3), (0.24, 0.22), (0.36, 0.15)]
        ir = dsp.impulse_response(rng, 1.9, 1.3, 0.42, early, 1.2, 0.01, stereo=True)
        f_lp = 4200
    else:  # indoors: dense, bright, short and loud
        early = [(0.003, 0.8), (0.0055, 0.72), (0.009, 0.64), (0.014, 0.52), (0.021, 0.44), (0.03, 0.36)]
        ir = dsp.impulse_response(rng, 0.95, 0.6, 0.24, early, 1.7, 0.0, stereo=True)
        f_lp = 6500
    ir[:, : secs(0.002)] = 0.0  # no direct sound
    g = GUNS["rifle"]
    burst = _dry(rng, g)[: secs(0.12)]
    x = np.stack([lp(dsp.convolve(burst, ir[c], wet=1.0, dry=0.0), f_lp) for c in range(2)])
    return dsp.soft_clip(x / (np.max(np.abs(x)) + 1e-9), 1.3)


LOUD = {"sniper": -11.0, "shotgun": -11.5, "dmr": -12.0, "lmg": -12.5, "ak": -12.5, "rifle": -13.0, "smg": -14.0, "pistol": -14.0}


def main():
    for i, cls in enumerate(GUNS):
        loud = LOUD[cls]
        for v in range(4):
            x = close_shot(cls, 100 * i + v)
            dsp.write("shot_%s_%d" % (cls, v + 1), x, 0.95, rms=loud)
            if v == 0:
                dsp.write("shot_" + cls, x, 0.95, rms=loud)
        for v in range(3):
            dsp.write("shot_%s_fp_%d" % (cls, v + 1), fp_shot(cls, 100 * i + v), 0.95, rms=loud + 0.5)
        dsp.write("shot_%s_far" % cls, far_shot(cls, i), 0.9, rms=-13.0)
        dsp.write("shot_%s_vfar" % cls, vfar_shot(cls, i), 0.9, rms=-14.0)
    for j, kind in enumerate(["field", "forest", "town", "indoor"]):
        dsp.write("tail_" + kind, env_tail(kind, 900 + j), 0.8, rms=-17.0)
    print("gunshots written")


if __name__ == "__main__":
    main()
