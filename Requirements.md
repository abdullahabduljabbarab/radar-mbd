# Requirements — radar-mbd

Every requirement covered by the Simulink model, grouped by DSP stage and traced to (a) the specific Simulink block or MATLAB kernel that implements it and (b) the external source the requirement derives from. Each REQ-ID is also tagged in [`req_map.csv`](req_map.csv) (the machine-readable form used by the traceability report). This doc adds the Source column that `req_map.csv` doesn't carry.

Companion to [`docs/V_AND_V_PLAN.md`](docs/V_AND_V_PLAN.md), which is the verification strategy behind proving each requirement.

## Numbering scheme

```
REQ-RD-<###>
```

Numbers ascend and are never reused. Deprecated REQ-IDs stay in place with a `[DEPRECATED]` marker rather than being renumbered.

## REQ-RD-001..004 — Beamforming stage

| ID | Requirement | Verified by | Source |
|---|---|---|---|
| REQ-RD-001 | MVDR beamforming shall collapse N-element array data to single-channel output by inverting the spatial covariance matrix | `radar/BeamformStage` | Capon (1969), *High-Resolution Frequency-Wavenumber Spectrum Analysis*, Proc. IEEE — original MVDR/Capon derivation |
| REQ-RD-002 | Steering vector shall compute plane-wave phase pattern `a(theta) = exp(j·2π·x·sin(theta)/lambda)` for arbitrary linear array | `model/steering_vector.m` | Van Trees, *Optimum Array Processing*, ch. 2 — plane-wave steering-vector convention |
| REQ-RD-003 | Sample spatial covariance shall be computed as `R = (1/K) · rx.'·conj(rx)` matching the standard `E[x·xᴴ]` convention | `model/mvdr_beamform.m` | Van Trees, *Optimum Array Processing*, sample covariance definition; ensures MVDR null lies in the direction of the interferer, not its conjugate |
| REQ-RD-004 | Diagonal loading shall regularise the covariance inverse under snapshot-deficient conditions | `model/mvdr_beamform.m` | Carlson (1988), *Covariance Matrix Estimation Errors and Diagonal Loading in Adaptive Arrays*, IEEE Trans. AES |

## REQ-RD-005..006 — Matched filter

| ID | Requirement | Verified by | Source |
|---|---|---|---|
| REQ-RD-005 | Matched-filter pulse compression shall be applied per pulse using full-length convolution with the time-reversed conjugate of the transmit chirp | `radar/RangeDopplerStage` | Skolnik, *Introduction to Radar Systems* (3rd ed. 2001), ch. 6 — matched-filter theorem |
| REQ-RD-006 | Matched filter output indexing shall map sample `i` to delay `(i-1)` samples with no post-hoc range-axis offset | `model/matched_filter.m` | Causal-slice indexing convention; avoids off-by-`N_tx/2` errors that plague `'same'` convolution mode |

## REQ-RD-007..011 — Range-Doppler processing

| ID | Requirement | Verified by | Source |
|---|---|---|---|
| REQ-RD-007 | Hamming window shall be applied across slow-time before Doppler FFT to suppress Doppler sidelobes | `radar/RangeDopplerStage` | Harris (1978), *On the Use of Windows for Harmonic Analysis with the Discrete Fourier Transform*, Proc. IEEE — Hamming window sidelobe characterisation |
| REQ-RD-008 | Doppler FFT shall be computed across pulses per range cell | `model/range_doppler.m` | Richards, *Fundamentals of Radar Signal Processing* (2nd ed. 2014), ch. 5 — Doppler processing via slow-time FFT |
| REQ-RD-009 | `fftshift` shall place zero-Doppler bin at the centre of the velocity axis | `model/range_doppler.m` | MATLAB `fftshift` convention; consistent with negative→positive velocity axis rendering |
| REQ-RD-010 | Range axis shall map to physical distance via `i·c/(2·fs)` metres per sample | `model/range_doppler.m` | Skolnik ch. 6 — round-trip time-to-range conversion |
| REQ-RD-011 | Velocity axis shall map to physical velocity via `v = lambda·f_d/2` with positive = closing | `model/range_doppler.m` | Skolnik ch. 3 — Doppler frequency to radial velocity |

## REQ-RD-012..015 — CFAR detection

| ID | Requirement | Verified by | Source |
|---|---|---|---|
| REQ-RD-012 | CA-CFAR detector shall estimate local noise from a training ring around a guard region and threshold above `alpha·noise` | `radar/CFARStage` | Rohling (1983), *Radar CFAR Thresholding in Clutter and Multiple Target Situations*, IEEE Trans. AES-19(4) — original CA-CFAR formulation |
| REQ-RD-013 | CFAR threshold multiplier shall follow the Rohling formula `alpha = N_train·(Pfa^(-1/N_train) - 1)` for exponential noise | `model/cfar_ca.m` | Rohling (1983); assumes exponentially-distributed square-law-detected noise |
| REQ-RD-014 | Guard cells around each cell under test shall be excluded from the noise estimate | `model/cfar_ca.m` | Rohling (1983); prevents target energy from biasing the noise estimate upward |
| REQ-RD-015 | CFAR detections shall be extracted as a top-K list sorted by power (K = 16) with SNR estimated from a global noise floor | `radar/CFARStage` | Fixed-size output for reusable-function code-gen compatibility; standard top-K extraction pattern |

## REQ-RD-016..018 — Root inport contracts

| ID | Requirement | Verified by | Source |
|---|---|---|---|
| REQ-RD-016 | Root inport `rx_cube` shall accept a `Nspp_receive × 8 × 16` complex IQ data cube | `radar/rx_cube` | CLEARANCE integration contract — 8-element ULA × 16-pulse CPI |
| REQ-RD-017 | Root inport `look_angle_rad` shall accept the steering direction in radians from array broadside | `radar/look_angle_rad` | CLEARANCE integration contract — beam-steering command from operator scope |
| REQ-RD-018 | Root inport `tx` shall accept the transmit reference chirp for matched filtering | `radar/tx` | Matched-filter theorem — receiver needs the exact transmit waveform |

## REQ-RD-019..020 — Root outport contracts

| ID | Requirement | Verified by | Source |
|---|---|---|---|
| REQ-RD-019 | Root outport `det_range_m` shall expose detection range in metres for up to 16 top hits | `radar/det_range_m` | Fixed-size buffer for reusable-function code-gen compatibility; SI units for CLEARANCE integration |
| REQ-RD-020 | Root outport `n_detections` shall expose the actual detection count as `int32` | `radar/n_detections` | Signals how many entries of the fixed-size buffers are populated |

## Coverage summary

| Stage | REQs | Verification tier |
|---|---:|---|
| Beamforming | 4 | T1 kernel probe + T2 baseline regression + T3 CLEARANCE integration |
| Matched filter | 2 | T1 kernel probe + T2 baseline regression |
| Range-Doppler | 5 | T1 kernel probe + T2 baseline regression |
| CFAR detection | 4 | T1 kernel probe + T2 baseline regression + Monte Carlo (deferred) |
| Root inport contracts | 3 | T2 baseline regression + T3 wrapper type check |
| Root outport contracts | 2 | T2 baseline regression + T3 wrapper type check |
| **Total** | **20** | |

## Design decisions not captured as REQs

Some design choices are deliberately not requirements because they're tunable parameters that can change without affecting the external contract:

- **Waveform profile choice (v1 terminal vs v2 long-range).** Selected via `model/waveform_params.m`. The generated `radar_step` interface is identical between profiles so the choice is a data change, not a model-structure change.
- **`Pfa = 1e-6` design value.** Tunable via CFAR parameters. Would tighten for a defensive scenario, loosen for a search scenario.
- **Diagonal-loading factor of `0.001 · trace(R)/N`.** Empirical setting that keeps the covariance inverse well-conditioned without smearing the null; tunable per operating scenario.
- **CPI length = 16 pulses.** Trades Doppler resolution for tick cadence. Bumping to 64 pulses improves Doppler resolution proportionally.
- **8-element array, λ/2 spacing.** Portfolio-scale default; a larger array would extend adaptive nulling capability at the cost of a bigger sample-covariance dimension.

## Adding a new REQ-RD-*

1. Extend `model/*.m` or the Simulink model, then add or extend a `tools/verify_*.m` script that probes it.
2. Append a row to `req_map.csv` with the next available ID, the block or kernel path, and the description.
3. Add a row here in the appropriate stage section with the Source citation.
4. Regenerate `traceability_report.html` via `slreq.generateReport` so CI covers it.

## References cited in the Source column

- **Skolnik, M. I.**, *Introduction to Radar Systems*, McGraw-Hill, 3rd ed. 2001. The monostatic pulse radar equation, matched-filter theory, and Doppler processing all trace to this reference (chapters 2, 3, 6).
- **Richards, M. A.**, *Fundamentals of Radar Signal Processing*, McGraw-Hill, 2nd ed. 2014. Modern reference for MVDR/Capon adaptive beamforming derivation and Doppler processing via slow-time FFT.
- **Van Trees, H. L.**, *Optimum Array Processing (Detection, Estimation, and Modulation Theory, Part IV)*, Wiley, 2002. Steering vector, covariance conventions, adaptive-array fundamentals.
- **Capon, J.** (1969), *High-Resolution Frequency-Wavenumber Spectrum Analysis*, Proc. IEEE 57(8):1408-1418. Original MVDR / Capon beamformer derivation.
- **Carlson, B. D.** (1988), *Covariance Matrix Estimation Errors and Diagonal Loading in Adaptive Arrays*, IEEE Trans. AES 24(4):397-401. Diagonal-loading rationale.
- **Rohling, H.** (1983), *Radar CFAR Thresholding in Clutter and Multiple Target Situations*, IEEE Trans. AES-19(4):608-621. Source of the `alpha = N·(Pfa^(-1/N) - 1)` CA-CFAR threshold formula.
- **Harris, F. J.** (1978), *On the Use of Windows for Harmonic Analysis with the Discrete Fourier Transform*, Proc. IEEE 66(1):51-83. Sidelobe characterisation used to justify the Hamming window across slow-time.
- **IEEE Std 686-2017**, *IEEE Standard for Radar Definitions*. Terminology reference for PRF, PRI, CPI, unambiguous range, matched filter, etc.
- **SISO-REF-010-2025 v36**, *Reference for Enumerations for Simulation Interoperability*. Used by the CLEARANCE integration to map this radar to Emitter Name `8790 = ASR-9` on DIS Emission PDUs. Free from https://www.sisostandards.org/page/ReferenceDocuments.
