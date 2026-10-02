#include "stuff.h"
#include <esp_attr.h>
#include <esp_timer.h>

// cafe_ble: two presets only — COCO_MOD (coco, from Apple π) and ECHO (the original echo + an organ on YELLOW)

// ==========================================
// 1. COCO - modified
// ==========================================
// same as coco, just with changes below
// yellow is a clock pulse
// earth is record on/off switch
// ash is clean audio output

void IRAM_ATTR coco_mod() {


 //INTABRUPT
 //REG(GPIO_STATUS_W1TC_REG)[0]=0xFFFFFFFF; 

 DACWRITER(pout)
 gyo=ADCREADER // Audio Input signal is read here

// --- WAKE UP & BOOT SYNC ---
    static bool is_first_run = true;
    static bool last_frozen = false; //added memory state
    static int smoothed_earth = -1;    // for Earth Smoothing 
    if (is_first_run) {
        is_first_run = false;
        // Pre-read the Earth knob to anchor the state without toggling the lamp
        if (EARTHREAD > TRIGGER_ON_THRESHOLD) {
            earth_last_state = 1;
        } else {
            earth_last_state = 0;
        }
    }

// EARTHREAD SLEW
// Needed to prevent false triggers 
int raw_earth = EARTHREAD; 

if (smoothed_earth == -1) {
    smoothed_earth = raw_earth; 
} else {
    smoothed_earth += (raw_earth - smoothed_earth) >> 4; // LPF
}

// HYSTERESIS (Using earth_cv)
 if (earth_last_state == 0) {
     if (smoothed_earth > TRIGGER_ON_THRESHOLD) {
         lamp = !lamp; 
         audio_frozen_state = lamp;
        if (lamp) { LAMP_ON; } 
        else { LAMP_OFF; }
         earth_last_state = 1; 
     }
 } 
 else { 
     if (smoothed_earth < TRIGGER_OFF_THRESHOLD) {
         earth_last_state = 0; 
     }
 }

 // --- CLICK-FREE LOOP (k.odk) ---
 // freeze: the recording gain ramps (~6ms) instead of Peter's xfado
 // SKIP loop point: the jump back crossfades the old head into the new one (~6ms),
 // and the recording is spliced the same way, so no hard edge is left on the tape
 static int32_t rg = 256;
 static int32_t tail = 0;
 static int xf = 0;
 static bool jump_pending = false;
 if (audio_frozen_state != last_frozen) last_frozen = audio_frozen_state;
 if (audio_frozen_state) { if (rg > 0) rg--; } else { if (rg < 256) rg++; }
 int dir = FLIPPERAT ? -1 : 1;           //inverted to make work with sampler based presets

 if (xf > 0) {
   int32_t on = dread(t);
   int32_t ot = dread(tail);
   int32_t gt = (rg * xf) >> 8;
   int32_t gh = (rg * (256 - xf)) >> 8;
   if (gt) dwrite(tail, ot + (((gyo - ot) * gt) >> 8));
   int32_t on2 = dread(t);
   if (gh) dwrite(t, on2 + (((gyo - on2) * gh) >> 8));
   pout = (on * (256 - xf) + ot * xf) >> 8;
   tail = (tail + dir) & 0x1FFFF;
   xf--;
 } else {
   int32_t v = dread(t);
   if (rg) dwrite(t, v + (((gyo - v) * rg) >> 8));
   pout = v;
 }
 t = (t + dir) & 0x1FFFF;

 if (SKIPPERAT)  {
  if (lastskp==0) delayskp = t;
  lastskp = 1;
 } else {
  if (lastskp) jump_pending = true;
  lastskp = 0;
 }
 if (jump_pending && xf == 0) {          // jump back to the loop point, crossfaded
   jump_pending = false;
   tail = t; xf = 256;
   t = delayskp;
 }


ASHWRITER(pout); //Sends wet audio through ASH. Try swapping out with other Ashes

//MODIFIED FIRMWARE

// Set desired clock division (PPQN where the length of the buffer is considered 1 bar (4 quarter notes))
// Use these options below: 13 (4 PPQN), 15 (1 PPQN), 17 (0.25 PPQN)
// external_sync preset assumes 13 (4 PPQN) to sync together the buffers
static uint8_t clock_shift = 13; 

// Dynamically calculate the window and mask based on the shift
uint32_t window_size = 1 << clock_shift;
uint32_t clock_mask = window_size - 1;

// --- YELLOW VARIABLE SYNC CLOCK ---
// Send this to any clocked device
// Try sending to Clicker as a metronome to play in time with the coco buffer
if ((t & clock_mask) < 2000) { 
    // if DOWNBEAT (checks if we are in the very first window of the buffer)
    if (t < window_size) {
        YELLOW_AUDIO(4095); // 3.3V accent
    } else {
        YELLOW_AUDIO(3000); // 2.4V clock
    }
} else {
    YELLOW_AUDIO(0); 
}

///////////END MODIFIED
 
 // HEARTBEAT
 REG(I2S_CONF_REG)[0] &= ~(BIT(5)); 
 REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= (BIT(5)); //start rx 
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

///////ORINGAL FIRMWARE
int myNumbers[] = {32000, 31578, 22444, 25111};
//you need to make a table that is 0,3000,5578
int myPlacers[] = {0, 0, 0, 0};
int tapsz=sizeof(myPlacers)>>2;

// Alternate values:
// int myNumbers[] = {12000, 11578, 14444, 15111,8900, 10278, 12004, 12111};
// int myPlacers[] = {0, 0, 0, 0, 0, 0, 0, 0};
// int tapsz=sizeof(myPlacers)>>2;


// ==========================================
// ECHO + ORGAN (k.odk, from the original echo)
// ==========================================
// audio: the original 4-tap echo (taps 32000 / 31578 / 22444 / 25111), unchanged sound
// ASH + main out = wet echo only
// YELLOW = a steady organ: 5 octaves of square waves (A2 110Hz .. 1760Hz at 44.1k), 2 pins each,
//          like a divide-down combo organ. one phase counter -> the pitch never wanders.
// EARTH  = the organ's pitch follows EARTH like a pitch CV: 1 oct per ~1/4 of its range (unplugged = a steady A2)
// FLIP   = trigger: PITCH (smooth, octaves, for LFOs) -> RING (linear through-zero FM, audio-rate: ring-mod-like) -> OFF
//          (starts on RING without Bluetooth — EARTH is read every sample then — and on PITCH with it)
// SKIP   = trigger: WOBBLE on/off. the 4 echo taps drift like worn tape (slow wow + a little flutter),
//          each tap on its own phase -> the echoes smear and detune against each other.
//          it fades in/out over ~0.2s
// SPEED  = transposes everything (sample clock)
// BUTTON = freeze the echo buffer (lamp). the recording fades out/in over ~23ms,
//          so the frozen loop point is a crossfade, not a click

void IRAM_ATTR echo_og() {
  static uint32_t oph = 0;                          // organ phase (32 bit)
  static int32_t s_earth = 0, s_earth2 = 0, s_earth3 = 0;   // EARTH, 12 bit, three slews (Q8)
  static int initial_earth = 0, boot_timer = 0;
  static bool knob_moved = false;
  static int cal_min = 4095, cal_max = 0;
  static bool last_frozen = false;
  static bool patched = false;                      // latched "a CV is really moving" state
  static int unpatch_timer = 0;
  static int32_t rate_s = 256 << 8;                // slewed FM rate (Q16)
  static int32_t rg = 1024;                          // recording gain 0..1024 (freeze ramp)
  static int fm_mode = -1;                          // FLIP: PITCH -> RING -> off -> PITCH (first: RING without Bluetooth, PITCH with)
  static bool wob_on = false;                       // SKIP: wobble
  static int32_t wob = 0;                           // wobble depth 0..8192 (ramped)
  static uint32_t wph = 0;                          // wobble LFO phase
  static int skip_int = 0;
  static bool skip_latch = true;
  static int flip_int = 0;
  static bool flip_latch = true;

  // --- WAKE UP (coming back from the preset menu) ---
  static bool was_in_menu = true;
  if (preset_mode) {
    was_in_menu = true;
  } else if (was_in_menu) {
    was_in_menu = false;
    last_frozen = audio_frozen_state;
    rg = audio_frozen_state ? 0 : 1024;
    flip_int = FLIPPERAT ? 2000 : 0;  flip_latch = FLIPPERAT ? true : false;
    skip_int = SKIPPERAT ? 2000 : 0;  skip_latch = SKIPPERAT ? true : false;
    s_earth = s_earth2 = s_earth3 = earth_raw12 << 8;
    boot_timer = 0; knob_moved = false; cal_min = 4095; cal_max = 0;
  }

  // --- BUTTON: freeze. the recording gain ramps (~23ms) so the loop point is smooth ---
  if (audio_frozen_state != last_frozen) last_frozen = audio_frozen_state;
  if (audio_frozen_state) { if (rg > 0) rg--; } else { if (rg < 1024) rg++; }

  // --- AUDIO: the original echo ---
  DACWRITER(pout)
  gyo = ADCREADER
  pout = 0;
  int32_t rec = gyo;
  // wobble: each tap reads a little behind its write point, by a slowly moving amount
  if (wob_on) { if (wob < 8192) wob++; } else { if (wob > 0) wob--; }
  wph += 68000;                                     // ~0.7 Hz at 44.1k (2^32 / 44100 * 0.7)
  for (int i = 0; i < tapsz; i++) {
    int p = (myPlacers[i] << 2) + i;
    int old = dread(p);                             // the sample under the write point
    int32_t heard = old;
    if (wob > 0) {
      // triangle LFOs, each tap a quarter turn apart, plus a faster small flutter
      uint32_t ph = wph + (uint32_t)i * 0x40000000u;
      int32_t tri = (int32_t)((ph >> 16) & 0xFFFF);             // 0..65535
      tri = (tri < 32768) ? tri : 65535 - tri;                  // 0..32767
      uint32_t fph = wph * 7 + (uint32_t)i * 0x2A000000u;
      int32_t ftr = (int32_t)((fph >> 16) & 0xFFFF);
      ftr = (ftr < 32768) ? ftr : 65535 - ftr;
      // offset in samples, Q8: wow up to ~120 samples, flutter ~10
      int32_t off = ((tri * 120) >> 7) + ((ftr * 10) >> 7);   // Q8 (0 .. ~32000)
      off = (off * wob) >> 13;
      off = (off * ((ch_v[1] * 1024) / 1000)) >> 10;   // CHAR = WEAR
      int oi = off >> 8, fr = off & 0xFF;
      // address (placer - off) holds the sound from (N - off) samples ago -> delay shortened by off
      int q0 = myPlacers[i] - oi;       if (q0 < 0) q0 += myNumbers[i];
      int q1 = q0 - 1;                  if (q1 < 0) q1 += myNumbers[i];
      int32_t a0 = dread((q0 << 2) + i), a1 = dread((q1 << 2) + i);
      heard = a0 + (((a1 - a0) * fr) >> 8);                   // interpolated
    }
    pout += heard;
    if (rg) dwrite(p, old + (((rec - old) * rg) >> 10));   // record over the write point (faded)
  }
  pout = pout >> 2;
  for (int i = 0; i < tapsz; i++) {
    myPlacers[i]--;
    if (myPlacers[i] < 0) myPlacers[i] += myNumbers[i];
  }
  ASHWRITER(pout);                                  // wet only

  // --- SKIP: wobble on/off ---
  if (SKIPPERAT) { if (skip_int < 2000) skip_int += 500; }
  else           { if (skip_int > 0) skip_int -= 50; }
  if (skip_int > 1500) {
    if (!skip_latch) { skip_latch = true; wob_on = !wob_on; }
  } else if (skip_int < 100) skip_latch = false;

  // --- FLIP: FM depth x1 / x2 ---
  if (FLIPPERAT) { if (flip_int < 2000) flip_int += 500; }
  else           { if (flip_int > 0) flip_int -= 50; }
  if (flip_int > 1500) {
    if (!flip_latch) { flip_latch = true; fm_mode = fm_mode == 1 ? 2 : (fm_mode == 2 ? 0 : 1); }
  } else if (flip_int < 100) flip_latch = false;

  // --- EARTH (12 bit) -> the organ's pitch, like a pitch CV (fixed, no self-calibration: steady) ---
  // three slews (~6 ms each) smooth the 1 kHz readings; the level at power-up is "zero" (unplugged = A2);
  // a small dead band keeps the idle noise out; 1 octave per 1024 counts (FLIP: 2), clamped at ±2 (±3) octaves.
  // PITCH (FLIP 1st): three slews, smooth — for LFOs / slow CVs
  // AUDIO (FLIP 2nd): one light slew only, so an audio-rate signal on EARTH really frequency-modulates the organ
  if (fm_mode < 0) fm_mode = cafe_no_ble ? 2 : 1;
  s_earth  += ((int32_t)(earth_raw12 << 8) - s_earth)  >> (fm_mode == 2 ? (cafe_no_ble ? 1 : 4) : 8);   // (no Bluetooth: EARTH is fresh every sample)
  s_earth2 += (s_earth - s_earth2) >> (fm_mode == 2 ? 2 : 8);
  s_earth3 += (s_earth2 - s_earth3) >> (fm_mode == 2 ? 1 : 8);
  int e = s_earth3 >> 8;                             // 0..4095
  if (boot_timer < 8000) { boot_timer++; if (boot_timer > 4000) initial_earth = e; }   // the resting level
  int32_t rate = 256;                               // Q8, 1.0 = A2
  if (boot_timer >= 8000 && fm_mode == 2) {
    // RING: linear, through-zero FM — the organ's speed is A2 × (1 + EARTH), so a strong audio signal pushes it
    // through zero and backwards: sidebands on both sides, the ring-modulator-like clang
    int32_t dd = e - initial_earth;
    dd = dd > 12 ? dd - 12 : (dd < -12 ? dd + 12 : 0);
    rate = 256 + (dd >> 1);                                              // ±2048 counts -> ×(-3 … +5)
  } else if (boot_timer >= 8000 && fm_mode > 0) {
    int32_t dd = e - initial_earth;
    dd = dd > 40 ? dd - 40 : (dd < -40 ? dd + 40 : 0);
    int32_t o = fm_mode == 2 ? dd : (dd >> 2);                           // 1/256 octave (AUDIO: 4x deeper)
    int32_t lim = fm_mode == 2 ? 1024 : 512;
    if (o > lim) o = lim; if (o < -lim) o = -lim;
    int32_t ip = o >> 8, fr = o & 255;
    int32_t m = 256 + ((fr * (168 + ((fr * 88) >> 8))) >> 8);           // 2^(fr/256), Q8 (±0.3 %)
    rate = ip >= 0 ? (m << ip) : (m >> -ip);
  }
  (void)knob_moved; (void)cal_min; (void)cal_max; (void)patched; (void)unpatch_timer;

  // --- ORGAN ---
  rate_s += ((rate << 8) - rate_s) >> (fm_mode == 2 ? 1 : 8);   // PITCH: ~6 ms slew · AUDIO: follows at once
  oph += (uint32_t)(int32_t)(((int64_t)10713070 * rate_s) >> 16);   // 10713070 = 110 Hz at 44.1k (negative = backwards)
  int pins = 2 * __builtin_popcount(oph >> 27);     // 5 octave squares x 2 pins = 0..10
  {
    uint32_t mask = 0;
    if (pins >= 1) mask |= BIT(12);  if (pins >= 2) mask |= BIT(13);
    if (pins >= 3) mask |= BIT(14);  if (pins >= 4) mask |= BIT(15);
    if (pins >= 5) mask |= BIT(16);  if (pins >= 6) mask |= BIT(17);
    if (pins >= 7) mask |= BIT(21);  if (pins >= 8) mask |= BIT(22);
    if (pins >= 9) mask |= BIT(26);  if (pins >= 10) mask |= BIT(27);
    REG(GPIO_OUT_W1TC_REG)[0] = YELLOW_MASK & ~mask;
    REG(GPIO_OUT_W1TS_REG)[0] = mask;
  }

  // --- LAMP: freeze state ---
  if (audio_frozen_state) { LAMP_ON; } else { LAMP_OFF; }

  // HEARTBEAT
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
