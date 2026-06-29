/*
QDTS_SC - Quadratic Distortion Tone Spectra for SuperCollider
==============================================================

Comprehensive examples demonstrating the QDTSSolver UGen for
Auditory Distortion Product (ADP) synthesis.

Based on:
  Kendall, G.S., Haworth, C., and Cadiz, R.F. (2014).
  "Sound Synthesis with Auditory Distortion Products."
  Computer Music Journal 38(4).

  Gutierrez, E., Haworth, C., and Cadiz, R. (2024).
  "Generating Sonic Phantoms with Quadratic Difference Tone
  Spectrum Synthesis." Computer Music Journal 47(3):1-16.

HOW QDTS WORKS:
  QDTSSolver.kr(numHarmonics, *targets) returns numHarmonics+2 values:
    [0] to [numHarmonics]   -- normalized amplitude coefficients
    [numHarmonics + 1]      -- estimation error

  These amplitudes scale sinusoids at:
    carrierFreq, carrierFreq + targetPitch, carrierFreq + 2*targetPitch, ...

  The ear's nonlinear response to these sinusoids produces quadratic
  difference tones whose harmonic amplitudes approximate the target
  spectrum. The perceived pitch equals targetPitch.

  The solver runs asynchronously on the NRT thread. There is a brief
  latency (~1 control block) before results appear on the first call.

  Carrier frequencies should sit in the 1-5 kHz range (optimal ~2.5 kHz).
  Always clamp target values with .max(0.01) to prevent solver instability.
*/

// Boot the server first
s.boot;

// ============================================================================
// 1. BASIC USAGE
// ============================================================================
Server.killAll; // Stop all running synths
// Simple test -- verify the UGen is working
(
{
    var targets = [1, 0.5, 0.33, 0.25];
    var sig = QDTSSolver.kr(4, *targets);
    sig.poll(2); // Poll outputs at 2 Hz
    Silent.ar;
}.play;
)
// Outputs: [amp0, amp1, amp2, amp3, amp4, error]
// The error should be very small (< 0.001) indicating good convergence

// Basic synthesis with carrier and target pitch
(
{
    var numPartials = 4;
    var carrierPitch = 2500;
    var targetPitch = 100;
    var targets = [1, 0.5, 0.33, 0.25];

    var amps = QDTSSolver.kr(numPartials, *targets);
    var freqs = (numPartials + 1).collect {|i| carrierPitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// ============================================================================
// 2. SYNTHDEF WITH ENVELOPE
// ============================================================================

(
SynthDef(\qdtsEnv, {|out = 0, carrierPitch = 2500, targetPitch = 130,
    amp = 0.2, gate = 1, atk = 0.01, dec = 0.1, sus = 0.7, rel = 0.5,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25|

    // Clamp targets to avoid 0 (causes solver instability)
    var t0s = t0.max(0.01);
    var t1s = t1.max(0.01);
    var t2s = t2.max(0.01);
    var t3s = t3.max(0.01);

    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
    var amps = QDTSSolver.kr(4, t0s, t1s, t2s, t3s);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    var sig = Limiter.ar(sines.sum * env * amp, 0.9);

    Out.ar(out, sig ! 2);
}).add;
)

// Test the SynthDef
x = Synth(\qdtsEnv, [\carrierPitch, 3000, \targetPitch, 10]);
x.set(\gate, 0); // Release

// ============================================================================
// 3. REAL-TIME PARAMETER CONTROL
// ============================================================================

(
SynthDef(\qdtsDynamic, {|out = 0, carrierPitch = 2500, targetPitch = 130, amp = 0.2,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25|

    var t0s = t0.max(0.01);
    var t1s = t1.max(0.01);
    var t2s = t2.max(0.01);
    var t3s = t3.max(0.01);

    var amps = QDTSSolver.kr(4, t0s, t1s, t2s, t3s);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// Play and modulate
x = Synth(\qdtsDynamic);

// Try different spectra
x.set(\t0, 1, \t1, 0.01, \t2, 0.5, \t3, 0.01);    // Square-ish (odd harmonics)
x.set(\t0, 1, \t1, 0.5, \t2, 0.33, \t3, 0.25);    // Sawtooth
x.set(\t0, 1, \t1, 1, \t2, 1, \t3, 1);            // Bright/harsh
x.set(\t0, 1, \t1, 0.1, \t2, 0.05, \t3, 0.02);    // Mellow

// Non-standard spectra (upper harmonic dominant)
x.set(\t0, 0.2, \t1, 1, \t2, 0.1, \t3, 0.1);      // 2nd harmonic dominant (hollow)
x.set(\t0, 0.1, \t1, 0.1, \t2, 1, \t3, 0.1);      // 3rd harmonic dominant (nasal)
x.set(\t0, 0.3, \t1, 0.3, \t2, 0.3, \t3, 1);      // 4th harmonic dominant
x.set(\t0, 0.5, \t1, 0.8, \t2, 1, \t3, 0.6);      // Peak at 3rd, gradual rolloff

// Change pitch
x.set(\carrierPitch, 3000, \targetPitch, 50);
x.set(\carrierPitch, 2500, \targetPitch, 51);

x.free;

// ============================================================================
// 4. PATTERN EXAMPLES
// ============================================================================

// Rhythmic pattern with varying spectrum
(
Pdef(\qdtsRhythm,
    Pbind(
        \instrument, \qdtsEnv,
        \dur, Pseq([0.25, 0.25, 0.5, 0.25, 0.25, 0.25, 0.25], inf),
        \carrierPitch, Pseq([2800, 3000, 3200, 2600], inf),
        \targetPitch, Pwhite(60, 150),
        \amp, 0.15,
        \atk, 0.01,
        \dec, 0.1,
        \sus, 0.6,
        \rel, 0.3,
        // Vary spectrum per note
        \t0, 1,
        \t1, Pwhite(0.2, 0.8),
        \t2, Pwhite(0.1, 0.5),
        \t3, Pwhite(0.05, 0.3),
    )
).play;
)

Pdef(\qdtsRhythm).stop;

// ============================================================================
// 5. LFO-MODULATED SPECTRUM
// ============================================================================

(
SynthDef(\qdtsLFO, {|out = 0, carrierPitch = 2500, targetPitch = 130, amp = 0.2,
    lfoRate = 0.3|

    // LFOs modulate the target spectrum
    var t0 = LFNoise1.kr(lfoRate).range(0.5, 1);
    var t1 = LFNoise1.kr(lfoRate * 0.7).range(0.1, 0.8);
    var t2 = LFNoise1.kr(lfoRate * 0.5).range(0.05, 0.5);
    var t3 = LFNoise1.kr(lfoRate * 0.3).range(0.02, 0.3);

    var amps = QDTSSolver.kr(4, t0, t1, t2, t3);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

y = Synth(\qdtsLFO, [\lfoRate, 0.2]);
y.set(\carrierPitch, 3000, \targetPitch, 180);
y.set(\lfoRate, 3.5);
y.free;

// ============================================================================
// 6. MORE HARMONICS (8 partials)
// ============================================================================

(
SynthDef(\qdts8, {|out = 0, carrierPitch = 2500, targetPitch = 130, amp = 0.15,
    gate = 1, atk = 0.01, dec = 0.1, sus = 0.7, rel = 0.5|

    var numPartials = 8;
    // Sawtooth-like spectrum: 1/n for each harmonic
    var targets = (1..numPartials).collect {|n| (1/n).max(0.01) };

    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
    var amps = QDTSSolver.kr(numPartials, *targets);
    var freqs = (numPartials + 1).collect {|i| carrierPitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

z = Synth(\qdts8, [\carrierPitch, 3000, \targetPitch, 100]);
z.set(\gate, 0);

// ============================================================================
// 7. USING THE QDTS HELPER CLASS
// ============================================================================

// The QDTS class provides a higher-level interface.
// IMPORTANT: QDTS is a language-side helper, not a UGen. Each call to
// .solver, .ar, or .arFM builds new UGen graph nodes. Use once per SynthDef.

// Check if it's loaded
QDTS.class;

// Create with presets
(
{
    var qdts = QDTS.sawtooth(8, 440);
    Limiter.ar(qdts.ar(0.2), 0.9) ! 2
}.play;
)

(
{
    var qdts = QDTS.square(8, 440);
    Limiter.ar(qdts.ar(0.2), 0.9) ! 2
}.play;
)

(
{
    var qdts = QDTS.triangle(8, 440);
    Limiter.ar(qdts.ar(0.2), 0.9) ! 2
}.play;
)

// ============================================================================
// 8. FORMANT SHAPING (Vowel-like Sounds)
// ============================================================================

/*
Formants are resonant frequencies that give vowels their characteristic sound.
By shaping the harmonic spectrum, QDTS can approximate vowel qualities.

These are artistic approximations -- not precise formant synthesis, but they
capture the essential spectral character of each vowel.
*/

(
SynthDef(\qdtsFormant, {|out = 0, carrierPitch = 2500, targetPitch = 150,
    amp = 0.2, t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25, t4 = 0.2, t5 = 0.16|

    var amps = QDTSSolver.kr(6,
        t0.max(0.01), t1.max(0.01), t2.max(0.01),
        t3.max(0.01), t4.max(0.01), t5.max(0.01)
    );
    var freqs = 7.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 7.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// Create synth
x = Synth(\qdtsFormant, [\carrierPitch, 3500, \targetPitch, 150]);

// Vowel presets -- execute each line to hear the difference

// "AH" (as in "father") -- open, strong low harmonics
x.set(\t0, 1, \t1, 0.9, \t2, 0.5, \t3, 0.3, \t4, 0.15, \t5, 0.1);

// "EE" (as in "see") -- bright, emphasis on higher harmonics
x.set(\t0, 1, \t1, 0.3, \t2, 0.2, \t3, 0.5, \t4, 0.7, \t5, 0.4);

// "OO" (as in "boot") -- dark, rapid rolloff
x.set(\t0, 1, \t1, 0.4, \t2, 0.1, \t3, 0.05, \t4, 0.02, \t5, 0.01);

// "EH" (as in "bed") -- mid-range emphasis
x.set(\t0, 1, \t1, 0.7, \t2, 0.8, \t3, 0.4, \t4, 0.2, \t5, 0.1);

// "OH" (as in "go") -- rounded, low-mid emphasis
x.set(\t0, 1, \t1, 0.8, \t2, 0.6, \t3, 0.2, \t4, 0.1, \t5, 0.05);

// "IH" (as in "bit") -- between EE and EH
x.set(\t0, 1, \t1, 0.5, \t2, 0.4, \t3, 0.6, \t4, 0.4, \t5, 0.2);

x.free;

// ----------------------------------------
// Animated vowel sequence
// ----------------------------------------
(
SynthDef(\qdtsVowelSeq, {|out = 0, carrierPitch = 3500, targetPitch = 150, amp = 0.2,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25, t4 = 0.2, t5 = 0.16|

    var amps = QDTSSolver.kr(6,
        t0.max(0.01), t1.max(0.01), t2.max(0.01),
        t3.max(0.01), t4.max(0.01), t5.max(0.01)
    );
    var freqs = 7.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 7.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// Vowel sequence: AH -> EE -> OO -> EH -> OH (loops)
(
~vowels = [
    [1, 0.9, 0.5, 0.3, 0.15, 0.1],   // AH
    [1, 0.3, 0.2, 0.5, 0.7, 0.4],    // EE
    [1, 0.4, 0.1, 0.05, 0.02, 0.01], // OO
    [1, 0.7, 0.8, 0.4, 0.2, 0.1],    // EH
    [1, 0.8, 0.6, 0.2, 0.1, 0.05]    // OH
];
~vowelNames = ["AH", "EE", "OO", "EH", "OH"];

~vowelSynth = Synth(\qdtsVowelSeq);
~vowelRoutine = fork {
    var idx = 0;
    loop {
        var v = ~vowels[idx];
        (~vowelNames[idx] ++ " vowel").postln;
        ~vowelSynth.set(\t0, v[0], \t1, v[1], \t2, v[2], \t3, v[3], \t4, v[4], \t5, v[5]);
        idx = (idx + 1) % ~vowels.size;
        1.5.wait;
    }
};
)

// Stop vowel sequence
(~vowelRoutine.stop; ~vowelSynth.free;)

// ============================================================================
// 9. BEATING AND ROUGHNESS
// ============================================================================

/*
Two QDTS voices slightly detuned create beating (slow) or roughness (fast).
  Detune < 5 Hz:  slow beating, phasing effect
  Detune 5-15 Hz: fast beating, tremolo-like
  Detune 15-30 Hz: roughness, dissonance
  Detune > 30 Hz: separate pitches emerge
*/

(
SynthDef(\qdtsBeating, {|out = 0, carrierPitch = 3500, targetPitch = 100,
    amp = 0.2, detune = 2|

    // Two QDTS voices with slight detune
    var targets = [1, 0.5, 0.33, 0.25];

    var amps1 = QDTSSolver.kr(4, *targets);
    var amps2 = QDTSSolver.kr(4, *targets);

    var freqs1 = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var freqs2 = 5.collect {|i| (carrierPitch + detune) + (i * targetPitch) };

    var sines1 = 5.collect {|i| SinOsc.ar(freqs1[i]) * amps1[i] };
    var sines2 = 5.collect {|i| SinOsc.ar(freqs2[i]) * amps2[i] };

    var sig = (sines1.sum + sines2.sum) * 0.5;

    Out.ar(out, Limiter.ar(sig * amp, 0.9) ! 2);
}).add;
)

// Slow beating (2 Hz) -- gentle phasing
x = Synth(\qdtsBeating, [\detune, 2]);

// Faster beating (8 Hz) -- tremolo-like
x.set(\detune, 8);

// Roughness zone (20 Hz) -- dissonant, tense
x.set(\detune, 20);

// Very rough (35 Hz) -- harsh, two pitches emerging
x.set(\detune, 35);

// Back to gentle
x.set(\detune, 1.5);

x.free;

// ----------------------------------------
// Stereo beating (detuned left/right)
// ----------------------------------------
(
SynthDef(\qdtsStereoBeating, {|out = 0, carrierPitch = 3500, targetPitch = 100,
    amp = 0.2, detune = 3|

    var targets = [1, 0.5, 0.33, 0.25];

    var amps1 = QDTSSolver.kr(4, *targets);
    var amps2 = QDTSSolver.kr(4, *targets);

    // Left channel: base pitch
    var freqsL = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sinesL = 5.collect {|i| SinOsc.ar(freqsL[i]) * amps1[i] };

    // Right channel: detuned
    var freqsR = 5.collect {|i| (carrierPitch + detune) + (i * targetPitch) };
    var sinesR = 5.collect {|i| SinOsc.ar(freqsR[i]) * amps2[i] };

    var sigL = sinesL.sum;
    var sigR = sinesR.sum;

    Out.ar(out, Limiter.ar([sigL, sigR] * amp, 0.9));
}).add;
)

// Creates a widening stereo effect
y = Synth(\qdtsStereoBeating, [\detune, 3]);
y.set(\detune, 5);   // Wider
y.set(\detune, 0.5); // Subtle
y.free;

// ----------------------------------------
// Beating with different spectra per voice
// ----------------------------------------
(
SynthDef(\qdtsSpectralBeating, {|out = 0, carrierPitch = 3500, targetPitch = 100,
    amp = 0.2, detune = 2|

    // Voice 1: Sawtooth-like
    var amps1 = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
    // Voice 2: Hollow (2nd harmonic dominant)
    var amps2 = QDTSSolver.kr(4, 0.3, 1, 0.2, 0.1);

    var freqs1 = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var freqs2 = 5.collect {|i| (carrierPitch + detune) + (i * targetPitch) };

    var sines1 = 5.collect {|i| SinOsc.ar(freqs1[i]) * amps1[i] };
    var sines2 = 5.collect {|i| SinOsc.ar(freqs2[i]) * amps2[i] };

    var sig = (sines1.sum + sines2.sum) * 0.5;

    Out.ar(out, Limiter.ar(sig * amp, 0.9) ! 2);
}).add;
)

// Two different timbres beating against each other
z = Synth(\qdtsSpectralBeating, [\detune, 2]);
z.set(\detune, 5);
z.free;

// ============================================================================
// 10. SPECTRAL ENVELOPE (Per-harmonic dynamics)
// ============================================================================

/*
Different attack/decay times per harmonic creates evolving timbres.
  Fast attack on fundamentals, slow on upper harmonics = "bloom" effect
  Slow attack on all = pad-like
  Fast decay on upper harmonics = natural instrument-like decay
*/

(
SynthDef(\qdtsSpectralEnv, {|out = 0, carrierPitch = 3500, targetPitch = 100,
    amp = 0.3, gate = 1|

    // Different envelope times per harmonic
    var atkTimes = [0.01, 0.05, 0.1, 0.2, 0.3];   // Fundamental fastest
    var relTimes = [0.8, 0.6, 0.4, 0.3, 0.2];     // Upper harmonics decay faster

    var envs = 5.collect {|i|
        EnvGen.kr(Env.perc(atkTimes[i], relTimes[i]), gate)
    };

    // Static target spectrum
    var targets = [1, 0.6, 0.4, 0.25, 0.15];
    var amps = QDTSSolver.kr(5, *targets);

    var freqs = 6.collect {|i| carrierPitch + (i * targetPitch) };
    // Apply per-harmonic envelopes
    var sines = 6.collect {|i| SinOsc.ar(freqs[i]) * amps[i] * envs[i.min(4)] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// Trigger notes -- upper harmonics bloom in after attack
Synth(\qdtsSpectralEnv, [\carrierPitch, 3200, \targetPitch, 100]);
Synth(\qdtsSpectralEnv, [\carrierPitch, 3500, \targetPitch, 120]);
Synth(\qdtsSpectralEnv, [\carrierPitch, 3800, \targetPitch, 80]);

// ----------------------------------------
// Reverse spectral envelope (upper harmonics attack first)
// ----------------------------------------
(
SynthDef(\qdtsReverseEnv, {|out = 0, carrierPitch = 3500, targetPitch = 100,
    amp = 0.3, gate = 1|

    // Upper harmonics attack first, fundamental last
    var atkTimes = [0.3, 0.2, 0.1, 0.05, 0.01];
    var relTimes = [0.5, 0.5, 0.5, 0.5, 0.5];

    var envs = 5.collect {|i|
        EnvGen.kr(Env.perc(atkTimes[i], relTimes[i]), gate)
    };

    var targets = [1, 0.6, 0.4, 0.25, 0.15];
    var amps = QDTSSolver.kr(5, *targets);

    var freqs = 6.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 6.collect {|i| SinOsc.ar(freqs[i]) * amps[i] * envs[i.min(4)] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// "Reverse bloom" -- brightness arrives before body
Synth(\qdtsReverseEnv, [\carrierPitch, 3400, \targetPitch, 110]);

// ----------------------------------------
// Sustained with spectral shimmer
// ----------------------------------------
(
SynthDef(\qdtsShimmer, {|out = 0, carrierPitch = 3500, targetPitch = 100,
    amp = 0.2, gate = 1, atk = 0.3, rel = 1.0|

    var mainEnv = EnvGen.kr(Env.asr(atk, 1, rel), gate, doneAction: 2);

    // Each harmonic has slight independent movement
    var shimmer = 5.collect {|i|
        LFNoise1.kr(0.5 + (i * 0.2)).range(0.7, 1.0)
    };

    var targets = [1, 0.5, 0.33, 0.25, 0.2];
    var amps = QDTSSolver.kr(5, *targets);

    var freqs = 6.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 6.collect {|i| SinOsc.ar(freqs[i]) * amps[i] * shimmer[i.min(4)] };

    Out.ar(out, Limiter.ar(sines.sum * mainEnv * amp, 0.9) ! 2);
}).add;
)

// Sustained shimmering tone
x = Synth(\qdtsShimmer);
x.set(\gate, 0);  // Release

// ----------------------------------------
// Pattern: Blooming melody
// ----------------------------------------
(
Pdef(\bloomMelody,
    Pbind(
        \type, \on,
        \instrument, \qdtsSpectralEnv,
        \dur, 0.5,
        \carrierPitch, Pseq([3200, 3350, 3500, 3350, 3200, 3100, 3200, 3350], inf),
        \targetPitch, Pseq([100, 110, 120, 110, 100, 90, 100, 110], inf),
        \amp, 0.25
    )
).play;
)

Pdef(\bloomMelody).stop;

// ============================================================================
// 11. GALLOPING RHYTHM (Tempo-dependent streaming)
// ============================================================================

/*
Classic auditory scene analysis demo: ABA_ABA_ pattern
  At slow tempos: hear integrated "gallop" rhythm (da-da-DUM)
  At fast tempos: segregates into two separate streams (A-A-A... and B...B...)

Based on: Bregman, A.S. (1990). Auditory Scene Analysis. MIT Press.
*/

(
SynthDef(\qdtsGallop, {|out = 0, carrierPitch = 3000, targetPitch = 100,
    amp = 0.15, atk = 0.005, rel = 0.1|

    var env = EnvGen.kr(Env.perc(atk, rel), doneAction: 2);
    var amps = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// ----------------------------------------
// Slow gallop -- hear as integrated ABA rhythm
// ----------------------------------------
(
~gallopA = 3000;  // Low pitch
~gallopB = 4600;  // High pitch

~gallopSlow = fork {
    loop {
        Synth(\qdtsGallop, [\carrierPitch, ~gallopA, \rel, 0.15]);
        0.3.wait;
        Synth(\qdtsGallop, [\carrierPitch, ~gallopB, \rel, 0.15]);
        0.3.wait;
        Synth(\qdtsGallop, [\carrierPitch, ~gallopA, \rel, 0.15]);
        0.3.wait;
        0.3.wait;  // Rest
    }
};
)

~gallopSlow.stop;

// ----------------------------------------
// Fast gallop -- segregates into two streams
// ----------------------------------------
(
~gallopFast = fork {
    loop {
        Synth(\qdtsGallop, [\carrierPitch, ~gallopA, \rel, 0.06]);
        0.1.wait;
        Synth(\qdtsGallop, [\carrierPitch, ~gallopB, \rel, 0.06]);
        0.1.wait;
        Synth(\qdtsGallop, [\carrierPitch, ~gallopA, \rel, 0.06]);
        0.1.wait;
        0.1.wait;  // Rest
    }
};
)

~gallopFast.stop;

// ----------------------------------------
// Accelerating gallop -- hear the transition
// ----------------------------------------
(
~gallopAccel = fork {
    var dur = 0.35;
    100.do {
        Synth(\qdtsGallop, [\carrierPitch, ~gallopA, \rel, dur * 0.5]);
        dur.wait;
        Synth(\qdtsGallop, [\carrierPitch, ~gallopB, \rel, dur * 0.5]);
        dur.wait;
        Synth(\qdtsGallop, [\carrierPitch, ~gallopA, \rel, dur * 0.5]);
        dur.wait;
        dur.wait;  // Rest
        dur = (dur * 0.97).max(0.08);
        ("Tempo: " ++ (60 / dur / 4).round(1) ++ " BPM").postln;
    };
    "Done -- did you hear the streams separate?".postln;
};
)

~gallopAccel.stop;

// ============================================================================
// 12. PITCH GLIDE (Carrier sweeps)
// ============================================================================

/*
Sweeping the carrier pitch while maintaining spectral shape creates
glissando effects. The perceived pitch follows the target pitch spacing,
while the carrier determines the register/brightness.
*/

(
SynthDef(\qdtsGlide, {|out = 0, carrierStart = 1500, carrierEnd = 3000,
    targetPitch = 100, amp = 0.2, dur = 2|

    var carrierPitch = Line.kr(carrierStart, carrierEnd, dur, doneAction: 2);
    var env = EnvGen.kr(Env.linen(0.05, dur - 0.1, 0.05));

    var amps = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// Rising glide
Synth(\qdtsGlide, [\carrierStart, 1500, \carrierEnd, 3500, \dur, 2]);

// Falling glide
Synth(\qdtsGlide, [\carrierStart, 3500, \carrierEnd, 1500, \dur, 3]);

// Fast sweep
Synth(\qdtsGlide, [\carrierStart, 1500, \carrierEnd, 4000, \dur, 0.5]);

// ----------------------------------------
// Exponential glide (more musical)
// ----------------------------------------
(
SynthDef(\qdtsExpGlide, {|out = 0, carrierStart = 1500, carrierEnd = 3000,
    targetPitch = 100, amp = 0.2, sustain = 2, atk = 0.02, rel = 0.05|

    var glideDur = sustain.max(0.1);
    var carrierPitch = XLine.kr(carrierStart, carrierEnd, glideDur);
    var env = EnvGen.kr(Env.linen(atk, glideDur - atk - rel, rel), doneAction: 2);

    var amps = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// Exponential rise (octave glide)
Synth(\qdtsExpGlide, [\carrierStart, 1500, \carrierEnd, 3000, \sustain, 2]);

// ----------------------------------------
// Vibrato (pitch oscillation)
// ----------------------------------------
(
SynthDef(\qdtsVibrato, {|out = 0, carrierPitch = 2500, targetPitch = 100,
    amp = 0.2, vibRate = 5, vibDepth = 30|

    var vibrato = SinOsc.kr(vibRate) * vibDepth;
    var pitch = carrierPitch + vibrato;

    var amps = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
    var freqs = 5.collect {|i| pitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// Gentle vibrato
x = Synth(\qdtsVibrato, [\vibRate, 5, \vibDepth, 20]);

// Wide, slow vibrato
x.set(\vibRate, 3, \vibDepth, 50);

// Fast, narrow vibrato (shimmer)
x.set(\vibRate, 8, \vibDepth, 10);

x.free;

// ----------------------------------------
// Pattern: Gliding melody
// ----------------------------------------
(
Pdef(\glideMelody,
    Pbind(
        \instrument, \qdtsExpGlide,
        \dur, 0.8,
        \sustain, 0.75,
        \atk, 0.02,
        \rel, 0.08,
        \carrierStart, Pseq([3000, 3200, 3400, 3200], inf),
        \carrierEnd, Pseq([1500, 1700, 1900, 1300], inf),
        \targetPitch, 100,
        \amp, 0.2
    )
).play;
)

Pdef(\glideMelody).stop;

// ----------------------------------------
// Siren effect (continuous up/down)
// ----------------------------------------
(
SynthDef(\qdtsSiren, {|out = 0, carrierLow = 1500, carrierHigh = 3500,
    targetPitch = 100, amp = 0.2, rate = 0.5|

    var carrierPitch = SinOsc.kr(rate).range(carrierLow, carrierHigh);

    var amps = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
    var freqs = 5.collect {|i| carrierPitch + (i * targetPitch) };
    var sines = 5.collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

// Slow siren
x = Synth(\qdtsSiren, [\rate, 0.3]);

// Faster siren
x.set(\rate, 1);

// Ambulance-style
x.set(\rate, 2, \carrierLow, 2000, \carrierHigh, 3000);

x.free;


// ============================================================================
// 13. INSTRUMENTAL TONE SYNTHESIS
// ============================================================================

/*
QDTS can approximate characteristic instrumental timbres by setting target
spectra that match the harmonic amplitude profiles of acoustic instruments.

The spectral profiles below are drawn from standard acoustics references
(e.g., Fletcher & Rossing, Campbell & Greated, Benade). Each instrument
has a characteristic distribution of energy across harmonics.

IMPORTANT CAVEAT: These are simplified static approximations. Real
instruments have time-varying spectra (attack transients, vibrato,
register-dependent timbral shifts) and inharmonicity. QDTS captures only
the steady-state spectral envelope. The resulting sound is a "phantom"
timbre -- perceived through distortion products rather than direct
acoustic radiation.

8 harmonics are used throughout for a good balance of timbral richness
and solver reliability.
*/

// ----------------------------------------
// 13a. Generic 8-harmonic instrument SynthDef
// ----------------------------------------
(
SynthDef(\qdtsInstrument, {|out = 0, carrierPitch = 2500, targetPitch = 220,
    amp = 0.2, gate = 1, atk = 0.02, dec = 0.1, sus = 0.8, rel = 0.3,
    vibRate = 0, vibDepth = 0,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25,
    t4 = 0.2, t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var numPartials = 8;
    var vibrato = SinOsc.kr(vibRate) * vibDepth;
    var pitch = carrierPitch + vibrato;

    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    var amps = QDTSSolver.kr(numPartials,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01)
    );

    var freqs = (numPartials + 1).collect {|i| pitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// ----------------------------------------
// 13b. Clarinet
// ----------------------------------------
/*
The clarinet (cylindrical closed bore) strongly favors odd harmonics.
Even harmonics are suppressed due to the bore geometry. The 1st, 3rd,
5th, and 7th harmonics dominate, with rapid decay of even-numbered
partials. This produces the characteristic "hollow" quality.

Harmonic profile (mid register, sustained):
  H1=1.0  H2=0.05  H3=0.75  H4=0.04  H5=0.5  H6=0.03  H7=0.3  H8=0.02
*/
(
~clarinet = {|pitch = 220|
    Synth(\qdtsInstrument, [
        \carrierPitch, 2500,
        \targetPitch, pitch,
        \amp, 0.2,
        \atk, 0.08, \dec, 0.05, \sus, 0.9, \rel, 0.15,
        \vibRate, 4.5, \vibDepth, 8,
        // Odd harmonics dominant, even harmonics suppressed
        \t0, 1.0,  \t1, 0.05, \t2, 0.75, \t3, 0.04,
        \t4, 0.5,  \t5, 0.03, \t6, 0.3,  \t7, 0.02
    ]);
};
)

x = ~clarinet.(220);   // A3
x.set(\gate, 0);

x = ~clarinet.(261.6); // C4
x.set(\gate, 0);

// ----------------------------------------
// 13c. Oboe
// ----------------------------------------
/*
The oboe (conical bore, double reed) has all harmonics present with
a characteristic peak around the 2nd-4th harmonics that gives it its
penetrating, nasal quality. The spectral energy is spread more evenly
than most woodwinds.

Harmonic profile (mid register):
  H1=0.8  H2=1.0  H3=0.9  H4=0.7  H5=0.5  H6=0.35  H7=0.25  H8=0.15
*/
(
~oboe = {|pitch = 440|
    Synth(\qdtsInstrument, [
        \carrierPitch, 2500,
        \targetPitch, pitch,
        \amp, 0.2,
        \atk, 0.04, \dec, 0.08, \sus, 0.85, \rel, 0.12,
        \vibRate, 5, \vibDepth, 6,
        // Peak at H2-H3, gradual rolloff from H4
        \t0, 0.8,  \t1, 1.0,  \t2, 0.9,  \t3, 0.7,
        \t4, 0.5,  \t5, 0.35, \t6, 0.25, \t7, 0.15
    ]);
};
)

x = ~oboe.(440);  // A4
x.set(\gate, 0);

x = ~oboe.(349.2); // F4
x.set(\gate, 0);

// ----------------------------------------
// 13d. Flute
// ----------------------------------------
/*
The flute is strongly fundamental-dominant with rapid spectral rolloff.
The near-sinusoidal quality (especially in the upper register) comes
from the open cylindrical bore driven by an air jet. Upper harmonics
are present but weak, contributing breathiness more than pitch content.

Harmonic profile (mid register):
  H1=1.0  H2=0.3  H3=0.1  H4=0.03  H5=0.01  H6=0.01  H7=0.01  H8=0.01
*/
(
~flute = {|pitch = 523.3|
    Synth(\qdtsInstrument, [
        \carrierPitch, 2500,
        \targetPitch, pitch,
        \amp, 0.2,
        \atk, 0.12, \dec, 0.05, \sus, 0.85, \rel, 0.2,
        \vibRate, 5, \vibDepth, 5,
        // Fundamental dominant, steep rolloff
        \t0, 1.0,  \t1, 0.3,  \t2, 0.1,  \t3, 0.03,
        \t4, 0.01, \t5, 0.01, \t6, 0.01, \t7, 0.01
    ]);
};
)

x = ~flute.(523.3); // C5
x.set(\gate, 0);

x = ~flute.(880); // A5
x.set(\gate, 0);

// ----------------------------------------
// 13e. Trumpet
// ----------------------------------------
/*
The trumpet has a rich harmonic spectrum with relatively slow rolloff.
The cup mouthpiece and flared bell produce strong upper harmonics that
give the instrument its brilliant, projecting quality. All harmonics
contribute significantly through about the 8th partial.

Harmonic profile (mid register, mezzo-forte):
  H1=1.0  H2=0.9  H3=0.7  H4=0.6  H5=0.5  H6=0.4  H7=0.3  H8=0.2
*/
(
~trumpet = {|pitch = 349.2|
    Synth(\qdtsInstrument, [
        \carrierPitch, 2500,
        \targetPitch, pitch,
        \amp, 0.2,
        \atk, 0.03, \dec, 0.05, \sus, 0.9, \rel, 0.1,
        \vibRate, 5.5, \vibDepth, 8,
        // Rich spectrum, slow rolloff -- brilliant quality
        \t0, 1.0, \t1, 0.9, \t2, 0.7, \t3, 0.6,
        \t4, 0.5, \t5, 0.4, \t6, 0.3, \t7, 0.2
    ]);
};
)

x = ~trumpet.(349.2); // F4
x.set(\gate, 0);

x = ~trumpet.(466.2); // Bb4
x.set(\gate, 0);

// ----------------------------------------
// 13f. Violin
// ----------------------------------------
/*
The violin has a complex harmonic structure dependent on register,
bowing position, and dynamics. In mid-register sustained playing, the
spectrum shows strong presence through the first 6-8 harmonics. The
bowed string excitation maintains energy across a wide spectral range.

Harmonic profile (mid register, sustained):
  H1=1.0  H2=0.8  H3=0.6  H4=0.5  H5=0.4  H6=0.3  H7=0.2  H8=0.15
*/
(
~violin = {|pitch = 440|
    Synth(\qdtsInstrument, [
        \carrierPitch, 2500,
        \targetPitch, pitch,
        \amp, 0.2,
        \atk, 0.08, \dec, 0.1, \sus, 0.85, \rel, 0.2,
        \vibRate, 5.5, \vibDepth, 10,
        // Rich, gradually decaying spectrum
        \t0, 1.0, \t1, 0.8, \t2, 0.6, \t3, 0.5,
        \t4, 0.4, \t5, 0.3, \t6, 0.2, \t7, 0.15
    ]);
};
)

x = ~violin.(3240);  // A4
x.set(\gate, 0);

x = ~violin.(659.3); // E5
x.set(\gate, 0);

// ----------------------------------------
// 13g. Instrument comparison
// ----------------------------------------
/*
Play the same pitch on different instruments to hear the timbral
differences produced by different harmonic amplitude profiles.
*/
(
fork {
    "Clarinet A4...".postln;
    x = ~clarinet.(440);
    2.wait;
    x.set(\gate, 0);
    0.5.wait;

    "Oboe A4...".postln;
    x = ~oboe.(440);
    2.wait;
    x.set(\gate, 0);
    0.5.wait;

    "Flute A5 (octave up for idiomatic range)...".postln;
    x = ~flute.(880);
    2.wait;
    x.set(\gate, 0);
    0.5.wait;

    "Trumpet A4...".postln;
    x = ~trumpet.(440);
    2.wait;
    x.set(\gate, 0);
    0.5.wait;

    "Violin A4...".postln;
    x = ~violin.(440);
    2.wait;
    x.set(\gate, 0);
    0.5.wait;

    "Comparison complete.".postln;
};
)

// ----------------------------------------
// 13h. Instrument melody pattern
// ----------------------------------------
(
SynthDef(\qdtsEnv8, {|out = 0, carrierPitch = 2500, targetPitch = 130,
    amp = 0.2, gate = 1, atk = 0.02, dec = 0.1, sus = 0.7, rel = 0.3,
    vibRate = 0, vibDepth = 0,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25,
    t4 = 0.2, t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var numPartials = 8;
    var vibrato = SinOsc.kr(vibRate) * vibDepth;
    var pitch = carrierPitch + vibrato;

    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    var amps = QDTSSolver.kr(numPartials,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01)
    );

    var freqs = (numPartials + 1).collect {|i| pitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// Clarinet melody
(
Pdef(\clarinetMelody,
    Pbind(
        \instrument, \qdtsEnv8,
        \dur, Pseq([0.5, 0.5, 1, 0.5, 0.5, 0.5, 0.5, 1], inf),
        \carrierPitch, 2500,
        \targetPitch, Pseq([220, 247, 262, 294, 330, 294, 262, 247], inf),
        \amp, 0.2,
        \atk, 0.08, \dec, 0.05, \sus, 0.85, \rel, 0.15,
        \vibRate, 4.5, \vibDepth, 6,
        // Clarinet spectrum
        \t0, 1.0,  \t1, 0.05, \t2, 0.75, \t3, 0.04,
        \t4, 0.5,  \t5, 0.03, \t6, 0.3,  \t7, 0.02
    )
).play;
)

Pdef(\clarinetMelody).stop;

// Trumpet fanfare
(
Pdef(\trumpetFanfare,
    Pbind(
        \instrument, \qdtsEnv8,
        \dur, Pseq([0.25, 0.25, 0.5, 0.25, 0.25, 1, 0.5], inf),
        \carrierPitch, 2500,
        \targetPitch, Pseq([349, 349, 440, 523, 440, 349, 349], inf),
        \amp, 0.2,
        \atk, 0.03, \dec, 0.05, \sus, 0.9, \rel, 0.1,
        \vibRate, 5, \vibDepth, 5,
        // Trumpet spectrum
        \t0, 1.0, \t1, 0.9, \t2, 0.7, \t3, 0.6,
        \t4, 0.5, \t5, 0.4, \t6, 0.3, \t7, 0.2
    )
).play;
)

Pdef(\trumpetFanfare).stop;


// ============================================================================
// 14. INSTRUMENTAL TONE WITH SPECTRAL ENVELOPE
// ============================================================================

/*
Realistic instruments have time-varying spectra: upper harmonics arrive
and decay at different rates. Combining QDTS harmonic profiles with
per-partial envelopes creates more convincing instrumental attacks.
*/

// ----------------------------------------
// 14a. Clarinet with spectral attack
// ----------------------------------------
/*
Clarinet attacks begin with a brief burst of even harmonics (the "chiff")
before settling into the odd-harmonic steady state. We approximate this
by giving even harmonics a faster attack and shorter sustain.
*/
(
SynthDef(\qdtsClarinetAttack, {|out = 0, carrierPitch = 2500, targetPitch = 220,
    amp = 0.2, gate = 1|

    var numPartials = 8;
    // Per-harmonic envelopes: odd harmonics sustain, even harmonics decay
    var atkTimes = [0.08, 0.01, 0.06, 0.01, 0.05, 0.01, 0.04, 0.01, 0.03];
    var decTimes = [0.05, 0.2, 0.05, 0.15, 0.05, 0.12, 0.05, 0.1, 0.05];
    var susLevels = [0.9, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02, 0.2];
    var relTimes = [0.15, 0.05, 0.12, 0.05, 0.1, 0.05, 0.08, 0.05, 0.06];

    var envs = (numPartials + 1).collect {|i|
        EnvGen.kr(Env.adsr(atkTimes[i], decTimes[i], susLevels[i], relTimes[i]),
            gate, doneAction: if(i == 0, 2, 0))
    };

    // Clarinet steady-state targets
    var amps = QDTSSolver.kr(numPartials,
        1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02
    );

    var vibrato = SinOsc.kr(4.5) * 6;
    var pitch = carrierPitch + vibrato;
    var freqs = (numPartials + 1).collect {|i| pitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] * envs[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

x = Synth(\qdtsClarinetAttack, [\targetPitch, 262]);
x.set(\gate, 0);

// ----------------------------------------
// 14b. Trumpet with brass attack
// ----------------------------------------
/*
Brass attack transients show upper harmonics arriving progressively.
The lower harmonics establish first, with brightness building over
10-50 ms depending on the attack type.
*/
(
SynthDef(\qdtsTrumpetAttack, {|out = 0, carrierPitch = 2500, targetPitch = 349,
    amp = 0.2, gate = 1|

    var numPartials = 8;
    // Progressive attack: lower harmonics first, upper harmonics bloom in
    var atkTimes = [0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09];
    var envs = (numPartials + 1).collect {|i|
        EnvGen.kr(Env.adsr(atkTimes[i], 0.08, 0.9, 0.1),
            gate, doneAction: if(i == 0, 2, 0))
    };

    // Trumpet targets
    var amps = QDTSSolver.kr(numPartials,
        1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2
    );

    var vibrato = SinOsc.kr(5.5) * 8;
    var pitch = carrierPitch + vibrato;
    var freqs = (numPartials + 1).collect {|i| pitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] * envs[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

x = Synth(\qdtsTrumpetAttack, [\targetPitch, 440]);
x.set(\gate, 0);

// ----------------------------------------
// 14c. Violin with bowing attack
// ----------------------------------------
/*
Bowed string attacks show the Helmholtz motion establishing over
several cycles. Higher harmonics build in as the bow-string system
reaches steady state. We model this with staggered attack times
and slight per-harmonic tremolo (simulating bow pressure fluctuations).
*/
(
SynthDef(\qdtsViolinBow, {|out = 0, carrierPitch = 2500, targetPitch = 440,
    amp = 0.2, gate = 1|

    var numPartials = 8;
    // Bowing attack: fundamental first, harmonics fill in
    var atkTimes = [0.06, 0.08, 0.1, 0.12, 0.15, 0.18, 0.2, 0.22, 0.25];
    var envs = (numPartials + 1).collect {|i|
        EnvGen.kr(Env.adsr(atkTimes[i], 0.1, 0.85, 0.2),
            gate, doneAction: if(i == 0, 2, 0))
    };

    // Slight per-harmonic tremolo (bow pressure variations)
    var tremolo = (numPartials + 1).collect {|i|
        LFNoise1.kr(3 + (i * 0.5)).range(0.9, 1.0)
    };

    // Violin targets
    var amps = QDTSSolver.kr(numPartials,
        1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.15
    );

    var vibrato = SinOsc.kr(5.5) * 10;
    var pitch = carrierPitch + vibrato;
    var freqs = (numPartials + 1).collect {|i| pitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i|
        SinOsc.ar(freqs[i]) * amps[i] * envs[i] * tremolo[i]
    };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

x = Synth(\qdtsViolinBow, [\targetPitch, 440]);
x.set(\gate, 0);

x = Synth(\qdtsViolinBow, [\targetPitch, 659.3]); // E5
x.set(\gate, 0);


// ============================================================================
// 15. SPEECH / VOWEL FORMANT SYNTHESIS
// ============================================================================

/*
Speech vowels are characterized by formant frequencies -- resonances of
the vocal tract. The perceived vowel quality depends on the positions
of the first three formants (F1, F2, F3). By computing harmonic
amplitude profiles that approximate these formant shapes, QDTS can
produce vowel-like timbres.

The approach:
  1. Given a fundamental frequency (targetPitch), compute the harmonic
     series: f0, 2*f0, 3*f0, ...
  2. For each harmonic, evaluate the combined energy from overlapping
     formant peaks (modeled as Gaussian resonances)
  3. Use the resulting amplitude profile as QDTS targets

Below we provide both pre-computed profiles (for fixed f0) and a
dynamic version that can adapt to different pitches.

Standard formant data (adult male, from Peterson & Barney 1952):
  /a/ (father): F1=730  F2=1090 F3=2440 Hz
  /i/ (see):    F1=270  F2=2290 F3=3010 Hz
  /u/ (boot):   F1=300  F2=870  F3=2240 Hz
  /e/ (bed):    F1=530  F2=1840 F3=2480 Hz
  /o/ (go):     F1=570  F2=840  F3=2410 Hz
*/

// ----------------------------------------
// 15a. Pre-computed vowel profiles (f0 = 150 Hz, 8 harmonics)
// ----------------------------------------
/*
These profiles were computed by evaluating the combined formant
resonance at each harmonic frequency of a 150 Hz fundamental:
  H1=150, H2=300, H3=450, H4=600, H5=750, H6=900, H7=1050, H8=1200

Each formant is modeled as a Gaussian peak with bandwidth ~100 Hz.
The resulting amplitudes are normalized so the maximum equals 1.0.
*/
(
SynthDef(\qdtsVowelFormant, {|out = 0, carrierPitch = 2500, targetPitch = 150,
    amp = 0.2, gate = 1, atk = 0.05, dec = 0.1, sus = 0.8, rel = 0.2,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25,
    t4 = 0.2, t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var numPartials = 8;
    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    var amps = QDTSSolver.kr(numPartials,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01)
    );

    var freqs = (numPartials + 1).collect {|i| carrierPitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// /a/ (father) -- F1=730, F2=1090: energy concentrated in H4-H7
// Strong mid-range harmonics, open quality
x = Synth(\qdtsVowelFormant, [
    \carrierPitch, 2500, \targetPitch, 150,
    \t0, 0.15, \t1, 0.3,  \t2, 0.55, \t3, 0.85,
    \t4, 1.0,  \t5, 0.7,  \t6, 0.9,  \t7, 0.5
]);
x.set(\gate, 0);

// /i/ (see) -- F1=270, F2=2290: energy at H2 and very high
// Weak fundamental, bright upper harmonics
x = Synth(\qdtsVowelFormant, [
    \carrierPitch, 2500, \targetPitch, 150,
    \t0, 0.3,  \t1, 0.8,  \t2, 0.2,  \t3, 0.1,
    \t4, 0.08, \t5, 0.07, \t6, 0.06, \t7, 0.05
]);
x.set(\gate, 0);

// /u/ (boot) -- F1=300, F2=870: energy at H2 and H5-H6
// Dark, closed quality with strong fundamental
x = Synth(\qdtsVowelFormant, [
    \carrierPitch, 2500, \targetPitch, 150,
    \t0, 0.6,  \t1, 1.0,  \t2, 0.35, \t3, 0.2,
    \t4, 0.5,  \t5, 0.8,  \t6, 0.3,  \t7, 0.15
]);
x.set(\gate, 0);

// /e/ (bed) -- F1=530, F2=1840: energy at H3-H4 and high harmonics
// Mid emphasis, slightly nasal
x = Synth(\qdtsVowelFormant, [
    \carrierPitch, 2500, \targetPitch, 150,
    \t0, 0.2,  \t1, 0.4,  \t2, 0.8,  \t3, 1.0,
    \t4, 0.6,  \t5, 0.3,  \t6, 0.2,  \t7, 0.15
]);
x.set(\gate, 0);

// /o/ (go) -- F1=570, F2=840: energy at H3-H6
// Rounded, low-mid emphasis
x = Synth(\qdtsVowelFormant, [
    \carrierPitch, 2500, \targetPitch, 150,
    \t0, 0.25, \t1, 0.5,  \t2, 0.75, \t3, 1.0,
    \t4, 0.85, \t5, 0.9,  \t6, 0.4,  \t7, 0.2
]);
x.set(\gate, 0);

// ----------------------------------------
// 15b. Vowel morphing sequence
// ----------------------------------------
/*
Smooth interpolation between vowel spectra.
The solver adapts in real-time as targets change.
*/
(
~vowelProfiles = Dictionary[
    \a -> [0.15, 0.3,  0.55, 0.85, 1.0,  0.7,  0.9,  0.5],
    \i -> [0.3,  0.8,  0.2,  0.1,  0.08, 0.07, 0.06, 0.05],
    \u -> [0.6,  1.0,  0.35, 0.2,  0.5,  0.8,  0.3,  0.15],
    \e -> [0.2,  0.4,  0.8,  1.0,  0.6,  0.3,  0.2,  0.15],
    \o -> [0.25, 0.5,  0.75, 1.0,  0.85, 0.9,  0.4,  0.2]
];
~vowelOrder = [\a, \e, \i, \o, \u];
~vowelLabels = Dictionary[
    \a -> "/a/ (father)",
    \e -> "/e/ (bed)",
    \i -> "/i/ (see)",
    \o -> "/o/ (go)",
    \u -> "/u/ (boot)"
];

~morphSynth = Synth(\qdtsVowelFormant, [\carrierPitch, 2500, \targetPitch, 150]);

~morphRoutine = fork {
    var idx = 0;
    loop {
        var vowel = ~vowelOrder[idx];
        var profile = ~vowelProfiles[vowel];
        (~vowelLabels[vowel]).postln;
        8.do {|i|
            ~morphSynth.set(("t" ++ i).asSymbol, profile[i]);
        };
        idx = (idx + 1) % ~vowelOrder.size;
        1.5.wait;
    };
};
)

// Stop morphing
(~morphRoutine.stop; ~morphSynth.free;)

// ----------------------------------------
// 15c. "Singing" pattern -- vowel sequence with pitch movement
// ----------------------------------------
(
Pdef(\qdtsSinging,
    Pbind(
        \instrument, \qdtsVowelFormant,
        \dur, Pseq([0.75, 0.75, 1.5, 0.75, 0.75, 1.5], inf),
        \carrierPitch, 2500,
        \targetPitch, Pseq([150, 170, 150, 130, 150, 130], inf),
        \amp, 0.2,
        \atk, 0.05, \dec, 0.08, \sus, 0.8, \rel, 0.15,
        // Cycle through vowel profiles
        [\t0, \t1, \t2, \t3, \t4, \t5, \t6, \t7],
        Pseq([
            [0.15, 0.3, 0.55, 0.85, 1.0, 0.7, 0.9, 0.5],     // /a/
            [0.3, 0.8, 0.2, 0.1, 0.08, 0.07, 0.06, 0.05],     // /i/
            [0.6, 1.0, 0.35, 0.2, 0.5, 0.8, 0.3, 0.15],       // /u/
            [0.2, 0.4, 0.8, 1.0, 0.6, 0.3, 0.2, 0.15],        // /e/
            [0.25, 0.5, 0.75, 1.0, 0.85, 0.9, 0.4, 0.2],      // /o/
            [0.15, 0.3, 0.55, 0.85, 1.0, 0.7, 0.9, 0.5],      // /a/
        ], inf)
    )
).play;
)

Pdef(\qdtsSinging).stop;


// ============================================================================
// 16. TIMBRE MORPHING BETWEEN INSTRUMENTS
// ============================================================================

/*
Because QDTS timbres are defined purely by target amplitude arrays,
morphing between instruments is simply linear interpolation between
their harmonic profiles. This produces smooth timbral transitions
that would be difficult to achieve with conventional synthesis.
*/

(
~instrumentProfiles = Dictionary[
    \clarinet -> [1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02],
    \oboe     -> [0.8, 1.0, 0.9, 0.7, 0.5, 0.35, 0.25, 0.15],
    \flute    -> [1.0, 0.3, 0.1, 0.03, 0.01, 0.01, 0.01, 0.01],
    \trumpet  -> [1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2],
    \violin   -> [1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.15]
];
)

// ----------------------------------------
// 16a. Continuous morph between two instruments
// ----------------------------------------
(
~morphFrom = ~instrumentProfiles[\clarinet];
~morphTo = ~instrumentProfiles[\oboe];

~morphInstr = Synth(\qdtsInstrument, [
    \carrierPitch, 2500, \targetPitch, 262,
    \amp, 0.2, \vibRate, 5, \vibDepth, 6
]);

// Morph over 5 seconds
~morphTask = fork {
    var steps = 100;
    steps.do {|i|
        var blend = i / (steps - 1);
        var profile = ~morphFrom.collect {|from, j|
            from + (blend * (~morphTo[j] - from))
        };
        8.do {|k|
            ~morphInstr.set(("t" ++ k).asSymbol, profile[k]);
        };
        0.05.wait;
    };
    "Morph complete: clarinet -> oboe".postln;
};
)

~morphInstr.free;

// ----------------------------------------
// 16b. Cyclic morph through all instruments
// ----------------------------------------
(
~cycleMorph = Synth(\qdtsInstrument, [
    \carrierPitch, 2500, \targetPitch, 220,
    \amp, 0.2, \vibRate, 5, \vibDepth, 6
]);

~cycleTask = fork {
    var order = [\clarinet, \oboe, \flute, \trumpet, \violin];
    var morphSteps = 80;
    var holdTime = 1.0;

    loop {
        order.size.do {|idx|
            var from = ~instrumentProfiles[order[idx]];
            var to = ~instrumentProfiles[order[(idx + 1) % order.size]];

            // Hold current timbre
            ("Holding: " ++ order[idx]).postln;
            8.do {|k| ~cycleMorph.set(("t" ++ k).asSymbol, from[k]) };
            holdTime.wait;

            // Morph to next
            ("Morphing to: " ++ order[(idx + 1) % order.size]).postln;
            morphSteps.do {|i|
                var blend = i / (morphSteps - 1);
                var profile = from.collect {|fv, j|
                    fv + (blend * (to[j] - fv))
                };
                8.do {|k| ~cycleMorph.set(("t" ++ k).asSymbol, profile[k]) };
                0.04.wait;
            };
        };
    };
};
)

// Stop morphing
(~cycleTask.stop; ~cycleMorph.free;)


// ============================================================================
// 17. DYNAMIC SPECTRAL RESHAPING WITH LFOs
// ============================================================================

/*
Instrument-like timbral evolution using LFOs to modulate individual
harmonic targets. This creates living, breathing tones that shift
between instrument-like characters.
*/

(
SynthDef(\qdtsBreathing, {|out = 0, carrierPitch = 2500, targetPitch = 220,
    amp = 0.2, gate = 1, breathRate = 0.15|

    var numPartials = 8;

    // Slow LFOs create timbral "breathing"
    // Odd harmonics modulate together (clarinet-like axis)
    // Even harmonics modulate together (fullness axis)
    var oddMod = SinOsc.kr(breathRate).range(0.3, 1.0);
    var evenMod = SinOsc.kr(breathRate * 0.7, pi/4).range(0.05, 0.8);

    var t0 = 1.0;
    var t1 = evenMod * 0.9;
    var t2 = oddMod * 0.7;
    var t3 = evenMod * 0.6;
    var t4 = oddMod * 0.5;
    var t5 = evenMod * 0.3;
    var t6 = oddMod * 0.25;
    var t7 = evenMod * 0.15;

    var env = EnvGen.kr(Env.asr(0.3, 1, 0.5), gate, doneAction: 2);

    var amps = QDTSSolver.kr(numPartials,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01)
    );

    var vibrato = SinOsc.kr(5) * 6;
    var pitch = carrierPitch + vibrato;
    var freqs = (numPartials + 1).collect {|i| pitch + (i * targetPitch) };
    var sines = (numPartials + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// Tone that breathes between clarinet-like and oboe-like
x = Synth(\qdtsBreathing, [\breathRate, 0.1]);

// Faster breathing
x.set(\breathRate, 0.4);

// Very slow (meditative)
x.set(\breathRate, 0.05);

x.set(\gate, 0);


// ============================================================================
// 18. TIPS AND TROUBLESHOOTING
// ============================================================================

/*
IMPORTANT NOTES:

1. TARGET VALUE RANGE
   Target values (t0, t1, t2...) represent RELATIVE amplitude ratios.
   - Minimum: > 0 (use 0.01 as safe minimum to avoid instability)
   - Maximum: No strict limit, but typical range is 0.01 to 2.0
   - Values can exceed 1.0 (e.g., t1=1.5 means 2nd harmonic is 1.5x the 1st)
   Always clamp: target.max(0.01) or target.clip(0.01, 2.0)

   Standard spectra (fundamental dominant):
   - [1, 0.5, 0.33, 0.25]  - Sawtooth (1/n rolloff)
   - [1, 0.01, 0.5, 0.01]  - Square-ish (odd harmonics)
   - [1, 1, 1, 1]          - Equal harmonics (bright)
   - [1, 0.1, 0.05, 0.02]  - Mellow/sine-like

   Non-standard spectra (upper harmonic dominant):
   - [0.2, 1, 0.1, 0.1]    - 2nd harmonic dominant (hollow)
   - [0.1, 0.1, 1, 0.1]    - 3rd harmonic dominant (nasal)
   - [0.3, 0.3, 0.3, 1]    - 4th harmonic dominant
   - [0.5, 0.8, 1, 0.6]    - Peak at 3rd, gradual rolloff

   Instrumental spectra (8 harmonics):
   - Clarinet: [1, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02]
   - Oboe:     [0.8, 1.0, 0.9, 0.7, 0.5, 0.35, 0.25, 0.15]
   - Flute:    [1, 0.3, 0.1, 0.03, 0.01, 0.01, 0.01, 0.01]
   - Trumpet:  [1, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]
   - Violin:   [1, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.15]

2. MONITOR ERROR OUTPUT
   The last output of QDTSSolver is the estimation error.
   Values < 0.001 indicate good convergence.

   {
       var amps = QDTSSolver.kr(4, 1, 0.5, 0.33, 0.25);
       var error = amps[5]; // Last output
       error.poll;
       Silent.ar;
   }.play;

3. ASYNC SOLVER BEHAVIOR
   The solver runs on the NRT thread. There is a brief latency (~1 control
   block) before results appear after synth creation or target changes.
   This is normally inaudible. For rapid parameter automation, the solver
   debounces: it waits a few blocks before re-solving if targets keep
   changing.

4. USE LIMITER
   For safety, wrap output in Limiter.ar(signal, 0.9)

5. CARRIER vs TARGET PITCH
   - Carrier: The base frequency (optimal range: 1-5 kHz)
   - Target: The difference between successive partials (the perceived pitch)
   - Frequencies generated: carrier, carrier+target, carrier+2*target, ...

6. SINGLE SOLVER INSTANCE
   When using the QDTS helper class, call .solver or .ar only ONCE in a
   SynthDef function. Each call creates new UGen graph nodes. Store the
   solver result in a variable and reuse it.

7. NUMBER OF HARMONICS
   More harmonics = richer sound but more CPU
   Maximum supported: 16 harmonics
   For instrumental tones, 8 harmonics is a good default.

8. INSTRUMENTAL TONES
   The instrumental profiles above are static spectral snapshots. Real
   instruments have register-dependent timbral variation, attack transients,
   and dynamic spectral changes. Combine QDTS profiles with per-harmonic
   envelopes (Section 14) for more realistic results.

9. VOWEL SYNTHESIS
   Vowel quality depends on f0. The pre-computed profiles in Section 15a
   are optimized for f0 = 150 Hz. For other fundamentals, formant energy
   shifts across different harmonics. The formant-based approach works best
   in the 100-300 Hz fundamental range.
*/

// Cleanup
Pdef.all.do(_.stop);
