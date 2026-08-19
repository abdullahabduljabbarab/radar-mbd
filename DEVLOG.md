# Development log

Chronological engineering journal for the radar signal processing
Simulink model and its generated code integration into CLEARANCE.
Most recent first.

Companion material:

- [docs/RADAR_MBD_DESIGN.md](docs/RADAR_MBD_DESIGN.md) — design brief
  for the DSP chain.
- [docs/INTEGRATION.md](docs/INTEGRATION.md) — how the generated code
  plugs into CLEARANCE.
- [Requirements.md](Requirements.md) — requirements this model
  satisfies.

---

## 2026-07

### 2026-07-09 — v2 long-range surveillance profile

The v1 medium-PRF waveform (PRF 4 kHz, 20 nm unambiguous range) could
not cover a 1000 nm CLEARANCE sector even with five radar sites. The
game world needs range far more than it needs unambiguous Doppler for
target discrimination.

Regenerated the model with:

- `PRF = 100 Hz`
- `fs = 250 kHz`
- `tau = 100 µs`
- `BW = 100 kHz`

Result: **810 nm unambiguous range**. Trade: unambiguous velocity
folds into ±2.7 m/s, so Doppler is unusable for target
discrimination in this mode. The matching layer in the CLEARANCE
wrapper switched to **range-only** detection under this profile.

Wrapper constants realigned:

- `NTxSamples`: 200 → 25
- `FsHz`: 10 MHz → 250 kHz

Commit: *Long-range surveillance profile (100 Hz PRF, 810 nm
unambig range)*.

### 2026-07-09 — Integrated live into CLEARANCE

Radar model is now the detection source for every `UClearanceRadar`
in the sim. Wrapper (`RadarWrapper.h/.cpp`) auto-detects the
Embedded Coder output under
`ThirdParty/RadarGenerated/{include,src}` in the CLEARANCE plugin.
Every radar site owns one wrapper instance and one
`RT_MODEL_RadarSubsystem_T` handle.

I/Q cube is synthesised on the CLEARANCE side from the live
airspace state per site (per aircraft position, velocity, RCS,
per-radar look direction, per-radar noise floor). The matching
layer unaliases range and maps each detection back to its source
aircraft callsign so downstream consumers see structured tracks,
not raw detections.

`bUseSimulinkDSP = true` on `UClearanceRadar` by default. Console
commands `clearance.radar.mbd.probe`, `.enable`, `.disable`, `.test`
for runtime introspection and A/B comparison against the built-in
analytic radar equation fallback.

CPI phase-staggering added via `SiteName` hash so five radar sites
in the same scenario do not pile all their I/Q synthesis onto the
same game frame.

### 2026-07-09 — EW rewrite

First attempt at jamming injected a barrage-noise source into the
I/Q cube and let MVDR null it. Real physics, wrong effect for the
game world: a strong jammer dominated the sample covariance, MVDR
nulled its bearing, and the resulting weight vector also collapsed
sidelobe gain everywhere off boresight. Every non-boresight
aircraft on the scope vanished.

Reverted to per-aircraft degradation for self-jamming. The jamming
aircraft's own return drops to 30% confidence and loses its
transponder tag; every other blip on the scope is untouched. This
matches the intent of self-protection jamming in an operator's
picture: the jammer degrades its own visibility, not the entire
sensor picture.

Chaff went from silent (the previous Simulink model never saw it)
to a **five-blip primary-only ghost cluster** dispersed ±1.2 nm
around each cloud, fading with cloud lifetime (about eight seconds).
Ghost blips carry no secondary data because chaff has no
transponder.

## 2026-06

### 2026-06 — Reusable function packaging

Regenerated with **Reusable Function** packaging so every consumer
gets its own per-instance state. Previous static-globals output was
incompatible with multi-radar operation.

Every radar site now allocates one
`RT_MODEL_RadarSubsystem_T` handle. Fleet operation confirmed with
five concurrent radar sites, each carrying independent covariance
matrix history, matched filter state, and CFAR reference cell
history. No cross-site state bleed.

### 2026-06 — MVDR beamformer built from the covariance matrix

The adaptive receive beamformer is written as a MATLAB Function
block from the analytic Capon expression, not dragged in from
Phased Array Toolbox.

Given the sample spatial covariance matrix `R = <x x^H>` and a
steering vector `a(theta_look)`, MVDR (Minimum Variance
Distortionless Response) computes weights that minimise output
power subject to unit gain at the look direction:

```
R_hat  = (1/K) * rx.' * conj(rx)
R_load = R_hat + load_factor * trace(R_hat)/N * I
w      = R_load^-1 * a  /  (a^H * R_load^-1 * a)
```

Diagonal loading regularises the inverse under snapshot-deficient
conditions. Verified against a target at 30 km, +10° azimuth,
60 m/s with a barrage jammer at −40°, +30 dB above per-element
noise: MVDR carves a ~40 dB null at the jammer bearing while
delay-and-sum has its natural sidelobe there at about −20 dB.
Range profile after matched filter shows a 28 dB SNR gain from
adaptive nulling on the same input signal.

Full derivation in
[docs/RADAR_MBD_DESIGN.md](docs/RADAR_MBD_DESIGN.md).

### 2026-06 — Full DSP chain in place

Standard pulsed-radar architecture, block by block:

```
LFM waveform generator (tau = 20 us, BW = 1 MHz, S-band)
        |
        v
Target scene (per-element receive window across 8-element ULA + AWGN)
        |
        v (Nspp x 8 x 16 complex cube per CPI)
MVDR beamformer (adaptive weights per look direction)
        |
        v (Nspp x 16 single-channel per CPI)
Matched filter (pulse compression, 13 dB gain from tau*BW = 20)
        |
        v
Doppler FFT (Hamming-windowed, 12 dB coherent integration gain)
        |
        v (range-Doppler map)
CA-CFAR detector (Rohling threshold, guard cells around CUT)
        |
        v
Detection list (range, velocity, SNR per hit)
```

Every stage is textbook. Nothing exotic. Every stage is implemented
from the analytic formula in a MATLAB Function block so the
generated code has zero external toolbox library dependencies.

### 2026-06 — First working model

Eight-element uniform linear array, S-band centre frequency,
per-element noise from `kTBF`. Waveform, target scene, MVDR, matched
filter, Doppler FFT, and CFAR wired end to end. Detection list
returned as a fixed-size buffer with padded no-detection rows so the
generated C has a stable interface size.

## 2026-05

### 2026-05 — Requirements captured

REQ IDs in [Requirements.md](Requirements.md) covering:

- Range accuracy per waveform profile.
- Doppler resolution per CPI length.
- CFAR probability of false alarm at the design SNR.
- MVDR null depth against a specified jammer scenario.
- Reusable function packaging discipline.
- Zero external toolbox runtime dependency in the generated code.
