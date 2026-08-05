# Radar design notes

Design brief for the signal processor in `radar.slx`. What it is,
why each stage looks the way it does, what the deployed C code
does when CLEARANCE's radar sites call it.

## What it is

A pulsed-radar signal processor for a monostatic S-band surveillance
sensor with an 8-element phased array receiver. One CPI (coherent
processing interval) of input, one detection list of output. That's
the entire runtime contract.

- **Input**: `rx_cube` = complex I/Q samples, shape
  `Nspp_receive x N_elements x N_pulses = 2500 x 8 x 16`. Represents
  one 4 ms burst of received signal across the array. Plus a
  `look_angle_rad` scalar (where to steer the receive beam) and a
  `tx` chirp reference (for the matched filter).
- **Output**: up to 16 detections, each with range (m), radial
  velocity (m/s, positive closing), and SNR (dB), plus a count of
  actual detections. Fixed-size arrays so the generated C has static
  memory layout.

CLEARANCE would generate `rx_cube` from its own airspace state (per-
aircraft returns delayed by 2R/c, phase-shifted by the steering
vector, with per-element noise). This model does the DSP; the
scene generator is CLEARANCE's job.

## Design choices

### S-band, 2.8 GHz

Standard civil airport surveillance band (2.7-2.9 GHz). Matches
what the C++ radar equation module in CLEARANCE already uses so
link-budget analysis produces the same numbers in either
implementation. Physical constants derived: `lambda = c/fc ~=
107 mm`, so half-wavelength element spacing = 53.5 mm and an
8-element aperture is 37 cm.

### LFM chirp, 20 us pulse, 1 MHz bandwidth

Time-bandwidth product `tau * BW = 20`. Matched-filter pulse
compression delivers `10*log10(TB) ~ 13 dB` gain over an
uncompressed pulse of the same peak power. Range resolution is set
entirely by bandwidth: `dR = c / (2*BW) = 150 m` per cell. Longer
pulse would give more SNR gain at the cost of larger blind range
right after transmit; 20 us is on the short side of a "long"
surveillance chirp but readable for verification plots.

### Two shippable waveform profiles

The model ships two profiles, both selected via
`model/waveform_params.m`. Same block diagram, same C interface, so
the generated `radar_step` entry point is source-compatible between
them and the CLEARANCE wrapper needs no changes to switch.

**v1 terminal profile**: `PRF = 4 kHz, tau = 20 us, BW = 1 MHz`.
Medium-PRF surveillance for the airliner regime. Balances range and
velocity ambiguity:

    R_max_unamb = c * PRI / 2       = 37.5 km    (targets to 37.5 km unambig)
    v_max_unamb = lambda / (4*PRI)  = +/-107 m/s (covers 250 kt typical)

Aliasing at 1 kHz PRF (the value initially in `waveform_params.m`)
was the reason for the medium-PRF switch: a 100 m/s target aliased
into a -7 m/s Doppler bin. Used for the single-target verification
plots in the README.

**v2 long-range profile**: `PRF = 100 Hz, tau = 100 us, BW = 100 kHz`.
Low-PRF surveillance for the CLEARANCE integration where a single
site has to cover a ~1000 nm sector:

    R_max_unamb = c * PRI / 2       = 1500 km   (810 nm unambig)
    v_max_unamb = lambda / (4*PRI)  = +/-2.7 m/s

Velocity aliases into the ±2.7 m/s range so Doppler is effectively
unused for target matching in this profile: CLEARANCE relies on
range and beam-angle for track association. This is the profile
shipping in the current CLEARANCE integration.

Real long-range surveillance rigs stagger PRF across a burst to
disambiguate beyond a single PRI's constraints; the v2 profile does
not do this. Adding PRF staggering would be a natural extension.

### 8-element uniform linear array, lambda/2 spacing

Textbook baseline. Half-wavelength element spacing avoids grating
lobes across the full field of view. 8 elements is enough for
meaningful adaptive nulling (7 degrees of freedom minus the
distortionless-response constraint) without ballooning the sample
covariance dimension.

Array is zero-centred: element positions
`((0:N-1) - (N-1)/2) * lambda/2 = [-3.5, -2.5, ..., +3.5] * lambda/2`.
Puts the phase reference at the array centre so steering vectors
read symmetrically about broadside.

### MVDR receive beamforming with diagonal loading

Adaptive Capon beamforming: minimise output power subject to
distortionless (unit) gain at the look direction. Closed-form
weights:

    R_hat  = (1/K) * rx.^T * conj(rx)   sample spatial covariance
    R_load = R_hat + load * (trace/N) * I   diagonal loading
    w      = R_load^{-1} a  /  (a^H R_load^{-1} a)

The covariance convention matters. Using `rx' * rx` (Hermitian
transpose) gives the conjugate covariance, whose eigenvectors are
`conj(a)` rather than `a`. MVDR built on that inverts a matrix
whose null space is in the wrong direction and fails to null the
jammer at all. The `rx.' * conj(rx)` form gives the standard
R = <x x^H>. Getting this backwards was the session 2 debug.

Diagonal loading regularises the inverse when the snapshot count K
is close to the element count N (snapshot-deficient regime). Load
factor of `0.001 * trace(R_hat)/N` scales with the noise level and
is aggressive enough to keep the inverse well-conditioned without
smearing the null.

### Matched filter with causal-slice indexing

`conv(rx, h, 'full')` produces `N_rx + N_tx - 1` samples where a
target at delay D peaks at index `D + N_tx`. Taking
`y = y_full(N_tx : N_tx + N_rx - 1)` gives an N_rx-length output
where sample index i (1-indexed) maps to delay `i-1`. The range
axis `(0:N-1) * c / (2*fs)` then reads directly with no offset.

The 'same' variant would shift the peak by `floor(N_tx/2)` samples
and every downstream range measurement would need a compensating
offset. The causal-slice form keeps the range axis honest.

### Range-Doppler processing

Standard two-step. Matched-filter every pulse in fast time to
compress the chirp. Apply a Hamming window across the slow-time
axis to suppress Doppler sidelobes. FFT across pulses at every
range cell. `fftshift` so zero-Doppler sits in the middle of the
velocity axis.

Coherent integration across N pulses lifts the target by
`10*log10(N) = 12 dB` at 16 pulses. Doppler resolution is
`lambda / (2*CPI) = 3.35 m/s` at CPI = 16 ms. Velocity mapping
`v = lambda * f_d / 2` with positive convention = closing.

Note: the current model runs at CPI = `N_pulses * PRI` = 4 ms,
which gives coarser Doppler resolution (13.4 m/s per bin) than a
longer CPI would. This matches the codegen fixed-step tick rate
(one model call per CPI) - trading Doppler resolution for
integration cadence. For finer Doppler analysis, bump `N_pulses`
to 64 and the resolution improves proportionally.

### CA-CFAR with Rohling threshold

Textbook cell-averaging constant false-alarm rate. For each cell
under test, skip a guard region around it (target energy shouldn't
leak into the noise estimate), average the surrounding training
cells, threshold above `alpha * mean` where alpha comes from the
Rohling formula:

    alpha = N_train_total * (Pfa^(-1/N_train_total) - 1)

Under an exponential noise assumption this gives a constant false-
alarm rate `Pfa` across the entire range-Doppler map. Guard cells
= 4 range x 1 Doppler; training cells = 8 range x 2 Doppler
(surrounding ring). `Pfa = 1e-6` is defensive enough that random
noise almost never triggers a hit; strong targets light up several
adjacent cells (the top-K extraction picks the strongest).

Implementation uses scalar-only iteration (no submatrix slicing,
no dynamic ranges) because MATLAB Coder needs to prove fixed-size
memory layout at compile time for reusable-function codegen.

## Code generation

Configured for **reusable-function packaging** via
`CodeInterfacePackaging = 'Reusable function'` +
`RootIOFormat = 'Part of model data structure'` +
`SystemTargetFile = 'ert.tlc'`. Same as the autopilot repo.
Generated entry points:

```c
void radar_initialize(RT_MODEL_radar_T *rtM);
void radar_step      (RT_MODEL_radar_T *rtM);
void radar_terminate (RT_MODEL_radar_T *rtM);
```

Every field of the run-time state (blockIO, contStates, inputs,
outputs) lives inside the `RT_MODEL_radar_T` struct pointed to by
`rtM`. Consumers allocate one per radar site. No file-scope
globals; a fleet of sites runs concurrently on the same `.c`.

Fixed-step discrete solver at 4 ms per tick
(`N_pulses * PRI = 4 ms`). CLEARANCE will call `radar_step` once
per CPI, feeding a freshly synthesised `rx_cube` each time.

Regenerating C from the model:

```matlab
build_radar_model
rtwbuild('radar')
```

Output in `radar_ert_rtw/`. Five files CLEARANCE needs:
`radar.c`, `radar.h`, `radar_types.h`, `radar_private.h`,
`rtwtypes.h`. Plus `rt_nonfinite.c/.h` and `rtGetNaN.c/.h` for the
NaN handling in the top-K detection buffer (unused entries filled
with NaN by design so downstream code can distinguish "no
detection here" from "detection at range 0").

## Verification

Five test benches in `tools/verify_*.m`:

- `verify_lfm_waveform.m` - chirp real/imag time domain,
  instantaneous frequency ramp, spectrogram. Asserts start
  frequency, end frequency, and unit amplitude.
- `verify_matched_filter.m` - end-to-end with single target at
  30 km, +5 dB pre-integration SNR. Asserts detected range
  within 2 range cells of truth (150 m each) and 45 dB post-
  compression peak.
- `verify_beamformer.m` - MVDR vs DAS beam patterns, matched
  filter outputs before/after adaptive nulling. Asserts MVDR
  peak within tolerance and beam patterns diverge sharply at
  the jammer angle.
- `verify_range_doppler.m` - 16-pulse burst, moving target,
  jammer, full pipeline through CFAR. Asserts detected range
  and velocity within 2 cells each on the strongest CFAR hit.
- `verify_radar_dsp.m` - same scene run through the top-level
  `radar_dsp` entry point that the Simulink model wraps.
  Confirms the wrapper is behaviourally identical to the
  piecewise pipeline.

Regression baseline: `tools/save_reference_baseline.m` freezes
the canonical scene under a fixed RNG seed to
`ci_artifacts/simOut_radar_defaults.mat`. `tools/compare_sim.m`
reruns and asserts zero drift on range, velocity, SNR, and
detection count. Currently verified at 0.0 drift on every metric.

`tools/run_model_tests_and_build.m` is the CI entry point -
runs all five verify scripts, runs compare_sim, rebuilds the
model, invokes rtwbuild.

## Integration with CLEARANCE

The plugin module in CLEARANCE will be `ClearanceRadarMBD`,
mirroring the pattern of the existing `ClearanceAutopilotMBD`
module:

- `RadarWrapper.h/.cpp` - thin C++ wrapper around the extern-C
  entry points. Owns one `RT_MODEL_radar_T` per instance. Exposes a
  clean UE-native interface: feed it aircraft states, get
  detections back.
- `RadarGeneratedUnit.cpp` - compilation shim. Single TU includes
  `radar.c` under `extern "C"` so Unreal Build Tool compiles the
  generated code as part of the module without needing a per-file
  compilation rule.
- `ClearanceRadarMBD.Build.cs` - detects the presence of
  `ThirdParty/RadarGenerated/include/` and `src/`, flips
  `CLEARANCE_RADAR_MBD_HAVE_CODEGEN=1`, adds the include paths.

Each `AClearanceRadarSite` in the game will hold one
`FRadarWrapper` and call `Step()` from its tick. When the model
detects, the wrapper translates the detection list into
`FRadarTrack` entries that feed the existing operator scope.

## What's not in here

Deliberate omissions:

- **No IQ transmit / channel / propagation model.** The Simulink
  model is signal processing only. Generating `rx_cube` from an
  airspace state (positional geometry, RCS lookups, propagation
  losses, atmospheric attenuation) is CLEARANCE's job. Keeps the
  model portable and the generated C small.
- **No Phased Array System Toolbox blocks.** MVDR, CFAR, and
  matched filter are all authored from the analytic formulae as
  MATLAB Function blocks. Generated C is pure ANSI with no
  toolbox library dependencies. The toolbox blocks would generate
  code that depends on runtime helpers we'd have to link
  alongside.
- **No STAP (space-time adaptive processing).** Full 2D adaptive
  processing across space and slow time would be a natural
  extension but is deferred. Current MVDR is spatial only.
- **No tracker.** The output is per-CPI detection lists. Track
  initiation, association, and maintenance across CPIs belongs
  either in CLEARANCE (via the existing `UClearanceRadar` fusion
  logic) or in a follow-on `radar-tracker-mbd` project.
- **No monopulse angle estimation.** Detection includes range and
  velocity but not azimuth. Angle would come from steering the
  beam across multiple looks or from a monopulse angle-error
  channel - both deferred.
- **No clutter model.** All noise is thermal AWGN. Real
  surveillance radars deal with ground clutter, sea clutter,
  bird flocks. Would need a proper clutter distribution
  (Rayleigh, K, log-normal depending on scenario) and a Doppler
  clutter map - deferred.
- **No waveform diversity.** LFM only. Barker codes, Costas
  hopping, staggered PRF would be extensions.

## Files

```
radar.slx                          <-- source of truth (Simulink model)
model/
  radar_params.m                   <-- physical + RF constants
  waveform_params.m                <-- pulse shape + PRF + CPI
  array_params.m                   <-- element geometry + MVDR loading
  lfm_waveform.m                   <-- chirp generator
  steering_vector.m                <-- plane-wave phase pattern
  matched_filter.m                 <-- causal-slice pulse compression
  target_scene.m                   <-- single-element scene
  target_scene_array.m             <-- N-element scene
  multi_pulse_scene.m              <-- 3D cube with Doppler
  mvdr_beamform.m                  <-- Capon weights, standard R convention
  range_doppler.m                  <-- matched filter + Doppler FFT + axes
  cfar_ca.m                        <-- Rohling threshold, scalar-only iter
  radar_dsp.m                      <-- top-level codegen entry
tools/
  build_radar_model.m              <-- programmatic Simulink build
  save_reference_baseline.m        <-- freezes ci_artifacts
  compare_sim.m                    <-- regression check
  run_model_tests_and_build.m      <-- CI entry point
  verify_lfm_waveform.m            <-- test 1
  verify_matched_filter.m          <-- test 2
  verify_beamformer.m              <-- test 3
  verify_range_doppler.m           <-- test 4
  verify_radar_dsp.m               <-- test 5
ci_artifacts/simOut_radar_defaults.mat   <-- deterministic baseline
req_map.csv                        <-- 20 REQ-RD-* entries
traceability_report.csv/html       <-- rendered traceability
docs/
  RADAR_MBD_DESIGN.md              <-- this file
  img/                             <-- README figures
```
