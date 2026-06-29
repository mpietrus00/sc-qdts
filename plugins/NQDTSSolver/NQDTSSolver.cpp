/*
 * NQDTSSolver - Neural Quadratic Distortion Tone Spectra solver
 *
 * A neural-network-based solver for the inverse QDTS mapping.
 * Given N target harmonic amplitudes, predicts N+1 carrier amplitudes
 * using a trained MLP (HomogeneousInverse architecture from Gutiérrez & Cádiz).
 *
 * Optionally refines the prediction with Newton iterations (hybrid mode).
 *
 * Network architecture per N value:
 *   Linear(N, 256) + SiLU → Linear(256, 256) + ReLU → Linear(256, 256) + ReLU → Linear(256, N+1)
 * with homogeneous scaling: G(T) = g(T/‖T‖) × √‖T‖
 *
 * Weights trained by Gutiérrez, E. and Cádiz, R.
 * https://github.com/cordutie/qdts
 */

#include "SC_PlugIn.h"
#include "nqdts_weights.h"
#include <cmath>
#include <cstring>

static InterfaceTable *ft;

// ============================================================
// Constants
// ============================================================

static const int MAX_HARMONICS = 16;
static const int MAX_VEC = MAX_HARMONICS + 1;
static const int HIDDEN = NQDTS_HIDDEN; // 256

// ============================================================
// UGen struct
// ============================================================

struct NQDTSSolver : public Unit {
    int numHarmonics;
    int refineIters;

    // Pointers into static weight data
    const float* w_in;   // [HIDDEN × n]
    const float* b_in;   // [HIDDEN]
    const float* w_h0;   // [HIDDEN × HIDDEN]
    const float* b_h0;   // [HIDDEN]
    const float* w_h1;   // [HIDDEN × HIDDEN]
    const float* b_h1;   // [HIDDEN]
    const float* w_out;  // [(n+1) × HIDDEN]
    const float* b_out;  // [n+1]

    double cachedTargets[MAX_HARMONICS];
    float outputAmps[MAX_VEC];
    float outputError;
    bool weightsValid;
};

// ============================================================
// Neural forward pass
// ============================================================

static inline float silu(float x) {
    return x / (1.0f + expf(-x));
}

static void neuralForward(NQDTSSolver* unit, const double* targets, float* carriersOut, float* errorOut) {
    int n = unit->numHarmonics;

    // Step 1: Compute input norm
    float normSq = 0.0f;
    for (int i = 0; i < n; i++) {
        float t = static_cast<float>(targets[i]);
        normSq += t * t;
    }
    float norm = sqrtf(normSq > 1e-12f ? normSq : 1e-12f);
    float scale = sqrtf(norm);  // √‖T‖

    // Step 2: Normalize input
    float T_unit[MAX_HARMONICS];
    float invNorm = 1.0f / norm;
    for (int i = 0; i < n; i++) {
        T_unit[i] = static_cast<float>(targets[i]) * invNorm;
    }

    // Step 3: Input layer — Linear(n, 256) + SiLU
    float h0[HIDDEN];
    const float* wi = unit->w_in;
    const float* bi = unit->b_in;
    for (int j = 0; j < HIDDEN; j++) {
        float sum = bi[j];
        // w_in is row-major [HIDDEN][n], row j starts at j*n
        const float* row = wi + j * n;
        for (int i = 0; i < n; i++) {
            sum += row[i] * T_unit[i];
        }
        h0[j] = silu(sum);
    }

    // Step 4: Hidden layer 0 — Linear(256, 256) + ReLU
    float h1[HIDDEN];
    const float* wh0 = unit->w_h0;
    const float* bh0 = unit->b_h0;
    for (int j = 0; j < HIDDEN; j++) {
        float sum = bh0[j];
        const float* row = wh0 + j * HIDDEN;
        for (int i = 0; i < HIDDEN; i++) {
            sum += row[i] * h0[i];
        }
        h1[j] = sum > 0.0f ? sum : 0.0f; // ReLU
    }

    // Step 5: Hidden layer 1 — Linear(256, 256) + ReLU
    float h2[HIDDEN];
    const float* wh1 = unit->w_h1;
    const float* bh1 = unit->b_h1;
    for (int j = 0; j < HIDDEN; j++) {
        float sum = bh1[j];
        const float* row = wh1 + j * HIDDEN;
        for (int i = 0; i < HIDDEN; i++) {
            sum += row[i] * h1[i];
        }
        h2[j] = sum > 0.0f ? sum : 0.0f; // ReLU
    }

    // Step 6: Output layer — Linear(256, n+1) × scale
    int outSize = n + 1;
    float raw[MAX_VEC];
    const float* wo = unit->w_out;
    const float* bo = unit->b_out;
    for (int j = 0; j < outSize; j++) {
        float sum = bo[j];
        const float* row = wo + j * HIDDEN;
        for (int i = 0; i < HIDDEN; i++) {
            sum += row[i] * h2[i];
        }
        // Apply homogeneous scaling and clamp
        float val = sum * scale;
        raw[j] = val < -2.0f ? -2.0f : (val > 2.0f ? 2.0f : val);
    }

    // Copy to output
    for (int i = 0; i < outSize; i++) {
        carriersOut[i] = raw[i];
    }

    // Compute reconstruction error: ‖D(X) - T‖²
    // D maps R^{n+1} → R^n via anti-diagonal dot products
    float errSum = 0.0f;
    for (int i = 0; i < n; i++) {
        float dval = 0.0f;
        for (int j = 0; j <= n - i - 1; j++) {
            dval += raw[j] * raw[j + i + 1];
        }
        float diff = dval - static_cast<float>(targets[i]);
        errSum += diff * diff;
    }
    *errorOut = errSum / static_cast<float>(n);
}

// ============================================================
// Newton refinement (reuses QDTSSolver math)
// ============================================================

// Fixed-size vector for Newton refinement
struct FVec {
    double d[MAX_HARMONICS];
    int n;
};

// Compute A(X): anti-diagonal dot products with X[0]=1 prepended
static FVec computeA_fv(const double* X, int n) {
    FVec Z;
    Z.n = n;
    // Y = [1, X[0], X[1], ..., X[n-1]]
    double Y[MAX_VEC];
    Y[0] = 1.0;
    for (int i = 0; i < n; i++) Y[i + 1] = X[i];

    for (int i = 0; i < n; i++) {
        double sum = 0.0;
        for (int j = 0; j <= n - i - 1; j++) {
            sum += Y[j] * Y[j + i + 1];
        }
        Z.d[i] = sum;
    }
    return Z;
}

// Newton step: given current X[n] and targets T[n], do one Newton iteration
// X_new = DF(X)^{-1} × (DF(X)×X - F(X,T))
// F(X,T) = A(X) - T
// DF(X) = Jacobian of A(X) + I
static void newtonStep(double* X, const double* T, int n) {
    // Compute F(X, T) = A(X) - T
    FVec AX = computeA_fv(X, n);
    double F[MAX_HARMONICS];
    for (int i = 0; i < n; i++) F[i] = AX.d[i] - T[i];

    // Compute Jacobian DF(X) = shifts + identity
    double J[MAX_HARMONICS][MAX_HARMONICS];
    memset(J, 0, sizeof(J));
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n; j++) {
            double left = 0.0, right = 0.0;
            if (j + i + 1 < n) left = X[j + i + 1];
            if (j - i - 1 >= 0) right = X[j - i - 1];
            J[i][j] = left + right;
        }
    }
    for (int i = 0; i < n; i++) J[i][i] += 1.0;

    // Compute RHS = J×X - F
    double rhs[MAX_HARMONICS];
    for (int i = 0; i < n; i++) {
        double sum = 0.0;
        for (int j = 0; j < n; j++) sum += J[i][j] * X[j];
        rhs[i] = sum - F[i];
    }

    // Solve J × X_new = rhs via Gaussian elimination with partial pivoting
    double A[MAX_HARMONICS][MAX_HARMONICS];
    double b[MAX_HARMONICS];
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) A[i][j] = J[i][j];
        b[i] = rhs[i];
    }

    for (int k = 0; k < n; k++) {
        int maxRow = k;
        double maxVal = std::abs(A[k][k]);
        for (int i = k + 1; i < n; i++) {
            if (std::abs(A[i][k]) > maxVal) {
                maxVal = std::abs(A[i][k]);
                maxRow = i;
            }
        }
        if (maxRow != k) {
            for (int j = k; j < n; j++) {
                double tmp = A[k][j]; A[k][j] = A[maxRow][j]; A[maxRow][j] = tmp;
            }
            double tmp = b[k]; b[k] = b[maxRow]; b[maxRow] = tmp;
        }
        if (std::abs(A[k][k]) < 1e-14) continue;
        for (int i = k + 1; i < n; i++) {
            double factor = A[i][k] / A[k][k];
            for (int j = k + 1; j < n; j++) A[i][j] -= factor * A[k][j];
            b[i] -= factor * b[k];
            A[i][k] = 0.0;
        }
    }

    // Back substitution
    for (int i = n - 1; i >= 0; i--) {
        double sum = b[i];
        for (int j = i + 1; j < n; j++) sum -= A[i][j] * X[j];
        if (std::abs(A[i][i]) > 1e-14)
            X[i] = sum / A[i][i];
        else
            X[i] = 0.0;
    }
}

// ============================================================
// UGen functions
// ============================================================

static void NQDTSSolver_Ctor(NQDTSSolver* unit);
static void NQDTSSolver_next_k(NQDTSSolver* unit, int inNumSamples);

static void NQDTSSolver_Ctor(NQDTSSolver* unit) {
    unit->numHarmonics = static_cast<int>(IN0(0));
    if (unit->numHarmonics < NQDTS_N_MIN) unit->numHarmonics = NQDTS_N_MIN;
    if (unit->numHarmonics > NQDTS_N_MAX) unit->numHarmonics = NQDTS_N_MAX;

    unit->refineIters = static_cast<int>(IN0(1));
    if (unit->refineIters < 0) unit->refineIters = 0;
    if (unit->refineIters > 16) unit->refineIters = 16;

    int n = unit->numHarmonics;
    int modelIdx = n - NQDTS_N_MIN;

    // Look up weight pointers from static data
    if (modelIdx >= 0 && modelIdx < NQDTS_NUM_MODELS) {
        const NQDTSModelInfo& info = NQDTS_MODELS[modelIdx];
        unit->w_in  = nqdts_weight_data + info.w_in_off  / sizeof(float);
        unit->b_in  = nqdts_weight_data + info.b_in_off  / sizeof(float);
        unit->w_h0  = nqdts_weight_data + info.w_h0_off  / sizeof(float);
        unit->b_h0  = nqdts_weight_data + info.b_h0_off  / sizeof(float);
        unit->w_h1  = nqdts_weight_data + info.w_h1_off  / sizeof(float);
        unit->b_h1  = nqdts_weight_data + info.b_h1_off  / sizeof(float);
        unit->w_out = nqdts_weight_data + info.w_out_off  / sizeof(float);
        unit->b_out = nqdts_weight_data + info.b_out_off  / sizeof(float);
        unit->weightsValid = true;
    } else {
        unit->weightsValid = false;
    }

    // Read initial targets
    for (int i = 0; i < n; i++) {
        unit->cachedTargets[i] = static_cast<double>(IN0(2 + i));
    }

    memset(unit->outputAmps, 0, sizeof(unit->outputAmps));
    unit->outputError = 1e6f;

    SETCALC(NQDTSSolver_next_k);

    // Run initial solve
    if (unit->weightsValid) {
        float amps[MAX_VEC];
        float err;
        neuralForward(unit, unit->cachedTargets, amps, &err);

        // Optional Newton refinement
        if (unit->refineIters > 0) {
            double X[MAX_HARMONICS];
            // Neural output is [A_1, A_2, ..., A_{n+1}]
            // Newton solver works with [A_2, ..., A_{n+1}] (A_1=1 implicit)
            // Scale: neural output is raw amplitudes; Newton expects A_1=1 convention
            double a1 = static_cast<double>(amps[0]);
            if (std::abs(a1) > 1e-10) {
                for (int i = 0; i < n; i++) {
                    X[i] = static_cast<double>(amps[i + 1]) / a1;
                }
            } else {
                for (int i = 0; i < n; i++) X[i] = 0.5;
            }

            // Newton iterations
            for (int iter = 0; iter < unit->refineIters; iter++) {
                newtonStep(X, unit->cachedTargets, n);
            }

            // Convert back: A_1 = 1, X contains A_2..A_{n+1}
            amps[0] = 1.0f;
            for (int i = 0; i < n; i++) {
                amps[i + 1] = static_cast<float>(X[i]);
            }

            // Recompute error
            FVec AX = computeA_fv(X, n);
            float errSum = 0.0f;
            for (int i = 0; i < n; i++) {
                float diff = static_cast<float>(AX.d[i] - unit->cachedTargets[i]);
                errSum += diff * diff;
            }
            err = errSum;
        }

        // Store
        for (int i = 0; i < n + 1; i++) unit->outputAmps[i] = amps[i];
        unit->outputError = err;
    }

    // Output first block
    float normalizer = 1.0f / sqrtf(static_cast<float>(n + 1));
    for (int i = 0; i < n + 1; i++) {
        float val = unit->outputAmps[i] * normalizer;
        OUT0(i) = std::isfinite(val) ? val : 0.0f;
    }
    OUT0(n + 1) = std::isfinite(unit->outputError) ? unit->outputError : 1e6f;
}

static void NQDTSSolver_next_k(NQDTSSolver* unit, int inNumSamples) {
    int n = unit->numHarmonics;

    if (!unit->weightsValid) {
        ClearUnitOutputs(unit, inNumSamples);
        return;
    }

    // Check if targets changed
    bool changed = false;
    for (int i = 0; i < n; i++) {
        double newVal = static_cast<double>(IN0(2 + i));
        if (std::abs(unit->cachedTargets[i] - newVal) > 1e-10) {
            unit->cachedTargets[i] = newVal;
            changed = true;
        }
    }

    if (changed) {
        float amps[MAX_VEC];
        float err;
        neuralForward(unit, unit->cachedTargets, amps, &err);

        // Optional Newton refinement
        if (unit->refineIters > 0) {
            double X[MAX_HARMONICS];
            double a1 = static_cast<double>(amps[0]);
            if (std::abs(a1) > 1e-10) {
                for (int i = 0; i < n; i++) {
                    X[i] = static_cast<double>(amps[i + 1]) / a1;
                }
            } else {
                for (int i = 0; i < n; i++) X[i] = 0.5;
            }

            for (int iter = 0; iter < unit->refineIters; iter++) {
                newtonStep(X, unit->cachedTargets, n);
            }

            amps[0] = 1.0f;
            for (int i = 0; i < n; i++) {
                amps[i + 1] = static_cast<float>(X[i]);
            }

            FVec AX = computeA_fv(X, n);
            float errSum = 0.0f;
            for (int i = 0; i < n; i++) {
                float diff = static_cast<float>(AX.d[i] - unit->cachedTargets[i]);
                errSum += diff * diff;
            }
            err = errSum;
        }

        for (int i = 0; i < n + 1; i++) unit->outputAmps[i] = amps[i];
        unit->outputError = err;
    }

    // Output
    float normalizer = 1.0f / sqrtf(static_cast<float>(n + 1));
    for (int i = 0; i < n + 1; i++) {
        float val = unit->outputAmps[i] * normalizer;
        OUT0(i) = std::isfinite(val) ? val : 0.0f;
    }
    OUT0(n + 1) = std::isfinite(unit->outputError) ? unit->outputError : 1e6f;
}

// Entry point
PluginLoad(NQDTSSolver) {
    ft = inTable;
    DefineSimpleUnit(NQDTSSolver);
}
