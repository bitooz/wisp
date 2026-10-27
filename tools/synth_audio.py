import math, random, struct, wave, sys
SR = 22050
out = sys.argv[1]
def save(name, s):
    peak = max(1e-6, max(abs(x) for x in s))
    k = 0.85 / peak
    w = wave.open(f"{out}/{name}.wav", "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * k)) * 32767)) for x in s)); w.close()
def loop(s, fade=SR):
    # crossfade the end into the start so it loops without a click
    n = len(s) - fade
    o = s[:n]
    for i in range(fade):
        t = i / fade
        o[i] = s[i] * t + s[n + i] * (1 - t)
    return o
def lowpass(s, a):
    y = 0.0; o = []
    for x in s:
        y += a * (x - y); o.append(y)
    return o
def noise(n): return [random.uniform(-1, 1) for _ in range(n)]
random.seed(7)
L = SR * 14
# Wind: low-passed noise with slow gusts
wind = lowpass(lowpass(noise(L), .02), .05)
wind = [x * (0.55 + 0.45 * math.sin(2 * math.pi * i / SR / 7.0) * math.sin(2 * math.pi * i / SR / 3.1 + 1)) for i, x in enumerate(wind)]
# Sea: deeper noise, swelling every ~3.5 s
sea = lowpass(lowpass(noise(L), .008), .03)
sea = [x * (0.25 + 0.75 * max(0, math.sin(2 * math.pi * i / SR / 3.5)) ** 2) for i, x in enumerate(sea)]
def birds(n, count):
    s = [0.0] * n
    for _ in range(count):
        t0 = random.randint(0, n - SR)
        f0 = random.uniform(2600, 4200); notes = random.randint(2, 5)
        for k in range(notes):
            st = t0 + k * int(SR * random.uniform(.09, .16)); dur = int(SR * random.uniform(.05, .1))
            f1 = f0 * random.uniform(.8, 1.3)
            ph = 0
            for i in range(dur):
                if st + i >= n: break
                f = f0 + (f1 - f0) * i / dur
                ph += 2 * math.pi * f / SR
                env = math.sin(math.pi * i / dur) ** 2
                s[st + i] += math.sin(ph) * env * .35
    return s
def crickets(n):
    s = [0.0] * n; ph = 0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * 4700 / SR
        chirp = (math.sin(2 * math.pi * 28 * t) > 0.3) * (math.sin(2 * math.pi * t / 0.9) > 0.1)
        s[i] = math.sin(ph) * chirp * .12
    return lowpass(s, .5)
# No birds by day (they were too much); still drawn, so the random numbers after stay as they were
_ = birds(L, 9)
day = [w * .5 + s * .9 for w, s in zip(wind, sea)]
save("island_day", loop(day))
dusk = [w * .45 + s * .9 + c for w, s, c in zip(wind, sea, crickets(L))]
save("island_dusk", loop(dusk))
# Cave: a low drone and drips
drone = []
dn = lowpass(lowpass(noise(L), .004), .01)
for i in range(L):
    t = i / SR
    drone.append(.35 * math.sin(2 * math.pi * 55 * t) * (0.7 + .3 * math.sin(2 * math.pi * t / 5)) + .25 * math.sin(2 * math.pi * 82.6 * t) + dn[i] * 1.5)
for _ in range(9):
    st = random.randint(0, L - SR); f = random.uniform(900, 1500)
    for i in range(int(SR * .35)):
        t = i / SR
        drone[st + i] += math.sin(2 * math.pi * (f + 300 * math.exp(-t * 30)) * t) * math.exp(-t * 14) * .5
save("cave", loop(drone))
# Dash: a short rising whoosh
n = int(SR * .45)
wh = lowpass(noise(n), .25)
wh = [x * math.sin(math.pi * i / n) ** 1.5 * (0.4 + i / n) for i, x in enumerate(wh)]
save("dash", wh)
# Fire: a soft roar with crackles and the odd pop (the campfire and the hearths)
F = SR * 8
roar = lowpass(lowpass(noise(F), .03), .08)
fire = [x * (0.6 + 0.4 * math.sin(2 * math.pi * i / SR / 1.7) * math.sin(2 * math.pi * i / SR / 0.6 + 2)) for i, x in enumerate(roar)]
for _ in range(220):
    st = random.randint(0, F - SR // 4); big = random.random() < .08
    dur = int(SR * (random.uniform(.02, .05) if big else random.uniform(.003, .012)))
    amp = random.uniform(.6, 1.4) if big else random.uniform(.15, .6)
    for i in range(dur):
        fire[st + i] += random.uniform(-1, 1) * amp * math.exp(-i / max(1, dur) * 4)
save("fire", loop(lowpass(fire, .6), SR // 2))
# Indoors: the wind outside, muffled through the walls, and a quiet room
R = SR * 12
room = lowpass(lowpass(lowpass(noise(R), .006), .02), .05)
room = [x * (0.5 + 0.5 * math.sin(2 * math.pi * i / SR / 9.0) ** 2) for i, x in enumerate(room)]
for _ in range(5):
    # A creak of the house now and then
    st = random.randint(0, R - SR); f = random.uniform(180, 320)
    for i in range(int(SR * .25)):
        t = i / SR
        room[st + i] += math.sin(2 * math.pi * (f + 40 * math.sin(t * 30)) * t) * math.sin(math.pi * t / .25) * .04
save("indoors", loop(room))
print("ok")
