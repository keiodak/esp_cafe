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
