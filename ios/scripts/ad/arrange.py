"""Score for the Clausa ad: 100 BPM, 12 bars (28.8 s) plus a tail, B minor
resolving to D major on the logo. Every effect sits on a frame of the film;
the times here are the same ones the renderer animates on.

  python3 arrange.py out.wav
"""
import sys
import wave
import numpy as np
from synth import *

BEAT = 0.6
BAR = 4 * BEAT
TOTAL = 29.6
N = int(TOTAL * SR)


def at(bar, beat=0.0):
    return (bar - 1) * BAR + beat * BEAT


class Mix:
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


music, beat_bus = Mix(), Mix()  # music is ducked by the kick; beat_bus is not

VOICING = {
    'Bm7': [47, 54, 57, 62, 66], 'Gmaj7': [43, 50, 54, 59, 62], 'Em7': [40, 47, 50, 55, 59],
    'A': [45, 52, 57, 61, 64], 'Asus': [45, 52, 57, 62, 64], 'D': [38, 50, 54, 57, 62],
    'Dmaj9': [38, 50, 54, 57, 61, 64],
}
ROOT = {'Bm7': 35, 'Gmaj7': 31, 'Em7': 40, 'A': 33, 'Asus': 33, 'D': 38, 'Dmaj9': 38}
ARP = {
    'Bm7': [71, 74, 78, 81], 'Gmaj7': [67, 71, 74, 78], 'D': [69, 74, 78, 81],
    'A': [69, 73, 76, 81], 'Asus': [69, 74, 76, 81], 'Dmaj9': [69, 73, 76, 78],
}
# (bar, chord, beats) — bars 3 and 11 change chord halfway.
CHORDS = [
    (1, 'Bm7', 4), (2, 'Gmaj7', 4), (3, 'Em7', 2), (3.5, 'A', 2), (4, 'Dmaj9', 4),
    (5, 'Bm7', 4), (6, 'Gmaj7', 4), (7, 'D', 4), (8, 'A', 4), (9, 'Bm7', 4),
    (10, 'Gmaj7', 4), (11, 'Asus', 2), (11.5, 'A', 2), (12, 'Dmaj9', 5.3),
]
DRUM_BARS = [5, 6, 7, 9, 10, 11]

# --- Pads -------------------------------------------------------------------
for bar, chord, beats in CHORDS:
    start = (bar - 1) * BAR
    level, bright = (0.55, 0.33) if bar < 4 else (0.8 if int(bar) in (8, 12) else 0.62, 0.5)
    music.add(pad(VOICING[chord], beats * BEAT, level, bright, atk=0.6 if bar > 1 else 1.4,
                  rel=2.5 if bar == 12 else 0.9), start, verb=0.25)

# --- Piano: the opening motif, the reveal, the breakdown, the ending -------
MOTIF = [  # (bar, beat, notes, velocity)
    (1, 0, [59, 66], 0.55), (1, 2, [74], 0.45), (1, 3, [73], 0.4),
    (2, 0, [55, 62], 0.55), (2, 1, [71], 0.42), (2, 2.5, [69], 0.4), (2, 3, [66], 0.38),
    (3, 0, [64, 67], 0.55), (3, 1, [71], 0.45), (3, 2, [64, 73], 0.5), (3, 3, [76], 0.5),
    (4, 0, [50, 57, 66, 76, 81], 0.9),
    (8, 0, [69, 76], 0.5), (8, 1, [73], 0.42), (8, 2, [69], 0.4), (8, 3, [76], 0.45),
    (12, 0, [50, 57, 66, 73, 76], 0.85),
]
for bar, beat, notes, vel in MOTIF:
    for i, m in enumerate(notes):
        music.add(piano(m, 4.0 if bar in (4, 12) else 2.6, vel), at(bar, beat) + i * 0.012,
                  pan=(m - 64) / 40, verb=0.35)

# --- Arp and bass under the beat -------------------------------------------
PATTERN = [0, 2, 1, 3, 0, 2, 1, 3]
for bar, chord, beats in CHORDS:
    if int(bar) not in DRUM_BARS:
        continue
    for k in range(int(beats * 2)):
        t = (bar - 1) * BAR + k * BEAT / 2
        vel = 0.5 if k % 2 == 0 else 0.34
        music.add(pluck(ARP[chord][PATTERN[k % 8]], vel), t, pan=0.35 if k % 2 else -0.35, verb=0.3)
        music.add(bass(ROOT[chord], BEAT / 2 * 0.95, 0.62 if k % 2 == 0 else 0.45), t)
music.add(bass(ROOT['A'], BAR, 0.5), at(8))           # the breakdown holds one note
music.add(bass(ROOT['Dmaj9'], 3.0, 0.6), at(12))     # and the ending rings

# --- Drums -------------------------------------------------------------------
kicks = []
for b in DRUM_BARS:
    for beat in ([0, 1, 2, 3] if b == 11 else [0, 2, 2.5] if b in (6, 10) else [0, 2]):
        kicks.append(at(b, beat))
    for beat in (1, 3):
        beat_bus.add(clap(0.8), at(b, beat), gain=0.36, verb=0.25)
    for k in range(16 if b == 11 else 8):
        step = 0.25 if b == 11 else 0.5
        vel = 0.3 if (k * step) % 1 == 0.5 else 0.18
        beat_bus.add(hat(vel), at(b, k * step), gain=0.5, pan=0.25)
    beat_bus.add(hat(0.22, open_=True), at(b, 3.5), gain=0.45, pan=-0.2)
for t in kicks:
    beat_bus.add(kick(), t, gain=0.85)
for i, t in enumerate(np.arange(at(8, 3), at(9), BEAT / 4)):   # roll into bar 9
    beat_bus.add(clap(0.3 + 0.12 * i), t, gain=0.32, verb=0.25)
for i in range(4):                                              # pickup into bar 5
    beat_bus.add(hat(0.1 + 0.07 * i), at(4, 3 + i / 4), gain=0.5)

# --- Heartbeat and the reveal --------------------------------------------------
for k in range(4):
    beat_bus.add(thump(1.0), at(3, k), gain=0.75, verb=0.1)
    beat_bus.add(thump(0.65), at(3, k) + 0.2, gain=0.75, verb=0.1)
riser_stereo = np.stack([riser(1.8, 11), riser(1.8, 12)], 1)
beat_bus.add(riser_stereo, at(3, 1), gain=0.32, verb=0.2)
beat_bus.add(boom(), at(4), gain=0.9, verb=0.3)
beat_bus.add(bell(86, 0.35), at(4), verb=0.5, pan=0.2)
beat_bus.add(riser_stereo[int(1.0 * SR):], at(11, 2.67), gain=0.2, verb=0.2)
beat_bus.add(boom() * 0.6, at(12), gain=0.8, verb=0.3)
beat_bus.add(bell(86, 0.3), at(12), verb=0.55, pan=-0.2)
beat_bus.add(bell(93, 0.22), at(12) + 0.3, verb=0.6, pan=0.3)

# --- Effects, on the film's events --------------------------------------------
sfx = Mix()
for i in range(48):   # the 48 pages landing, one click each
    sfx.add(paper(0.06 + 0.05 * rng.random()), 0.8 + i * 0.021, pan=rng.uniform(-0.6, 0.6), verb=0.1)
for t in (2.62, 9.5, 11.9, 16.65, 19.1, 21.5, 23.9):
    sfx.add(whoosh(0.7), t - 0.35, gain=0.22, verb=0.15)
sfx.add(pop(0.22, 300, 520), 10.2, verb=0.2)          # the document lands
sfx.add(shimmer(0.9), 10.8, gain=0.8, verb=0.3)       # the scan
sfx.add(pop(0.2), 11.7, verb=0.2)                     # "48 pages read"
sfx.add(marker(0.6), 12.9, gain=1.4, verb=0.1)        # the highlight
sfx.add(pop(0.24, 600, 1300), 13.6, verb=0.2)         # the figure lifts
sfx.add(tick(2637, 0.2), 14.4, verb=0.3)              # "Page 12"
sfx.add(pop(0.18), 14.4, verb=0.2)
sfx.add(pop(0.22, 380, 700), 17.2, verb=0.2)          # not stated
sfx.add(tick(1760, 0.14), 18.0, verb=0.3)
for i, m in enumerate((86, 88, 90, 93)):              # the four steps
    sfx.add(tick(mtof(m), 0.16), 19.8 + i * 0.3, verb=0.3)
sfx.add(pop(0.2, 700, 1400), 21.95, verb=0.2)         # question sent
for t in (22.3, 22.42, 22.54):
    sfx.add(tick(3000, 0.05), t)
sfx.add(pop(0.22), 22.62, verb=0.2)                   # answer
sfx.add(tick(2637, 0.16), 22.98, verb=0.3)
for k in range(1, 8):                                 # one cut per eighth note
    sfx.add(shutter(0.14), at(11, k / 2), pan=0.1)

# --- Sidechain, reverb, master ---------------------------------------------------
duck = np.ones(N)
for t in kicks:
    i = int(t * SR)
    g = 1 - 0.45 * np.exp(-times(int(0.4 * SR)) / 0.11)
    seg = duck[i:i + len(g)]
    duck[i:i + len(g)] = np.minimum(seg, g[:len(seg)])

send = music.send * duck + beat_bus.send + sfx.send
wet = np.stack([convolve(send, make_ir(seed=1)), convolve(send, make_ir(seed=2))], 1)
mix = music.dry * duck[:, None] + beat_bus.dry + sfx.dry + wet * 0.8

mix /= np.max(np.abs(mix)) / 1.1
mix = np.tanh(mix) / np.tanh(1.1)
mix[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))[:, None]
tail = int(0.9 * SR)
mix[-tail:] *= np.linspace(1, 0, tail)[:, None] ** 1.5
mix *= 0.89 / np.max(np.abs(mix))

for name, a, b in (('intro', 0, 7.2), ('reveal', 7.2, 9.6), ('beat', 9.6, 16.8),
                   ('breakdown', 16.8, 19.2), ('beat2', 19.2, 26.4), ('end', 26.4, TOTAL)):
    seg = mix[int(a * SR):int(b * SR)]
    print(f'{name:10s} rms {20 * np.log10(np.sqrt(np.mean(seg ** 2))):6.1f} dBFS')

pcm = np.clip(mix * 32767 + rng.uniform(-0.5, 0.5, mix.shape) + rng.uniform(-0.5, 0.5, mix.shape), -32768, 32767)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.astype('<i2').tobytes())
print('wrote', sys.argv[1])
