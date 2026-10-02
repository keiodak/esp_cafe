// ##### FIRMWARE VERSION ###########################
// #####   CAFE BLE   v1.0   (2026-10-02)
// #####   (= FW_VERSION below; bump both together)
// ###################################################
//
// CAFE BLE (k.odk) — a small, plain starting point for the Ciat-Lonbarde Cafe's ESP32, for anyone who wants to build
// on it: two presets and an optional Bluetooth LE link, nothing else.
//
//   PRESETS   1 COCO_MOD (coco: a looper; EARTH = record, YELLOW = a clock)
//             2 ECHO     (four-tap echo; YELLOW = an organ, EARTH = its pitch, FLIP deeper, SKIP wobble)
//             BUTTON menu as on Apple π: long-press, tap N times, long-press again (the lamp blinks the number).
//
//   BLUETOOTH is off unless BUTTON is held down while the Cafe powers on (~0.3 s). Then:
//             - the radio is started first, then the Cafe's own setup (see BLE.md in the repository for why)
//             - EARTH (GPIO 4 = ADC2 ch 0) is read by the IDF driver from a timer on core 0, 2000x a second;
//               the sound's DMA pattern table runs on ADC1 only (the radio takes ADC2)
//             - it advertises as "Cafe-XXXX" with the Nordic UART Service (6E400001-…); one text line per command:
//                 P            -> "HELLO cafe-ble <version> <name> ota"
//                 H            -> heap, link, EARTH
//                 G <0|1>      -> go to COCO_MOD / ECHO
//                 U …          -> firmware update over Bluetooth (6E400004-…, see ota_cmd; Partition Scheme: Default)
//             Add your own commands in pc_line().
//           Without Bluetooth everything is as the original firmware: radio clocks off, EARTH read every sample.
//
//   Arduino IDE, board "ESP32 Dev Module", ESP32 core 2.0.9, library NimBLE-Arduino (2.3.x). Keep build_opt.h.
//
// Built on: the original Cafe firmware (Peter Blasser, Ciat-Lonbarde) and Apple π (ieat31415).
// ==========================================

// The original Cocoquantus booted with its delay buffer frozen and filled with noise.
// This boots unfrozen (the buffer cleared). Change to 'true' for the classic frozen noise boot.
#define CLASSIC_NOISE_BOOT false

#include "synths.h"

#define PC_BAUD 115200                // USB: boot messages only (Serial Monitor)
#define FW_VERSION "1.0"

// ==========================================
// BLE LINK (k.odk) --- text lines over the Nordic UART Service (only when BUTTON was held at power-on)
// ==========================================
// Needs the library "NimBLE-Arduino" (Library Manager). The Cafe advertises as "Cafe-XXXX".
// The BLE task (core 0) only copies what arrives into ble_rb; loop() reads whole lines out of it (pc_service).
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
    ble_mtu = 23; ble_conn = true; ble_itvl = ci.getConnInterval();
    s->updateConnParams(ci.getConnHandle(), 12, 12, 0, 300);   // ask for 15 ms between radio exchanges (less lag)
    Serial.printf("[ble] connected, interval %u x1.25ms. heap %u largest %u\n", (unsigned)ble_itvl, (unsigned)ESP.getFreeHeap(), (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  }
  void onDisconnect(NimBLEServer *s, NimBLEConnInfo &ci, int reason) override {
    ble_conn = false;
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
void pc_out(const char *s) { ble_line(s); }       // replies go out as notifications


// ------------------------------------------
// THE PRESETS (pool ids 0, 1 — the BUTTON menu and "G <n>" use these)
// ------------------------------------------
void (*pool[])() = { coco_mod, echo_og };
#define POOL_N ((int)(sizeof(pool) / sizeof(pool[0])))

// ==========================================
// THE LINK: one text line per command (from the BLE task through ble_rb into loop())
// ==========================================
volatile int pc_goto = -1;                  // "G <n>": the phone asks for preset n (handled in loop)
void ota_cmd(char *s);
void pc_line(char *s) {
  if (s[0] == 'U') { ota_cmd(s); return; }
  if (ota_active) return;                   // updating: nothing else
  switch (s[0]) {
    case 'P': { char hb[48]; snprintf(hb, sizeof(hb), "HELLO cafe-ble %s %s ota", FW_VERSION, ble_name); pc_out(hb); } break;
    case 'H': { char hb[120]; snprintf(hb, sizeof(hb), "H heap %u min %u mtu %d interval_ms %d earth %d fail %lu preset %d",
                (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMinFreeHeap(), (int)ble_mtu, (int)(ble_itvl * 5 / 4),
                (int)EARTHREAD, (unsigned long)earth_fail, preset);
                pc_out(hb); } break;
    case 'G': { long n = atol(s + 1); if (n >= 0 && n < POOL_N) pc_goto = (int)n; } break;
    // add your own here: "X <id> <value>" … (keep them short — a line is at most ~240 bytes)
  }
}
void pc_service() {                         // called from loop(): lines that arrived over BLE
  static char bl[256]; static int bn = 0;
  while (ble_rh != ble_wh) {
    char c = ble_rb[ble_rh]; ble_rh = (ble_rh + 1) & 1023;
    if (c == '\n' || c == '\r') { if (bn) { bl[bn] = 0; pc_line(bl); bn = 0; } }
    else if (bn < 255) bl[bn++] = c;
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


// EARTH with Bluetooth: ADC2 channel 0 (GPIO 4) through the IDF driver, from an esp_timer callback on core 0
static void earth_tick(void *) {
  int sum = 0, n = 0;                            // one conversion, 2000x a second (fast enough for audio-rate FM in ECHO)
  for (int k = 0; k < 1; k++) { int r = 0; if (adc2_get_raw(ADC2_CHANNEL_0, ADC_WIDTH_BIT_12, &r) == ESP_OK) { sum += r; n++; } }
  if (n) { earth_raw12 = sum / n; earth_now = earth_raw12 >> 4; } else earth_fail++;
}


void setup() {
  Serial.begin(PC_BAUD);
  delay(1000);
  Serial.printf("\n--- BOOT --- (cafe_ble %s, last reset reason %d)\n", FW_VERSION, (int)esp_reset_reason());

  // SKIP (GPIO 34) and FLIP (GPIO 35) are plain digital inputs; their analog (RTC) setting survives a software
  // restart (an update ends in one), so give them back to the digital side at every start.
  rtc_gpio_deinit(GPIO_NUM_34); rtc_gpio_deinit(GPIO_NUM_35);
  pinMode(34, INPUT); pinMode(35, INPUT);
  pinMode(32, INPUT);                                   // BUTTON (GPIO 32), low = pressed
  delay(5);
  // BUTTON held for the whole 0.3 s at power-on = Bluetooth; otherwise none (as the original firmware)
  bool held = true;
  for (int i = 0; i < 30 && held; i++) { if (REG(GPIO_IN1_REG)[0] & 0x1) held = false; delay(10); }
  cafe_no_ble = !held;
  if (!cafe_no_ble) ble_begin();                        // the radio FIRST, then the Cafe's hardware
  Serial.printf("[ble] %s%s\n", cafe_no_ble ? "off (hold BUTTON at power-on to turn it on)" : (ble_ok ? "advertising as " : "FAILED "), cafe_no_ble ? "" : ble_name);

  SETUPPERS
  if (!cafe_no_ble) {                                   // EARTH through the ADC2 driver (never touched without BLE)
    adc2_config_channel_atten(ADC2_CHANNEL_0, ADC_ATTEN_DB_2_5);
    esp_timer_create_args_t ta = {}; ta.callback = earth_tick; ta.name = "earth";
    esp_timer_handle_t th; if (esp_timer_create(&ta, &th) == ESP_OK) esp_timer_start_periodic(th, 500);
  }

  if (CLASSIC_NOISE_BOOT) { audio_frozen_state = true; lamp = true; FILLNOISE }
  else { audio_frozen_state = false; lamp = false; for (int i = 0; i < DELAYSIZE; i++) dellius(i, 0, false); }

  // pre-charge the ASH capacitor (so ASH doesn't need to wake up to send audio)
  REG(ESP32_RTCIO_PAD_DAC1)[0] = BIT(10) | BIT(17) | BIT(18) | (64 << 19);

  active_preset_count = POOL_N;
  for (int i = 0; i < POOL_N; i++) { pl_id[i] = i; presets[i] = pool[i]; }
  preset = 0; preset_counter = 0;
  DOUBLECLK
  PRESETTER(pool[preset])

  for (int i = 0; i < 5; i++) {                         // the boot blink
    REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); delay(50);
    REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1); delay(50);
  }
  LAMPLIGHT_OVERRIDE;
  Serial.printf("--- BOOT COMPLETE (heap %u) ---\n", (unsigned)ESP.getFreeHeap());
}

// load pool[preset] the way the menu does: the audio paused for the moment
static void load_preset() {
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  detachInterrupt(2);
  PRESETTER(pool[preset]);
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}

void loop() {
  if (!cafe_no_ble) {
    pc_service();                                       // lines from the phone
    if (ota_active) { ota_service(); delay(1); return; }   // firmware update: nothing else runs
    static uint32_t pin_t = 0;                          // SKIP / FLIP stay digital (an ADC call may touch their pads)
    if (millis() - pin_t >= 200) {
      pin_t = millis();
      if (REG(RTC_IO_ADC_PAD_REG)[0] & (BIT(29) | BIT(28))) { rtc_gpio_deinit(GPIO_NUM_34); rtc_gpio_deinit(GPIO_NUM_35); pin_fix++; }
      REG(IO_MUX_GPIO34_REG)[0] |= FUN_IE; REG(IO_MUX_GPIO35_REG)[0] |= FUN_IE;
    }
    if (pc_goto >= 0 && !preset_mode) {                 // "G <n>"
      int n = pc_goto; pc_goto = -1;
      if (n != preset) { preset = n; preset_counter = n; load_preset(); }
    }
  }

  // BUTTON held: the lamp flickers once it counts as a long press (0.8 s)
  if (is_pressed && !preset_mode) {
    REG(TIMG0_T0UPDATE_REG)[0] = BIT(1);
    uint32_t now = REG(TIMG0_T0LO_REG)[0];
    if (now - press_time > 2000000) { lamp = ((now % 250000) > 125000); LAMPLIGHT_OVERRIDE; }
  }

  // --- THE PRESET MENU: long-press, tap N times, long-press again (doubleclicker in stuff.h counts) ---
  if (preset_mode) {
    int tick = 0;
    while (preset_mode) {
      bool letgo = false;
      if (is_pressed) {                                 // held long enough: a fast flicker says "let go"
        REG(TIMG0_T0UPDATE_REG)[0] = BIT(1);
        uint32_t now = REG(TIMG0_T0LO_REG)[0];
        if (now - press_time > 2000000) { lamp = ((now % 250000) > 125000); LAMPLIGHT_OVERRIDE; letgo = true; }
      }
      if (!letgo && !is_pressed) {                      // the number chosen so far, blinked: 1 or 2, then a pause
        int n = (preset_counter % active_preset_count) + 1;
        int step = tick % 160;                          // (10 ms a tick)
        lamp = step < n * 40 && (step % 40) < 15;
        LAMPLIGHT_OVERRIDE;
        tick++;
      } else tick = 0;
      vTaskDelay(10);
    }
    load_preset();                                      // (doubleclicker set "preset")
    lamp = audio_frozen_state;
    os_blink_active = true;                             // the preset's number, once
    REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1); delay(250);
    for (int i = 0; i <= preset && !preset_mode; i++) {
      REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); delay(80);
      REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1); delay(120);
    }
    os_blink_active = false;
    LAMPLIGHT_OVERRIDE;
  }
  delay(1);
}
