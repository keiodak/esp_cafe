// ==== NOBSRINE (BLE mode 8): after Blasser's paper circuit (crucFX's PCB read from its Gerbers). Two knobs; each one's
// buffer goes through a capacitor into a Schmitt comparator, and each flip (a turn beginning, either way) samples the knob
// into a hold that sets its triangle's pitch. How fast the knob turns, rectified, is the level — the tail current of the
// differential pair the triangle goes through: it sounds only while it turns, as loud as it turns, no strike, no hold on.
// L (OUT) = knob A, R (ASH) = knob B. "E <id> <0..1000>":
//   0 KNOB A · 1 KNOB B · 3 DECAY (20 ms … 2 s) · 4 PITCH (30 … 960 Hz) · 5 SPREAD (0 … 6 oct) · 7 MIX ·
//   8 SWITCH A · 9 SWITCH B (LO / HI: two octaves up)
#define nb_p fr_p                                             // (FOURSES' settings: the two modes never run together)
volatile bool nb_reset = true, nb_gate = false;
struct NbState {
  int32_t kn[2], kp[2], dv[2], e[2], es[2], s1[2], s2[2], pv[2][2], lem[2];
  uint32_t ph[2][2], inc[2][2];
  uint32_t sub, inc0;
  int32_t dk, spread;
  uint8_t st[2];
};
static_assert(sizeof(NbState) <= DCHUNK_BYTES, "NOBSRINE: its state must fit a piece of the tape");
#define NB ((NbState *)dchunk[100])
static inline uint32_t nb_exp2(uint32_t base, int32_t x) {
  int32_t o = x >> 12;
  uint64_t t = (uint64_t)(x & 4095) << 4;
  uint64_t m = 65536 + ((t * (43025 + ((22512 * t) >> 16))) >> 16);
  uint64_t v = ((uint64_t)base * m) >> 16;
  if (o > 0) v <<= (o > 12 ? 12 : o); else if (o < 0) v >>= (-o > 30 ? 30 : -o);
  return v > 0xFFFFFFFFull ? 0xFFFFFFFFu : (uint32_t)v;
}
static void nb_settings(NbState *n) {
  n->dk = (int32_t)nb_exp2(26214, -(nb_p[3] * 27213 / 1000)); if (n->dk < 1) n->dk = 1;
  n->inc0 = nb_exp2(4026532, nb_p[4] * 20480 / 1000);
  n->spread = nb_p[5] * 24576 / 1000;
}
static inline int32_t nb_sat(int32_t x) {
  if (x >= 32768) return 21845;
  if (x <= -32768) return -21845;
  return x - ((((x * x) >> 15) * x) >> 15) / 3;
}
static int32_t __attribute__((noinline)) nb_tick(int32_t *rout) {
  NbState *n = NB;
  if (nb_reset) {
    nb_reset = false;
    memset(n, 0, sizeof(NbState));
    for (int h = 0; h < 2; h++) {
      n->kn[h] = n->kp[h] = (nb_p[h] * 65) << 8;
      n->s1[h] = n->s2[h] = n->pv[h][0] = n->pv[h][1] = nb_p[h] * 65;
      n->lem[h] = pc_emod;
    }
    nb_settings(n);
  }
  const bool sub = (++n->sub & 15) == 0;
  if (sub) nb_settings(n);
  int32_t o[2];
  for (int h = 0; h < 2; h++) {
    n->kn[h] += (((nb_p[h] * 65) << 8) - n->kn[h]) / 1024;                      // the knob (Q24; the phone's steps smoothed)
    int32_t v = n->kn[h] - n->kp[h]; n->kp[h] = n->kn[h];                       // its turning...
    n->dv[h] = (n->dv[h] * 511) / 512 + (v * 16) / 512;                         // ...through the capacitor
    int32_t dv = n->dv[h];
    if (!n->st[h] && dv > 2400) { n->st[h] = 1; n->s1[h] = n->kn[h] >> 8; }      // a turn begins: the hold takes the knob
    else if (n->st[h] && dv < -2400) { n->st[h] = 0; n->s1[h] = n->kn[h] >> 8; }
    int32_t a = dv < 0 ? -dv : dv;                                             // as loud as it turns, no more
    int32_t t = a > 8191 ? 65535 : a * 8;
    int32_t e = n->es[h];
    e += t > e ? (t - e) / 64 : -(((e >> 4) * (n->dk >> 4)) >> 16) - 1;          // (up in ~2 ms, down as DECAY says)
    n->es[h] = e < 0 ? 0 : e;
    n->pv[h][0] += (n->s1[h] - n->pv[h][0]) / 64;                               // the hold, through its buffer
    if (sub) {
      uint32_t i = nb_exp2(n->inc0, (int32_t)(((int64_t)n->spread * (n->pv[h][0] - 32768)) >> 16) + (nb_p[8 + h] >= 500 ? 8192 : 0));
      n->inc[h][0] = i > 900000000u ? 900000000u : i;
    }
    int32_t p = (int32_t)(n->ph[h][0] >> 16);
    int32_t w = p < 32768 ? p * 2 - 32768 : (65535 - p) * 2 - 32768;           // one triangle, plain
    n->ph[h][0] += n->inc[h][0];
    o[h] = (int32_t)(((int64_t)w * n->es[h]) >> 20);                            // (±2047 at full)
  }
  nb_gate = n->es[0] > 6000 || n->es[1] > 6000;
  int32_t l = o[0] + (((o[1] - o[0]) * nb_p[7]) / 2000), r = o[1] + (((o[0] - o[1]) * nb_p[7]) / 2000);
  if (l > 2047) l = 2047;
  if (l < -2047) l = -2047;
  if (r > 2047) r = 2047;
  if (r < -2047) r = -2047;
  *rout = r;
  return l;
}

