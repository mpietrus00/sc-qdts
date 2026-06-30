/*
NQDTSSolver Examples
====================

Comprehensive examples for the neural QDTS solver.
NQDTSSolver uses a trained neural network to compute carrier amplitudes
for quadratic difference tone spectra synthesis.

Neural network architecture: HomogeneousInverse (3-layer MLP, 256 hidden units)
Trained models from: https://github.com/cordutie/qdts
Supports N = 5-16 harmonics.

Usage: boot the server, then execute blocks individually (Cmd+Enter).
Use headphones or near-field monitors. Carrier frequencies are in the 1-5 kHz range.

IMPORTANT: Always use Limiter.ar for safety when experimenting.
*/

// ============================================================
// SETUP
// ============================================================
(
s.waitForBoot {
    "Server booted. Ready for NQDTSSolver examples.".postln;
    "NQDTSSolver supports N = 5..16 harmonics.".postln;
    "  NQDTSSolver.kr(numHarmonics, refine, *targets)".postln;
    "  refine: 0 = pure neural, 3-5 = hybrid (neural + Newton)".postln;
};
)

// ============================================================
// 1. BASIC SYNTHESIS
// ============================================================

// -- 1a. Minimal example: 5-harmonic sawtooth
(
{
    var n = 5;
    var targets = [1, 0.5, 0.33, 0.25, 0.2];
    var carrierFreq = 2500;
    var targetFreq = 150;
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 1b. 8-harmonic sawtooth with error monitoring
(
{
    var n = 8;
    var targets = (1..8).collect {|i| 1.0 / i };
    var carrierFreq = 2500;
    var targetFreq = 150;
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var error = amps[n + 1];
    error.poll(2, "Error");
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 1c. Hybrid mode: neural + 5 Newton refinement iterations
(
{
    var n = 8;
    var targets = (1..8).collect {|i| 1.0 / i };
    var carrierFreq = 2500;
    var targetFreq = 150;
    var amps = NQDTSSolver.kr(n, 5, *targets); // refine = 5
    var error = amps[n + 1];
    error.poll(2, "Hybrid error");
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// ============================================================
// 2. STANDARD WAVEFORMS
// ============================================================

// -- 2a. Sawtooth (all harmonics, 1/n rolloff)
(
{
    var n = 8;
    var targets = (1..n).collect {|i| 1.0 / i };
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| 2500 + (i * 150) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 2b. Square (odd harmonics only)
(
{
    var n = 8;
    var targets = n.collect {|i|
        if((i + 1).odd) { 1.0 / (i + 1) } { 0.01 }
    };
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| 2500 + (i * 150) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 2c. Triangle (odd harmonics, 1/n^2 rolloff)
(
{
    var n = 8;
    var targets = n.collect {|i|
        if((i + 1).odd) {
            ((-1) ** ((i) / 2)).abs / ((i + 1) ** 2)
        } { 0.01 }
    };
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| 2500 + (i * 150) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 2d. Using NQDTS helper class
(
{ NQDTS.sawtooth(8, 150).ar(0.2) ! 2 }.play;
)
(
{ NQDTS.square(8, 150).ar(0.2) ! 2 }.play;
)
(
{ NQDTS.triangle(8, 150).ar(0.2) ! 2 }.play;
)

// ============================================================
// 3. INSTRUMENTAL TONES
// ============================================================

// SynthDef for all instrumental examples
(
SynthDef(\nqdtsInstr, { |out = 0, carrierFreq = 2500, targetFreq = 220,
    amp = 0.2, gate = 1, atk = 0.02, dec = 0.1, sus = 0.8, rel = 0.3,
    vibRate = 0, vibDepth = 0,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25,
    t4 = 0.2, t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var numH = 8;
    var vibrato = SinOsc.kr(vibRate) * vibDepth;
    var pitch = carrierFreq + vibrato;
    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    var amps = NQDTSSolver.kr(numH, 0,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01));

    var freqs = (numH + 1).collect {|i| pitch + (i * targetFreq) };
    var sines = (numH + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// -- 3a. Clarinet: odd harmonics dominant
(
~x = Synth(\nqdtsInstr, [
    \targetFreq, 262, \vibRate, 4.5, \vibDepth, 6,
    \atk, 0.08, \sus, 0.9,
    \t0, 1.0,  \t1, 0.05, \t2, 0.75, \t3, 0.04,
    \t4, 0.5,  \t5, 0.03, \t6, 0.3,  \t7, 0.02
]);
)
~x.set(\gate, 0);

// -- 3b. Oboe: peak at H2-H3
(
~x = Synth(\nqdtsInstr, [
    \targetFreq, 440, \vibRate, 5, \vibDepth, 4,
    \atk, 0.04, \sus, 0.85,
    \t0, 0.8,  \t1, 1.0,  \t2, 0.9,  \t3, 0.7,
    \t4, 0.5,  \t5, 0.35, \t6, 0.25, \t7, 0.15
]);
)
~x.set(\gate, 0);

// -- 3c. Flute: fundamental dominant, steep rolloff
(
~x = Synth(\nqdtsInstr, [
    \targetFreq, 523, \vibRate, 5.5, \vibDepth, 5,
    \atk, 0.1, \sus, 0.7,
    \t0, 1.0,  \t1, 0.3,  \t2, 0.1,  \t3, 0.03,
    \t4, 0.01, \t5, 0.01, \t6, 0.01, \t7, 0.01
]);
)
~x.set(\gate, 0);

// -- 3d. Trumpet: rich spectrum, slow rolloff
(
~x = Synth(\nqdtsInstr, [
    \targetFreq, 349, \vibRate, 5.5, \vibDepth, 8,
    \atk, 0.03, \sus, 0.9,
    \t0, 1.0, \t1, 0.9, \t2, 0.7, \t3, 0.6,
    \t4, 0.5, \t5, 0.4, \t6, 0.3, \t7, 0.2
]);
)
~x.set(\gate, 0);

// -- 3e. Violin: broad harmonic content
(
~x = Synth(\nqdtsInstr, [
    \targetFreq, 440, \vibRate, 6, \vibDepth, 5,
    \atk, 0.05, \sus, 0.85,
    \t0, 1.0,  \t1, 0.8,  \t2, 0.6,  \t3, 0.5,
    \t4, 0.4,  \t5, 0.3,  \t6, 0.2,  \t7, 0.15
]);
)
~x.set(\gate, 0);

// ============================================================
// 4. TIMBRE MORPHING
// The neural solver produces smooth continuous output
// under rapid parameter changes (no branch jumping).
// ============================================================

// -- 4a. Clarinet to Trumpet morph (5 seconds)
(
~clarinet = [1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02];
~trumpet  = [1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2];

~x = Synth(\nqdtsInstr, [
    \targetFreq, 262, \vibRate, 5, \vibDepth, 6
]);

fork {
    "Morphing: clarinet -> trumpet (5s)".postln;
    200.do {|i|
        var blend = i / 199;
        8.do {|k|
            var val = ~clarinet[k] + (blend * (~trumpet[k] - ~clarinet[k]));
            ~x.set(("t" ++ k).asSymbol, val.max(0.01));
        };
        0.025.wait;
    };
    "Morph complete.".postln;
};
)
~x.set(\gate, 0);

// -- 4b. Flute to Oboe morph (5 seconds)
(
~flute = [1.0, 0.3, 0.1, 0.03, 0.01, 0.01, 0.01, 0.01];
~oboe  = [0.8, 1.0, 0.9, 0.7, 0.5, 0.35, 0.25, 0.15];

~x = Synth(\nqdtsInstr, [
    \targetFreq, 440, \vibRate, 5, \vibDepth, 4
]);

fork {
    "Morphing: flute -> oboe (5s)".postln;
    200.do {|i|
        var blend = i / 199;
        8.do {|k|
            var val = ~flute[k] + (blend * (~oboe[k] - ~flute[k]));
            ~x.set(("t" ++ k).asSymbol, val.max(0.01));
        };
        0.025.wait;
    };
    "Morph complete.".postln;
};
)
~x.set(\gate, 0);

// -- 4c. Continuous circular morph through 5 instruments (25 seconds)
(
~profiles = [
    [1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02],   // clarinet
    [0.8, 1.0, 0.9, 0.7, 0.5, 0.35, 0.25, 0.15],      // oboe
    [1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2],          // trumpet
    [1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.15],         // violin
    [1.0, 0.3, 0.1, 0.03, 0.01, 0.01, 0.01, 0.01],     // flute
    [1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02],     // back to clarinet
];
~names = ["clarinet", "oboe", "trumpet", "violin", "flute", "clarinet"];

~x = Synth(\nqdtsInstr, [\targetFreq, 262, \vibRate, 5, \vibDepth, 5]);

fork {
    "Circular instrument morph (25s)".postln;
    (~profiles.size - 1).do {|seg|
        var from = ~profiles[seg];
        var to = ~profiles[seg + 1];
        "  % -> %".format(~names[seg], ~names[seg + 1]).postln;
        200.do {|i|
            var blend = i / 199;
            8.do {|k|
                var val = from[k] + (blend * (to[k] - from[k]));
                ~x.set(("t" ++ k).asSymbol, val.max(0.01));
            };
            0.025.wait;
        };
    };
    "Instrument cycle complete.".postln;
};
)
~x.set(\gate, 0);

// ============================================================
// 5. VOWEL SYNTHESIS
// Formant profiles for f0 = 150 Hz, 8 harmonics
// (Peterson & Barney 1952)
// ============================================================

// -- 5a. Individual vowels
(
// /a/ (father) — F1=730, F2=1090
~x = Synth(\nqdtsInstr, [
    \targetFreq, 150, \vibRate, 0, \vibDepth, 0,
    \t0, 0.15, \t1, 0.3, \t2, 0.55, \t3, 0.85,
    \t4, 1.0,  \t5, 0.7, \t6, 0.9,  \t7, 0.5
]);
)
~x.set(\gate, 0);

(
// /i/ (see) — F1=270, F2=2290
~x = Synth(\nqdtsInstr, [
    \targetFreq, 150, \vibRate, 0, \vibDepth, 0,
    \t0, 0.3, \t1, 0.8, \t2, 0.2, \t3, 0.1,
    \t4, 0.08, \t5, 0.07, \t6, 0.06, \t7, 0.05
]);
)
~x.set(\gate, 0);

(
// /u/ (boot) — F1=300, F2=870
~x = Synth(\nqdtsInstr, [
    \targetFreq, 150, \vibRate, 0, \vibDepth, 0,
    \t0, 0.6, \t1, 1.0,  \t2, 0.35, \t3, 0.2,
    \t4, 0.5, \t5, 0.8,  \t6, 0.3,  \t7, 0.15
]);
)
~x.set(\gate, 0);

(
// /e/ (bed) — F1=530, F2=1840
~x = Synth(\nqdtsInstr, [
    \targetFreq, 150, \vibRate, 0, \vibDepth, 0,
    \t0, 0.2, \t1, 0.4, \t2, 0.8, \t3, 1.0,
    \t4, 0.6, \t5, 0.3, \t6, 0.2, \t7, 0.15
]);
)
~x.set(\gate, 0);

(
// /o/ (go) — F1=570, F2=840
~x = Synth(\nqdtsInstr, [
    \targetFreq, 150, \vibRate, 0, \vibDepth, 0,
    \t0, 0.25, \t1, 0.5,  \t2, 0.75, \t3, 1.0,
    \t4, 0.85, \t5, 0.9,  \t6, 0.4,  \t7, 0.2
]);
)
~x.set(\gate, 0);

// -- 5b. Vowel cycle morph: /a/ -> /e/ -> /i/ -> /o/ -> /u/ -> /a/
(
~vowels = Dictionary[
    \a -> [0.15, 0.3, 0.55, 0.85, 1.0, 0.7, 0.9, 0.5],
    \e -> [0.2, 0.4, 0.8, 1.0, 0.6, 0.3, 0.2, 0.15],
    \i -> [0.3, 0.8, 0.2, 0.1, 0.08, 0.07, 0.06, 0.05],
    \o -> [0.25, 0.5, 0.75, 1.0, 0.85, 0.9, 0.4, 0.2],
    \u -> [0.6, 1.0, 0.35, 0.2, 0.5, 0.8, 0.3, 0.15],
];
~vowelSeq = [\a, \e, \i, \o, \u, \a];

~x = Synth(\nqdtsInstr, [
    \targetFreq, 150, \carrierFreq, 2500,
    \vibRate, 0, \vibDepth, 0
]);

fork {
    "Vowel cycle: /a/ -> /e/ -> /i/ -> /o/ -> /u/ -> /a/ (10s)".postln;
    (~vowelSeq.size - 1).do {|seg|
        var from = ~vowels[~vowelSeq[seg]];
        var to = ~vowels[~vowelSeq[seg + 1]];
        "  /%/ -> /%/".format(~vowelSeq[seg], ~vowelSeq[seg + 1]).postln;
        80.do {|i|
            var blend = i / 79;
            8.do {|k|
                var val = from[k] + (blend * (to[k] - from[k]));
                ~x.set(("t" ++ k).asSymbol, val.max(0.01));
            };
            0.025.wait;
        };
    };
    "Vowel cycle complete.".postln;
};
)
~x.set(\gate, 0);

// ============================================================
// 6. DYNAMIC MODULATION
// The neural solver runs every control block with no NRT latency.
// LFO-modulated targets produce smoothly evolving timbres.
// ============================================================

// -- 6a. Slow LFO modulation of harmonic amplitudes
(
{
    var n = 6;
    var carrierFreq = 2500;
    var targetFreq = 150;

    var t0 = SinOsc.kr(0.1).range(0.5, 1.5);
    var t1 = SinOsc.kr(0.15).range(0.1, 0.8);
    var t2 = SinOsc.kr(0.2).range(0.1, 0.6);
    var t3 = SinOsc.kr(0.25).range(0.05, 0.4);
    var t4 = SinOsc.kr(0.3).range(0.05, 0.3);
    var t5 = SinOsc.kr(0.35).range(0.05, 0.2);

    var amps = NQDTSSolver.kr(n, 0, t0, t1, t2, t3, t4, t5);
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 6b. Noise-modulated spectrum (stochastic timbre)
(
{
    var n = 8;
    var carrierFreq = 2500;
    var targetFreq = 100;

    var targets = n.collect {|i|
        var base = 1.0 / (i + 1);
        var noise = LFNoise1.kr(0.5 + (i * 0.1)).range(0.5, 1.5);
        (base * noise).max(0.01)
    };

    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// -- 6c. Spectral brightening/darkening with a single control
(
{
    var n = 8;
    var carrierFreq = 2500;
    var targetFreq = 150;

    // MouseX controls spectral tilt: left = dark, right = bright
    var tilt = MouseX.kr(-2, 2);
    var targets = n.collect {|i|
        var harmonic = i + 1;
        ((1.0 / harmonic) * (harmonic ** tilt)).clip(0.01, 2.0)
    };

    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// ============================================================
// 7. PATTERN INTEGRATION
// ============================================================

// -- 7a. Melodic sequence with per-note timbre variation
(
SynthDef(\nqdtsNote, {|out = 0, freq = 440, amp = 0.2, gate = 1,
    atk = 0.01, dec = 0.1, sus = 0.7, rel = 0.3,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25,
    t4 = 0.2, t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var carrierFreq = freq * 4;
    var targetFreq = freq;
    var n = 8;

    var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
    var amps = NQDTSSolver.kr(n, 0,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01));
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Out.ar(out, Limiter.ar(sines.sum * env * amp, 0.9) ! 2);
}).add;
)

// Simple scale with random timbre per note
(
Pbind(
    \instrument, \nqdtsNote,
    \degree, Pseq([0, 2, 4, 5, 7, 9, 11, 12], inf),
    \dur, 0.25,
    \amp, 0.15,
    \t1, Pwhite(0.1, 0.8),
    \t2, Pwhite(0.05, 0.5),
    \t3, Pwhite(0.05, 0.4),
).play;
)

// -- 7b. Chords with consistent timbre
(
Ppar([
    Pbind(
        \instrument, \nqdtsNote,
        \degree, Pseq([0, 4, 7, 4], inf),
        \dur, 0.5,
        \amp, 0.1,
        \t0, 1.0, \t1, 0.05, \t2, 0.75, \t3, 0.04,
        \t4, 0.5, \t5, 0.03, \t6, 0.3, \t7, 0.02
    ),
    Pbind(
        \instrument, \nqdtsNote,
        \degree, Pseq([4, 7, 12, 7], inf),
        \dur, 0.5,
        \amp, 0.1,
        \t0, 1.0, \t1, 0.05, \t2, 0.75, \t3, 0.04,
        \t4, 0.5, \t5, 0.03, \t6, 0.3, \t7, 0.02
    ),
]).play;
)

// -- 7c. Timbre as a pattern parameter (morph across phrase)
(
Pbind(
    \instrument, \nqdtsNote,
    \degree, Pseq([0, 2, 4, 5, 7, 5, 4, 2], inf),
    \dur, 0.2,
    \amp, 0.15,
    // Morph from clarinet-like to trumpet-like across each phrase
    \t1, Pseg([0.05, 0.9, 0.05], [8, 8], \lin, inf),
    \t3, Pseg([0.04, 0.6, 0.04], [8, 8], \lin, inf),
    \t5, Pseg([0.03, 0.4, 0.03], [8, 8], \lin, inf),
    \t7, Pseg([0.02, 0.2, 0.02], [8, 8], \lin, inf),
).play;
)

// ============================================================
// 8. SPECTRAL ENVELOPE (Per-harmonic dynamics)
// Different envelopes per carrier partial create
// attack-dependent timbre evolution.
// ============================================================

// -- 8a. Attack transient: higher harmonics arrive later
(
SynthDef(\nqdtsAttack, {|out = 0, carrierFreq = 3000, targetFreq = 100,
    amp = 0.3, gate = 1|

    var n = 6;
    var atkTimes = [0.01, 0.03, 0.06, 0.1, 0.15, 0.2, 0.25];
    var relTimes = [0.8, 0.6, 0.45, 0.35, 0.25, 0.2, 0.15];

    var envs = (n + 1).collect {|i|
        EnvGen.kr(Env.perc(atkTimes[i], relTimes[i]), gate)
    };

    var targets = [1, 0.6, 0.4, 0.25, 0.15, 0.1];
    var amps = NQDTSSolver.kr(n, 0, *targets);

    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] * envs[i] };

    Out.ar(out, Limiter.ar(sines.sum * amp, 0.9) ! 2);
}).add;
)

Synth(\nqdtsAttack);

// Repeat for rhythmic effect
(
fork {
    20.do {
        Synth(\nqdtsAttack, [\targetFreq, rrand(80, 200)]);
        rrand(0.15, 0.4).wait;
    };
};
)

// ============================================================
// 9. HIGH N VALUES (12 and 16 harmonics)
// The neural solver has trained models up to N=16.
// ============================================================

// -- 9a. 12-harmonic sawtooth
(
{
    var n = 12;
    var targets = (1..n).collect {|i| 1.0 / i };
    var carrierFreq = 2500;
    var targetFreq = 100;
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var error = amps[n + 1];
    error.poll(2, "N=12 error");
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.15, 0.9) ! 2
}.play;
)

// -- 9b. 16-harmonic sawtooth (maximum)
(
{
    var n = 16;
    var targets = (1..n).collect {|i| 1.0 / i };
    var carrierFreq = 3000;
    var targetFreq = 80;
    var amps = NQDTSSolver.kr(n, 0, *targets);
    var error = amps[n + 1];
    error.poll(2, "N=16 error");
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.1, 0.9) ! 2
}.play;
)

// ============================================================
// 10. CARRIER FREQUENCY EXPLORATION
// The phantom tones are most audible when the carrier
// sits in the ear's most sensitive range (1-5 kHz).
// ============================================================

// -- 10a. MouseY controls carrier frequency
(
{
    var n = 8;
    var targetFreq = 150;
    var targets = (1..n).collect {|i| 1.0 / i };
    // MouseY: 800 Hz (bottom) to 5000 Hz (top)
    var carrierFreq = MouseY.kr(800, 5000, 1);

    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    carrierFreq.poll(2, "Carrier Hz");

    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)

// ============================================================
// 11. AMPLITUDE MODULATION
// Due to the quadratic nature of ADPs, use sqrt of
// the intended modulation depth on the carrier.
// ============================================================

// -- 11a. Tremolo with correct quadratic compensation
(
{
    var n = 8;
    var carrierFreq = 2500;
    var targetFreq = 150;
    var targets = (1..n).collect {|i| 1.0 / i };

    var amps = NQDTSSolver.kr(n, 0, *targets);
    var freqs = (n + 1).collect {|i| carrierFreq + (i * targetFreq) };

    // sqrt modulation: perceived depth matches intended depth
    var mod = SinOsc.kr(4).range(0.2, 1.0).sqrt;
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };

    Limiter.ar(sines.sum * mod * 0.2, 0.9) ! 2
}.play;
)

// ============================================================
// 12. REFINEMENT COMPARISON
// Listen to the difference between pure neural (refine=0)
// and hybrid (refine=5) on the same spectrum.
// ============================================================

// -- 12a. Pure neural
(
"Pure neural (refine=0)".postln;
~x = {
    var n = 8;
    var targets = [1, 0.5, 0.33, 0.25, 0.2, 0.16, 0.14, 0.12];
    var amps = NQDTSSolver.kr(n, 0, *targets);
    amps[n + 1].poll(2, "Neural error");
    var freqs = (n + 1).collect {|i| 2500 + (i * 150) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)
~x.free;

// -- 12b. Hybrid (refine=5)
(
"Hybrid (refine=5)".postln;
~x = {
    var n = 8;
    var targets = [1, 0.5, 0.33, 0.25, 0.2, 0.16, 0.14, 0.12];
    var amps = NQDTSSolver.kr(n, 5, *targets);
    amps[n + 1].poll(2, "Hybrid error");
    var freqs = (n + 1).collect {|i| 2500 + (i * 150) };
    var sines = (n + 1).collect {|i| SinOsc.ar(freqs[i]) * amps[i] };
    Limiter.ar(sines.sum * 0.2, 0.9) ! 2
}.play;
)
~x.free;
