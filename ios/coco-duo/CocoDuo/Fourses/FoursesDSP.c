// FoursesDSP.c — the four horses and the two resonant filters, as circuits (k.odk)
//
// THE HORSES: Blasser's Fourses as built on crucFX's boards (TARPTERGE), read from their Gerbers and run in SPICE.
// Each horse: a timing capacitor charged and discharged by switched current mirrors (4066 A / B), an LM358 buffer
// of the capacitor and an LM358 comparator whose + input takes a bound through 4066 D (going up: the buffer of the
// horse above, through 100K + 10K) or C (going down: the one below); 2.2M from the output gives the hysteresis. The
// stack: the floor and the ceiling are dividers off the top horse's bias. The rates: two differential pairs (NPN for
// up, PNP for down) whose tails are current sources on the pot; the pairs' bases sit on 10K to a 22K/22K bias and
// on a 100K ladder whose three touch nodes unbalance them.
//   What is exact here: every resistor between the nodes (the network is solved each step), the capacitors (the
//   timing capacitor and the pulse capacitor, implicit), the 4066s (their on-resistance against their control
//   voltage, as in the SPICE model), the pairs (a logistic of the base difference, 25 mV), the supply (a diode and
//   a source resistance into 100 µF, sagging under the load it feeds).
//   What is measured: the tails against the pot and the supply, and the mirrors against the capacitor's voltage
//   (their Early slope and their headroom), all from SPICE sweeps of the full netlist.
//   What is modelled: the LM358s — a gm stage (9 µA · tanh(21 Δ)) into 30 pF, the output a soft rail at 0.05 …
//   Vcc − 1.5 (as the SPICE model) but without its wind-up (a real 358 comes off the rail in microseconds).
// THE FILTERS (DUB): two OTA state-variable band-passes (LM13700 + TL084), as the Dubernator board has them: the
//   input and the low-pass summed into the first op-amp with the resonance pot's share of the band-pass (Q = 1 / 4r,
//   0: it rings by itself), each OTA fed its output through 47K / 470, the integrators on 1 nF. The bias: an
//   exponential PNP off the FREQ pot (220K / 4.7K onto a follower's base), steered by a PNP pair whose bases take
//   the CV nodes through 220K / 4.7K.

#include "FoursesDSP.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>

#include "FoursesTails.h"

// ---------------------------------------------------------------- the board's nodes (the app's order)
// role: 0 POS · 1 BUF · 2 PULSE · 3 THR · 4 GATE · 5 NGATE · 6 BOUND UP · 7 BOUND DOWN · 8 LADDER A · 9 LADDER MID · 10 LADDER B
static const int kRole[44] = { 4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6, 4, 3, 2, 1,
                               0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6 };
static const int kHorse[44] = { 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2,
                                2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0 };
int fr_node_role(int n) { if (n >= 200 && n < 244) n -= 200; return (n >= 0 && n < 44) ? kRole[n] : -1; }
int fr_node_horse(int n) { if (n >= 200 && n < 244) n -= 200; return (n >= 0 && n < 44) ? kHorse[n] : -1; }

// internal nodes: 14 a horse, then the rest
enum { P_POS, P_BUF, P_PUL, P_THR, P_GAT, P_NGT, P_BUP, P_BLO, P_LA, P_LM, P_LB, P_B, P_PB, P_BIAS, P_N };
// horses 0…3 TARPTERGE, 4…7 ARPSERGE (each board its own stack); INTERSEXON: eight sample & holds, eight current cells
#define NH 8
#define NSH 8
enum {
    N_OUTL = NH * P_N, N_OUTR, N_FING0, N_SHIN0 = N_FING0 + 5, N_SHG0 = N_SHIN0 + NSH, N_SHO0 = N_SHG0 + NSH,
    N_VI0 = N_SHO0 + NSH, N_DUB0 = N_VI0 + 2 * NSH, N_DR0 = N_DUB0 + 4, N_ASH0 = N_DR0 + 16, N_NODES = N_ASH0 + 2
};
static const int kRoleToP[11] = { P_POS, P_BUF, P_PUL, P_THR, P_GAT, P_NGT, P_BUP, P_BLO, P_LA, P_LM, P_LB };

static int node_index(int id) {
    if (id >= 0 && id < 44) return kHorse[id] * P_N + kRoleToP[kRole[id]];
    if (id >= 200 && id < 244) return (4 + kHorse[id - 200]) * P_N + kRoleToP[kRole[id - 200]];
    if (id == 46) return N_OUTL;
    if (id == 47) return N_OUTR;
    if (id >= 48 && id < 53) return N_FING0 + id - 48;
    if (id >= 300 && id < 300 + NSH) return N_SHIN0 + id - 300;
    if (id >= 310 && id < 310 + NSH) return N_SHG0 + id - 310;
    if (id >= 320 && id < 320 + NSH) return N_SHO0 + id - 320;
    if (id >= 330 && id < 330 + 2 * NSH) return N_VI0 + id - 330;
    if (id >= 80 && id < 84) return N_DUB0 + id - 80;
    if (id >= 100 && id < 116) return N_DR0 + id - 100;
    if (id == 90 || id == 91) return N_ASH0 + id - 90;
    return -1;
}

// ---------------------------------------------------------------- constants
#define VT 0.025f            // the pairs (SPICE at 27 °C)
#define C_PULSE 10e-9f
#define R_MIR 4700.0f        // each mirror's output resistor
#define G100K 1e-5f
#define G10K 1e-4f
#define G22K (1.0f / 22000.0f)
#define C_SUPPLY 100e-6f
#define DEC_TAPS 96
#define OS 4                 // oversampling
#define MAXE (128 + FR_MAX_LINKS)

typedef struct { int a, b; float g; } Edge;

struct FrEngine {
    float host, fs, dt;
    // parameters (written by the main thread)
    volatile float pot[NH], starve, drift[16], level;
    volatile int range[NH];
    volatile int dubOn;
    volatile float dubF[2], dubR[2];
    // links: the main thread fills `pend` and raises `hasPend`; the audio thread takes them at a block's start
    int pendA[FR_MAX_LINKS], pendB[FR_MAX_LINKS], pendV[FR_MAX_LINKS];
    int pendN;
    atomic_int hasPend;
    atomic_int resetReq;
    // the network
    float V[N_NODES];
    float srcG[N_NODES], srcI[N_NODES], diag[N_NODES], lo[N_NODES], hi[N_NODES];
    Edge e[MAXE];
    int ne, nStatic, eSwD[NH], eSwC[NH];
    int adjOff[N_NODES + 1], adjN[2 * MAXE], adjE[2 * MAXE];
    // the horses
    float vint[NH], out[NH], buf[NH], pulPrev[NH], outPrev[NH];
    float ledAcc[NH]; int ledN;
    float cvAcc[NH]; int cvN;
    float peak;                        // (the output's peak since the last look, for VOLUME's meter)
    float ashLo[2], ashHi[2]; int ashN; // CAFE A / B: the lowest and highest on their terminals since the last look
    // the output held back (CAFE: so the phone sounds when the Cafe's ASH does — what Bluetooth takes)
    #define DLY_MAX 24000
    float dly[2][DLY_MAX]; int dlyPos; volatile int dlyWant; int dlyNow;
    // ANALOG: the output as the hardware's (hard, bright highs), its attacks held down (a compressor on the instant only)
    int danger;
    float dzL, dzR, dz2L, dz2R, dEnv, dSlow;          // (each horse's CV — its buffer — summed, for the LEDs' colour)
    // how much current each node passes through its links (the screen's colours)
    float cur[N_NODES]; int actN;
    // INTERSEXON's nodes take almost no current (high-impedance ins): how much each moves shows how it is driven
    float iMean[N_DUB0 - N_SHIN0], iDev[N_DUB0 - N_SHIN0];
    // the supply
    float vcc;
    // cached: the tails (every 32 steps), the static edges' sums, the nodes the network must solve
    float tu[NH], td[NH]; int tailN;
    float edgeSum[N_NODES];
    int act[N_NODES], nAct, pas[N_NODES], nPas;
    // INTERSEXON
    float held[NSH];
    // the hum
    float humPh;
    // the filters
    float bp[2], lp[2], dubInHp[2], dubInX[2], dubMix;
    unsigned int rnd;
    // the output
    float dcL, dcR;
    float hist[2][DEC_TAPS]; int hpos;
    float taps[DEC_TAPS];
};

// ---------------------------------------------------------------- small pieces
static inline float clampf(float x, float a, float b) { return x < a ? a : (x > b ? b : x); }
/// tanh, rational (|error| < 2e-4; exact enough for switches and gm stages)
static inline float ftanh(float x) {
    if (x > 4.97f) return 1.0f;
    if (x < -4.97f) return -1.0f;
    float x2 = x * x;
    float a = x * (135135.0f + x2 * (17325.0f + x2 * (378.0f + x2)));
    float b = 135135.0f + x2 * (62370.0f + x2 * (3150.0f + x2 * 28.0f));
    return a / b;
}
static inline float sigm(float x) { return 0.5f + 0.5f * ftanh(0.5f * x); }
/// the 4066's conductance against its control (the SPICE model's)
static inline float sw_g(float ctl, float vcc) { return 1e-9f + 0.0025f * (1.0f + ftanh(4.0f * (ctl - 0.5f * vcc))); }
static inline float ser(float g1, float g2) { return g1 * g2 / (g1 + g2); }
static inline float softmin(float a, float b) {        // (the mirror running into its headroom: SPICE's knee)
    if (a <= 0 || b <= 0) return 0;
    float ia = 1.0f / a, ib = 1.0f / b;
    ia *= ia; ia *= ia; ib *= ib; ib *= ib;
    return 1.0f / sqrtf(sqrtf(ia + ib));
}
static float tail(const float t[6][33], float x, float vcc) {
    float fi = clampf(x, 0, 1) * 32.0f;
    int i = (int)fi; if (i > 31) i = 31;
    float fr = fi - i;
    float v = vcc, k = 1.0f;
    if (v < 5.0f) { k = clampf((v - 3.0f) / 2.0f, 0, 1); v = 5.0f; }
    if (v > 12.0f) v = 12.0f;
    int j = 0; while (j < 4 && FR_TVCC[j + 1] < v) j++;
    float fv = (v - FR_TVCC[j]) / (FR_TVCC[j + 1] - FR_TVCC[j]);
    // (log-interpolated: the tails are exponential in the pot)
    float a0 = logf(t[j][i]) * (1 - fr) + logf(t[j][i + 1]) * fr;
    float a1 = logf(t[j + 1][i]) * (1 - fr) + logf(t[j + 1][i + 1]) * fr;
    return k * expf(a0 * (1 - fv) + a1 * fv);
}

static void add_edge(FrEngine *E, int a, int b, float g) {
    if (E->ne >= MAXE || a < 0 || b < 0 || a == b) return;
    E->e[E->ne].a = a; E->e[E->ne].b = b; E->e[E->ne].g = g; E->ne++;
}

/// the fixed resistors between nodes, and a slot for each switch
static void build_static(FrEngine *E) {
    E->ne = 0;
    for (int h = 0; h < NH; h++) {
        int o = h * P_N, s = h & 3, top = ((h & 4) + 3) * P_N;      // (s: its place in its board's stack)
        add_edge(E, o + P_B, o + P_LA, G100K);       // the ladder: base — LA — MID — LB — the other base
        add_edge(E, o + P_LA, o + P_LM, G100K);
        add_edge(E, o + P_LM, o + P_LB, G100K);
        add_edge(E, o + P_LB, o + P_PB, G100K);
        add_edge(E, o + P_B, o + P_BIAS, G10K);      // both bases on 10K to the bias
        add_edge(E, o + P_PB, o + P_BIAS, G10K);
        if (s < 3) add_edge(E, o + P_BUP, (h + 1) * P_N + P_BUF, G100K);   // the bound above: the next horse's buffer
        else add_edge(E, o + P_BUP, top + P_BIAS, G100K);                  // (the ceiling: 100K to Vcc, 100K to the bias)
        if (s > 0) add_edge(E, o + P_BLO, (h - 1) * P_N + P_BUF, G100K);   // the bound below: the one below
        else add_edge(E, o + P_BLO, top + P_BIAS, G100K);                  // (the floor: 100K to 0, 100K to the top's bias)
    }
    for (int h = 0; h < NH; h++) {
        int o = h * P_N;
        E->eSwD[h] = E->ne; add_edge(E, o + P_THR, o + P_BUP, 1e-9f);    // 4066 D + 10K: the upper bound
        E->eSwC[h] = E->ne; add_edge(E, o + P_THR, o + P_BLO, 1e-9f);    // 4066 C + 10K: the lower bound
    }
    E->nStatic = E->ne;
}

static void build_adj(FrEngine *E) {
    // (the switches' slots are recomputed every step: their sums are added there)
    int cnt[N_NODES + 1];
    memset(cnt, 0, sizeof(cnt));
    for (int k = 0; k < E->ne; k++) { cnt[E->e[k].a]++; cnt[E->e[k].b]++; }
    E->adjOff[0] = 0;
    for (int i = 0; i < N_NODES; i++) E->adjOff[i + 1] = E->adjOff[i] + cnt[i];
    int fill[N_NODES];
    for (int i = 0; i < N_NODES; i++) fill[i] = E->adjOff[i];
    for (int k = 0; k < E->ne; k++) {
        int a = E->e[k].a, b = E->e[k].b;
        E->adjN[fill[a]] = b; E->adjE[fill[a]++] = k;
        E->adjN[fill[b]] = a; E->adjE[fill[b]++] = k;
    }
    for (int i = 0; i < N_NODES; i++) E->edgeSum[i] = 0;
    for (int k = 0; k < E->ne; k++) {
        int sw = 0;
        for (int h = 0; h < NH; h++) if (k == E->eSwD[h] || k == E->eSwC[h]) sw = 1;
        if (sw) continue;
        E->edgeSum[E->e[k].a] += E->e[k].g; E->edgeSum[E->e[k].b] += E->e[k].g;
    }
    E->nAct = E->nPas = 0;
    for (int i = 0; i < N_NODES; i++) {
        if (E->adjOff[i + 1] > E->adjOff[i]) E->act[E->nAct++] = i; else E->pas[E->nPas++] = i;
    }
}

static void take_links(FrEngine *E) {
    E->ne = E->nStatic;
    for (int k = 0; k < E->pendN; k++) {
        int a = node_index(E->pendA[k]), b = node_index(E->pendB[k]);
        int v = E->pendV[k];
        if (a < 0 || b < 0 || v <= 0) continue;
        if (v > 1000) v = 1000;
        float R = 2000.0f * powf(5000.0f, (1000 - v) / 1000.0f);
        add_edge(E, a, b, 1.0f / R);
    }
    build_adj(E);
}

static void design_taps(FrEngine *E) {
    // Kaiser-windowed sinc: the band edge at 0.45 of the host rate, 96 taps at four times it
    const double fc = 0.45 / OS, beta = 8.0;
    double sum = 0;
    double i0b = 0; { double t = 1, s = 1; for (int k = 1; k < 40; k++) { t *= (beta / 2) * (beta / 2) / ((double)k * k); s += t; } i0b = s; }
    for (int n = 0; n < DEC_TAPS; n++) {
        double m = n - (DEC_TAPS - 1) / 2.0;
        double x = 2 * fc * m;
        double sinc = fabs(x) < 1e-12 ? 1.0 : sin(M_PI * x) / (M_PI * x);
        double r = 2.0 * n / (DEC_TAPS - 1) - 1.0;
        double arg = beta * sqrt(fmax(0, 1 - r * r));
        double t = 1, s = 1; for (int k = 1; k < 40; k++) { t *= (arg / 2) * (arg / 2) / ((double)k * k); s += t; }
        double w = s / i0b;
        E->taps[n] = (float)(2 * fc * sinc * w);
        sum += E->taps[n];
    }
    for (int n = 0; n < DEC_TAPS; n++) E->taps[n] = (float)(E->taps[n] / sum);
}

// ---------------------------------------------------------------- life
FrEngine *fr_create(double hostRate) {
    FrEngine *E = (FrEngine *)calloc(1, sizeof(FrEngine));
    if (!E) return NULL;
    E->host = (float)hostRate; E->fs = (float)(hostRate * OS); E->dt = 1.0f / E->fs;
    for (int h = 0; h < NH; h++) { E->pot[h] = h < 4 ? 0.25f : 0.5f; E->range[h] = 2; }
    E->starve = 0.5f; E->level = 0.8f;
    E->dubF[0] = E->dubF[1] = 0.45f; E->dubR[0] = E->dubR[1] = 0.6f;
    E->rnd = 0x12345u;
    design_taps(E);
    build_static(E);
    E->pendN = 0;
    atomic_store(&E->hasPend, 1);
    atomic_store(&E->resetReq, 1);
    return E;
}
void fr_destroy(FrEngine *E) { free(E); }
void fr_set_out_delay(FrEngine *E, float seconds) {
    int n = (int)(seconds * E->host);
    E->dlyWant = n < 0 ? 0 : (n > DLY_MAX - 1 ? DLY_MAX - 1 : n);
}
void fr_reset(FrEngine *E) { atomic_store(&E->resetReq, 1); }

static void do_reset(FrEngine *E) {
    E->vcc = 8.4f;
    for (int i = 0; i < N_NODES; i++) E->V[i] = 4.2f;
    for (int h = 0; h < NH; h++) {
        E->V[h * P_N + P_POS] = 1.5f + 1.5f * (h & 3) + 0.3f * (h >> 2);          // (a spread start: they begin already apart)
        E->out[h] = (h & 1) ? 0.05f : 6.8f;
        E->vint[h] = (h & 1) ? -3.0f : 9.0f;
        E->buf[h] = E->V[h * P_N + P_POS];
        E->outPrev[h] = E->out[h]; E->pulPrev[h] = 4.2f;
    }
    for (int k = 0; k < NSH; k++) E->held[k] = 4.2f;
    E->bp[0] = E->bp[1] = E->lp[0] = E->lp[1] = 0;
    E->dubInHp[0] = E->dubInHp[1] = E->dubInX[0] = E->dubInX[1] = 0;
    E->dcL = E->dcR = 0;
    memset(E->hist, 0, sizeof(E->hist));
}

// ---------------------------------------------------------------- the setters
/// TARPTERGE (0…3): the knob's middle where up and down are equal (a quarter of the pot's travel in SPICE): below it
/// the lower quarter, above it the rest. ARPSERGE (4…7): one rate, the knob as it is
void fr_set_pot(FrEngine *E, int h, float v) {
    if (h < 0 || h >= NH) return;
    v = clampf(v, 0, 1);
    E->pot[h] = h >= 4 ? v : (v <= 0.5f ? v * 0.5f : 0.25f + (v - 0.5f) * 1.5f);
}
void fr_set_range(FrEngine *E, int h, int r) { if (h >= 0 && h < NH) E->range[h] = r < 0 ? 0 : (r > 2 ? 2 : r); }
void fr_set_starve(FrEngine *E, float v) { E->starve = clampf(v, 0, 1); }
void fr_set_drift(FrEngine *E, int k, float volts) { if (k >= 0 && k < 16) E->drift[k] = volts; }
void fr_set_level(FrEngine *E, float v) { E->level = clampf(v, 0, 1); }
void fr_set_dub(FrEngine *E, int on, float fa, float fb, float ra, float rb) {
    E->dubOn = on; E->dubF[0] = clampf(fa, 0, 1); E->dubF[1] = clampf(fb, 0, 1);
    E->dubR[0] = clampf(ra, 0, 1); E->dubR[1] = clampf(rb, 0, 1);
}
void fr_set_links(FrEngine *E, const int *a, const int *b, const int *v, int n) {
    // (wait for the audio thread to take the last set: it does so at every block)
    for (int spin = 0; spin < 200000 && atomic_load(&E->hasPend); spin++) { }
    if (n > FR_MAX_LINKS) n = FR_MAX_LINKS;
    for (int k = 0; k < n; k++) { E->pendA[k] = a[k]; E->pendB[k] = b[k]; E->pendV[k] = v[k]; }
    E->pendN = n;
    atomic_store(&E->hasPend, 1);
}
void fr_take_leds(FrEngine *E, float o[8]) {
    int n = E->ledN > 0 ? E->ledN : 1;
    for (int h = 0; h < NH; h++) { o[h] = E->ledAcc[h] / n; E->ledAcc[h] = 0; }
    E->ledN = 0;
}
void fr_take_cv(FrEngine *E, float o[8]) {
    int n = E->cvN > 0 ? E->cvN : 1;
    float top = E->vcc - 1.5f > 1.0f ? E->vcc - 1.5f : 1.0f;      // (the buffer's own top)
    for (int h = 0; h < NH; h++) {
        float v = E->cvAcc[h] / n / top;
        o[h] = v < 0 ? 0 : (v > 1 ? 1 : v);
        E->cvAcc[h] = 0;
    }
    E->cvN = 0;
}
float fr_supply(FrEngine *E) { return E->vcc; }
void fr_set_danger(FrEngine *E, int on) { E->danger = on ? 1 : 0; }
float fr_take_peak(FrEngine *E) { float p = E->peak; E->peak = 0; return p; }
void fr_take_ash(FrEngine *E, float now[2], float lo[2], float hi[2]) {
    for (int k = 0; k < 2; k++) {
        now[k] = E->V[N_ASH0 + k];                                    // (as it is this instant: sampled, not averaged)
        lo[k] = E->ashN > 0 ? E->ashLo[k] : now[k];
        hi[k] = E->ashN > 0 ? E->ashHi[k] : now[k];
    }
    E->ashN = 0;
}
void fr_take_activity(FrEngine *E, const int *ids, float *out, int n) {
    int m = E->actN > 0 ? E->actN : 1;
    for (int k = 0; k < n; k++) {
        int i = node_index(ids[k]);
        float a = i >= 0 ? E->cur[i] / m : 0;
        if (i >= N_SHIN0 && i < N_DUB0) {                                // (INTERSEXON: its swing, as if 20 µA a volt)
            float sw = E->iDev[i - N_SHIN0] / m * 2.0e-5f;
            if (sw > 2.0e-7f && sw > a) a = sw;                           // (a still node: nothing)
        }
        out[k] = a;
    }
    for (int i = 0; i < N_NODES; i++) E->cur[i] = 0;
    for (int j = 0; j < N_DUB0 - N_SHIN0; j++) E->iDev[j] = 0;
    E->actN = 0;
}

// ---------------------------------------------------------------- one step at the internal rate
static inline void step(FrEngine *E, float humV, float *outL, float *outR) {
    const float dt = E->dt, vcc = E->vcc;
    float *V = E->V;
    const float half = 0.5f * (vcc - 1.55f), mid = 0.5f * (vcc - 1.5f);
    float cap[NH];
    // (the capacitors are not on the board's silkscreen: 2.2 nF · 100 nF · 4.7 µF)
    for (int h = 0; h < NH; h++) cap[h] = E->range[h] == 2 ? 2.2e-9f : (E->range[h] == 1 ? 100e-9f : 4.7e-6f);

    // ---- the sources, and what each node is held by
    memset(E->srcG, 0, sizeof(E->srcG)); memset(E->srcI, 0, sizeof(E->srcI));
    float *G = E->srcG, *I = E->srcI;
    float Iload = 2.8e-3f * 2.0f + 1.0e-3f;                  // (the op-amps' own draw: two boards and INTERSEXON)
    for (int h = 0; h < NH; h++) {
        int o = h * P_N;
        float vo = E->out[h];
        // the timing capacitor (implicit) and what the mirrors put into it
        float vp = V[o + P_POS];
        float gc = cap[h] / dt;
        G[o + P_POS] += gc; I[o + P_POS] += gc * vp;
        float fracUp = sigm((V[o + P_B] - V[o + P_PB]) / VT);
        if (E->tailN == 0) {
            if (h < 4) { E->tu[h] = tail(FR_TUP, E->pot[h], vcc); E->td[h] = tail(FR_TDN, E->pot[h], vcc); }
            else {                                                // ARPSERGE: the pot drives one rate, up and down alike
                float t = tail(FR_TDN, 1.0f - E->pot[h], vcc);
                E->tu[h] = t; E->td[h] = t;
            }
        }
        float tu = E->tu[h], td = E->td[h];
        float gA = sw_g(V[o + P_GAT], vcc), gB = sw_g(V[o + P_NGT], vcc);
        E->e[E->eSwD[h]].g = ser(gA, G10K);                  // the switches into the bounds (4066 + 10K)
        E->e[E->eSwC[h]].g = ser(gB, G10K);
        float iu = tu * fracUp * (1.0f + (4.2f - vp) * 0.045f);
        float id = td * (1.0f - fracUp) * (1.0f + (vp - 4.2f) * 0.0129f);
        float hu = vcc - 0.15f - vp, hd = vp - 0.1f;
        iu = softmin(iu, fmaxf(hu, 0) / (R_MIR + 1.0f / gA));
        id = softmin(id, fmaxf(hd, 0) / (R_MIR + 1.0f / gB));
        I[o + P_POS] += iu - id;
        Iload += 1.5f * (tu + td) + iu;
        // the buffer (a follower, slewing, on its rails)
        G[o + P_BUF] += 0.02f; I[o + P_BUF] += 0.02f * E->buf[h];
        // the pulse: 10 nF from the output (implicit)
        float gp = C_PULSE / dt;
        G[o + P_PUL] += gp + 1e-9f; I[o + P_PUL] += gp * (vo + E->pulPrev[h] - E->outPrev[h]) + 1e-9f * 4.2f;
        // the threshold: 2.2M from the output
        G[o + P_THR] += 1.0f / 2.2e6f; I[o + P_THR] += vo / 2.2e6f;
        // the gate: 100K from the output
        G[o + P_GAT] += G100K; I[o + P_GAT] += G100K * vo;
        // the inverted gate: 100K from the inverter (an NPN on 100K from the output, its LED as the pull-up)
        float ic = 416.0f * fmaxf(0, vo - 0.65f) / 100e3f;
        float vpu = fmaxf(0.1f, vcc - 1.75f);
        float n62 = fmaxf(0.08f, vpu - ic * 4500.0f);
        G[o + P_NGT] += G100K; I[o + P_NGT] += G100K * n62;
        if (n62 < 1.0f) Iload += fmaxf(0, vcc - 1.9f) / 4700.0f;   // (the LED lit: it draws)
        // the ends of the stack
        if ((h & 3) == 3) { G[o + P_BUP] += G100K; I[o + P_BUP] += G100K * vcc; }
        if ((h & 3) == 0) { G[o + P_BLO] += G100K; }
        // the bias: 22K / 22K
        G[o + P_BIAS] += 2 * G22K; I[o + P_BIAS] += G22K * vcc;
        Iload += vcc / 44000.0f;
    }
    // the outputs (an amplifier's input: 100K to its reference)
    G[N_OUTL] += G100K; I[N_OUTL] += G100K * 4.2f;
    G[N_OUTR] += G100K; I[N_OUTR] += G100K * 4.2f;
    // the fingers: 1M to the body
    for (int f = 0; f < 5; f++) { G[N_FING0 + f] += 1e-6f; I[N_FING0 + f] += 1e-6f * humV; }
    // INTERSEXON: the holds' inputs (floating: they read what they hold), gates (100K down), outputs (followers)
    for (int k = 0; k < NSH; k++) {
        G[N_SHIN0 + k] += 1e-9f; I[N_SHIN0 + k] += 1e-9f * E->held[k];
        G[N_SHG0 + k] += G100K;
        float ho = clampf(E->held[k], 0.02f, vcc - 1.5f);
        G[N_SHO0 + k] += 0.02f; I[N_SHO0 + k] += 0.02f * ho;
    }
    // … and the current cells: I = (X − Y) / 10K, pushed or pulled at their collectors
    // (each half: D→A, A→D, B→C, C→B — and H→E, E→H, F→G, G→F)
    static const int vx[4] = { 3, 0, 1, 2 }, vy[4] = { 0, 3, 2, 1 };
    for (int j = 0; j < NSH; j++) {
        int so = N_VI0 + 2 * j, si = so + 1, g = j & 4;
        G[so] += 1e-9f; I[so] += 1e-9f * 4.2f; G[si] += 1e-9f; I[si] += 1e-9f * 4.2f;
        float xv = E->held[g + vx[j & 3]], yv = E->held[g + vy[j & 3]];
        if (xv > yv) I[si] -= (xv - yv) * 1e-4f;
        else I[so] += (yv - xv) * 1e-4f;
    }
    // the filters' CV: 220K + 4.7K onto their pairs' bases (4.5 V)
    for (int k = 0; k < 4; k++) { G[N_DUB0 + k] += 1.0f / 224.7e3f; I[N_DUB0 + k] += 4.5f / 224.7e3f; }
    // a shape's own voltage through 33K
    for (int k = 0; k < 16; k++) { G[N_DR0 + k] += 1.0f / 33e3f; I[N_DR0 + k] += E->drift[k] / 33e3f; }
    // CAFE: a probe (1M to 0 V) — it reads what it is joined to, the voltage that goes to the Cafe's ASH
    G[N_ASH0] += 1e-6f; G[N_ASH0 + 1] += 1e-6f;

    if (++E->tailN >= 32) E->tailN = 0;
    // ---- the network: Gauss–Seidel from where it was (a node on nothing: only its own source)
    for (int j = 0; j < E->nPas; j++) { int i = E->pas[j]; V[i] = G[i] > 0 ? I[i] / G[i] : V[i]; }
    for (int i = 0; i < N_NODES; i++) E->diag[i] = G[i] + E->edgeSum[i];
    for (int h = 0; h < NH; h++) {
        Edge *d = &E->e[E->eSwD[h]], *c = &E->e[E->eSwC[h]];
        E->diag[d->a] += d->g; E->diag[d->b] += d->g; E->diag[c->a] += c->g; E->diag[c->b] += c->g;
    }
    for (int it = 0; it < 2; it++) {
        for (int j = 0; j < E->nAct; j++) {
            int i = E->act[j];
            float s = I[i];
            for (int k = E->adjOff[i]; k < E->adjOff[i + 1]; k++) s += E->e[E->adjE[k]].g * V[E->adjN[k]];
            V[i] = s / E->diag[i];
        }
    }
    // (the rails: the inputs' diodes; a current cell's transistor saturates)
    for (int i = 0; i < N_NODES; i++) V[i] = clampf(V[i], -0.6f, vcc + 0.6f);
    for (int j = 0; j < 2 * NSH; j++) V[N_VI0 + j] = clampf(V[N_VI0 + j], 0.1f, vcc - 0.1f);
    for (int k = 0; k < 2; k++) {
        float v = V[N_ASH0 + k];
        if (E->ashN == 0 || v < E->ashLo[k]) E->ashLo[k] = v;
        if (E->ashN == 0 || v > E->ashHi[k]) E->ashHi[k] = v;
    }
    E->ashN++;
    // (what flows through each link, for the screen)
    for (int k = E->nStatic; k < E->ne; k++) {
        float i = fabsf(E->e[k].g * (V[E->e[k].a] - V[E->e[k].b]));
        E->cur[E->e[k].a] += i; E->cur[E->e[k].b] += i;
    }
    E->actN++;
    for (int j = 0; j < N_DUB0 - N_SHIN0; j++) {
        float v = V[N_SHIN0 + j];
        E->iMean[j] += (v - E->iMean[j]) * 2.0e-4f;                     // (its middle, over ~30 ms at 4x)
        E->iDev[j] += fabsf(v - E->iMean[j]);
    }

    // ---- the op-amps
    for (int h = 0; h < NH; h++) {
        int o = h * P_N;
        float vp = V[o + P_POS];
        // the comparator: + THR, − the capacitor
        float d = V[o + P_THR] - vp;
        float vi = E->vint[h] + dt * 3.0e5f * ftanh(21.0f * d);
        E->vint[h] = clampf(vi, mid - 2.0f * half, mid + 2.0f * half);
        E->outPrev[h] = E->out[h];
        E->pulPrev[h] = V[o + P_PUL];
        E->out[h] = 0.05f + (vcc - 1.55f) * 0.5f * (1.0f + ftanh((E->vint[h] - mid) / half));
        if (E->out[h] > 1.0f) E->ledAcc[h] += 1;
        // the buffer: follows the capacitor, 0.3 V/µs, on its rails
        float b = E->buf[h], step = 3.0e5f * dt;
        b += clampf(vp - b, -step, step);
        E->buf[h] = clampf(b, 0.02f, vcc - 1.5f);
        E->cvAcc[h] += E->buf[h];
    }
    E->ledN++;
    E->cvN++;

    // INTERSEXON: a gate above 3 V samples
    for (int k = 0; k < NSH; k++) if (V[N_SHG0 + k] > 3.0f) E->held[k] = V[N_SHIN0 + k];

    // ---- the supply: a diode and the source's resistance into 100 µF, under its load
    {
        float s = E->starve;
        float vs = 9.0f * (0.6f + 0.8f * s);
        float lack = fmaxf(0, 0.5f - s) / 0.5f;
        float rs = 3.0f + 200.0f * lack * lack;
        float isup = fmaxf(0, vs - 0.6f - vcc) / rs;
        E->vcc = clampf(vcc + dt * (isup - Iload) / C_SUPPLY, 0.5f, 16.0f);
    }

    *outL = V[N_OUTL] - 4.2f;
    *outR = V[N_OUTR] - 4.2f;
}

// ---------------------------------------------------------------- the filters
static inline float dub_step(FrEngine *E, int c, float in, float vMinus, float vPlus) {
    const float dt = E->dt, C = 1e-9f, vt = 0.0258f, rail = 3.3f;
    // the bias: an exponential PNP off FREQ (220K / 4.7K onto a follower), steered by the pair (CV through 220K / 4.7K)
    float x = E->dubF[c] * 0.82f;
    float i5 = 8e-6f * expf(7.3f * x);
    float vb3 = 4.5f + (vMinus - 4.5f) * 0.0209f, vb7 = 4.5f + (vPlus - 4.5f) * 0.0209f;
    float iq3 = i5 * sigm((vb7 - vb3) / vt);
    const float imax = 0.74e-3f;
    iq3 = 1.0f / sqrtf(1.0f / (iq3 * iq3 + 1e-30f) + 1.0f / (imax * imax));
    float iabc = 0.5f * iq3;
    // the resonance: the pot's share of the band-pass (100K pot, 100K to the band-pass)
    // (at the end of its travel the pot leaves nothing: the op-amps' own phase makes it ring — here a hair below zero)
    float r = 0.5f * (1.0f - E->dubR[c]) - 0.012f;
    // a little noise, as any real input has (it starts the ringing)
    E->rnd = E->rnd * 1664525u + 1013904223u;
    float nz = ((float)(E->rnd >> 9) / 8388608.0f - 0.5f) * 2e-4f;
    float hp = -(in + nz + E->lp[c]) + 4.0f * r * E->bp[c];
    hp = rail * tanhf(hp / rail);
    float i1 = iabc * tanhf(0.0099f * hp / (2 * vt));
    E->bp[c] = clampf(E->bp[c] - i1 * dt / C, -rail, rail);
    float i2 = iabc * tanhf(0.0099f * E->bp[c] / (2 * vt));
    E->lp[c] = clampf(E->lp[c] - i2 * dt / C, -rail, rail);
    return E->bp[c];
}

// ---------------------------------------------------------------- render
void fr_render(FrEngine *E, float *left, float *right, int n) {
    if (atomic_load(&E->resetReq)) { do_reset(E); atomic_store(&E->resetReq, 0); }
    if (atomic_load(&E->hasPend)) { take_links(E); atomic_store(&E->hasPend, 0); }
    const float humInc = 50.0f / E->fs;
    const float dcK = 1.0f - expf(-2.0f * (float)M_PI * 4.0f / E->fs);
    const float inK = 1.0f - expf(-2.0f * (float)M_PI * 3.4f / E->fs);
    const float lvl = E->level;
    const int dub = E->dubOn;
    const float dk1 = 1.0f - expf(-2.0f * (float)M_PI * 1800.0f / E->host);
    const float dk2 = 1.0f - expf(-2.0f * (float)M_PI * 6000.0f / E->host);
    const float cAtk = 1.0f - expf(-1.0f / (0.0003f * E->host));
    const float cRel = 1.0f - expf(-1.0f / (0.006f * E->host));
    const float cSlow = 1.0f - expf(-1.0f / (0.04f * E->host));
    for (int s = 0; s < n; s++) {
        for (int k = 0; k < OS; k++) {
            E->humPh += humInc; if (E->humPh >= 1) E->humPh -= 1;
            float humV = (fabsf(E->humPh * 2 - 1) - 0.5f) * 0.6f;
            float l, r;
            step(E, humV, &l, &r);
            // (DC out below a few Hz: the output's coupling)
            E->dcL += (l - E->dcL) * dcK; l -= E->dcL;
            E->dcR += (r - E->dcR) * dcK; r -= E->dcR;
            if (dub) {
                float a = dub_step(E, 0, l, E->V[N_DUB0 + 0], E->V[N_DUB0 + 1]);
                float b = dub_step(E, 1, r, E->V[N_DUB0 + 2], E->V[N_DUB0 + 3]);
                l = a; r = b;
            }
            E->hist[0][E->hpos] = l; E->hist[1][E->hpos] = r;
            E->hpos = (E->hpos + 1) % DEC_TAPS;
        }
        // decimate: the FIR over the last 96 internal samples
        float yl = 0, yr = 0;
        int p = E->hpos;
        for (int t = 0; t < DEC_TAPS; t++) {
            p = (p == 0) ? DEC_TAPS - 1 : p - 1;
            yl += E->taps[t] * E->hist[0][p];
            yr += E->taps[t] * E->hist[1][p];
        }
        yl *= lvl * 0.78f; yr *= lvl * 0.78f;                     // (×2.5 louder than before: tanh below keeps the top round)
        if (E->danger) {
            // the highs lifted hard (two shelves: presence ~1.8 kHz, air ~6 kHz), as the real board's square edges are
            E->dzL += (yl - E->dzL) * dk1; E->dzR += (yr - E->dzR) * dk1;
            E->dz2L += (yl - E->dz2L) * dk2; E->dz2R += (yr - E->dz2R) * dk2;
            yl += 1.6f * (yl - E->dzL) + 1.4f * (yl - E->dz2L);
            yr += 1.6f * (yr - E->dzR) + 1.4f * (yr - E->dz2R);
            // the attack's instant only: where the level jumps above where it has been (a slow follower), it is held
            // down to just over it — the body and the tail pass as they are
            float det = fabsf(yl) > fabsf(yr) ? fabsf(yl) : fabsf(yr);
            E->dEnv += (det - E->dEnv) * (det > E->dEnv ? cAtk : cRel);          // (fast: 0.3 ms in, 6 ms out)
            E->dSlow += (det - E->dSlow) * cSlow;                                  // (slow: 40 ms)
            float ceil = E->dSlow * 1.25f + 0.04f;
            float g = E->dEnv > ceil ? ceil / E->dEnv : 1.0f;
            yl *= g; yr *= g;
        }
        left[s] = tanhf(yl); right[s] = tanhf(yr);
        // held back: a ring, read dlyNow behind (it walks to dlyWant a sample at a time — no click, a slight glide)
        {
            int w = E->dlyPos;
            E->dly[0][w] = left[s]; E->dly[1][w] = right[s];
            if (E->dlyNow < E->dlyWant) E->dlyNow += (s & 1);           // (half speed: a gentle pitch dip)
            else if (E->dlyNow > E->dlyWant) E->dlyNow -= (s & 1);
            if (E->dlyNow > 0) {
                int r = w - E->dlyNow; if (r < 0) r += DLY_MAX;
                left[s] = E->dly[0][r]; right[s] = E->dly[1][r];
            }
            E->dlyPos = (w + 1) % DLY_MAX;
        }
        float pk = fabsf(left[s]) > fabsf(right[s]) ? fabsf(left[s]) : fabsf(right[s]);
        if (pk > E->peak) E->peak = pk;
    }
    (void)inK;
}
