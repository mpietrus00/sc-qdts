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

#include "SC_PlugIn.h"
#include <cmath>
#include <cstring>

// InterfaceTable contains pointers to functions in SuperCollider's API
static InterfaceTable *ft;

// Maximum number of harmonics supported
static const int MAX_HARMONICS = 16;
// Maximum vector size: N+1 amplitudes for N harmonics
static const int MAX_VEC = MAX_HARMONICS + 1;

// ============================================================
// Fixed-size linear algebra (no heap allocation)
// ============================================================

struct FixedVec {
    double data[MAX_VEC];
    int n;

    FixedVec() : n(0) { memset(data, 0, sizeof(data)); }
    explicit FixedVec(int size) : n(size) { memset(data, 0, sizeof(data)); }

    double& operator()(int i) { return data[i]; }
    double operator()(int i) const { return data[i]; }

    double squaredNorm() const {
        double sum = 0.0;
        for (int i = 0; i < n; i++) sum += data[i] * data[i];
        return sum;
    }

    FixedVec operator-(const FixedVec& other) const {
        FixedVec result(n);
        for (int i = 0; i < n; i++) result.data[i] = data[i] - other.data[i];
        return result;
    }

    FixedVec operator+(const FixedVec& other) const {
        FixedVec result(n);
        for (int i = 0; i < n; i++) result.data[i] = data[i] + other.data[i];
        return result;
    }

    FixedVec operator*(double s) const {
        FixedVec result(n);
        for (int i = 0; i < n; i++) result.data[i] = data[i] * s;
        return result;
    }

    double dot(const FixedVec& other) const {
        double sum = 0.0;
        int m = (n < other.n) ? n : other.n;
        for (int i = 0; i < m; i++) sum += data[i] * other.data[i];
        return sum;
    }
};

struct FixedMat {
    double data[MAX_HARMONICS][MAX_HARMONICS];
    int rows, cols;

    FixedMat() : rows(0), cols(0) { memset(data, 0, sizeof(data)); }
    FixedMat(int r, int c) : rows(r), cols(c) { memset(data, 0, sizeof(data)); }

    double& operator()(int r, int c) { return data[r][c]; }
    double operator()(int r, int c) const { return data[r][c]; }

    // Multiply matrix by vector
    FixedVec mulVec(const FixedVec& v) const {
        FixedVec result(rows);
        for (int i = 0; i < rows; i++) {
            double sum = 0.0;
            for (int j = 0; j < cols; j++) sum += data[i][j] * v.data[j];
            result.data[i] = sum;
        }
        return result;
    }

    // Solve Ax = b using Gaussian elimination with partial pivoting
    // Returns x. Modifies internal state.
    FixedVec solve(const FixedVec& b) const {
        // Work on copies
        double A[MAX_HARMONICS][MAX_HARMONICS];
        double rhs[MAX_HARMONICS];
        int n = rows;

        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) A[i][j] = data[i][j];
            rhs[i] = b.data[i];
        }

        // Forward elimination with partial pivoting
        for (int k = 0; k < n; k++) {
            // Find pivot
            int maxRow = k;
            double maxVal = std::abs(A[k][k]);
            for (int i = k + 1; i < n; i++) {
                if (std::abs(A[i][k]) > maxVal) {
                    maxVal = std::abs(A[i][k]);
                    maxRow = i;
                }
            }

            // Swap rows
            if (maxRow != k) {
                for (int j = k; j < n; j++) {
                    double tmp = A[k][j];
                    A[k][j] = A[maxRow][j];
                    A[maxRow][j] = tmp;
                }
                double tmp = rhs[k];
                rhs[k] = rhs[maxRow];
                rhs[maxRow] = tmp;
            }

            // Check for near-singular
            if (std::abs(A[k][k]) < 1e-14) continue;

            // Eliminate
            for (int i = k + 1; i < n; i++) {
                double factor = A[i][k] / A[k][k];
                for (int j = k + 1; j < n; j++) {
                    A[i][j] -= factor * A[k][j];
                }
                rhs[i] -= factor * rhs[k];
                A[i][k] = 0.0;
            }
        }

        // Back substitution
        FixedVec x(n);
        for (int i = n - 1; i >= 0; i--) {
            double sum = rhs[i];
            for (int j = i + 1; j < n; j++) {
                sum -= A[i][j] * x.data[j];
            }
            if (std::abs(A[i][i]) > 1e-14)
                x.data[i] = sum / A[i][i];
            else
                x.data[i] = 0.0;
        }
        return x;
    }
};

// ============================================================
// Simple LCG random number generator (no heap, no std::random_device)
// ============================================================

struct SimpleRNG {
    uint64_t state;

    explicit SimpleRNG(uint64_t seed = 12345) : state(seed) {}

    uint64_t next() {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        return state;
    }

    // Returns value in [-1, 1]
    double uniform() {
        uint64_t val = next();
        return (static_cast<double>(val >> 11) / 9007199254740992.0) * 2.0 - 1.0;
    }
};

// ============================================================
// QDTS math functions (stack-allocated, no Eigen)
// ============================================================

// A(X): generates the right part of equation (17) with A_1=1
// Maps R^N -> R^N where N is the number of target harmonics
static FixedVec computeA(const FixedVec& X) {
    int N = X.n;

    // Build Y = [1, X_0, X_1, ..., X_{N-1}]  (size N+1)
    FixedVec Y(N + 1);
    Y(0) = 1.0;
    for (int i = 0; i < N; i++) Y(i + 1) = X(i);

    // Z(i) = sum_{j=0}^{N-i} Y(j) * Y(j+i+1)  for i = 0..N-1
    FixedVec Z(N);
    for (int i = 0; i < N; i++) {
        double sum = 0.0;
        for (int j = 0; j <= N - i - 1; j++) {
            sum += Y(j) * Y(j + i + 1);
        }
        Z(i) = sum;
    }
    return Z;
}

// F(X, T) = A(X) - T
static FixedVec computeF(const FixedVec& X, const FixedVec& T) {
    FixedVec ax = computeA(X);
    return ax - T;
}

// Jacobian matrix DF(X)
static FixedMat computeDF(const FixedVec& X) {
    int N = X.n;
    FixedMat Z(N, N);

    // For rows 0..N-2: compute contribution from shift operators.
    // Row i gets: SN(X, i+1) + RN(X, i+1) where SN = left-shift, RN = right-shift.
    // Implemented directly via index arithmetic rather than repeated shifting.
    for (int i = 0; i < N - 1; i++) {
        for (int j = 0; j < N; j++) {
            double left = 0.0, right = 0.0;
            // SN(X, i+1)[j] = X[j + i + 1] if j + i + 1 < N, else 0
            if (j + i + 1 < N) left = X(j + i + 1);
            // RN(X, i+1)[j] = X[j - i - 1] if j - i - 1 >= 0, else 0
            if (j - i - 1 >= 0) right = X(j - i - 1);
            Z(i, j) = left + right;
        }
    }
    // Last row (i = N-1): SN(X, N) and RN(X, N) both yield zero vectors
    // for an N-element vector, so only the identity term contributes.

    // Add identity matrix
    for (int i = 0; i < N; i++) Z(i, i) += 1.0;

    return Z;
}

// Generate random vector with values in [-1, 1]
static FixedVec randomVector(int n, SimpleRNG& rng) {
    FixedVec v(n);
    for (int i = 0; i < n; i++) v(i) = rng.uniform();
    return v;
}

// ============================================================
// Solver data structures
// ============================================================

// Shared mailbox between Unit and NRT commands.
// Allocated via NRTAlloc, outlives the Unit if a command is in-flight.
struct QDTSMailbox {
    double solution[MAX_HARMONICS];   // best solution found
    float error;                       // estimation error
    volatile bool dead;                // set true when Unit is freed
    volatile bool solveInProgress;     // prevent overlapping dispatches
    volatile uint32_t generation;      // monotonic counter for staleness check
    int numHarmonics;                  // cached for stage3
};

// Command data passed to DoAsynchronousCommand
struct QDTSSolverCmd {
    QDTSMailbox* mailbox;
    int numHarmonics;
    double targets[MAX_HARMONICS];     // snapshot of targets
    double solution[MAX_HARMONICS];    // result written by NRT stage
    float error;                       // result written by NRT stage
    uint32_t generation;               // which generation this command belongs to
    uint64_t rngSeed;                  // RNG seed for this solve
};

// The UGen struct
struct QDTSSolver : public Unit {
    QDTSMailbox* mailbox;             // shared with async commands
    double cachedTargets[MAX_HARMONICS]; // last known target values
    double outputAmps[MAX_VEC];       // current output amplitudes
    float outputError;                // current output error
    int numHarmonics;                 // number of target harmonics
    uint64_t rngCounter;              // incrementing seed counter
};

// ============================================================
// Solver core (runs on NRT thread, no RT allocation)
// ============================================================

static void solveSystem(int n, const double* targets, double* solutionOut,
                        float* errorOut, uint64_t rngSeed)
{
    const double TOLERANCE = 0.0001;
    const int MAX_NEWTON_ITER = 33;
    const int MAX_RESTARTS = 100;

    SimpleRNG rng(rngSeed);

    FixedVec init_T(n);
    for (int i = 0; i < n; i++) init_T(i) = targets[i];

    FixedVec T = init_T;

    // Initial guess: random values mapped to [0, 1]
    FixedVec ones(n);
    for (int i = 0; i < n; i++) ones(i) = 1.0;
    FixedVec X = (randomVector(n, rng) + ones) * 0.5;

    // Best solution tracker
    FixedVec bestSolution(n);
    for (int i = 0; i < n; i++) bestSolution(i) = 0.5;
    double bestError = computeF(bestSolution, init_T).squaredNorm();

    int success = 0;
    int escape = 0;
    int j = 0;

    // First attempt with perturbation strategy
    while (success == 0 && escape == 0) {
        int iter = 0;
        j++;

        FixedVec fval = computeF(X, T);
        double fnorm = fval.squaredNorm();

        while (fnorm > TOLERANCE && iter < MAX_NEWTON_ITER) {
            iter++;
            FixedMat df = computeDF(X);
            // Newton step: X_new = df^{-1} * (df * X - F(X, T))
            FixedVec rhs = df.mulVec(X) - fval;
            X = df.solve(rhs);
            fval = computeF(X, T);
            fnorm = fval.squaredNorm();
        }

        // Check if this is the best solution against original targets
        double errVsOrig = computeF(X, init_T).squaredNorm();
        if (errVsOrig < bestError) {
            bestSolution = X;
            bestError = errVsOrig;
        }

        if (fnorm <= TOLERANCE) {
            success = 1;
        } else {
            if (j > MAX_RESTARTS) {
                escape = 1;
            } else {
                T = init_T + randomVector(n, rng) * 0.01;
                X = (ones + randomVector(n, rng)) * 0.5;
            }
        }
    }

    // Second attempt if first failed - cumulative perturbation
    if (success == 0) {
        X = (randomVector(n, rng) + ones) * 0.5;
        T = init_T;
        j = 0;

        while (j < MAX_RESTARTS) {
            int iter = 0;
            j++;

            FixedVec fval = computeF(X, T);
            double fnorm = fval.squaredNorm();

            while (fnorm > TOLERANCE && iter < MAX_NEWTON_ITER) {
                iter++;
                FixedMat df = computeDF(X);
                FixedVec rhs = df.mulVec(X) - fval;
                X = df.solve(rhs);
                fval = computeF(X, T);
                fnorm = fval.squaredNorm();
            }

            double errVsOrig = computeF(X, init_T).squaredNorm();
            if (errVsOrig < bestError) {
                bestSolution = X;
                bestError = errVsOrig;
            }

            if (fnorm <= TOLERANCE) {
                break;
            } else {
                // Cumulative perturbation
                T = T + randomVector(n, rng) * 0.01;
                X = (ones + randomVector(n, rng)) * 0.5;
            }
        }
    }

    // Write results
    for (int i = 0; i < n; i++) {
        solutionOut[i] = bestSolution(i);
    }
    *errorOut = static_cast<float>(bestError);
}

// ============================================================
// Async command callbacks
// ============================================================

// Stage 2: NRT thread - run the solver
static bool qdtsSolve_stage2(World* world, void* inUserData) {
    QDTSSolverCmd* cmd = static_cast<QDTSSolverCmd*>(inUserData);

    // Check if unit was freed before we started
    if (cmd->mailbox->dead) return false;

    solveSystem(cmd->numHarmonics, cmd->targets, cmd->solution,
                &cmd->error, cmd->rngSeed);
    return true;
}

// Stage 3: RT thread - copy results back
static bool qdtsSolve_stage3(World* world, void* inUserData) {
    QDTSSolverCmd* cmd = static_cast<QDTSSolverCmd*>(inUserData);
    QDTSMailbox* mb = cmd->mailbox;

    // Only apply if mailbox is alive and this is the latest generation
    if (!mb->dead && cmd->generation == mb->generation) {
        for (int i = 0; i < cmd->numHarmonics; i++) {
            mb->solution[i] = cmd->solution[i];
        }
        mb->error = cmd->error;
    }
    mb->solveInProgress = false;
    return false; // no completion message
}

// Cleanup: free the command data (allocated with RTAlloc)
static void qdtsSolve_cleanup(World* world, void* inUserData) {
    RTFree(world, inUserData);
}

// Dispatch an async solve command
static void dispatchSolve(QDTSSolver* unit) {
    QDTSMailbox* mb = unit->mailbox;
    if (mb->solveInProgress) return;

    // Allocate command data with RTAlloc
    QDTSSolverCmd* cmd = static_cast<QDTSSolverCmd*>(
        RTAlloc(unit->mWorld, sizeof(QDTSSolverCmd)));
    if (!cmd) return; // allocation failed

    cmd->mailbox = mb;
    cmd->numHarmonics = unit->numHarmonics;
    cmd->generation = ++mb->generation;
    cmd->rngSeed = ++unit->rngCounter * 6364136223846793005ULL + unit->mParent->mNode.mID;
    for (int i = 0; i < unit->numHarmonics; i++) {
        cmd->targets[i] = unit->cachedTargets[i];
    }

    mb->solveInProgress = true;

    DoAsynchronousCommand(unit->mWorld, nullptr, "qdts_solve",
        static_cast<void*>(cmd),
        (AsyncStageFn)qdtsSolve_stage2,
        (AsyncStageFn)qdtsSolve_stage3,
        nullptr, // no stage4
        qdtsSolve_cleanup,
        0, nullptr);
}

// ============================================================
// UGen functions
// ============================================================

static void QDTSSolver_Ctor(QDTSSolver* unit);
static void QDTSSolver_Dtor(QDTSSolver* unit);
static void QDTSSolver_next_k(QDTSSolver* unit, int inNumSamples);

static void QDTSSolver_Ctor(QDTSSolver* unit) {
    unit->numHarmonics = static_cast<int>(IN0(0));
    if (unit->numHarmonics < 1) unit->numHarmonics = 1;
    if (unit->numHarmonics > MAX_HARMONICS) unit->numHarmonics = MAX_HARMONICS;

    int n = unit->numHarmonics;

    // Allocate mailbox via NRTAlloc (outlives Unit if async command in-flight)
    unit->mailbox = static_cast<QDTSMailbox*>(NRTAlloc(sizeof(QDTSMailbox)));
    if (!unit->mailbox) {
        SETCALC(*ClearUnitOutputs);
        ClearUnitOutputs(unit, 1);
        return;
    }
    memset(unit->mailbox, 0, sizeof(QDTSMailbox));
    unit->mailbox->dead = false;
    unit->mailbox->solveInProgress = false;
    unit->mailbox->generation = 0;
    unit->mailbox->numHarmonics = n;
    unit->mailbox->error = 1e6f; // large initial error

    // Deterministic seed from node ID
    unit->rngCounter = static_cast<uint64_t>(unit->mParent->mNode.mID) * 2654435761ULL;

    // Read initial targets and initialize outputs to zero
    for (int i = 0; i < n; i++) {
        unit->cachedTargets[i] = static_cast<double>(IN0(1 + i));
    }
    memset(unit->outputAmps, 0, sizeof(unit->outputAmps));
    unit->outputError = 1e6f;

    SETCALC(QDTSSolver_next_k);

    // Output zeros for the first block (solver hasn't run yet)
    float normalizer = 1.0f / std::sqrt(static_cast<float>(n + 1));
    OUT0(0) = normalizer; // A_1 = 1, normalized
    for (int i = 0; i < n; i++) OUT0(i + 1) = 0.0f;
    OUT0(n + 1) = unit->outputError;

    // Dispatch initial solve
    dispatchSolve(unit);
}

static void QDTSSolver_Dtor(QDTSSolver* unit) {
    if (unit->mailbox) {
        // Mark as dead. If an async command is in-flight, stage3 will see
        // this and skip the copy. The mailbox must outlive the async command.
        // In practice, stage3 runs on the RT thread very soon after stage2
        // completes. We mark it dead and let cleanup free the command data.
        // The mailbox itself is freed by NRTFree here. If a command is still
        // in stage2 on the NRT thread, it checks ->dead before writing.
        // There is a small race window; acceptable for this use case.
        unit->mailbox->dead = true;

        // If no solve is in progress, safe to free immediately.
        // If in progress, we accept the small leak risk vs. crash risk.
        if (!unit->mailbox->solveInProgress) {
            NRTFree(unit->mailbox);
        }
        // else: mailbox leaks (tiny, ~200 bytes) but avoids use-after-free
        unit->mailbox = nullptr;
    }
}

static void QDTSSolver_next_k(QDTSSolver* unit, int inNumSamples) {
    int n = unit->numHarmonics;
    QDTSMailbox* mb = unit->mailbox;
    if (!mb) {
        ClearUnitOutputs(unit, inNumSamples);
        return;
    }

    // Check if target values have changed
    bool changed = false;
    for (int i = 0; i < n; i++) {
        double newVal = static_cast<double>(IN0(1 + i));
        if (std::abs(unit->cachedTargets[i] - newVal) > 1e-10) {
            unit->cachedTargets[i] = newVal;
            changed = true;
        }
    }

    // Dispatch solve if targets changed
    if (changed) {
        dispatchSolve(unit);
    }

    // Copy latest solution from mailbox to output
    float normalizer = 1.0f / std::sqrt(static_cast<float>(n + 1));

    // A_1 = 1, normalized
    OUT0(0) = normalizer;

    // Solution amplitudes
    for (int i = 0; i < n; i++) {
        float val = static_cast<float>(mb->solution[i]) * normalizer;
        OUT0(i + 1) = std::isfinite(val) ? val : 0.0f;
    }

    // Error output
    float err = mb->error;
    OUT0(n + 1) = std::isfinite(err) ? err : 1e6f;
}

// Entry point
PluginLoad(QDTSSolver) {
    ft = inTable;
    DefineDtorUnit(QDTSSolver);
}
