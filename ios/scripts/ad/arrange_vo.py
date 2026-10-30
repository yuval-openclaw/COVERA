"""The narrated cut's soundtrack: Arthur's narration over a calm, trustworthy bed.

Under a voice the music has to step back: warm pads and sparse piano instead of a
beat and a hook, a soft pulse for momentum once the product appears, and an
automatic duck of about 10 dB wherever the narrator speaks. The heartbeat, the
riser, the logo's boom and bells stay — they are the story's punctuation.

Scene times here are the film's output times in the narrated cut (main.swift,
CLAUSA_NARRATED=1); effects that belong to a moment of the film are placed with
the same piecewise map, so picture and sound stay locked.

  python3 arrange_vo.py narration.mp3 out.wav
"""
import subprocess
import sys
import wave
import numpy as np
from synth import *

TOTAL = 40.5
N = int(TOTAL * SR)
KNOTS = [(0, 0), (3.9, 2.4), (5.3, 3.6), (6.8, 4.8), (9.2, 7.2), (11.6, 9.6), (15.6, 12.0),
         (21.4, 16.8), (26.0, 19.2), (31.0, 21.6), (33.6, 24.0), (35.6, 26.4), (40.5, 29.6)]


def out(film_t):
    """Film time → output time, the inverse of main.swift's filmTime."""
    for (ao, af), (bo, bf) in zip(KNOTS, KNOTS[1:]):
        if film_t <= bf:
            return ao + (bo - ao) * (film_t - af) / (bf - af)
    return KNOTS[-1][0]


class Bus:
    def __init__(self):
        self.dry = np.zeros((N, 2))
        self.send = np.zeros(N)

    def add(self, sig, t, gain=1.0, pan=0.0, verb=0.0):
        if sig.ndim == 1:
            sig = np.stack([sig * np.cos((pan + 1) * np.pi / 4), sig * np.sin((pan + 1) * np.pi / 4)], 1) * np.sqrt(2)
        i = int(round(t * SR))
        end = min(N, i + len(sig))
        if end <= i:
            return
        self.dry[i:end] += sig[: end - i] * gain
        self.send[i:end] += sig[: end - i].mean(1) * gain * verb


music, fx, voice = Bus(), Bus(), Bus()

# --- The bed: one chord per scene, in output time -----------------------------
V = {
    'Bm7': [47, 54, 57, 62, 66], 'Gmaj7': [43, 50, 54, 59, 62], 'Em7': [40, 47, 50, 55, 59],
    'A': [45, 52, 57, 61, 64], 'Asus': [45, 52, 57, 62, 64], 'D': [38, 50, 54, 57, 62],
    'Dmaj9': [38, 50, 54, 57, 61, 64],
}
ROOT = {'Bm7': 35, 'Gmaj7': 31, 'Em7': 40, 'A': 33, 'Asus': 33, 'D': 38, 'Dmaj9': 38}
SCENES = [  # (start, end, chord, brightness)
    (0.0, 3.9, 'Bm7', 0.30), (3.9, 5.3, 'Gmaj7', 0.30), (5.3, 6.8, 'Em7', 0.32),
    (6.8, 9.2, 'Asus', 0.36), (9.2, 11.6, 'Dmaj9', 0.55), (11.6, 15.6, 'Bm7', 0.50),
    (15.6, 21.4, 'Gmaj7', 0.52), (21.4, 26.0, 'A', 0.48), (26.0, 31.0, 'Bm7', 0.52),
    (31.0, 33.6, 'D', 0.55), (33.6, 35.6, 'Asus', 0.58), (35.6, 40.5, 'Dmaj9', 0.55),
]
for start, end, chord, bright in SCENES:
    music.add(pad(V[chord], end - start, 0.55 if start < 9.2 else 0.62, bright, atk=0.8, rel=1.6), start, verb=0.3)
    if start >= 9.2:
        music.add(bass(ROOT[chord], end - start, 0.45), start)

# Sparse piano: chord tones every 1.2 s, quiet, never a melody to follow.
rng_p = np.random.default_rng(3)
for start, end, chord, _ in SCENES:
    tones = [m + 12 for m in V[chord][1:]]
    t = start + 0.15
    while t < end - 0.3:
        m = tones[rng_p.integers(len(tones))]
        music.add(piano(m, 2.4, 0.32 + 0.08 * rng_p.random()), t, pan=(m - 64) / 50, verb=0.45)
        t += 1.2

# A soft pulse from the product's first scene to the language montage: muted
# plucks on the eighth notes at 100 BPM, for momentum without a drum kit.
ARP = {'Bm7': [71, 74, 78], 'Gmaj7': [67, 71, 74], 'A': [69, 73, 76], 'D': [69, 74, 78], 'Asus': [69, 74, 76]}
t = 11.6
while t < 35.6:
    chord = next(c for s, e, c, _ in SCENES if s <= t < e)
    notes = ARP.get(chord, ARP['D'])
    k = int(round((t - 11.6) / 0.3))
    music.add(pluck(notes[k % 3], 0.22 if k % 2 == 0 else 0.15, 0.5), t, pan=0.3 if k % 2 else -0.3, verb=0.3)
    t += 0.3

# --- The story's punctuation ----------------------------------------------------
for i in range(48):                                   # the pages landing
    fx.add(paper(0.05 + 0.04 * rng.random()), out(0.8 + i * 0.021), pan=rng.uniform(-0.6, 0.6), verb=0.1)
fx.add(whoosh(0.7), out(2.62) - 0.35, gain=0.18, verb=0.15)
for k in range(4):                                    # the heartbeat, on the ECG spikes
    fx.add(thump(1.0), out(4.8 + k * 0.6), gain=0.7, verb=0.1)
    fx.add(thump(0.65), out(4.8 + k * 0.6) + 0.2, gain=0.7, verb=0.1)
fx.add(np.stack([riser(1.8, 11), riser(1.8, 12)], 1), out(5.4), gain=0.28, verb=0.2)
fx.add(boom(), out(7.2), gain=0.85, verb=0.3)
fx.add(bell(86, 0.32), out(7.2), verb=0.5, pan=0.2)
for t_film in (9.5, 11.9, 16.65, 19.1, 21.5, 23.9):   # scene changes
    fx.add(whoosh(0.7), out(t_film + 0.35) - 0.35, gain=0.12, verb=0.15)
fx.add(shimmer(0.9), out(10.8), gain=0.5, verb=0.3)
fx.add(marker(0.6), out(12.9), gain=1.0, verb=0.1)
fx.add(pop(0.18, 600, 1300), out(13.6), verb=0.2)
fx.add(tick(2637, 0.14), out(14.4), verb=0.3)
for i, m in enumerate((86, 88, 90, 93)):
    fx.add(tick(mtof(m), 0.11), out(19.8 + i * 0.3), verb=0.3)
for k in range(1, 8):
    fx.add(shutter(0.1), out(24.0 + k * 0.3), pan=0.1)
fx.add(boom() * 0.5, out(26.4), gain=0.7, verb=0.3)
fx.add(bell(86, 0.28), out(26.4), verb=0.55, pan=-0.2)
fx.add(bell(93, 0.2), out(26.4) + 0.3, verb=0.6, pan=0.3)

# --- The narration ---------------------------------------------------------------
raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', sys.argv[1], '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                     capture_output=True, check=True).stdout
vo = np.frombuffer(raw, dtype='<f4').astype(np.float64)
vo = fft_filter(vo, 80, None)                          # rumble out; the voice starts above it
# Lines as cut at the narration's own pauses (silencedetect), and where each lands.
LINES = [((0.00, 3.47), 0.35), ((4.04, 5.04), 4.05), ((5.72, 7.00), 5.45), ((7.66, 8.81), 9.75),
         ((9.34, 12.87), 11.85), ((13.55, 18.82), 15.85), ((19.53, 23.72), 21.65), ((24.43, 29.09), 26.25),
         ((29.67, 31.90), 31.20), ((32.37, 33.36), 33.95), ((34.04, 37.60), 36.00)]
speech = np.zeros(N)
for (a, b), at_t in LINES:
    seg = vo[int(max(0, a - 0.03) * SR):int(min(len(vo) / SR, b + 0.08) * SR)].copy()
    edge = int(0.01 * SR)
    seg[:edge] *= np.linspace(0, 1, edge)
    seg[-edge:] *= np.linspace(1, 0, edge)
    voice.add(seg, at_t, gain=1.0, verb=0.04)
    i = int(at_t * SR)
    speech[i:i + len(seg)] = 1.0

# Duck the music ~12 dB under the voice, easing in 0.12 s and out 0.5 s.
duck = np.ones(N)
target = 1 - 0.75 * speech
a_in, a_out = np.exp(-1 / (0.12 * SR)), np.exp(-1 / (0.5 * SR))
g = 1.0
for i in range(0, N, 64):
    tgt = target[i:i + 64].min()
    g = a_in * g + (1 - a_in) * tgt if tgt < g else a_out * g + (1 - a_out) * tgt
    duck[i:i + 64] = g

send = music.send * duck + fx.send * (0.6 + 0.4 * duck) + voice.send
wet = np.stack([convolve(send, make_ir(seed=1)), convolve(send, make_ir(seed=2))], 1)
bed = music.dry * duck[:, None] + fx.dry * (0.6 + 0.4 * duck)[:, None] + wet * 0.7
bed = master(bed)
bed *= 0.62 / np.max(np.abs(bed))                     # full where no one speaks; the duck clears the voice
v = voice.dry / np.max(np.abs(voice.dry)) * 0.85
mix = bed + v
mix /= np.max(np.abs(mix)) / 0.95
mix = np.tanh(mix * 1.05) / np.tanh(1.05)
mix[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))[:, None]
tail = int(0.8 * SR)
mix[-tail:] *= np.linspace(1, 0, tail)[:, None] ** 1.5
mix *= 0.89 / np.max(np.abs(mix))

pcm = np.clip(mix * 32767 + rng.uniform(-0.5, 0.5, mix.shape) + rng.uniform(-0.5, 0.5, mix.shape), -32768, 32767)
with wave.open(sys.argv[2], 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.astype('<i2').tobytes())
print('wrote', sys.argv[2])
