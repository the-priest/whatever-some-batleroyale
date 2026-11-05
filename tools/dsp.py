"""Shared sound-design building blocks for Block Royale's synthesized audio.

Everything is generated from first principles, no samples:
  * modal synthesis: struck metal, wood and polymer parts ring at their own
    (inharmonic) modes, each with its own decay
  * contact transients: the sub-millisecond click when two hard parts meet
  * friction: band-passed noise riding a sweep with stick-slip micro-impulses
  * Friedlander blast waves: the pressure shape of a muzzle blast or explosion
  * synthetic impulse responses: early reflections plus a diffuse tail whose
    highs die faster than its lows, applied by convolution
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gen")


# ------------------------------------------------------------------ basics --
def secs(n):
    return int(n * SR)


def tvec(n):
    return np.arange(n) / SR


def white(n, rng):
    return rng.normal(0.0, 1.0, n)


def pink(n, rng):
    # Voss-McCartney approximation via filtering white noise.
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, white(n, rng)) * 6.0


def brown(n, rng):
    x = np.cumsum(white(n, rng))
    x = signal.lfilter([1, -1], [1, -0.995], x)
    return x / (np.std(x) + 1e-9)


def biquad(kind, f, q=0.707, g=0.0):
    f = min(max(f, 10.0), SR * 0.49)
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
    elif kind == "peak":
        b, aa = [1 + a * A, -2 * c, 1 - a * A], [1 + a / A, -2 * c, 1 - a / A]
    elif kind == "hs":
        sq = 2 * np.sqrt(A) * a
        b = [A * ((A + 1) + (A - 1) * c + sq), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sq)]
        aa = [(A + 1) - (A - 1) * c + sq, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sq]
    elif kind == "ls":
        sq = 2 * np.sqrt(A) * a
        b = [A * ((A + 1) - (A - 1) * c + sq), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sq)]
        aa = [(A + 1) + (A - 1) * c + sq, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sq]
    else:
        raise ValueError(kind)
    return np.array(b) / aa[0], np.array(aa) / aa[0]


def filt(x, kind, f, q=0.707, g=0.0):
    b, a = biquad(kind, f, q, g)
    return signal.lfilter(b, a, x)


def lp(x, f, order=1):
    for _ in range(order):
        x = filt(x, "lp", f)
    return x


def hp(x, f, order=1):
    for _ in range(order):
        x = filt(x, "hp", f)
    return x


def bp(x, f, q=1.0):
    return filt(x, "bp", f, q)


def sweep_bp(x, f0, f1, q=2.0, block=128):
    """Band-pass whose centre glides from f0 to f1 (log), processed in blocks."""
    out = np.zeros_like(x)
    n = len(x)
    zi = None
    for i in range(0, n, block):
        fr = f0 * (f1 / f0) ** (i / max(1, n))
        b, a = biquad("bp", fr, q)
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0.0
        seg, zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
        out[i:i + block] = seg
    return out


def env_ad(n, attack, decay, curve=1.0):
    t = tvec(n)
    a = np.minimum(1.0, t / max(attack, 1e-6)) ** curve
    return a * np.exp(-np.maximum(0.0, t - attack) / max(decay, 1e-6))


def env_hann(n):
    return np.hanning(n) if n > 2 else np.ones(n)


def place(buf, x, at, gain=1.0):
    s = int(at * SR)
    if s >= len(buf) or s + len(x) <= 0:
        return buf
    if s < 0:
        x = x[-s:]
        s = 0
    e = min(len(buf), s + len(x))
    buf[s:e] += x[:e - s] * gain
    return buf


def fit(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


# ---------------------------------------------------------------- physics --
BAR = [1.0, 2.756, 5.404, 8.933, 13.34]      # free-free bar
PLATE = [1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.16, 3.50]  # thin plate (approx.)
SHELL = [1.0, 1.47, 1.89, 2.41, 2.90, 3.36]  # short tube / casing


def modal(rng, f0, ratios, n, decay, amps=None, detune=0.02, decay_tilt=0.7, phase_rand=True):
    """Sum of exponentially decaying sines: a struck object ringing."""
    t = tvec(n)
    out = np.zeros(n)
    for i, r in enumerate(ratios):
        fr = f0 * r * (1.0 + rng.uniform(-detune, detune))
        if fr > SR * 0.45:
            continue
        a = amps[i] if amps is not None and i < len(amps) else 1.0 / (1.0 + i * 0.7)
        tau = decay * (decay_tilt ** i)
        ph = rng.uniform(0, 2 * np.pi) if phase_rand else 0.0
        out += a * np.sin(2 * np.pi * fr * t + ph) * np.exp(-t / tau)
    return out


def contact(rng, n_ms=0.6, bright=6000.0, hard=1.0):
    """The click of two hard surfaces meeting: a tiny broadband burst."""
    n = max(8, int(n_ms * 0.001 * SR))
    x = white(n, rng) * env_ad(n, 0.00005, n_ms * 0.00025)
    x = hp(x, bright * 0.35)
    return x * hard


def strike(rng, n, f0, ratios, decay, hard=1.0, bright=6000.0, body=0.0, body_f=300.0, ring=0.6):
    """Contact transient exciting a set of modes (+ optional low body thump)."""
    x = np.zeros(n)
    c = contact(rng, 0.5 + rng.uniform(0, 0.5), bright, hard)
    x[:len(c)] += c
    x += modal(rng, f0, ratios, n, decay) * ring * hard
    if body > 0:
        bn = min(n, secs(0.06))
        th = lp(white(bn, rng), body_f, 2) * env_ad(bn, 0.0008, 0.012) * body
        x[:bn] += th
    return x


def friction(rng, n, f0, f1, rough=0.5, q=1.6, grain_rate=900.0):
    """Sliding contact: filtered noise along a sweep + stick-slip ticks."""
    x = sweep_bp(white(n, rng), f0, f1, q)
    if rough > 0:
        ticks = np.zeros(n)
        k = int(grain_rate * n / SR)
        for _ in range(k):
            i = rng.integers(0, n)
            ticks[i] += rng.uniform(-1, 1)
        ticks = bp(ticks, (f0 + f1) * 0.5 * 1.6, 1.2) * 6.0
        x = x * (1 - rough * 0.5) + ticks * rough
    return x * env_hann(n) ** 0.6


def spring(rng, n, f=2600.0, decay=0.06):
    """A coil spring twanging: a dispersive, slightly chirped ring."""
    t = tvec(n)
    fr = f * (1.0 + 0.08 * np.exp(-t * 40))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    x = np.sin(ph) * np.exp(-t / decay) + 0.4 * np.sin(ph * 2.31) * np.exp(-t / (decay * 0.6))
    return x * 0.5


def friedlander(n, td, b=1.4, neg=1.0):
    """Blast-wave pressure: instant rise, decay through zero to a suction phase."""
    t = tvec(n)
    p = (1 - t / td) * np.exp(-b * t / td)
    p[t > td * 6] *= np.exp(-(t[t > td * 6] - td * 6) / (td * 3))
    p[p < 0] *= neg
    return p


def cloth(rng, n, f=1800.0, amt=1.0):
    """Fabric moving: soft broadband rustle with a slow swell."""
    x = bp(pink(n, rng), f, 0.6) + hp(white(n, rng), 3000) * 0.25
    return x * env_hann(n) ** 1.2 * amt


def grains(rng, n, count, f_lo, f_hi, dur_ms=(0.4, 2.0), amp=(0.2, 1.0), spread=1.0):
    """Many tiny impacts (gravel, debris, grit)."""
    out = np.zeros(n)
    span = int(n * spread)
    for _ in range(count):
        ln = int(rng.uniform(*dur_ms) * 0.001 * SR)
        s = rng.integers(0, max(1, span - ln))
        g = bp(white(ln, rng), rng.uniform(f_lo, f_hi), 2.0) * env_ad(ln, 0.0001, ln / SR * 0.3)
        out[s:s + ln] += g * rng.uniform(*amp)
    return out


# ------------------------------------------------------------- ambience --
def impulse_response(rng, length, rt_low, rt_high, early=(), density=1.0, pre=0.0, stereo=False):
    """Synthetic room/outdoor IR: discrete early reflections, then diffuse
    decay in four bands (highs fade sooner than lows)."""
    n = secs(length)
    t = tvec(n)
    chans = []
    for ch in range(2 if stereo else 1):
        r = np.random.default_rng(rng.integers(1 << 30) + ch)
        x = np.zeros(n)
        x[0] = 1.0
        for (d, g) in early:
            i = int((d + r.uniform(-0.0015, 0.0015)) * SR)
            if not 0 < i < n:
                continue
            amp = g * r.uniform(0.75, 1.0) * (1 if r.random() > 0.3 else -1)
            if d < 0.012:
                # Close, hard surface (the ground): a clean mirror image.
                x[i] += amp
                continue
            # Further surfaces (walls, trees, hills) scatter: the echo arrives
            # smeared over time and darker the further it travelled.
            ln = int(min(0.06, max(0.004, d * 0.12)) * SR)
            burst = white(ln, r) * np.exp(-np.arange(ln) / (ln * 0.35))
            burst = lp(burst, 9000.0 / (1.0 + d * 6.0), 2)
            burst *= amp / (np.sqrt(np.sum(burst ** 2)) + 1e-9)
            e = min(n, i + ln)
            x[i:e] += burst[:e - i]
        tail = np.zeros(n)
        bands = [(60, 250), (250, 1000), (1000, 4000), (4000, 12000)]
        for k, (lo, hi) in enumerate(bands):
            rt = rt_low * (rt_high / rt_low) ** (k / 3.0)
            nz = white(n, r)
            nz = filt(filt(nz, "hp", lo), "lp", hi)
            tail += nz * np.exp(-6.91 * t / rt)
        onset = np.minimum(1.0, np.maximum(0.0, t - pre) / 0.012)
        x += tail * onset * 0.02 * density
        chans.append(x)
    return np.stack(chans) if stereo else chans[0]


def convolve(x, ir, wet=0.3, dry=1.0):
    if ir.ndim == 2:
        out = [dry * fit(x, len(x) + ir.shape[1] - 1) + wet * signal.fftconvolve(x, ir[c]) for c in range(2)]
        return np.stack(out)
    return dry * fit(x, len(x) + len(ir) - 1) + wet * signal.fftconvolve(x, ir)


# ------------------------------------------------------------- dynamics --
def compress(x, thresh_db=-18.0, ratio=4.0, attack=0.002, release=0.08, makeup_db=0.0):
    """Feed-forward peak compressor (per sample envelope)."""
    mono = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    a_att = np.exp(-1.0 / (attack * SR))
    a_rel = np.exp(-1.0 / (release * SR))
    env = np.zeros_like(mono)
    e = 0.0
    for i, v in enumerate(mono):
        e = a_att * e + (1 - a_att) * v if v > e else a_rel * e + (1 - a_rel) * v
        env[i] = e
    lvl = 20 * np.log10(env + 1e-9)
    over = np.maximum(0.0, lvl - thresh_db)
    gain_db = -over * (1 - 1 / ratio) + makeup_db
    g = 10 ** (gain_db / 20)
    return x * g


def soft_clip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def fade(x, fin=0.0, fout=0.01):
    n = x.shape[-1]
    a = int(fin * SR)
    b = int(fout * SR)
    w = np.ones(n)
    if a > 0:
        w[:a] = np.linspace(0, 1, a)
    if b > 0:
        w[-b:] *= np.linspace(1, 0, b)
    return x * w


def trim_silence(x, thresh=0.0008, tail=0.02):
    m = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    idx = np.where(m > thresh * np.max(m))[0]
    if len(idx) == 0:
        return x
    end = min(len(m), idx[-1] + secs(tail))
    return x[..., :end]


def rms_db(x, win=0.3):
    k = min(x.shape[-1], secs(win))
    seg = x[..., :k]
    return 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-12)


def write(name, x, peak=0.89, out_dir=None, rms=None):
    """Normalise to `peak` (or to an RMS loudness over the first 0.3 s when
    `rms` is given, limiting any overs smoothly), short fades, 16-bit WAV."""
    x = np.asarray(x, dtype=np.float64)
    x = x - (np.mean(x, axis=-1, keepdims=True) if x.ndim == 2 else np.mean(x))
    x = fade(trim_silence(x), 0.0, 0.006)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    if rms is not None:
        for _ in range(4):
            x *= 10 ** ((rms - rms_db(x)) / 20.0)
            over = np.max(np.abs(x))
            if over > 0.97:
                # Smooth limiter: transparent below ~0.6, rounds the overs.
                knee = 0.6
                a = np.abs(x)
                y = np.where(a <= knee, a, knee + (0.97 - knee) * np.tanh((a - knee) / (0.97 - knee)))
                x = np.sign(x) * y
    ch = 2 if x.ndim == 2 else 1
    data = (x.T if ch == 2 else x)
    with wave.open(os.path.join(out_dir or OUT, name + ".wav"), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(data, -1, 1) * 32767).astype(np.int16).tobytes())
