"""Create short original game sound cues from simple synthesized signals."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
SR = 44100
rng = np.random.default_rng(271028)


def tone(freq0, freq1, seconds):
    t = np.arange(int(SR * seconds)) / SR
    phase = 2 * np.pi * (freq0 * t + (freq1 - freq0) * t * t / (2 * seconds))
    return np.sin(phase)


def save(name, data):
    data = np.asarray(data, dtype=np.float64)
    peak = max(1.0, np.max(np.abs(data)) / 0.85)
    pcm = np.int16(np.clip(data / peak, -1, 1) * 32767)
    with wave.open(str(OUT / (name + ".wav")), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SR)
        out.writeframes(pcm.tobytes())


def noise(seconds):
    return rng.normal(0, 1, int(SR * seconds))


t = np.arange(int(SR * 0.18)) / SR
n = noise(0.18)
swish = (n - np.convolve(n, np.ones(85) / 85, mode="same")) * (np.sin(np.pi * t / 0.18) ** 2) * 0.27
swish += tone(420, 145, 0.18) * (np.sin(np.pi * t / 0.18) ** 2) * 0.18
save("attack_swing", swish)

t = np.arange(int(SR * 0.27)) / SR
impact = tone(125, 42, 0.27) * np.exp(-t * 20) * 0.75
impact += noise(0.27) * np.exp(-t * 27) * 0.23
save("attack_hit", impact)

t = np.arange(int(SR * 0.34)) / SR
grunt = tone(205, 105, 0.34) * (0.5 + 0.5 * np.sin(2 * np.pi * 17 * t)) * np.exp(-t * 9) * 0.5
grunt += noise(0.34) * np.exp(-t * 18) * 0.09
save("hurt", grunt)

t = np.arange(int(SR * 0.22)) / SR
block = (tone(730, 510, 0.22) + tone(1270, 880, 0.22) * 0.55) * np.exp(-t * 22) * 0.43
block += noise(0.22) * np.exp(-t * 35) * 0.18
save("block", block)

t = np.arange(int(SR * 0.36)) / SR
skill = tone(240, 880, 0.36) * np.exp(-t * 6) * 0.4
skill += noise(0.36) * (np.sin(np.pi * t / 0.36) ** 2) * 0.13
save("skill", skill)

for p in OUT.glob("*.wav"):
    print(p.name, p.stat().st_size)
