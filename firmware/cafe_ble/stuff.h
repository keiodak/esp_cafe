// stuff.h — cafe_ble: the Cafe's outputs, inputs, BUTTON, lamp and tape (from Apple π / the original firmware)
#include "setup.h"
#include <esp_heap_caps.h>

#define SETUPPERS initDEL();
#define PRESETTER(p) attachInterrupt(2, p, FALLING);      // a preset = the audio interrupt (one call per sample)

// =========================================================
// INPUTS: BUTTON, FLIP, SKIP, EARTH
// =========================================================
#define BUTTONEST REG(GPIO_IN1_REG)[0] & 0x1              // 0 = pressed
#define FLIPPERAT REG(GPIO_IN1_REG)[0] & 0x8
#define SKIPPERAT REG(GPIO_IN1_REG)[0] & 0x4
#define DOUBLECLK attachInterrupt(32, doubleclicker, CHANGE);

// EARTH, 0..255 (EARTHREAD) and 12 bit (earth_raw12). Without Bluetooth it comes from the original path (the SAR's
// FIFO), fresh every sample (earth_fifo, called with every DAC write); with Bluetooth the radio takes ADC2 and EARTH
// is read 2000x a second by earth_tick (cafe_ble.ino).
volatile int earth_now = 0;
volatile int earth_raw12 = 0;
#define EARTHREAD (earth_now)
static inline void earth_fifo() {
  if (cafe_no_ble) { int r = (REG(I2S_FIFO_RD_REG)[0] & 0x7FF) << 1; earth_raw12 = r; earth_now = r >> 4; }
}
volatile int earth_last_state = 0;                        // EARTH as a switch (COCO_MOD: record on / off)
const int TRIGGER_ON_THRESHOLD = 100;                     // (a 4 V midpoint, for a 2 V – 6 V LFO)
const int TRIGGER_OFF_THRESHOLD = 85;

// =========================================================
// LAMP
// =========================================================
bool lamp;
volatile bool preset_mode = false;                        // the BUTTON menu is open
volatile bool os_blink_active = false;                    // the menu is blinking a number: presets leave the lamp alone
#define LAMPLIGHT \
  if (BUTTONEST) { \
      if (lamp) REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); \
      else REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1); \
  }
#define LAMPLIGHT_OVERRIDE \
  if (lamp) REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); \
  else REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1);
#define LAMP_ON  do { if(!preset_mode && !os_blink_active && BUTTONEST) REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); } while(0)
#define LAMP_OFF do { if(!preset_mode && !os_blink_active && BUTTONEST) REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1); } while(0)

// =========================================================
// OUTPUTS: main (the codec, over SPI3), ASH (the ESP32's DAC), YELLOW (ten GPIO pins)
// =========================================================
#define SPIWRITER(d) \
  REG(SPI3_W8_REG) \
  [0] = (d) << 16; \
  REG(SPI3_CMD_REG) \
  [0] = BIT(18);
#define DACWRITER(p) earth_fifo(); SPIWRITER(0x9000 | (p))   // main out (and EARTH, without Bluetooth)
#define ADCREADER ((REG(SPI3_W0_REG)[0]) >> 16) & 0xFFF;     // the input

// ASH: AC only, ×2 into a limiter, 8 bits (Apple π's "compressed" ASH)
inline void write_ash_compressed(int raw_val) {
    // DC Blocker  and extracting AC signal
    static int32_t dc_tracker = 2048 << 12;
    dc_tracker += ((raw_val << 12) - dc_tracker) >> 12; 
    int32_t ac_only = raw_val - (dc_tracker >> 12); 
    
    // Boosting by 2 to pull quiet sounds up
    ac_only = ac_only * 2; 
    
    // Hard Limiting (clamp at 12-bit cieling)
    if (ac_only > 2047) ac_only = 2047;
    if (ac_only < -2048) ac_only = -2048;
    
    // Scale to full 8-bit range
    int32_t out_8bit = (ac_only + 2048) >> 4; 
    
    // Safety Clipping
    if (out_8bit > 255) out_8bit = 255;
    if (out_8bit < 0) out_8bit = 0;
    
    // Write to the hardware DAC
    REG(ESP32_RTCIO_PAD_DAC1)[0] = BIT(10) | BIT(17) | BIT(18) | ((out_8bit & 0xFF) << 19);
}
#define ASHWRITER(a) write_ash_compressed(a)

#define YELLOW_MASK (BIT(12) | BIT(13) | BIT(14) | BIT(15) | BIT(16) | BIT(17) | BIT(21) | BIT(22) | BIT(26) | BIT(27))
// YELLOW as a rough DAC: 0..4095 -> how many of its ten pins are on (dithered)
inline void write_yellow_audio(int raw_val) {
    static int32_t yellow_error = 0;
    
    // TPDF Dither
    int32_t dither = (rand() & 127) - (rand() & 127);
    int32_t target = raw_val + dither + yellow_error;
    
    // Map 12 bit audio (4095 steps) to 10 hardware pins (4095 / 10 = ~409)
    int32_t pins_on = target / 409;
    
    if (pins_on > 10) pins_on = 10;
    if (pins_on < 0) pins_on = 0;
    
    // Save discarded remainder
    yellow_error = target - (pins_on * 409);
    
    uint32_t mask = 0;
    if (pins_on >= 1) mask |= BIT(12);
    if (pins_on >= 2) mask |= BIT(13);
    if (pins_on >= 3) mask |= BIT(14);
    if (pins_on >= 4) mask |= BIT(15);
    if (pins_on >= 5) mask |= BIT(16);
    if (pins_on >= 6) mask |= BIT(17);
    if (pins_on >= 7) mask |= BIT(21);
    if (pins_on >= 8) mask |= BIT(22);
    if (pins_on >= 9) mask |= BIT(26);
    if (pins_on >= 10) mask |= BIT(27);
    
    REG(GPIO_OUT_W1TC_REG)[0] = YELLOW_MASK;
    REG(GPIO_OUT_W1TS_REG)[0] = mask;
}
#define YELLOW_AUDIO(a) write_yellow_audio(a)

// =========================================================
// PRESETS AND THE BUTTON
// =========================================================
int preset;                                               // the preset playing (pool[] in cafe_ble.ino)
int active_preset_count = 1;
volatile uint32_t press_time = 0;
volatile uint32_t release_time = 0;
volatile bool is_pressed = false;
volatile int preset_counter = 0;
volatile bool audio_frozen_state = false;                 // BUTTON's short press: the tape held (lamp on)

// BUTTON (Apple π): a short press = freeze on / off · a long press (0.8 s) opens the menu, short presses count,
// another long press loads that preset. Times from timer group 0 (counting at 2.5 MHz).
void IRAM_ATTR doubleclicker() {
  int buttnow = BUTTONEST; // 0 is pressed, 1 is released

  // Force timer update and read the lower 32 bits
  REG(TIMG0_T0UPDATE_REG)[0] = BIT(1); 
  uint32_t current_time = REG(TIMG0_T0LO_REG)[0]; 

  if (buttnow == 0) { 
    // === PRESS ===
    // register a new press if it has been released for 100ms (250,000 ticks)
    if (!is_pressed && (current_time - release_time > 250000)) { 
       is_pressed = true;
       press_time = current_time;
    }
  } else { 
    // === RELEASE ===
    // register a release if it is currently pressed AND has been held for 50ms (125,000 ticks)
    if (is_pressed && (current_time - press_time > 125000)) { 
       is_pressed = false;
       release_time = current_time;
       
       // Unsigned 32-bit math automatically handles timer overflow
       uint32_t hold_time = current_time - press_time;

       // Check if held for more than 0.8 seconds (2,000,000 ticks)
       if (hold_time > 2000000) { 
          // LONG PRESS DETECTED
          preset_mode = !preset_mode; 
          
          if (preset_mode) {
            preset_counter = 0; 
          } else {
            // Exiting mode: the preset counted
            preset = preset_counter % active_preset_count;
            // set audio_frozen_state so preset changing doesn't 
            // record over transferred buffers
            audio_frozen_state = true; 
          }
       } else if (preset_mode) {
          // SHORT PRESS (While in Preset Mode)
          preset_counter++;
          lamp = true; 
          LAMPLIGHT; 
       } else {
          // NORMAL SHORT PRESS (Toggles Lamp)
          lamp = !lamp; 
          audio_frozen_state = lamp;
          LAMPLIGHT; 
       }
    }
  }
}

// =========================================================
// THE TAPE: 2^17 samples of 12 bits, two to three bytes. With Bluetooth there is no single free block that big,
// so it is 128 pieces of 1024 samples (1.5 KB), the last one in RTC memory.
// =========================================================
#define DELAYSIZE (1 << 17)
#define DCHUNK_BITS 10
#define DCHUNKS (DELAYSIZE >> DCHUNK_BITS)
#define DCHUNK_BYTES (((1 << DCHUNK_BITS) * 3) >> 1)
uint8_t *dchunk[DCHUNKS];
RTC_NOINIT_ATTR static uint8_t dchunk_rtc[DCHUNK_BYTES];
static int t;                                             // the head
static int delayskp;                                      // COCO_MOD: the loop point (SKIP)
static int lastskp;
int gyo;                                                  // the input, this sample
volatile int pout;                                        // the main out, this sample

int IRAM_ATTR dread(int ptr) {                            // read a sample
  uint8_t *dp = dchunk[(ptr >> DCHUNK_BITS) & (DCHUNKS - 1)];
  ptr = (ptr & ((1 << DCHUNK_BITS) - 1)) * 3;
  int biz = ptr & 1;
  int forsh = biz << 2;
  int zut = dp[(ptr >> 1) + biz] << 4;
  zut |= (dp[(ptr >> 1) + 1 - biz] & (0xF << forsh)) >> forsh;
  return zut;
}
void IRAM_ATTR dwrite(int ptr, int val) {                 // write a sample (0..4095)
  if (val < 0) val = 0; if (val > 4095) val = 4095;
  uint8_t *dp = dchunk[(ptr >> DCHUNK_BITS) & (DCHUNKS - 1)];
  ptr = (ptr & ((1 << DCHUNK_BITS) - 1)) * 3;
  int biz = ptr & 1;
  int forsh = biz << 2;
  dp[(ptr >> 1) + biz] = (uint8_t)(val >> 4);
  dp[(ptr >> 1) + 1 - biz] &= (uint8_t)(0xF << (4 - forsh));
  dp[(ptr >> 1) + 1 - biz] |= (uint8_t)((val & 0xF) << forsh);
}
#define FILLNOISE for (int i = 0; i < DELAYSIZE; i++) dwrite(i, rand() & 4095);

// the tape, then the hardware: the ADC (initDIG, setup.h), the codec on SPI3, the pins
void initDEL() {
  bool ok = true;
  for (int i = 0; i < DCHUNKS - 1; i++) { dchunk[i] = (uint8_t *)heap_caps_malloc(DCHUNK_BYTES, MALLOC_CAP_8BIT); if (!dchunk[i]) ok = false; }
  dchunk[DCHUNKS - 1] = dchunk_rtc;
  if (!ok) {                                              // no memory for the tape: the lamp flickers for ever
    Serial.printf("FATAL: no memory for the tape (free %u, largest %u)\n", (unsigned)heap_caps_get_free_size(MALLOC_CAP_8BIT), (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
    while (1) { REG(GPIO_OUT1_W1TS_REG)[0] = BIT(1); delay(50); REG(GPIO_OUT1_W1TC_REG)[0] = BIT(1); delay(50); }
  }
  t = 0;

  REG(ESP32_SENS_SAR_DAC_CTRL1)
  [0] = 0x0;
  REG(ESP32_SENS_SAR_DAC_CTRL2)
  [0] = 0x0;

  initDIG();
  //function 2 on the 12 block
  REG(IO_MUX_GPIO12ISH_REG)
  [0] = BIT(13);  //sdi2 q MISO
  REG(IO_MUX_GPIO12ISH_REG)
  [1] = BIT(13);  //d MOSI
  REG(IO_MUX_GPIO12ISH_REG)
  [2] = BIT(13);  //clk
  REG(IO_MUX_GPIO12ISH_REG)
  [3] = BIT(13);  //cs0
  //perip clock bit 16 is spi3, 13 is timer0
  CHANGOR(DPORT_PERIP_CLK_EN_REG, BIT(16) | BIT(13))
  // BLE build: only SPI3 is reset. Resetting timer group 0 (bit 13) also wipes the system clock
  // (esp_timer runs on TG0 on the ESP32), and BLE connections need that clock.
  CHANGNOR(DPORT_PERIP_RST_EN_REG, BIT(16))

  REG(TIMG0_T0CONFIG_REG)
  [0] = (1 << 18) | BIT(30) | BIT(31);

  REG(IO_MUX_GPIO5_REG)
  [0] = BIT(12);  //sdi3 cs0
  REG(IO_MUX_GPIO18_REG)
  [0] = BIT(12);  //sdi3 clk
  REG(IO_MUX_GPIO19_REG)
  [0] = BIT(12) | BIT(9);  //sdi3 q MISO
  REG(IO_MUX_GPIO23_REG)
  [0] = BIT(12);  //sdi3 d MOSI
  REG(SPI3_MOSI_DLEN_REG)
  [0] = 15;
  REG(SPI3_MISO_DLEN_REG)
  [0] = 15;
  REG(SPI3_USER_REG)
  [0] = BIT(25) | BIT(0) | BIT(27) | BIT(28) | BIT(7) | BIT(6) | BIT(5) | BIT(11) | BIT(10);
  //USR_MOSI, MISO_HIGHPART, and DOUTDIN
  REG(SPI3_PIN_REG)
  [0] = BIT(29);
  REG(SPI3_CLOCK_REG)
  [0] = (1 << 18) | (3 << 12) | (1 << 6) | 3;

#define SPINNER 500000
#define SPRINTER(a) \
  SPIWRITER(a); \
  spin(SPINNER);

  spin(SPINNER * 5);
  SPRINTER(0);
  SPRINTER(0);

  SPRINTER(0x1201);  //adc_seq,9rep,1chan0
  SPRINTER(0x1800);  //gen_ctrl_reg
  SPRINTER(0x2001);  //adc_config,io0adc0
  SPRINTER(0x2802);  //dac_config,io1dac1
  SPRINTER(0x5a00);  //pd_ref_ctrl,9vref

  SPRINTER(0x1201);  //adc_seq,9rep,1chan0
  SPRINTER(0x1800);  //gen_ctrl_reg
  SPRINTER(0x2001);  //adc_config,io0adc0
  SPRINTER(0x2802);  //dac_config,io1dac1
  SPRINTER(0x5a00);  //pd_ref_ctrl,9vref

//LEDs//YELLOW PINS and more
#define GPIO_FUNC_OUT_SEL_CFG_REG REG(0X3ff44530)
  GPIO_FUNC_OUT_SEL_CFG_REG[33] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[12] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[13] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[14] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[15] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[16] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[17] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[21] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[22] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[26] = 256;
  GPIO_FUNC_OUT_SEL_CFG_REG[27] = 256;
  REG(GPIO_ENABLE_REG)
  [0] = BIT(12) | BIT(13)
        | BIT(14) | BIT(15) | BIT(16) | BIT(17)
        | BIT(21) | BIT(22) | BIT(26) | BIT(27);  //ouit freaqs
  REG(GPIO_ENABLE_REG)
  [3] = 2;  //output enable 33
  REG(IO_MUX_GPIO32_REG)
  [0] = BIT(9) | BIT(8);  //input enable 
  REG(IO_MUX_GPIO34_REG)
  [1] = BIT(9) | BIT(8);  //input enable Flip
  REG(IO_MUX_GPIO34_REG)
  [0] = BIT(9) | BIT(8);  //input enable Skip
  REG(IO_MUX_GPIO2_REG)
  [0] = BIT(9) | BIT(8);  //input enable
}
