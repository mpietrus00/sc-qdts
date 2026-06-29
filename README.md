# QDTS_SC

SuperCollider UGen plugins for synthesising sounds using Auditory Distortion Products (ADPs).

## Overview

QDTS_SC implements solvers for the system of equations described in Kendall, Haworth and Cadiz (2014) and Gutierrez, Haworth and Cadiz (2024), enabling controlled generation of quadratic difference tone spectra. The solvers calculate the precise carrier amplitudes needed so that the nonlinear response of the cochlea produces a target harmonic spectrum as perceived "phantom tones".

Based on the original Max/MSP implementation by Esteban Gutierrez and Rodrigo Cadiz. The neural network solver uses trained models from [cordutie/qdts](https://github.com/cordutie/qdts).

## Features

- **QDTSSolver** -- Newton's method solver, NRT async dispatch, N = 1-16
- **NQDTSSolver** -- neural network solver, synchronous control-rate, N = 5-16
- **Hybrid mode** -- neural initial guess + Newton refinement iterations
- **QDTS / NQDTS helper classes** -- language-side convenience interface with waveform presets
- **Dynamic spectrum control** -- modulate target harmonics in real time (neural solver handles rapid changes without branch jumping)
- **Normalised output** -- amplitudes are normalised for safe mixing
- **Error output** -- monitor solver convergence quality
- **No external dependencies** -- self-contained C++ with embedded neural network weights

## Installation

### Pre-built binary (macOS arm64, SC 3.14.x)

A pre-built plugin for Apple Silicon is included in `bin/macos-arm64/`.

1. Find your SuperCollider Extensions directory:

```supercollider
Platform.userExtensionDir
```

2. Create `QDTS_SC` inside that directory and copy the following files:

```
Extensions/
  QDTS_SC/
    QDTSSolver.scx           <-- from bin/macos-arm64/
    NQDTSSolver.scx          <-- from bin/macos-arm64/ (neural solver)
    QDTSSolver.sc            <-- from sc-classes/
    NQDTSSolver.sc           <-- from sc-classes/
    HelpSource/
      Classes/
        QDTS.schelp
        QDTSSolver.schelp
        NQDTSSolver.schelp
      Guides/
        QDTS_Guide.schelp
```

3. Recompile the class library: **Cmd+Shift+L**

4. Verify:

```supercollider
QDTSSolver.class;   // -> QDTSSolver
NQDTSSolver.class;  // -> NQDTSSolver
QDTS.class;         // -> QDTS
NQDTS.class;        // -> NQDTS
```

### Building from source

Requires CMake 3.12+ and the SuperCollider source tree (headers only).

```bash
git clone https://github.com/supercollider/supercollider.git /path/to/supercollider

cd QDTS_SC
mkdir build && cd build
cmake .. -DSC_PATH=/path/to/supercollider -DCMAKE_BUILD_TYPE=Release
make -j$(sysctl -n hw.ncpu)
```

The compiled plugins will be at `build/plugins/QDTSSolver.scx` and `build/plugins/NQDTSSolver.scx` (macOS) or `.so` (Linux).

Then follow the same installation steps above, using the freshly built files instead of the pre-built ones.

Note: NQDTSSolver embeds ~6.5 MB of neural network weights. The initial compilation of the weight data file takes ~30 seconds.

## Quick start

```supercollider
s.boot;

(
{
    var targets = [1, 0.5, 0.33, 0.25];
    var amps = QDTSSolver.kr(4, *targets);
    var carrierPitch = 2500;
    var targetPitch = 100;
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)
```

## Usage

### QDTSSolver -- Newton solver

```supercollider
QDTSSolver.kr(numHarmonics, *targets)
```

- `numHarmonics` -- number of target harmonics (1--16, scalar)
- `targets` -- target harmonic amplitudes
- Returns `numHarmonics + 2` values: solved amplitudes + estimation error
- Runs asynchronously on NRT thread

### NQDTSSolver -- Neural solver

```supercollider
NQDTSSolver.kr(numHarmonics, refine, *targets)
```

- `numHarmonics` -- number of target harmonics (5--16, scalar)
- `refine` -- Newton refinement iterations after neural pass (0--16, scalar). Use 0 for pure neural, 3--5 for hybrid precision.
- `targets` -- target harmonic amplitudes
- Returns `numHarmonics + 2` values: solved amplitudes + estimation error (same format as QDTSSolver)
- Runs synchronously on control-rate thread

### Choosing a solver

| | QDTSSolver (Newton) | NQDTSSolver (Neural) |
|---|---|---|
| Thread | NRT async | Control-rate sync |
| N range | 1--16 | 5--16 |
| Dynamic targets | Branch jumping | Smooth continuous |
| Best for | Static targets, N < 5 | Morphing, real-time control |

### Helper classes

```supercollider
// Newton solver
{ QDTS.sawtooth(8, 440).ar(0.2) ! 2 }.play;

// Neural solver
{ NQDTS.sawtooth(8, 440).ar(0.2) ! 2 }.play;

// Neural with refinement
{ NQDTS.sawtooth(8, 440, refine: 5).ar(0.2) ! 2 }.play;

// Presets: .sawtooth, .square, .triangle
```

## Architecture

### QDTSSolver (Newton)

Runs on the NRT thread via `DoAsynchronousCommand`. When target values change, the RT calc function dispatches an async command to the NRT thread, which runs the Newton solver without blocking audio. Results are copied back to the RT thread on completion.

### NQDTSSolver (Neural)

Runs a trained 3-layer MLP (256 hidden units, SiLU/ReLU activations) directly on the control-rate thread. The forward pass takes ~20 microseconds, well within a single control block. Neural network weights from [cordutie/qdts](https://github.com/cordutie/qdts) are embedded as static arrays in the compiled plugin (~6.5 MB for 12 models, one per N=5..16).

The network uses homogeneous scaling: input is normalised to unit length, output is scaled by sqrt(input norm). This allows the network to learn only the mapping on the unit sphere.

Both solvers ensure:
- No audio dropouts
- No heap allocation in the audio thread
- NaN/Inf protection on all outputs

## Important notes

### Target values

**Avoid setting targets to exactly 0** -- this can cause solver instability. Always use a small minimum:

```supercollider
var t0s = t0.max(0.01);
```

### Carrier and target pitch

- **Carrier pitch**: base frequency, should be in the **1--5 kHz range** (typically ~2.5 kHz)
- **Target pitch**: difference frequency (the perceived pitch)
- **Resulting frequencies**: carrier, carrier + target, carrier + 2*target, ...

### Perceptual notes

- Max 16 harmonics: more than 16 QDT harmonics unlikely to be effective
- Continuous sounds work better than transients for perceiving QDTs
- Loudspeakers preferred: QDTs easier to hear over speakers than headphones
- Fatigue: keep durations under 2 minutes at high levels

## Examples

See `examples/QDTS_examples.scd` for comprehensive usage including:
- Basic synthesis and SynthDefs
- Pattern integration (Pbind, Pdef)
- Real-time parameter control
- LFO-modulated spectrum
- Formant shaping (vowel-like sounds)
- Spectral envelope (per-harmonic dynamics)
- Instrumental tone synthesis (clarinet, oboe, flute, trumpet, violin)
- Timbre morphing between instruments

## Verification

See `verification/` for test code:
- `QDTS_verification.scd` -- QDTSSolver convergence and stability tests
- `NQDTS_comparison.scd` -- comprehensive Newton vs Neural vs Hybrid comparison across standard spectra, instrumental profiles, vowel morphing, and dynamic modulation

### Convergence tests

| Spectrum | Harmonics | Error | Status |
|----------|-----------|-------|--------|
| Sawtooth | 4 | ~10^-9 | Pass |
| Sawtooth | 8 | ~10^-6 | Pass |
| Square | 4 | ~10^-4 | Pass |
| Triangle | 4 | ~10^-8 | Pass |
| Formant | 6 | ~10^-5 | Pass |
| Flat | 4 | ~0.3 | Fail (expected) |
| Inverted | 4 | ~2.0 | Fail (expected) |

### Known limitations

- **Flat spectra** (all harmonics equal) are mathematically difficult for the solver
- **Inverted spectra** (upper harmonics stronger than lower) fail to converge
- Best results with natural harmonic decay (sawtooth, triangle, formants)

## References

- Gutierrez, E., Haworth, C., and Cadiz, R. (2024). Generating Sonic Phantoms with Quadratic Difference Tone Spectrum Synthesis. *Computer Music Journal* 47(3):1--16.
- Kendall, G.S., Haworth, C., and Cadiz, R.F. (2014). Sound Synthesis with Auditory Distortion Products. *Computer Music Journal* 38(4).
- Neural QDTS solver and trained models: [cordutie/qdts](https://github.com/cordutie/qdts)

## Credits

Original Max/MSP implementation, solver design, and neural network training: Esteban Gutierrez and Rodrigo Cadiz, based on the theoretical framework developed with Chris Haworth and Gary Kendall.

SuperCollider port: Marcin Pietruszewski

## License

GPL-3.0 -- see [LICENSE](LICENSE) for details.
