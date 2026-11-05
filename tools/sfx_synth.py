#!/usr/bin/env python3
"""Mechanical, foley and impact sounds for Block Royale (no samples).

Reloads are built per weapon type from what really happens: the release
button clicks, the magazine unseats and slides out, a hand pulls a fresh one
from a pouch, it scrapes into the well and latches, the palm slaps it home,
the charging handle is pulled against its spring and slams the bolt forward.
Metal parts ring at their own modes; polymer thuds; fabric rustles.

Footsteps are a heel and a toe with the surface's own response (grass
rustle, gravel crunch, stone click and grit, hollow wooden planks that
sometimes creak). Bullet impacts, hits, casings, pickups and the grenade
blast follow the same idea.

Run: python3 tools/sfx_synth.py
"""
import numpy as np

import dsp
from dsp import secs, white, pink, lp, hp, bp, filt, place, strike, friction, cloth, grains, modal

# Receiver, magazine and latch pitches per weapon type (bigger = lower).
GUN = {
    "ar":      dict(rec=1350, mag=2100, latch=3700, poly=320, size=1.0),
    "smg":     dict(rec=1850, mag=2700, latch=4300, poly=380, size=0.8),
    "pistol":  dict(rec=2300, mag=3200, latch=4700, poly=420, size=0.65),
    "lmg":     dict(rec=980, mag=1500, latch=3000, poly=260, size=1.3),
    "dmr":     dict(rec=1250, mag=2000, latch=3500, poly=300, size=1.05),
    "sniper":  dict(rec=1500, mag=2400, latch=3900, poly=300, size=1.1),
    "shotgun": dict(rec=1100, mag=1600, latch=3300, poly=260, size=1.15),
}

_RNG = np.random.default_rng(7)


def _close_room(x, rng, amt=0.12):
    """Handling noise is right at your ears: a hint of body and room."""
    ir = dsp.impulse_response(rng, 0.3, 0.2, 0.09, [(0.0022, 0.35), (0.0055, 0.22), (0.011, 0.15)], density=0.6)
    return dsp.fit(dsp.convolve(x, ir, wet=amt, dry=1.0), len(x) + secs(0.12))


def click(rng, f, hard=1.0, decay=0.01, n=0.06, body=0.0, body_f=320.0, ring=0.5, ratios=dsp.BAR):
    return strike(rng, secs(n), f, ratios, decay, hard=hard, bright=min(9000, f * 2.2), body=body, body_f=body_f, ring=ring)


def thud(rng, f=220.0, decay=0.018, n=0.08, amt=1.0):
    k = secs(n)
    return lp(white(k, rng), f, 2) * dsp.env_ad(k, 0.0008, decay) * amt * 3.0


def velcro(rng, dur=0.12, amt=1.0):
    n = secs(dur)
    x = grains(rng, n, int(dur * 1100), 2500, 7500, (0.15, 0.6), (0.3, 1.0))
    return x * dsp.env_hann(n) ** 0.5 * amt


# ---------------------------------------------------------------- reloads --
def mag_out(c, rng):
    g = GUN[c]
    x = np.zeros(secs(0.5))
    place(x, click(rng, g["latch"], 0.55, 0.006, ring=0.35), 0.0)
    place(x, click(rng, g["mag"] * 0.85, 0.8, 0.01, body=0.45, body_f=g["poly"], ring=0.3, ratios=dsp.PLATE), 0.022)
    place(x, friction(rng, secs(0.1 * g["size"]), g["mag"] * 0.9, g["mag"] * 0.55, rough=0.7, q=3.0) * 0.2, 0.03)
    # Rounds and spring shift inside the free magazine.
    for k in range(3):
        place(x, click(rng, g["mag"] * rng.uniform(1.3, 2.0), 0.25, 0.004, n=0.02, ring=0.4), 0.12 + k * 0.022 + rng.uniform(0, 0.01))
    place(x, cloth(rng, secs(0.16), 1500, 0.15), 0.1)
    if c == "pistol":
        # Pistol mags drop free and clatter off the hand.
        place(x, click(rng, g["mag"] * 1.1, 0.6, 0.02, body=0.3, ring=0.6), 0.23)
        place(x, click(rng, g["mag"] * 1.25, 0.35, 0.015, ring=0.6), 0.29)
    return _close_room(x, rng)


def mag_grab(c, rng):
    g = GUN[c]
    x = np.zeros(secs(0.32))
    place(x, velcro(rng, 0.1, 0.5), 0.0)
    place(x, cloth(rng, secs(0.22), 1300, 0.6), 0.02)
    place(x, click(rng, g["mag"] * 1.1, 0.4, 0.008, body=0.3, body_f=g["poly"], ring=0.35), 0.12)
    for k in range(2):
        place(x, click(rng, g["mag"] * rng.uniform(1.4, 2.2), 0.18, 0.004, n=0.02), 0.16 + k * 0.03)
    return _close_room(x, rng)


def mag_in(c, rng):
    g = GUN[c]
    x = np.zeros(secs(0.35))
    place(x, friction(rng, secs(0.07 * g["size"]), g["mag"] * 0.6, g["mag"] * 1.05, rough=0.85, q=3.0) * 0.28, 0.0)
    seat = strike(rng, secs(0.12), g["latch"] * 0.75, dsp.PLATE, 0.018, hard=1.15, bright=7000, body=0.75, body_f=g["poly"], ring=0.45)
    place(x, seat, 0.07 * g["size"])
    place(x, click(rng, g["latch"], 0.45, 0.005, ring=0.4), 0.07 * g["size"] + 0.012)
    place(x, modal(rng, g["rec"], dsp.PLATE, secs(0.2), 0.035) * 0.12, 0.07 * g["size"])
    return _close_room(x, rng, 0.16)


def mag_slap(c, rng):
    g = GUN[c]
    x = np.zeros(secs(0.25))
    place(x, thud(rng, 320, 0.014, amt=0.9), 0.0)
    place(x, click(rng, g["mag"] * 0.9, 0.6, 0.01, body=0.6, body_f=g["poly"], ring=0.3, ratios=dsp.PLATE), 0.002)
    place(x, cloth(rng, secs(0.08), 2200, 0.2), 0.0)
    return _close_room(x, rng, 0.16)


def rack(c, rng):
    g = GUN[c]
    x = np.zeros(secs(0.42))
    # Handle pulled back against the recoil spring...
    place(x, click(rng, g["latch"] * 0.9, 0.4, 0.005, ring=0.35), 0.0)
    pull = friction(rng, secs(0.085), g["rec"] * 0.9, g["rec"] * 1.8, rough=0.9, q=3.0) * 0.38
    pull += dsp.spring(rng, secs(0.085), g["rec"] * 2.1, 0.03) * 0.15
    place(x, pull, 0.01)
    place(x, click(rng, g["rec"] * 1.3, 0.7, 0.012, body=0.3, ratios=dsp.PLATE, ring=0.35), 0.095)
    # ...and let go: the bolt slams home and the receiver rings.
    slam = strike(rng, secs(0.2), g["rec"], dsp.PLATE, 0.03, hard=1.4, bright=6500, body=0.9, body_f=g["poly"] * 1.2, ring=0.55)
    place(x, friction(rng, secs(0.03), g["rec"] * 1.8, g["rec"] * 1.1, rough=0.6) * 0.35, 0.13)
    place(x, slam, 0.16)
    return _close_room(x, rng, 0.18)


def slide_release(rng):
    g = GUN["pistol"]
    x = np.zeros(secs(0.3))
    place(x, click(rng, g["latch"] * 1.1, 0.35, 0.004, ring=0.3), 0.0)
    place(x, friction(rng, secs(0.022), 3000, 1800, rough=0.5) * 0.4, 0.008)
    place(x, strike(rng, secs(0.18), g["rec"], dsp.BAR, 0.035, hard=1.4, bright=8000, body=0.5, body_f=500, ring=0.6), 0.03)
    return _close_room(x, rng, 0.18)


def sniper_bolt(rng):
    g = GUN["sniper"]
    x = np.zeros(secs(0.62))
    place(x, click(rng, g["latch"], 0.7, 0.008, body=0.2, ring=0.4), 0.0)                       # handle up
    place(x, friction(rng, secs(0.11), 1900, 1200, rough=0.35, q=3.5) * 0.32, 0.05)                    # back
    place(x, click(rng, g["rec"] * 1.2, 0.9, 0.02, body=0.4, ratios=dsp.PLATE, ring=0.5), 0.16)  # bolt stop
    place(x, click(rng, 5200, 0.3, 0.06, n=0.1, ratios=dsp.SHELL, ring=0.9), 0.19)              # case flips out
    place(x, friction(rng, secs(0.09), 1200, 2000, rough=0.35, q=3.5) * 0.32, 0.27)                    # forward
    place(x, click(rng, g["latch"] * 0.8, 0.7, 0.01, body=0.3, ring=0.4), 0.36)                 # round chambers
    place(x, strike(rng, secs(0.18), g["rec"], dsp.PLATE, 0.03, hard=1.2, bright=6000, body=0.7, body_f=280, ring=0.45), 0.43)  # lock down
    return _close_room(x, rng, 0.18)


def shell_insert(rng):
    g = GUN["shotgun"]
    x = np.zeros(secs(0.3))
    place(x, cloth(rng, secs(0.06), 1800, 0.25), 0.0)
    place(x, friction(rng, secs(0.05), 900, 1500, rough=0.5) * 0.45, 0.02)          # hull past the gate
    place(x, click(rng, g["latch"], 0.85, 0.008, body=0.45, body_f=450, ring=0.45), 0.065)  # shell catch
    place(x, dsp.spring(rng, secs(0.05), 2400, 0.02) * 0.12, 0.07)
    place(x, thud(rng, 400, 0.01, amt=0.5), 0.07)                                     # thumb
    return _close_room(x, rng)


def shotgun_pump(rng):
    g = GUN["shotgun"]
    x = np.zeros(secs(0.42))
    place(x, friction(rng, secs(0.06), 900, 1500, rough=0.8) * 0.55, 0.0)
    place(x, strike(rng, secs(0.14), g["rec"], dsp.PLATE, 0.022, hard=1.2, bright=6000, body=0.8, body_f=260, ring=0.4), 0.06)
    place(x, click(rng, 1300, 0.35, 0.03, n=0.08, ratios=dsp.SHELL, ring=0.7), 0.075)   # hull ejects
    place(x, friction(rng, secs(0.05), 1500, 950, rough=0.8) * 0.55, 0.15)
    place(x, strike(rng, secs(0.16), g["rec"] * 1.1, dsp.PLATE, 0.025, hard=1.4, bright=6500, body=0.9, body_f=240, ring=0.45), 0.2)
    return _close_room(x, rng, 0.2)


def lmg_open(rng):
    g = GUN["lmg"]
    x = np.zeros(secs(0.45))
    place(x, click(rng, g["latch"], 0.8, 0.01, body=0.3, ring=0.4), 0.0)
    place(x, friction(rng, secs(0.14), 700, 1000, rough=0.95, q=3.0) * 0.4, 0.02)   # hinge
    place(x, strike(rng, secs(0.14), g["rec"] * 1.1, dsp.PLATE, 0.02, hard=0.8, body=0.6, ring=0.4), 0.15)
    place(x, mag_out("lmg", rng) * 0.8, 0.2)
    return x


def lmg_in(rng):
    g = GUN["lmg"]
    x = np.zeros(secs(0.5))
    place(x, mag_in("lmg", rng), 0.0)
    # The belt's links and rounds chatter as it is laid on the feed tray.
    for k in range(14):
        place(x, click(rng, rng.uniform(2600, 5200), rng.uniform(0.15, 0.4), 0.004, n=0.02, ratios=dsp.SHELL, ring=0.5), 0.18 + k * 0.017 + rng.uniform(0, 0.008))
    return x


def lmg_close(rng):
    g = GUN["lmg"]
    x = np.zeros(secs(0.35))
    place(x, strike(rng, secs(0.25), g["rec"], dsp.PLATE, 0.04, hard=1.5, bright=6000, body=1.0, body_f=230, ring=0.55), 0.0)
    place(x, click(rng, g["latch"], 0.6, 0.008, ring=0.4), 0.02)
    return _close_room(x, rng, 0.2)


# -------------------------------------------------------------- footsteps --
def _foot(rng, surface, heavy=1.0):
    n = secs(0.42)
    x = np.zeros(n)
    toe_at = rng.uniform(0.055, 0.09)
    for k, (at, amp) in enumerate([(0.0, 1.0), (toe_at, 0.55)]):
        a = amp * heavy
        if surface == "grass":
            place(x, thud(rng, 260, 0.02, amt=0.6 * a), at)
            m = secs(0.14)
            rustle = bp(pink(m, rng), rng.uniform(2500, 4200), 0.7) * dsp.env_ad(m, 0.012, 0.045) * 1.3
            place(x, rustle * a, at)
            place(x, grains(rng, secs(0.1), 30, 3000, 8000, (0.2, 0.8), (0.1, 0.4)) * a, at + 0.005)
        elif surface == "dirt":
            place(x, thud(rng, 300, 0.018, amt=0.7 * a), at)
            place(x, grains(rng, secs(0.11), 110, 1200, 6000, (0.3, 1.4), (0.15, 0.8)) * a, at)
            place(x, lp(white(secs(0.06), rng), 1800) * dsp.env_ad(secs(0.06), 0.002, 0.02) * 0.4 * a, at)
        elif surface == "stone":
            place(x, thud(rng, 180, 0.012, amt=0.6 * a), at)
            place(x, dsp.contact(rng, 0.8, 4500, 0.9) * a, at)
            place(x, bp(white(secs(0.03), rng), 3200, 1.2) * dsp.env_ad(secs(0.03), 0.0003, 0.006) * 0.7 * a, at)
            place(x, grains(rng, secs(0.07), 25, 2500, 7000, (0.2, 0.6), (0.1, 0.35)) * a, at + 0.004)
        elif surface == "wood":
            f0 = rng.uniform(170, 260)
            place(x, strike(rng, secs(0.18), f0, [1.0, 2.31, 3.86, 5.4], 0.045, hard=0.9 * a, bright=3500, body=0.6 * a, body_f=180, ring=0.9), at)
            place(x, dsp.contact(rng, 0.7, 3000, 0.5) * a, at)
    if surface == "wood" and rng.random() < 0.35:
        # Old boards creak under the weight.
        m = secs(0.16)
        cr = friction(rng, m, rng.uniform(380, 520), rng.uniform(300, 420), rough=1.0, q=6.0, grain_rate=260.0) * 0.35
        place(x, cr, 0.06)
    place(x, cloth(rng, secs(0.12), 2200, 0.06), 0.0)
    return x


# ---------------------------------------------------------------- impacts --
def impact_metal(rng):
    x = np.zeros(secs(0.6))
    f0 = rng.uniform(1500, 2400)
    place(x, strike(rng, secs(0.55), f0, dsp.PLATE, 0.16, hard=1.4, bright=9000, body=0.3, ring=0.9), 0.0)
    place(x, hp(white(secs(0.05), rng), 5000) * dsp.env_ad(secs(0.05), 0.0002, 0.01) * 0.6, 0.0)
    return x


def impact_stone(rng):
    x = np.zeros(secs(0.55))
    place(x, dsp.contact(rng, 1.2, 4000, 1.6), 0.0)
    place(x, bp(white(secs(0.04), rng), 2600, 0.8) * dsp.env_ad(secs(0.04), 0.0002, 0.009) * 1.4, 0.0)
    place(x, thud(rng, 250, 0.012, amt=0.6), 0.0)
    # Chips rain down: dense at first, then sparse.
    n = secs(0.45)
    d = np.zeros(n)
    for k in range(70):
        at = (rng.random() ** 2.2) * 0.42
        ln = secs(rng.uniform(0.0005, 0.002))
        g = bp(white(ln, rng), rng.uniform(2000, 7000), 2.0) * dsp.env_ad(ln, 0.0001, ln / dsp.SR * 0.3)
        place(d, g * rng.uniform(0.1, 0.6) * (1.0 - at * 1.5), at)
    place(x, d, 0.004)
    place(x, lp(pink(secs(0.3), rng), 1200) * dsp.env_ad(secs(0.3), 0.01, 0.08) * 0.15, 0.0)
    return x


def impact_wood(rng):
    x = np.zeros(secs(0.45))
    f0 = rng.uniform(380, 620)
    place(x, strike(rng, secs(0.25), f0, [1.0, 2.31, 3.86, 5.4], 0.035, hard=1.3, bright=4000, body=0.7, body_f=300, ring=0.9), 0.0)
    place(x, grains(rng, secs(0.12), 40, 2000, 6000, (0.3, 1.0), (0.15, 0.5)), 0.003)
    return x


def impact_dirt(rng):
    x = np.zeros(secs(0.5))
    place(x, thud(rng, 280, 0.02, amt=1.2), 0.0)
    place(x, dsp.contact(rng, 0.8, 2500, 0.6), 0.0)
    n = secs(0.35)
    d = grains(rng, n, 90, 700, 4000, (0.4, 1.8), (0.1, 0.6))
    place(x, d * np.exp(-np.arange(n) / (n * 0.35)), 0.006)
    return x


def hit_body(rng):
    x = np.zeros(secs(0.3))
    place(x, thud(rng, 180, 0.03, amt=1.6), 0.0)
    place(x, bp(white(secs(0.025), rng), 1600, 0.9) * dsp.env_ad(secs(0.025), 0.0003, 0.006) * 0.9, 0.0)
    place(x, cloth(rng, secs(0.08), 1400, 0.4), 0.0)
    return x


def hit_flesh(rng):
    x = np.zeros(secs(0.35))
    place(x, thud(rng, 140, 0.045, amt=2.0), 0.0)
    place(x, lp(white(secs(0.05), rng), 900) * dsp.env_ad(secs(0.05), 0.001, 0.012) * 0.8, 0.0)
    return x


def hit_armor(rng):
    x = np.zeros(secs(0.35))
    place(x, dsp.contact(rng, 0.6, 5000, 1.2), 0.0)
    place(x, modal(rng, rng.uniform(2600, 3400), dsp.PLATE, secs(0.3), 0.025) * 0.7, 0.0)
    place(x, thud(rng, 260, 0.02, amt=1.0), 0.0)
    place(x, grains(rng, secs(0.06), 18, 3000, 8000, (0.2, 0.6), (0.2, 0.6)), 0.002)
    return x


def hit_helmet(rng):
    x = np.zeros(secs(0.6))
    place(x, strike(rng, secs(0.4), rng.uniform(2300, 3000), dsp.PLATE, 0.11, hard=1.3, bright=9000, body=0.5, ring=0.9), 0.0)
    place(x, thud(rng, 300, 0.015, amt=0.5), 0.0)
    return x


def ricochet(rng):
    n = secs(0.55)
    t = dsp.tvec(n)
    f = 3800 * np.exp(-t * 2.6) + 900
    f *= 1 + 0.015 * np.sin(2 * np.pi * 31 * t)
    ph = 2 * np.pi * np.cumsum(f) / dsp.SR
    tone = np.sin(ph) * dsp.env_ad(n, 0.004, 0.16)
    whoosh = bp(white(n, rng), 2500, 0.8) * dsp.env_ad(n, 0.003, 0.08) * 0.3
    x = np.zeros(n)
    place(x, dsp.contact(rng, 0.8, 5000, 1.0), 0.0)
    return x + tone * 0.6 + whoosh


def bullet_whiz(rng):
    n = secs(0.32)
    t = dsp.tvec(n)
    x = dsp.sweep_bp(white(n, rng), 3200, 900, 1.6) * np.exp(-((t - 0.11) / 0.06) ** 2)
    return x


def bullet_crack(rng):
    n = secs(0.25)
    x = np.zeros(n)
    nw = dsp.friedlander(secs(0.002), 0.0003, 0.5, 1.0)
    place(x, hp(nw, 600), 0.0)
    place(x, lp(white(secs(0.15), rng), 3500) * dsp.env_ad(secs(0.15), 0.004, 0.03) * 0.12, 0.004)
    return x


# --------------------------------------------------------- handling, misc --
def empty_click(rng):
    x = np.zeros(secs(0.15))
    place(x, click(rng, 3600, 0.4, 0.005, ring=0.3), 0.0)                # trigger
    place(x, click(rng, 2400, 1.0, 0.014, body=0.3, ring=0.5), 0.012)    # hammer falls on nothing
    return _close_room(x, rng)


def equip(rng):
    x = np.zeros(secs(0.45))
    place(x, cloth(rng, secs(0.25), 1500, 0.7), 0.0)
    for k in range(3):
        place(x, click(rng, rng.uniform(3000, 5200), rng.uniform(0.25, 0.5), 0.02, n=0.05, ratios=dsp.SHELL, ring=0.8), 0.04 + k * rng.uniform(0.03, 0.06))
    place(x, strike(rng, secs(0.16), 1400, dsp.PLATE, 0.025, hard=0.8, body=0.6, body_f=300, ring=0.35), 0.2)
    return _close_room(x, rng)


def casing(rng):
    x = np.zeros(secs(0.7))
    f0 = rng.uniform(4300, 6200)
    at = 0.0
    amp = 1.0
    gap = rng.uniform(0.07, 0.1)
    for k in range(rng.integers(3, 6)):
        place(x, strike(rng, secs(0.12), f0 * rng.uniform(0.98, 1.02), dsp.SHELL, 0.07 * amp + 0.01, hard=amp, bright=9000, ring=0.9), at)
        at += gap
        gap *= rng.uniform(0.55, 0.75)
        amp *= rng.uniform(0.45, 0.65)
    place(x, friction(rng, secs(0.12), f0 * 0.5, f0 * 0.4, rough=0.9) * 0.05, at)
    return x


def shell_hull(rng):
    x = np.zeros(secs(0.5))
    at = 0.0
    amp = 1.0
    for k in range(3):
        place(x, strike(rng, secs(0.08), rng.uniform(900, 1300), dsp.SHELL, 0.015, hard=amp, bright=4000, body=0.4 * amp, body_f=500, ring=0.6), at)
        place(x, click(rng, rng.uniform(5000, 6000), 0.25 * amp, 0.02, n=0.05, ratios=dsp.SHELL), at)
        at += 0.09 * (0.6 ** k)
        amp *= 0.5
    return x


def pickup(rng):
    x = np.zeros(secs(0.35))
    place(x, cloth(rng, secs(0.2), 1700, 0.8), 0.0)
    place(x, thud(rng, 350, 0.012, amt=0.6), 0.09)
    place(x, click(rng, rng.uniform(2200, 3200), 0.3, 0.01, ratios=dsp.PLATE), 0.1)
    return _close_room(x, rng)


def ammo_pickup(rng):
    x = np.zeros(secs(0.45))
    place(x, thud(rng, 420, 0.015, amt=0.7), 0.0)
    for k in range(20):
        place(x, click(rng, rng.uniform(3000, 6500), rng.uniform(0.15, 0.55), 0.006, n=0.03, ratios=dsp.SHELL, ring=0.7), 0.01 + rng.random() ** 1.5 * 0.22)
    place(x, cloth(rng, secs(0.15), 1500, 0.4), 0.15)
    return _close_room(x, rng)


def armor_pickup(rng):
    x = np.zeros(secs(0.6))
    place(x, velcro(rng, 0.18, 0.9), 0.0)
    place(x, cloth(rng, secs(0.3), 1100, 0.9), 0.12)
    place(x, thud(rng, 200, 0.03, amt=1.0), 0.28)
    for k in range(2):
        place(x, click(rng, rng.uniform(2600, 3600), 0.5, 0.012, ring=0.5), 0.32 + k * 0.06)
    return _close_room(x, rng)


def gear_rattle(rng):
    x = np.zeros(secs(0.3))
    place(x, cloth(rng, secs(0.2), 1600, 0.5), 0.0)
    for k in range(4):
        place(x, click(rng, rng.uniform(2500, 5000), rng.uniform(0.15, 0.4), 0.01, n=0.04, ratios=dsp.SHELL, ring=0.6), rng.uniform(0.0, 0.15))
    return x


def jump(rng):
    x = np.zeros(secs(0.35))
    place(x, cloth(rng, secs(0.25), 1200, 1.0), 0.0)
    place(x, gear_rattle(rng) * 0.6, 0.02)
    return x


def land_thud(rng):
    x = np.zeros(secs(0.5))
    place(x, thud(rng, 120, 0.05, amt=2.0), 0.0)
    place(x, thud(rng, 300, 0.02, amt=0.8), 0.0)
    place(x, grains(rng, secs(0.15), 60, 1200, 5000, (0.3, 1.2), (0.1, 0.5)), 0.003)
    place(x, gear_rattle(rng) * 0.7, 0.01)
    return x


def explosion(rng):
    n = secs(3.2)
    dry = np.zeros(n)
    place(dry, dsp.friedlander(secs(0.12), 0.0032, 1.3, 0.7) * 1.6, 0.0)
    place(dry, lp(pink(secs(0.9), rng), 900, 2) * dsp.env_ad(secs(0.9), 0.004, 0.16) * 0.9, 0.0)
    place(dry, lp(dsp.brown(secs(1.2), rng), 120) * dsp.env_ad(secs(1.2), 0.01, 0.3) * 0.8, 0.0)
    # Dirt and stones falling back.
    debris = np.zeros(secs(1.6))
    for k in range(160):
        at = 0.15 + rng.random() ** 1.6 * 1.3
        ln = secs(rng.uniform(0.0006, 0.003))
        g = bp(white(ln, rng), rng.uniform(800, 5000), 2.0) * dsp.env_ad(ln, 0.0001, ln / dsp.SR * 0.3)
        place(debris, g * rng.uniform(0.05, 0.35), at)
    place(dry, debris, 0.0)
    early = [(0.005, 0.6), (0.03, 0.4), (0.09, 0.3), (0.3, 0.25), (0.7, 0.18), (1.2, 0.12)]
    ir = dsp.impulse_response(rng, 3.0, 2.6, 0.6, early, 1.2, 0.01)
    wet = dsp.fit(dsp.convolve(dry, ir, wet=0.5, dry=1.0), n)
    wet = wet / (np.max(np.abs(wet)) + 1e-9)
    wet = dsp.compress(wet, -14.0, 3.0, 0.001, 0.15, 4.0)
    return dsp.soft_clip(wet, 1.5)


def hitmarker(rng):
    x = np.zeros(secs(0.12))
    place(x, dsp.contact(rng, 0.4, 6000, 0.6), 0.0)
    place(x, modal(rng, 3400, [1.0, 2.1], secs(0.1), 0.018) * 0.7, 0.0)
    return x


def headshot(rng):
    x = np.zeros(secs(0.45))
    place(x, dsp.contact(rng, 0.5, 7000, 0.9), 0.0)
    place(x, modal(rng, 4200, [1.0, 1.51, 2.02], secs(0.4), 0.12, detune=0.0) * 0.8, 0.0)
    place(x, thud(rng, 220, 0.02, amt=0.6), 0.0)
    return x


# ------------------------------------------------------------------ write --
def main():
    r = np.random.default_rng(1234)
    for c in ["ar", "smg", "pistol", "dmr"]:
        dsp.write("rl_%s_out" % c, mag_out(c, r), 0.85, rms=-19.0)
        dsp.write("rl_%s_grab" % c, mag_grab(c, r), 0.6, rms=-19.0)
        dsp.write("rl_%s_in" % c, mag_in(c, r), 0.9, rms=-19.0)
        dsp.write("rl_%s_slap" % c, mag_slap(c, r), 0.75, rms=-19.0)
        dsp.write("rl_%s_rack" % c, rack(c, r) if c != "pistol" else slide_release(r), 0.9, rms=-19.0)
    dsp.write("rl_lmg_out", lmg_open(r), 0.85, rms=-19.0)
    dsp.write("rl_lmg_grab", mag_grab("lmg", r), 0.6, rms=-19.0)
    dsp.write("rl_lmg_in", lmg_in(r), 0.9, rms=-19.0)
    dsp.write("rl_lmg_slap", lmg_close(r), 0.9, rms=-19.0)
    dsp.write("rl_lmg_rack", rack("lmg", r), 0.9, rms=-19.0)
    dsp.write("rl_sniper_out", mag_out("sniper", r), 0.85, rms=-19.0)
    dsp.write("rl_sniper_grab", mag_grab("sniper", r), 0.6, rms=-19.0)
    dsp.write("rl_sniper_in", mag_in("sniper", r), 0.9, rms=-19.0)
    dsp.write("rl_sniper_slap", mag_slap("sniper", r), 0.7, rms=-19.0)
    dsp.write("rl_sniper_rack", sniper_bolt(r), 0.9, rms=-19.0)
    dsp.write("bolt", sniper_bolt(r), 0.9, rms=-18.0)
    dsp.write("rl_shotgun_shell", shell_insert(r), 0.85, rms=-19.0)
    dsp.write("rl_shotgun_pump", shotgun_pump(r), 0.92, rms=-19.0)
    # Legacy names still used by bots and older code paths.
    dsp.write("reload_out", mag_out("ar", r), 0.85, rms=-19.0)
    dsp.write("reload_in", mag_in("ar", r), 0.9, rms=-19.0)
    for surf, heavy in [("grass", 1.0), ("dirt", 1.0), ("stone", 1.0), ("wood", 1.0)]:
        for k in range(4):
            dsp.write("step_%s_%d" % (surf, k + 1), _foot(r, surf, heavy), 0.55, rms={"grass": -20.0, "dirt": -20.0, "stone": -21.0, "wood": -19.0}[surf])
    dsp.write("impact_metal", impact_metal(r), 0.85, rms=-18.0)
    dsp.write("impact_stone", impact_stone(r), 0.85, rms=-17.0)
    dsp.write("impact_wood", impact_wood(r), 0.85, rms=-17.0)
    dsp.write("bullet_impact", impact_dirt(r), 0.85, rms=-17.0)
    dsp.write("hit_body", hit_body(r), 0.9, rms=-14.0)
    dsp.write("hit_flesh", hit_flesh(r), 0.9, rms=-14.0)
    dsp.write("hit_armor", hit_armor(r), 0.9, rms=-15.0)
    dsp.write("hit_helmet", hit_helmet(r), 0.9, rms=-15.0)
    dsp.write("ricochet", ricochet(r), 0.7, rms=-17.0)
    dsp.write("bullet_whiz", bullet_whiz(r), 0.75, rms=-16.0)
    dsp.write("bullet_crack", bullet_crack(r), 0.9, rms=-14.0)
    dsp.write("empty_click", empty_click(r), 0.8, rms=-16.0)
    dsp.write("equip", equip(r), 0.8, rms=-15.0)
    for k in range(3):
        dsp.write("casing_%d" % (k + 1), casing(r), 0.7, rms=-20.0)
    dsp.write("shell_hull", shell_hull(r), 0.7, rms=-20.0)
    dsp.write("pickup", pickup(r), 0.75, rms=-16.0)
    dsp.write("ammo_pickup", ammo_pickup(r), 0.75, rms=-16.0)
    dsp.write("armor_pickup", armor_pickup(r), 0.8, rms=-15.0)
    dsp.write("gear_rattle", gear_rattle(r), 0.6, rms=-20.0)
    dsp.write("jump", jump(r), 0.6, rms=-19.0)
    dsp.write("land_thud", land_thud(r), 0.85, rms=-11.0)
    dsp.write("explosion", explosion(r), 0.95, rms=-9.0)
    dsp.write("hitmarker", hitmarker(r), 0.7, rms=-13.0)
    dsp.write("headshot", headshot(r), 0.8, rms=-13.0)
    print("sfx written")


if __name__ == "__main__":
    main()
