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

// BLE TEST BUILD (esp_cafe_ble). The USB-only version is in esp_cafe_apple_pi / backup_2026-09-25_serial_ok.
// USB serial speed. 921600 garbled on this Cafe, 115200 works.
#define PC_BAUD 115200

// ==========================================
// BLE LINK (k.odk, test) --- the same text protocol as USB, over the Nordic UART Service
// ==========================================
// Needs the library "NimBLE-Arduino" (Library Manager). The Cafe advertises as "Cafe-XXXX".
// Replies go back to wherever the command came from (USB or BLE).
#include <NimBLEDevice.h>
#define NUS_SVC "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"   // computer -> Cafe (write)
#define NUS_TX  "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"   // Cafe -> computer (notify)
static NimBLECharacteristic *ble_tx = nullptr;
static volatile bool ble_conn = false;
static volatile uint16_t ble_mtu = 23;
static volatile uint16_t ble_itvl = 0;          // connection interval, units of 1.25 ms
static bool ble_ok = false;
static char ble_name[16] = "Cafe";
static char ble_rb[512];                           // bytes written by the BLE task (core 0), read in loop()
static volatile uint16_t ble_wh = 0, ble_rh = 0;
static uint8_t pc_src = 0;                         // 0 = USB, 1 = BLE

class CafeServerCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *s, NimBLEConnInfo &ci) override {
    ble_mtu = 23; ble_conn = true; ble_itvl = ci.getConnInterval();
    s->updateConnParams(ci.getConnHandle(), 12, 12, 0, 300);   // ask for 15 ms between radio exchanges (less lag)
    Serial.printf("[ble] connected, interval %u x1.25ms. heap %u largest %u\n", (unsigned)ble_itvl, (unsigned)ESP.getFreeHeap(), (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  }
  void onDisconnect(NimBLEServer *s, NimBLEConnInfo &ci, int reason) override {
    ble_conn = false;
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
      uint16_t n = (ble_wh + 1) & 511;
      if (n == ble_rh) break;                      // full: drop the rest
      ble_rb[ble_wh] = (char)d[i]; ble_wh = n;
    }
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
  static char tmp[1024];
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
void pc_out(const char *s) {
  if (pc_src == 1) ble_line(s);
  else Serial.println(s);
}

// ==========================================
// PC LINK (k.odk) --- USB serial protocol for coco-pc.html
// ==========================================
// REQUEST / REPLY only: the Cafe never talks unless asked (the HELLO path is the one that proved to work).
// computer -> Cafe (one line each):
//   P            ping            -> "HELLO coco-pc 2"
//   Q            poll            -> one status line "T ..." and one overview chunk "O <bin> <hex>"
//   S <milli>    play speed x1000 (1000 = 1x, -500 = half speed backwards), -8000..8000
//   L <a> <b>    loop region in samples, 0..131072
//   J <pos>      jump the play head
//   R <0|1>      recording off/on
//   D <start>    send 256 samples from <start> -> "B <start> <hex 3 chars/sample>"
//   X <id> <v>   sound: 0 fold 0..1000, 1 bias -1000..1000, 2 overdub 0..1000, 3 delay time 0..1000, 4 delay amount 0..1000
// T wpos ppos rec ls le speed earth flip skip button samples preset
void pc_status() {
  char tb[128];
  snprintf(tb, sizeof(tb), "T %lu %lu %d %ld %ld %ld %d %d %d %d %lu %d",
    (unsigned long)pc_wpos, (unsigned long)pc_ppos, (pc_rec && !audio_frozen_state) ? 1 : 0,
    (long)pc_ls, (long)pc_le, (long)(pc_speed * 1000 / 4096),
    (int)pc_earth, (int)pc_flip, (int)pc_skip, (BUTTONEST) ? 0 : 1, (unsigned long)pc_samples, preset);
  pc_out(tb);
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
void pc_dump(long start) {
  static const char *hx = "0123456789ABCDEF";
  static char buf[16 + 256 * 3];
  if (start < 0) start = 0; if (start > 131072 - 256) start = 131072 - 256;
  int n = snprintf(buf, 16, "B %ld ", start);
  for (int i = 0; i < 256; i++) {
    int v = dread(start + i);
    buf[n++] = hx[(v >> 8) & 15]; buf[n++] = hx[(v >> 4) & 15]; buf[n++] = hx[v & 15];
  }
  buf[n] = 0;
  pc_out(buf);
}
void pc_line(char *s) {
  switch (s[0]) {
    case 'P': { char hb[48]; snprintf(hb, sizeof(hb), "HELLO coco-pc 3 %s %s", pc_src ? "ble" : "usb", ble_name); pc_out(hb); } break;
    case 'H': { char hb[128]; snprintf(hb, sizeof(hb), "H heap %u min %u ble %d conn %d mtu %d interval_ms %d earth %d clock_ms %lu",
                (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMinFreeHeap(), ble_ok, ble_conn ? 1 : 0, (int)ble_mtu, (int)(ble_itvl * 5 / 4), (int)pc_earth,
                (unsigned long)(esp_timer_get_time() / 1000));
                pc_out(hb); } break;
    case 'Q': pc_status(); pc_overview(); break;
    case 'S': { long m = atol(s + 1); if (m > 8000) m = 8000; if (m < -8000) m = -8000;
                pc_speed = (int32_t)((m * 4096) / 1000); } break;
    case 'L': { long a = 0, b = 0; sscanf(s + 1, "%ld %ld", &a, &b);
                if (a < 0) a = 0; if (b > 131072) b = 131072; if (b - a < 512) b = a + 512;
                if (b > 131072) { b = 131072; a = b - 512; }
                pc_ls = a; pc_le = b; } break;
    case 'J': { long p = atol(s + 1); if (p < 0) p = 0; if (p > 131071) p = 131071; pc_jump = p; } break;
    case 'R': pc_rec = atol(s + 1) != 0; break;
    case 'D': pc_dump(atol(s + 1)); break;
    case 'X': { long id = -1, val = 0; sscanf(s + 1, "%ld %ld", &id, &val);      // sound shaping, val 0..1000
                if (val < -1000) val = -1000; if (val > 1000) val = 1000;
                long u = val < 0 ? 0 : val;
                switch (id) {
                  case 0: pc_fold_g = 256 + (u * 1792) / 1000; break;           // fold 1x..8x
                  case 1: pc_bias = (val * 2048) / 1000; break;                 // bias -1000..1000
                  case 2: pc_dub = 256 - (u * 224) / 1000; break;               // 0 = replace .. 1000 = keep most of the old sound
                  case 3: pc_dt = 8 + (u * (PC_DLEN - 16)) / 1000; break;        // delay time
                  case 4: pc_dfb = (u * 235) / 1000; pc_dwet = u ? 96 + (u * 160) / 1000 : 0; break;   // delay amount
                }
              } break;
  }
}
void pc_service() {                       // called from loop(): only reads, replies come from pc_line
  static char line[48]; static int ln = 0;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') { if (ln) { line[ln] = 0; pc_line(line); ln = 0; } }
    else if (ln < 47) line[ln++] = c;
  }
  static char bl[48]; static int bn = 0;          // the same for BLE
  while (ble_rh != ble_wh) {
    char c = ble_rb[ble_rh]; ble_rh = (ble_rh + 1) & 511;
    if (c == '\n' || c == '\r') { if (bn) { bl[bn] = 0; pc_src = 1; pc_line(bl); pc_src = 0; bn = 0; } }
    else if (bn < 47) bl[bn++] = c;
  }
}

// ------------------------------------------
// PRESET PLAYLIST
// ------------------------------------------
// Trimmed to six presets. Long-press the button, tap N times (count from 0), long-press again.
//   0 = coco_mod  (startup preset)
//   1 = echo_og
//   2 = resonator
//   3 = rungler (coco chopped by a shift register)
//   4 = selfread (the tape steers its own playhead)
//   5 = coco_pc (remote control from a computer: coco-pc.html)
void (*playlist_main[])() = {
    coco_mod, echo_og, resonator, rungler, selfread, coco_pc
};

// ------------------------------------------
// PRESET PLAYLIST SELECTION TO LOAD
// ------------------------------------------
// Type the name of the playlist you want to load onto the Cafe: <<<<<<<<<<<<<<<<<<<<<<<<<----------
#define ACTIVE_PLAYLIST playlist_main




//////ORIGINAL FIRMWARE
void setup() {

  // FOR DEBUGGING
  Serial.begin(PC_BAUD);  // USB serial for coco-pc.html (same speed in the page / Serial Monitor)
  delay(1000); // Give the serial monitor a moment to connect
  Serial.printf("\n--- BOOT START ---\n");
  Serial.printf("Initial Free Heap: %d bytes\n", ESP.getFreeHeap());

  // BLE test: start the radio FIRST (clean ADC for its calibration), then the Cafe hardware setup
  Serial.printf("[1b] Starting BLE... Free Heap before: %d bytes\n", ESP.getFreeHeap());
  ble_begin();
  Serial.printf("[1b] BLE %s, name %s. Free Heap: %d bytes, largest block %u\n", ble_ok ? "advertising" : "FAILED", ble_name, ESP.getFreeHeap(), (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  Serial.println("[1] Running SETUPPERS (Hardware Init)...");

  SETUPPERS
  Serial.printf("[1] SETUPPERS Complete. Free Heap: %d bytes\n", ESP.getFreeHeap()); // FOR DEBUGGING


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
  active_preset_count = sizeof(ACTIVE_PLAYLIST) / sizeof(ACTIVE_PLAYLIST[0]);
  
  for (int i = 0; i < active_preset_count; i++) {
      presets[i] = ACTIVE_PLAYLIST[i];
  }  
  Serial.printf("[2] Routing Complete. Free Heap: %d bytes\n", ESP.getFreeHeap()); // FOR DEBUGGING

  DOUBLECLK

  Serial.println("[3] Starting Startup PRESETTER (Preset 0)..."); // FOR DEBUGGING

  // ------------------------------------------
  // ------------------------------------------
  // THIS IS THE STARTUP PRESET 
     PRESETTER(presets[0])
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

  pc_service();   // USB link to coco-pc.html (request / reply)


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
    PRESETTER(presets[preset]);


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
