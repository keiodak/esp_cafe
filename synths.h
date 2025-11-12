#include "stuff.h"

int myNumbers[] = {32000, 31578, 22444, 25111};
//you need to make a table that is 0,3000,5578
int myPlacers[] = {0, 0, 0, 0};
//int myNumbers[] = {12000, 11578, 14444, 15111,8900, 10278, 12004, 12111};
//you need to make a table that is 0,3000,5578
//int myPlacers[] = {0, 0, 0, 0,0,0,0,0};

int tapsz=sizeof(myPlacers)>>2;

void IRAM_ATTR coco() {
 INTABRUPT
 DACWRITER(pout)
 gyo=ADCREADER
 pout=dellius(t,gyo,lamp);
 if (FLIPPERAT) t++;
 else t--; 
 t=t&0x1FFFF;//
 if (SKIPPERAT)  {
  if (lastskp==0) delayskp = t;
  lastskp = 1;
 } else {
  if (lastskp) t=delayskp;
  lastskp = 0;
 } 
 REG(I2S_CONF_REG)[0] &= ~(BIT(5)); 
 adc_read = EARTHREAD;
 int16_t scaled = pout / 2;
    ASHWRITER(scaled);
 REG(I2S_INT_CLR_REG)[0]=0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= (BIT(5)); //start rx
 YELLOWERS(t)
}

void IRAM_ATTR echo() {
 INTABRUPT
 DACWRITER(pout)
 gyo=ADCREADER
 pout =0;
 for (int i=0; i<tapsz; i++) 
  pout+=dellius((myPlacers[i]<<2)+i,gyo,lamp);
 pout = pout>>2;
 if (FLIPPERAT)
  for (int i=0; i<tapsz; i++)  //sizeof(myPlacers)
   myPlacers[i]++;
 else 
  for (int i=0; i<tapsz; i++) 
   myPlacers[i]--;
 for (int i=0; i<tapsz; i++) {
  myPlacers[i] %= myNumbers[i];
  if (myPlacers[i]<0) myPlacers[i] += myNumbers[i];
 }
 if (SKIPPERAT)  {} else {} 
 REG(I2S_CONF_REG)[0] &= ~(BIT(5)); 
 adc_read = EARTHREAD;
 ASHWRITER(adc_read); //rand()
 REG(I2S_INT_CLR_REG)[0]=0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= (BIT(5)); //start rx
 YELLOWERS(myPlacers[0]+myPlacers[1]+myPlacers[2]+myPlacers[3]);
}

//AM-OSC
void IRAM_ATTR amosc() {
    INTABRUPT;

    DACWRITER(pout);
    gyo = ADCREADER;
    pout = dellius(t, gyo, lamp);

    if (FLIPPERAT) t++;
    else t--;

    static uint8_t last_skp = 0;
    static uint8_t wrap_index = 0;
    static const uint32_t wrap_table[5] = {
        0x0FFF,   // 4096
        0x1FFF,   // 8192
        0x3FFF,   // 16384
        0x7FFF,   // 32768
        0xFFFFFFFF // no wrap
    };

    if (SKIPPERAT && !last_skp) {
        wrap_index = (wrap_index + 1) % 5;
    }
    last_skp = SKIPPERAT;

    uint32_t wrap_mask = wrap_table[wrap_index];

    if (wrap_mask != 0xFFFFFFFF) {
        t &= wrap_mask; 
    } else {
        if (t > 0xFFFFF) t = 0; 
    }

    int16_t brown_cv = EARTHREAD;
    int32_t t_extended = t;
    int32_t scaled = (t_extended * (brown_cv + 32768)) >> 16;
    if (scaled > 32767) scaled = 32767;
    if (scaled < -32768) scaled = -32768;

    static int16_t y_last = 0;
    static int16_t g_last = 0;
    int16_t yellow_val = (scaled + y_last) >> 1;
    int16_t gray_val   = (scaled + g_last) >> 1;
    y_last = yellow_val;
    g_last = gray_val;

    YELLOWERS(yellow_val);
    ASHWRITER(gray_val);
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

//simple short delay
void IRAM_ATTR ssd() {
 INTABRUPT;
 DACWRITER(pout);
 gyo = ADCREADER;
 pout = dellius(t, gyo, lamp);
 if (FLIPPERAT) t++;
 else t--;
 t &= 0xFF;
 if (SKIPPERAT) {} else {}
 REG(I2S_CONF_REG)[0] &= ~(BIT(5));
 adc_read = EARTHREAD;
 ASHWRITER(adc_read);
 REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= (BIT(5));
 YELLOWERS(t);
}

// BBD delay
void IRAM_ATTR bbd() {
 INTABRUPT;
 DACWRITER(pout);
 gyo = ADCREADER;

 static int16_t last_mix = 0;
 int32_t mix = gyo;
 mix = (mix + last_mix * 7) / 8;
 last_mix = mix;
 mix &= 0xFFF0;
 pout = dellius(t, (int16_t)mix, lamp);
 if (FLIPPERAT) t++; else t--;
 t &= 0x1FFF;
 if (SKIPPERAT) {
  if (!lastskp) delayskp = t;
  lastskp = 1;
 } else {
  if (lastskp) t = delayskp;
  lastskp = 0;
 }

 REG(I2S_CONF_REG)[0] &= ~BIT(5);
 adc_read = EARTHREAD;
 ASHWRITER(adc_read);
 REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= BIT(5);
 YELLOWERS(t);
}

// 3-layer coco 5th
void IRAM_ATTR cococo() {
 INTABRUPT;
 DACWRITER(pout);
 gyo = ADCREADER;

 static int t1 = 0;
 static int t2 = 1024;
 static int t3 = 2048;
 static int c2 = 0;
 static int c3 = 0;

 int16_t out1 = dellius(t1, gyo, lamp);
 int16_t out2 = dellius(t2, gyo, lamp);
 int16_t out3 = dellius(t3, gyo, lamp);

 pout = (out1 + out2 + out3) / 3;

 if (FLIPPERAT) {
  t1++;
  if (c2++ % 2 == 0) t2 += 3; 
  if (c3++ % 3 == 0) t3--;  
 } else {
  t1--;
  if (c2++ % 2 == 0) t2 -= 3;
  if (c3++ % 3 == 0) t3++;
 }

 t1 = t1 & 0x1FFFF;
 t2 = t2 & 0x1FFFF;
 t3 = t3 & 0x1FFFF;

 if (SKIPPERAT) {
  if (lastskp == 0) delayskp = t1;
  lastskp = 1;
 } else {
  if (lastskp) t1 = delayskp;
  lastskp = 0;
 }

 REG(I2S_CONF_REG)[0] &= ~BIT(5);
 adc_read = EARTHREAD;
 ASHWRITER(adc_read);
 REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= BIT(5);
 YELLOWERS(t1);
}

// 3-layer coco oct
void IRAM_ATTR cocooct() {
 INTABRUPT;
 DACWRITER(pout);
 gyo = ADCREADER;

 static int t1 = 0;
 static int t2 = 0;
 static int t3 = 0;
 static int flip_count = 0;
 static int skip_count = 0;

 int16_t out1 = dellius(t1, gyo, lamp);
 int16_t out2 = dellius(t2, gyo, lamp);
 int16_t out3 = dellius(t3, gyo, lamp);

 pout = (out1 + out2 + out3) / 3;

 if(FLIPPERAT) {
   flip_count++;
   t2 += 4;
 } 

 if(SKIPPERAT) {
   skip_count++;
   t3 -= 3;
 }

 t1 = (t1 + 1) & 0x1FFFF;
 t2 = (t2 + 1) & 0x1FFFF;
 t3 = (t3 + 1) & 0x1FFFF;

 REG(I2S_CONF_REG)[0] &= ~BIT(5);
 adc_read = EARTHREAD;
 ASHWRITER(adc_read);
 REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
 REG(I2S_CONF_REG)[0] |= BIT(5);
 YELLOWERS(t1);
}

// harmonic echo
void IRAM_ATTR he() {
  INTABRUPT;
  DACWRITER(pout);
  gyo = ADCREADER;

  static int t1 = -512;
  static int t2 = 1024;
  static int t3 = 2048 + 512;

  static int c2 = 0;
  static int c3 = 0;

  static int flip_state = 0;
  static int skip_state = 0;

  static int scale2[] = {-4, 2, 5};  // t2用 Ionian
  static int scale3[] = {-2, 4, -5}; // t3用 Ionian
  static int scale_index2 = 0;
  static int scale_index3 = 0;

  if (FLIPPERAT && !flip_state) {
    flip_state = 1;
    scale_index2 = (scale_index2 + 1) % 3;
  } else if (!FLIPPERAT) flip_state = 0;

  if (SKIPPERAT && !skip_state) {
    skip_state = 1;
    scale_index3 = (scale_index3 + 1) % 3;
  } else if (!SKIPPERAT) skip_state = 0;

  int interval2 = scale2[scale_index2];
  int interval3 = scale3[scale_index3];

  t1 &= 0x1FFFF;
  t2 &= 0x1FFFF;
  t3 &= 0x1FFFF;

  int16_t out1 = dellius(t1, gyo, lamp) >> 1;
  int16_t out2 = dellius(t2, gyo, lamp);
  int16_t out3 = dellius(t3, gyo, lamp);

  pout = (out1 + out2 + out3) / 3;

  if (c2++ % 2 == 0) t2 = (t2 + interval2) & 0x1FFFF;
  if (c3++ % 3 == 0) t3 = (t3 + interval3) & 0x1FFFF;

  t1 = (t1 + 1) & 0x1FFFF;

  REG(I2S_CONF_REG)[0] &= ~BIT(5);
  adc_read = EARTHREAD;
  ASHWRITER(adc_read);
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= BIT(5);

  YELLOWERS(t1);
}

// WMP
void IRAM_ATTR wmp() {
    INTABRUPT;

    int16_t gyo = ADCREADER;        // Green入力
    static int16_t pout = 0;        // 歪み WMP 出力バッファ

    int32_t sample = gyo;

    // ---- SKIPPERAT: WMP パターン切替 ----
    static uint8_t wmp_pattern = 0;
    static uint8_t last_skipp = 0;
    if (SKIPPERAT && !last_skipp) wmp_pattern = (wmp_pattern + 1) % 3;
    last_skipp = SKIPPERAT;

    // ---- クリーン WMP（ASH用） ----
    int32_t wmp_sample;
    switch (wmp_pattern) {
        case 0: wmp_sample = (sample + sample*2 + sample*3/2)/3; break;
        case 1: wmp_sample = (sample + sample*3/2 + sample*4/3)/3; break;
        case 2: wmp_sample = (sample + sample*4/3 + sample*5/4)/3; break;
    }
    ASHWRITER((int16_t)wmp_sample);

    // ---- 歪み WMP（pout用） ----
    int32_t distorted = wmp_sample;

    // ---- FLIPPERAT: 歪みパターン切替 ----
    static uint8_t dist_pattern = 0;
    static uint8_t last_flipp = 0;
    if (FLIPPERAT && !last_flipp) dist_pattern = (dist_pattern + 1) % 3;
    last_flipp = FLIPPERAT;

    int32_t hard_threshold = (dist_pattern==0 ? 6000 : (dist_pattern==1 ? 4000 : 3000));

    if (distorted > hard_threshold) distorted = hard_threshold;
    if (distorted < -hard_threshold) distorted = -hard_threshold;

    distorted = distorted - (distorted*distorted*distorted)/134217728;  // 強めのソフトクリップ

    // ---- フィードバック合成 ----
    pout = (distorted + pout)/2;

    // ---- DAC 出力（歪み WMP）----
    DACWRITER((int16_t)pout);

    // ---- I2S制御 ----
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

// distortion test
void IRAM_ATTR disc() {
    INTABRUPT;

    int16_t gyo = ADCREADER;       
    int16_t lamp = EARTHREAD;   
    static uint32_t phase = 0;   
    static uint8_t last_skp = 0;

    int32_t sample = gyo;

    if (FLIPPERAT) {
        const int16_t bass_amp = 8000;
        phase = (phase + 50) & 0xFFFFF;
        int16_t bass = (int16_t)((phase & 0xFFFF) - 0x8000) / 2;
        sample += bass_amp * bass / 32768;
    }

    const int16_t hard_threshold = 5000;
    if (sample > hard_threshold) sample = hard_threshold;
    if (sample < -hard_threshold) sample = -hard_threshold;

    sample = sample - (sample * sample * sample) / 1073741824;

    DACWRITER((int16_t)sample);

    int32_t gray_val = (sample * (lamp + 32768) * 4) >> 16; // AM強め
    if (gray_val > 32767) gray_val = 32767;
    if (gray_val < -32768) gray_val = -32768;
    ASHWRITER((int16_t)gray_val);
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

//simple distortion
void IRAM_ATTR dist() {
    INTABRUPT;

    int16_t gyo = ADCREADER; 
    int16_t lamp = EARTHREAD; 

    int32_t sample = gyo;

    // ---- 強歪み ----
    const int16_t hard_threshold = 5000;
    if (sample > hard_threshold) sample = hard_threshold;
    if (sample < -hard_threshold) sample = -hard_threshold;

    sample = sample - (sample * sample * sample) / 1073741824;

    sample = (sample * (lamp + 32768) * 4) >> 16;
    if (sample > 32767) sample = 32767;
    if (sample < -32768) sample = -32768;

    DACWRITER((int16_t)sample);
    ASHWRITER(gyo);
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

//phase osc + shiftregister
void IRAM_ATTR prun() {
    INTABRUPT;

    static uint32_t phase = 0;

    static uint8_t last_flipp = 0;
    static uint8_t last_skipp = 0;
    static uint8_t step_idx = 0;
    static uint8_t config_idx = 0;

    static uint32_t pitch_configs[2][8];
    static uint8_t initialized = 0;
    if (!initialized) {
        for (int i=0;i<2;i++)
            for (int j=0;j<8;j++)
                pitch_configs[i][j] = 50 + (rand() & 31); // 50~81程度のランダム
        initialized = 1;
    }
    uint32_t* pitch_steps = pitch_configs[config_idx];

    if (FLIPPERAT && !last_flipp) {
        step_idx = (step_idx + 1) % 8;
        pitch_steps[step_idx] = 50 + (rand() & 31);
    }
    last_flipp = FLIPPERAT;

    if (SKIPPERAT && !last_skipp) {
        config_idx = (config_idx + 1) % 2;
        step_idx = 0;
    }
    last_skipp = SKIPPERAT;

    // ---- 単一オシレーター（triangle）----
    phase = (phase + pitch_steps[step_idx]) & 0xFFFFFF;
    int32_t tri = (int32_t)(phase & 0xFFFFFF);
    tri = (tri >> 4); 
    if (tri & 0x8000) tri = 0xFFFF - tri; 
    tri -= 0x4000; 

    int16_t amp_cv = EARTHREAD;
    int16_t sample = (int16_t)((tri * (amp_cv + 32768)) >> 15); 

    ASHWRITER(sample);
    DACWRITER(sample);
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

//complex bytebeats
static uint16_t pattern1(uint32_t t){ return (t*(t>>8)) & 0xFFF; }
static uint16_t pattern2(uint32_t t){ return (t*(t>>6 | t>>9)) & 0xFFF; }
static uint16_t pattern3(uint32_t t){ return (t*(t>>5 | t>>7)) & 0xFFF; }
static uint16_t pattern4(uint32_t t){ return (t*((t>>4)|(t>>10))) & 0xFFF; }
static uint16_t pattern5(uint32_t t){ return (t*(t>>3 | t>>11)) & 0xFFF; }
static uint16_t pattern6(uint32_t t){ return (t*(t>>2 | t>>9)) & 0xFFF; }
static uint16_t pattern7(uint32_t t){ return (t*(t>>7 ^ t>>10)) & 0xFFF; }
static uint16_t pattern8(uint32_t t){ return (t*((t>>5)|(t>>12))) & 0xFFF; }

typedef uint16_t (*BytebeatFunc)(uint32_t);

void IRAM_ATTR bytebeats() {
    INTABRUPT;

    if (FLIPPERAT) t++;
    else t--;

    if (SKIPPERAT) t += 2;

    bool both_pressed = (FLIPPERAT && SKIPPERAT);

    static BytebeatFunc patterns[] = { pattern1, pattern2, pattern3, pattern4, pattern5, pattern6, pattern7, pattern8 };
    static const int num_patterns = sizeof(patterns)/sizeof(patterns[0]);
    static int current_pattern = 0;

    static bool prev_both_pressed = false;
    if (both_pressed && !prev_both_pressed) {
        current_pattern = (current_pattern + 1) % num_patterns;
    }
    prev_both_pressed = both_pressed;

    pout = patterns[current_pattern](t);

    DACWRITER(pout & 0xFFF); 

    gyo = ADCREADER;
    adc_read = EARTHREAD;
    ASHWRITER(adc_read);
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
    YELLOWERS(pout);
}
