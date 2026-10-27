"""Instruments for the Clausa ad score. Everything is synthesised here, so the
track has no licence attached to it. Mono unless noted; 48 kHz float."""
import numpy as np

SR = 48000
rng = np.random.default_rng(7)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def times(n):
    return np.arange(n) / SR


def fft_filter(x, lo=None, hi=None):
    """Second-order Butterworth magnitude, applied in the frequency domain."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    h = np.ones_like(f)
    if lo:
        h *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** 4)
    if hi:
        h *= 1 / np.sqrt(1 + (f / hi) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * h, n)


def norm(x, peak=1.0):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def noise(n, lo=None, hi=None):
    return norm(fft_filter(rng.standard_normal(n), lo, hi))


def fade_out(x, seconds=0.05):
    k = min(len(x), int(seconds * SR))
    x[-k:] *= np.linspace(1, 0, k)
    return x


def piano(m, dur=3.0, vel=0.8):
    """Two strings a hair apart per note, as a piano has, so it beats and blooms
    instead of sounding like a sine organ; partials decay faster as they rise."""
    f0, n = mtof(m), int(dur * SR)
    t = times(n)
    out = np.zeros(n)
    for detune in (-0.9, 0.9):                      # cents
        f = f0 * 2 ** (detune / 1200)
        for k in range(1, 16):
            fk = k * f * np.sqrt(1 + 0.00032 * k * k)
            if fk > 15000:
                break
            tau = 2.2 * (220 / f0) ** 0.3 / (1 + 0.45 * (k - 1))
            amp = vel ** (0.6 + 0.15 * k) / k ** 1.25        # harder = brighter
            out += amp * np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    out *= np.minimum(1, t / 0.004)
    h = int(0.03 * SR)
    out[:h] += 0.025 * noise(h, 200, 2500) * np.exp(-times(h) / 0.006)
    return fade_out(out, 0.15) * vel / 4.2


def pluck(m, vel=0.6, dur=0.8):
    f0, n = mtof(m), int(dur * SR)
    t = times(n)
    out = np.zeros(n)
    for k in range(1, 9):
        if k * f0 > 14000:
            break
        out += np.sin(2 * np.pi * k * f0 * t) * np.exp(-t / (0.3 / (1 + 0.6 * (k - 1)))) / k ** 1.1
    return fade_out(out * np.minimum(1, t / 0.002), 0.05) * vel / 2.0


def pad(notes, dur, level=1.0, bright=0.5, atk=0.9, rel=1.0):
    """Stereo: five detuned voices per note with saw-like harmonics, through a
    gentle low-pass that opens slowly, so it breathes rather than sits still."""
    n = int((dur + rel) * SR)
    t = times(n)
    out = np.zeros((n, 2))
    cutoff_lo, cutoff_hi = 700 + 1800 * bright, 1600 + 4200 * bright
    for m in notes:
        for detune, pan in ((-0.12, -0.85), (-0.05, -0.35), (0.0, 0.0), (0.05, 0.35), (0.12, 0.85)):
            f = mtof(m) * 2 ** (detune / 12)
            v = np.zeros(n)
            for k in range(1, 22):
                if k * f > 12000:
                    break
                v += np.sin(2 * np.pi * k * f * t + rng.uniform(0, 6.28)) / k
            dark, open_ = fft_filter(v, 60, cutoff_lo), fft_filter(v, 60, cutoff_hi)
            sweep = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(dur, 0.1), 0, 1))
            v = dark * (1 - sweep) + open_ * sweep
            out[:, 0] += v * np.cos((pan + 1) * np.pi / 4)
            out[:, 1] += v * np.sin((pan + 1) * np.pi / 4)
    env = np.minimum(1, t / atk) ** 1.5 * np.clip((dur + rel - t) / rel, 0, 1)
    env *= 1 + 0.05 * np.sin(2 * np.pi * 0.18 * t)
    return out * env[:, None] * level / (len(notes) * 4.5)


def lead(m, dur=0.55, vel=0.5):
    """The hook: a soft bell-like voice (sine with a little FM shimmer)."""
    f, n = mtof(m), int(dur * SR)
    t = times(n)
    mod = 0.6 * np.exp(-t / 0.25) * np.sin(2 * np.pi * f * 2 * t)
    x = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / (dur * 0.7))
    x += 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.3)
    return fade_out(x * np.minimum(1, t / 0.006), 0.08) * vel * 0.6


def bass(m, dur, vel=1.0):
    f, n = mtof(m), int(dur * SR)
    t = times(n)
    v = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) + 0.15 * np.sin(6 * np.pi * f * t)
    v *= np.minimum(1, t / 0.008) * np.exp(-t / max(0.12, dur * 0.8))
    return fade_out(np.tanh(1.4 * v) / np.tanh(1.4), 0.03) * vel


def kick(vel=1.0):
    n = int(0.45 * SR)
    t = times(n)
    f = 44 + 100 * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
    click = noise(n, 2000, 9000) * np.exp(-t / 0.003) * 0.3
    return np.tanh(2.0 * (body + click)) / np.tanh(2.0) * vel


def clap(vel=0.8):
    n = int(0.4 * SR)
    t = times(n)
    env = np.zeros(n)
    for off, tau in ((0, 0.006), (0.012, 0.006), (0.024, 0.13)):
        env += (t >= off) * np.exp(-np.maximum(t - off, 0) / tau)
    return norm(noise(n, 900, 6000) * env, vel)


def hat(vel=0.3, open_=False):
    n = int((0.35 if open_ else 0.08) * SR)
    return norm(noise(n, 6500, 12500) * np.exp(-times(n) / (0.09 if open_ else 0.016)), vel)


def thump(vel=1.0):
    """One half of a heartbeat."""
    n = int(0.4 * SR)
    t = times(n)
    f = 46 + 34 * np.exp(-t / 0.04)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09) * np.minimum(1, t / 0.004)
    return norm(body + 0.3 * noise(n, None, 200) * np.exp(-t / 0.05), vel)


def riser(dur, seed=0):
    n = int(dur * SR)
    t = times(n)
    p = t / dur
    g = np.random.default_rng(seed).standard_normal(n)
    low, high = norm(fft_filter(g, 200, 900)), norm(fft_filter(g, 2500, 12000))
    tone = 0.25 * np.sin(2 * np.pi * np.cumsum(180 * 2 ** (p * 2.5)) / SR)
    return (0.6 * (low * (1 - p) ** 1.5 + high * p ** 1.5) + tone) * p ** 2.2


def boom():
    n = int(3.0 * SR)
    t = times(n)
    f = 32 + 55 * np.exp(-t / 0.25)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.9) * np.minimum(1, t / 0.002)
    crack = noise(n, 100, 5000) * np.exp(-t / 0.06) * 0.5
    air = noise(n, 4000, 15000) * np.exp(-t / 0.8) * 0.1
    return norm(np.tanh(1.6 * (sub + crack + air)))


def whoosh(dur=0.7, peak=0.55, vel=1.0):
    """Stereo, panning left to right as it passes."""
    n = int(dur * SR)
    t = times(n)
    p = t / dur
    g = rng.standard_normal(n)
    mid, top = norm(fft_filter(g, 300, 2500)), norm(fft_filter(g, 2500, 10000))
    env = np.where(p < peak, (p / peak) ** 2, np.exp(-(p - peak) / (1 - peak) * 4))
    x = (mid * (1 - env) + top * env) * env
    pan = -0.7 + 1.4 * p
    return np.stack([x * np.cos((pan + 1) * np.pi / 4), x * np.sin((pan + 1) * np.pi / 4)], 1) * vel


def tick(f=2200, vel=0.2):
    n = int(0.06 * SR)
    t = times(n)
    x = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * 2.01 * f * t)
    return x * np.exp(-t / 0.012) * np.minimum(1, t / 0.0008) * vel / 1.4


def pop(vel=0.25, lo=520, hi=1020):
    n = int(0.12 * SR)
    t = times(n)
    f = lo + (hi - lo) * (1 - np.exp(-t / 0.02))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.03) * np.minimum(1, t / 0.001) * vel


def paper(vel=0.1):
    n = int(0.025 * SR)
    return noise(n, 1500, 7000) * np.exp(-times(n) / 0.005) * vel


def marker(dur=0.6, vel=0.12):
    n = int(dur * SR)
    t = times(n)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7 * (1 + 0.3 * np.sin(2 * np.pi * 23 * t))
    return noise(n, 2500, 9000) * env * vel


def shimmer(dur=0.9, vel=0.1):
    """A rising glassy sweep, for the scan beam."""
    n = int(dur * SR)
    t = times(n)
    p = t / dur
    f = 900 * 2 ** (p * 1.6)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR)
    return (0.5 * tone + noise(n, 3000, 12000) * 0.4) * np.sin(np.pi * p) ** 1.5 * vel


def bell(m, vel=0.3, dur=4.0):
    f, n = mtof(m), int(dur * SR)
    t = times(n)
    out = np.zeros(n)
    for ratio, amp, tau in ((1, 1, 2.4), (2.0, 0.5, 1.5), (2.76, 0.35, 1.1), (5.4, 0.18, 0.5), (8.93, 0.08, 0.25)):
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / tau)
    return fade_out(out * np.minimum(1, t / 0.002), 0.2) * vel / 1.6


def shutter(vel=0.18):
    n = int(0.05 * SR)
    t = times(n)
    a = noise(n, 1200, 8000) * np.exp(-t / 0.004)
    b = np.roll(noise(n, 800, 5000) * np.exp(-t / 0.006), int(0.018 * SR))
    return (a + 0.7 * b) * vel


def make_ir(seconds=3.0, tau=0.55, seed=1):
    n = int(seconds * SR)
    t = times(n)
    g = np.random.default_rng(seed)
    x = g.standard_normal(n) * np.exp(-t / tau) * np.minimum(1, t / 0.03)
    cf = np.clip(t / 1.4, 0, 1)
    x = fft_filter(x, 120, 8000) * (1 - cf) + fft_filter(x, 120, 2600) * cf
    for d, a in ((0.011, 0.5), (0.019, 0.35), (0.027, 0.3), (0.041, 0.2)):   # early reflections
        i = int(d * SR)
        x[i] += a * (1 if g.random() > 0.5 else -1) * np.max(np.abs(x))
    x = np.concatenate([np.zeros(int(0.028 * SR)), x])
    return x / np.sqrt(np.sum(x ** 2))


def master(mix, kick_times=()):
    """EQ, bus compression and a soft limit, so the parts sit together."""
    out = np.zeros_like(mix)
    for c in range(mix.shape[1]):
        x = mix[:, c]
        f = np.fft.rfftfreq(len(x), 1 / SR)
        X = np.fft.rfft(x)
        # Tuned by measured band balance, for phones first: they cannot play
        # deep bass, so sub energy only makes the rest quieter.
        X *= 1 / np.sqrt(1 + (32 / np.maximum(f, 1e-3)) ** 4)                       # rumble out
        X *= 1 - 0.42 / (1 + (np.maximum(f, 1) / 85) ** 2)                           # less sub
        X *= 1 - 0.25 * np.exp(-((np.log2(np.maximum(f, 1) / 320)) ** 2) / 0.5)      # less mud
        X *= 1 + 1.4 * np.exp(-((np.log2(np.maximum(f, 1) / 3000)) ** 2) / 0.9)      # presence
        X *= 1 + 1.6 / (1 + (8000 / np.maximum(f, 1)) ** 2)                          # air
        out[:, c] = np.fft.irfft(X, len(x))
    # Bus compressor: 2.5:1 above -18 dB, 10 ms attack, 180 ms release, on the summed level.
    level = np.abs(out).max(axis=1)
    env = np.zeros_like(level)
    a_att, a_rel = np.exp(-1 / (0.010 * SR)), np.exp(-1 / (0.180 * SR))
    e = 0.0
    for i in range(0, len(level), 32):                  # block-rate is plenty for glue
        v = level[i:i + 32].max()
        e = a_att * e + (1 - a_att) * v if v > e else a_rel * e + (1 - a_rel) * v
        env[i:i + 32] = e
    thr = 10 ** (-18 / 20) * np.max(np.abs(out))
    gain = np.where(env > thr, (thr / np.maximum(env, 1e-9)) ** (1 - 1 / 2.5), 1.0)
    out *= gain[:, None]
    out /= np.max(np.abs(out)) / 1.15
    return np.tanh(out) / np.tanh(1.15)


def convolve(sig, ir):
    size = 1 << (len(sig) + len(ir) - 2).bit_length()
    return np.fft.irfft(np.fft.rfft(sig, size) * np.fft.rfft(ir, size), size)[: len(sig)]
