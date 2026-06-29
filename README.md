# QDTS_SC

A SuperCollider UGen plugin for synthesising sounds using Auditory Distortion Products (ADPs).

## Overview

QDTS_SC implements a solver for the system of equations described in Kendall, Haworth and Cadiz (2014) and Gutierrez, Haworth and Cadiz (2024), enabling controlled generation of quadratic difference tone spectra. The solver calculates the precise amplitudes needed so that the nonlinear response of the cochlea produces a target harmonic spectrum as perceived "phantom tones".

This is a SuperCollider port of the original Max/MSP implementation by Esteban Gutierrez and Rodrigo Cadiz.

## Features

- **QDTSSolver UGen** -- Newton's method solver with NRT thread offloading for dropout-free audio
- **QDTS helper class** -- language-side convenience interface with waveform presets
- **Dynamic spectrum control** -- modulate target harmonics in real time
- **Normalised output** -- amplitudes are normalised for safe mixing
- **Error output** -- monitor solver convergence quality
- **No external dependencies** -- self-contained C++ (no Eigen required)

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
    QDTSSolver.scx          <-- from bin/macos-arm64/
    QDTSSolver.sc            <-- from sc-classes/
    HelpSource/
      Classes/
        QDTS.schelp
        QDTSSolver.schelp
      Guides/
        QDTS_Guide.schelp
```

3. Recompile the class library: **Cmd+Shift+L**

4. Verify:

```supercollider
QDTSSolver.class;  // -> QDTSSolver
QDTS.class;        // -> QDTS
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

The compiled plugin will be at `build/plugins/QDTSSolver.scx` (macOS) or `build/plugins/QDTSSolver.so` (Linux).

Then follow the same installation steps above, using the freshly built `.scx`/`.so` instead of the pre-built one.

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

### QDTSSolver UGen

```supercollider
QDTSSolver.kr(numHarmonics, *targets)
```

**Inputs:**
- `numHarmonics` -- number of target harmonics (1--16, scalar)
- `targets` -- array of target harmonic amplitudes (must match numHarmonics count)

**Outputs:** array of `numHarmonics + 2` values:
- `[0]` to `[numHarmonics]` -- solved amplitudes (normalised)
- `[numHarmonics + 1]` -- estimation error (lower = better convergence)

### QDTS helper class

```supercollider
// Presets
{ Limiter.ar(QDTS.sawtooth(8, 440).ar(0.2), 0.9) ! 2 }.play;
{ Limiter.ar(QDTS.square(8, 440).ar(0.2), 0.9) ! 2 }.play;
{ Limiter.ar(QDTS.triangle(8, 440).ar(0.2), 0.9) ! 2 }.play;

// Custom targets
~qdts = QDTS(8, 440);
~qdts.targets = [1, 0.5, 0.33, 0.25, 0.2, 0.166, 0.142, 0.125];
{ Limiter.ar(~qdts.ar(0.2), 0.9) ! 2 }.play;
```

## Architecture

The solver runs on the NRT (non-real-time) thread via `DoAsynchronousCommand`. When target values change, the RT calc function dispatches an async command to the NRT thread, which runs the Newton solver without blocking audio. Results are copied back to the RT thread on completion. The first control block outputs zeros until the initial solve completes (typically within a few milliseconds).

This design ensures:
- No audio dropouts during solver computation
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
- Beating and roughness effects
- Spectral envelope (per-harmonic dynamics)
- Pitch glide and vibrato
- Instrumental tone synthesis (clarinet, oboe, flute, trumpet, violin)
- Timbre morphing between instruments

## Verification

The implementation has been verified against a Python reference solver. See `verification/` for test code.

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

## Credits

Original Max/MSP implementation and solver design: Esteban Gutierrez and Rodrigo Cadiz, based on the theoretical framework developed with Chris Haworth and Gary Kendall.

SuperCollider port: Marcin Pietruszewski

## License

GPL-3.0 -- see [LICENSE](LICENSE) for details.
