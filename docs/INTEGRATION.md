# Integration with CLEARANCE

Runtime integration counterpart to
[RADAR_MBD_DESIGN.md](RADAR_MBD_DESIGN.md). The design brief covers
the DSP chain. This document covers how the generated code plugs
into CLEARANCE: how the I/Q cube is synthesised on the sim side, how
the matching layer maps detections back to source aircraft, how
multiple radar sites coexist in one scene, and how the wrapper
interacts with the CLEARANCE electronic warfare model.

## Contents

- [Generated code shape](#generated-code-shape)
- [The wrapper](#the-wrapper)
- [Per-radar state ownership](#per-radar-state-ownership)
- [I/Q cube synthesis](#iq-cube-synthesis)
- [Matching layer](#matching-layer)
- [CPI phase staggering across sites](#cpi-phase-staggering-across-sites)
- [Electronic warfare hooks](#electronic-warfare-hooks)
- [Waveform profiles](#waveform-profiles)
- [Runtime introspection and A/B](#runtime-introspection-and-ab)
- [Where the boundaries sit](#where-the-boundaries-sit)

## Generated code shape

Embedded Coder produces portable ANSI C under
`ThirdParty/RadarGenerated/{include,src}` in the CLEARANCE plugin:

```
ThirdParty/RadarGenerated/
  include/
    RadarSubsystem.h                  generated public header
    RadarSubsystem_types.h            typedefs, enums
    rtwtypes.h                        Embedded Coder core types
  src/
    RadarSubsystem.c                  generated step function
    RadarSubsystem_data.c             generated constants
```

Two symbols matter for integration:

- `RT_MODEL_RadarSubsystem_T` — per-instance model handle. Contains
  covariance matrix history, matched filter state, and CFAR reference
  cell history. One per radar site.
- `RadarSubsystem_step(RT_MODEL_RadarSubsystem_T*, ExtU*, ExtY*)` —
  the entry point. Called from the wrapper with the site's handle,
  its per-CPI input struct, and an output struct.

Reusable Function packaging keeps every site's DSP state private to
its own handle so five radar sites can share the same generated code
without cross-site contamination.

## The wrapper

`ClearanceRadarMBD` is a plugin module inside CLEARANCE at
`Plugins/ClearanceSim/Source/ClearanceRadarMBD/`. Public API:

- `Initialize()` allocates the model handle and runs generated init.
- `Terminate()` runs generated termination and releases the handle.
- `SetIQCube(cube)` writes the synthesised I/Q data for one CPI.
- `SetLookDirection(theta_look)` writes the current steering vector
  input.
- `Step()` calls `RadarSubsystem_step` and reads the detection list.
- `GetDetections()` returns the parsed detection list.

The wrapper never exposes the generated types to the rest of
CLEARANCE. Downstream code sees only POD detection records and
matched track records.

## Per-radar state ownership

Every `UClearanceRadar` actor owns one `FRadarWrapper` by value. The
wrapper's constructor and destructor call `Initialize()` and
`Terminate()` so the model handle lifetime matches the actor
lifetime. A scenario with five radar sites has five wrappers and
five independent model handles.

Each wrapper owns:

- Its own `RT_MODEL_RadarSubsystem_T`.
- Its own last-CPI detection list.
- Its own matched track map (callsign → last detection metadata).

## I/Q cube synthesis

CLEARANCE synthesises the per-CPI receive I/Q cube from the live
airspace state. The synthesis input for each site is:

- Site position and orientation.
- Look direction (site's current steering angle).
- Per-aircraft state: position, velocity, RCS category, EW state.
- Per-aircraft transponder state (used for tag rendering after
  detection, not for the DSP path).
- Per-aircraft self-jamming state (affects the ghost multiplier in
  the matching layer rather than injecting into the cube; see
  [Electronic warfare hooks](#electronic-warfare-hooks)).
- Chaff clouds active in range, per-cloud lifetime.
- Site-local noise floor from `kTBF`.

Synthesis produces an `Nspp × Nelem × Npulses` complex cube where
each aircraft's contribution is a delayed chirp copy with a spatial
phase progression across the array. The cube goes into
`SetIQCube` and the model does the rest.

## Matching layer

The DSP output is a raw detection list (`range, velocity, SNR` per
hit). The CLEARANCE-side matching layer converts detections into
per-callsign tracks:

- Unaliases range using the site's current unambiguous range for
  the active waveform profile (v2 long-range profile gives 810 nm).
- Nearest-neighbour matches each detection to the aircraft whose
  synthesised contribution most likely produced it, using the truth
  state that was used to synthesise the cube.
- Fills in the transponder ID and secondary data on the track from
  the matched aircraft's state.
- Applies the self-jamming confidence multiplier (see below).

Result: a `Tracks` map on `UClearanceRadar` keyed by callsign,
consumed by the operator scope and by the fusion layer.

## CPI phase staggering across sites

Five radar sites in the same scenario would otherwise pile all their
I/Q synthesis onto the same game frame every CPI. The wrapper
staggers per-site CPI phase by hashing the site's `SiteName`, so
each site's `Step()` call lands on a different frame within the CPI
period. Distributes cost across frames without changing the
per-site detection cadence.

## Electronic warfare hooks

Two EW behaviours are wired through the wrapper's matching layer
rather than into the DSP cube itself:

- **Self-jamming.** A jamming aircraft's own return in the matched
  track drops to 30% confidence and its transponder tag is
  suppressed. Every other aircraft on the scope is untouched. This
  matches the operator picture for self-protection jamming: the
  jammer degrades its own visibility, not the sensor as a whole.
  The initial approach of injecting a barrage-noise source into the
  I/Q cube and letting MVDR null it worked as physics but collapsed
  sidelobe gain everywhere off boresight and took every non-boresight
  aircraft with it. See
  [DEVLOG 2026-07-09](../DEVLOG.md#2026-07-09--ew-rewrite).
- **Chaff.** Each active chaff cloud in range produces a five-blip
  primary-only ghost cluster dispersed ±1.2 nm around the cloud
  centre, fading with cloud lifetime (about eight seconds). Ghost
  blips carry no secondary data because chaff has no transponder.

Both are inserted into the `Tracks` map after the DSP step. The
generated code sees a clean cube.

## Waveform profiles

Two waveform profiles ship with the model. The wrapper carries
constants for each and switches between them at build time via a
CLEARANCE preprocessor gate:

| Profile | PRF | fs | tau | BW | Unambig range | Unambig velocity | Use case |
|---|---|---|---|---|---|---|---|
| v1 medium PRF | 4 kHz | 10 MHz | 20 µs | 1 MHz | 20 nm | ±150 m/s | Portfolio demo of full DSP chain including Doppler |
| v2 long-range | 100 Hz | 250 kHz | 100 µs | 100 kHz | 810 nm | ±2.7 m/s | CLEARANCE live operation |

v1 is retained for demonstration of the full DSP chain; v2 is what
CLEARANCE ships. Under v2, Doppler folds too tightly to be usable
for target discrimination so the matching layer uses range only.

## Runtime introspection and A/B

Console commands exposed for debugging and comparison:

- `clearance.radar.mbd.probe [siteName]` — dumps the site's last CPI
  detection list, the matched tracks, and the confidence multipliers
  applied by the matching layer.
- `clearance.radar.mbd.enable` / `clearance.radar.mbd.disable` —
  toggles the whole fleet between the Simulink-generated DSP and
  the built-in analytic radar-equation fallback.
- `clearance.radar.mbd.test` — runs a scripted target scene against
  a single site and prints the returned detection list.

The analytic fallback exists because CLEARANCE has to run cleanly
without the generated model present. `Build.cs` in the module skips
the module link if the generated code directory is absent, and
`UClearanceRadar` falls back to the analytic equation path.

## Where the boundaries sit

```
CLEARANCE::AClearanceAirspaceManager (authoritative aircraft state)
        |
        v
CLEARANCE::UClearanceRadar::TickCPI
        |
        v (synthesise per-site I/Q cube)
CLEARANCE::RadarWrapper::SetIQCube / SetLookDirection
        |
        v
GENERATED::RadarSubsystem_step (waveform gen, MVDR, matched filter,
                                Doppler FFT, CFAR)
        |
        v
CLEARANCE::RadarWrapper::GetDetections
        |
        v (matching layer, EW hooks, confidence multipliers)
CLEARANCE::UClearanceRadar::Tracks (per-callsign)
        |
        v
CLEARANCE::UClearanceMultiRadarFusion (fuses across sites)
        |
        v
Operator scope / instructor scope / coverage heatmap
```

The Simulink boundary sits between `SetIQCube` and `GetDetections`.
Everything upstream is CLEARANCE synthesising a simulated receive
signal; everything downstream is the matching layer converting DSP
output into structured tracks.

## Related material

- [RADAR_MBD_DESIGN.md](RADAR_MBD_DESIGN.md) — the model itself.
- [Requirements.md](../Requirements.md) — REQ IDs verifying model
  behaviour.
- [DEVLOG.md](../DEVLOG.md) — chronological record of design and
  integration decisions.
- CLEARANCE
  [SystemsDesign.md](https://github.com/abdullahabduljabbarab/CLEARANCE/blob/main/Docs/Design/SystemsDesign.md)
  — surrounding sensor stack (fusion, EW, coverage overlay).
