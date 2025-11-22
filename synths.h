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

void IRAM_ATTR wmp() {
    INTABRUPT

    DACWRITER(pout)
    gyo = ADCREADER;
    pout = dellius(t, gyo, lamp);

    if (FLIPPERAT) t++;
    else t--;
    t = t & 0x1FFFF;

    if (SKIPPERAT)  {
        static int delayskp = 0, lastskp = 0;
        if (lastskp == 0) delayskp = t;
        lastskp = 1;
    } else {
        static int delayskp = 0, lastskp = 0;
        if (lastskp) t = delayskp;
        lastskp = 0;
    }

    static uint8_t play_order[8] = {0,1,2,3,4,5,6,7};
    static uint8_t pstep = 0;
    static uint8_t lastflp = 0;
    const int SPLITS = 8;
    const int SPLIT_SIZE = 512 / SPLITS;

    if (FLIPPERAT && lastflp == 0) {
        for (int i = 0; i < SPLITS; i++) {
            int j = rand() & (SPLITS - 1);
            uint8_t tmp = play_order[i];
            play_order[i] = play_order[j];
            play_order[j] = tmp;
        }
        pstep = 0;
    }
    lastflp = FLIPPERAT;

    uint32_t split_pos = t & (SPLIT_SIZE - 1);
    uint32_t base = play_order[pstep] * SPLIT_SIZE;
    uint32_t idx = base + split_pos;
    if (split_pos == SPLIT_SIZE - 1) pstep = (pstep + 1) & (SPLITS - 1);

    int32_t cv = EARTHREAD;
    int32_t cv_amt = (cv >> 3);
    int32_t s1 = gyo;
    int32_t fold1 = (s1 * (abs(s1) + 12000 + cv_amt)) >> 15;
    int32_t s2 = fold1;
    int32_t rect2 = abs(s2);
    int32_t fold2 = (rect2 * (8000 + (cv_amt >> 1))) >> 14;
    int32_t s3 = fold2;
    int32_t fold3 = (s3 * (abs(s3) + 16000 + (cv_amt >> 2))) >> 15;

    if (fold3 > 32767) fold3 = 32767;
    if (fold3 < -32768) fold3 = -32768;
    ASHWRITER((int16_t)fold3);
}

void IRAM_ATTR dico() {
  INTABRUPT
  DACWRITER(pout)
  gyo = ADCREADER;
  pout = dellius(t, gyo, lamp);

  if (FLIPPERAT) t++;
  else t--;
  t &= 0x1FFFF;
  if (SKIPPERAT) {
    if (lastskp == 0) delayskp = t;
    lastskp = 1;
  } else {
    if (lastskp) t = delayskp;
    lastskp = 0;
  }

  int16_t abc_in = EARTHREAD;
  int32_t ytmp = abc_in * (lamp ? 3 : 2);
  if (ytmp > 32767) ytmp = 32767;
  if (ytmp < -32768) ytmp = -32768;
  int16_t yellow_sig = (int16_t)ytmp;
  int32_t gtmp = (yellow_sig ^ (yellow_sig >> 3)) * (lamp ? 2 : 1);
  if (gtmp > 32767) gtmp = 32767;
  if (gtmp < -32768) gtmp = -32768;
  int16_t gray_sig = (int16_t)gtmp;

  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  YELLOWERS(yellow_sig);
  ASHWRITER(gray_sig); 
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= (BIT(5));
}

#define DISJ_BUF_SIZE 512
static int16_t disj_buf[DISJ_BUF_SIZE];
static uint16_t disj_idx = 0;
void IRAM_ATTR disj() {
    INTABRUPT;
    gyo = ADCREADER;
    int32_t temp = gyo;
    const int32_t HARD_THRESHOLD = 5000;
    if(temp > HARD_THRESHOLD) temp = HARD_THRESHOLD;
    if(temp < -HARD_THRESHOLD) temp = -HARD_THRESHOLD;
    temp -= (temp * temp * temp) / 1073741824;
    temp -= (temp * temp * temp * temp) / 1073741824;
    int16_t distorted = (int16_t)temp;
    pout = dellius(t, distorted, lamp);

    static uint8_t last_flipp = 0;
    static uint8_t last_skipp = 0;
    static uint32_t delayskp = 0;
    if(FLIPPERAT && !last_flipp) t += 0x10000;
    last_flipp = FLIPPERAT ? 1 : 0;
    if(SKIPPERAT && !last_skipp) t += 0x08000;
    if(SKIPPERAT) {
        if(last_skipp == 0) delayskp = t;
    } else {
        if(last_skipp) t = delayskp;
        delayskp = 0;
    }
    last_skipp = SKIPPERAT ? 1 : 0;
    t &= 0x1FFFF;

    disj_buf[disj_idx] = distorted;
    disj_idx = (disj_idx + 1) & (DISJ_BUF_SIZE - 1);

    DACWRITER(pout);
    adc_read = distorted;
    ASHWRITER(adc_read);
    REG(I2S_CONF_REG)[0] &= ~BIT(5);
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
    t++; 
}

void IRAM_ATTR crackle() {
    static int16_t fb = 0;
    static int32_t chaos = 0;
    static int16_t last_cr = 0;
    static int16_t last_dac = 0;
    static int low_speed_counter = 0;
    static int32_t tri_phase = 0;
    static int16_t last_cr_out = 0;

    INTABRUPT;

    auto crackle_on_ear = [&](int16_t ear, bool flipp, bool skipp, bool lamp) -> int16_t {
        int32_t chaos_delta = 0;
        int32_t fb_delta = 0;
        int32_t touch;

        if(!lamp){
            touch = (int32_t)ear - 2048;
            if(++low_speed_counter >= 20){
                int16_t lfo = ((tri_phase >> 6) & 0xFF) - 128;
                chaos_delta = lfo;
                fb_delta = (lfo >> 2);
                low_speed_counter = 0;
                tri_phase += 2;
            }
        } else {
            touch = (ear >> 3) - 64;
            chaos_delta = 3000 + ((tri_phase & 0xFF) - 128);
            fb_delta = 800 + (((tri_phase >> 1) & 0xFF) - 128);
            tri_phase += 20;
        }

        int32_t x = chaos + fb + touch + chaos_delta;
        if(x > 30000) x = 30000 - (x - 30000);
        if(x < -30000) x = -30000 - (x + 30000);
        chaos = x;

        int32_t y = chaos * 2 + fb_delta;
        if(y > 32767) y = 32767;
        if(y < -32768) y = -32768;
        fb = y >> 3;

        int16_t out = (last_cr + (int16_t)y) >> 1;
        last_cr = out;

        if(flipp){
            int32_t old = chaos;
            int32_t rev = -old + ((tri_phase & 0x3FF) - 512);
            int32_t d   = (old - rev);
            d = (d * 3) >> 2;
            out += (int16_t)d;
            chaos = rev + (d >> 3);
        }

        if(skipp){
            if(out > 3000)  out = 15000 - out;
            if(out < -3000) out = -15000 - out;
            out = out >> 1;
        }

        if(flipp && skipp){
            out += ((tri_phase >> 2) & 0x7FF) - 1024;
        }

        return out;
    };

    int16_t gyo = ADCREADER;
    int16_t cr = crackle_on_ear(EARTHREAD, FLIPPERAT, SKIPPERAT, lamp);

    int16_t cr_out;
    if(!lamp){
        int32_t gain = EARTHREAD;
        cr_out = (cr * gain) >> 12;
    } else {
        int32_t gain = (EARTHREAD >> 3);
        cr_out = (cr * gain) >> 8;
    }

    int32_t temp = gyo * 2;
    if(temp > 32767) temp = 32767;
    if(temp < -32768) temp = -32768;
    int16_t out_dac = (last_dac + (int16_t)temp) >> 1;
    last_dac = out_dac;

    DACWRITER(out_dac);
    ASHWRITER(cr_out);
    YELLOWERS(cr_out);

    last_cr_out = cr_out;

    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
}

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
