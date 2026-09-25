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
// COCO-PC / BLE SYSTEM --- NEW PRESET (k.odk)
// ==========================================
// Preset 3, played from the phone (coco duo app over BLE). Four modes ("M 25 <0..3>", ~12 ms fade between them):
//   0 GRAIN   = smooth or struck grains of the tape on a shared score (grain_tick)
//   1 COCO    = a play head in a loop at its own speed, EARTH = FM of the speed, wobble, filter, crush (co_tick)
//   2 DELAY   = stereo / ping-pong delay: main out = L, ASH = R, YELLOW = click on the beat (dl_tick)
//   3 NOISE   = a noise machine: a ring of three delay lines through deciders, shift-register noise,
//               a gate and a filter bent by the ring (nz_tick). Nothing is recorded.
// GRAIN / COCO keep a record head on the tape (BUTTON = hold). DELAY / NOISE use the tape as their own memory.

volatile int32_t  pc_speed = 4096;          // (kept for the status line)
volatile int32_t  pc_ls = 0, pc_le = 131072;
volatile bool     pc_rec = true;            // recording enabled from the phone
volatile uint32_t pc_wpos = 0, pc_ppos = 0; // heads, for the status line
volatile uint32_t pc_samples = 0;           // counts interrupts -> clock rate
volatile uint8_t  pc_earth = 0, pc_flip = 0, pc_skip = 0;
volatile bool     pc_link = false;          // the phone is connected (set by the BLE callbacks)
volatile uint32_t preset_gen = 0;
volatile uint32_t pc_fifo = 0;                // the last raw word read for EARTH (diagnosis)           // +1 at every preset load (menu or phone): presets wake up on a change
volatile float    cafe_bpm = 120.0f;        // shared tempo (DELAY and HARMONY), "K <bpm x10>", SKIP = tap
volatile int32_t  tap_samples = 0;          // set by a preset when SKIP was tapped twice: samples between the taps

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
// MOVE (M 26): Ikue Mori-like — every grain its own pitch (all intervals) and it glides up or down
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
volatile bool     mo_move = false;           // MOVE (Ikue Mori-like): every grain its own pitch from all intervals, and it glides
volatile bool     mo_usemarks = false;       // take grains only from the marked places
volatile int32_t  mo_mark[8] = {-1, -1, -1, -1, -1, -1, -1, -1};
volatile int32_t  mo_last = 0;               // where the last grain started (MARK stores this)
static int16_t    mo_win[129];               // rising half of sin², 0 .. 4096 (filled at boot)
// intervals a grain can take (Q12): 1, 2, 1/2, 3/2, 2/3, 4, 1/4, 3, 1/3
static const int32_t mo_iv[9] = {4096, 8192, 2048, 6144, 2731, 16384, 1024, 12288, 1365};
struct MoVoice { int32_t pq, rate, n, len, edge, wstep, inv; bool perc; int32_t rq, dr; };   // rq/dr: MOVE glide, Q20
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

volatile int      pc_mode = 0;               // BLE preset: 0 = GRAIN, 1 = COCO, 2 = DELAY, 3 = NOISE ("M 25 <0..3>")
volatile int32_t  pc_emod = 0;               // EARTH, AC-coupled: -128 .. 127 around its own average (0 = unplugged)
volatile bool     mo_reset = true;           // set when the preset wakes up: the grain engine starts clean
volatile int      mo_pulse = 0;              // YELLOW pulse length after a grain (read by coco_pc)

/// One sample of the grain engine: returns the grains (centred on 0, filtered, level applied).
/// wpos = the record head, frz = FREEZE (grains stay at the moment it was pressed), restart = back to grain 0.
static int32_t grain_tick(uint32_t wpos, int64_t now, bool frz, bool restart) {
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
    bool mv = mo_move;
    uint32_t pn = mv ? n : n / (uint32_t)(mo_hold > 0 ? mo_hold : 1);        // MOVE: a new pitch every grain
    uint32_t spr = mv ? 9u : (uint32_t)(mo_spread ? mo_spread : 1);            //       from all nine intervals
    int32_t rate = (mo_rate * mo_iv[(mo_rnd(pn, 2) * spr) >> 16]) >> 12;
    if (rate < 256) rate = 256; if (rate > 65536) rate = 65536;
    // MOVE: the pitch glides during the grain, up to an octave up or down (a chirp), direction from the score
    int32_t rend = rate;
    if (mv) {
      int32_t g = (int32_t)mo_rnd(n, 7) - 32768;                               // -32768 .. 32767
      rend = g >= 0 ? rate + (int32_t)(((int64_t)rate * g) >> 15) : rate + (int32_t)(((int64_t)rate * g) >> 16);
      if (rend < 256) rend = 256; if (rend > 65536) rend = 65536;
    }
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
    v.rq = v.rate << 8;
    v.dr = mv ? (int32_t)((((int64_t)(backward ? -rend : rend) - v.rate) << 8) / len) : 0;
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
    if (v.dr) { v.rq += v.dr; v.rate = v.rq >> 8; }
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
static int32_t bj_tick(int32_t in) {
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

// ---- shared by the BLE preset and HARMONY (k.odk) ----
// (the engines' tick functions are NOT in IRAM: the ESP32's 128 KB of IRAM is full with BLE; they run from flash cache)
/// EARTH, AC-coupled (slow): its movement counts, a constant level does nothing. Sets pc_emod (-128..127).
static inline void IRAM_ATTR earth_ac() {
  // the average follows slowly (~1.5 s), so CV movements, LFOs and hand gestures come through;
  // only a constant level (e.g. an empty jack) is taken away
  static int32_t eavg = 0; static bool first = true;
  uint32_t raw = REG(I2S_FIFO_RD_REG)[0];            // (the same as EARTHREAD, but the whole word kept for "H")
  pc_fifo = raw;
  int32_t ev = (int32_t)((raw & 0x7FF) >> 3);
  pc_earth = (uint8_t)ev;                          // what the phone shows (EARTH is read ONCE per sample:
                                                   //  a second read of the I2S FIFO gets another entry)
  if (first) { first = false; eavg = ev << 16; }
  eavg += ((ev << 16) - eavg) >> 16;
  int32_t em = ev - (eavg >> 16);
  if (em > -3 && em < 3) em = 0;                  // a little dead zone for the noise of an empty jack
  if (em > 127) em = 127; if (em < -128) em = -128;
  pc_emod = em;
}
/// SKIP, debounced: true once on each press
static inline bool IRAM_ATTR skip_press() {
  static int s = 0; static bool latch = true;
  if (SKIPPERAT) { if (s < 2000) s += 500; } else { if (s > 0) s -= 50; }
  if (s > 1500) { if (!latch) { latch = true; return true; } }
  else if (s < 100) latch = false;
  return false;
}
/// SKIP as TAP TEMPO: two presses 0.1 .. 3.5 s apart -> tap_samples (loop() turns it into BPM)
static inline void IRAM_ATTR tap_note() {
  static uint32_t last = 0; static bool have = false;
  uint32_t d = pc_samples - last;
  if (have && d > 3000 && d < 150000) tap_samples = (int32_t)d;
  last = pc_samples; have = true;
}
static inline int32_t IRAM_ATTR soft_clip(int32_t x) {
  if (x > 1500) x = 1500 + ((x - 1500) >> 2);
  if (x < -1500) x = -1500 + ((x + 1500) >> 2);
  if (x > 2047) x = 2047; if (x < -2047) x = -2047;
  return x;
}

// ==========================================
// DELAY --- mode 2 of the BLE preset (k.odk): stereo / ping-pong
// ==========================================
// main out = L, ASH = R. The tape is the memory: L line = its first half, R line = its second half
// (up to 65000 samples each, ~1.5 s). Times glide like tape when they change.
// PING-PONG 0 = each side repeats itself, 1000 = the repeats cross L -> R -> L (input goes in on the left).
// SYNC: the time is a division of the shared BPM. YELLOW = a click on every beat (patch it to other gear).
// SKIP = tap tempo · FLIP / BUTTON / HOLD key = hold (the repeats go on forever, the input is kept out)
// LINK (two Cafes as one delay, "Y 11 1" + "Y 12 <0 = A | 1 = B>"): each Cafe is one side and the whole tape is
// one line. PING-PONG then goes across the Cafes: A plays the odd repeats (T, 3T, ..), B the even ones (2T, 4T, ..).
// Linked, the time is always on the beat grid (the TIME pad steps through divisions), and when the Cafe's clock
// (its pitch) moves, the time is re-set to the same division — it jumps along the grid instead of drifting.
// EARTH (AC) = wow on the time.  Parameters: "Y <id> <0..1000>" (see dl_update), tempo "K <bpm x10>"
volatile int16_t  dl_p[12];
volatile int32_t  dl_tl = 16000 << 8, dl_tr = 16000 << 8;   // target times, samples Q8
volatile int32_t  dl_fb = 100, dl_pp = 256;                 // feedback Q8, ping-pong Q8
volatile int32_t  dl_wet = 256, dl_dry = 256;               // Q8
volatile int32_t  dl_tone = 2800;                           // low-pass in the loop, Q12 (4096 = open)
volatile int32_t  dl_wow = 0;                               // EARTH -> time, Q8 samples per step
volatile int32_t  dl_beat = 16000;                          // samples per click
volatile bool     dl_hold = false;                          // the phone's HOLD key
volatile int      dl_pair = 0;                              // LINK: 0 = off, 1 = this Cafe is A, 2 = B
volatile bool     dl_reset = true, dl_align = false;
volatile int      dl_click = 0;                             // YELLOW click length left
volatile uint32_t dl_wpos = 0, dl_rpos = 0;                 // for the status line

/// one sample of the stereo delay. in = centred. Returns L, *rout = R.
static int32_t dl_tick(int32_t in, int32_t *rout, bool hold) {
  static uint32_t w = 0, fill = 0, bc = 0, pw = 0;
  static int32_t cl = 16000 << 8, cr = 16000 << 8;           // current times (they glide)
  static int32_t lpl = 0, lpr = 0;
  if (dl_reset) { dl_reset = false; w = 0; pw = 0; fill = 0; bc = 0; cl = dl_tl; cr = dl_tr; lpl = lpr = 0; }
  if (dl_align) { dl_align = false; bc = 0; dl_click = 300; }  // a tap puts the click on the beat
  cl += (dl_tl - cl) >> 11; cr += (dl_tr - cr) >> 11;
  int32_t wob = pc_emod * dl_wow;
  if (dl_pair) {                                             // LINK: one line over the whole tape
    int32_t T = cl + wob;
    if (T < (16 << 8)) T = 16 << 8; if (T > (65000 << 8)) T = 65000 << 8;
    int32_t loop = T + (int32_t)(((int64_t)T * dl_pp) >> 8);    // ping-pong: the loop is 2T, each Cafe hears half
    int32_t tap = (dl_pair == 1) ? T : loop;
    int32_t rq = (int32_t)(pw << 8) - loop;
    int32_t i = (rq >> 8) & 0x1FFFF, f = rq & 255;
    int32_t a = dread(i), b = dread((i + 1) & 0x1FFFF);
    int32_t vf = a + (((b - a) * f) >> 8) - 2048;               // what goes round
    rq = (int32_t)(pw << 8) - tap;
    i = (rq >> 8) & 0x1FFFF; f = rq & 255;
    a = dread(i); b = dread((i + 1) & 0x1FFFF);
    int32_t vo = a + (((b - a) * f) >> 8) - 2048;               // what this Cafe plays
    dl_rpos = (uint32_t)i;
    if (fill < 140000) fill++;
    if (fill <= (uint32_t)((loop >> 8) + 2)) { vf = 0; vo = 0; }
    if (fill <= (uint32_t)((tap >> 8) + 2)) vo = 0;
    lpl += ((vf - lpl) * dl_tone) >> 12;
    int32_t fb = hold ? 256 : dl_fb;
    int32_t x = hold ? vf : lpl;
    dwrite(pw, soft_clip((hold ? 0 : in) + ((x * fb) >> 8)) + 2048);
    dl_wpos = pw;
    pw = (pw + 1) & 0x1FFFF;
    if (++bc >= (uint32_t)dl_beat) { bc = 0; dl_click = 300; }
    int32_t out = ((in * dl_dry) >> 8) + ((vo * dl_wet) >> 8);
    *rout = out;
    return out;
  }
  int32_t tl = cl + wob, tr = cr - wob;
  if (tl < (16 << 8)) tl = 16 << 8; if (tl > (65000 << 8)) tl = 65000 << 8;
  if (tr < (16 << 8)) tr = 16 << 8; if (tr > (65000 << 8)) tr = 65000 << 8;

  int32_t rq = (int32_t)(w << 8) - tl;                       // interpolated reads
  int32_t i = (rq >> 8) & 0xFFFF, f = rq & 255;
  int32_t a = dread(i), b = dread((i + 1) & 0xFFFF);
  int32_t vl = a + (((b - a) * f) >> 8) - 2048;
  rq = (int32_t)(w << 8) - tr;
  i = (rq >> 8) & 0xFFFF; f = rq & 255;
  a = dread(65536 + i); b = dread(65536 + ((i + 1) & 0xFFFF));
  int32_t vr = a + (((b - a) * f) >> 8) - 2048;
  dl_rpos = (uint32_t)i;
  // right after a start the lines still hold old tape: keep them silent until they were written once
  if (fill < 65536) fill++;
  if (fill <= (uint32_t)(((tl > tr ? tl : tr) >> 8) + 2)) { vl = 0; vr = 0; }

  lpl += ((vl - lpl) * dl_tone) >> 12;
  lpr += ((vr - lpr) * dl_tone) >> 12;
  int32_t pp = dl_pp, fb = hold ? 256 : dl_fb;
  int32_t xl = hold ? vl : lpl, xr = hold ? vr : lpr;         // hold: no filter, no loss, no input
  int32_t il = hold ? 0 : in, ir = hold ? 0 : ((in * (256 - pp)) >> 8);
  int32_t wl = il + ((((xl * (256 - pp) + xr * pp) >> 8) * fb) >> 8);
  int32_t wr = ir + ((((xr * (256 - pp) + xl * pp) >> 8) * fb) >> 8);
  dwrite(w, soft_clip(wl) + 2048);
  dwrite(65536 + w, soft_clip(wr) + 2048);
  dl_wpos = w;
  w = (w + 1) & 0xFFFF;

  if (++bc >= (uint32_t)dl_beat) { bc = 0; dl_click = 300; }
  int32_t dry = (in * dl_dry) >> 8;
  *rout = dry + ((vr * dl_wet) >> 8);
  return dry + ((vl * dl_wet) >> 8);
}

// ==========================================
// NOISE --- mode 3 of the BLE preset (k.odk): a Ciat-Lonbarde-ish noise machine
// ==========================================
// Nothing is recorded (the tape is only its scratch memory). Three short delay lines in a ring
// (A -> B -> C -> A, with a little A -> C across, Fyrall-like), each through a DECIDER:
// soft clip .. wave fold .. 1-bit comparator. The ring is excited by a 16-bit shift register (noise,
// clocked at its own rate; LOOP makes it repeat = pitched), opened by a GATE (Rollz-like pulses).
// A resonant filter follows, its cutoff flipped by the ring's own comparator (SELF).
// main out = A + B (L), ASH = C - B (R), YELLOW = the gate.
// SKIP = open the gate (burst) · FLIP = freeze the shift register · BUTTON = 1-bit everywhere
// EARTH (AC) = bends the line lengths.  Parameters: "N <id> <0..1000>" (see nz_update)
volatile int16_t  nz_p[14];
volatile int32_t  nz_len[3] = {701, 1103, 1597};
volatile int32_t  nz_fb = 230;               // ring gain Q8 (above 256 = it screams by itself)
volatile int32_t  nz_grit = 1000;            // 0 soft clip .. 2048 fold .. 4096 1-bit
volatile uint32_t nz_sinc = 1u << 28;        // shift clock step (Q32 per sample)
volatile int32_t  nz_loop = 0;               // 0 = free, n = the register restarts every n steps
volatile uint32_t nz_ginc = 1u << 18;        // gate phase step (Q32 per sample)
volatile uint32_t nz_duty = 0x80000000u;     // gate open while phase < duty
volatile int32_t  nz_fc = 1800, nz_q = 2000; // cutoff (1/256 oct above 20 Hz), resonance Q12
volatile int32_t  nz_self = 300;             // ring -> cutoff, 1/256 oct
volatile int32_t  nz_gain = 256, nz_in = 0;  // output Q8, live input into the ring Q8
volatile int32_t  nz_emod = 64;              // EARTH -> lengths
volatile bool     nz_reset = true, nz_burst = false;
volatile int      nz_gate = 0;

static inline int32_t IRAM_ATTR nz_decide(int32_t x, int32_t grit) {
  int32_t s = soft_clip(x);
  if (grit <= 0) return s;
  int32_t g = (x * (256 + (grit >> 2))) >> 8;                // fold: up to 5x into a triangle
  int32_t tf = (g + 2048) & 8191; if (tf >= 4096) tf = 8191 - tf;
  int32_t fo = tf - 2048;
  if (grit <= 2048) return s + (((fo - s) * grit) >> 11);
  int32_t bit = x >= 0 ? 1800 : -1800;                        // the comparator
  return fo + (((bit - fo) * (grit - 2048)) >> 11);
}

static int32_t nz_tick(int32_t in, int32_t *rout, bool onebit, bool freeze) {
  static uint32_t w = 0, sph = 0, gph = 0;
  static uint16_t lfsr = 0xACE1;
  static int32_t steps = 0, val = 0, env = 0;
  static int32_t la = 0, ba = 0, lb = 0, bb = 0;
  static int32_t lastc = 0;
  if (nz_reset) { nz_reset = false; w = 0; sph = gph = 0; lfsr = 0xACE1; steps = 0; val = 0; env = 0; la = ba = lb = bb = 0; lastc = 0; }

  // shift register noise (SELF also speeds its clock up while the ring is high)
  uint32_t os = sph;
  sph += nz_sinc + ((lastc > 0 && nz_self) ? (nz_sinc >> 1) : 0);
  if (sph < os) {
    if (!freeze) {
      lfsr = (lfsr >> 1) ^ (uint16_t)(-(int16_t)(lfsr & 1) & 0xB400);
      if (nz_loop && ++steps >= nz_loop) { steps = 0; lfsr = 0xACE1; }
    }
    val = (int32_t)(lfsr & 0xFFF) - 2048;
  }
  // gate
  gph += nz_ginc;
  bool open = nz_burst || gph < nz_duty;
  env += ((open ? 4096 : 0) - env) >> 7;
  nz_gate = open ? 1 : 0;
  int32_t ex = ((val * env) >> 12) + ((in * nz_in) >> 8);

  // the ring
  int32_t em = (pc_emod * nz_emod) >> 6;
  int32_t l0 = nz_len[0] + em, l1 = nz_len[1] - em, l2 = nz_len[2] + (em >> 1);
  if (l0 < 8) l0 = 8; if (l0 > 8000) l0 = 8000;
  if (l1 < 8) l1 = 8; if (l1 > 8000) l1 = 8000;
  if (l2 < 8) l2 = 8; if (l2 > 8000) l2 = 8000;
  uint32_t wi = w & 8191;
  int32_t a = dread((wi - l0) & 8191) - 2048;
  int32_t b = dread(8192 + ((wi - l1) & 8191)) - 2048;
  int32_t c = dread(16384 + ((wi - l2) & 8191)) - 2048;
  int32_t grit = onebit ? 4096 : nz_grit;
  int32_t na = nz_decide(ex + ((c * nz_fb) >> 8), grit);
  int32_t nb = nz_decide(((a * nz_fb) >> 8) + (ex >> 2), grit);
  int32_t nc = nz_decide(((b * nz_fb) >> 8) - (a >> 3), grit);
  dwrite(wi, na + 2048); dwrite(8192 + wi, nb + 2048); dwrite(16384 + wi, nc + 2048);
  w++;
  lastc = c;

  // filter (two: L and R), cutoff flipped by the ring
  int32_t oc = nz_fc + (c > 0 ? nz_self : -nz_self);
  if (oc < 0) oc = 0; if (oc > 2560) oc = 2560;
  int32_t fq = (int32_t)(((int64_t)bj_fk * bj_exp2(oc)) >> 24);
  if (fq > 4096) fq = 4096; if (fq < 1) fq = 1;
  int32_t xl = (a + b) >> 1, xr = (c - b) >> 1;
  la += (fq * ba) >> 12; int32_t hl = xl - la - ((nz_q * ba) >> 12); ba += (fq * hl) >> 12;
  lb += (fq * bb) >> 12; int32_t hr = xr - lb - ((nz_q * bb) >> 12); bb += (fq * hr) >> 12;
  if (la > 32767) la = 32767; if (la < -32768) la = -32768; if (ba > 32767) ba = 32767; if (ba < -32768) ba = -32768;
  if (lb > 32767) lb = 32767; if (lb < -32768) lb = -32768; if (bb > 32767) bb = 32767; if (bb < -32768) bb = -32768;
  *rout = (lb * nz_gain) >> 8;
  return (la * nz_gain) >> 8;
}

// ==========================================
// COCO --- mode 1 of the BLE preset (k.odk)
// ==========================================
// coco with a separate play head: the record head keeps writing the input (BUTTON / REC key = hold),
// the play head runs inside a loop at its own speed. EARTH (AC-coupled) = FM of the play speed —
// from slow bends to audio-rate FM (SLEW), a WOBBLE LFO on the speed, a resonant low-pass, a CRUSH
// (sample & hold + bits), and the dry input mixed in. Loop wraps and restarts are crossfaded.
// FLIP = backwards (while high) · SKIP = back to the loop start · YELLOW = a pulse at every wrap
// Parameters: "C <id> <0..1000>" (see co_update). "Z" = restart the loop (both Cafes together).
volatile int16_t  co_p[18];
volatile int32_t  co_speed = 4096;            // Q12 (4096 = 1x forward)
volatile int32_t  co_ls = 0, co_len = 131072; // loop start / length, samples
volatile int32_t  co_dub = 256;               // record strength Q8: 256 = replace, lower = overdub
volatile int32_t  co_fm = 150;                // EARTH -> speed, 0..512 (512 = up to ±200 %)
volatile int32_t  co_slew = 1024;             // how fast the FM follows EARTH, Q12 (4096 = at once)
volatile uint32_t co_lfo_inc = 0;             // WOBBLE rate (Q32 per sample)
volatile int32_t  co_lfo_depth = 0;           // WOBBLE depth, Q12 share of the speed
volatile int32_t  co_f = 4096, co_q = 4096;   // low-pass (4096 = open), resonance
volatile int32_t  co_hold = 1, co_bits = 0;   // CRUSH: keep each sample n samples, drop n bits
volatile int32_t  co_dry = 0, co_gain = 256;  // Q8
volatile int32_t  co_det = 0;                 // this Cafe's speed offset, Q12 share (L · R pad, B side)
volatile int32_t  co_loff = 0;                // this Cafe's loop start offset (B side)
volatile bool     co_rev = false, co_restart = false, co_reset = true;
volatile int      co_pulse = 0;
volatile uint32_t co_ppos = 0;
#define CO_XF 256

static int32_t co_tick(uint32_t wpos, int32_t in, int32_t rg, bool back) {
  static int32_t rel = 0;                         // position inside the loop, Q12
  static int32_t tail = -1, xf = 0;               // the old head (absolute Q12) while a crossfade runs
  static int32_t ef = 0;                          // EARTH, smoothed, Q8
  static uint32_t lph = 0;
  static int32_t low = 0, band = 0, held = 0, hn = 0;
  if (co_reset) { co_reset = false; rel = 0; xf = 0; ef = 0; lph = 0; low = band = 0; held = 0; hn = 0; }

  int32_t start = (co_ls + co_loff) & 0x1FFFF;
  int32_t len = co_len; if (len < 256) len = 256; if (len > 131072) len = 131072;
  int32_t lenq = len << 12;

  // speed: base (+ B's detune), EARTH FM, WOBBLE, FLIP / reverse key
  int32_t sp = co_speed;
  sp += (int32_t)(((int64_t)sp * co_det) >> 12);
  ef += (int32_t)((((int64_t)(pc_emod << 8) - ef) * co_slew) >> 12);
  sp += (int32_t)(((int64_t)sp * (ef >> 8) * co_fm) >> 15);
  lph += co_lfo_inc;
  if (co_lfo_depth) {
    int32_t tri = (int32_t)(lph >> 16); tri = tri < 32768 ? tri * 2 - 32768 : (65535 - tri) * 2 - 32768;   // -32768..32766
    sp += (int32_t)(((int64_t)sp * tri * co_lfo_depth) >> 27);
  }
  if (back != co_rev) sp = -sp;
  if (sp > 8 * 4096) sp = 8 * 4096; if (sp < -8 * 4096) sp = -8 * 4096;

  bool jump = false;
  if (co_restart) { co_restart = false; jump = true; }
  if (rel >= lenq || rel < 0) rel %= lenq;       // the loop got shorter
  if (rel < 0) rel += lenq;
  int32_t abs_q = (int32_t)((((uint32_t)start << 12) + (uint32_t)rel) & 0x1FFFFFFFu);
  int32_t v = pc_read(abs_q) - 2048;
  if (xf > 0) {
    int32_t w = pc_read(tail) - 2048;
    v = (v * (CO_XF - xf) + w * xf) / CO_XF;
    tail = (tail + sp) & 0x1FFFFFFF;
    xf--;
  }
  // seam: near the record head, lean on the live input (no click where "a lap ago" meets "now")
  if (rg) {
    int32_t d = (int32_t)(((uint32_t)(abs_q >> 12) - wpos) & 0x1FFFF);
    if (d >= 65536) d -= 131072;
    int32_t ad = d < 0 ? -d : d;
    if (ad < 256) { int32_t g = ((256 - ad) * rg) >> 8; v = (v * (256 - g) + in * g) >> 8; }
  }
  co_ppos = (uint32_t)(abs_q >> 12);

  rel += sp;
  if (rel >= lenq || rel < 0 || jump) {
    if (xf == 0) { tail = (abs_q + sp) & 0x1FFFFFFF; xf = CO_XF; }
    if (jump) rel = 0;
    else if (rel >= lenq) rel -= lenq;
    else rel += lenq;
    if (rel >= lenq || rel < 0) rel = 0;
    co_pulse = 1500;
  }

  // filter, crush
  if (co_f < 4096) {
    low += (co_f * band) >> 12;
    int32_t high = v - low - ((co_q * band) >> 12);
    band += (co_f * high) >> 12;
    if (low > 32767) low = 32767; if (low < -32768) low = -32768;
    if (band > 32767) band = 32767; if (band < -32768) band = -32768;
    v = low;
  }
  if (++hn >= co_hold) { hn = 0; held = v; }
  v = held;
  if (co_bits) v &= ~((1 << co_bits) - 1);
  return ((v * co_gain) >> 8) + ((in * co_dry) >> 8);
}

void IRAM_ATTR coco_pc() {
  static uint32_t wpos = 0;
  static int32_t rg = 256;                  // record gain ramp
  static uint32_t gen_seen = 0xFFFFFFFF;
  static int cur = -1;                      // the mode that is sounding
  static int32_t mg = 0;                    // its fade, 0..4096

  static bool was_in_menu = true;
  if (preset_mode) {
    was_in_menu = true;
  } else if (was_in_menu || gen_seen != preset_gen) {
    gen_seen = preset_gen;
    was_in_menu = false;
    wpos = t & 0x1FFFF;
    // the preset menu leaves every preset frozen; this one starts RECORDING instead
    audio_frozen_state = false; lamp = false;
    pc_rec = true;
    rg = 0;
    cur = -1; mg = 0;
  }
  int64_t now = esp_timer_get_time();

  DACWRITER(pout)
  gyo = ADCREADER
  pc_samples++;
  earth_ac();

  // --- MODE: fade the old one out, start the new one, fade it in (~6 ms each way) ---
  int want = pc_mode;
  if (cur < 0) {
    cur = want;
    if (cur == 0) mo_reset = true; else if (cur == 1) co_reset = true; else if (cur == 2) dl_reset = true; else if (cur == 3) nz_reset = true;
  }
  if (want != cur) {
    if (mg > 0) mg -= 16;
    else { cur = want; if (cur == 0) mo_reset = true; else if (cur == 1) co_reset = true; else if (cur == 2) dl_reset = true; else if (cur == 3) nz_reset = true; }
  } else if (mg < 4096) mg += 16;
  bool gmode = cur == 0, bmode = cur == 1, dmode = cur == 2, nmode = cur == 3;
  bool frz = gmode && mo_freeze;              // FREEZE only exists in GRAIN mode

  // --- SKIP: GRAIN = restart the score · COCO = back to the loop start · DELAY = tap tempo · NOISE = burst (held) ---
  bool press = skip_press();
  bool g_restart = false;
  if (press) {
    if (gmode) g_restart = true;
    else if (bmode) co_restart = true;
    else if (dmode) { tap_note(); dl_align = true; }
  }
  nz_burst = nmode && SKIPPERAT;

  // --- RECORD HEAD (GRAIN / COCO only: the other two use the tape themselves) ---
  bool rec = (gmode || bmode) && pc_rec && !audio_frozen_state && !frz;
  if (rec) { if (rg < 256) rg++; } else { if (rg > 0) rg--; }
  if (rg && (gmode || bmode)) {
    int32_t old = dread(wpos);
    int32_t g = bmode ? ((rg * co_dub) >> 8) : rg;          // COCO: overdub keeps some of the old sound
    dwrite(wpos, old + (((gyo - old) * g) >> 8));
  }
  if (gmode || bmode) wpos = (wpos + 1) & 0x1FFFF;

  // --- THE SOUND ---
  int32_t l = 0, r = 0;
  if (gmode) { l = grain_tick(wpos, now, frz, g_restart); r = l; }
  else if (bmode) { l = co_tick(wpos, gyo - 2048, rg, FLIPPERAT); r = l; }
  else if (dmode) { bool hold = dl_hold || FLIPPERAT || audio_frozen_state; l = dl_tick(gyo - 2048, &r, hold); }
  else { l = nz_tick(gyo - 2048, &r, audio_frozen_state, FLIPPERAT); }
  if (!gmode && g_restart) mo_sync = true;
  l = (l * mg) >> 12; r = (r * mg) >> 12;
  int32_t v = l + 2048; if (v > 4095) v = 4095; if (v < 0) v = 0;
  pout = v;
  int32_t vr = r + 2048; if (vr > 4095) vr = 4095; if (vr < 0) vr = 0;
  ASHWRITER(vr);                              // ASH = R (the same as L in GRAIN / COCO)

  // --- YELLOW: GRAIN = a pulse at every grain · COCO = a pulse at every wrap · DELAY = the click · NOISE = the gate ---
  bool y = false;
  if (gmode) { if (mo_pulse > 0) { mo_pulse--; y = true; } }
  else if (bmode) { if (co_pulse > 0) { co_pulse--; y = true; } }
  else if (dmode) { if (dl_click > 0) { dl_click--; y = true; } }
  else y = nz_gate;
  if (y) { YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); }

  // --- LAMP ---
  //   phone not connected : slow blink (about once a second)
  //   GRAIN / COCO        : OFF while recording, ON while the tape is held
  //   DELAY               : ON while held, else a flash on every click
  //   NOISE               : the gate
  if (!pc_link) { if ((now >> 19) & 1) { LAMP_ON; } else { LAMP_OFF; } }
  else if (dmode) { if (dl_hold || FLIPPERAT || audio_frozen_state || dl_click > 150) { LAMP_ON; } else { LAMP_OFF; } }
  else if (nmode) { if (nz_gate) { LAMP_ON; } else { LAMP_OFF; } }
  else if (rec) { LAMP_OFF; } else { LAMP_ON; }

  // --- report ---
  if (dmode) { pc_wpos = dl_wpos; pc_ppos = dl_rpos; }
  else { t = wpos; pc_wpos = wpos; pc_ppos = gmode ? ((mo_v[0].pq >> 12) & 0x1FFFF) : co_ppos; }
  if (bmode) { pc_ls = (co_ls + co_loff) & 0x1FFFF; pc_le = pc_ls + co_len; }
  pc_flip = FLIPPERAT ? 1 : 0;
  pc_skip = SKIPPERAT ? 1 : 0;

  // HEARTBEAT
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////

// ==========================================
// HARMONY --- PRESET 7 (k.odk): replay in intervals, after norns' rpls (andr-ew)
// ==========================================
// Three buffers take turns (like rpls): the record head fills one with the input for one CYCLE (a number of beats),
// then moves on; two voices play the two buffers behind it — VOICE 1 the last cycle, VOICE 2 the one before —
// at their own speed = their INTERVAL (-2 oct … +2 oct, fourths, fifths, or backwards) and TIMING (where in the cycle
// they start: 16 steps). The voices never meet the record head, so any speed plays without clicks.
// Little feedback by default (FEEDBACK puts the voices back on the tape: transposed overdubs).
// main out = dry + VOICE 1 (+ a little 2), ASH = dry + VOICE 2 (+ a little 1). YELLOW = a click on the beat,
// the lamp flashes at every cycle. SKIP = tap tempo · FLIP / BUTTON / HOLD = stop recording (the voices keep
// playing the last cycles) · EARTH = varispeed wobble of the voices. Parameters: "V <id> <0..1000>" (hd_update).
#define HD_STRIDE 43690
static const int32_t hd_iv[12] = {-4096, -2048, 1024, 2048, 2731, 3072, 4096, 5461, 6144, 8192, 12288, 16384};
volatile int16_t  hd_p[14];
volatile int32_t  hd_rate[2] = {2048, 6144};   // the voices' speeds, Q12 (negative = backwards)
volatile int32_t  hd_off[2] = {0, 4};          // where they start in the cycle, 1/16 steps
volatile int32_t  hd_S = 22050;                // cycle length, samples
volatile int32_t  hd_fb = 0, hd_keep = 0;      // voices -> tape, Q8 · old tape kept (overdub), Q8
volatile int32_t  hd_lvl = 200, hd_dry = 256;  // Q8
volatile int32_t  hd_tone = 4096, hd_wob = 0;  // low-pass on the voices · EARTH wobble depth
volatile int32_t  hd_beat = 16000;
volatile bool     hd_hold = false, hd_reset = true, hd_align = false;

static inline int32_t hd_voice(int b, int32_t q, int32_t S) {           // one buffer, position Q12, with fades
  int32_t i = q >> 12, f = (q >> 4) & 255;
  if (i < 0) i = 0; if (i >= S) i = S - 1;
  int32_t j = i + 1 >= S ? 0 : i + 1;
  int32_t base = b * HD_STRIDE;
  int32_t a = dread(base + i), c = dread(base + j);
  int32_t v = a + (((c - a) * f) >> 8) - 2048;
  int32_t e = i < 64 ? i : (S - 1 - i < 64 ? S - 1 - i : 64);          // a dip where the buffer wraps
  return (v * e) >> 6;
}

void IRAM_ATTR harmony() {
  static int rb = 0;                         // the buffer being recorded
  static int32_t t = 0, S = 22050;           // time in the cycle, this cycle's length
  static int32_t q[2] = {0, 0};              // voice positions, Q12
  static uint32_t cycles = 0, bc = 0;
  static int32_t lp[2] = {0, 0};
  static int click = 0, flash = 0;
  static uint32_t gen_seen = 0xFFFFFFFF;
  static bool was_in_menu = true;
  if (preset_mode) { was_in_menu = true; }
  else if (was_in_menu || gen_seen != preset_gen) {
    gen_seen = preset_gen; was_in_menu = false;
    audio_frozen_state = false; lamp = false;
    hd_reset = true;
  }
  if (hd_reset) { hd_reset = false; rb = 0; t = 0; cycles = 0; bc = 0; lp[0] = lp[1] = 0; S = hd_S; }
  if (hd_align) { hd_align = false; t = 0; bc = 0; click = 300; }

  DACWRITER(pout)
  gyo = ADCREADER
  pc_samples++;
  earth_ac();
  if (skip_press()) { tap_note(); hd_align = true; }
  bool hold = hd_hold || FLIPPERAT || audio_frozen_state;
  int32_t in = gyo - 2048;

  // a new cycle: the record head moves to the next buffer, the voices start again at their TIMING
  if (t == 0) {
    if (cycles > 0 && !hold) rb = (rb + 1) % 3;
    cycles++;
    S = hd_S; if (S < 256) S = 256; if (S > HD_STRIDE - 2) S = HD_STRIDE - 2;
    for (int k = 0; k < 2; k++) {
      int32_t st = (int32_t)(((int64_t)S * hd_off[k]) >> 4);
      q[k] = (hd_rate[k] < 0 ? (S - 1 - st) : st) << 12;
    }
    flash = 600;
  }

  // the voices: VOICE 1 plays the last cycle, VOICE 2 the one before
  int32_t v[2];
  int32_t gc = t < 64 ? t : (S - 1 - t < 64 ? S - 1 - t : 64);            // fade at the cycle's edges
  for (int k = 0; k < 2; k++) {
    int b = (rb + 2 - k) % 3;                                            // k 0 -> rb-1, k 1 -> rb-2
    bool ready = cycles > (uint32_t)(k + 1);                             // those buffers hold this input yet
    int32_t x = ready ? hd_voice(b, q[k], S) : 0;
    x = (x * gc) >> 6;
    if (hd_tone < 4096) { lp[k] += ((x - lp[k]) * hd_tone) >> 12; x = lp[k]; }
    v[k] = x;
    int32_t r = hd_rate[k] + (int32_t)(((int64_t)hd_rate[k] * pc_emod * hd_wob) >> 15);   // EARTH = wobble
    q[k] += r;
    int32_t Sq = S << 12;
    while (q[k] >= Sq) q[k] -= Sq;
    while (q[k] < 0) q[k] += Sq;
  }

  // the record head (little feedback by default)
  if (!hold) {
    int32_t base = rb * HD_STRIDE;
    int32_t old = hd_keep ? dread(base + t) - 2048 : 0;
    int32_t w = in + ((((v[0] + v[1]) >> 1) * hd_fb) >> 8) + ((old * hd_keep) >> 8);
    dwrite(base + t, soft_clip(w) + 2048);
  }
  if (++t >= S) t = 0;

  int32_t dry = (in * hd_dry) >> 8;
  int32_t l = dry + ((((v[0] * 205) >> 8) + ((v[1] * 77) >> 8)) * hd_lvl >> 8);
  int32_t r = dry + ((((v[1] * 205) >> 8) + ((v[0] * 77) >> 8)) * hd_lvl >> 8);
  int32_t o = l + 2048; if (o > 4095) o = 4095; if (o < 0) o = 0;
  pout = o;
  int32_t orr = r + 2048; if (orr > 4095) orr = 4095; if (orr < 0) orr = 0;
  ASHWRITER(orr);

  if (++bc >= (uint32_t)hd_beat) { bc = 0; click = 300; }
  if (click > 0) { click--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); }
  if (flash > 0) flash--;
  if (hold || flash > 0) { LAMP_ON; } else { LAMP_OFF; }

  pc_wpos = rb * HD_STRIDE + t; pc_ppos = ((rb + 2) % 3) * HD_STRIDE + (q[0] >> 12);
  pc_flip = FLIPPERAT ? 1 : 0; pc_skip = SKIPPERAT ? 1 : 0;

  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////

// ==========================================
// FORMANT (Vowel Filter) --- from ieat31415's Apple Pi (ported, k.odk)
// ==========================================
// based on the coco preset with a formant filter added
// earth modulates the vowels
// ash is wet signal at line level 
// yellow is buffer position

// 3 filters, each has 2 state variables (Band, Low)
// Values are scaled up by 4096 (12 bits) to simulate decimals and eliminate floating point computation
int f1_band=0, f1_low=0;
int f2_band=0, f2_low=0;
int f3_band=0, f3_low=0;

// State Variable Filter (high performance with ints)
// input: Audio sample
// f: Frequency coefficient (0.01 to 0.5)
// q: Resonance (Damping), lower is more resonant (0.05 to 0.5)
// f and q are fixed-point integers (1.0 = 4096)
int svf_bandpass_int(int input, int f, int q, int *band, int *low) {
    // low += f * band
    *low += (*band * f) >> 12;
    
    // high = input - low - q * band
    int high = input - *low - ((*band * q) >> 12);
    
    // band += f * high
    *band += (high * f) >> 12;
    
    return *band;
}

void IRAM_ATTR formant() {

 
 // read inputs
 int audio_in = ADCREADER;      // audio input
 int earth_cv = EARTHREAD;      // earth

 // get audio from delay
 //int raw_audio = dellius(t, audio_in, lamp); //TO BE REPLACED BELOW TO ALLOW FOR BUFFER TRANSFER
 int raw_audio = dellius(t, audio_in, audio_frozen_state);
 
// Center the audio (0-4095 -> -2048 to +2048)
 int signal = raw_audio - 2048;

 // FORMANT FILTER BANK
 // map earth_cv (0-255) to frequency coefficients (0.0 to 1.0)
 // these numbers tune the vowels
 
// quantized earth (0 to 255)
 int cv = earth_cv;

 // Formant 1 (Throat): Slides 200Hz -> 800Hz
 // Base 80 + (cv * 0.5) -> Range ~80 to 200
 int f1_freq = 80 + (cv >> 1);
 
 // Formant 2 (Mouth): Slides 800Hz -> 2200Hz
 // Base 300 + (cv * 1.5) -> Range ~300 to 700
 int f2_freq = 300 + ((cv * 3) >> 1);
 
 // Formant 3 (Teeth): Slides 2200Hz -> 3000Hz
 // Base 800 + (cv * 1.0) -> Range ~800 to 1055
 int f3_freq = 800 + cv;

 // Q Factor (Resonance): Fixed at 0.1 (approx 400 in 12-bit scale)
 int q = 400;

 // Apply the 3 Filters in Parallel
int out1 = svf_bandpass_int(signal, f1_freq, q, &f1_band, &f1_low);
 int out2 = svf_bandpass_int(signal, f2_freq, q, &f2_band, &f2_low);
 int out3 = svf_bandpass_int(signal, f3_freq, q, &f3_band, &f3_low);

 // Sum them up and scale back to integer
 // We multiply by 1.5 to boost the resonance volume
int filtered_mix = (out1 + out2 + out3);
 filtered_mix = filtered_mix + (filtered_mix >> 1);
 
 // Clip and re-center to 0-4095 for output
 int final_out = (int)filtered_mix + 2048;
 if (final_out > 4095) final_out = 4095;
 if (final_out < 0) final_out = 0;

 // Update Global Output
 pout = final_out;

 // 5. TIMING & OUTPUTS
 if (FLIPPERAT) t--;
 else t++; 
 t=t&0x1FFFF;
 
 if (SKIPPERAT)  {
  if (lastskp==0) delayskp = t;
  lastskp = 1;
 } else {
  if (lastskp) t=delayskp;
  lastskp = 0;
 } 
 
 DACWRITER(pout); // Send the "Talking" audio to speakers
 CLEAN_ASHWRITER(pout); // Monitor the Vowel Control on Ash
 YELLOW_BINARY(t) // Buffer position encoded

  // HEARTBEAT
 REG(I2S_CONF_REG)[0] &= ~(BIT(5)); 
 REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= (BIT(5)); //start rx 
}

// ==========================================
// SATURATOR --- from ieat31415's Apple Pi (ported, k.odk: tape_flange in its own buffer)
// ==========================================
// BUTTON = next of 8 kinds (blinks 1-8): tube, fuzz, fold, tape, vinyl, mp3, radio, rat
// FLIP / SKIP = two switches (latched) that change each kind, EARTH = drive
void IRAM_ATTR saturator() { 
    
    // --- MIXING CONSOLE  ---
    // 128 = 1.0x (Unity) 
    // 256 = 2.0x (Boost)
    // 64  = 0.5x (Cut)
    const int16_t gain_compensation[8] = { 
        96,  // 1. Tube  
        72,  // 2. Fuzz  
        64,  // 3. Fold  
        256, // 4. Tape  
        320, // 5. Vinyl 
        200, // 6. MP3   
        384, // 7. Radio 
        72   // 8. RAT  
    };

    // --- STATE ---
    static int dist_mode = 0;   
    static bool last_frozen = false; 
    static int blink_queue = 0;
    static int blink_timer = 0;
    static int blink_state = 0;
    
    static int32_t dc_slow = 0; 
    static bool servo_ready = false;

    static int32_t dist_lpf = 0; 
    static uint32_t t = 0; 
    static int hp_mem = 0;
    static int lp_mem = 0;
    
    // TAPE STATE 
    //static int16_t tape_flange[256]; //replaced below by putting this buffer in a specified memory ppol
    RTC_DATA_ATTR static int16_t tape_flange[256];   // (k.odk: its own buffer, in RTC memory: the heap is tight)
    static uint8_t tape_f_ptr = 0;

    // RADIO STATE
    static int32_t svf_low = 0;
    static int32_t svf_band = 0;

    // RAT STATE
    static int32_t rat_slew = 0;
    static int32_t rat_tone = 0;

    // Earth Auto-Calibration States
    static int cal_min = 255;
    static int cal_max = 0;

    // Stompbox State
    static int flip_latched = 0; 
    static int skip_latched = 0;
    static bool flip_was_high = false;
    static bool skip_was_high = false;

    // INPUTS
    int audio_in = ADCREADER; 
    t++; 

    // --- EARTH AUTO-CALIBRATION ---
    int earth_raw = EARTHREAD; 
    
    if (earth_raw < cal_min) cal_min = earth_raw;
    if (earth_raw > cal_max) cal_max = earth_raw;
    
    int spread = cal_max - cal_min;
    int cv = earth_raw;
    
    if (spread > 10) {
        cv = ((earth_raw - cal_min) * 255) / spread;
    }

    // DC SERVO
    if (!servo_ready || dc_slow == 0) {
        dc_slow = audio_in << 12;
        servo_ready = true;
    } else {
        dc_slow += (audio_in << 12) - dc_slow >> 10;
    }
    int32_t signal = audio_in - (dc_slow >> 12);

    // MODE SELECTOR 
    if (audio_frozen_state != last_frozen) {
        last_frozen = audio_frozen_state;
        
        dist_mode++;
        if (dist_mode > 7) dist_mode = 0;
        
        blink_queue = dist_mode + 1;
        blink_timer = 0; blink_state = 0;
    }

    // STOMPBOX LOGIC
    bool flip_is_high = FLIPPERAT;
    if (flip_is_high && !flip_was_high) flip_latched = !flip_latched;
    flip_was_high = flip_is_high;

    bool skip_is_high = SKIPPERAT;
    if (skip_is_high && !skip_was_high) skip_latched = !skip_latched;
    skip_was_high = skip_is_high;

    // WAKE UP BLOCK
    static bool was_in_menu = false;
    if (preset_mode) {
        was_in_menu = true;
    } else if (was_in_menu) {
        was_in_menu = false;
        last_frozen = audio_frozen_state;
        flip_was_high = FLIPPERAT;
        skip_was_high = SKIPPERAT;
        cal_min = 255;
        cal_max = 0;
    }

    int32_t out = 0;
    bool flip_active = flip_latched; 
    bool skip_active = skip_latched; 

    switch (dist_mode) {
        
        // MODE 0: TUBE
        case 0: {
            int64_t gain = 256 + (cv * 150); 
            int64_t driven = (signal * gain) >> 8;
            int64_t limit = 1950; 
            int64_t abs_d = (driven > 0) ? driven : -driven;
            int64_t stage1 = (driven * limit) / (limit + abs_d);

            if (flip_active) {
                int64_t turbo = stage1 * 3; 
                if (turbo > 2000) turbo = 2000;
                if (turbo < -2000) turbo = -2000;
                out = (int32_t)turbo;
            } else {
                out = (int32_t)stage1;
            }
            if (skip_active) { lp_mem += (out - lp_mem) >> 2; out = lp_mem; }
            break;
        }

        // MODE 1: FUZZ
        case 1: {
            if (skip_active) { lp_mem += (signal - lp_mem) >> 3; signal = signal + lp_mem; }
            int bias = (cv - 128) * 32; 
            int fuzz_sig = (signal * 32) + bias; 
            int limit = 2048; 
            if (fuzz_sig > limit) fuzz_sig = limit;
            if (fuzz_sig < -limit) fuzz_sig = -limit;
            
            if (flip_active) { 
                if (fuzz_sig < 0) fuzz_sig = -fuzz_sig; 
                fuzz_sig -= 1024;  
                fuzz_sig = (fuzz_sig * 3) >> 1;   
            }
            out = fuzz_sig;
            break;
        }

        // MODE 2: FOLD
        case 2: {
            int drive = 256 + (cv * 64);
            int folded = (signal * drive) >> 8;
            int threshold = 2000; 
            for (int i=0; i<2; i++) {
                if (folded > threshold) folded = threshold - (folded - threshold); 
                if (folded < -threshold) folded = -threshold - (folded + threshold);
            }
            if (flip_active) folded = folded ^ ((cv << 4) & 0xFFF); 
            if (skip_active) { 
                if (folded > 500) folded = 1000; 
                else if (folded < -500) folded = -1000; 
                else folded = 0; 
            }
            out = folded;
            break;
        }

        // MODE 3: TAPE 
        case 3: {
            signal = signal << 1; 
            int drive = 300 + cv;
            int tape_sig = (signal * drive) >> 8;
            
            if (tape_sig > 1500) tape_sig = 1500 + ((tape_sig - 1500) >> 2);
            if (tape_sig < -1500) tape_sig = -1500 + ((tape_sig + 1500) >> 2);
            
            if (skip_active) {
                int lfo = (t >> 10) & 0xFF; 
                if ((t >> 18) & 1) lfo = 255 - lfo; 
                int drop_gain = 256 - (lfo >> 1); 
                tape_sig = (tape_sig * drop_gain) >> 8; 
            }
            if (flip_active) { 
                tape_flange[tape_f_ptr] = (int16_t)tape_sig;
                tape_f_ptr++; 
                int lfo = (t >> 9) & 0xFF;
                if ((t >> 17) & 1) lfo = 255 - lfo;
                uint8_t read_ptr = tape_f_ptr - (lfo >> 1); 
                int delayed = tape_flange[read_ptr];
                tape_sig = (tape_sig + delayed) >> 1; 
            }
            dist_lpf += (tape_sig - dist_lpf) >> 2;
            out = dist_lpf;
            break;
        }

        // MODE 4: VINYL
        case 4: {
            int vinyl_sig = signal;
            int threshold = 4095 - (cv >> 2); 
            if (skip_active) threshold -= 500; 
            
            int crackle_vol = 32; 
            if ((rand() & 4095) > threshold) { 
                int raw_crackle = (rand() & 1024) - 512;
                vinyl_sig += (raw_crackle * crackle_vol) >> 7; 
            }

            if (flip_active) { 
                hp_mem += (vinyl_sig - hp_mem) >> 2; 
                int32_t hp_sig = vinyl_sig - hp_mem;
                lp_mem += (hp_sig - lp_mem) >> 1; 
                vinyl_sig = lp_mem;
                
                vinyl_sig = (vinyl_sig * 3) >> 1; 
                if (vinyl_sig > 1500) vinyl_sig = 1500 + ((vinyl_sig - 1500) >> 3);
                if (vinyl_sig < -1500) vinyl_sig = -1500 - ((vinyl_sig + 1500) >> 3);
                
                vinyl_sig *= 4; 
            } else {
                hp_mem += (vinyl_sig - hp_mem) >> 4; vinyl_sig = vinyl_sig - hp_mem;
                lp_mem += (vinyl_sig - lp_mem) >> 2; vinyl_sig = lp_mem;
            }

            out = vinyl_sig * 2; 
            break;
        }

        // MODE 5: MP3
        case 5: {
            static int hold_sample = 0;
            static int timer = 0;
            static int packet_loss_timer = 0;
            static int16_t micro_buffer[3]; 
            static uint8_t micro_ptr = 0;

            int rate = 1 + (cv >> 5); 
            
            if (skip_active) {
                if (packet_loss_timer > 0) {
                    packet_loss_timer--;
                    micro_ptr = (micro_ptr + 1) % 3; 
                    out = micro_buffer[micro_ptr] >> 1; 
                    break; 
                } else if ((rand() & 255) < 3) { 
                    packet_loss_timer = 100 + (rand() & 2000); 
                }
            }

            timer++;
            if (timer >= rate) {
                hold_sample = signal;
                if (flip_active) hold_sample = (hold_sample / 64) * 64; 
                micro_buffer[micro_ptr] = hold_sample; 
                micro_ptr = (micro_ptr + 1) % 3;
                timer = 0;
            }
            out = hold_sample * 2; 
            break;
        }

        // MODE 6: RADIO
        case 6: {
            int32_t noisy_input = signal;

            if (flip_active) {
                noisy_input *= 16; 
                if (noisy_input > 3000) noisy_input = 3000;
                if (noisy_input < -3000) noisy_input = -3000;
                if (noisy_input > -800 && noisy_input < 800) noisy_input = 0; 
                noisy_input = noisy_input >> 2;
            }

            int tuning = 150 + (cv * 4); 
            int damp = 40; 
            
            svf_low  += (tuning * svf_band) >> 12;
            int32_t svf_high = noisy_input - svf_low - ((damp * svf_band) >> 8);
            svf_band += (tuning * svf_high) >> 12;

            int32_t radio_out = svf_band * 2; 

            if (skip_active) {
                if ((rand() & 255) > 230) {
                    radio_out += ((rand() & 4095) - 2048) >> 2; 
                }
            }

            out = radio_out;
            break;
        }

        // MODE 7: RAT
        case 7: {
            int32_t gain = 20 + (cv >> 4); 
            int32_t target = signal * gain;

            int32_t max_slew = 2000; 
            int32_t delta = target - rat_slew;
            if (delta > max_slew) delta = max_slew;
            if (delta < -max_slew) delta = -max_slew;
            
            int32_t op_amp_out = rat_slew + delta;
            rat_slew = op_amp_out; 

            int32_t threshold = flip_active ? 6000 : 2048;
            
            if (op_amp_out > threshold) op_amp_out = threshold;
            if (op_amp_out < -threshold) op_amp_out = -threshold;

            if (skip_active) {
                rat_tone += (op_amp_out - rat_tone) >> 3; 
                op_amp_out = rat_tone;
            }

            // Removed the `out = out * 2` blowout logic here!
            out = op_amp_out;
            break;
        }
    }

    // MIXING STAGE
    int32_t compensated = (out * gain_compensation[dist_mode]) >> 7;

    // OUTPUT CLIPPING
    int32_t wet_out_dac = compensated + 2048;
    if (wet_out_dac > 4095) wet_out_dac = 4095;
    if (wet_out_dac < 0) wet_out_dac = 0;

    // LAMP
    bool lamp_busy = false;
    if (blink_queue > 0) {
        lamp_busy = true;
        blink_timer++;
        if (blink_state == 0) { 
             if (blink_timer > 3000) { blink_state = 1; blink_timer = 0; LAMP_ON; } 
             else { LAMP_OFF; }
        } else { 
             if (blink_timer > 3000) { blink_state = 0; blink_timer = 0; LAMP_OFF; blink_queue--; } 
             else { LAMP_ON; }
        }
    }
    
    if (!lamp_busy) {
        if (flip_latched) {
            LAMP_ON;
        } else if (abs(out) > 500) {
            LAMP_ON;
        } else {
            LAMP_OFF;
        }
    }

    DACWRITER(wet_out_dac);   
    CLEANER_ASHWRITER(wet_out_dac); 
    YELLOW_AUDIO(wet_out_dac); 
    
    REG(I2S_CONF_REG)[0] &= ~(BIT(5)); 
    REG(I2S_INT_CLR_REG)[0]=0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= (BIT(5)); 
}


// ==========================================
// MULTI --- NEW PRESET 10 (k.odk): a multi-effect with seven effects
// ==========================================
//   0 CLEAN · 1 ECHO (stereo ping-pong) · 2 SAMPLER (one-shot, -1 .. +2 octaves) · 3 REVERSE · 4 GLITCH
//   5 FOLD + OCTAVER · 6 REVERB (it can HOWL: feedback past unity, held by a soft clip, and a slow MOD) · 7 SHORT DELAY
// FLIP = next effect · SKIP = a random other one (not faster than LOCK: fast gates don't make it flutter). The random order comes from a seed both Cafes share:
//   after a sync ("Z") the same gate into both Cafes makes the same jumps (or the phone's LINK mirrors them).
// Changes are crossfaded (F 91). BUTTON = HOLD (delay / reverb freeze, reverse / glitch keep the past),
//   in SAMPLER the button takes a new sample instead.
// EARTH (AC-coupled, depth F 95) modulates each effect: CLEAN = level (VCA) · DELAY = time (wow) ·
//   SAMPLER = pitch, and a rising EARTH triggers it · REVERSE = speed · GLITCH = chance · FOLD = drive · REVERB = size
// main out = L, ASH = R, YELLOW = a click on the beat (shared tempo "K"). The lamp blinks the effect's number.
// Tape: [0, 32K) the input's history · [32K, 64K) echo L · [64K, 96K) echo R · [96K, 112K) the sample
//       · [112K, 120K) short delay L / R · [120K, 128K) reverb
// Phone: "F <effect> <id 0..7> <0..1000>" parameters, "F 90 <n>" choose, "F 91 <v>" crossfade, "F 92" take a sample,
//        "F 93" trigger, "F 94 <0|1>" hold, "F 95 <v>" EARTH depth, "F 96 <v>" LOCK (the shortest time between changes)
#define FX_N 8
#define TD_L 32768
#define TD_R 65536
#define H_MASK 0x7FFF
#define SM_BASE 98304
#define SM_LEN 16384
#define SD_L 114688
#define SD_R 118784
#define RB_BASE 122880
RTC_DATA_ATTR volatile int16_t fx_p[FX_N][8];     // (RTC memory: the heap is tight)
volatile int      fx_want = 0, fx_now = 0;
volatile int32_t  fx_xf_len = 12000;
volatile int32_t  fx_edepth = 160;            // EARTH depth, Q8
volatile int32_t  fx_gap = 20000;             // LOCK: after a change, FLIP / SKIP are ignored this many samples (F 96)
volatile bool     fx_capture = false, fx_trig = false, fx_hold_app = false, fx_sync = false;
volatile uint32_t fx_seed = 0x2545F491;
volatile int32_t  fx_beat = 22050;            // samples per beat
volatile int32_t  fx_em = 0;                  // EARTH for the effects (AC, depth applied), -128..127
static uint32_t   fx_hw = 0;                  // history write position
// CLEAN
volatile int32_t  cl_g = 256;
// TAP DELAY
volatile int32_t  td_T = 16000 << 8, td_fb = 140, td_pp = 256, td_ratio = 4096, td_tone = 3500, td_wow = 0, td_wet = 360, td_dry = 256;
// SAMPLER
volatile int32_t  sm_rate = 4096, sm_len = 8000, sm_start = 0, sm_auto = 0, sm_tone = 4096, sm_wet = 256, sm_dry = 256;
volatile uint32_t sm_dec = 65535;
// REVERSE
volatile int32_t  rv_W = 12000, rv_speed = 4096, rv_tone = 4096, rv_wet = 256, rv_dry = 128;
// GLITCH
volatile int32_t  gl_ev = 5000, gl_chance = 30000, gl_slice = 1000, gl_len = 3, gl_var = 200, gl_pitch = 150, gl_crush = 0, gl_wet = 256;
// FOLD + OCT
volatile int32_t  fo_drive = 600, fo_bias = 0, fo_down = 150, fo_up = 50, fo_tone = 3000, fo_wet = 256, fo_dry = 0;
// REVERB
volatile int32_t  rb_fb = 3500, rb_damp = 1100, rb_width = 200, rb_ap = 2048, rb_wet = 256, rb_dry = 256;
volatile int32_t  rb_howl = 0, rb_mod = 0;                  // HOWL: feedback past unity (Q12), MOD: comb wobble depth (Q8 samples)
volatile uint32_t rb_lfo = 40000;                          // MOD rate (Q32 per sample)
volatile int32_t  rb_len[8] = {1116, 1188, 1277, 1356, 556, 441, 579, 464};
static const int32_t rb_max[8] = {1116, 1188, 1277, 1356, 556, 441, 579, 464};
volatile bool     fx_rs[FX_N] = {true, true, true, true, true, true, true, true};
// SHORT DELAY
volatile int32_t  sd_T = 1000 << 8, sd_fb = 140, sd_tone = 3000, sd_mod = 0, sd_spread = 0, sd_wet = 256, sd_dry = 256;
volatile uint32_t sd_lfo = 20000;

static inline int32_t IRAM_ATTR fx_lp(int32_t *st, int32_t x, int32_t k) { *st += ((x - *st) * k) >> 12; return *st; }
/// the input's history, interpolated: posq = absolute position, Q12
static inline int32_t IRAM_ATTR h_readq(uint32_t posq) {
  uint32_t i = (posq >> 12) & H_MASK; int32_t f = (posq >> 4) & 255;
  int32_t a = dread(i), b = dread((i + 1) & H_MASK);
  return a + (((b - a) * f) >> 8) - 2048;
}

// ---- 1 ECHO: a clear stereo delay, L line + R line, the repeats ping-pong between them ----
static int32_t td_tick(int32_t in, int32_t *rout, bool hold, bool rs) {
  static uint32_t w = 0, fill = 0; static int32_t ct = 16000 << 8, lpl = 0, lpr = 0, hpl = 0, hpr = 0;
  if (rs) { w = 0; fill = 0; ct = td_T; lpl = lpr = 0; hpl = hpr = 0; }
  ct += (td_T - ct) >> 11;
  int32_t tl = ct + fx_em * td_wow;
  if (tl < (64 << 8)) tl = 64 << 8; if (tl > (32000 << 8)) tl = 32000 << 8;
  int32_t tr = (int32_t)(((int64_t)tl * td_ratio) >> 12);
  if (tr < (64 << 8)) tr = 64 << 8; if (tr > (32000 << 8)) tr = 32000 << 8;
  int32_t rq = (int32_t)(w << 8) - tl;
  int32_t i = (rq >> 8) & 0x7FFF, f = rq & 255;
  int32_t a = dread(TD_L + i), b = dread(TD_L + ((i + 1) & 0x7FFF));
  int32_t vl = a + (((b - a) * f) >> 8) - 2048;
  rq = (int32_t)(w << 8) - tr;
  i = (rq >> 8) & 0x7FFF; f = rq & 255;
  a = dread(TD_R + i); b = dread(TD_R + ((i + 1) & 0x7FFF));
  int32_t vr = a + (((b - a) * f) >> 8) - 2048;
  if (fill < 40000) fill++;
  if (fill <= (uint32_t)(((tl > tr ? tl : tr) >> 8) + 2)) { vl = 0; vr = 0; }   // the lines still hold old tape
  fx_lp(&lpl, vl, td_tone); fx_lp(&lpr, vr, td_tone);
  hpl += (lpl - hpl) >> 8; hpr += (lpr - hpr) >> 8;                  // the repeats lose a little low end each time: clean, not muddy
  int32_t pp = td_pp, fb = hold ? 256 : td_fb;
  int32_t xl = hold ? vl : lpl - hpl, xr = hold ? vr : lpr - hpr;
  int32_t il = hold ? 0 : in, ir = hold ? 0 : ((in * (256 - pp)) >> 8);
  int32_t wl = il + ((((xl * (256 - pp) + xr * pp) >> 8) * fb) >> 8);
  int32_t wr = ir + ((((xr * (256 - pp) + xl * pp) >> 8) * fb) >> 8);
  dwrite(TD_L + w, soft_clip(wl) + 2048);
  dwrite(TD_R + w, soft_clip(wr) + 2048);
  w = (w + 1) & 0x7FFF;
  int32_t dry = (in * td_dry) >> 8;
  *rout = dry + ((vr * td_wet) >> 8);
  return dry + ((vl * td_wet) >> 8);
}

// ---- 2 SAMPLER: a slice of the recent past, played once per trigger at -1 .. +2 octaves ----
static int32_t sm_tick(int32_t in, bool rs) {
  static int32_t cp = -1; static uint32_t csrc = 0;
  static int32_t pq[2] = {0, 0}, n[2] = {0, 0}, len[2] = {1, 1}, env[2] = {0, 0}, rate[2] = {4096, 4096};
  static int vi = 0; static uint32_t ac = 0; static int32_t lp = 0; static bool ehi = false;
  if (rs) { fx_capture = true; n[0] = n[1] = 0; ac = 0; lp = 0; }
  if (fx_capture) { fx_capture = false; cp = 0; csrc = fx_hw - SM_LEN; }
  if (cp >= 0) {                                               // copy the last SM_LEN samples, a little per sample
    for (int k = 0; k < 32 && cp < SM_LEN; k++, cp++) dwrite(SM_BASE + cp, dread((csrc + cp) & H_MASK));
    if (cp >= SM_LEN) cp = -1;
  }
  bool trig = false;
  if (fx_trig) { fx_trig = false; trig = true; }
  if (!ehi && pc_emod > 40) { ehi = true; trig = true; } else if (ehi && pc_emod < 10) ehi = false;   // EARTH rises = trigger
  if (sm_auto > 0 && ++ac >= (uint32_t)sm_auto) { ac = 0; trig = true; }
  if (trig) {
    if (n[vi] > 256) n[vi] = 256;                              // the old voice fades out quickly
    vi ^= 1;
    int32_t r = sm_rate + (int32_t)(((int64_t)sm_rate * fx_em) >> 7);   // EARTH = pitch (up to an octave)
    if (r < 1024) r = 1024; if (r > 32768) r = 32768;
    rate[vi] = r;
    pq[vi] = sm_start << 12; len[vi] = sm_len; n[vi] = sm_len; env[vi] = 65535;
  }
  int32_t sum = 0;
  for (int k = 0; k < 2; k++) {
    if (n[k] <= 0) continue;
    int32_t i = pq[k] >> 12;
    if (i >= SM_LEN - 1) { n[k] = 0; continue; }
    int32_t f = (pq[k] >> 4) & 255;
    int32_t a = dread(SM_BASE + i), b = dread(SM_BASE + i + 1);
    int32_t v = a + (((b - a) * f) >> 8) - 2048;
    int32_t done = len[k] - n[k];
    int32_t g = env[k] >> 4;                                    // 0..4095
    if (done < 64) g = (g * done) >> 6;
    if (n[k] < 256) g = (g * n[k]) >> 8;
    sum += (v * g) >> 12;
    env[k] = (int32_t)(((uint32_t)env[k] * sm_dec) >> 16);
    pq[k] += rate[k]; n[k]--;
  }
  if (sm_tone < 4096) sum = fx_lp(&lp, sum, sm_tone);
  return ((in * sm_dry) >> 8) + ((sum * sm_wet) >> 8);
}

// ---- 3 REVERSE: two heads read the past backwards, sin² windows half a length apart ----
static int32_t rv_tick(int32_t in, bool rs) {
  static uint32_t anc[2] = {0, 0}; static int32_t t[2] = {0, 0}, p[2] = {0, 0}; static int32_t lp = 0;
  int32_t W = rv_W; if (W < 256) W = 256; if (W > 15000) W = 15000;
  if (rs) { anc[0] = anc[1] = fx_hw; t[0] = 0; t[1] = W / 2; p[0] = 0; p[1] = (W / 2) * rv_speed; lp = 0; }
  int32_t sp = rv_speed + (int32_t)(((int64_t)rv_speed * fx_em) >> 8);    // EARTH = speed
  if (sp < 1024) sp = 1024; if (sp > 8192) sp = 8192;
  int32_t sum = 0;
  for (int k = 0; k < 2; k++) {
    if (t[k] >= W) { t[k] = 0; p[k] = 0; anc[k] = fx_hw; }
    int32_t x = (t[k] << 8) / W;                                   // 0..255
    int32_t ix = x < 128 ? x : 255 - x;
    int32_t g = mo_win[ix > 128 ? 128 : ix];
    int32_t v = h_readq(((anc[k] - 1) << 12) - (uint32_t)p[k]);
    sum += (v * g) >> 12;
    p[k] += sp; t[k]++;
  }
  if (rv_tone < 4096) sum = fx_lp(&lp, sum, rv_tone);
  return ((in * rv_dry) >> 8) + ((sum * rv_wet) >> 8);
}

// ---- 4 GLITCH: on a grid, one of eight moves happens to the recent past ----
//   0 STUTTER · 1 BACKWARDS · 2 RATCHET (shorter every repeat) · 3 PITCH STEPS (a fifth up every repeat)
//   4 TAPE STOP · 5 SCATTER (a slice from further back) · 6 CHOP (gated in 1/32s) · 7 CRUSH
// VARIETY lets more moves in, and makes everything more random: slice length, how long a move lasts,
// when the next one comes (the grid gets skips and doubles), backwards / pitch on single repeats.
// All the dice come from a score both Cafes share (the same after "Z").
volatile bool gl_resync = false;
static int32_t gl_tick(int32_t in, bool hold, bool rs) {
  static uint32_t bc = 0, n = 0, sst = 0, next = 5000, tq = 0;
  static int32_t left = 0, total = 1, cur = 1, pq = 0, rate = 4096, mv = 0, held = 0, hn = 0, rr = 0;
  if (rs || gl_resync) { gl_resync = false; bc = 0; n = 0; left = 0; next = gl_ev; }
  if (++bc >= next) {
    bc = 0;
    uint32_t h = mo_hash(fx_seed ^ (n * 0x9E3779B9u)), h2 = mo_hash(h + 0x7F4A7C15u), h3 = mo_hash(h2 ^ 0x5bd1e995u);
    n++;
    int32_t var = gl_var;                                           // 0..256
    // when the next one comes: on the grid, but with more VARIETY it skips, doubles and halves
    next = gl_ev;
    if ((int32_t)(h3 & 0xFF) < var) { static const uint8_t mul[6] = {1, 2, 3, 4, 1, 1}; next = gl_ev * mul[(h3 >> 8) % 6]; if (((h3 >> 12) & 3) == 0) next = gl_ev / 2; }
    if (next < 128) next = 128;
    int32_t ch = gl_chance + fx_em * 400; if (ch < 0) ch = 0;         // EARTH = chance
    if ((int32_t)(h & 0xFFFF) < ch && !(hold && left > 0)) {
      int nm = 1 + ((var * 7) >> 8);                                // 1..8 moves allowed
      mv = (int32_t)((h >> 16) % (uint32_t)nm);
      int32_t len = 1 + (int32_t)((h2 & 0xFF) % (uint32_t)(gl_len > 0 ? gl_len : 1));
      total = gl_ev * len; if (total > 24000) total = 24000; if (total < 256) total = 256;
      left = total;
      // slice: the SLICE setting, randomly 1/4 .. 2x of it with more variety
      int32_t sl = gl_slice;
      if ((int32_t)((h2 >> 8) & 0xFF) < var) { static const int16_t sm[6] = {64, 96, 128, 256, 384, 512}; sl = (sl * sm[(h2 >> 16) % 6]) >> 8; }
      if (sl < 64) sl = 64; if (sl > 8000) sl = 8000;
      cur = sl;
      int32_t back = sl + 16;
      if (mv == 5) back += (int32_t)((h3 >> 16) % 16000);           // SCATTER
      sst = fx_hw - back;
      rate = 4096;
      if ((int32_t)((h >> 24) & 0xFF) < gl_pitch) { static const int32_t pr[5] = {2048, 8192, 6144, 2731, 3069}; rate = pr[(h2 >> 24) % 5]; }
      pq = 0; rr = 0;
      tq = (uint32_t)(fx_hw - 64) << 12;
    }
  }
  if (left <= 0) return in;
  if (!hold) left--;
  int32_t v;
  switch (mv) {
    case 4: {                                                       // TAPE STOP
      int32_t r = (int32_t)(((int64_t)4096 * left) / total);
      tq += (uint32_t)r; v = h_readq(tq);
    } break;
    case 6: {                                                       // CHOP
      int32_t per = gl_ev / 4; if (per < 128) per = 128;
      int32_t ph = (total - left) % per, half = per / 2, g;
      if (ph < 32) g = ph * 8; else if (ph < half - 32) g = 256; else if (ph < half) g = (half - ph) * 8; else g = 0;
      v = (in * g) >> 8;
    } break;
    case 7: {                                                       // CRUSH
      int32_t hl = 2 + (gl_crush >> 1);
      if (++hn >= hl) { hn = 0; held = in & ~((1 << (4 + (gl_crush >> 3))) - 1); }
      v = held;
    } break;
    default: {                                                      // STUTTER · BACKWARDS · RATCHET · PITCH STEPS · SCATTER
      int32_t off = pq >> 12;
      pq += rate;
      if ((pq >> 12) >= cur) {                                      // one repeat done
        pq -= cur << 12; if (pq < 0) pq = 0;
        rr++;
        uint32_t hr = mo_hash(n * 131u + (uint32_t)rr);
        if (mv == 2 && cur > 256) cur = (cur * 3) >> 2;             // RATCHET
        if (mv == 3) { rate = (rate * 3) >> 1; if (rate > 16384) rate = 2048; }   // PITCH STEPS
        if ((int32_t)(hr & 0xFF) < (gl_var >> 2)) rate = ((hr >> 8) & 1) ? 8192 : 2048;   // a random octave now and then
      }
      bool back = (mv == 1) || ((int32_t)((mo_hash(n * 77u + (uint32_t)rr) >> 4) & 0xFF) < (gl_var >> 3));
      int32_t o = back ? cur - 1 - off : off;
      if (o < 0) o = 0; if (o >= cur) o = cur - 1;
      v = dread((sst + o) & H_MASK) - 2048;
      int32_t e = off < 32 ? off : (cur - off < 32 ? cur - off : 32); if (e < 0) e = 0;
      v = (v * e) >> 5;
      if (gl_crush) { if (++hn >= 1 + (gl_crush >> 2)) { hn = 0; held = v; } v = held; }
    } break;
  }
  int32_t fe = left < 128 ? left * 2 : 256;                          // a soft return at the end of a move
  return in + (((v - in) * ((gl_wet * fe) >> 8)) >> 8);
}

// ---- 5 FOLD + OCTAVER: an octave down (flip-flop), an octave up (rectifier), into a wave folder ----
static int32_t fo_tick(int32_t in, bool rs) {
  static int32_t env = 0, lpd = 0, ff = 1, lp = 0; static bool pos = false;
  if (rs) { env = 0; lpd = 0; ff = 1; lp = 0; pos = false; }
  int32_t a = in < 0 ? -in : in;
  env += (a > env) ? (a - env) >> 4 : (a - env) >> 9;
  lpd += (in - lpd) >> 3;
  if (!pos && lpd > 40) { pos = true; ff = -ff; } else if (pos && lpd < -40) pos = false;
  int32_t down = ff * env;
  int32_t up = (a - env) * 2;
  int32_t x = in + ((down * fo_down) >> 8) + ((up * fo_up) >> 8);
  int32_t drv = fo_drive + fx_em * 12; if (drv < 64) drv = 64;              // EARTH = drive
  x = ((x * drv) >> 8) + fo_bias;
  int32_t tf = (x + 2048) & 8191; if (tf >= 4096) tf = 8191 - tf;
  x = tf - 2048;
  if (fo_tone < 4096) x = fx_lp(&lp, x, fo_tone);
  int32_t g = (env * 3) >> 3; if (g < 40) g = 40; if (g > 110) g = 110;   // as loud as the input, not full scale
  x = (x * g) >> 8;
  return ((in * fo_dry) >> 8) + ((x * fo_wet) >> 8);
}

// ---- 6 REVERB: four combs (damped, wobbling) + two allpasses per side, on the tape (lo-fi, 12 bits) ----
// HOWL pushes the combs' feedback past unity: they sing by themselves, held by the soft clip in the loop
// (a DC blocker keeps them from drifting). MOD wobbles each comb's length (a slow triangle, each its own phase).
static int32_t rb_tick(int32_t in, int32_t *rout, bool hold, bool rs) {
  static uint32_t idx[8], lph = 0; static int32_t st[4], dc[4]; static int32_t clr = 0, fade = 0;
  static int32_t base[8]; static bool based = false;
  if (!based) { int32_t o = RB_BASE; for (int k = 0; k < 8; k++) { base[k] = o; o += rb_max[k]; } based = true; }
  if (rs) { for (int k = 0; k < 8; k++) idx[k] = 0; for (int k = 0; k < 4; k++) { st[k] = 0; dc[k] = 0; } clr = 0; fade = 0; }
  if (clr < 6977) {                                               // wipe the old tail first (~10 ms)
    for (int k = 0; k < 16 && clr < 6977; k++, clr++) dwrite(RB_BASE + clr, 2048);
    return in;
  }
  if (fade < 4096) fade += 4;
  int32_t x = hold ? 0 : (in >> 2);
  int32_t fb = hold ? 4090 : rb_fb + rb_howl + fx_em * 3;          // EARTH = size (and howl)
  if (fb > 4600) fb = 4600; if (fb < 2000) fb = 2000;
  int32_t damp = hold ? 0 : rb_damp;
  lph += rb_lfo;
  int32_t y[4];
  for (int k = 0; k < 4; k++) {
    int32_t L = rb_len[k]; if (L > rb_max[k]) L = rb_max[k]; if (L < 64) L = 64;
    if (idx[k] >= (uint32_t)L) idx[k] = 0;
    // MOD: read a little ahead of the write (= a slightly shorter comb), wobbling
    int32_t v;
    if (rb_mod) {
      uint32_t ph = lph + (uint32_t)k * 0x40000000u;
      int32_t tri = (int32_t)(ph >> 16); tri = tri < 32768 ? tri : 65535 - tri;       // 0..32767
      int32_t m = (int32_t)(((int64_t)tri * rb_mod) >> 15);                             // Q8 samples
      int32_t r = (int32_t)(idx[k] << 8) + m;
      int32_t i = (r >> 8) % L, f = r & 255, j = (i + 1) % L;
      int32_t a = dread(base[k] + i), b = dread(base[k] + j);
      v = a + (((b - a) * f) >> 8) - 2048;
    } else {
      v = dread(base[k] + idx[k]) - 2048;
    }
    st[k] = v + (((st[k] - v) * damp) >> 12);
    dc[k] += (st[k] - dc[k]) >> 10;
    int32_t loop = st[k] - dc[k];
    dwrite(base[k] + idx[k], soft_clip(x + ((loop * fb) >> 12)) + 2048);
    idx[k]++;
    y[k] = v;
  }
  int32_t s[2] = {y[0] + y[2], y[1] + y[3]};
  for (int c = 0; c < 2; c++) {
    for (int j = 0; j < 2; j++) {
      int k = 4 + c * 2 + j;
      int32_t L = rb_len[k]; if (L > rb_max[k]) L = rb_max[k]; if (L < 16) L = 16;
      if (idx[k] >= (uint32_t)L) idx[k] = 0;
      int32_t b = dread(base[k] + idx[k]) - 2048;
      int32_t o = b - s[c];
      dwrite(base[k] + idx[k], soft_clip(s[c] + ((b * rb_ap) >> 12)) + 2048);
      idx[k]++;
      s[c] = o;
    }
  }
  int32_t l = s[0], r = s[1];
  int32_t w = rb_width;
  int32_t ol = (l * (256 + w) + r * (256 - w)) >> 9, orr = (r * (256 + w) + l * (256 - w)) >> 9;
  int32_t g = (rb_wet * fade) >> 12;
  int32_t dry = (in * rb_dry) >> 8;
  *rout = dry + ((orr * g) >> 9);                                        // (half as loud as before)
  return dry + ((ol * g) >> 9);
}

// ---- 7 SHORT DELAY: 1 .. 90 ms, two lines (L / R), feedback through a soft clip and a damping filter,
//      a slow wobble (chorus / flanger), R a little longer (SPREAD) and wobbling the other way. EARTH = time.
static int32_t sd_tick(int32_t in, int32_t *rout, bool hold, bool rs) {
  static uint32_t w = 0, ph = 0, fill = 0; static int32_t lpl = 0, lpr = 0, ct = 1000 << 8, dcl = 0, dcr = 0;
  if (rs) { w = 0; ph = 0; lpl = lpr = 0; ct = sd_T; fill = 0; dcl = dcr = 0; }
  ct += (sd_T - ct) >> 10;
  ph += sd_lfo;
  int32_t tri = (int32_t)(ph >> 16); tri = tri < 32768 ? tri : 65535 - tri;          // 0..32767
  int32_t m = (int32_t)(((int64_t)tri * sd_mod) >> 15);
  int32_t e = (int32_t)(((int64_t)ct * fx_em) >> 8);                                  // EARTH = time (up to ±50 %)
  int32_t tl = ct + m + e;
  int32_t tr = (int32_t)(((int64_t)ct * (4096 + sd_spread)) >> 12) + (sd_mod - m) + e;
  if (tl < (16 << 8)) tl = 16 << 8; if (tl > (4090 << 8)) tl = 4090 << 8;
  if (tr < (16 << 8)) tr = 16 << 8; if (tr > (4090 << 8)) tr = 4090 << 8;
  int32_t rq = (int32_t)(w << 8) - tl, i = (rq >> 8) & 0xFFF, f = rq & 255;
  int32_t a = dread(SD_L + i), b = dread(SD_L + ((i + 1) & 0xFFF));
  int32_t vl = a + (((b - a) * f) >> 8) - 2048;
  rq = (int32_t)(w << 8) - tr; i = (rq >> 8) & 0xFFF; f = rq & 255;
  a = dread(SD_R + i); b = dread(SD_R + ((i + 1) & 0xFFF));
  int32_t vr = a + (((b - a) * f) >> 8) - 2048;
  if (fill < 5000) fill++;
  if (fill <= 4100) { vl = 0; vr = 0; }
  fx_lp(&lpl, vl, sd_tone); fx_lp(&lpr, vr, sd_tone);
  dcl += (lpl - dcl) >> 9; dcr += (lpr - dcr) >> 9;
  int32_t fb = hold ? 256 : sd_fb;
  int32_t xl = hold ? vl : lpl - dcl, xr = hold ? vr : lpr - dcr;
  int32_t il = hold ? 0 : in;
  dwrite(SD_L + w, soft_clip(il + ((xl * fb) >> 8)) + 2048);
  dwrite(SD_R + w, soft_clip(il + ((xr * fb) >> 8)) + 2048);
  w = (w + 1) & 0xFFF;
  int32_t dry = (in * sd_dry) >> 8;
  *rout = dry + ((vr * sd_wet) >> 8);
  return dry + ((vl * sd_wet) >> 8);
}

static inline void fx_run(int e, int32_t in, int32_t *l, int32_t *r, bool hold) {
  bool rs = fx_rs[e]; fx_rs[e] = false;
  switch (e) {
    case 0: { int32_t g = cl_g + ((cl_g * fx_em) >> 7); if (g < 0) g = 0;     // EARTH = level (VCA)
              *l = *r = (in * g) >> 8; } break;
    case 1: *l = td_tick(in, r, hold, rs); break;
    case 2: *l = sm_tick(in, rs); *r = *l; break;
    case 3: *l = rv_tick(in, rs); *r = *l; break;
    case 4: *l = gl_tick(in, hold, rs); *r = *l; break;
    case 5: *l = fo_tick(in, rs); *r = *l; break;
    case 6: *l = rb_tick(in, r, hold, rs); break;
    default: *l = sd_tick(in, r, hold, rs); break;
  }
}

void IRAM_ATTR multi() {
  static uint32_t gen_seen = 0xFFFFFFFF; static bool was_in_menu = true;
  static int cur = 0, prev = 0; static int32_t xf = 0, xfl = 1;
  static bool last_frozen = false;
  static int flip_i = 0, skip_i = 0; static bool flip_l = true, skip_l = true;
  static uint32_t rng_n = 0, bc = 0; static int click = 0;
  static int blinks = 0, bt = 0;
  static uint32_t since = 0;                         // samples since the last change (LOCK)
  if (preset_mode) { was_in_menu = true; }
  else if (was_in_menu || gen_seen != preset_gen) {
    gen_seen = preset_gen; was_in_menu = false;
    audio_frozen_state = false; lamp = false; last_frozen = false;
    cur = fx_want; prev = cur; xf = 0; fx_now = cur;
    for (int k = 0; k < FX_N; k++) fx_rs[k] = true;
    flip_i = FLIPPERAT ? 2000 : 0; flip_l = flip_i > 0;
    skip_i = SKIPPERAT ? 2000 : 0; skip_l = skip_i > 0;
    blinks = (cur + 1) * 2; bt = 0;
  }
  DACWRITER(pout)
  gyo = ADCREADER
  pc_samples++;
  earth_ac();
  fx_em = (pc_emod * fx_edepth) >> 8;
  int32_t in = gyo - 2048;

  // FLIP = next, SKIP = a random other one (same seed on both Cafes), at most one change per LOCK time
  if (since < 0x7FFFFFFF) since++;
  bool open = since >= (uint32_t)fx_gap;
  if (FLIPPERAT) { if (flip_i < 2000) flip_i += 500; } else { if (flip_i > 0) flip_i -= 50; }
  if (flip_i > 1500) { if (!flip_l) { flip_l = true; if (open) { fx_want = (fx_want + 1) % FX_N; since = 0; open = false; } } } else if (flip_i < 100) flip_l = false;
  if (SKIPPERAT) { if (skip_i < 2000) skip_i += 500; } else { if (skip_i > 0) skip_i -= 50; }
  if (skip_i > 1500) {
    if (!skip_l) { skip_l = true; if (open) { fx_want = (fx_want + 1 + (int)(mo_hash(fx_seed + rng_n * 0x632BE5ABu) % (FX_N - 1))) % FX_N; rng_n++; since = 0; } }
  } else if (skip_i < 100) skip_l = false;
  if (fx_sync) { fx_sync = false; rng_n = 0; bc = 0; gl_resync = true; click = 300; }

  // a change: the old one fades out while the new one fades in
  int want = fx_want; if (want < 0 || want >= FX_N) want = 0;
  if (want != cur && xf == 0) {
    prev = cur; cur = want; fx_rs[cur] = true;
    xfl = fx_xf_len; if (xfl < 64) xfl = 64; xf = xfl;
    fx_now = cur; blinks = (cur + 1) * 2; bt = 0;
  }

  // BUTTON: HOLD, or in SAMPLER a new sample
  bool bchg = audio_frozen_state != last_frozen; last_frozen = audio_frozen_state;
  if (bchg && cur == 2) fx_capture = true;
  bool hold = (audio_frozen_state && cur != 2) || fx_hold_app;

  // the input's history (kept while HOLD, so reverse / glitch play the held past)
  if (!hold) dwrite(fx_hw & H_MASK, gyo);
  fx_hw++;

  int32_t l, r;
  fx_run(cur, in, &l, &r, hold);
  if (xf > 0) {
    int32_t pl, pr;
    fx_run(prev, in, &pl, &pr, hold);
    int32_t a = (int32_t)(((int64_t)(xfl - xf) << 12) / xfl);           // 0 .. 4096
    l = (l * a + pl * (4096 - a)) >> 12;
    r = (r * a + pr * (4096 - a)) >> 12;
    xf--;
  }
  int32_t v = l + 2048; if (v > 4095) v = 4095; if (v < 0) v = 0;
  pout = v;
  int32_t vr = r + 2048; if (vr > 4095) vr = 4095; if (vr < 0) vr = 0;
  ASHWRITER(vr);

  if (++bc >= (uint32_t)fx_beat) { bc = 0; click = 300; }
  if (click > 0) { click--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); }

  // lamp: the effect's number in blinks after a change, then ON while HOLD
  if (blinks > 0) {
    if (++bt >= 4000) { bt = 0; blinks--; }
    if ((blinks & 1) == 0 && blinks > 0) { LAMP_ON; } else { LAMP_OFF; }
  } else if (hold) { LAMP_ON; } else { LAMP_OFF; }

  t = fx_hw & H_MASK;
  pc_wpos = fx_hw & H_MASK; pc_ppos = fx_hw & H_MASK;
  pc_flip = FLIPPERAT ? 1 : 0; pc_skip = SKIPPERAT ? 1 : 0;

  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////

// ==========================================
// ARP_DELAY --- NEW PRESET 11 (k.odk): MULTI's stereo tap delay on its own, for the phone's arpeggiator
// ==========================================
// Patch the iPhone's audio (coco duo, ARP) into the Cafe's input. The tempo is shared both ways:
// the phone sends it ("K"), and SKIP on the Cafe = tap tempo (the phone's arpeggio follows).
// FLIP / BUTTON / the phone's HOLD = hold (the repeats go on). EARTH = wow (depth F 95).
// Parameters: the same as MULTI's TAP DELAY ("F 1 <id> <v>"). main out = L, ASH = R, YELLOW = click on the beat.
void IRAM_ATTR arpdelay() {
  static uint32_t gen_seen = 0xFFFFFFFF; static bool was_in_menu = true;
  static uint32_t bc = 0; static int click = 0;
  if (preset_mode) { was_in_menu = true; }
  else if (was_in_menu || gen_seen != preset_gen) {
    gen_seen = preset_gen; was_in_menu = false;
    audio_frozen_state = false; lamp = false;
    fx_rs[1] = true; bc = 0;
  }
  DACWRITER(pout)
  gyo = ADCREADER
  pc_samples++;
  earth_ac();
  fx_em = (pc_emod * fx_edepth) >> 8;
  if (skip_press()) { tap_note(); bc = 0; click = 300; }
  if (fx_sync) { fx_sync = false; bc = 0; click = 300; }
  bool hold = FLIPPERAT || audio_frozen_state || fx_hold_app;
  int32_t in = gyo - 2048, l, r;
  bool rs = fx_rs[1]; fx_rs[1] = false;
  l = td_tick(in, &r, hold, rs);
  int32_t v = l + 2048; if (v > 4095) v = 4095; if (v < 0) v = 0;
  pout = v;
  int32_t vr = r + 2048; if (vr > 4095) vr = 4095; if (vr < 0) vr = 0;
  ASHWRITER(vr);
  if (++bc >= (uint32_t)fx_beat) { bc = 0; click = 300; }
  if (click > 0) { click--; YELLOW_PULSE(4095); } else { YELLOW_PULSE(0); }
  if (hold || click > 200) { LAMP_ON; } else { LAMP_OFF; }
  pc_wpos = 0; pc_ppos = 0;
  pc_flip = FLIPPERAT ? 1 : 0; pc_skip = SKIPPERAT ? 1 : 0;
  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}
/////////////////////////////////////////////////////////END//////////////////////////////////////////////////////
