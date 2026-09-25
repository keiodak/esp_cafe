#include "stuff.h"
#include <esp_attr.h>
#include <esp_timer.h>

// Trimmed Apple Pi: coco_mod, echo_og, resonator, rungler, selfread, coco_pc

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
// EARTH  = FM: organ pitch follows EARTH, 0 .. ~4x (unplugged = steady A2)
// FLIP   = trigger: FM depth x1 (0..4x) <-> x2 (0..8x)
// SKIP   = trigger: WOBBLE on/off. the 4 echo taps drift like worn tape (slow wow + a little flutter),
//          each tap on its own phase -> the echoes smear and detune against each other.
//          it fades in/out over ~0.2s
// SPEED  = transposes everything (sample clock)
// BUTTON = freeze the echo buffer (lamp). the recording fades out/in over ~23ms,
//          so the frozen loop point is a crossfade, not a click

void IRAM_ATTR echo_og() {
  static uint32_t oph = 0;                          // organ phase (32 bit)
  static int32_t s_earth = 0;
  static int initial_earth = 0, boot_timer = 0;
  static bool knob_moved = false;
  static int cal_min = 255, cal_max = 0;
  static bool last_frozen = false;
  static bool patched = false;                      // latched "a CV is really moving" state
  static int unpatch_timer = 0;
  static int32_t rate_s = 256 << 8;                // slewed FM rate (Q16)
  static int32_t rg = 1024;                          // recording gain 0..1024 (freeze ramp)
  static bool deep = false;                         // FLIP: FM depth x2
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
    s_earth = EARTHREAD << 8;
    boot_timer = 0; knob_moved = false; cal_min = 255; cal_max = 0;
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
    if (!flip_latch) { flip_latch = true; deep = !deep; }
  } else if (flip_int < 100) flip_latch = false;

  // --- EARTH ---
  s_earth += ((int32_t)(EARTHREAD << 8) - s_earth) >> 4;
  int e = s_earth >> 8;
  if (boot_timer < 2000) { boot_timer++; initial_earth = e; }
  else if (!knob_moved) {
    int d = e - initial_earth; if (d < 0) d = -d;
    if (d > 40) knob_moved = true;
  }
  int k = -1;                                       // -1 = unplugged
  if (knob_moved) {
    static int leak = 0;
    if (e < cal_min) cal_min = e;
    if (e > cal_max) cal_max = e;
    if (++leak >= 16384) {                           // slowly forget old extremes (~0.4s per step) -> range fits the CV you patch now
      leak = 0;
      if (cal_min < e) cal_min++;
      if (cal_max > e) cal_max--;
    }
    int spread = cal_max - cal_min;
    // hysteresis: become "patched" at a clear swing, drop back only after ~2s of small swing
    if (!patched) { if (spread >= 60) { patched = true; unpatch_timer = 0; } }
    else if (spread < 25) { if (++unpatch_timer > 88200) patched = false; }
    else unpatch_timer = 0;
    if (patched && spread > 0) {
      k = ((e - cal_min) * 255) / spread;
      if (k > 255) k = 255; if (k < 0) k = 0;
    }                                                // else: jitter / nothing patched -> plain organ
  }

  // --- ORGAN ---
  int32_t rate = 256;                               // Q8, 1.0 = original organ pitch
  if (k >= 0) rate = deep ? k * 8 : k * 4;          // FM: 0 .. ~4x  (x2: 0 .. ~8x)
  rate_s += ((rate << 8) - rate_s) >> 6;            // ~1.5ms slew: no jumps on plug/unplug
  rate = rate_s >> 8;
  oph += (uint32_t)(((uint64_t)10713070u * rate) >> 8);   // 10713070 = 110 Hz at 44.1k
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

// ==========================================
// RESONATOR - NEW PRESET
// ==========================================
// 16 band resonator
// excite it through the audio inputs and button
// try sending it in a steady sine wave and modulate everything else
// flip button switches between organ and gong mode
// skip is an octave down toggle
// skip and flip are latching switches
// patch antenna to them and touch screw to switch
// earth is central pitch

// --- TUNING TABLES ---
const int ratios_prime[] = {
    100, 106, 119, 131, 137, 144, 162, 175, 
    181, 194, 212, 237, 275, 325, 350, 400 
};

typedef struct {
    int32_t low;
    int32_t band;
} svf_int;

#define NUM_BANDS 16
static svf_int bank[NUM_BANDS];
static bool bank_init = false;

static int res_yellow_lpf = 0;
// Damping: 12 = Long Ring
static int32_t global_damp = 12; 

// DC Blocker State
static int32_t dc_offset = 2048 << 12;

// DEBOUNCE & LOGIC MEMORY
static int res_skip_integrator = 0;
static bool res_skip_stable = false;
static int res_flip_integrator = 0;
static bool res_flip_stable = false;

// LATCHING MEMORY
static bool skip_latched = false;
static bool flip_latched = false;
static bool prev_skip_stable = false;
static bool prev_flip_stable = false;

// PING (BUTTON) MEMORY
static int ping_timer = 0;
static bool prev_btn_state = false;

// LAMP MEMORY
static int res_lamp_env = 0;
static int res_lamp_dc_tracker = 2048 << 6;

// Soft Limiter
int32_t res_limit(int32_t x) {
    if (x > 2000) return 2000 + (x - 2000) / 4;
    if (x < -2000) return -2000 + (x + 2000) / 4;
    return x;
}

void IRAM_ATTR resonator() {
    
    // INIT
    if (!bank_init) {
        for (int i=0; i<NUM_BANDS; i++) {
            bank[i].low = 0; bank[i].band = 0;
        }
        bank_init = true;
    }

    // --- WAKE UP BLOCK ---
    static bool was_in_menu = false;
    if (preset_mode) {
        was_in_menu = true;
    } else if (was_in_menu) {
        was_in_menu = false;
        
        // Sync flip and skip to prevent toggles on boot
        prev_skip_stable = SKIPPERAT;
        prev_flip_stable = FLIPPERAT;
        res_skip_integrator = SKIPPERAT ? 300 : 0;
        res_flip_integrator = FLIPPERAT ? 300 : 0;
        res_skip_stable = SKIPPERAT;
        res_flip_stable = FLIPPERAT;
    }
    
    // INPUTS & DC BLOCKING
    int raw_in = ADCREADER;
    
    // Slow DC Tracking
    int32_t current_dc = dc_offset >> 12;
    int32_t ac_raw = raw_in - current_dc;
    dc_offset += ac_raw >> 4; 
    
    // Input Gain
    int32_t ac_in = ac_raw << 1; 
    
    // 3. BUTTON PING LOGIC (IMPULSE + BOOST)
    bool btn_pressed = BUTTON_PRESSED;
    
    if (btn_pressed && !prev_btn_state) {
        ping_timer = 2500; // 80ms Sustain
        ac_in += 30000; 
    }
    prev_btn_state = btn_pressed;
    
    // Inject Sustaining Noise
    if (ping_timer > 0) {
        // Massive Noise Boost (<< 4) for high energy
        int32_t noise = ((rand() & 4095) - 2048) << 4;
        ac_in += noise; 
        ping_timer--;
    }
    
    // CONTROLS (DEBOUNCED & LATCHED)
    
    // SKIP (Octave Down Toggle)
    if (SKIPPERAT) {
        if (res_skip_integrator < 300) res_skip_integrator++;
    } else {
        if (res_skip_integrator > 0) res_skip_integrator--;
    }
    if (res_skip_integrator > 250) res_skip_stable = true;
    else if (res_skip_integrator < 50)  res_skip_stable = false; 
    
    if (res_skip_stable && !prev_skip_stable) {
        skip_latched = !skip_latched;
    }
    prev_skip_stable = res_skip_stable;
    
    // FLIP (Mode Select Toggle)
    if (FLIPPERAT) {
        if (res_flip_integrator < 300) res_flip_integrator++;
    } else {
        if (res_flip_integrator > 0) res_flip_integrator--;
    }
    if (res_flip_integrator > 250) res_flip_stable = true;
    else if (res_flip_integrator < 50)  res_flip_stable = false; 

    if (res_flip_stable && !prev_flip_stable) {
        flip_latched = !flip_latched;
    }
    prev_flip_stable = res_flip_stable;
    
    bool mode_gong = flip_latched;
    
    // EARTH (Pitch)
    int earth_cv = EARTHREAD; 
    
    // FREQUENCY CALC
    int32_t base_f = 60 + earth_cv; 
    if (skip_latched) base_f = base_f >> 1; // Octave Down
    if (base_f < 8) base_f = 8;
    
     // FILTER ENGINE
     int32_t out_accum = 0;
    
    for (int i=0; i<NUM_BANDS; i++) {
        int32_t f;
        
        if (mode_gong) {
            f = (base_f * ratios_prime[i]) / 100;
        } else {
            f = base_f * (i + 1); 
        }
        
        if (f > 2500) f = 2500; 

        // SVF Algorithm
        bank[i].low += (f * bank[i].band) >> 12;
        int32_t damp_term = (global_damp * bank[i].band) >> 12;
        int32_t high = ac_in - bank[i].low - damp_term;
        bank[i].band += (f * high) >> 12;
        
        out_accum += bank[i].band >> (i >> 3); 
    }
    
    // OUTPUT STAGE
    int32_t final = res_limit(out_accum >> 4); 
    
    if (final > 2047) final = 2047;
    if (final < -2047) final = -2047;
    
    pout = final + 2048;
    if (pout > 4095) pout = 4095;
    if (pout < 0) pout = 0;
    
    DACWRITER(pout);
    ASHWRITER(pout);
    
    // LAMP // Envelope Follower
    res_lamp_dc_tracker += (pout - (res_lamp_dc_tracker >> 6));
    int current_out_dc = res_lamp_dc_tracker >> 6;
    int ac_pout = pout - current_out_dc;
    int abs_vol = (ac_pout > 0) ? ac_pout : -ac_pout;
    res_lamp_env += (abs_vol - res_lamp_env) >> 4;
    if (res_lamp_env > 100) { LAMP_ON; } else { LAMP_OFF; }
    
    // YELLOW
    YELLOW_AUDIO(pout);        

    // CLEANUP
    REG(I2S_CONF_REG)[0] &= ~(BIT(5)); 
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= (BIT(5)); 
}

// ==========================================
// RUNGLER COCO --- NEW PRESET (k.odk)
// ==========================================
// coco looper whose loop is chopped by an 8-bit shift register (after Rob Hordijk's Rungler)
// FLIP   = clock: every rising edge shifts the register and jumps the loop
// SKIP   = data: the bit shifted in is SKIP XOR the last bit
//          (nothing on SKIP -> the register cycles its own pattern)
// register top 3 bits  -> loop START (8 places in the buffer)
// register low 3 bits  -> loop LENGTH (8 lengths)
// EARTH  = range: low = long pieces, high = short stutters (unplugged = middle)
// BUTTON = freeze the buffer (lamp ON), same as coco
// ASH    = wet audio
// YELLOW = GATE: the bit pushed out of the register on each clock (High = ~3.3V, all 10 pins)
//          it stays until the next clock -> patch into another shift register's DATA (e.g. Plumbutter)
// lamp   = ON while frozen, a short flash on every clock

static const int32_t rung_len[8] = {2048, 3072, 4608, 6912, 10368, 15552, 23328, 34992};
#define RUNG_XF 256          // crossfade on every jump (~6ms)

void IRAM_ATTR rungler() {
  static uint8_t reg = 0xA5;
  static int32_t loop_start = 0, loop_len = 131072;
  static int32_t pos = 0;             // position inside the loop
  static int32_t tail = 0;            // old playhead, fading out
  static int xf = 0;
  static bool last_frozen = false;
  static int flip_int = 0;
  static bool flip_latch = true;
  static int flash = 0;
  static bool pending = false;        // a clock that came in during a crossfade
  static bool out_bit = false;        // last bit pushed out of the register (YELLOW gate)
  static int32_t rg = 0;              // recording gain 0..256 (ramps: no clicks on freeze)
  static int32_t s_earth = 0;
  static int initial_earth = 0, boot_timer = 0;
  static bool knob_moved = false;
  static int cal_min = 255, cal_max = 0;

  // --- WAKE UP (coming back from the preset menu) ---
  static bool was_in_menu = true;
  if (preset_mode) {
    was_in_menu = true;
  } else if (was_in_menu) {
    was_in_menu = false;
    last_frozen = audio_frozen_state;
    flip_int = FLIPPERAT ? 2000 : 0;  flip_latch = FLIPPERAT ? true : false;
    s_earth = EARTHREAD << 8;
    boot_timer = 0; knob_moved = false; cal_min = 255; cal_max = 0;
    loop_start = 0; loop_len = 131072; pos = t & 0x1FFFF; xf = 0; pending = false;
    rg = audio_frozen_state ? 0 : 256;
  }

  DACWRITER(pout)
  gyo = ADCREADER

  // --- BUTTON: freeze (the recording gain ramps over ~6ms, see rg) ---
  if (audio_frozen_state != last_frozen) last_frozen = audio_frozen_state;
  if (audio_frozen_state) { if (rg > 0) rg--; } else { if (rg < 256) rg++; }

  // --- EARTH: range ---
  s_earth += ((int32_t)(EARTHREAD << 8) - s_earth) >> 6;
  int e = s_earth >> 8;
  if (boot_timer < 2000) { boot_timer++; initial_earth = e; }
  else if (!knob_moved) {
    int d = e - initial_earth; if (d < 0) d = -d;
    if (d > 20) knob_moved = true;
  }
  int range = 128;
  if (knob_moved) {
    if (e < cal_min) cal_min = e;
    if (e > cal_max) cal_max = e;
    int spread = cal_max - cal_min;
    if (spread > 10) range = ((e - cal_min) * 255) / spread;
    if (range > 255) range = 255; if (range < 0) range = 0;
  }
  int32_t scale_q8 = 1024 - range * 3;            // 4x (long) .. ~1x (short)

  // --- FLIP: clock the register ---
  if (FLIPPERAT) { if (flip_int < 2000) flip_int += 500; }
  else           { if (flip_int > 0) flip_int -= 50; }
  bool clock = false;
  if (flip_int > 1500) {
    if (!flip_latch) { flip_latch = true; clock = true; }
  } else if (flip_int < 100) flip_latch = false;

  if (clock) pending = true;
  int32_t cur = (loop_start + pos) & 0x1FFFF;
  if (pending && xf == 0) {            // never cut a crossfade short
    pending = false;
    uint8_t data = (SKIPPERAT ? 1 : 0) ^ (reg >> 7);
    out_bit = (reg >> 7) & 1;                      // the bit falling off the top
    reg = (uint8_t)((reg << 1) | data);
    int a = reg >> 5;                              // start
    int b = reg & 7;                               // length
    int32_t len = (rung_len[b] * scale_q8) >> 8;
    if (len > 131072) len = 131072;
    if (len < 512) len = 512;
    tail = cur; xf = RUNG_XF;                      // fade out the old head
    loop_start = a << 14;
    loop_len = len;
    pos = 0;
    cur = loop_start;
    flash = 1500;
  }

  // --- READ / WRITE (coco style: read the old sound, then record the input at the same spot) ---
  // every write is  old + (input - old) * gain,  and every gain moves smoothly:
  //   rg   = freeze ramp,   xf = jump crossfade (new spot fades the recording in, old spot out)
  // jumps only start when the previous crossfade is over -> no hard splice ever lands on the tape
  int32_t v;
  if (xf > 0) {
    int32_t on = dread(cur);
    int32_t ot = dread(tail);
    int32_t gt = (rg * xf) >> 8;                  // old spot: recording fades out
    int32_t gh = (rg * (RUNG_XF - xf)) >> 8;      // new spot: recording fades in
    if (gt) dwrite(tail, ot + (((gyo - ot) * gt) >> 8));
    int32_t on2 = dread(cur);                      // (heads may overlap)
    if (gh) dwrite(cur, on2 + (((gyo - on2) * gh) >> 8));
    v = (on * (RUNG_XF - xf) + ot * xf) >> 8;      // RUNG_XF = 256
    tail = (tail + 1) & 0x1FFFF;
    xf--;
  } else {
    v = dread(cur);
    if (rg) dwrite(cur, v + (((gyo - v) * rg) >> 8));
  }
  pout = v;

  // advance, wrap inside the loop (crossfaded)
  pos++;
  if (pos >= loop_len && xf == 0) {
    tail = (loop_start + pos) & 0x1FFFF; xf = RUNG_XF;
    pos = 0;
  }
  t = (loop_start + pos) & 0x1FFFF;               // keep coco's playhead in step

  ASHWRITER(pout);

  // --- YELLOW: gate = the bit pushed out (all 10 pins together = full ~3.3V) ---
  if (out_bit) REG(GPIO_OUT_W1TS_REG)[0] = YELLOW_MASK;
  else         REG(GPIO_OUT_W1TC_REG)[0] = YELLOW_MASK;

  // --- LAMP ---
  if (flash > 0) flash--;
  if (audio_frozen_state || flash > 0) { LAMP_ON; } else { LAMP_OFF; }

  // HEARTBEAT
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////

// ==========================================
// SELF-READING TAPE --- NEW PRESET (k.odk)
// ==========================================
// coco looper whose playhead is steered by the sound on the tape itself.
// it plays a short piece, then reads the sample under the head and uses it as the next address:
//   REL (default): jump by the sample value   t' = t + (value - centre) * 32   (silence = keep going, loud = far)
//   ABS          : the value IS the address  t' = value * 32                  (loud peaks -> the edges)
// frozen, the tape is a fixed map -> the head falls into its own repeating orbit.
// recording, the map rewrites itself as it plays.
// EARTH  = piece length: low = long pieces (mostly normal play), high = short (constant hopping). unplugged = middle
// FLIP   = trigger: REL <-> ABS   (lamp blinks 1 = REL, 2 = ABS)
// SKIP   = trigger: back to the start of the orbit (replays the same path when frozen)
// BUTTON = freeze the buffer (lamp ON), same as coco
// ASH    = wet audio,  YELLOW = a pulse on every jump

#define SELF_XF 256

void IRAM_ATTR selfread() {
  static int32_t tail = 0;
  static int xf = 0;
  static int32_t piece = 0;           // samples left in this piece
  static int32_t origin = 0;          // where the orbit started (SKIP returns here)
  static bool absolute = false;
  static bool last_frozen = false;
  static int flip_int = 0, skip_int = 0;
  static bool flip_latch = true, skip_latch = true;
  static int gate = 0;
  static bool pending_restart = false;
  static int32_t rg = 0;              // recording gain 0..256 (ramps: no clicks on freeze)
  static int blink_counter = 0, blink_timer = 0;
  static bool blink_state = false;
  static int32_t s_earth = 0;
  static int initial_earth = 0, boot_timer = 0;
  static bool knob_moved = false;
  static int cal_min = 255, cal_max = 0;

  // --- WAKE UP (coming back from the preset menu) ---
  static bool was_in_menu = true;
  if (preset_mode) {
    was_in_menu = true;
  } else if (was_in_menu) {
    was_in_menu = false;
    last_frozen = audio_frozen_state;
    flip_int = FLIPPERAT ? 2000 : 0;  flip_latch = FLIPPERAT ? true : false;
    skip_int = SKIPPERAT ? 2000 : 0;  skip_latch = SKIPPERAT ? true : false;
    s_earth = EARTHREAD << 8;
    boot_timer = 0; knob_moved = false; cal_min = 255; cal_max = 0;
    t &= 0x1FFFF; origin = t; piece = 0; xf = 0;
    rg = audio_frozen_state ? 0 : 256;
  }

  DACWRITER(pout)
  gyo = ADCREADER

  // --- BUTTON: freeze (the recording gain ramps over ~6ms, see rg) ---
  if (audio_frozen_state != last_frozen) last_frozen = audio_frozen_state;
  if (audio_frozen_state) { if (rg > 0) rg--; } else { if (rg < 256) rg++; }

  // --- FLIP: REL <-> ABS ---
  if (FLIPPERAT) { if (flip_int < 2000) flip_int += 500; }
  else           { if (flip_int > 0) flip_int -= 50; }
  if (flip_int > 1500) {
    if (!flip_latch) {
      flip_latch = true;
      absolute = !absolute;
      blink_counter = absolute ? 4 : 2; blink_timer = 0; blink_state = false;
    }
  } else if (flip_int < 100) flip_latch = false;

  // --- SKIP: back to the orbit's start ---
  bool restart = false;
  if (SKIPPERAT) { if (skip_int < 2000) skip_int += 500; }
  else           { if (skip_int > 0) skip_int -= 50; }
  if (skip_int > 1500) {
    if (!skip_latch) { skip_latch = true; restart = true; }
  } else if (skip_int < 100) skip_latch = false;

  // --- EARTH: piece length 256 .. 16384 samples (exponential) ---
  s_earth += ((int32_t)(EARTHREAD << 8) - s_earth) >> 6;
  int e = s_earth >> 8;
  if (boot_timer < 2000) { boot_timer++; initial_earth = e; }
  else if (!knob_moved) {
    int d = e - initial_earth; if (d < 0) d = -d;
    if (d > 20) knob_moved = true;
  }
  int k = 128;
  if (knob_moved) {
    if (e < cal_min) cal_min = e;
    if (e > cal_max) cal_max = e;
    int spread = cal_max - cal_min;
    if (spread > 10) k = ((e - cal_min) * 255) / spread;
    if (k > 255) k = 255; if (k < 0) k = 0;
  }
  // 16384 >> (k/42.5) with a linear step in between: 6 octaves
  int oct = (k * 6) >> 8;                          // 0..5
  int32_t plen = 16384 >> oct;
  plen -= ((plen >> 1) * ((k * 6) & 0xFF)) >> 8;  // glide towards the next octave
  if (plen < 256) plen = 256;

  // --- READ / WRITE at the head (coco style) ---
  // same splice-free recording as rungler: old + (input - old) * gain, gains always ramp
  int32_t v, out;
  if (xf > 0) {
    int32_t on = dread(t);
    int32_t ot = dread(tail);
    int32_t gt = (rg * xf) >> 8;
    int32_t gh = (rg * (SELF_XF - xf)) >> 8;
    if (gt) dwrite(tail, ot + (((gyo - ot) * gt) >> 8));
    int32_t on2 = dread(t);
    if (gh) dwrite(t, on2 + (((gyo - on2) * gh) >> 8));
    v = on;
    out = (on * (SELF_XF - xf) + ot * xf) >> 8;
    tail = (tail + 1) & 0x1FFFF;
    xf--;
  } else {
    v = dread(t);
    if (rg) dwrite(t, v + (((gyo - v) * rg) >> 8));
    out = v;
  }
  pout = out;

  // --- MOVE: play the piece, then let the tape pick the next address ---
  t = (t + 1) & 0x1FFFF;
  piece--;
  if (restart) pending_restart = true;
  if (xf > 0) {
    // wait: never start a new jump inside a crossfade
  } else if (pending_restart) {
    pending_restart = false;
    tail = t; xf = SELF_XF;
    t = origin; piece = plen; gate = 600;
  } else if (piece <= 0) {
    int32_t nt;
    if (absolute) nt = v << 5;                     // value = address
    else          nt = t + ((v - 2048) << 5);      // value = jump
    tail = t; xf = SELF_XF;
    t = nt & 0x1FFFF;
    piece = plen;
    gate = 600;
  }

  ASHWRITER(pout);

  // --- YELLOW: pulse on every jump ---
  if (gate > 0) { gate--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); }

  // --- LAMP: mode blink, otherwise frozen state ---
  if (os_blink_active) {
    blink_timer = 0;
  } else if (blink_counter > 0) {
    blink_timer++;
    if (blink_timer > 4000) {
      blink_state = !blink_state;
      if (blink_state) { LAMP_ON; } else { LAMP_OFF; }
      blink_timer = 0;
      blink_counter--;
    }
  } else {
    if (audio_frozen_state) { LAMP_ON; } else { LAMP_OFF; }
  }

  // HEARTBEAT
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////

// ==========================================
// COCO-PC --- NEW PRESET (k.odk)
// ==========================================
// DUO preset: one record head, played three ways (switched from the phone, "M 25 <0|1|2>", ~20 ms crossfade):
//   LOOP  = a play head with its own speed inside a loop (below)
//   GRAIN = smooth or struck grains of the tape on a shared score (grain_tick above)
//   BENJOLIN = two oscillators + rungler + filter, linked to the tape (bj_tick above)
// EARTH (AC-coupled): LOOP = play-speed FM · GRAIN = where grains come from · BENJOLIN = osc 1 FM
// coco with SEPARATE record and play heads, remote-controlled from a computer over USB serial
// (see pc_service() in the .ino and coco-pc.html).
// record head : writes the input around the whole buffer, 1 sample per clock (off when frozen)
// play head   : reads at its own speed (-8x .. +8x, fractional), inside a loop region,
//               jumps and loop wraps are crossfaded (~6ms)
// BUTTON = freeze (stop recording), FLIP = reverse the play head (while HIGH),
// SKIP   = trigger: jump the play head to the loop start
// EARTH  = not used here (its value is sent to the computer)
// ASH + main out = the play head.  YELLOW = pulse at every loop wrap

volatile int32_t  pc_speed = 4096;          // play speed, Q12 (4096 = 1x)
volatile int32_t  pc_ls = 0, pc_le = 131072; // loop region [start, end) in samples
volatile int32_t  pc_jump = -1;             // requested jump (sample), -1 = none
volatile bool     pc_rec = true;            // recording enabled from the computer
volatile uint32_t pc_wpos = 0, pc_ppos = 0; // heads, for the status line
volatile uint32_t pc_samples = 0;           // counts interrupts -> clock rate
volatile uint8_t  pc_earth = 0, pc_flip = 0, pc_skip = 0;
volatile bool     pc_link = false;          // coco duo: the phone is connected (set by the BLE callbacks)
volatile uint32_t preset_gen = 0;           // +1 at every preset load (menu or phone): presets wake up on a change
// sound shaping from the phone (k.odk). Set by "X <id> <0..1000>" in the .ino (derived values, no division here)
//   fold / bias act on the PLAY sound only (the tape keeps the clean recording)
volatile int32_t  pc_fold_g = 256;          // fold input gain, Q8 (256 = 1x .. 2048 = 8x)
volatile int32_t  pc_bias = 0;              // offset before folding, -2048..2048
volatile int32_t  pc_dub = 256;             // record strength, Q8: 256 = replace, lower = overdub (old sound stays)
volatile int32_t  pc_dt = 400;              // short delay time in samples
volatile int32_t  pc_dfb = 0, pc_dwet = 0;  // short delay feedback / wet, Q8
#define PC_DLEN 2048                        // short delay buffer (4 KB; heap is tight with BLE)
RTC_DATA_ATTR static uint16_t pc_dbuf[PC_DLEN];  // in the ESP32's separate RTC memory: the main heap is full (tape + BLE)

static inline int32_t IRAM_ATTR pc_read(int32_t pq) {        // pq = position Q12, interpolated read
  int32_t i = (pq >> 12) & 0x1FFFF;
  int32_t f = (pq >> 4) & 0xFF;
  int32_t a = dread(i), b = dread((i + 1) & 0x1FFFF);
  return a + (((b - a) * f) >> 8);
}

// ==========================================
// GRAIN --- the second mode of the duo preset (k.odk)
// ==========================================
// Clean, fine grains of sound, layered. The grains come from the tape,
// which keeps recording the input (the button holds it = a fixed library).
// Grains have smooth windows (sin²) and overlap. They follow a SCORE: grain n always gets the same
// timing / pitch / place from a hash of n, and the grain times run on the ESP32's microsecond clock.
// So two Cafes that were synced ("Z") play the same score side by side — L and R move together —
// and SEPARATION pulls each one toward its own score, OFFSET shifts one of them in time.
// Only the grains are heard (no dry sound).
// FREEZE (M 23): hold the moment · PERCUSSION (M 24): struck grains instead of smooth ones
// SKIP = restart the score (patch the same gate into both Cafes to re-align them) · FLIP = grains backwards
// BUTTON = hold the tape · YELLOW = a pulse at every grain.  Parameters: "M <id> <0..1000>", sync: "Z"

volatile int16_t  mo_p[24];                  // raw values 0..1000 from the phone
volatile int32_t  mo_int_us = 90000;         // time between grains, µs
volatile int32_t  mo_jit = 0;                // timing jitter 0..4096 (0 = an even stream)
volatile int32_t  mo_len = 3000;             // grain length, samples
volatile int32_t  mo_edge = 1500;            // fade in / out, samples (len/2 = a pure sin² window)
volatile int32_t  mo_rate = 4096;            // base speed, Q12
volatile uint8_t  mo_spread = 1;             // intervals a grain may take (1..9)
volatile int32_t  mo_back = 4096;            // how far behind the record head grains are taken
volatile int32_t  mo_scat = 1;               // + up to this much, per grain
volatile int32_t  mo_f = 4096, mo_q = 4096;  // filter, Q12 (f = 4096 = open)
volatile uint16_t mo_rev = 0;                // share of backwards grains, 0..65535
volatile int32_t  mo_hold = 1;               // a pitch is kept for this many grains (1 = may change every grain)
volatile uint8_t  mo_layers = 4;             // grains sounding at once (1..6)
volatile int32_t  mo_gain = 256;             // output gain, Q8 (includes the overlap normalisation)
volatile int32_t  mo_sep = 0;                // 0 = the common score .. 4096 = this Cafe's own score
volatile int32_t  mo_offs_us = 0;            // this Cafe's grains come this much later (B side)
volatile uint32_t mo_salt = 0;               // 0 = Cafe A, 1 = Cafe B (whose "own" score)
volatile bool     mo_sync = false;           // "Z": restart the score now
volatile bool     mo_freeze = false;         // FREEZE: stop recording and keep taking grains from the same moment
volatile bool     mo_perc = false;           // PERCUSSION: grains are struck (instant attack, curved decay)
volatile bool     mo_usemarks = false;       // take grains only from the marked places
volatile int32_t  mo_mark[8] = {-1, -1, -1, -1, -1, -1, -1, -1};
volatile int32_t  mo_last = 0;               // where the last grain started (MARK stores this)
static int16_t    mo_win[129];               // rising half of sin², 0 .. 4096 (filled at boot)
// intervals a grain can take (Q12): 1, 2, 1/2, 3/2, 2/3, 4, 1/4, 3, 1/3
static const int32_t mo_iv[9] = {4096, 8192, 2048, 6144, 2731, 16384, 1024, 12288, 1365};
struct MoVoice { int32_t pq, rate, n, len, edge, wstep, inv; bool perc; };
static MoVoice mo_v[6];

static inline uint32_t IRAM_ATTR mo_hash(uint32_t x) {
  x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16; return x;
}
/// the score: value 0..65535 for grain n, parameter k. mo_sep pulls it toward this Cafe's own value.
static inline uint32_t IRAM_ATTR mo_rnd(uint32_t n, uint32_t k) {
  uint32_t key = n * 16u + k;
  int32_t c = (int32_t)(mo_hash(key) >> 16);
  if (!mo_sep) return (uint32_t)c;
  int32_t o = (int32_t)(mo_hash(key ^ (0x9E3779B9u * (mo_salt + 1u))) >> 16);
  return (uint32_t)(c + (((o - c) * mo_sep) >> 12));
}

volatile int      pc_mode = 0;               // duo: 0 = LOOP, 1 = GRAIN, 2 = BENJOLIN ("M 25 <0|1|2>")
volatile int32_t  pc_emod = 0;               // EARTH, AC-coupled: -128 .. 127 around its own average (0 = unplugged)
volatile bool     mo_reset = true;           // set when the preset wakes up: the grain engine starts clean
volatile int      mo_pulse = 0;              // YELLOW pulse length after a grain (read by coco_pc)

/// One sample of the grain engine: returns the grains (centred on 0, filtered, level applied).
/// wpos = the record head, frz = FREEZE (grains stay at the moment it was pressed), restart = back to grain 0.
static int32_t IRAM_ATTR grain_tick(uint32_t wpos, int64_t now, bool frz, bool restart) {
  static uint32_t gn = 0, anchor = 0;
  static int64_t next_t = 0, beat_t = 0;        // beat = the steady grid, next = beat + this grain's jitter
  static int32_t low = 0, band = 0;
  static bool was_frozen = false;
  if (mo_reset) {
    mo_reset = false;
    low = 0; band = 0; was_frozen = false;
    for (int i = 0; i < 6; i++) mo_v[i].n = 0;
    restart = true;
  }
  if (frz && !was_frozen) anchor = wpos;
  was_frozen = frz;
  if (mo_sync) { mo_sync = false; restart = true; }
  if (restart) { gn = 0; beat_t = now + mo_offs_us; next_t = beat_t; }

  // --- WHEN: the next grain of the score ---
  if (now >= next_t) {
    uint32_t n = gn++;
    int32_t iv = mo_int_us;
    beat_t += iv;                                                             // the grid never drifts ...
    if (beat_t < now - 200000) beat_t = now;                                  // (no backlog after a stall)
    int32_t jj = (((int32_t)mo_rnd(n + 1, 1) - 32768) * mo_jit) >> 12;        // ... the jitter is only an offset
    next_t = beat_t + (int32_t)(((int64_t)iv * jj * 13) >> 20);               // up to ±0.4 of a gap

    int nl = mo_layers; if (nl < 1) nl = 1; if (nl > 6) nl = 6;
    int vi = 0; int32_t best = 0x7FFFFFFF;
    for (int i = 0; i < nl; i++) {
      if (mo_v[i].n <= 0) { vi = i; break; }
      if (mo_v[i].n < best) { best = mo_v[i].n; vi = i; }
    }
    MoVoice &v = mo_v[vi];
    int32_t len = mo_len;
    // pitch: one interval of the spread, kept for mo_hold grains (a phrase, not a new note every grain)
    uint32_t pn = n / (uint32_t)(mo_hold > 0 ? mo_hold : 1);
    int32_t rate = (mo_rate * mo_iv[(mo_rnd(pn, 2) * (uint32_t)(mo_spread ? mo_spread : 1)) >> 16]) >> 12;
    if (rate < 256) rate = 256; if (rate > 65536) rate = 65536;
    int32_t span = (int32_t)(((int64_t)len * rate) >> 12);
    int32_t start = -1;
    if (mo_usemarks) {
      int k0 = mo_rnd(n, 6) >> 13;
      for (int k = 0; k < 8; k++) if (mo_mark[(k0 + k) & 7] >= 0) { start = mo_mark[(k0 + k) & 7]; break; }
    }
    if (start < 0) {
      int32_t back = mo_back + (int32_t)((mo_rnd(n, 3) * (uint32_t)(mo_scat > 0 ? mo_scat : 1)) >> 16) + span + 64;
      if (back > 131072 - 1024) back = 131072 - 1024;
      back -= pc_emod * 64;                                          // EARTH moves the place (±~8000 samples)
      if (back < span + 64) back = span + 64;
      if (back > 131072 - 1024) back = 131072 - 1024;
      start = ((int32_t)(frz ? anchor : wpos) - back) & 0x1FFFF;
    }
    bool backward = mo_rnd(n, 4) < mo_rev;
    if (FLIPPERAT) backward = !backward;
    v.rate = backward ? -rate : rate;
    v.pq = (backward ? ((start + span) & 0x1FFFF) : start) << 12;
    int32_t edge = mo_edge; if (edge > len / 2) edge = len / 2; if (edge < 16) edge = 16;
    v.len = len; v.n = len; v.edge = edge;
    v.wstep = (int32_t)((128u << 16) / (uint32_t)edge);                      // one division per grain
    v.perc = mo_perc;
    int32_t rl = len - 32; if (rl < 16) rl = 16;
    v.inv = (int32_t)((1u << 24) / (uint32_t)rl);
    mo_last = start;
    mo_pulse = 300;
  }

  // --- THE GRAINS: smooth sin² fades (or struck), flat in between ---
  int32_t sum = 0;
  for (int i = 0; i < 6; i++) {
    MoVoice &v = mo_v[i];
    if (v.n <= 0) continue;
    int32_t k = v.len - v.n;
    int32_t e;
    if (v.perc) {                                                    // struck: 32-sample attack, then a curved fall
      if (k < 32) e = k << 7;
      else { int32_t lin = (int32_t)(((int64_t)v.n * v.inv) >> 12); if (lin > 4096) lin = 4096; e = (lin * lin) >> 12; }
    }
    else if (k < v.edge)  { int32_t ix = (k * v.wstep) >> 16;   e = mo_win[ix > 128 ? 128 : ix]; }
    else if (v.n <= v.edge) { int32_t ix = (v.n * v.wstep) >> 16; e = mo_win[ix > 128 ? 128 : ix]; }
    else e = 4096;
    int32_t sm = pc_read(v.pq) - 2048;
    sum += (sm * e) >> 12;
    v.pq = (v.pq + v.rate) & 0x1FFFFFFF;
    v.n--;
  }

  // --- FILTER: state-variable low-pass with resonance ---
  if (mo_f < 4096) {
    low += (mo_f * band) >> 12;
    int32_t high = sum - low - ((mo_q * band) >> 12);
    band += (mo_f * high) >> 12;
    if (low > 32767) low = 32767; if (low < -32768) low = -32768;
    if (band > 32767) band = 32767; if (band < -32768) band = -32768;
    sum = low;
  }
  return (sum * mo_gain) >> 8;
}


// ==========================================
// BENJOLIN --- the third mode of the duo preset (k.odk)
// ==========================================
// After Rob Hordijk's Benjolin: two triangle oscillators, a "rungler" (8-bit shift register clocked by
// oscillator 2, fed by oscillator 1's pulse XOR its own last bit), whose 3-bit R2R voltage bends both
// oscillators and the filter; the PWM of the two triangles goes through a resonant low-pass.
// Extra links to the Cafe: the tape / live input can go into the filter, the Benjolin can be PRINTED
// onto the tape (so LOOP and GRAIN play what it made), EARTH = FM for oscillator 1.
// FLIP = LOCK the rungler (the pattern repeats) · SKIP = flip a bit (a new pattern) · YELLOW = rungler clock
// Parameters: "B <id> <0..1000>" (see bj_update in the .ino)
volatile int16_t  bj_p[16];
volatile uint32_t bj_inc1 = 1000000, bj_inc2 = 700000;   // base phase steps per sample (Q32)
volatile int32_t  bj_r1 = 0, bj_r2 = 0;          // rungler -> osc 1 / osc 2, 1/256 octave per step (0..7)
volatile int32_t  bj_x21 = 0;                    // osc 2 triangle -> osc 1, 1/256 octave at full swing
volatile int32_t  bj_fc = 1600;                  // filter cutoff, 1/256 octave above 20 Hz
volatile int32_t  bj_frr = 0, bj_fro2 = 0;       // rungler -> cutoff (per step), osc 2 -> cutoff (full swing)
volatile int32_t  bj_q = 3000;                   // resonance (Q12, lower = more)
volatile int32_t  bj_fk = 4000;                  // cutoff scale for this clock (Q8)
volatile uint16_t bj_chaos = 52000;              // 0 = the rungler recycles (loops), 65535 = always new data
volatile int32_t  bj_in = 0;                     // tape / input into the filter, Q8
volatile int32_t  bj_print = 0;                  // Benjolin onto the tape, Q8
volatile int32_t  bj_blend = 2048;               // 0 = PWM .. 4096 = filter
volatile int32_t  bj_gain = 256;                 // output, Q8
volatile bool     bj_lock = false;               // the key LOCK (FLIP does the same while high)
volatile bool     bj_sync = false;               // "Z": same start on both Cafes
volatile bool     bj_kick = false;               // SKIP: flip a bit
volatile int32_t  bj_last = 0;                   // last output (for PRINT)
volatile int      bj_pulse = 0;                  // YELLOW after a rungler clock
RTC_DATA_ATTR static uint32_t bj_exp[256];       // 2^(i/256), Q16 (filled at boot; RTC memory: the heap is tight)

static inline uint32_t IRAM_ATTR bj_exp2(int32_t o) {   // 2^(o/256), Q16
  int32_t ip = o >> 8;
  uint32_t v = bj_exp[o & 255];
  if (ip >= 0) { if (ip > 14) ip = 14; return v << ip; }
  ip = -ip; if (ip > 31) return 0;
  return v >> ip;
}

/// one sample of the Benjolin. in = tape / live input (centred). Returns the output (centred).
static int32_t IRAM_ATTR bj_tick(int32_t in) {
  static uint32_t ph1 = 0, ph2 = 0x40000000;
  static uint8_t reg = 0xA5;
  static int32_t low = 0, band = 0;
  static uint32_t seed = 0x2545F491;
  if (bj_sync) { bj_sync = false; ph1 = 0; ph2 = 0x40000000; reg = 0xA5; low = band = 0; seed = 0x2545F491; }
  if (bj_kick) { bj_kick = false; reg ^= 0x01; }

  int32_t cv = (reg >> 5) & 7;                                    // rungler: top 3 bits, R2R 0..7
  int32_t t1 = (int32_t)(ph1 >> 16); if (t1 > 32767) t1 = 65535 - t1;   // triangles 0..32767
  int32_t t2 = (int32_t)(ph2 >> 16); if (t2 > 32767) t2 = 65535 - t2;
  int32_t t2c = (t2 - 16384) * 2;                                 // osc 2, centred ±32767

  // oscillators (exponential FM, 1/256 octave units)
  int32_t o1 = cv * bj_r1 + ((t2c * bj_x21) >> 15) + pc_emod * 4;  // EARTH = FM for osc 1
  int32_t o2 = cv * bj_r2;
  uint32_t i1 = (uint32_t)(((uint64_t)bj_inc1 * bj_exp2(o1)) >> 16);
  uint32_t i2 = (uint32_t)(((uint64_t)bj_inc2 * bj_exp2(o2)) >> 16);
  uint32_t old2 = ph2;
  ph1 += i1; ph2 += i2;

  // rungler clock: osc 2 square rising edge
  if (!(old2 & 0x80000000u) && (ph2 & 0x80000000u)) {
    uint8_t last = (reg >> 7) & 1;
    uint8_t bit = last;                                           // LOCK / loop: the pattern recycles
    bool locked = bj_lock || FLIPPERAT;
    seed = seed * 1664525u + 1013904223u;
    if (!locked && (seed >> 16) < bj_chaos) bit = ((ph1 >> 31) & 1) ^ last;   // Benjolin: osc 1 pulse XOR last bit
    reg = (uint8_t)((reg << 1) | bit);
    bj_pulse = 200;
  }

  // PWM: the comparator of the two triangles
  int32_t pwm = (t1 > t2) ? 1800 : -1800;

  // filter: resonant low-pass, cutoff bent by the rungler and osc 2
  int32_t oc = bj_fc + cv * bj_frr + ((t2c * bj_fro2) >> 15);
  if (oc < 0) oc = 0; if (oc > 2560) oc = 2560;
  int32_t f = (int32_t)(((int64_t)bj_fk * bj_exp2(oc)) >> 24);
  if (f > 4096) f = 4096; if (f < 1) f = 1;
  int32_t x = pwm + ((in * bj_in) >> 8);
  low += (f * band) >> 12;
  int32_t high = x - low - ((bj_q * band) >> 12);
  band += (f * high) >> 12;
  if (low > 32767) low = 32767; if (low < -32768) low = -32768;
  if (band > 32767) band = 32767; if (band < -32768) band = -32768;

  int32_t out = (pwm * (4096 - bj_blend) + low * bj_blend) >> 12;
  out = (out * bj_gain) >> 8;
  if (out > 2047) out = 2047; if (out < -2048) out = -2048;
  bj_last = out;
  return out;
}

#define PC_XF 256


void IRAM_ATTR coco_pc() {
  static uint32_t wpos = 0;
  static int32_t pq = 0;                    // play position, Q12 (0 .. 131072<<12)
  static int32_t tq = 0;                    // tail (old head) position, Q12
  static int xf = 0;
  static int xfl = PC_XF;                   // length of the running crossfade
  static int32_t rg = 256;
  static int32_t pend = -1;                 // jump waiting for the crossfade to end
  static int skip_int = 0;
  static bool skip_latch = true;
  static int ypulse = 0;
  static uint32_t gen_seen = 0xFFFFFFFF;

  static bool was_in_menu = true;
  if (preset_mode) {
    was_in_menu = true;
  } else if (was_in_menu || gen_seen != preset_gen) {
    gen_seen = preset_gen;
    was_in_menu = false;
    wpos = t & 0x1FFFF;
    pq = (int32_t)(t & 0x1FFFF) << 12;
    skip_int = SKIPPERAT ? 2000 : 0;  skip_latch = SKIPPERAT ? true : false;
    // the preset menu leaves every preset frozen; coco-pc starts RECORDING instead
    audio_frozen_state = false; lamp = false;
    pc_rec = true;
    rg = 0;                                   // ramps up over ~6ms
    xf = 0; pend = -1;
    for (int i = 0; i < PC_DLEN; i++) pc_dbuf[i] = 2048;   // silent delay line
    mo_reset = true;                                        // grains start clean too
  }
  int64_t now = esp_timer_get_time();
  int mode = pc_mode;
  bool gmode = mode == 1, bmode = mode == 2;
  bool frz = gmode && mo_freeze;              // FREEZE only exists in GRAIN mode

  DACWRITER(pout)
  gyo = ADCREADER
  pc_samples++;

  // --- EARTH, AC-coupled: only its movement counts, so an empty jack does nothing ---
  static int32_t eavg = 128 << 8;
  int32_t ev = (int32_t)(EARTHREAD);
  eavg += ((ev << 8) - eavg) >> 11;
  int32_t em = ev - (eavg >> 8);
  if (em > -3 && em < 3) em = 0;                  // a little dead zone for the noise of an empty jack
  if (em > 127) em = 127; if (em < -128) em = -128;
  pc_emod = em;

  // --- RECORD HEAD ---
  bool rec = pc_rec && !audio_frozen_state && !frz;
  if (rec) { if (rg < 256) rg++; } else { if (rg > 0) rg--; }
  if (rg) {
    int32_t old = dread(wpos);
    int32_t src = gyo;
    if (bmode && bj_print) src = gyo + (((bj_last + 2048) - gyo) * bj_print >> 8);   // PRINT: the Benjolin onto the tape
    dwrite(wpos, old + (((src - old) * ((rg * pc_dub) >> 8)) >> 8));
  }
  wpos = (wpos + 1) & 0x1FFFF;

  // --- JUMPS: from the computer, or SKIP -> loop start ---
  int32_t j = pc_jump;
  if (j >= 0) { pc_jump = -1; pend = j & 0x1FFFF; }
  // crossfade length that fits the loop: never longer than half a loop pass at the current speed
  int32_t spd = pc_speed; if (spd < 0) spd = -spd; if (spd < 256) spd = 256;
  int32_t lenS = pc_le - pc_ls; if (lenS < 512) lenS = 512;
  int32_t fit = (int32_t)(((int64_t)lenS << 11) / spd);          // (len/2) / (speed)
  if (fit > PC_XF) fit = PC_XF; if (fit < 16) fit = 16;
  if (SKIPPERAT) { if (skip_int < 2000) skip_int += 500; }
  else           { if (skip_int > 0) skip_int -= 50; }
  bool g_restart = false;
  if (skip_int > 1500) {                     // SKIP: LOOP = back to the loop start / GRAIN = restart the score
    if (!skip_latch) { skip_latch = true; if (gmode) g_restart = true; else if (bmode) bj_kick = true; else pend = pc_ls; }
  } else if (skip_int < 100) skip_latch = false;
  if (pend >= 0 && xf == 0) {
    int32_t p = pend;                       // keep jumps inside the loop region
    if (p < pc_ls || p >= pc_le) p = pc_ls;
    tq = pq; xf = xfl = fit;
    pq = p << 12;
    pend = -1;
  }

  // --- PLAY HEAD ---
  int32_t sp = pc_speed;
  if (FLIPPERAT && !bmode) sp = -sp;               // (in BENJOLIN, FLIP locks the rungler instead)
  sp += (sp * pc_emod) >> 8;                        // EARTH = FM of the play speed, up to ±50 %
  int32_t v = pc_read(pq);
  if (xf > 0) {
    int32_t w = pc_read(tq);
    v = (v * (xfl - xf) + w * xf) / xfl;
    tq += sp;
    if (tq < 0) tq += (131072 << 12);
    if (tq >= (131072 << 12)) tq -= (131072 << 12);
    xf--;
  }
  pq += sp;
  // loop region (crossfaded wrap)
  int32_t ls = pc_ls, le = pc_le;
  if (le - ls < 512) le = ls + 512;
  int32_t lsq = ls << 12, leq = le << 12, lenq = (le - ls) << 12;
  int32_t asp = sp < 0 ? -sp : sp;
  bool far_out = (pq >= leq + asp + 4096) || (pq < lsq - asp - 4096);
  if (far_out) {                                    // region moved away from the head: crossfaded jump
    if (pend < 0) pend = ls;
    if (xf == 0) { tq = pq; xf = xfl = fit; pq = lsq; pend = -1; }
  } else if (pq >= leq || pq < lsq) {
    int32_t np = pq;
    if (pq >= leq) np = lsq + ((pq - leq) % lenq);
    else           np = leq - ((lsq - pq) % lenq) - 1;
    if (xf == 0) { tq = pq; xf = xfl = fit; }
    if (tq < 0) tq += (131072 << 12);
    if (tq >= (131072 << 12)) tq -= (131072 << 12);
    pq = np;
    ypulse = 1500;
  }
  // seam: where the play head crosses the record head, the tape jumps from "one lap ago" to "just now".
  // near the crossing, lean on the live input instead, so the crossing is smooth
  if (rg) {
    int32_t d = ((pq >> 12) - (int32_t)wpos) & 0x1FFFF;
    if (d >= 65536) d -= 131072;
    int32_t ad = d < 0 ? -d : d;
    if (ad < 256) {
      int32_t g = ((256 - ad) * rg) >> 8;              // 0..256 weight of the live input
      v = (v * (256 - g) + gyo * g) >> 8;
    }
  }
  // --- FOLD (play sound only): gain, offset, triangle fold back into range ---
  static int32_t fgs = 256 << 6, dts = 400 << 6;
  fgs += ((pc_fold_g << 6) - fgs) >> 7;             // smoothed, no zipper
  dts += ((pc_dt << 6) - dts) >> 9;                 // delay time glides (tape-like)
  int32_t x = (((v - 2048) * (fgs >> 6)) >> 8) + pc_bias;
  int32_t tf = (x + 2048) & 8191;
  if (tf >= 4096) tf = 8191 - tf;
  x = tf - 2048;
  // --- SHORT DELAY (after the fold) ---
  static int dw = 0;
  int32_t dsm = dts >> 6; if (dsm < 8) dsm = 8; if (dsm > PC_DLEN - 2) dsm = PC_DLEN - 2;
  int rdp = dw - dsm; if (rdp < 0) rdp += PC_DLEN;
  int32_t dv = (int32_t)pc_dbuf[rdp] - 2048;
  int32_t din = x + ((dv * pc_dfb) >> 8);
  if (din > 2047) din = 2047; if (din < -2048) din = -2048;
  pc_dbuf[dw] = (uint16_t)(din + 2048);
  if (++dw >= PC_DLEN) dw = 0;
  x += (dv * pc_dwet) >> 8;
  // --- LOOP / GRAIN / BENJOLIN: one record head, three ways of playing. Switching = ~20 ms crossfade ---
  static int32_t xm = 0, xb = 0;               // weights of GRAIN and BENJOLIN (LOOP gets the rest)
  if (gmode) { if (xm < 4096) xm += 8; } else { if (xm > 0) xm -= 8; }
  if (bmode) { if (xb < 4096) xb += 8; } else { if (xb > 0) xb -= 8; }
  if (xm + xb > 4096) { if (gmode) xb = 4096 - xm; else xm = 4096 - xb; }
  int32_t mix = (x * (4096 - xm - xb)) >> 12;
  if (xm > 0 || gmode) {
    int32_t gs = grain_tick(wpos, now, frz, g_restart);   // each engine runs only when it is heard
    mix += (gs * xm) >> 12;
  } else if (g_restart) {
    mo_sync = true;
  }
  if (xb > 0 || bmode) {
    int32_t bs = bj_tick(gyo - 2048);
    mix += (bs * xb) >> 12;
  }
  x = mix;
  v = x + 2048;
  if (v > 4095) v = 4095; if (v < 0) v = 0;
  pout = v;
  ASHWRITER(pout);

  // --- YELLOW: LOOP = pulse at every loop wrap / GRAIN = pulse at every grain ---
  if (gmode) { if (mo_pulse > 0) { mo_pulse--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); } }
  else if (bmode) { if (bj_pulse > 0) { bj_pulse--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); } }
  else if (ypulse > 0) { ypulse--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); }

  // --- LAMP (coco duo) ---
  //   phone not connected : slow blink (about once a second)
  //   connected           : OFF while recording, ON while the tape is held (button / REC key / FREEZE)
  if (!pc_link) { if ((now >> 19) & 1) { LAMP_ON; } else { LAMP_OFF; } }
  else if (rec) { LAMP_OFF; } else { LAMP_ON; }

  // --- report ---
  t = wpos;
  pc_wpos = wpos;
  pc_ppos = gmode ? ((mo_v[0].pq >> 12) & 0x1FFFF) : ((pq >> 12) & 0x1FFFF);
  pc_earth = EARTHREAD;
  pc_flip = FLIPPERAT ? 1 : 0;
  pc_skip = SKIPPERAT ? 1 : 0;

  // HEARTBEAT
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////

