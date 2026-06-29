/*
QDTS Solver Comparison: Newton vs Neural vs Hybrid
====================================================

Comprehensive comparison of the three solving modes:
  1. QDTSSolver   — iterative Newton method, NRT async dispatch
  2. NQDTSSolver  — neural network forward pass, control-rate synchronous
  3. NQDTSSolver  — hybrid: neural initial guess + Newton refinement

Usage:
  1. Boot server: s.boot;
  2. Execute test blocks individually (Cmd+Enter on each parenthesized block)
  3. Results print to post window
*/

// ============================================================
// SETUP
// ============================================================
(
s.waitForBoot {
    "Server booted. Ready for QDTS comparison tests.".postln;
    "NQDTSSolver supports N = 5..16".postln;
    "QDTSSolver  supports N = 1..16".postln;
};
)

// ============================================================
// TEST 1: Error Comparison — Standard Spectra
// All three solvers on the same targets, side by side
// ============================================================
(
"" .postln;
"=" ! 70 ++ "";
"TEST 1: Error Comparison — Standard Spectra".postln;
"=" ! 70 ++ "";

fork {
    var testCases = [
        [\sawtooth_5,  (1..5).collect { |i| 1/i }],
        [\sawtooth_8,  (1..8).collect { |i| 1/i }],
        [\square_6,    [1.0, 0.01, 0.333, 0.01, 0.2, 0.01]],
        [\triangle_6,  [1.0, 0.01, 0.111, 0.01, 0.04, 0.01]],
        [\flat_5,      [1.0, 1.0, 1.0, 1.0, 1.0]],
        [\bright_8,    [0.2, 0.4, 0.6, 0.8, 1.0, 0.8, 0.6, 0.4]],
    ];

    "".postln;
    "%-14s  %3s  %12s  %12s  %12s".format(
        "Spectrum", "N", "Newton", "Neural", "Hybrid(r=5)"
    ).postln;
    "-" ! 70 ++ "";

    testCases.do { |test|
        var name = test[0];
        var targets = test[1];
        var numH = targets.size;
        var synth, oscFunc;
        var results = Dictionary.new;
        var done = false;

        oscFunc = OSCFunc({ |msg|
            var newton = msg[3];
            var neural = msg[4];
            var hybrid = msg[5];
            if(newton < 1e5 and: { neural < 1e5 }) {
                if(done.not) {
                    results[\newton] = newton;
                    results[\neural] = neural;
                    results[\hybrid] = hybrid;
                    done = true;
                };
            };
        }, '/cmp_error');

        synth = {
            var newton = QDTSSolver.kr(numH, *targets);
            var neural = NQDTSSolver.kr(numH, 0, *targets);
            var hybrid = NQDTSSolver.kr(numH, 5, *targets);
            var errNewton = newton[numH + 1];
            var errNeural = neural[numH + 1];
            var errHybrid = hybrid[numH + 1];
            SendReply.kr(Impulse.kr(5), '/cmp_error',
                [errNewton, errNeural, errHybrid]);
            Silent.ar;
        }.play;

        // Newton solver needs time (async NRT)
        1.0.wait;

        if(done) {
            "%-14s  %3d  %12.8f  %12.8f  %12.8f".format(
                name, numH,
                results[\newton], results[\neural], results[\hybrid]
            ).postln;
        } {
            "%-14s  %3d  (no result received)".format(name, numH).postln;
        };

        oscFunc.free;
        synth.free;
        0.2.wait;
    };

    0.3.wait;
    "".postln;
    "Test 1 complete.".postln;
    "Newton error = L2 residual of nonlinear system".postln;
    "Neural/Hybrid error = MSE of D(X_hat) vs T".postln;
};
)

// ============================================================
// TEST 2: Error Comparison — Instrumental Spectra
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 2: Error Comparison — Instrumental Spectra".postln;
"=" ! 70 ++ "";

fork {
    var instrumentTests = [
        [\clarinet,  [1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02]],
        [\oboe,      [0.8, 1.0, 0.9, 0.7, 0.5, 0.35, 0.25, 0.15]],
        [\flute,     [1.0, 0.3, 0.1, 0.03, 0.01, 0.01, 0.01, 0.01]],
        [\trumpet,   [1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]],
        [\violin,    [1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.15]],
        [\vowel_a,   [0.15, 0.3, 0.55, 0.85, 1.0, 0.7, 0.9, 0.5]],
        [\vowel_i,   [0.3, 0.8, 0.2, 0.1, 0.08, 0.07, 0.06, 0.05]],
    ];

    "".postln;
    "%-12s  %3s  %12s  %12s  %12s".format(
        "Instrument", "N", "Newton", "Neural", "Hybrid(r=5)"
    ).postln;
    "-" ! 70 ++ "";

    instrumentTests.do { |test|
        var name = test[0];
        var targets = test[1];
        var numH = targets.size;
        var synth, oscFunc;
        var results = Dictionary.new;
        var done = false;

        oscFunc = OSCFunc({ |msg|
            var newton = msg[3];
            var neural = msg[4];
            var hybrid = msg[5];
            if(newton < 1e5 and: { neural < 1e5 }) {
                if(done.not) {
                    results[\newton] = newton;
                    results[\neural] = neural;
                    results[\hybrid] = hybrid;
                    done = true;
                };
            };
        }, '/cmp_instr');

        synth = {
            var newton = QDTSSolver.kr(numH, *targets);
            var neural = NQDTSSolver.kr(numH, 0, *targets);
            var hybrid = NQDTSSolver.kr(numH, 5, *targets);
            SendReply.kr(Impulse.kr(5), '/cmp_instr',
                [newton[numH + 1], neural[numH + 1], hybrid[numH + 1]]);
            Silent.ar;
        }.play;

        1.0.wait;

        if(done) {
            "%-12s  %3d  %12.8f  %12.8f  %12.8f".format(
                name, numH,
                results[\newton], results[\neural], results[\hybrid]
            ).postln;
        } {
            "%-12s  %3d  (no result)".format(name, numH).postln;
        };

        oscFunc.free;
        synth.free;
        0.2.wait;
    };

    0.3.wait;
    "".postln;
    "Test 2 complete.".postln;
};
)

// ============================================================
// TEST 3: Scaling with N — Error across harmonic counts
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 3: Scaling with N — Sawtooth spectrum at each N (5..16)".postln;
"=" ! 70 ++ "";

fork {
    "".postln;
    "%3s  %12s  %12s  %12s  %12s".format(
        "N", "Newton", "Neural", "Hybrid(r=3)", "Hybrid(r=8)"
    ).postln;
    "-" ! 60 ++ "";

    (5..16).do { |numH|
        var targets = (1..numH).collect { |i| 1.0 / i };
        var synth, oscFunc;
        var results = Dictionary.new;
        var done = false;

        oscFunc = OSCFunc({ |msg|
            if(msg[3] < 1e5 and: { msg[4] < 1e5 } and: { done.not }) {
                results[\newton] = msg[3];
                results[\neural] = msg[4];
                results[\hybrid3] = msg[5];
                results[\hybrid8] = msg[6];
                done = true;
            };
        }, '/cmp_n');

        synth = {
            var newton = QDTSSolver.kr(numH, *targets);
            var neural = NQDTSSolver.kr(numH, 0, *targets);
            var hybrid3 = NQDTSSolver.kr(numH, 3, *targets);
            var hybrid8 = NQDTSSolver.kr(numH, 8, *targets);
            SendReply.kr(Impulse.kr(5), '/cmp_n',
                [newton[numH + 1], neural[numH + 1],
                 hybrid3[numH + 1], hybrid8[numH + 1]]);
            Silent.ar;
        }.play;

        1.0.wait;

        if(done) {
            "%3d  %12.8f  %12.8f  %12.8f  %12.8f".format(
                numH,
                results[\newton], results[\neural],
                results[\hybrid3], results[\hybrid8]
            ).postln;
        } {
            "%3d  (no result)".format(numH).postln;
        };

        oscFunc.free;
        synth.free;
        0.2.wait;
    };

    0.3.wait;
    "".postln;
    "Test 3 complete.".postln;
};
)

// ============================================================
// TEST 4: Refinement Iteration Sweep
// How many Newton iterations does the hybrid need to match Newton?
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 4: Refinement Sweep — N=8 sawtooth, refine 0..10".postln;
"=" ! 70 ++ "";

fork {
    var targets = (1..8).collect { |i| 1.0 / i };
    var numH = 8;

    "".postln;
    "%6s  %14s".format("refine", "Hybrid Error").postln;
    "-" ! 25 ++ "";

    (0..10).do { |refine|
        var synth, oscFunc;
        var errVal = nil;

        oscFunc = OSCFunc({ |msg|
            if(msg[3] < 1e5 and: { errVal.isNil }) {
                errVal = msg[3];
            };
        }, '/cmp_refine');

        synth = {
            var sol = NQDTSSolver.kr(numH, refine, *targets);
            SendReply.kr(Impulse.kr(5), '/cmp_refine', [sol[numH + 1]]);
            Silent.ar;
        }.play;

        0.5.wait;

        if(errVal.notNil) {
            "%6d  %14.10f".format(refine, errVal).postln;
        } {
            "%6d  (no result)".format(refine).postln;
        };

        oscFunc.free;
        synth.free;
        0.2.wait;
    };

    0.3.wait;
    "".postln;
    "Test 4 complete.".postln;
    "Note: refine=0 is pure neural, higher values add Newton iterations.".postln;
};
)

// ============================================================
// TEST 5: Amplitude Comparison
// Compare the actual carrier amplitudes produced by each solver
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 5: Amplitude Comparison — N=5, sawtooth".postln;
"=" ! 70 ++ "";

fork {
    var targets = [1.0, 0.5, 0.333, 0.25, 0.2];
    var numH = 5;
    var synth;
    var newtonAmps, neuralAmps, hybridAmps;
    var gotResult = false;

    OSCFunc({ |msg|
        if(gotResult.not) {
            // msg[3..8] = newton amps (6 values: A1..A6)
            // msg[9..14] = neural amps
            // msg[15..20] = hybrid amps
            newtonAmps = msg[3..8];
            neuralAmps = msg[9..14];
            hybridAmps = msg[15..20];
            gotResult = true;
        };
    }, '/cmp_amps').oneShot;

    synth = {
        var newton = QDTSSolver.kr(numH, *targets);
        var neural = NQDTSSolver.kr(numH, 0, *targets);
        var hybrid = NQDTSSolver.kr(numH, 5, *targets);
        // Send all amplitudes (excluding error)
        SendReply.kr(Impulse.kr(2), '/cmp_amps',
            newton[0..numH] ++ neural[0..numH] ++ hybrid[0..numH]);
        Silent.ar;
    }.play;

    1.2.wait;
    synth.free;

    if(gotResult) {
        "".postln;
        "Targets: %".format(targets).postln;
        "".postln;
        "%6s  %s".format("", (numH + 1).collect { |i| "A_%".format(i + 1).padLeft(10) }.join("  ")).postln;
        "-" ! 70 ++ "";
        "%6s  %s".format("Newton", newtonAmps.collect { |v| v.round(0.000001).asString.padLeft(10) }.join("  ")).postln;
        "%6s  %s".format("Neural", neuralAmps.collect { |v| v.round(0.000001).asString.padLeft(10) }.join("  ")).postln;
        "%6s  %s".format("Hybrid", hybridAmps.collect { |v| v.round(0.000001).asString.padLeft(10) }.join("  ")).postln;
        "".postln;
        "Max Newton-Neural diff: %".format(
            (newtonAmps - neuralAmps).abs.maxItem.round(0.000001)
        ).postln;
        "Max Newton-Hybrid diff: %".format(
            (newtonAmps - hybridAmps).abs.maxItem.round(0.000001)
        ).postln;
    } {
        "No result received.".postln;
    };

    "".postln;
    "Test 5 complete.".postln;
};
)

// ============================================================
// TEST 6: Dynamic Modulation Stability
// Neural solver handles rapid changes without NRT latency
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 6: Dynamic Modulation Stability".postln;
"Both solvers under rapid LFO modulation of targets".postln;
"=" ! 70 ++ "";

fork {
    var synth;
    var newtonAlerts = 0, neuralAlerts = 0;

    OSCFunc({ |msg|
        var errNewton = msg[3], errNeural = msg[4];
        var badNewton = msg[5], badNeural = msg[6];
        if(badNewton > 0) { newtonAlerts = newtonAlerts + 1 };
        if(badNeural > 0) { neuralAlerts = neuralAlerts + 1 };
    }, '/stability_cmp').fix;

    synth = {
        var numH = 6;
        // Rapidly modulated targets
        var t0 = LFNoise1.kr(4).range(0.3, 1.5);
        var t1 = LFNoise1.kr(5).range(0.05, 0.9);
        var t2 = LFNoise1.kr(3).range(0.05, 0.7);
        var t3 = LFNoise1.kr(6).range(0.05, 0.5);
        var t4 = LFNoise1.kr(4.5).range(0.05, 0.4);
        var t5 = LFNoise1.kr(3.5).range(0.05, 0.3);

        var newton = QDTSSolver.kr(numH, t0, t1, t2, t3, t4, t5);
        var neural = NQDTSSolver.kr(numH, 0, t0, t1, t2, t3, t4, t5);

        var errNewton = newton[numH + 1];
        var errNeural = neural[numH + 1];
        var badNewton = CheckBadValues.kr(errNewton, post: 0);
        var badNeural = CheckBadValues.kr(errNeural, post: 0);

        SendReply.kr(Impulse.kr(10), '/stability_cmp',
            [errNewton, errNeural, badNewton, badNeural]);

        // Also print periodic error comparison
        Poll.kr(Impulse.kr(1), errNewton, "Newton err");
        Poll.kr(Impulse.kr(1), errNeural, "Neural err");

        Silent.ar;
    }.play;

    "Running for 8 seconds with rapid LFO modulation...".postln;
    "Watch for NaN/Inf alerts.".postln;
    "".postln;

    8.wait;

    synth.free;
    OSCFunc.allFuncs.do { |f| if(f.path == '/stability_cmp') { f.free } };

    "".postln;
    "Newton stability alerts: %".format(newtonAlerts).postln;
    "Neural stability alerts: %".format(neuralAlerts).postln;
    "".postln;
    "Test 6 complete.".postln;
};
)

// ============================================================
// TEST 7: Audio A/B Comparison
// Listen to both solvers on the same target spectrum
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 7: Audio A/B Comparison".postln;
"=" ! 70 ++ "";

// SynthDefs for each solver mode
SynthDef(\qdts_newton, { |out = 0, carrierFreq = 2500, targetFreq = 150,
    amp = 0.2, gate = 1,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25, t4 = 0.2,
    t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var numH = 8;
    var env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);
    var solver = QDTSSolver.kr(numH,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01));
    var amps = solver[0..numH];
    var sig = (numH + 1).collect { |i|
        SinOsc.ar(carrierFreq + (i * targetFreq)) * amps[i];
    }.sum;

    Out.ar(out, Limiter.ar(sig * env * amp, 0.9) ! 2);
}).add;

SynthDef(\qdts_neural, { |out = 0, carrierFreq = 2500, targetFreq = 150,
    amp = 0.2, gate = 1,
    t0 = 1, t1 = 0.5, t2 = 0.33, t3 = 0.25, t4 = 0.2,
    t5 = 0.16, t6 = 0.14, t7 = 0.12|

    var numH = 8;
    var refine = \refine.ir(0); // initial-rate: set at Synth creation, not modulatable
    var env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);
    var solver = NQDTSSolver.kr(numH, refine,
        t0.max(0.01), t1.max(0.01), t2.max(0.01), t3.max(0.01),
        t4.max(0.01), t5.max(0.01), t6.max(0.01), t7.max(0.01));
    var amps = solver[0..numH];
    var sig = (numH + 1).collect { |i|
        SinOsc.ar(carrierFreq + (i * targetFreq)) * amps[i];
    }.sum;

    Out.ar(out, Limiter.ar(sig * env * amp, 0.9) ! 2);
}).add;

"SynthDefs loaded. Execute listening tests below.".postln;
"Use headphones or near-field monitors. Carrier at 2500 Hz.".postln;
)

// -- 7a: Sawtooth -- Newton
(
"Playing SAWTOOTH — Newton solver".postln;
~x = Synth(\qdts_newton, [
    \targetFreq, 150,
    \t0, 1, \t1, 0.5, \t2, 0.33, \t3, 0.25,
    \t4, 0.2, \t5, 0.16, \t6, 0.14, \t7, 0.12
]);
)
~x.set(\gate, 0);

// -- 7a: Sawtooth -- Neural
(
"Playing SAWTOOTH — Neural solver".postln;
~x = Synth(\qdts_neural, [
    \targetFreq, 150,
    \t0, 1, \t1, 0.5, \t2, 0.33, \t3, 0.25,
    \t4, 0.2, \t5, 0.16, \t6, 0.14, \t7, 0.12
]);
)
~x.set(\gate, 0);

// -- 7a: Sawtooth -- Hybrid (refine=5)
(
"Playing SAWTOOTH — Hybrid solver (refine=5)".postln;
~x = Synth(\qdts_neural, [
    \targetFreq, 150, \refine, 5,
    \t0, 1, \t1, 0.5, \t2, 0.33, \t3, 0.25,
    \t4, 0.2, \t5, 0.16, \t6, 0.14, \t7, 0.12
]);
)
~x.set(\gate, 0);

// -- 7b: Clarinet
(
"Playing CLARINET — Newton".postln;
~x = Synth(\qdts_newton, [
    \targetFreq, 262,
    \t0, 1.0, \t1, 0.05, \t2, 0.75, \t3, 0.04,
    \t4, 0.5, \t5, 0.03, \t6, 0.3, \t7, 0.02
]);
)
~x.set(\gate, 0);

(
"Playing CLARINET — Neural".postln;
~x = Synth(\qdts_neural, [
    \targetFreq, 262,
    \t0, 1.0, \t1, 0.05, \t2, 0.75, \t3, 0.04,
    \t4, 0.5, \t5, 0.03, \t6, 0.3, \t7, 0.02
]);
)
~x.set(\gate, 0);

// -- 7c: Vowel /a/
(
"Playing VOWEL /a/ — Newton".postln;
~x = Synth(\qdts_newton, [
    \targetFreq, 150,
    \t0, 0.15, \t1, 0.3, \t2, 0.55, \t3, 0.85,
    \t4, 1.0, \t5, 0.7, \t6, 0.9, \t7, 0.5
]);
)
~x.set(\gate, 0);

(
"Playing VOWEL /a/ — Neural".postln;
~x = Synth(\qdts_neural, [
    \targetFreq, 150,
    \t0, 0.15, \t1, 0.3, \t2, 0.55, \t3, 0.85,
    \t4, 1.0, \t5, 0.7, \t6, 0.9, \t7, 0.5
]);
)
~x.set(\gate, 0);

// ============================================================
// TEST 8: Timbre Morphing
// Neural solver updates synchronously every control block.
// Newton solver dispatches async NRT solves with variable latency.
// ============================================================

// -- 8a: Clarinet to Trumpet — Neural (smooth)
(
"".postln;
"=" ! 70 ++ "";
"TEST 8a: Instrumental Morph — Clarinet to Trumpet (Neural)".postln;
"=" ! 70 ++ "";

~clarinet = [1.0, 0.05, 0.75, 0.04, 0.5, 0.03, 0.3, 0.02];
~trumpet  = [1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2];

"Playing morph — Neural solver (5 seconds)...".postln;
~x = Synth(\qdts_neural, [\targetFreq, 220]);

fork {
    200.do { |i|
        var blend = i / 199;
        8.do { |k|
            var val = ~clarinet[k] + (blend * (~trumpet[k] - ~clarinet[k]));
            ~x.set(("t" ++ k).asSymbol, val.max(0.01));
        };
        0.025.wait;
    };
    "Morph complete (clarinet -> trumpet).".postln;
};
)
~x.set(\gate, 0);

// -- 8b: Clarinet to Trumpet — Newton (for comparison)
(
"Playing morph — Newton solver (5 seconds)...".postln;
~x = Synth(\qdts_newton, [\targetFreq, 220]);

fork {
    200.do { |i|
        var blend = i / 199;
        8.do { |k|
            var val = ~clarinet[k] + (blend * (~trumpet[k] - ~clarinet[k]));
            ~x.set(("t" ++ k).asSymbol, val.max(0.01));
        };
        0.025.wait;
    };
    "Morph complete (clarinet -> trumpet).".postln;
};
)
~x.set(\gate, 0);

// -- 8c: Vowel Cycle — Neural
// /a/ -> /e/ -> /i/ -> /o/ -> /u/ -> /a/ (10 seconds total)
// Formant profiles for f0 = 150 Hz (Peterson & Barney 1952)
(
"".postln;
"=" ! 70 ++ "";
"TEST 8c: Vowel Cycle Morph (Neural)".postln;
"/a/ -> /e/ -> /i/ -> /o/ -> /u/ -> /a/  (10 seconds)".postln;
"=" ! 70 ++ "";

~vowels = Dictionary[
    \a -> [0.15, 0.3, 0.55, 0.85, 1.0, 0.7, 0.9, 0.5],   // F1=730, F2=1090
    \e -> [0.2, 0.4, 0.8, 1.0, 0.6, 0.3, 0.2, 0.15],      // F1=530, F2=1840
    \i -> [0.3, 0.8, 0.2, 0.1, 0.08, 0.07, 0.06, 0.05],   // F1=270, F2=2290
    \o -> [0.25, 0.5, 0.75, 1.0, 0.85, 0.9, 0.4, 0.2],    // F1=570, F2=840
    \u -> [0.6, 1.0, 0.35, 0.2, 0.5, 0.8, 0.3, 0.15],     // F1=300, F2=870
];
~vowelSeq = [\a, \e, \i, \o, \u, \a];

~x = Synth(\qdts_neural, [\targetFreq, 150, \carrierFreq, 2500]);

fork {
    var morphTime = 2.0;
    var stepsPerMorph = 80;
    var stepTime = morphTime / stepsPerMorph;

    (~vowelSeq.size - 1).do { |seg|
        var from = ~vowels[~vowelSeq[seg]];
        var to = ~vowels[~vowelSeq[seg + 1]];
        "  /%/ -> /%/".format(~vowelSeq[seg], ~vowelSeq[seg + 1]).postln;

        stepsPerMorph.do { |i|
            var blend = i / (stepsPerMorph - 1);
            8.do { |k|
                var val = from[k] + (blend * (to[k] - from[k]));
                ~x.set(("t" ++ k).asSymbol, val.max(0.01));
            };
            stepTime.wait;
        };
    };
    "Vowel cycle complete.".postln;
};
)
~x.set(\gate, 0);

// -- 8d: Vowel Cycle — Newton (for comparison)
(
"".postln;
"TEST 8d: Vowel Cycle Morph (Newton)".postln;

~x = Synth(\qdts_newton, [\targetFreq, 150, \carrierFreq, 2500]);

fork {
    var morphTime = 2.0;
    var stepsPerMorph = 80;
    var stepTime = morphTime / stepsPerMorph;

    (~vowelSeq.size - 1).do { |seg|
        var from = ~vowels[~vowelSeq[seg]];
        var to = ~vowels[~vowelSeq[seg + 1]];
        "  /%/ -> /%/".format(~vowelSeq[seg], ~vowelSeq[seg + 1]).postln;

        stepsPerMorph.do { |i|
            var blend = i / (stepsPerMorph - 1);
            8.do { |k|
                var val = from[k] + (blend * (to[k] - from[k]));
                ~x.set(("t" ++ k).asSymbol, val.max(0.01));
            };
            stepTime.wait;
        };
    };
    "Vowel cycle complete.".postln;
};
)
~x.set(\gate, 0);

// ============================================================
// TEST 9: Higher N Values (N=12, N=16)
// Only NQDTSSolver has trained models for high N
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 9: High N Values — N=12 and N=16".postln;
"=" ! 70 ++ "";

fork {
    [\twelve, \sixteen].do { |label, idx|
        var numH = [12, 16][idx];
        var targets = (1..numH).collect { |i| 1.0 / i };
        var synth, oscFunc;
        var results = Dictionary.new;
        var done = false;

        oscFunc = OSCFunc({ |msg|
            if(msg[3] < 1e5 and: { done.not }) {
                results[\newton] = msg[3];
                results[\neural] = msg[4];
                results[\hybrid] = msg[5];
                done = true;
            };
        }, '/cmp_highn');

        synth = {
            var newton = QDTSSolver.kr(numH, *targets);
            var neural = NQDTSSolver.kr(numH, 0, *targets);
            var hybrid = NQDTSSolver.kr(numH, 5, *targets);
            SendReply.kr(Impulse.kr(5), '/cmp_highn',
                [newton[numH + 1], neural[numH + 1], hybrid[numH + 1]]);
            Silent.ar;
        }.play;

        1.5.wait;

        if(done) {
            "N=% sawtooth:".format(numH).postln;
            "  Newton: %".format(results[\newton].round(0.000001)).postln;
            "  Neural: %".format(results[\neural].round(0.000001)).postln;
            "  Hybrid: %".format(results[\hybrid].round(0.000001)).postln;
        } {
            "N=%: no result".format(numH).postln;
        };

        oscFunc.free;
        synth.free;
        0.3.wait;
    };

    "".postln;
    "Test 9 complete.".postln;
};
)

// ============================================================
// TEST 10: NQDTS Helper Class
// Verify drop-in replacement works with high-level interface
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"TEST 10: NQDTS Helper Class — Preset Timbres".postln;
"=" ! 70 ++ "";

"Playing NQDTS.sawtooth...".postln;
~x = { NQDTS.sawtooth(8, 150).ar(0.2) ! 2 }.play;
)
~x.free;

(
"Playing NQDTS.square...".postln;
~x = { NQDTS.square(8, 150).ar(0.2) ! 2 }.play;
)
~x.free;

(
"Playing NQDTS.triangle...".postln;
~x = { NQDTS.triangle(8, 150).ar(0.2) ! 2 }.play;
)
~x.free;

(
"Playing NQDTS with refine=5...".postln;
~x = { NQDTS.sawtooth(8, 150, refine: 5).ar(0.2) ! 2 }.play;
)
~x.free;

// ============================================================
// SUMMARY
// ============================================================
(
"".postln;
"=" ! 70 ++ "";
"COMPARISON SUMMARY".postln;
"=" ! 70 ++ "";
"".postln;
"Tests:".postln;
"  1. Error comparison — standard spectra (N=5..8)".postln;
"  2. Error comparison — instrumental spectra".postln;
"  3. Scaling with N (5..16) — sawtooth series".postln;
"  4. Refinement sweep — how many Newton iters to converge".postln;
"  5. Amplitude comparison — carrier values side by side".postln;
"  6. Dynamic modulation stability — rapid LFO targets".postln;
"  7. Audio A/B comparison — listening tests".postln;
"  8a. Instrumental morph — clarinet to trumpet (neural)".postln;
"  8b. Instrumental morph — clarinet to trumpet (Newton)".postln;
"  8c. Vowel cycle morph /a/e/i/o/u/ (neural)".postln;
"  8d. Vowel cycle morph /a/e/i/o/u/ (Newton)".postln;
"  9. High N values (12, 16)".postln;
" 10. NQDTS helper class presets".postln;
"".postln;
"Key observations to verify:".postln;
"  - Neural error should be < 0.001 for N <= 8".postln;
"  - Hybrid (refine=3..5) should approach Newton precision".postln;
"  - Neural solver responds immediately (no NRT latency)".postln;
"  - Morphing should be smoother with neural (per-block updates)".postln;
"  - Neither solver should produce NaN or Inf".postln;
"  - Audio should be perceptually similar between solvers".postln;
)
