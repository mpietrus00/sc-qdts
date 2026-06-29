/*
 * NQDTSSolver - Neural Quadratic Distortion Tone Spectra solver
 *
 * A neural-network-based solver for the inverse QDTS mapping,
 * trained by Gutiérrez, E. and Cádiz, R. (https://github.com/cordutie/qdts)
 *
 * Uses a 3-layer MLP (HomogeneousInverse architecture) with optional
 * Newton refinement iterations. Runs entirely on the control-rate thread
 * (no NRT dispatch needed).
 *
 * Supports numHarmonics 5-16 (one trained model per N value).
 * For N < 5, use QDTSSolver instead.
 */

NQDTSSolver : MultiOutUGen {
    *kr { |numHarmonics = 8, refine = 0 ... targets|
        numHarmonics = numHarmonics.asInteger.clip(5, 16);
        refine = refine.asInteger.clip(0, 16);
        ^this.multiNew('control', numHarmonics, refine, *targets);
    }

    *new { |numHarmonics = 8, refine = 0 ... targets|
        ^this.kr(numHarmonics, refine, *targets);
    }

    init { |... theInputs|
        var n = theInputs[0].asInteger.clip(5, 16);
        inputs = theInputs;
        // Outputs: [A_1, A_2, ..., A_{n+1}, error] = n + 2 values
        ^this.initOutputs(n + 2, 'control');
    }

    checkInputs {
        var numHarmonics = inputs[0];
        var refine = inputs[1];
        if(numHarmonics.rate != 'scalar') {
            ^"numHarmonics must be a scalar value";
        };
        if(refine.rate != 'scalar') {
            ^"refine must be a scalar value";
        };
        if((inputs.size - 2) != numHarmonics.asInteger.clip(5, 16)) {
            ^"number of target inputs (%) must match numHarmonics (%)".format(
                inputs.size - 2, numHarmonics.asInteger.clip(5, 16));
        };
        ^this.checkValidInputs;
    }
}

/*
 * NQDTS - High-level interface for neural QDTS synthesis
 *
 * Drop-in replacement for QDTS that uses the neural solver.
 * Supports numHarmonics 5-16.
 */

NQDTS {
    var <numHarmonics;
    var <targets;
    var <baseFreq;
    var <refine;

    *new { |numHarmonics = 8, baseFreq = 440, refine = 0|
        ^super.new.init(numHarmonics, baseFreq, refine);
    }

    init { |n, freq, ref|
        numHarmonics = n.clip(5, 16);
        baseFreq = freq;
        refine = ref.clip(0, 16);
        targets = Array.fill(numHarmonics, { |i| 1.0 / (i + 1) });
    }

    targets_ { |targetArray|
        if(targetArray.size != numHarmonics) {
            "Target array size (%) must match numHarmonics (%)".format(
                targetArray.size, numHarmonics
            ).warn;
            ^this;
        };
        targets = targetArray;
    }

    setTarget { |index, value|
        if(index >= 0 and: { index < numHarmonics }) {
            targets[index] = value;
        } {
            "Index % out of range (0-%)".format(index, numHarmonics - 1).warn;
        };
    }

    solver {
        ^NQDTSSolver.kr(numHarmonics, refine, *targets);
    }

    ar { |amp = 0.1|
        var sol = this.solver;
        var amps = sol[0..numHarmonics];
        var sines = Array.fill(numHarmonics + 1, { |i|
            SinOsc.ar(baseFreq * (i + 1)) * amps[i];
        });
        ^Mix(sines) * amp;
    }

    arFM { |modFreq = 1, modDepth = 0, amp = 0.1|
        var sol = this.solver;
        var amps = sol[0..numHarmonics];
        var freqMod = SinOsc.kr(modFreq) * modDepth;
        var sines = Array.fill(numHarmonics + 1, { |i|
            SinOsc.ar((baseFreq + freqMod) * (i + 1)) * amps[i];
        });
        ^Mix(sines) * amp;
    }

    // Presets

    *sawtooth { |numHarmonics = 8, baseFreq = 440, refine = 0|
        ^this.new(numHarmonics, baseFreq, refine);
    }

    *square { |numHarmonics = 8, baseFreq = 440, refine = 0|
        var nqdts = this.new(numHarmonics, baseFreq, refine);
        nqdts.targets_(Array.fill(numHarmonics, { |i|
            if((i + 1).odd) { 1.0 / (i + 1) } { 0.01 };
        }));
        ^nqdts;
    }

    *triangle { |numHarmonics = 8, baseFreq = 440, refine = 0|
        var nqdts = this.new(numHarmonics, baseFreq, refine);
        nqdts.targets_(Array.fill(numHarmonics, { |i|
            if((i + 1).odd) {
                ((-1) ** ((i) / 2)).abs / ((i + 1) ** 2);
            } { 0.01 };
        }));
        ^nqdts;
    }

    printOn { |stream|
        stream << "NQDTS(numHarmonics: %, baseFreq: %, refine: %, targets: %)".format(
            numHarmonics, baseFreq, refine, targets.round(0.001)
        );
    }
}
