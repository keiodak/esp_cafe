// 2^x without tables or floats (was NOBSRINE's)
static inline uint32_t nb_exp2(uint32_t base, int32_t x) {
  int32_t o = x >> 12;
  uint64_t t = (uint64_t)(x & 4095) << 4;
  uint64_t m = 65536 + ((t * (43025 + ((22512 * t) >> 16))) >> 16);
  uint64_t v = ((uint64_t)base * m) >> 16;
  if (o > 0) v <<= (o > 12 ? 12 : o); else if (o < 0) v >>= (-o > 30 ? 30 : -o);
  return v > 0xFFFFFFFFull ? 0xFFFFFFFFu : (uint32_t)v;
}

// ==== STUBER (BLE mode 8): after Blasser's Din Datin Dudero Stuber, as its Surfing Guide lays it out. Four identical
// state-variable filters (12 dB, resonant, soft rails): B and D the audio (the Cafe's IN; B → OUT, D → ASH), A and C the
// gesture (A the right wheel's movement, C the left's: a slow resonant "heartbeat" that ripples the other channel).
// The big wheels are the pitch (cutoff), the small knobs the Q; past ~75 % the audio filters sing on their own.
// Its 63 sandrodes keep their numbers (1…63): each filter's LowPass / BandPass / Resonance, its cutoff and resonance
// modulation (verso / inverso), the dividers (16 stages a side: left from D, right from B), the parasites; [0] RESET;
// 64 / 65 the Sh'mance clocks [A] / [B]; 66 IN, 67 EARTH (the Cafe's own). A modulation node carries what the Sh'mance
// routes to it (a wheel, a knob, a ripple — or nothing) and what flows in through its patches; a patch between two
// nodes is a current by the difference of their potentials. The Sh'mance: 16 of those routes, a bit each, from two
// 8-bit registers clocked at [A] / [B] (the data: its wheel, past the middle, against the last bit, as a Rungler);
// 2^16 states; [0] (or the RESET key) the base.
// "A <id> <0..1000>": 0 / 1 the wheels (L / R) · 2 / 3 the Q knobs (L / R) · 19 RESET · 20 a random state.
#define ST_N 68
volatile int16_t st_p[4] = { 400, 600, 150, 850 };
volatile bool st_reset = true, st_base = false, st_on = false, st_gate = false;
volatile bool st_rand = false;
struct StState {                                              // (in a piece of the tape: no RAM of its own)
  int32_t V[ST_N], I[ST_N];
  int32_t lp[4], bp[4];
  int32_t wh[2], rs[2], lem;
  uint32_t cnt[2], rng;
  uint8_t hy[2], reg[2], ck[2], rk;
  int32_t par[2];
  uint32_t sub;
  uint8_t nl[2], cur;
};
static_assert(sizeof(StState) <= DCHUNK_BYTES, "STUBER: its state must fit a piece of the tape");
#define ST ((StState *)dchunk[100])
// the modulation nodes: node · filter (0 B, 1 D, 2 A, 3 C) · 0 cutoff / 1 resonance · +1 verso / -1 inverso · the base
// source · the other (0 none, 1 left wheel, 2 right wheel, 3 left knob, 4 right knob, 5 A's ripple, 6 C's) · Sh'mance bit
// (section × 8 + bit; -1 fixed)
struct StMod { uint8_t node, f, res; int8_t sign; uint8_t base, alt; int8_t bit; };
static const StMod st_mods[17] = {
  { 11, 0, 0,  1, 1, 2,  0 }, { 24, 0, 0, -1, 5, 6,  1 }, { 42, 0, 0, -1, 0, 5,  2 }, { 39, 0, 1, -1, 3, 4,  3 },
  {  5, 2, 0,  1, 1, 2,  4 }, { 27, 2, 0, -1, 0, 1,  5 }, { 41, 2, 1,  1, 3, 4,  6 }, { 25, 2, 1, -1, 0, 3,  7 },
  { 22, 1, 0,  1, 2, 1,  8 }, { 38, 1, 1,  1, 4, 3,  9 }, { 28, 1, 1, -1, 0, 6, 10 }, { 49, 3, 0,  1, 2, 1, 11 },
  { 30, 3, 0, -1, 0, 2, 12 }, { 32, 3, 1,  1, 0, 4, 13 }, { 14, 3, 1, -1, 4, 3, 14 }, { 31, 0, 1,  1, 0, 5, 15 },
  { 19, 1, 0, -1, 6, 6, -1 },
};
static const uint8_t st_lp[4] = { 40, 35, 7, 34 }, st_bp[4] = { 4, 45, 3, 12 }, st_rs[4] = { 21, 44, 1, 20 };
static const uint8_t st_div[2][16] = {                        // fastest (÷2) first
  { 26, 36, 16, 6, 8, 10, 2, 48, 52, 56, 60, 58, 62, 46, 50, 54 },     // left, from D
  { 23, 9, 43, 17, 33, 15, 13, 53, 57, 61, 63, 55, 59, 47, 51, 37 } }; // right, from B
static void st_rebuild() {                                    // (the loop) the patches, compact, into the buffer the audio is not reading
  if (!st_on || pc_mode != 8) return;
  StState *s = ST;
  int b = 1 - s->cur, n = 0;
  for (int k = 0; k < TP_NL; k++) {
    if (!tp_lg[k] || tp_la[k] >= ST_N || tp_lb[k] >= ST_N) continue;
    TC->ca[b][n] = tp_la[k]; TC->cb[b][n] = tp_lb[k]; TC->cg[b][n] = tp_lg[k]; n++;
  }
  s->nl[b] = (uint8_t)n;
  s->cur = (uint8_t)b;
}
static inline int32_t st_sat(int32_t x) {                     // the op-amps' rails, soft
  if (x > 24000) { x = 24000 + ((x - 24000) >> 2); if (x > 32000) x = 32000; }
  else if (x < -24000) { x = -24000 + ((x + 24000) >> 2); if (x < -32000) x = -32000; }
  return x;
}
static inline void st_svf(int32_t *lp, int32_t *bp, int32_t x, int32_t f, int32_t q) {   // Chamberlin: f Q15, q Q14 (damping)
  *lp = st_sat(*lp + ((f * *bp) >> 15));
  int32_t hp = x - *lp - ((q * *bp) >> 14);
  if (hp > 90000) hp = 90000;
  if (hp < -90000) hp = -90000;
  *bp = st_sat(*bp + ((f * hp) >> 15));
}
static inline uint32_t st_rnd(StState *s) { s->rng = s->rng * 1664525u + 1013904223u; return s->rng; }
static int32_t __attribute__((noinline)) st_tick(int32_t in, int32_t *rout) {
  StState *s = ST;
  if (st_reset) {
    st_reset = false;
    uint32_t seed = s->rng ^ (uint32_t)esp_timer_get_time();
    memset(s, 0, sizeof(StState));                                            // (the base routing; no patches until rebuilt)
    s->rng = seed | 1;
    for (int h = 0; h < 2; h++) { s->wh[h] = st_p[h] * 65; s->rs[h] = st_p[2 + h] * 65; }
    s->lem = pc_emod;
    st_on = true;
    st_rebuild();
  }
  if (st_base) { st_base = false; s->reg[0] = s->reg[1] = 0; }
  if (st_rand) { st_rand = false; s->reg[0] = (uint8_t)st_rnd(s); s->reg[1] = (uint8_t)(st_rnd(s) >> 8); }
  int32_t *V = s->V, *I = s->I;
  // the patches: a current between each two joined nodes, as their potentials differ
  for (int i = 0; i < ST_N; i++) I[i] = 0;
  const int c = s->cur, nl = s->nl[c];
  const uint8_t *la = TC->ca[c], *lb = TC->cb[c]; const int16_t *lg = TC->cg[c];
  for (int k = 0; k < nl; k++) {
    int a = la[k], b = lb[k];
    if (a >= ST_N || b >= ST_N) continue;
    int32_t d = (int32_t)(((int64_t)(V[b] - V[a]) * lg[k]) >> 12);
    I[a] += d; I[b] -= d;
  }
  // the wheels and knobs (the phone's steps smoothed), mido-centred
  for (int h = 0; h < 2; h++) { s->wh[h] += (st_p[h] * 65 - s->wh[h]) / 256; s->rs[h] += (st_p[2 + h] * 65 - s->rs[h]) / 256; }
  // [0] touched: the base state
  bool rk = I[0] > 3000 || I[0] < -3000;
  if (rk && !s->rk) s->reg[0] = s->reg[1] = 0;
  s->rk = rk;
  // the Sh'mance: a rising current at [A] (64) / [B] (65) steps its register; the data: its wheel past the middle,
  // against the last bit
  for (int h = 0; h < 2; h++) {
    bool hi = I[64 + h] > 3000 || (s->ck[h] && I[64 + h] > 1000);
    if (hi && !s->ck[h]) {
      uint8_t bit = (uint8_t)((s->wh[h] > 32500) ^ (s->reg[h] >> 7));
      s->reg[h] = (uint8_t)((s->reg[h] << 1) | bit);
    }
    s->ck[h] = hi;
  }
  // the modulation nodes: what the Sh'mance routes there, and what flows in; summed into each filter's cutoff / Q
  int32_t src[7] = { 0, s->wh[0] - 32500, s->wh[1] - 32500, s->rs[0] - 32500, s->rs[1] - 32500, V[1] * 3, V[20] * 3 };
  int32_t cut[4] = { 0, 0, 0, 0 }, res[4] = { 0, 0, 0, 0 };
  for (int k = 0; k < 17; k++) {
    const StMod &m = st_mods[k];
    bool alt = m.bit >= 0 && ((s->reg[m.bit >> 3] >> (m.bit & 7)) & 1);
    int32_t v = src[alt ? m.alt : m.base];
    V[m.node] = v;                                                              // (a patch from here carries it away)
    v += I[m.node];
    if (m.res) res[m.f] += m.sign * v; else cut[m.f] += m.sign * v;
  }
  // the gesture filters, A (the right wheel's movement) and C (the left's), at 1 kHz
  const bool sub = (++s->sub & 31) == 0;
  if (sub) {
    for (int h = 0; h < 2; h++) {
      int f = 2 + h;
      int32_t x = (s->wh[1 - h] - 32500) / 2 + I[st_lp[f]] / 4;               // the wheel's position (and what is patched in)
      int32_t oct = cut[f] / 4; if (oct > 16384) oct = 16384; if (oct < -16384) oct = -16384;
      int32_t fq = (int32_t)nb_exp2(620, oct); if (fq > 12000) fq = 12000;     // (~3 Hz; ±4 octaves)
      int32_t q = 8000 - (int32_t)(((int64_t)res[f] * 6000) >> 15); if (q < 1500) q = 1500; if (q > 30000) q = 30000;
      s->bp[f] += I[st_bp[f]] / 8 + I[st_rs[f]] / 8;
      st_svf(&s->lp[f], &s->bp[f], x, fq, q);
      V[st_lp[f]] = s->lp[f]; V[st_bp[f]] = s->bp[f];
      V[st_rs[f]] = s->bp[f] / 3;                                               // the ripple (±1 V)
    }
  }
  // the audio filters, B (left) and D (right), twice a sample
  int32_t o[2];
  for (int h = 0; h < 2; h++) {
    int32_t oct = 16384 + cut[h] / 2;                                           // (the wheel: ±4 octaves round ~480 Hz)
    if (oct < 0) oct = 0; if (oct > 36000) oct = 36000;
    int32_t fq = (int32_t)nb_exp2(97, oct); if (fq > 20000) fq = 20000;
    int32_t q = 7333 - (int32_t)(((int64_t)res[h] * 14667) >> 15);             // (the Q: sings past ~75 %)
    if (q < -3000) q = -3000; if (q > 30000) q = 30000;
    int32_t x = in * 12 + (int32_t)((st_rnd(s) >> 22) & 255) - 128 + s->par[h] / 64;   // the input (and a breath of the parasites)
    s->lp[h] += I[st_lp[h]] / 32; s->bp[h] += I[st_bp[h]] / 32 + I[st_rs[h]] / 16;
    st_svf(&s->lp[h], &s->bp[h], x, fq, q);
    st_svf(&s->lp[h], &s->bp[h], x, fq, q);
    V[st_lp[h]] = s->lp[h]; V[st_bp[h]] = s->bp[h]; V[st_rs[h]] = 0;
    o[h] = s->lp[h] >> 4;
  }
  // the dividers: 16 flip-flops a side, left from D, right from B
  for (int h = 0; h < 2; h++) {
    int32_t v = h ? s->lp[0] : s->lp[1];
    if (!s->hy[h] && v > 1500) { s->hy[h] = 1; s->cnt[h]++; } else if (s->hy[h] && v < -1500) s->hy[h] = 0;
    uint32_t n = s->cnt[h];
    for (int k = 0; k < 16; k++) V[st_div[h][k]] = ((n >> k) & 1) ? 20000 : -20000;
  }
  // the parasites ([29] left, [18] right): a crackling ember
  for (int h = 0; h < 2; h++) {
    uint32_t z = st_rnd(s);
    if ((z >> 23) == 0) s->par[h] += (int32_t)((z >> 7) & 32767) - 16384;
    s->par[h] -= s->par[h] / 48;
    V[h ? 18 : 29] = s->par[h];
  }
  V[66] = in * 12;                                                              // IN
  V[67] = pc_emod * 200;                                                        // EARTH
  st_gate = s->ck[0] || s->ck[1] || (s->cnt[1] & 2048);
  int32_t l = o[0], rr = o[1];
  if (l > 2047) l = 2047;
  if (l < -2047) l = -2047;
  if (rr > 2047) rr = 2047;
  if (rr < -2047) rr = -2047;
  *rout = rr;
  return l;
}

