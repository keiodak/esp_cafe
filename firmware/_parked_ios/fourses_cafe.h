// fourses_cafe.h — FOURSES (BLE mode 7) as it was in synths.h (v4.71), parked. Goes back where
// "FOURSES: parked" stands in synths.h; its hooks are in git (the commit that parked it).
// ==========================================
// FOURSES --- mode 7 of the BLE preset (k.odk): Blasser's Fourses as built on crucFX's boards, read from their
// Gerbers: TARPTERGE (Cafe A) or ARPSERGE (Cafe B, "O 9 1"). Four horses (H1 at the bottom .. H4 at the top),
// each: a capacitor charged and discharged by switched current mirrors (4066 A / B), a comparator (LM358 B)
// with 2.2M hysteresis whose + input takes a bound through 4066 D (going up: the next horse's buffer) or C
// (going down: the one below); the floor and the ceiling are fixed dividers. The rates: two differential pairs
// whose tails are exponential current sources on the pot (TARPTERGE: the pot pushes up against down; ARPSERGE:
// both together), the pairs' bases on a 100K ladder.
// The 44 touch nodes are the board's own (the same order as on it, clockwise from the top left), each with its
// real source and source resistance; a touch or a wire ("T <a> <b> <0..1000>") is a resistance between two nodes
// (1000 = a wire, 2K; 0 = off; between: a finger, light ~10M .. firm ~20K), and the node voltages are solved
// with it. Nodes 44 IN (the Cafe's input), 45 EARTH, 46 OUT L (main), 47 OUT R (ASH), 48..52 the fingers (each
// also leaks to the body: the mains' hum). "O <id> <v>": 0..3 the pots · 8 RANGE (0 CV · 500 LOW · 1000 AUDIO)
// (all four; 4..7 each horse's own switch) · 9 the board (0 TARPTERGE · 1 ARPSERGE) · 19 RESET · 20 LINK IN (0..1000 = 0..8.4 V: the other Cafe's LINK OUT).
// And half of crucFX's INTERSEXON on every Cafe (read from its Gerbers too): four sample & holds (4066 + LM324
// followers: 53+k IN · 57+k GATE (100K down: a touch of a gate samples) · 61+k OUT) and four voltage-to-current
// cells (an op-amp forcing a push-pull pair's emitters, 10K between two held values; the collectors are the
// nodes: 65+2j SOURCE (the PNP, △), 66+2j SINK (the NPN, ▽)) — D→A, A→D, B→C, C→B. 73 LINK OUT (reported to the
// phone, "t <0..1000>", which hands it to the other Cafe's LINK IN, 74): slow (the link), but it crosses.
// 75: the other Cafe's EARTH ("O 21 <0..255>", from the phone: slow too). 76: YELLOW (a gate: above 3 V it is high;
// nothing on it: H1's comparator, as before). 77..92: LIGHT 0..15 — each drawn shape's brightness in the phone's
// camera ("O <30+k> <0..1000>" = 0..8.4 V through 10K), joined to what the shape covers: a light-dependent source.
// (Memory: the heap has nothing to spare — the tape takes all of it. So the solver's working space is a piece of
//  the tape (FOURSES does not use it), set up again each time FOURSES starts; the links are kept in RTC memory.)
// ==========================================
static inline float clock_hz();   // (in the sketch)
#define TP_NB 44
#define TP_N 93
#define TP_NL 128
enum { TP_POS, TP_BUF, TP_PULSE, TP_THR, TP_GATE, TP_NGATE, TP_BUP, TP_BLO, TP_LA, TP_LMID, TP_LB };
static const uint8_t tp_role[TP_NB] = { 4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6, 4, 3, 2, 1,
                                        0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6 };
static const uint8_t tp_h[TP_NB] = { 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2,
                                     2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0 };
static const int16_t tp_sig[128] = { 321,333,345,357,370,383,397,411,425,440,456,471,488,505,522,540,558,577,596,616,636,657,679,701,724,747,770,795,820,845,871,898,925,953,982,1011,1040,1070,1101,1132,1164,1196,1229,1263,1296,1331,1366,1401,1437,1473,1509,1546,1583,1621,1658,1697,1735,1773,1812,1851,1890,1929,1969,2008,2048,2087,2126,2166,2205,2244,2283,2322,2360,2398,2437,2474,2512,2549,2586,2622,2658,2694,2729,2764,2799,2832,2866,2899,2931,2963,2994,3025,3055,3084,3113,3142,3170,3197,3224,3250,3275,3300,3325,3348,3371,3394,3416,3438,3459,3479,3499,3518,3537,3555,3573,3590,3607,3624,3639,3655,3670,3684,3698,3712,3725,3738,3750,3762 };   // the pairs: σ(Δ / 26 mV), Q12, Δ = -64 .. 63 mV
// the links as the loop keeps them — a piece of the tape as well (the phone sends them all again whenever FOURSES
// starts, after its "T")
struct TpLinks { uint8_t la[TP_NL], lb[TP_NL]; int16_t lg[TP_NL]; int16_t light[16]; };   // (lg: Q12 per 10K; 0 = no link)
struct TpCl { int16_t cg[2][TP_NL]; uint8_t ca[2][TP_NL], cb[2][TP_NL]; };   // the compact lists the audio reads
static_assert(sizeof(TpLinks) <= DCHUNK_BYTES && sizeof(TpCl) <= DCHUNK_BYTES, "FOURSES: the links must fit tape pieces");
#define TL ((TpLinks *)dchunk[102])
#define TC ((TpCl *)dchunk[103])
#define tp_la (TL->la)
#define tp_lb (TL->lb)
#define tp_lg (TL->lg)
// the working space (a piece of the tape)
struct TpWs2 { int32_t num[TP_N], den[TP_N]; };
struct TpWs {
  int16_t E[TP_N], G[TP_N], V[TP_N];
  uint8_t an[2][TP_N], af[2][TP_N];
  uint8_t ncl[2], nan[2], lad[2][4];
};
static_assert(sizeof(TpWs) <= DCHUNK_BYTES, "FOURSES: the working space must fit a piece of the tape");
static_assert(sizeof(TpWs2) <= DCHUNK_BYTES, "FOURSES: the sums must fit a piece of the tape");
#define TW ((TpWs *)dchunk[100])
#define TW2 ((TpWs2 *)dchunk[101])
volatile int16_t fr_p[10] = { 500, 500, 500, 500, 1000, 1000, 1000, 1000, 1000, 0 };   // 4..7: each horse's range switch
volatile int32_t tp_linkin = 4200;                            // LINK IN (mV)
volatile int32_t tp_supply = 500;                             // STARVE: the supply (500 = its 8.4 V; 0 starved to ~0.3, 1000 ~1.7x)
RTC_DATA_ATTR static int32_t tp_kick = 0;                                   // the rails' bounce as a comparator snaps (mV, decaying fast): the Fourses' crackle
static int32_t tp_kq = 4096;                                  // (the supply now, Q12, sagging under the load)
volatile uint16_t tp_led[4];                                  // the four LEDs: how long each horse's output has been high since the loop last looked
volatile uint16_t tp_ledn = 0;
volatile int32_t tp_earth2 = 0;                               // the other Cafe's EARTH (0..255, as its status line has it)
static const uint8_t tp_vx[4] = { 3, 0, 1, 2 }, tp_vy[4] = { 0, 3, 2, 1 };   // the V→I cells: I = (X - Y) / 10K
volatile int32_t tp_up[4], tp_dn[4];                          // µV a sample at the middle of the pairs
volatile int32_t tp_kc[4] = { 5000, 5000, 5000, 5000 };      // a node's current into each capacitor (Q16)
volatile bool fr_flip = false, fr_reset = true, fr_gate = false;
volatile bool tp_on = false;                                  // (FOURSES is running: its working space is set up)
volatile uint8_t tp_cur = 0;
volatile uint32_t tp_gen = 0;
static int8_t tp_ix[11][4];                                   // (role, horse) -> node
static int tp_node(int role, int h) { for (int i = 0; i < TP_NB; i++) if (tp_role[i] == role && tp_h[i] == h) return i; return 0; }
// the compact list of the links in use, into the buffer the audio is not reading, then switched over
static void tp_rebuild() {
  if (!tp_on || pc_mode != 7) return;                          // (else the tape is someone else's)
  TpWs *w = TW;
  int b = 1 - tp_cur, n = 0, m = 0;
  for (int i = 0; i < TP_N; i++) w->af[b][i] = 0;
  for (int k = 0; k < TP_NL; k++) {
    if (!tp_lg[k]) continue;
    TC->ca[b][n] = tp_la[k]; TC->cb[b][n] = tp_lb[k]; TC->cg[b][n] = tp_lg[k]; n++;
    int q[2] = { tp_la[k], tp_lb[k] };
    for (int j = 0; j < 2; j++) if (!w->af[b][q[j]]) { w->af[b][q[j]] = 1; w->an[b][m++] = (uint8_t)q[j]; }
  }
  for (int h = 0; h < 4; h++) {                                // (a touched ladder: all three of its nodes)
    int q[3] = { tp_ix[TP_LA][h], tp_ix[TP_LMID][h], tp_ix[TP_LB][h] };
    w->lad[b][h] = w->af[b][q[0]] || w->af[b][q[1]] || w->af[b][q[2]];
    if (w->lad[b][h]) for (int j = 0; j < 3; j++) if (!w->af[b][q[j]]) { w->af[b][q[j]] = 1; w->an[b][m++] = (uint8_t)q[j]; }
  }
  w->ncl[b] = (uint8_t)n; w->nan[b] = (uint8_t)m;
  tp_gen++;
  tp_cur = (uint8_t)b;
}
// the tails' currents against the pot (33 steps), at 8.4 V — from SPICE sweeps of the full netlist (the iOS Fourses'):
// the shape of each rate over the pot, as the circuit really bends it (not a pure exponential)
static const float tp_tup[33] = { 2.6013e-05f, 3.0988e-05f, 3.6820e-05f, 4.3621e-05f, 5.1505e-05f, 6.0583e-05f, 7.0956e-05f, 8.2707e-05f, 9.5889e-05f, 1.1052e-04f, 1.2656e-04f, 1.4392e-04f, 1.6246e-04f, 1.8194e-04f, 2.0212e-04f, 2.2266e-04f, 2.4324e-04f, 2.6350e-04f, 2.8313e-04f, 3.0183e-04f, 3.1936e-04f, 3.3557e-04f, 3.5033e-04f, 3.6362e-04f, 3.7545e-04f, 3.8584e-04f, 3.9491e-04f, 4.0275e-04f, 4.0949e-04f, 4.1523e-04f, 4.2013e-04f, 4.2427e-04f, 4.2775e-04f };
static const float tp_tdn[33] = { 2.9523e-04f, 2.6517e-04f, 2.3656e-04f, 2.0928e-04f, 1.8365e-04f, 1.5996e-04f, 1.3836e-04f, 1.1893e-04f, 1.0165e-04f, 8.6445e-05f, 7.3195e-05f, 6.1741e-05f, 5.1907e-05f, 4.3516e-05f, 3.6394e-05f, 3.0375e-05f, 2.5308e-05f, 2.1055e-05f, 1.7496e-05f, 1.4524e-05f, 1.2046e-05f, 9.9826e-06f, 8.2683e-06f, 6.8445e-06f, 5.6637e-06f, 4.6847e-06f, 3.8737e-06f, 3.2027e-06f, 2.6468e-06f, 2.1873e-06f, 1.8085e-06f, 1.4932e-06f, 1.2342e-06f };
static float tp_tail(const float *t, float x) {               // (log-interpolated: the tails are near-exponential)
  if (x < 0) x = 0; if (x > 1) x = 1;
  float fi = x * 32.0f; int i = (int)fi; if (i > 31) i = 31; float fr = fi - i;
  return expf(logf(t[i]) * (1 - fr) + logf(t[i + 1]) * fr);
}
static void fr_update() {                                    // (the loop: floats are fine here)
  static bool once = false;
  if (!once) { once = true; for (int r = 0; r < 11; r++) for (int h = 0; h < 4; h++) tp_ix[r][h] = (int8_t)tp_node(r, h); }
  float hz = clock_hz();
  bool arp = fr_p[9] >= 500;
  for (int h = 0; h < 4; h++) {
    // each horse's range switch — its capacitor: AUDIO · LOW (x30) · CV (x1000)
    float c = fr_p[4 + h] >= 750 ? 1.0f : (fr_p[4 + h] >= 250 ? 30.0f : 1000.0f);
    float base = 150000.0f * 32000.0f / hz / c;                          // µV a sample, pot in the middle, pairs balanced
    tp_kc[h] = (int32_t)(5000.0f * 32000.0f / hz / c);
    float x = fr_p[h] / 1000.0f;
    // the rates over the pot as SPICE has them (each against its own middle, so the middle stays where it was)
    float ku = tp_tail(tp_tup, x) / tp_tup[16], kd = tp_tail(tp_tdn, x) / tp_tdn[16];
    float ka = tp_tail(tp_tdn, 1.0f - x) / tp_tdn[16];                   // (ARPSERGE: one rate, the pot as it is)
    tp_up[h] = (int32_t)fminf(base * (arp ? ka : ku), 3000000.0f);
    tp_dn[h] = (int32_t)fminf(base * (arp ? ka : kd), 3000000.0f);
  }
}
static void tp_link(int a, int b, int v) {                   // (the loop) a touch / a wire between two nodes
  if (pc_mode != 7) return;                                    // (the tape is someone else's)
  if (a > b) { int t = a; a = b; b = t; }
  if (a < 0 || b >= TP_N || a == b) return;
  int32_t g = 0;
  if (v > 0) { float R = 2000.0f * powf(5000.0f, (1000 - v) / 1000.0f); g = (int32_t)(4096.0f * 10000.0f / R); if (g < 1) g = 1; if (g > 20480) g = 20480; }
  int free_ = -1;
  for (int i = 0; i < TP_NL; i++) {
    if (tp_lg[i] && tp_la[i] == a && tp_lb[i] == b) { tp_lg[i] = (int16_t)g; tp_rebuild(); return; }
    if (!tp_lg[i] && free_ < 0) free_ = i;
  }
  if (g && free_ >= 0) { tp_la[free_] = (uint8_t)a; tp_lb[free_] = (uint8_t)b; tp_lg[free_] = (int16_t)g; }
  tp_rebuild();
}
static void tp_clear() { if (pc_mode != 7) return; memset(TL, 0, sizeof(TpLinks)); tp_rebuild(); }
static void tp_enter() { memset(TL, 0, sizeof(TpLinks)); }    // (the loop, as FOURSES is chosen: no links from the tape's old sound)
// the horses' state (the audio)
static int32_t tp_pos[4], tp_out[4], tp_olp[4], tp_bnd[4];
static int32_t tp_sh[4] = { 4200, 4200, 4200, 4200 };         // INTERSEXON: what each sample & hold holds (mV)
static int32_t tp_hum = 0;
// a node's own source (mV) and its conductance to it (Q12 per 10K)
static inline void tp_eg(TpWs *w, int i, int32_t in) {
  int32_t e = 4140, g = 372;
  if (i < TP_NB) {
    int h = tp_h[i];
    switch (tp_role[i]) {
      case TP_POS: e = tp_pos[h] / 1000; g = 0; break;                            // (a capacitor: below)
      case TP_BUF: e = tp_pos[h] / 1000; if (e > 6800) e = 6800; if (e < 50) e = 50; g = 20480; break;   // 358 A (2K)
      case TP_PULSE: e = 4200 + tp_out[h] - tp_olp[h]; g = 4096; break;           // through its capacitor
      case TP_THR: e = tp_bnd[h] + (((tp_out[h] - tp_bnd[h]) * 186) >> 12); g = 390; break;   // bound (110K) · output (2.2M)
      case TP_GATE: e = tp_out[h]; g = 410; break;                                // the output through 100K
      case TP_NGATE: e = tp_out[h] > ((3400 * tp_kq) >> 12) ? 60 : (8300 * tp_kq) >> 12; g = 390; break;            // the inverter through 100K
      case TP_BUP: if (h < 3) { e = tp_pos[h + 1] / 1000; if (e > 6800) e = 6800; g = 410; } else { e = 6200; g = 819; } break;
      case TP_BLO: if (h > 0) { e = tp_pos[h - 1] / 1000; if (e > 6800) e = 6800; g = 410; } else { e = 2000; g = 819; } break;
      case TP_LMID: g = 0; break;                                                 // (only the ladder)
      default: break;                                                             // the ladder's ends: 110K to the bias
    }
  } else if (i == 44) { e = 4200 + in * 2; g = 4096; }                            // IN (10K)
  else if (i == 45) { e = 4200 + pc_emod * 64; g = 2048; }                        // EARTH (20K, a wide swing: heard, not holding the rest)
  else if (i < 48) { e = 4200; g = 410; }                                         // OUT: an amplifier's input
  else if (i < 53) { e = tp_hum; g = 41; }                                        // a finger: the body (1M, the hum)
  else if (i < 57) { e = tp_sh[i - 53]; g = 1; }                                  // S&H IN (floats: reads what it holds)
  else if (i < 61) { e = 0; g = 410; }                                            // S&H GATE (100K down)
  else if (i < 65) { e = tp_sh[i - 61]; if (e > 6900) e = 6900; if (e < 20) e = 20; g = 20480; }   // S&H OUT (LM324)
  else if (i < 73) { e = 4200; g = 0; }                                           // a collector: only a current (below)
  else if (i == 73) { e = 4200; g = 410; }                                        // LINK OUT
  else if (i == 74) { e = tp_linkin; g = 4096; }                                  // LINK IN (10K)
  else if (i == 76) { e = 0; g = 410; }                                           // YELLOW (a pin's input, 100K down)
  else if (i >= 77) { e = TL->light[i - 77]; g = 1241; }                          // LIGHT: a shape's brightness / pull (33K)
  else if (i == 75) { static int32_t avg = 0; avg += ((tp_earth2 << 8) - avg) >> 12;          // the other EARTH (as ours: around its
         e = 4200 + (tp_earth2 - (avg >> 8)) * 64; g = 2048; }                     //  own average)
  w->E[i] = (int16_t)e; w->G[i] = (int16_t)g;
}
static int32_t __attribute__((noinline)) fr_tick(int32_t in, int32_t *rout, bool flip, bool skip) {
  static uint32_t hum = 0, gen = 0xFFFFFFFF;
  static int32_t dcl = 0, dcr = 0;
  static uint8_t ph = 0;
  TpWs *w = TW;
  if (fr_reset) {                                                                 // (FOURSES starts: its working space anew)
    fr_reset = false;
    for (int h = 0; h < 4; h++) { tp_pos[h] = (1500 + h * 1500) * 1000; tp_out[h] = (h & 1) ? 50 : 6800; tp_olp[h] = 3000; tp_bnd[h] = 4200; }
    memset(w, 0, sizeof(TpWs)); memset(TC, 0, sizeof(TpCl));
    tp_on = true;
    tp_rebuild();
    gen = 0xFFFFFFFF;
  }
  hum += 6710886u;                                                                // (50 Hz)
  { int32_t ht = (int32_t)(hum >> 16) - 32768; tp_hum = ((ht < 0 ? -ht : ht) - 16384) / 55; }   // (±300 mV)
  const int c = tp_cur;
  const int nl = w->ncl[c], na = w->nan[c];
  const uint8_t *la = TC->ca[c], *lb = TC->cb[c], *an = w->an[c], *af = w->af[c];
  const int16_t *lg = TC->cg[c];
  int16_t *V = w->V;
  const bool fresh = gen != tp_gen; gen = tp_gen;
  const bool solve = fresh || ((++ph & 3) == 0);                                  // (the network: every 4th sample, 8 kHz — 16 kHz starved the ISR)
  if (solve && na) {
    const uint8_t *was = w->af[1 - c];                                            // (a new wire: only the nodes new to the network start
    for (int j = 0; j < na; j++) { int i = an[j]; tp_eg(w, i, in); if (fresh && !was[i]) V[i] = w->E[i]; }   //  anew; the rest keep their voltage)
    int32_t *num = TW2->num, *den = TW2->den;
    for (int j = 0; j < na; j++) { int i = an[j]; num[i] = w->E[i] * w->G[i]; den[i] = w->G[i]; }
    for (int h = 0; h < 4; h++) {                                                 // the ladders (100K, 100K)
      if (!w->lad[c][h]) continue;
      int a = tp_ix[TP_LA][h], m = tp_ix[TP_LMID][h], b = tp_ix[TP_LB][h];
      num[a] += 410 * V[m]; den[a] += 410; num[m] += 410 * (V[a] + V[b]); den[m] += 820; num[b] += 410 * V[m]; den[b] += 410;
    }
    for (int k = 0; k < nl; k++) {
      int a = la[k], b = lb[k]; int32_t g = lg[k];
      num[a] += g * V[b]; den[a] += g; num[b] += g * V[a]; den[b] += g;
    }
    for (int j = 0; j < 4; j++) {                                                 // INTERSEXON: the collectors' currents
      int so = 65 + 2 * j, si = so + 1;
      if (!af[so] && !af[si]) continue;
      int32_t x = tp_sh[tp_vx[j]], y = tp_sh[tp_vy[j]];                          // (the followers: the held values)
      if (af[si] && x > y) num[si] -= (x - y) * 4096;                           // the NPN sinks (X above Y)
      if (af[so] && y > x) num[so] += (y - x) * 4096;                           // the PNP sources (X below Y)
    }
    for (int j = 0; j < na; j++) {
      int i = an[j];
      if (i < TP_NB && tp_role[i] == TP_POS) { V[i] = w->E[i]; continue; }       // (the capacitor holds)
      if (den[i] > 0) { int32_t v = num[i] / den[i]; if (v > 9500) v = 9500; if (v < -1000) v = -1000; V[i] = (int16_t)v; }   // (the rails)
    }
  }
  // what the touches and wires pull out of the capacitors
  int32_t cur[4] = { 0, 0, 0, 0 };
  for (int k = 0; k < nl; k++) {
    int a = la[k], b = lb[k];
    if (a < TP_NB && tp_role[a] == TP_POS) cur[tp_h[a]] += lg[k] * (V[b] - tp_pos[tp_h[a]] / 1000) / 64;
    if (b < TP_NB && tp_role[b] == TP_POS) cur[tp_h[b]] += lg[k] * (V[a] - tp_pos[tp_h[b]] / 1000) / 64;
  }
  // STARVE: the supply, and how it sags as the horses' outputs go high (a starved supply droops under its load)
  {
    int32_t k = 1229 + tp_supply * 5734 / 1000;                                   // (0.3 … 1 … 1.7)
    int nh = 0; for (int h = 0; h < 4; h++) nh += tp_out[h] > 1000;
    if (k < 4096) k -= ((4096 - k) * nh * 260) >> 12;
    if (k < 250) k = 250;
    tp_kq = k;
  }
  const int32_t kq = tp_kq;
  if (tp_ledn < 65000) tp_ledn++;
  const int32_t vh = (6800 * kq) >> 12, vt = (4200 * kq) >> 12, vn = (3400 * kq) >> 12;
  int32_t rf = ((8400 * kq) >> 12) - 700; if (rf < 0) rf = 0; rf = rf * 4096 / 7700;   // (the mirrors: the supply less a Vbe)
  for (int h = 0; h < 4; h++) {
    int32_t pv = tp_pos[h] / 1000;
    int ni;
    ni = tp_ix[TP_THR][h];                                                        // the comparator: + THR, - the capacitor
    int32_t thr = af[ni] ? V[ni] : tp_bnd[h] + (((tp_out[h] - tp_bnd[h]) * 186) >> 12);
    int32_t o = thr > pv ? vh : 50;
    if (o > 1000) { o -= (o * 3) >> 7; if (tp_led[h] < 65000) tp_led[h]++; }         // (its LED: lit, and drawing on the output)
    if ((o > 1000) != (tp_out[h] > 1000)) tp_kick += (o > 1000 ? 1400 : -1400) * 4096 / (kq < 1024 ? 1024 : kq);   // (an edge: the rails jump)
    tp_out[h] = o;
    tp_olp[h] += (o - tp_olp[h]) >> 7;
    ni = tp_ix[TP_GATE][h]; bool ad = (af[ni] ? V[ni] : o) > vt;                // the 4066's controls (its thresholds with its supply)
    ni = tp_ix[TP_NGATE][h]; bool bc = af[ni] ? V[ni] > vt : o < vn;
    int32_t bu, bl;
    ni = tp_ix[TP_BUP][h];
    if (af[ni]) bu = V[ni]; else if (h < 3) { bu = tp_pos[h + 1] / 1000; if (bu > vh) bu = vh; } else bu = (6200 * kq) >> 12;
    ni = tp_ix[TP_BLO][h];
    if (af[ni]) bl = V[ni]; else if (h > 0) { bl = tp_pos[h - 1] / 1000; if (bl > vh) bl = vh; } else bl = (2000 * kq) >> 12;
    tp_bnd[h] = (ad && bc) ? (bu + bl) >> 1 : (ad ? bu : (bc ? bl : o));          // (none: only the hysteresis)
    int32_t fu = 2048;                                                            // the rates: the ladder onto the pairs
    if (w->lad[c][h]) {
      int32_t d = ((V[tp_ix[TP_LA][h]] - V[tp_ix[TP_LB][h]]) * 372) >> 12;        // (×10/110)
      int ix = d + 64; if (ix < 0) ix = 0; if (ix > 127) ix = 127;
      fu = tp_sig[ix];
    }
    int32_t dp = 0;
    // the mirrors as they are: an Early slope (more current the further the capacitor is from the rail it feeds
    // from) and their headroom running out near each rail (iOS Fourses) — Q12
    const int32_t vs = (8400 * kq) >> 12;
    int32_t eu = 4096 + (((4200 - pv) * 189) >> 10), ed = 4096 + (((pv - 4200) * 54) >> 10);
    int32_t hu = vs - 150 - pv, hd = pv - 100;
    if (hu < 512) eu = hu <= 0 ? 0 : (eu * hu) >> 9;                 // (32-bit only: no 64-bit division in the ISR —
    if (hd < 512) ed = hd <= 0 ? 0 : (ed * hd) >> 9;                 //  its library call lives in flash; over the last 0.5 V)
    if (ad) dp += (int32_t)(((((int64_t)tp_up[h] * fu) >> 11) * eu) >> 12);
    if (bc) dp -= (int32_t)(((((int64_t)tp_dn[h] * (4096 - fu)) >> 11) * ed) >> 12);
    if (cur[h]) dp += (int32_t)(((int64_t)cur[h] * tp_kc[h]) >> 10);
    if (rf != 4096) dp = (int32_t)(((int64_t)dp * rf) >> 12);
    int32_t np = tp_pos[h] + dp;
    if (np > 8300000) np = 8300000; if (np < 0) np = 0;                           // (the mirrors run out)
    tp_pos[h] = np;
  }
  // INTERSEXON: a gate above ~3 V samples (its own regulated supply: a lower threshold than the Fourses) (the 4066 on: the capacitor follows its IN)
  for (int k = 0; k < 4; k++) if (af[57 + k] && V[57 + k] > 3000) tp_sh[k] = af[53 + k] ? V[53 + k] : tp_sh[k];
  fr_gate = af[76] ? V[76] > 3000 : tp_out[0] > 1000;                            // YELLOW (and the lamp)
  int32_t l = af[46] ? V[46] - 4200 : 0, r = af[47] ? V[47] - 4200 : 0;         // out: what OUT L / R are wired to
  if (tp_kick) {                                                                  // (the edges' crackle rides the outputs, as on the board's shared rails)
    if (af[46]) l += tp_kick / 3;
    if (af[47]) r += tp_kick / 3;
    tp_kick -= tp_kick / 6 + (tp_kick > 0 ? 1 : -1);
  }
  l = l * 2047 / 1800; r = r * 2047 / 1800;                                      // (louder: ±1.8 V is full scale)
  dcl += ((l << 8) - dcl) >> 14; l -= dcl >> 8;                                  // (DC out below ~0.3 Hz: CV and LOW pass)
  dcr += ((r << 8) - dcr) >> 14; r -= dcr >> 8;
  if (l > 2047) l = 2047; if (l < -2047) l = -2047;
  if (r > 2047) r = 2047; if (r < -2047) r = -2047;
  *rout = r;
  return l;
}

// --- its commands, from pc_line (esp_cafe_duo.ino) ---
/*
    case 'O': { long id = -1, val = 0; sscanf(s + 1, "%ld %ld", &id, &val);   // FOURSES: "O <id> <0..1000>"
                if (val < 0) val = 0; if (val > 1000) val = 1000;
                if (id >= 0 && id < 10) { fr_p[id] = (int16_t)val; if (id == 8) for (int h = 0; h < 4; h++) fr_p[4 + h] = (int16_t)val; fr_update(); }
                else if (id == 20) tp_linkin = val * 84 / 10;                              // LINK IN: the other Cafe's LINK OUT
                else if (id == 21) tp_earth2 = val > 255 ? 255 : val;                      // the other Cafe's EARTH
                else if (id == 22) tp_supply = val;                                        // STARVE: the supply
                else if (id >= 30 && id < 46 && pc_mode == 7) TL->light[id - 30] = (int16_t)(val * 84 / 10);   // LIGHT: a shape's brightness
                else if (id == 19) fr_reset = true;
              } break;
    case 'T': { long a = -1, b2 = -1, v = 0; if (sscanf(s + 1, "%ld %ld %ld", &a, &b2, &v) == 3) {   // FOURSES: a touch / a wire
                  if (v < 0) v = 0; if (v > 1000) v = 1000; tp_link((int)a, (int)b2, (int)v); }
                else if (a == -1) tp_clear();                                           // "T": every link off
              } break;
*/

// --- its LINK OUT (esp_cafe_duo.ino, called from loop()) ---
// FOURSES: LINK OUT to the phone (for the other Cafe's LINK IN), ~30x a second while it is joined to anything
void tp_service() {
  static uint32_t t = 0; static int last = -1;
  if (pc_mode != 7 || !tp_on || !ble_conn || millis() - t < 33) return;
  t = millis();
  {                                                   // the four LEDs: each horse's time lit, 0…15, when it changes
    static int lastl = -1;
    uint32_t n = tp_ledn; if (!n) n = 1;
    int l = 0;
    for (int h = 0; h < 4; h++) { int b = (int)((uint32_t)tp_led[h] * 15 / n); if (b > 15) b = 15; l |= b << (4 * h); tp_led[h] = 0; }
    tp_ledn = 0;
    if (l != lastl) { lastl = l; char b[16]; snprintf(b, sizeof(b), "f %d", l); pc_out(b); }
  }
  if (!TW->af[tp_cur][73]) return;
  int v = TW->V[73] * 10 / 84; if (v < 0) v = 0; if (v > 1000) v = 1000;
  if (abs(v - last) < 3) return;
  last = v;
  char b[16]; snprintf(b, sizeof(b), "t %d", v); pc_out(b);
}
