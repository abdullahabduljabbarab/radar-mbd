# Verification and Validation Plan: radar-mbd

Companion to [`../req_map.csv`](../req_map.csv) (the source-of-truth requirement-to-block mapping) and [`../traceability_report.html`](../traceability_report.html) (the rendered coverage matrix). If `req_map.csv` answers "what is the model supposed to do?", this doc answers "how do we prove it does?".

## 1. Purpose and scope

Verification and validation on a Model-Based Design signal-processing chain is a proportionality exercise. This is a portfolio-scale Simulink model of a pulsed radar signal processor, not a certified radar-warning-receiver algorithm. So it does not need DO-178C / DO-331 tool qualification rigour, but it does need to demonstrate the discipline that a real defence programme would exhibit: traceable requirements, tiered verification, and reproducible detection performance a reviewer can audit without a live radar.

### In scope

| Item | Notes |
|---|---|
| Every requirement in `req_map.csv` | 20 REQ-RD-* entries across the LFM waveform generator, target scene, MVDR beamformer, matched filter, range-Doppler processor, and CA-CFAR detector |
| Every MATLAB Function block and every kernel `.m` cited by a requirement | The `Block` column of the CSV is grep-able against the model and against the `verify_*.m` scripts |
| Numeric equivalence between the model and the underlying analytic formulae | LFM instantaneous frequency vs `-BW/2 + BW*t/tau`, matched-filter peak vs `tau*BW` gain, MVDR weights vs `R^-1 a / (a^H R^-1 a)`, CFAR threshold vs Rohling formula |
| Physical calibration of the range and velocity axes | `range = i*c/(2*fs)`, `velocity = lambda*f_d/2`; verified against ground-truth target parameters in the smoke sim |
| Detection statistics under known SNR | Single-target verification per waveform profile; `Pd = 0.5` crossing sanity-checked against the radar equation via the smoke sim |
| Embedded-Coder-generated C's structural equivalence to the model | Regression check via `tools/compare_sim.m` comparing generated-code sim vs `sim('radar')` reference |

### Out of scope

| Item | Reason |
|---|---|
| DO-178C / DO-331 coverage | Portfolio scale. |
| Live-radar hardware verification | No hardware. CLEARANCE integration IS the operational loop. |
| Clutter modelling beyond AWGN (K-distributed sea clutter, Weibull ground clutter) | CA-CFAR assumes exponentially-distributed noise; verified against that assumption. Real-clutter statistics would require OS-CFAR or CA-CFAR variants and separate validation data. |
| Multi-target resolution beyond the top-K CFAR extraction | Single-target verification in the demo plots is the tractable case; multi-target scenarios would need a scenario generator and per-scenario expected-detection assertions. |
| Radar range equation calibration to real absolute SNR | Model outputs SNR relative to the noise floor from `kTBF`; matching absolute SNR to any real radar would need a link budget and antenna pattern measurements. |

## 2. Test tiers

Three tiers, each covering different requirement classes at different cost.

| Tier | Definition | Cost | Where they live | When to use |
|---|---|---|---|---|
| **T1 Verification-script probes** | Analytic-formula checks in `verify_*.m` scripts: build a canonical input (chirp, single target, known steering vector), run the block or kernel, assert numeric properties (instantaneous-frequency slope, matched-filter peak location and gain, MVDR null depth, CFAR false-alarm rate over Monte Carlo). | Low. Sub-second per script. | `tools/verify_lfm_waveform.m`, `tools/verify_matched_filter.m`, `tools/verify_beamformer.m`, `tools/verify_range_doppler.m`, `tools/verify_radar_dsp.m`: each cited from `req_map.csv`. | Any pure-model or pure-kernel requirement. |
| **T2 Regression against baseline** | `tools/compare_sim.m` loads `ci_artifacts/simOut_radar_defaults.mat` (the frozen reference), reruns the model, asserts each output within tolerance. Catches accidental drift from any parameter or block reconfiguration. | Low-medium. Requires a fresh Simulink session but runs headless. | `tools/compare_sim.m`, `tools/save_reference_baseline.m` (to refresh the baseline after an intentional design change), `tools/run_model_tests_and_build.m` (CI entry point). | Whole-model integrity checks after any config change. |
| **T3 Code-generation + integration** | `rtwbuild('radar')` generates C, CLEARANCE builds the wrapper, radar site runs the generated `radar_step` inside the sim, feeding CFAR detections into the operator's radar scope. Any behavioural regression versus pure-model sim is caught by scope-side observation (missed target, false-alarm rain, range-cell drift). | High. Requires full toolchain and CLEARANCE build. | Model integration lives in CLEARANCE's `ClearanceRadarMBD` plugin; `.github/workflows/ci.yml` covers the code-generation half. | Every release. Every waveform-profile change. |

### Selection rule

Default to T1. Escalate to T2 when a whole-model integrity concern applies. T3 always runs before a release; the waveform-profile switch from `v1 terminal` to `v2 long-range` was validated at T3 because the coherent-integration behaviour only matters when actual airspace state is exercised.

## 3. Traceability

`req_map.csv` is the traceability matrix. Every row maps one REQ-RD-* to one Simulink block or one MATLAB kernel. `traceability_report.html` renders it; `traceability_report.csv` is the machine-readable form used by CI to fail on missing coverage.

### Coverage discipline

| Rule | How it is enforced |
|---|---|
| Every REQ-RD-* must map to exactly one Block or kernel `.m` | `req_map.csv` schema; CI asserts no orphan REQ-IDs |
| Every mapped block must exist in `radar.slx` | `tools/run_model_tests_and_build.m` opens the model and resolves each block path |
| Every mapped kernel `.m` must exist in `model/` | Same resolution step catches missing kernels |
| Every `verify_*.m` script must probe at least one mapped block | Cross-check by grep of the kernel name in the verify script |

### Currently green

- 20 of 20 REQ-RD-* entries mapped
- 20 of 20 mapped blocks and kernels resolve
- Regression check passes against `ci_artifacts/simOut_radar_defaults.mat`
- Single-target verification plots (Figures 2-5 in the README) show the expected numeric behaviour: chirp instantaneous frequency, matched-filter peak location within 6 m of ground truth, MVDR nulling ~40 dB deep on a jammer, CFAR detection cluster on the true range-Doppler bin

## 4. Coverage targets

Self-imposed discipline goals.

| # | Target | Rule | Current status |
|---|---|---|---|
| 1 | REQ-RD coverage | Every requirement has at least one T1 verification probe. | 20 of 20. **Target met.** |
| 2 | Range-axis calibration | Matched-filter peak location must match ground-truth target range within one range cell. | Verified: 29.99 km measured vs 30.00 km truth (6 m error, inside the 150 m range cell). **Target met.** |
| 3 | Velocity-axis calibration | Range-Doppler peak location must match ground-truth target velocity within one Doppler bin. | Verified against 60 m/s ground-truth in `verify_range_doppler.m`. **Target met.** |
| 4 | MVDR null depth | Adaptive weights must deliver at least 30 dB null on a broadside jammer. | Verified: ~40 dB null in the beamformer verification. **Target met.** |
| 5 | CFAR false-alarm rate | Over Monte Carlo runs on pure-noise input, empirical Pfa must match the design `Pfa = 1e-6` within a factor of 3. | Not currently automated; would be added if the sim's operational scenarios required strict false-alarm control. **Target deferred.** |
| 6 | Code-generation equivalence | Generated C sim output must match pure-model sim within regression tolerance. | Verified by `tools/compare_sim.m`. **Target met.** |
| 7 | Waveform-profile switch integrity | Switching between v1 terminal and v2 long-range profiles via `waveform_params.m` must not require any wrapper or CLEARANCE-side code changes. | Verified: v2 long-range currently shipping in CLEARANCE with identical wrapper interface. **Target met.** |

## 5. When to run what

| Trigger | T1 | T2 | T3 (code-gen + CLEARANCE integration) |
|---|:-:|:-:|:-:|
| Any block edit in `radar.slx` | ✓ | ✓ | |
| Any kernel edit under `model/` | ✓ | ✓ | |
| Waveform parameter change (`waveform_params.m`) | ✓ | ✓ | ✓ |
| Array geometry change (`array_params.m`) | ✓ | ✓ | ✓ |
| CFAR parameter change (`cfar_ca.m` thresholds) | ✓ | ✓ | ✓ |
| MATLAB / Simulink version upgrade | ✓ | ✓ | ✓ |
| Before shipping to CLEARANCE | ✓ | ✓ | ✓ |
| Before recording a demo video | ✓ | ✓ | ✓ |

## 6. Change control

`req_map.csv` and this doc live with the model in the same repo. Changes to requirements are committed alongside the model change that motivates them.

- **New REQ-RD-***: append to `req_map.csv` with a stable ID, extend an existing `verify_*.m` or add a new one.
- **Removing a REQ-RD-***: mark the row `[DEPRECATED]` in the Description column; don't reuse the ID.
- **Waveform-profile addition** (e.g. a v3 profile): add a new row for the profile-selector setting under a REQ-RD-* covering the switch logic; regenerate the baseline via `save_reference_baseline.m` for the new profile.

## 7. What this doc deliberately doesn't cover

- **Real-world clutter modelling** (K-distributed sea clutter, Weibull ground, wind-driven Doppler spread). AWGN-only assumption is documented; validating against real clutter would need measurement data.
- **Antenna radiation patterns beyond isotropic elements**. Real ULA element patterns and mutual coupling would need EM simulation.
- **Radar cross-section models beyond point targets**. No Swerling target models, no glint, no scintillation. Fine for the ATC surveillance use case in CLEARANCE; wrong for weapons-quality tracking.
- **Certification artefacts** (DO-178C, DO-331 tool qualification). Not portfolio scale.

If this radar signal processor shipped in a certified surveillance system, every bullet above would need to be addressed. Documenting what's not done makes the current scope honest.
