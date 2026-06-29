/*
 * QDTS_SC - Quadratic Distortion Tone Spectra for SuperCollider
 *
 * A solver for a particular system of equations related to the synthesis
 * of Auditory Distortion Products. Such equation was first proposed in:
 * "Kendall, G.S., Haworth, C., and Cadiz, R.F. (2014). Sound Synthesis with
 * Auditory Distortion Products. Computer Music Journal 38(4)".
 *
 * Port from Max/MSP implementation by Gutierrez, E and Cadiz, R.
 */

QDTSSolver : MultiOutUGen {
    *kr { |numHarmonics = 8 ... targets|
        // Clamp numHarmonics to match C++ side
        numHarmonics = numHarmonics.asInteger.clip(1, 16);
        // Outputs: [A_1 (normalized), A_2, ..., A_n+1, error]
        // Total outputs = numHarmonics + 2
        ^this.multiNew('control', numHarmonics, *targets);
    }

    *new { |numHarmonics = 8 ... targets|
        ^this.kr(numHarmonics, *targets);
    }

    init { |... theInputs|
        var n = theInputs[0].asInteger.clip(1, 16);
        inputs = theInputs;
        ^this.initOutputs(n + 2, 'control');
    }

    checkInputs {
        var numHarmonics = inputs[0];
        if(numHarmonics.rate != 'scalar') {
            ^"numHarmonics must be a scalar value";
        };
        // Verify target count matches numHarmonics
        if((inputs.size - 1) != numHarmonics.asInteger.clip(1, 16)) {
            ^"number of target inputs (%) must match numHarmonics (%)".format(
                inputs.size - 1, numHarmonics.asInteger.clip(1, 16));
        };
        ^this.checkValidInputs;
    }
}

/*
 * QDTS - High-level interface for Quadratic Distortion Tone Spectra synthesis
 *
 * This class provides a convenient way to synthesize sounds using
 * Auditory Distortion Products (ADPs).
 *
 * NOTE: QDTS is a language-side helper class, not a UGen. Each call to
 * .solver, .ar, .amplitudes, or .error builds new UGen graph nodes.
 * Use .ar or .solver once in a SynthDef function, not repeatedly.
 */

QDTS {
    var <numHarmonics;
    var <targets;
    var <baseFreq;

    *new { |numHarmonics = 8, baseFreq = 440|
        ^super.new.init(numHarmonics, baseFreq);
    }

    init { |n, freq|
        numHarmonics = n.clip(1, 16);
        baseFreq = freq;
        // Default target: sawtooth-like spectrum
        targets = Array.fill(numHarmonics, { |i| 1.0 / (i + 1) });
    }

    // Set target spectrum from an array of harmonic amplitudes
    targets_ { |targetArray|
        if(targetArray.size != numHarmonics) {
            "Target array size (%) must match numHarmonics (%)".format(
                targetArray.size, numHarmonics
            ).warn;
            ^this;
        };
        targets = targetArray;
    }

    // Set individual target harmonic (0-indexed)
    setTarget { |index, value|
        if(index >= 0 and: { index < numHarmonics }) {
            targets[index] = value;
        } {
            "Index % out of range (0-%)".format(index, numHarmonics - 1).warn;
        };
    }

    // Get the solver UGen (returns array of [amplitudes, error])
    // Creates a single QDTSSolver UGen node.
    solver {
        ^QDTSSolver.kr(numHarmonics, *targets);
    }

    // Synthesize audio using the solved amplitudes.
    // Uses a single solver instance internally.
    ar { |amp = 0.1|
        var sol = this.solver;
        var amps = sol[0..numHarmonics];
        var sines = Array.fill(numHarmonics + 1, { |i|
            SinOsc.ar(baseFreq * (i + 1)) * amps[i];
        });
        ^Mix(sines) * amp;
    }

    // Synthesize with frequency modulation.
    // Uses a single solver instance internally.
    arFM { |modFreq = 1, modDepth = 0, amp = 0.1|
        var sol = this.solver;
        var amps = sol[0..numHarmonics];
        var freqMod = SinOsc.kr(modFreq) * modDepth;
        var sines = Array.fill(numHarmonics + 1, { |i|
            SinOsc.ar((baseFreq + freqMod) * (i + 1)) * amps[i];
        });
        ^Mix(sines) * amp;
    }

    // Common target spectra presets

    *sawtooth { |numHarmonics = 8, baseFreq = 440|
        ^this.new(numHarmonics, baseFreq);
        // Default init already sets sawtooth targets
    }

    *square { |numHarmonics = 8, baseFreq = 440|
        var qdts = this.new(numHarmonics, baseFreq);
        qdts.targets_(Array.fill(numHarmonics, { |i|
            if((i + 1).odd) { 1.0 / (i + 1) } { 0.01 };
        }));
        ^qdts;
    }

    *triangle { |numHarmonics = 8, baseFreq = 440|
        var qdts = this.new(numHarmonics, baseFreq);
        qdts.targets_(Array.fill(numHarmonics, { |i|
            if((i + 1).odd) {
                ((-1) ** ((i) / 2)).abs / ((i + 1) ** 2);
            } { 0.01 };
        }));
        ^qdts;
    }

    // Print current state
    printOn { |stream|
        stream << "QDTS(numHarmonics: %, baseFreq: %, targets: %)".format(
            numHarmonics, baseFreq, targets.round(0.001)
        );
    }
}
