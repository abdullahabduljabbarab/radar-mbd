# radar-mbd

Model-Based Design of a **pulsed radar signal-processing chain** in
Simulink. Waveform generation, matched-filter pulse compression,
range-Doppler processing, CFAR detection, and phased-array
beamforming. Auto-code-generated to portable C via Embedded Coder
with reusable-function packaging, so every radar site in the
downstream ATC simulator carries its own instance of the DSP chain
without shared globals.

Integrated live into the [CLEARANCE](https://github.com/) ATC
simulator: every `AClearanceRadarSite` runs the Simulink-generated
signal processing pipeline on incoming IQ samples, feeding detection
decisions back into the operator's radar scope.

## What's in the chain

Standard pulsed-radar architecture:

```
    +--------------------+
    | LFM waveform gen   |  chirp pulse, configurable BW + tau
    +--------------------+
             |
             v
    +--------------------+
    | Phased array Tx    |  beamforming + steering, 8-16 element ULA
    +--------------------+
             |
             v
         (channel)          IQ samples returned from target scene
             |
             v
    +--------------------+
    | Phased array Rx    |  adaptive beamforming (MVDR)
    +--------------------+
             |
             v
    +--------------------+
    | Matched filter     |  pulse compression - correlates against
    |                    |  the transmitted chirp
    +--------------------+
             |
             v
    +--------------------+
    | Range-Doppler proc |  2D FFT: fast-time -> range,
    |                    |  slow-time -> Doppler
    +--------------------+
             |
             v
    +--------------------+
    | CFAR detector      |  cell-averaging threshold, constant
    |                    |  false-alarm rate
    +--------------------+
             |
             v
       Detection decisions (range, velocity, azimuth per hit)
```

## Design choices

- **S-band, 3 GHz nominal** - typical civil surveillance / long-range
  air-defence band. Configurable in `model/radar_params.m`.
- **LFM chirp, 1 microsecond pulse, 1 MHz bandwidth** - matches the
  ASR-9 baseline used in CLEARANCE's C++ radar equation module.
- **8-element uniform linear array** - enough for meaningful beam
  steering + null placement without runtime cost the ATC sim can't
  afford.
- **MVDR beamforming on receive** - adaptive null in the direction of
  a jammer, gain toward the target. Compares against static
  broadside beam for the demo A/B.
- **Cell-averaging CFAR** - the industry-standard detector. Trained
  on cells around the cell under test, threshold set from a target
  false-alarm rate.

## Integration with CLEARANCE

`ClearanceRadarMBD` UE plugin module. Same architecture pattern as
the sister `ClearanceAutopilotMBD` module:

- Per-instance model state - each radar site allocates its own
  `RT_MODEL_radar_T` on first use, so a fleet of radars run
  concurrently without shared globals.
- `AutopilotGeneratedUnit.cpp`-style compilation shim under
  `extern "C"` so UBT compiles the generated `.c` as part of the
  module.
- `Build.cs` auto-detects the drop-in and flips
  `CLEARANCE_RADAR_MBD_HAVE_CODEGEN=1`.

## Repository layout

```
radar_repo/
|-- radar.slx                          <-- Simulink model (source of truth)
|-- model/
|   |-- radar_params.m                 <-- Pt, Gt, Gr, lambda, sigma, R, L
|   |-- waveform_params.m              <-- pulse tau, bandwidth, PRF
|   `-- array_params.m                 <-- element count, spacing, steering
|-- tools/
|   |-- run_model_tests_and_build.m    <-- CI entry point
|   |-- compare_sim.m                  <-- tolerance-based regression
|   |-- configure_reusable_function.m  <-- switch code interface to reusable
|   `-- generate_range_doppler.m       <-- IQ scene generator for the demo
|-- ci_artifacts/                      <-- smoke sim outputs
|-- docs/
|   |-- RADAR_MBD_DESIGN.md
|   `-- img/                           <-- README figures
`-- .github/workflows/ci.yml           <-- MATLAB CI pipeline
```

## Getting started

Open `radar.slx` in Simulink R2023b or later with these toolboxes:

- Simulink
- DSP System Toolbox
- Phased Array System Toolbox
- Embedded Coder
- MATLAB Coder
- Simulink Coder

Run smoke sim + regression check:

```matlab
addpath(genpath(pwd))
run('model/radar_params.m')
run('model/waveform_params.m')
run('model/array_params.m')
sim('radar')
tools/compare_sim
```

Generate C for integration:

```matlab
run('tools/configure_reusable_function.m')
rtwbuild('radar')
```

## License

MIT - see [`LICENSE`](LICENSE).
