// ==========================================
// MENU
// ==========================================
// "Apple Pi" alt Firmware for the CIAT LONBARDE CAFETERIA/CAFE QUANTUM
//
// 31 Presets: a mixed bag of effects
//
// by ieat31415
// playlist of preset demos on my YOUTUBE (youtube.com/@ieat3141592)
// ------------------------------------------

// ==========================================
// CHANGE LOG --- VERSION 1.41421
// ==========================================
// New Cleaner Ash output (otherss available in stuff)
// Improved button response in Preset Selection Mode
// Added visual feedback in Preset Selection Mode
// Configuration for Original Cocoquantus startup mode available.
// Fixed DC Offset in Ash for Saturator Preset
// Plus: External Sync optomized to sync with a Coco_mod preset
// Plus: coco_mod expanded to set PPQN
// ------------------------------------------

// ==========================================
// CHANGE LOG --- VERSION 2.718
// ==========================================
// New Preset: Tape Deck, an interface to save and recall loops in persistent memory, even across power cycles
// Load a tape deck slot during power on instead of noise. Set up in Boot configuration below
// New Preset: Windows from Daniel Fishkin
// New Preset: Splicer
// New Preset: Dissolve
// New Preset: Feedback reverb
// Added Crossfade from Peter's Firmware
// ------------------------------------------

// ============================================================================
// BOOT CONFIGURATION
// ============================================================================
// The original Cocoquantus booted with its delay buffer frozen and filled with noise
// By default, this firmware boots unfrozen (so the buffer is immediately cleared)
// 
// Change this to 'true' if you want the classic Cocoquantus frozen noise boot.
#define CLASSIC_NOISE_BOOT false

// ============================================================================

//90s cafe, warm tones, friends, extravagant laptop bezels.
//a coffee cup as big as your head.
//if arduino was bought by a printer company is this stable?


#include "synths.h"

// COCO DUO BUILD (esp_cafe_duo): controlled over BLE only, by the coco duo iPhone app (two Cafes, 8 XY pads).
// USB is only used for the boot messages (Serial Monitor at 115200). No USB commands, no WAV dump.
// For coco-pc (Mac page / iPhone app with save wav) use esp_cafe_ble instead.
// USB serial speed. 921600 garbled on this Cafe, 115200 works.
#define PC_BAUD 115200
// firmware version: shown in "HELLO" and at boot (raise it to see that an update went in)
#define FW_VERSION "3.44"

// ==========================================
// BLE LINK (k.odk, test) --- the same text protocol as USB, over the Nordic UART Service
// ==========================================
// Needs the library "NimBLE-Arduino" (Library Manager). The Cafe advertises as "Cafe-XXXX".
// Replies go back to wherever the command came from (USB or BLE).
#include <NimBLEDevice.h>
#define NUS_SVC "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"   // computer -> Cafe (write)
#define NUS_TX  "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"   // Cafe -> computer (notify)
#define OTA_RX  "6E400004-B5A3-F393-E0A9-E50E24DCCA9E"   // firmware update: binary pieces (write without response)
#include <Update.h>
#include <esp_ota_ops.h>
#include <driver/adc.h>
#include <driver/rtc_io.h>
volatile uint32_t earth_fail = 0, pin_fix = 0;               // EARTH reads the radio refused ("H")
static NimBLECharacteristic *ble_tx = nullptr;
static volatile bool ble_conn = false;
static volatile uint16_t ble_mtu = 23;
static volatile uint16_t ble_itvl = 0;          // connection interval, units of 1.25 ms
static bool ble_ok = false;
static char ble_name[16] = "Cafe";
RTC_DATA_ATTR static char ble_rb[1024];            // bytes written by the BLE task (core 0), read in loop() (RTC memory: the heap is tight)
static volatile uint16_t ble_wh = 0, ble_rh = 0;
static volatile bool ota_active = false;         // a firmware update is running (see below)

class CafeServerCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *s, NimBLEConnInfo &ci) override {
    ble_mtu = 23; ble_conn = true; pc_link = true; ble_itvl = ci.getConnInterval();
    s->updateConnParams(ci.getConnHandle(), 12, 12, 0, 300);   // ask for 15 ms between radio exchanges (less lag)
    Serial.printf("[ble] connected, interval %u x1.25ms. heap %u largest %u\n", (unsigned)ble_itvl, (unsigned)ESP.getFreeHeap(), (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  }
  void onDisconnect(NimBLEServer *s, NimBLEConnInfo &ci, int reason) override {
    ble_conn = false; pc_link = false;
    if (ota_active) { Update.abort(); Serial.println("[ota] link lost: restarting"); ESP.restart(); }
    Serial.printf("[ble] disconnected, reason 0x%X. heap %u\n", reason, (unsigned)ESP.getFreeHeap());
  }
  void onConnParamsUpdate(NimBLEConnInfo &ci) override { ble_itvl = ci.getConnInterval(); Serial.printf("[ble] interval now %u x1.25ms\n", (unsigned)ble_itvl); }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo &ci) override { ble_mtu = mtu; Serial.printf("[ble] mtu %u\n", mtu); }
};
class CafeRxCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &ci) override {
    NimBLEAttValue v = c->getValue();
    const uint8_t *d = v.data();
    for (size_t i = 0; i < v.size(); i++) {
      uint16_t n = (ble_wh + 1) & 1023;
      if (n == ble_rh) break;                      // full: drop the rest
      ble_rb[ble_wh] = (char)d[i]; ble_wh = n;
    }
  }
};
// ---- BLE firmware update (k.odk) ----
// "U <size> <crc32 hex>" on the text link starts it: audio stops, the tape memory is freed for a receive buffer,
// then the page writes pieces to OTA_RX: [4 bytes offset, little endian][data]. loop() writes them to the other
// app slot and answers "U A <bytes written>" every 4 KB. At the end the CRC is checked and the Cafe restarts.
#define OTA_RING 16384
static uint8_t *ota_rb = nullptr;
static volatile uint32_t ota_wh = 0, ota_rh = 0;      // ring heads (byte counters, never wrap back)
static volatile uint32_t ota_rx = 0;                  // next offset the ring expects
static volatile bool ota_bad = false;                 // a piece came out of order (dropped)
static volatile uint32_t ota_last_ms = 0;
class CafeOtaCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &ci) override {
    if (!ota_active || !ota_rb) return;
    NimBLEAttValue v = c->getValue();
    const uint8_t *d = v.data(); size_t n = v.size();
    if (n < 5) return;
    uint32_t off = d[0] | (d[1] << 8) | (d[2] << 16) | ((uint32_t)d[3] << 24);
    n -= 4; d += 4;
    if (off != ota_rx || (ota_wh - ota_rh) + n > OTA_RING) { ota_bad = true; return; }
    uint32_t w = ota_wh;
    for (size_t i = 0; i < n; i++) ota_rb[(w + i) & (OTA_RING - 1)] = d[i];
    ota_rx = off + n;
    ota_wh = w + n;
    ota_last_ms = millis();
  }
};

void ble_begin() {
  uint64_t m = ESP.getEfuseMac();
  snprintf(ble_name, sizeof(ble_name), "Cafe-%02X%02X", (unsigned)((m >> 32) & 0xFF), (unsigned)((m >> 40) & 0xFF));
  if (!NimBLEDevice::init(ble_name)) { Serial.println("    BLE init FAILED"); return; }
  NimBLEDevice::setMTU(247);
  NimBLEServer *srv = NimBLEDevice::createServer();
  srv->setCallbacks(new CafeServerCB());
  srv->advertiseOnDisconnect(true);
  NimBLEService *svc = srv->createService(NUS_SVC);
  ble_tx = svc->createCharacteristic(NUS_TX, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic *rx = svc->createCharacteristic(NUS_RX, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  rx->setCallbacks(new CafeRxCB());
  NimBLECharacteristic *ota = svc->createCharacteristic(OTA_RX, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ota->setCallbacks(new CafeOtaCB());
  svc->start();
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData ad, sr;
  ad.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  ad.addServiceUUID(NUS_SVC);                      // the app can look for the service
  sr.setName(ble_name);                            // the name goes in the scan response (no room in the ad)
  adv->setAdvertisementData(ad);
  adv->setScanResponseData(sr);
  ble_ok = adv->start();
}
void ble_line(const char *s) {                     // one text line -> notifications of (MTU-3) bytes
  RTC_DATA_ATTR static char tmp[320];                            // (the longest reply is ~130 characters)
  if (!ble_conn || !ble_tx) return;
  size_t len = strlen(s);
  if (len > sizeof(tmp) - 2) len = sizeof(tmp) - 2;
  memcpy(tmp, s, len); tmp[len++] = '\n';
  size_t chunk = (ble_mtu > 23) ? ble_mtu - 3 : 20;
  if (chunk > 244) chunk = 244;
  for (size_t o = 0; o < len; o += chunk) {
    size_t n = (len - o < chunk) ? len - o : chunk;
    int tries = 0;
    while (!ble_tx->notify((const uint8_t *)tmp + o, n)) {  // out of buffers: wait a little
      if (++tries > 25 || !ble_conn) return;
      delay(2);
    }
  }
}
void pc_out(const char *s) { ble_line(s); }       // duo: replies only go out over BLE

// ------------------------------------------
// THE POOL (k.odk): every preset this firmware has. Ids 0..10 = ours (as above), 11.. = Apple π's (ieat31415,
// namespace ie). The phone picks up to 11 of them as the playlist ("L ..."), kept in flash (NVS).
// "G <id>" loads any pool id directly.
// ------------------------------------------
void (*pool[])() = {
    coco_mod, echo_og, coco_pc, resonator, formant, saturator, harmony, rungler, selfread, multi, arpdelay,
    ie::coco_og, ie::echo_mod, ie::flanger, ie::karplus, ie::reverb_spring, ie::reverb_granular, ie::reverb_feedback,
    ie::harmonizer, ie::external_sync, ie::window, ie::splicer, ie::scrambler, ie::dissolve, ie::sampler,
    ie::sampler_4x, ie::granular, ie::phasing, ie::bytebeats_mod, ie::megabytebeats, ie::arcade, ie::FX,
    ie::wavetable, ie::drone, ie::groovebox, ie::polyrhythms
};
#define POOL_N ((int)(sizeof(pool) / sizeof(pool[0])))
#include <Preferences.h>
static void pl_save() {
  Preferences pr; if (!pr.begin("cafe", false)) return;
  uint8_t b[11]; for (int i = 0; i < 11; i++) b[i] = i < active_preset_count ? (uint8_t)pl_id[i] : 0xFF;
  pr.putBytes("pl", b, 11); pr.end();
}
static void pl_load() {
  Preferences pr; uint8_t b[11]; int n = 0;
  if (pr.begin("cafe", true)) {
    if (pr.getBytes("pl", b, 11) == 11) for (int i = 0; i < 11 && b[i] < POOL_N; i++) pl_id[n++] = b[i];
    pr.end();
  }
  if (n == 0) { for (int i = 0; i < 11; i++) pl_id[i] = i; n = 11; }
  active_preset_count = n;
  for (int i = 0; i < n; i++) presets[i] = pool[pl_id[i]];
}
static int pl_index(int id) { for (int i = 0; i < active_preset_count; i++) if (pl_id[i] == id) return i; return -1; }
static void pl_report() {
  char b[80]; int k = snprintf(b, sizeof(b), "L");
  for (int i = 0; i < active_preset_count; i++) k += snprintf(b + k, sizeof(b) - k, " %d", pl_id[i]);
  pc_out(b);
}


// ==========================================
// LINK (k.odk) --- text protocol, over BLE only in this build
// ==========================================
// REQUEST / REPLY only: the Cafe never talks unless asked (the HELLO path is the one that proved to work).
// phone -> Cafe (one line each):
//   P            ping            -> "HELLO coco-duo 3 <name> ota"
//   Q            poll            -> one status line "T ..." and one overview chunk "O <bin> <hex>"
//   R <0|1>      recording off/on (GRAIN / RUNGLER)
//   W <start> <data>  write samples (2 chars each, 48 + 6 bits) -> "w <start>"
//   G <n>        switch to preset n (0-based, see the playlist)
//   M <id> <v>   grain parameter (see mo_update); M 25 <0..3> = BLE preset mode GRAIN / COCO / DELAY / NOISE
//   C <id> <v>   coco parameter (see co_update)
//   Y <id> <v>   delay parameter (see dl_update)
//   N <id> <v>   noise parameter (see nz_update)
//   V <id> <v>   harmony parameter (see hd_update)
//   X <v> [p]    CHAR (0..1000) for preset p (0-based; default the current one): see ch_v in stuff.h
//   K <bpm x10>  the shared tempo (DELAY, HARMONY)
//   Z            sync: grain score / coco loop start / the click (send to both Cafes at once = in step)
//   U ...        firmware update (see ota_cmd)
// T wpos ppos rec ls le speed earth flip skip button samples preset mode bpm_x10 multi_effect
//   F …          MULTI (see the top of multi() in synths.h)
// FLIP / SKIP / BUTTON seen high since the last status line (short triggers are not missed by the 30 ms poll)
// the WAVE panel's YELLOW / ASH windows: loop() samples both outputs (the GPIO ladder, the DAC register) and keeps
// the lowest / highest value between two status lines (0..255 each) -> a rolling min/max picture on the phone
volatile uint8_t sc_amin = 255, sc_amax = 0, sc_ymin = 255, sc_ymax = 0;
static inline void scope_sample() {
  uint32_t g = REG(GPIO_OUT_REG)[0];
  uint32_t y = ((g >> 12) & 0x3F) | (((g >> 21) & 0x3) << 6) | (((g >> 26) & 0x3) << 8);   // 10-bit ladder
  uint8_t yv = (uint8_t)(y >> 2);
  uint8_t av = (uint8_t)((REG(ESP32_RTCIO_PAD_DAC1)[0] >> 19) & 0xFF);
  if (yv < sc_ymin) sc_ymin = yv; if (yv > sc_ymax) sc_ymax = yv;
  if (av < sc_amin) sc_amin = av; if (av > sc_amax) sc_amax = av;
}
volatile bool seen_flip = false, seen_skip = false, seen_btn = false;
void pc_status() {
  char tb[176];
  snprintf(tb, sizeof(tb), "T %lu %lu %d %ld %ld %ld %d %d %d %d %lu %d %d %d %d %d %d %d %d %d",
    (unsigned long)pc_wpos, (unsigned long)pc_ppos, (pc_rec && !audio_frozen_state) ? 1 : 0,
    (long)pc_ls, (long)pc_le, (long)(pc_speed * 1000 / 4096),
    (int)EARTHREAD, (seen_flip || (FLIPPERAT)) ? 1 : 0, (seen_skip || (SKIPPERAT)) ? 1 : 0, (seen_btn || !(BUTTONEST)) ? 1 : 0, (unsigned long)pc_samples, preset,
    pc_mode, (int)(cafe_bpm * 10.0f + 0.5f), fx_now, ch_now(),
    sc_amin > sc_amax ? 128 : sc_amin, sc_amin > sc_amax ? 128 : sc_amax, sc_ymin > sc_ymax ? 0 : sc_ymin, sc_ymin > sc_ymax ? 0 : sc_ymax);
  pc_out(tb);
  seen_flip = seen_skip = seen_btn = false;
  sc_amin = 255; sc_amax = 0; sc_ymin = 255; sc_ymax = 0;
}
void pc_overview() {
  static int obin = 0;
  static const char *hx = "0123456789ABCDEF";
  char buf[12 + 16 * 4 + 2];
  int n = snprintf(buf, sizeof(buf), "O %d ", obin);
  for (int b = 0; b < 16; b++) {
    int base = (obin + b) * 256, mn = 4095, mx = 0;
    for (int i = 0; i < 256; i += 2) {
      int v = dread(base + i);
      if (v < mn) mn = v; if (v > mx) mx = v;
    }
    mn >>= 4; mx >>= 4;
    buf[n++] = hx[mn >> 4]; buf[n++] = hx[mn & 15]; buf[n++] = hx[mx >> 4]; buf[n++] = hx[mx & 15];
  }
  buf[n] = 0;
  pc_out(buf);
  obin = (obin + 16) & 511;
}
// ---- GRAIN parameters (k.odk). Raw 0..1000 from the phone -> times at the Cafe's real clock ----
//  0 density  1 jitter  2 grain length  3 shape (0 = pure sin², 1000 = flatter)  4 pitch  5 pitch spread
//  6 where (recent .. deep in the tape)  7 scatter  8 filter  9 resonance  10 reverse  11 pitch hold (grains per pitch)
//  12 layers  13 level  14 offset (this Cafe later, share of a gap)  15 separation  16 which Cafe (0 = A, 1 = B)
//  20 <n> = mark the last grain's place in slot n  21 = clear the marks  22 <0|1> = grains only from the marks
//  23 <0|1> = freeze  24 <0|1> = percussion (struck grains)  26 <0|1> = MOVE (a new, gliding pitch every grain)  27 <0|1> = FOLD  25 <0|1|2> = duo mode: LOOP / GRAIN / BENJOLIN
volatile float mo_hz = 32000;
static const int16_t mo_default[17] = {550, 150, 550, 200, 500, 0, 200, 250, 1000, 200, 0, 700, 600, 500, 0, 0, 0};
void mo_update() {
  float hz = mo_hz > 1000 ? mo_hz : 32000;
  float p[17];
  for (int i = 0; i < 17; i++) p[i] = mo_p[i] / 1000.0f;
  float dens = powf(80.0f, p[0]);                          // 1 .. 80 grains per second
  mo_int_us = (int32_t)(1.0e6f / dens);
  mo_jit = (int32_t)(p[1] * 4096.0f);
  float ms = 10.0f * powf(50.0f, p[2]);                    // 10 .. 500 ms
  int32_t len = (int32_t)(ms * hz / 1000.0f); if (len < 128) len = 128; if (len > 60000) len = 60000;
  mo_len = len;
  int32_t edge = (int32_t)(len * (0.5f - 0.42f * p[3])); if (edge < 32) edge = 32;
  mo_edge = edge;
  mo_rate = (int32_t)(4096.0f * powf(2.0f, (p[4] - 0.5f) * 6.0f));   // -3 .. 0 .. +3 octaves (centre = 1x)
  mo_spread = 1 + (int)(p[5] * 8.0f + 0.5f);
  mo_back = 256 + (int32_t)(p[6] * p[6] * (131072 - 40000));
  mo_scat = 1 + (int32_t)(p[7] * 65534.0f);
  if (p[8] >= 0.98f) mo_f = 4096;
  else {
    float fc = 220.0f * powf(2.0f, p[8] * 6.5f);             // 220 Hz .. open (the bottom no longer swallows it)
    if (fc > hz / 6) fc = hz / 6;
    mo_f = (int32_t)(4096.0f * 2.0f * sinf(3.14159265f * fc / hz));
  }
  mo_q = (int32_t)(4096.0f * (1.0f - 0.92f * p[9]));
  mo_rev = (uint16_t)(p[10] * 65535.0f);
  mo_hold = 1 + (int32_t)(p[11] * p[11] * 63.0f + 0.5f);    // 1 .. 64 grains on one pitch
  mo_layers = 1 + (uint8_t)(p[12] * 5.0f + 0.5f);
  float overlap = dens * ms / 1000.0f * (1.0f - 0.5f * (0.5f - 0.42f * p[3]) * 2.0f * 0.5f);
  if (overlap > mo_layers) overlap = mo_layers; if (overlap < 1.0f) overlap = 1.0f;
  mo_gain = (int32_t)(p[13] * 2.0f * 256.0f * 1.8f / sqrtf(overlap));
  mo_fold = (int32_t)((0.12f + 0.33f * p[2]) * 4096.0f);          // a little fold: 0.12 (short grains) .. 0.45 (long)   // keep the level when grains pile up
  mo_sep = (int32_t)(p[15] * 4096.0f);
  mo_salt = mo_p[16] > 0 ? 1 : 0;

  // SEPARATION pulls the two sides apart in everything, not only in the dice (A = -1, B = +1):
  //   tempo  A up to 30 % faster, B up to 30 % slower   -> they phase against each other
  //   pitch  A down, B up, up to a fifth each            -> they no longer sit on one note
  //   length A longer, B shorter (up to 40 %)
  //   timing jitter, pitch spread and scatter all grow with it
  float sp = p[15], side = mo_salt ? 1.0f : -1.0f;
  if (sp > 0.0f) {
    mo_int_us = (int32_t)(mo_int_us * (1.0f + side * 0.30f * sp));
    int32_t j = (int32_t)(sp * 0.8f * 4096.0f); if (j > mo_jit) mo_jit = j;
    mo_rate = (int32_t)(mo_rate * powf(2.0f, side * sp * 7.0f / 12.0f));
    int32_t l = (int32_t)(mo_len * (1.0f - side * 0.40f * sp)); if (l < 128) l = 128; if (l > 60000) l = 60000;
    mo_len = l;
    mo_edge = (int32_t)(l * (0.5f - 0.42f * p[3])); if (mo_edge < 32) mo_edge = 32;
    int sprd = mo_spread + (int)(sp * 6.0f + 0.5f); mo_spread = sprd > 9 ? 9 : sprd;
    int32_t sc = mo_scat + (int32_t)(sp * 40000.0f); mo_scat = sc > 65535 ? 65535 : sc;
  }
  mo_offs_us = (int32_t)(p[14] * mo_int_us);
}
void mo_fill_window() { for (int i = 0; i <= 128; i++) { float s = sinf(3.14159265f * 0.5f * i / 128.0f); mo_win[i] = (int16_t)(4096.0f * s * s); } }

// ---- the filter scale for NOISE (k.odk) ----
void bj_update() {
  float hz = mo_hz > 1000 ? mo_hz : 32000;
  bj_fk = (int32_t)(2.0f * 3.14159265f * 20.0f / hz * 4096.0f * 256.0f);
}
void bj_fill_table() { for (int i = 0; i < 256; i++) bj_exp[i] = (uint32_t)(65536.0f * powf(2.0f, i / 256.0f)); }

// ---- tempo helpers ----
// divisions of a beat: 1/16, 1/8T, 1/8, 1/4T, 1/8., 1/4, 1/4., 1/2, 1/1
static const float beat_div[9] = {0.25f, 1.0f / 3.0f, 0.5f, 2.0f / 3.0f, 0.75f, 1.0f, 1.5f, 2.0f, 4.0f};
static inline int div_index(int v) { int i = (v * 8 + 500) / 1000; return i < 0 ? 0 : (i > 8 ? 8 : i); }
static inline float clock_hz() { return mo_hz > 1000 ? mo_hz : 32000; }

// ---- DELAY parameters (k.odk). "Y <id> <0..1000>" ----
//  0 time (free: 10 ms .. 1.5 s; SYNC / LINK: steps through the divisions)  1 R time vs L (0.5x .. 2x, 500 = same)
//  2 feedback  3 ping-pong  4 wet  5 tone  6 wow (EARTH)  7 division (SYNC)  8 sync  9 dry  10 hold
//  11 LINK (two Cafes = one delay)  12 which side (0 = A, 1 = B)
static const int16_t dl_default[13] = {450, 500, 450, 1000, 600, 700, 0, 625, 1000, 1000, 0, 0, 0};
void dl_update() {
  float hz = clock_hz(), p[13];
  for (int i = 0; i < 13; i++) p[i] = dl_p[i] / 1000.0f;
  bool link = dl_p[11] > 0, sync = link || dl_p[8] >= 500;
  float beat = hz * 60.0f / cafe_bpm;
  float tl;
  if (link) tl = beat * beat_div[div_index(dl_p[0])];            // linked: the TIME pad steps the grid
  else if (sync) tl = beat * beat_div[div_index(dl_p[7])];
  else tl = hz * 0.010f * powf(150.0f, p[0]);
  float lim = link ? 65000.0f : 65000.0f;
  while (tl > lim) tl *= 0.5f;                                   // too long for the tape: half of it
  float tr = tl * powf(2.0f, (p[1] - 0.5f) * 2.0f);
  if (tr > 65000.0f) tr = 65000.0f;
  dl_tl = (int32_t)(tl * 256.0f); dl_tr = (int32_t)(tr * 256.0f);
  dl_fb = (int32_t)(p[2] * 245.0f);
  dl_pp = (int32_t)(p[3] * 256.0f);
  dl_wet = (int32_t)(p[4] * 1.6f * 256.0f);
  dl_tone = (int32_t)(300.0f + p[5] * p[5] * 3796.0f);
  dl_wow = (int32_t)(p[6] * 600.0f);
  dl_dry = (int32_t)(p[9] * 256.0f);
  bool was_held = dl_hold;
  dl_hold = dl_p[10] > 0;
  if (was_held != dl_hold && !dl_hold) audio_frozen_state = false;   // HOLD off on the phone = everything lets go (also a BUTTON freeze)
  int pair = link ? (dl_p[12] > 0 ? 2 : 1) : 0;
  if (pair != dl_pair) { dl_pair = pair; dl_reset = true; }
  float b = sync ? beat : tl;
  dl_beat = (int32_t)(b > 64 ? b : 64);
}

// ---- NOISE parameters (k.odk). "N <id> <0..1000>" ----
//  0 size (line length)  1 spread (between the three lines)  2 feedback (ring gain)  3 grit (soft .. fold .. 1-bit)
//  4 shift clock  5 loop (0 = free noise .. short loop = pitched)  6 gate rate  7 gate open (share)  8 cutoff
//  9 resonance  10 self (ring -> cutoff / clock)  11 level  12 input (live into the ring)  15 speed (0 FAST | 500 SLOW | 1000 CRAWL)
static const int16_t nz_default[16] = {450, 500, 700, 350, 600, 0, 350, 600, 650, 450, 300, 350, 0, 400, 450, 0};
void nz_update() {
  float hz = clock_hz(), p[15];
  for (int i = 0; i < 15; i++) p[i] = nz_p[i] / 1000.0f;
  nz_slow = nz_p[15] > 0 ? 1 : 0;                                // 15 = FAST 0 · LFO 500 (a round LFO moves pitch, fold and filter; no hiss)
  float base = 16.0f * powf(2.0f, p[0] * 8.9f);                 // 16 .. ~7600 samples
  float l[3] = {base, base * (1.13f + 0.50f * p[1]), base * (1.29f + 1.10f * p[1])};
  for (int i = 0; i < 3; i++) { if (l[i] > 8000) l[i] = 8000; if (l[i] < 8) l[i] = 8; nz_len[i] = (int32_t)l[i]; }
  nz_fb = (int32_t)(p[2] * 270.0f);
  nz_grit = (int32_t)(p[3] * 4096.0f);
  float fs = 20.0f * powf(2.0f, p[4] * 11.0f); if (fs > hz * 0.5f) fs = hz * 0.5f;
  nz_sinc = (uint32_t)(fs / hz * 4294967295.0f);
  { float lf = 0.02f * powf(250.0f, p[4]); nz_lfoinc = (uint32_t)(lf / hz * 4294967295.0f); }   // LFO: 0.02 .. 5 Hz (SHIFT X)
  nz_loop = nz_p[5] > 0 ? 2 + (int32_t)((1.0f - p[5]) * (1.0f - p[5]) * 1000.0f) : 0;
  float fg = 0.1f * powf(400.0f, p[6]);                          // 0.1 .. 40 Hz
  nz_ginc = (uint32_t)(fg / hz * 4294967295.0f);
  nz_duty = (uint32_t)(p[7] * 4294967295.0f);
  nz_fc = (int32_t)(p[8] * 9.5f * 256.0f);
  nz_q = (int32_t)(4096.0f * (1.0f - 0.93f * p[9]));
  nz_self = (int32_t)(p[10] * 4.0f * 256.0f);
  nz_gain = (int32_t)(p[11] * 1.3f * 256.0f);
  nz_in = (int32_t)(p[12] * 256.0f);
  // 13 OSC pitch (20 Hz .. 5 kHz) · 14 FOLD: 0 = off, the first 15 % fades the oscillators in, then it folds
  float fo = 20.0f * powf(2.0f, p[13] * 8.0f);
  nz_oinc = (uint32_t)(fo / hz * 4294967295.0f);
  nz_olvl = (int32_t)((p[14] < 0.15f ? p[14] / 0.15f : 1.0f) * 230.0f);
  float fd = p[14] < 0.1f ? 0.0f : (p[14] - 0.1f) / 0.9f;
  nz_ofold = (int32_t)(fd * 4096.0f);
}

// ---- HARMONY parameters (k.odk). "V <id> <0..1000>" ----
//  0 VOICE 1 interval  1 VOICE 1 timing  2 VOICE 2 interval  3 VOICE 2 timing  4 cycle (1/4 .. 8 beats)  5 feedback
//  6 voices level  7 dry  8 overdub (old tape kept)  9 tone  11 EARTH wobble  13 hold
//  intervals (12): backwards · backwards -oct · -2 oct · -oct · -5th · -4th · unison · +4th · +5th · +oct · +oct+5th · +2 oct
//  timing: 16 steps of the cycle
static const int16_t hd_default[14] = {273, 0, 727, 267, 600, 150, 700, 1000, 0, 1000, 0, 300, 0, 0};
static const float hd_cyc[6] = {0.25f, 0.5f, 1.0f, 2.0f, 4.0f, 8.0f};
void hd_update() {
  float hz = clock_hz(), p[14];
  for (int i = 0; i < 14; i++) p[i] = hd_p[i] / 1000.0f;
  float beat = hz * 60.0f / cafe_bpm;
  hd_rate[0] = hd_iv[(int)(p[0] * 11.0f + 0.5f)];
  hd_off[0] = (int32_t)(p[1] * 15.0f + 0.5f);
  hd_rate[1] = hd_iv[(int)(p[2] * 11.0f + 0.5f)];
  hd_off[1] = (int32_t)(p[3] * 15.0f + 0.5f);
  float S = beat * hd_cyc[(int)(p[4] * 5.0f + 0.5f)];
  while (S > HD_STRIDE - 2) S *= 0.5f;
  hd_S = (int32_t)S;
  hd_fb = (int32_t)(p[5] * 200.0f);
  hd_lvl = (int32_t)(p[6] * 1.5f * 256.0f);
  hd_dry = (int32_t)(p[7] * 256.0f);
  hd_keep = (int32_t)(p[8] * 230.0f);
  hd_tone = p[9] >= 0.98f ? 4096 : (int32_t)(300.0f + p[9] * p[9] * 3796.0f);
  hd_wob = (int32_t)(p[11] * 256.0f);
  hd_hold = hd_p[13] > 0;
  hd_beat = (int32_t)(beat > 64 ? beat : 64);
}
// ---- COCO parameters (k.odk). "C <id> <0..1000>" ----
//  0 speed (centre = stop, 750 = 1x forward, 250 = 1x backward, ends = 4x)  1 overdub  2 loop start  3 loop length
//  4 EARTH FM depth (up to ±200 %)  5 FM slew (0 = follows at once = audio-rate FM, 1000 = slow bends)
//  6 wobble rate (0.05 .. 25 Hz)  7 wobble depth (up to ±50 %)  8 cutoff  9 resonance  10 crush (sample & hold)
//  11 bits  12 dry  13 level  14 this Cafe's speed offset (up to +6 %)  15 this Cafe's loop start offset
//  16 <0|1> reverse  17 = back to the loop start
static const int16_t co_default[16] = {750, 0, 0, 1000, 300, 200, 300, 0, 1000, 200, 0, 0, 0, 500, 0, 0};
void co_update() {
  float hz = clock_hz(), p[16];
  for (int i = 0; i < 16; i++) p[i] = co_p[i] / 1000.0f;
  float x = p[0] * 2.0f - 1.0f;
  float sp = fabsf(x) < 0.04f ? 0.0f : (x < 0 ? -1.0f : 1.0f) * 4.0f * x * x;
  co_speed = (int32_t)(sp * 4096.0f);
  co_dub = 256 - (int32_t)(p[1] * 224.0f);
  co_ls = (int32_t)(p[2] * 131071.0f);
  co_len = 256 + (int32_t)(p[3] * p[3] * (131072.0f - 256.0f));
  co_fm = (int32_t)(p[4] * 512.0f);
  co_slew = (int32_t)(4096.0f * powf(2.0f, -p[5] * 10.0f)); if (co_slew < 2) co_slew = 2;
  float lf = 0.05f * powf(500.0f, p[6]);
  co_lfo_inc = (uint32_t)(lf / hz * 4294967295.0f);
  co_lfo_depth = (int32_t)(p[7] * 2048.0f);
  if (p[8] >= 0.98f) co_f = 4096;
  else {
    float fc = 60.0f * powf(2.0f, p[8] * 8.0f);
    if (fc > hz / 6) fc = hz / 6;
    co_f = (int32_t)(4096.0f * 2.0f * sinf(3.14159265f * fc / hz));
  }
  co_q = (int32_t)(4096.0f * (1.0f - 0.92f * p[9]));
  co_hold = 1 + (int32_t)(p[10] * p[10] * 63.0f);
  co_bits = (int32_t)(p[11] * 10.0f + 0.5f);
  co_dry = (int32_t)(p[12] * 256.0f);
  co_gain = (int32_t)(p[13] * 2.0f * 256.0f);
  co_det = (int32_t)(p[14] * 0.06f * 4096.0f);
  co_loff = (int32_t)(p[15] * co_len);
}

// ---- MULTI parameters (k.odk). "F <effect> <id 0..7> <0..1000>" ----
//  0 CLEAN      0 level
//  1 ECHO       0 time (grid: 1/16 .. 1/1)  1 feedback  2 ping-pong  3 R time vs L (0.5 .. 2x)  4 tone  5 EARTH wow  6 wet  7 dry
//  2 SAMPLER    0 pitch (-12 .. +24 semitones)  1 length  2 start  3 decay  4 auto (0 = off, grid)  5 tone  6 wet  7 dry
//  3 REVERSE    0 length  1 speed (0.5 .. 2x)  2 tone  6 wet  7 dry
//  4 GLITCH     0 grid  1 chance  2 slice  3 length (1..8 grids)  4 variety (moves + randomness)  5 pitch  6 crush  7 wet
//  5 FOLD+OCT   0 drive  1 bias  2 octave down  3 octave up  4 tone  6 wet  7 dry
//  6 REVERB     0 size  1 damping  2 width  3 diffusion  4 HOWL  5 MOD  6 wet  7 dry
//  7 SHORT DLY  0 time (1 .. 90 ms)  1 feedback  2 tone  3 wobble depth  4 wobble rate  5 spread (R longer)  6 wet  7 dry
static const int16_t fx_default[FX_N][8] = {
  {500, 0, 0, 0, 0, 0, 0, 0},
  {625, 550, 1000, 500, 800, 300, 900, 1000},
  {333, 400, 0, 300, 0, 1000, 900, 600},
  {400, 500, 1000, 0, 0, 0, 1000, 300},
  {300, 550, 400, 300, 750, 300, 150, 1000},
  {300, 500, 600, 200, 800, 0, 1000, 0},
  {750, 300, 800, 500, 400, 400, 450, 1000},
  {350, 550, 700, 300, 300, 500, 800, 1000},
};
static int32_t fx_lpk(float v) { return v >= 0.98f ? 4096 : (int32_t)(300.0f + v * v * 3796.0f); }
void fx_update(int e) {
  float hz = clock_hz(), p[8];
  for (int i = 0; i < 8; i++) p[i] = fx_p[e][i] / 1000.0f;
  float beat = hz * 60.0f / cafe_bpm;
  fx_beat = (int32_t)(beat > 64 ? beat : 64);
  switch (e) {
    case 0: cl_g = (int32_t)(p[0] * 512.0f); break;
    case 1: {
      float tt = beat * beat_div[div_index(fx_p[1][0])];
      while (tt > 32000.0f) tt *= 0.5f;
      td_T = (int32_t)(tt * 256.0f);
      td_fb = (int32_t)(powf(p[1], 0.8f) * 0.93f * 256.0f);          // a curve: more room where the repeats sing
      td_pp = (int32_t)(p[2] * 256.0f);
      { static const float rr[7] = {0.5f, 2.0f / 3.0f, 0.75f, 1.0f, 4.0f / 3.0f, 1.5f, 2.0f};   // R's time: rhythmic steps only
        td_ratio = (int32_t)(4096.0f * rr[(int)(p[3] * 6.0f + 0.5f)]); }                       // (in-between = a smeared, reverb-ish cloud)
      td_tone = fx_lpk(p[4]);
      td_wow = (int32_t)(p[5] * 600.0f);
      td_wet = (int32_t)(p[6] * 1.6f * 256.0f);
      td_dry = (int32_t)(p[7] * 256.0f);
    } break;
    case 2: {
      int semis = (int)(p[0] * 36.0f + 0.5f) - 12;
      sm_rate = (int32_t)(4096.0f * powf(2.0f, semis / 12.0f));
      float len = hz * (0.05f + p[1] * 0.55f); if (len > SM_LEN - 64) len = SM_LEN - 64;
      sm_len = (int32_t)len;
      sm_start = (int32_t)(p[2] * (SM_LEN - 1 - len));
      float hl = hz * (0.01f + (1.0f - p[3]) * (1.0f - p[3]) * 3.0f);
      sm_dec = (uint32_t)(65536.0f * powf(2.0f, -1.0f / hl)); if (sm_dec > 65535) sm_dec = 65535;
      sm_auto = fx_p[2][4] > 0 ? (int32_t)(beat * beat_div[div_index(fx_p[2][4])]) : 0;
      sm_tone = fx_lpk(p[5]);
      sm_wet = (int32_t)(p[6] * 2.6f * 256.0f);                          // (louder: the sample stands out)
      sm_dry = (int32_t)(p[7] * 256.0f);
    } break;
    case 3: {
      float w = hz * (0.05f + p[0] * 0.5f); if (w > 15000) w = 15000;
      rv_W = (int32_t)w;
      rv_speed = (int32_t)(4096.0f * powf(2.0f, (p[1] - 0.5f) * 2.0f));
      rv_tone = fx_lpk(p[2]);
      rv_wet = (int32_t)(p[6] * 2.3f * 256.0f);                          // (louder)
      rv_dry = (int32_t)(p[7] * 256.0f);
    } break;
    case 4: {
      int di = (int)(p[0] * 6.0f + 0.5f);                          // 1/16 .. 1/4.
      float ev = beat * beat_div[di]; if (ev < 256) ev = 256;
      gl_ev = (int32_t)ev;
      gl_chance = (int32_t)(p[1] * 65535.0f);
      float sl = ev * (0.125f + p[2] * 0.875f); if (sl > 8000) sl = 8000;
      gl_slice = (int32_t)sl;
      gl_len = 1 + (int32_t)(p[3] * 7.0f);
      gl_var = (int32_t)(p[4] * 256.0f);
      gl_pitch = (int32_t)(p[5] * 255.0f);
      gl_crush = (int32_t)(p[6] * 32.0f);
      gl_wet = (int32_t)(p[7] * 256.0f);
    } break;
    case 5: {
      fo_drive = 256 + (int32_t)(p[0] * 7.0f * 256.0f);
      fo_bias = (int32_t)((p[1] - 0.5f) * 2048.0f);
      fo_down = (int32_t)(p[2] * 256.0f);
      fo_up = (int32_t)(p[3] * 256.0f);
      fo_tone = fx_lpk(p[4]);
      fo_wet = (int32_t)(p[6] * 256.0f);
      fo_dry = (int32_t)(p[7] * 256.0f);
    } break;
    case 7: {                                                            // KARPLUS
      float semi = floorf(p[0] * 48.0f + 0.5f);                          // 4 octaves in semitones, from A1 (55 Hz)
      float f = 55.0f * powf(2.0f, semi / 12.0f);
      float tt = hz / f; if (tt > 4000) tt = 4000; if (tt < 8) tt = 8;
      sd_T = (int32_t)(tt * 256.0f);
      sd_fb = (int32_t)((0.80f + powf(p[1], 0.5f) * 0.17f) * 256.0f);    // DECAY: short pluck .. long ring (no endless howl)
      sd_tone = fx_lpk(0.25f + p[2] * 0.75f);                            // DAMP: dark .. bright
      sd_pluck = (int32_t)(p[3] * 320.0f);                               // PLUCK: noise burst on attacks
      sd_mod = (int32_t)(p[4] * p[4] * 0.02f * 65536.0f);                // WOBBLE: up to ±2 % of the period
      sd_lfo = (uint32_t)(0.3f / hz * 4294967295.0f);
      sd_spread = (int32_t)(p[5] * 0.03f * 4096.0f);                     // SPREAD: R up to 3 % longer
      sd_wet = (int32_t)(p[6] * 1.4f * 256.0f);
      sd_dry = (int32_t)(p[7] * 256.0f);
    } break;
    default: {
      rb_fb = (int32_t)(4096.0f * (0.72f + p[0] * 0.27f));
      rb_howl = (int32_t)(p[4] * p[4] * 0.06f * 4096.0f);               // up to +0.06 past the size: it howls (gently)
      rb_mod = (int32_t)(p[5] * 40.0f * 256.0f);                         // up to 40 samples of wobble
      rb_lfo = (uint32_t)((0.15f + p[5] * 1.2f) / hz * 4294967295.0f);
      rb_damp = (int32_t)(p[1] * 0.7f * 4096.0f);
      rb_width = (int32_t)(p[2] * 256.0f);
      rb_ap = (int32_t)(4096.0f * (0.3f + p[3] * 0.4f));
      rb_wet = (int32_t)(p[6] * 1.6f * 256.0f);
      rb_dry = (int32_t)(p[7] * 256.0f);
      for (int k = 0; k < 8; k++) { int32_t L = (int32_t)(rb_max[k] * hz / 44100.0f); rb_len[k] = L > rb_max[k] ? rb_max[k] : L; }
    } break;
  }
}
void fx_update_all() { for (int e = 0; e < FX_N; e++) fx_update(e); }

void all_update() { mo_update(); bj_update(); co_update(); dl_update(); nz_update(); hd_update(); fx_update_all(); }

// ---- EARTH guard (k.odk) ----
// EARTH comes in through the ESP32's second ADC (SAR ADC2), read by the digital controller into I2S.
// The radio (Bluetooth) also uses ADC2 for its power detector and takes it over: then EARTH reads 0.
// (v3.8 took ADC2 back every 20 ms; the radio took it again at once. Not used any more: the ADC runs on ADC1 alone.)
volatile uint32_t e2_fix = 0;
void earth_guard() {
  uint32_t a = REG(APB_SARADC_CTRL_REG)[0];
  if (!(a & BIT(2))) { REG(APB_SARADC_CTRL_REG)[0] = a | BIT(2); e2_fix++; }          // sar2_mux: ADC2 <- DIG
  uint32_t r = REG(SENS_SAR_READ_CTRL2_REG)[0];
  uint32_t want = (r | BIT(28) | BIT(29)) & ~BIT(27);                                 // dig_force = 1, data_inv (as setup), pwdet_force = 0
  if (r != want) { REG(SENS_SAR_READ_CTRL2_REG)[0] = want; e2_fix++; }
}

volatile int pc_goto = -1;                  // "G <n>": the phone asks for preset n (handled in loop)

void ota_cmd(char *s);
void pc_line(char *s) {
  if (s[0] == 'U') { ota_cmd(s); return; }
  if (ota_active) return;                   // updating: nothing else
  switch (s[0]) {
    case 'P': { char hb[48]; snprintf(hb, sizeof(hb), "HELLO coco-duo %s %s ota", FW_VERSION, ble_name); pc_out(hb); } break;
    case 'H': { char hb[240]; snprintf(hb, sizeof(hb), "H heap %u min %u ble %d conn %d mtu %d interval_ms %d earth %d clock_ms %lu a4 %lu fail %lu in1 %02lx adcpad %08lx pinfix %lu sarctl %08lx rdctl2 %08lx meas2 %08lx e2fix %lu dhold %d frz %d",
                (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMinFreeHeap(), ble_ok, ble_conn ? 1 : 0, (int)ble_mtu, (int)(ble_itvl * 5 / 4), (int)EARTHREAD,
                (unsigned long)(esp_timer_get_time() / 1000), (unsigned long)pc_fifo, (unsigned long)earth_fail, (unsigned long)(REG(GPIO_IN1_REG)[0] & 0xFF), (unsigned long)REG(RTC_IO_ADC_PAD_REG)[0], (unsigned long)pin_fix, (unsigned long)REG(APB_SARADC_CTRL_REG)[0],
                (unsigned long)REG(SENS_SAR_READ_CTRL2_REG)[0], (unsigned long)REG(SENS_SAR_MEAS_START2_REG)[0], (unsigned long)e2_fix, dl_hold ? 1 : 0, audio_frozen_state ? 1 : 0);
                pc_out(hb); } break;
    case 'Q': pc_status(); pc_overview(); break;
    case 'R': pc_rec = atol(s + 1) != 0; break;
    case 'G': { long n = atol(s + 1); if (n >= 0 && n < POOL_N) pc_goto = (int)n; } break;
    case 'L': {                            // L = report the playlist · L <id> <id> ... = set it (up to 11 pool ids) and keep it
                char *q = s + 1; int ids[11], n = 0;
                while (n < 11) { char *e; long v = strtol(q, &e, 10); if (e == q) break; q = e; if (v >= 0 && v < POOL_N) ids[n++] = (int)v; }
                if (n > 0) {
                  bool same = n == active_preset_count;
                  for (int i = 0; i < n && same; i++) same = pl_id[i] == ids[i];
                  for (int i = 0; i < n; i++) { pl_id[i] = ids[i]; presets[i] = pool[ids[i]]; }
                  active_preset_count = n;
                  if (!same) pl_save();              // flash only when it really changed
                }
                pl_report();
              } break;
    case 'M': { long id = -1, val = 0; sscanf(s + 1, "%ld %ld", &id, &val);
                if (id >= 0 && id < 17) {
                  if (val < 0) val = 0; if (val > 1000) val = 1000;
                  mo_p[id] = (int16_t)val; mo_update();
                } else if (id == 20) { mo_mark[val & 7] = mo_last; }
                else if (id == 21) { for (int i = 0; i < 8; i++) mo_mark[i] = -1; }
                else if (id == 22) { mo_usemarks = val != 0; }
                else if (id == 23) { mo_freeze = val != 0; }
                else if (id == 24) { mo_perc = val != 0; }
                else if (id == 26) { mo_move = val != 0; }
                else if (id == 27) { mo_fold_on = val != 0; }
                else if (id == 25) { pc_mode = val < 0 ? 0 : (val > 3 ? 3 : (int)val); }
              } break;
    case 'X': { long v = 0, pr = -1; int k = sscanf(s + 1, "%ld %ld", &v, &pr);    // CHAR: "X <0..1000> [preset 0..10]"
                if (v < 0) v = 0; if (v > 1000) v = 1000;
                if (k < 2) pr = preset;                                              // no preset given: the current one
                if (pr >= 0 && pr < 11) ch_v[pr] = (int16_t)v; } break;
    case 'Z': mo_sync = true; co_restart = true; dl_align = true; hd_align = true; fx_sync = true; break;
    case 'F': { long e = -1, id = -1, val = 0; int k = sscanf(s + 1, "%ld %ld %ld", &e, &id, &val);   // MULTI
                if (k >= 3 && e >= 0 && e < FX_N && id >= 0 && id < 8) {
                  if (val < 0) val = 0; if (val > 1000) val = 1000;
                  fx_p[e][id] = (int16_t)val; fx_update((int)e);
                } else if (e == 90 && k >= 2) { if (id >= 0 && id < FX_N) fx_want = (int)id; }
                else if (e == 91 && k >= 2) { float hz = clock_hz(); fx_xf_len = (int32_t)(hz * (0.02f + (id / 1000.0f) * (id / 1000.0f) * 2.0f)); }
                else if (e == 92) fx_capture = true;
                else if (e == 93) fx_trig = true;
                else if (e == 94 && k >= 2) fx_hold_app = id != 0;
                else if (e == 97 && k >= 2) ad_mode = id != 0 ? 1 : 0;   // ARP_DELAY: 0 = ARP (tap delay) · 1 = SPEECH (COCO)
                else if (e == 95 && k >= 2) fx_edepth = (int32_t)((id < 0 ? 0 : (id > 1000 ? 1000 : id)) * 256 / 1000);
                else if (e == 96 && k >= 2) { float hz = clock_hz(); float q = (id < 0 ? 0 : (id > 1000 ? 1000 : id)) / 1000.0f; fx_gap = (int32_t)(hz * (0.05f + q * q * 4.95f)); }
              } break;
    case 'C': { long id = -1, val = 0; sscanf(s + 1, "%ld %ld", &id, &val);   // coco parameter
                if (val < 0) val = 0; if (val > 1000) val = 1000;
                if (id >= 0 && id < 16) { co_p[id] = (int16_t)val; co_update(); }
                else if (id == 16) co_rev = val != 0;
                else if (id == 17) co_restart = true;
              } break;
    case 'Y': case 'N': case 'V': {
                long id = -1, val = 0; sscanf(s + 1, "%ld %ld", &id, &val);
                if (val < 0) val = 0; if (val > 1000) val = 1000;
                if (s[0] == 'Y' && id >= 0 && id < 13) { dl_p[id] = (int16_t)val; dl_update(); }
                if (s[0] == 'N' && id >= 0 && id < 16) { nz_p[id] = (int16_t)val; nz_update(); }
                if (s[0] == 'V' && id >= 0 && id < 14) { hd_p[id] = (int16_t)val; hd_update(); }
              } break;
    case 'K': { long b = atol(s + 1); if (b < 300) b = 300; if (b > 3000) b = 3000;
                cafe_bpm = b / 10.0f; dl_update(); hd_update(); fx_update_all(); } break;
    case 'D': {                            // read the tape back (saving a file on the phone): D <start> <n> -> d <start> <2 chars per sample>
                long st = 0, n = 0; sscanf(s + 1, "%ld %ld", &st, &n);
                if (n < 1) n = 1; if (n > 128) n = 128;
                char hb[300]; int k = snprintf(hb, sizeof(hb), "d %ld ", st);
                for (long i = 0; i < n && k < (int)sizeof(hb) - 3; i++) {
                  int v = dread((int)((st + i) & 0x1FFFF)) & 0xFFF;
                  hb[k++] = (char)(48 + (v >> 6)); hb[k++] = (char)(48 + (v & 63));
                }
                hb[k] = 0; pc_out(hb);
              } break;
    case 'W': {                            // write samples into the tape (file loading from the phone)
                // W <start> <2 chars per sample: each char = 48 + 6 bits, high then low>  ->  "w <start>"
                char *q = s + 1;
                long st = strtol(q, &q, 10);
                while (*q == ' ') q++;
                int n = 0;
                while (q[0] >= 48 && q[0] < 112 && q[1] >= 48 && q[1] < 112 && n < 256) {
                  dwrite((int)(st + n), ((q[0] - 48) << 6) | (q[1] - 48));
                  q += 2; n++;
                }
                char hb[24]; snprintf(hb, sizeof(hb), "w %ld", st); pc_out(hb);
              } break;
  }
}
void pc_service() {                       // called from loop(): lines that arrived over BLE
  RTC_DATA_ATTR static char bl[300]; static int bn = 0;            // long enough for a W line (128 samples)
  while (ble_rh != ble_wh) {
    char c = ble_rb[ble_rh]; ble_rh = (ble_rh + 1) & 1023;
    if (c == '\n' || c == '\r') { if (bn) { bl[bn] = 0; pc_line(bl); bn = 0; } }
    else if (bn < 299) bl[bn++] = c;
  }
}

// ---- BLE firmware update: the loop() side ----
static uint32_t ota_size = 0, ota_crc_want = 0, ota_crc = 0xFFFFFFFF, ota_done = 0, ota_acked = 0, ota_bad_ms = 0;
static void ota_fail(const char *why) {
  char b[96]; snprintf(b, sizeof(b), "U ERR %s", why); pc_out(b);
  Serial.printf("[ota] %s: restarting\n", why);
  Update.abort(); delay(400); ESP.restart();
}
static uint32_t ota_crc32(uint32_t c, const uint8_t *p, size_t n) {   // zlib CRC-32 (c starts at 0xFFFFFFFF)
  while (n--) { c ^= *p++; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1))); }
  return c;
}
void ota_cmd(char *s) {
  if (s[1] == ' ' && !ota_active) {
    unsigned long size = 0, crc = 0;
    if (sscanf(s + 1, "%lu %lx", &size, &crc) < 2 || size < 1024) { pc_out("U ERR bad start"); return; }
    const esp_partition_t *next = esp_ota_get_next_update_partition(NULL);
    if (!next) { pc_out("U ERR no OTA slot (partition scheme: Default)"); return; }
    if (size > next->size) { pc_out("U ERR too big for the slot"); return; }
    Serial.printf("[ota] start: %lu bytes -> %s\n", size, next->label);
    // stop the audio, give the tape's memory back (the Cafe restarts at the end anyway)
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    detachInterrupt(2);
    ota_active = true;
    for (int i = 0; i < DCHUNKS; i++) { if (dchunk[i] && dchunk[i] != dchunk_rtc) free(dchunk[i]); dchunk[i] = nullptr; }
    delaybuffa = delaybuffb = nullptr;
    ota_rb = (uint8_t *)malloc(OTA_RING);
    if (!ota_rb) ota_fail("no memory");
    if (!Update.begin(size, U_FLASH)) ota_fail(Update.errorString());
    ota_size = size; ota_crc_want = crc; ota_crc = 0xFFFFFFFF; ota_done = 0; ota_acked = 0;
    ota_wh = ota_rh = 0; ota_rx = 0; ota_bad = false; ota_last_ms = millis();
    char b[48]; snprintf(b, sizeof(b), "U OK %d", OTA_RING); pc_out(b);
  } else if (s[1] == ' ' ) {
    pc_out("U ERR busy");
  } else if (s[1] == 'X' && ota_active) {
    ota_fail("stopped");
  }
}
void ota_service() {                      // loop() while updating: ring -> flash
  static uint8_t *buf = nullptr;                   // taken from the freed tape memory when the update starts
  if (!buf) { buf = (uint8_t *)malloc(1024); if (!buf) ota_fail("no memory"); }
  uint32_t avail = ota_wh - ota_rh;
  while (avail) {
    uint32_t n = avail > 1024 ? 1024 : avail;
    for (uint32_t i = 0; i < n; i++) buf[i] = ota_rb[(ota_rh + i) & (OTA_RING - 1)];
    if (Update.write(buf, n) != n) ota_fail(Update.errorString());
    ota_crc = ota_crc32(ota_crc, buf, n);
    ota_rh += n; ota_done += n; avail -= n;
  }
  if (ota_done >= ota_acked + 4096 || (ota_done == ota_size && ota_acked != ota_done)) {
    ota_acked = ota_done;
    char b[32]; snprintf(b, sizeof(b), "U A %lu", (unsigned long)ota_done); pc_out(b);
    static bool lit = false; lit = !lit;                                    // the lamp flickers while it writes
    if (lit) REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); else REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1);
  }
  if (ota_bad && ota_wh == ota_rh && millis() - ota_bad_ms > 300) {       // a piece was lost: ask again from here
    ota_bad = false; ota_bad_ms = millis();
    char b[32]; snprintf(b, sizeof(b), "U R %lu", (unsigned long)ota_rx); pc_out(b);
  }
  if (ota_done >= ota_size) {
    uint32_t crc = ~ota_crc;
    if (crc != ota_crc_want) { char b[64]; snprintf(b, sizeof(b), "crc %08lx wanted %08lx", (unsigned long)crc, (unsigned long)ota_crc_want); ota_fail(b); }
    if (!Update.end(true)) ota_fail(Update.errorString());
    pc_out("U DONE");
    Serial.println("[ota] done: restarting into the new firmware");
    delay(600); ESP.restart();
  }
  if (millis() - ota_last_ms > 20000) ota_fail("timeout");
}

// ------------------------------------------
// PRESET PLAYLIST
// ------------------------------------------
// Eleven presets. Long-press the button, tap N times (count from 0), long-press again.
// The lamp blinks the number (1-11) in the menu and right after a preset is loaded. The phone switches with "G <n>".
//   1 = coco_mod  (startup preset)
//   2 = echo_og   (4-tap echo, organ on YELLOW with EARTH FM, FLIP deeper, SKIP wobble)
//   3 = BLE       (coco_pc: played from the phone. Modes: GRAIN / COCO / DELAY / NOISE)
//   4 = resonator
//   5 = formant   (ieat31415)
//   6 = saturator (ieat31415: BUTTON = next kind)
//   7 = harmony   (replay in intervals, after norns' rpls: two voices, interval + timing each)
//   8 = rungler   (coco chopped by an 8-bit shift register: FLIP = clock, SKIP = data)
//   9 = selfread  (the sound on the tape steers the play head: loaded files make their own paths)
//  10 = multi     (eight effects: FLIP = next, SKIP = random, crossfaded; EARTH modulates each)
//  11 = arpdelay  (MULTI's stereo tap delay for the phone's arpeggiator; SKIP = tap tempo, shared with the phone)
void (*playlist_main[])() = {
    coco_mod, echo_og, coco_pc, resonator, formant, saturator, harmony, rungler, selfread, multi, arpdelay
};

// ------------------------------------------
// PRESET PLAYLIST SELECTION TO LOAD
// ------------------------------------------
// Type the name of the playlist you want to load onto the Cafe: <<<<<<<<<<<<<<<<<<<<<<<<<----------
#define ACTIVE_PLAYLIST playlist_main




//////ORIGINAL FIRMWARE
// EARTH on core 0 (the audio interrupt lives on core 1): ADC2 channel 0 = GPIO 4, 1000x a second.
// Read from an esp_timer callback: the esp_timer task already runs on core 0, so no task (and no stack) of our own
// (v3.21–3.24 had one: 1.6 KB the Bluetooth heap missed).
static void earth_tick(void *) {
  int sum = 0, n = 0;                            // one conversion, 2000x a second (fast enough for audio-rate FM in ECHO)
  for (int k = 0; k < 1; k++) { int r = 0; if (adc2_get_raw(ADC2_CHANNEL_0, ADC_WIDTH_BIT_12, &r) == ESP_OK) { sum += r; n++; } }
  if (n) { earth_raw12 = sum / n; earth_now = earth_raw12 >> 4; } else earth_fail++;
}

void setup() {

  // FOR DEBUGGING
  Serial.begin(PC_BAUD);  // USB serial for coco-pc.html (same speed in the page / Serial Monitor)
  delay(1000); // Give the serial monitor a moment to connect
  Serial.printf("\n--- BOOT START --- (esp_cafe_duo %s, last reset reason %d)\n", FW_VERSION, (int)esp_reset_reason());
  Serial.printf("Initial Free Heap: %d bytes\n", ESP.getFreeHeap());

  // BLE test: start the radio FIRST (clean ADC for its calibration), then the Cafe hardware setup
  Serial.printf("[1b] Starting BLE... Free Heap before: %d bytes\n", ESP.getFreeHeap());
  // SKIP (GPIO 34) and FLIP (GPIO 35) are plain digital inputs. Their analog (RTC) setting survives a software
  // restart (v3.12 left GPIO 34 analog = SKIP dead), so give them back to the digital side at every start.
  rtc_gpio_deinit(GPIO_NUM_34); rtc_gpio_deinit(GPIO_NUM_35);
  pinMode(34, INPUT); pinMode(35, INPUT);
  pinMode(32, INPUT);                                  // BUTTON (GPIO 32), low = pressed
  delay(5);
  cafe_no_ble = true;                                  // held down for the whole 0.3 s = no Bluetooth
  for (int i = 0; i < 30 && cafe_no_ble; i++) { if (REG(GPIO_IN1_REG)[0] & 0x1) cafe_no_ble = false; delay(10); }
  if (cafe_no_ble) Serial.println("[1b] BUTTON held at power-on: Bluetooth OFF, original ADC setup (EARTH test)");
  else ble_begin();
  Serial.printf("[1b] BLE %s, name %s. Free Heap: %d bytes, largest block %u\n", ble_ok ? "advertising" : "FAILED", ble_name, ESP.getFreeHeap(), (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  Serial.println("[1] Running SETUPPERS (Hardware Init)...");

  SETUPPERS
  Serial.printf("[1] SETUPPERS Complete. Free Heap: %d bytes\n", ESP.getFreeHeap()); // FOR DEBUGGING
  // EARTH on ADC2 channel 0 (GPIO 4), 12 bits, 2.5 dB like the original pattern table (ADC2_PATT = 0x0D)
  // With Bluetooth: EARTH through the ADC2 driver (esp_timer). Without: NOT a single adc2 call — the driver takes
  // ADC2 over to the RTC side and the original path (the FIFO, read every sample) would then get no EARTH at all.
  if (!cafe_no_ble) {
    adc2_config_channel_atten(ADC2_CHANNEL_0, ADC_ATTEN_DB_2_5);
    esp_timer_create_args_t ta = {}; ta.callback = earth_tick; ta.name = "earth";
    esp_timer_handle_t th; if (esp_timer_create(&ta, &th) == ESP_OK) esp_timer_start_periodic(th, 500);
    int r = 0; esp_err_t e = adc2_get_raw(ADC2_CHANNEL_0, ADC_WIDTH_BIT_12, &r);
    if (e == ESP_OK) { earth_raw12 = r; earth_now = r >> 4; }
    Serial.printf("[1] EARTH (GPIO 4, ADC2) now %d / 4095 (%s)\n", r, e == ESP_OK ? "ok" : esp_err_to_name(e));
  }


  //theCoolWifiInitiation();

  // --------------------------------------------------------
  // BOOT STATE
  // --------------------------------------------------------
  if (CLASSIC_NOISE_BOOT) {
    // Noise frozen on startup
    Serial.println("    -> Booting with Classic Frozen Noise.");
    audio_frozen_state = true;
    lamp = true;
    FILLNOISE
  } 
  else {
    // Clear buffer on startup
    Serial.println("    -> Clearing buffer.");
    audio_frozen_state = false;
    lamp = false;
    
    // Wipe the uninitialized RAM with silence
    for (int i = 0; i < DELAYSIZE; i++) {
        dellius(i, 0, false);
    }

  }
  // --------------------------------------------------------

  // Pre-charge Ash Capacitor
  // Needed so ash doesn't need to wake up to send audio
  REG(ESP32_RTCIO_PAD_DAC1)
  [0] = BIT(10) | BIT(17) | BIT(18) | (64 << 19);  // 64 to get to linearity of LM3900 past the diode drop on input
  //END

  // FOR DEBUGGING
  Serial.println("[2] Routing Preset Playlist...");
  active_preset_count = sizeof(ACTIVE_PLAYLIST) / sizeof(ACTIVE_PLAYLIST[0]);
  Serial.printf("    Active Preset Count: %d\n", active_preset_count);


  // PRESET PLAYLIST ROUTER
  // counts the presets in the ACTIVE_PLAYLIST   
  pl_load();                                  // the playlist the phone chose (default: our 11)
  preset = pl_id[0]; preset_counter = 0;
  Serial.printf("[2] Routing Complete. Free Heap: %d bytes\n", ESP.getFreeHeap()); // FOR DEBUGGING

  DOUBLECLK

  Serial.println("[3] Starting Startup PRESETTER (Preset 0)..."); // FOR DEBUGGING

  // ------------------------------------------
  // ------------------------------------------
  // THIS IS THE STARTUP PRESET 
     for (int i = 0; i < 17; i++) mo_p[i] = mo_default[i];
     mo_fill_window();
     mo_update();
     bj_fill_table();
     bj_update();
     for (int i = 0; i < 13; i++) dl_p[i] = dl_default[i];
     for (int i = 0; i < 16; i++) nz_p[i] = nz_default[i];
     for (int i = 0; i < 14; i++) hd_p[i] = hd_default[i];
     for (int i = 0; i < 16; i++) co_p[i] = co_default[i];
     for (int e = 0; e < FX_N; e++) for (int i = 0; i < 8; i++) fx_p[e][i] = fx_default[e][i];
     all_update();
     PRESETTER(pool[preset])
  // ------------------------------------------
  // ------------------------------------------

  // FOR DEBUGGING
  Serial.printf("[3] PRESETTER Complete. Free Heap: %d bytes\n", ESP.getFreeHeap());
  Serial.println("[4] Running Boot Animation...");

  //BOOT ANIMATION
  for (int i = 0; i < 5; i++) {
    REG(GPIO_OUT1_W1TS_REG)
    [0] = BIT(1);
    delay(50);
    REG(GPIO_OUT1_W1TC_REG)
    [0] = BIT(1);
    delay(50);
  }

LAMPLIGHT_OVERRIDE;   // Sync the physical hardware following boot animation

Serial.println("--- BOOT COMPLETE: Entering Main Loop ---\n"); // FOR DEBUGGING
}

////////////


// ==========================================
// PRESET SELECTION MODE --- NEW FIRMWARE
// ==========================================
//------------------------------------------
// long press button
// lamp will flash
// press button number of times as the preset index

void loop() {

  pc_service();   // lines from the phone (BLE)
  if (ota_active) { ota_service(); delay(1); return; }   // firmware update: nothing else runs

  // latch the switches for the status line
  scope_sample();
  if (FLIPPERAT) seen_flip = true;
  if (SKIPPERAT) seen_skip = true;
  if (!(BUTTONEST)) seen_btn = true;

  // SKIP / FLIP stay digital inputs (in case an ADC call touched their pads)
  static uint32_t pin_t = 0;
  if (millis() - pin_t >= 200) {
    pin_t = millis();
    if (REG(RTC_IO_ADC_PAD_REG)[0] & (BIT(29) | BIT(28))) {        // GPIO 34 / 35 muxed to the RTC (analog) side (ADC1 / ADC2 mux_sel)
      rtc_gpio_deinit(GPIO_NUM_34); rtc_gpio_deinit(GPIO_NUM_35); pin_fix++;
    }
    REG(IO_MUX_GPIO34_REG)[0] |= FUN_IE; REG(IO_MUX_GPIO35_REG)[0] |= FUN_IE;   // input enabled
  }

  // EARTH: read by an esp_timer callback on core 0 (see earth_tick) — not here: adc2_get_raw holds a spinlock that
  // shuts interrupts off on its core for each conversion, and on this core that stalled the audio interrupt
  // 1000x a second (YELLOW's organ crackled).

  // GRAIN works in samples: keep its times right when the SPEED knob moves the clock
  static uint32_t hz_t = 0, hz_n = 0;
  if (millis() - hz_t >= 500) {
    uint32_t n = pc_samples;
    float hz = (n - hz_n) * 1000.0f / (float)(millis() - hz_t);
    hz_t = millis(); hz_n = n;
    if (hz > 1000 && fabsf(hz - mo_hz) > mo_hz * 0.03f) { mo_hz = hz; all_update(); }
  }
  // (no more fighting the radio for ADC2: EARTH is read on ADC1 alone now, see CTRLJING in setup.h)
  // EARTH test over USB: once a second, the raw word and the ADC registers (Serial Monitor, 115200)
  static uint32_t dbg_t = 0;
  if (millis() - dbg_t >= 1000) {
    dbg_t = millis();
    Serial.printf("[earth] %s a4 %4lu fail %lu earth %d flip %d skip %d | sarctl %08lx rd1 %08lx rd2 %08lx st1 %08lx st2 %08lx wait2 %08lx i2s %08lx\n",
      cafe_no_ble ? "noBLE" : "BLE", (unsigned long)pc_fifo, (unsigned long)earth_fail, (int)pc_earth, (FLIPPERAT) ? 1 : 0, (SKIPPERAT) ? 1 : 0,
      (unsigned long)REG(APB_SARADC_CTRL_REG)[0], (unsigned long)REG(SENS_SAR_READ_CTRL_REG)[0], (unsigned long)REG(SENS_SAR_READ_CTRL2_REG)[0],
      (unsigned long)REG(SENS_SAR_MEAS_START1_REG)[0], (unsigned long)REG(SENS_SAR_MEAS_START2_REG)[0],
      (unsigned long)REG(SENS_SAR_MEAS_WAIT2_REG)[0], (unsigned long)REG(I2S_CONF_REG)[0]);
  }

  // SKIP was tapped twice (DELAY / HARMONY): that is the tempo now, and the delay follows it
  if (tap_samples > 0) {
    int32_t d = tap_samples; tap_samples = 0;
    float bpm = 60.0f * clock_hz() / d;
    while (bpm < 40.0f) bpm *= 2.0f;
    while (bpm > 240.0f) bpm *= 0.5f;
    cafe_bpm = bpm;
    if (dl_p[8] < 500) dl_p[8] = 1000;
    if (hd_p[11] < 500) hd_p[11] = 1000;
    dl_update(); hd_update(); fx_update_all();
    Serial.printf("[tap] %.1f bpm\n", bpm);
  }

  // the phone switched presets ("G <n>"): load it the same way the menu does
  if (pc_goto >= 0 && !preset_mode) {
    int n = pc_goto; pc_goto = -1;
    if (n != preset) {
      REG(I2S_CONF_REG)[0] &= ~(BIT(5));
      detachInterrupt(2);
      preset = n; { int k = pl_index(n); if (k >= 0) preset_counter = k; }
      preset_gen++;
      PRESETTER(pool[preset]);
      REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
      REG(I2S_CONF_REG)[0] |= (BIT(5));
      Serial.printf("[phone] preset %d\n", preset + 1);
    }
  }


  // LONG PRESS INDICATOR
  // If the button is held down, watch the hardware timer.
  if (is_pressed && !preset_mode) {
    REG(TIMG0_T0UPDATE_REG)[0] = BIT(1);
    uint32_t current_time = REG(TIMG0_T0LO_REG)[0];
    
    // Handle timer overflow
    uint32_t hold_time = current_time - press_time;
    if (current_time < press_time) hold_time = (0xFFFFFFFF - press_time) + current_time;

    // Once held past 0.8 seconds (2,000,000 ticks), flash lamp rapidly
    if (hold_time > 2000000) {
      // 250,000 ticks = 100ms
      lamp = ((current_time % 250000) > 125000); 
      LAMPLIGHT_OVERRIDE; //
    }
  }

  // --- PRESET SELECTION MODE ---
  if (preset_mode) {
    
    Serial.println("Preset Mode Active: Waiting for physical button punch-in...");

    // variables for visual feedback
    int blink_state = 0; // 0=Pause, 1=Tens ON, 2=Tens OFF, 3=Ones ON, 4=Ones OFF
    int blink_count = 0;
    int tick_timer = 0;

    int flash_tick = 0;

    // The Latching Loop
    while (preset_mode) {
      bool threshold_met = false;
      
      // --- LONG PRESS INDICATOR ---
      if (is_pressed) {
        REG(TIMG0_T0UPDATE_REG)[0] = BIT(1);
        uint32_t current_time = REG(TIMG0_T0LO_REG)[0];
        
        uint32_t hold_time = current_time - press_time;
        if (current_time < press_time) hold_time = (0xFFFFFFFF - press_time) + current_time;

        if (hold_time > 2000000) {
          // Override the slow stutter with the rapid strobe to say "Let Go!"
          lamp = ((current_time % 250000) > 125000); 
          LAMPLIGHT_OVERRIDE; //
          threshold_met = true;
        }
      }


      // PRESET BLINKER FOR VISUAL FEEDBACK
      if (!threshold_met && !is_pressed) {
          
          // Calculate the actual human-readable preset number (1 to 24)
          int display_num = (preset_counter % active_preset_count) + 1; // 1..6 blinks (1 = coco_mod)
          int tens = display_num / 10;
          int ones = display_num % 10;

          tick_timer++; // Increments roughly every 10ms due to vTaskDelay

          if (blink_state == 0) { 
              // State 0: Long pause (1 second) before repeating the pattern
              lamp = false;
              if (tick_timer > 100) { tick_timer = 0; blink_state = 1; blink_count = 0; }
          }
          else if (blink_state == 1) { 
              // State 1: Tens ON (Long Blink - 400ms)
              if (tens == 0) { blink_state = 3; tick_timer = 0; blink_count = 0; } // Skip to ones
              else {
                  lamp = true;
                  if (tick_timer > 40) { tick_timer = 0; blink_state = 2; }
              }
          }
          else if (blink_state == 2) { 
              // State 2: Tens OFF (Gap - 200ms)
              lamp = false;
              if (tick_timer > 20) { 
                  tick_timer = 0; 
                  blink_count++;
                  if (blink_count < tens) blink_state = 1; // Loop back for next Ten
                  else { blink_state = 3; blink_count = 0; tick_timer = -30; } // Extra 300ms gap before Ones
              }
          }
          else if (blink_state == 3) { 
              // State 3: Ones ON (Short Blink - 150ms)
              if (ones == 0) { blink_state = 0; tick_timer = 0; } // Skip back to start
              else {
                  lamp = true;
                  if (tick_timer > 15) { tick_timer = 0; blink_state = 4; }
              }
          }
          else if (blink_state == 4) { 
              // State 4: Ones OFF (Gap - 200ms)
              lamp = false;
              if (tick_timer > 20) {
                  tick_timer = 0;
                  blink_count++;
                  if (blink_count < ones) blink_state = 3; // Loop back for next One
                  else blink_state = 0; 
              }
          }
          
          LAMPLIGHT_OVERRIDE;
          
      } else if (is_pressed && !threshold_met) {
          // If actively tapping, reset
          blink_state = 0;
          tick_timer = 0;
      }
      
      // Yield to FreeRTOS to prevent watchdog resets
      vTaskDelay(10); 
    }

    Serial.printf("Exiting mode. Loading preset index: %d\n", preset_counter);


    Serial.printf("Exiting mode. Loading preset index: %d\n", preset_counter);

    // EXIT PRESET SELECTION MODE
    // When done tapping, pause the system for 1 microsecond
    // to format the memory and load the new preset

    REG(I2S_CONF_REG)[0] &= ~(BIT(5)); // Pause I2S
    detachInterrupt(2);                // Pause Clock

    // Load the new preset safely while everything is paused
    preset_gen++;
    PRESETTER(pool[preset]);


    // Resume Audio Engine
    lamp = audio_frozen_state; 
    LAMPLIGHT_OVERRIDE; 
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF; 
    REG(I2S_CONF_REG)[0] |= (BIT(5));     

    // PRESET NUMBER BLINK: 1..6 flashes = the preset you just landed on
    // (audio keeps running; presets leave the lamp alone while this runs)
    os_blink_active = true;
    REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1);
    delay(250);
    for (int i = 0; i <= preset && !preset_mode; i++) {
      REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1);
      delay(80);
      REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1);
      delay(120);
    }
    delay(200);
    os_blink_active = false;
    lamp = audio_frozen_state;
    LAMPLIGHT_OVERRIDE;
  }

  delay(1);
}

//------------------------------------------
