// shnth_glue.h — SHNTH (BLE mode 8, beside FOURSES) on the Cafe (k.odk)
// The Shbobo Shnth's sound engine (shnth_cafe.c: a C port of Peter Blasser's firmware, MIT, bit-exact) plays patches
// the phone compiles and sends ("A" lines). It runs in loop() — its nested expressions want more stack than an
// interrupt has — into a ring; the audio interrupt plays the ring back by real time (CPU cycles), so the patch's own
// sample rate (17.6 kHz, or what its `srate` asks) is kept whatever the Cafe's clock / SPEED knob does.
// Memory: all borrowed from the tape while SHNTH runs (19 of its 1536-byte pieces): the 16 KB delay (11), the engine
// (1), the patch (1), the ring (4 + 2 for the periods). Leaving SHNTH gives them back to the tape as they are.
//
// phone -> Cafe:
//   A <offset> <hex bytes>              a piece of the patch image (offset 0 first: the engine stops until AL)
//   AL <length> <preset> <channel>      the image is complete: load it, pick the preset, play
//                                       (channel 0 = left + right · 1 = left · 2 = right — two Cafes: L and R)
//   a <bar0> <bar1> <bar2> <bar3> <corp0> <corp1> <buttons>   the controls, raw as the Shnth reads them
//                                       (bars ±1040 = full, 0 at rest · antennae 0…512 · buttons: SHNTH_BTN_* bits)

extern "C" {
#include "shnth_engine.h"
extern int16_t *sh_dl[11];
}

#define SH_RING 1536                                   // frames (4 pieces of 384 · 4 bytes)
static shnth_engine *sh_e = nullptr;
static uint8_t *sh_img = nullptr;
static uint32_t *sh_ring[4];                           // l (12 bits) | r (12 bits) << 12
static uint16_t *sh_per[2];                            // each frame's period, 72 MHz cycles (2 pieces of 768)
static volatile uint16_t sh_wr = 0, sh_rd = 0;
static volatile bool sh_on = false;                    // an image is loaded and the engine runs
static volatile uint8_t sh_chan = 0;
static bool sh_ready = false;                          // the tape's pieces are taken
static shnth_inputs sh_in;
static volatile bool sh_in_new = false;

static_assert(sizeof(shnth_engine) <= 1536, "the engine must fit one tape piece");

// entering SHNTH: take 19 pieces of the tape (only pieces of its own — never the shared RTC one)
static bool sh_begin() {
  sh_on = false; sh_ready = false;
  int k = 0; uint8_t *p[19];
  for (int i = 0; i < DCHUNKS - 1 && k < 19; i++) if (dchunk_own[i]) p[k++] = dchunk[i];
  if (k < 19) { Serial.println("[shnth] not enough tape pieces"); return false; }
  for (int i = 0; i < 11; i++) { sh_dl[i] = (int16_t *)p[i]; memset(p[i], 0, DCHUNK_BYTES); }
  sh_e = (shnth_engine *)p[11];
  sh_img = p[12];
  for (int i = 0; i < 4; i++) sh_ring[i] = (uint32_t *)p[13 + i];
  for (int i = 0; i < 2; i++) sh_per[i] = (uint16_t *)p[17 + i];
  memset(sh_e, 0, sizeof(shnth_engine));
  shnth_init(sh_e, nullptr);
  memset(&sh_in, 0, sizeof(sh_in));
  sh_wr = sh_rd = 0;
  sh_ready = true;
  return true;
}
static void sh_end() { sh_on = false; sh_ready = false; }

// the phone's lines (from pc_line)
static void sh_line(char *s) {
  if (s[0] == 'a') {                                   // the controls
    long v[7] = {0, 0, 0, 0, 0, 0, 0};
    sscanf(s + 1, "%ld %ld %ld %ld %ld %ld %ld", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6]);
    for (int i = 0; i < 4; i++) sh_in.bar[i] = (int16_t)constrain(v[i], -4095, 4095);
    for (int i = 0; i < 2; i++) sh_in.corp[i] = (int16_t)constrain(v[4 + i], -32768, 32767);
    sh_in.buttons = (uint16_t)v[6];
    sh_in.cooked = 0;
    sh_in_new = true;
    return;
  }
  if (!(preset == 2 && pc_mode == 8)) return;          // (only while the BLE preset is on SHNTH)
  if (!sh_ready && !sh_begin()) return;
  if (s[1] == 'L') {                                   // AL: load, pick, play
    long len = 0, pre = 0, ch = 0;
    sscanf(s + 2, "%ld %ld %ld", &len, &pre, &ch);
    if (len < 2 || len > DCHUNK_BYTES) return;
    shnth_load(sh_e, sh_img, (uint32_t)len);
    shnth_select(sh_e, (int)pre);
    sh_chan = (uint8_t)constrain(ch, 0, 2);
    sh_wr = sh_rd = 0;
    sh_on = true;
    Serial.printf("[shnth] patch %ld bytes, preset %ld, %d presets, channel %d\n", len, pre, shnth_preset_count(sh_e), (int)sh_chan);
    return;
  }
  char *q = s + 1;                                     // A <offset> <hex>
  long off = strtol(q, &q, 10);
  if (off == 0) sh_on = false;                         // (a new image: stop reading the old one)
  while (*q == ' ') q++;
  while (q[0] && q[1] && off < DCHUNK_BYTES) {
    int hi = isdigit((unsigned char)q[0]) ? q[0] - '0' : (tolower(q[0]) - 'a' + 10);
    int lo = isdigit((unsigned char)q[1]) ? q[1] - '0' : (tolower(q[1]) - 'a' + 10);
    sh_img[off++] = (uint8_t)((hi << 4) | lo);
    q += 2;
  }
}

// loop(): run the engine ahead into the ring (≤ 768 samples a call)
static void sh_fill() {
  if (sh_ready && !(preset == 2 && pc_mode == 8)) { sh_end(); return; }   // (the tape is the tape again: let it go)
  if (!sh_on || !sh_e) return;
  if (sh_in_new) { sh_in_new = false; shnth_set_inputs(sh_e, &sh_in); }
  for (int n = 0; n < 768; n++) {
    uint16_t nx = (sh_wr + 1) % SH_RING;
    if (nx == sh_rd) break;
    int l, r;
    shnth_tick(sh_e, &l, &r);
    uint32_t per = shnth_period_cycles(sh_e);
    sh_ring[sh_wr / 384][sh_wr % 384] = (uint32_t)(l & 0xFFF) | ((uint32_t)(r & 0xFFF) << 12);
    sh_per[sh_wr / 768][sh_wr % 768] = (uint16_t)(per > 65535 ? 65535 : (per < 64 ? 64 : per));
    sh_wr = nx;
  }
}

// the audio interrupt in SHNTH: play the ring at the engine's own rate (real time, from the CPU's cycle counter)
static void sh_tick_isr() {
  static uint32_t lastc = 0, acc = 0, per10 = 40970;   // (72 MHz cycles × 10)
  static uint32_t cur = 0x800800;                      // (2048 | 2048 << 12: silence)
  DACWRITER(pout)
  gyo = ADCREADER
    pc_samples++;
  uint32_t cc; asm volatile("rsr %0, ccount" : "=a"(cc));
  uint32_t dcy = cc - lastc;
  lastc = cc;
  if (dcy > 240000 || dcy < 1000) dcy = 7500;
  acc += dcy * 3;                                      // (a 240 MHz cycle is 0.3 of a 72 MHz one: × 10 = 3)
  int guard = 0;
  while (acc >= per10 && guard++ < 64) {
    acc -= per10;
    if (sh_on && sh_rd != sh_wr) {
      uint16_t k = sh_rd;
      cur = sh_ring[k / 384][k % 384];
      per10 = (uint32_t)sh_per[k / 768][k % 768] * 10;
      sh_rd = (k + 1) % SH_RING;
    } else { acc = 0; break; }                         // (nothing new yet: hold the last sample)
  }
  int32_t l = cur & 0xFFF, r = (cur >> 12) & 0xFFF;
  int32_t o = sh_on ? (sh_chan == 1 ? l : sh_chan == 2 ? r : (l + r) >> 1) : 2048;
  pout = o;
  ASHWRITER(o);
  pc_flip = FLIPPERAT ? 1 : 0;
  pc_skip = SKIPPERAT ? 1 : 0;
  REG(I2S_CONF_REG)
  [0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)
  [0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)
  [0] |= (BIT(5));
}
