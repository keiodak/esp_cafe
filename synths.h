#include "stuff.h"

int myNumbers[] = {32000, 31578, 22444, 25111};
//you need to make a table that is 0,3000,5578
int myPlacers[] = {0, 0, 0, 0};
//int myNumbers[] = {12000, 11578, 14444, 15111,8900, 10278, 12004, 12111};
//you need to make a table that is 0,3000,5578
//int myPlacers[] = {0, 0, 0, 0,0,0,0,0};
int tapsz=sizeof(myPlacers)>>2;

void IRAM_ATTR coco() {
    DACWRITER(pout)
    gyo = ADCREADER;

    pout = dellius(t, gyo, lamp);

    if (FLIPPERAT) t++;
    else t--;
    t = t & 0x1FFFF;

    if (SKIPPERAT)  {
        if (lastskp == 0) delayskp = t;
        lastskp = 1;
    } else {
        if (lastskp) t = delayskp;
        lastskp = 0;
    }

    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    adc_read = EARTHREAD;
    int16_t ash = pout >> 4;
    ASHWRITER(ash);
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= (BIT(5));
    YELLOWERS(t)
}

void IRAM_ATTR echo() {
 //INTABRUPT
 //REG(GPIO_STATUS_W1TC_REG)[0]=0xFFFFFFFF; 
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

///bbd delay
void IRAM_ATTR bbd() {
    INTABRUPT;

    gyo = ADCREADER;

    if (FLIPPERAT) t++;
    else t--;
    t &= 0x1FFF;

    if (SKIPPERAT) {
        if (!lastskp) delayskp = t;
        lastskp = 1;
    } else {
        if (lastskp) t = delayskp;
        lastskp = 0;
    }

    int16_t dly = dellius(t, gyo, lamp);

    static int16_t lp = 0;
    static int16_t fb = 0;

    int16_t cut = 4 + (EARTHREAD >> 12);
    if (cut > 7) cut = 7;

    int16_t res = (EARTHREAD >> 9);
    if (res > 96) res = 96;

    int16_t damp = fb >> 4;
    int16_t x = dly - damp - ((fb * res) >> 11);

    lp += (x - lp) >> cut;
    fb = lp;

    pout = lp & 0x0FFF;
    DACWRITER(pout);

    REG(I2S_CONF_REG)[0] &= ~BIT(5);
    ASHWRITER(lp >> 4);
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

///earth>wave multiplier>ash + coco
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

void IRAM_ATTR nsd(){
    INTABRUPT;

    static int16_t buf[256]={0};
    static uint16_t idx=0;
    static bool l=true;

    gyo = ADCREADER;

    uint16_t dt = FLIPPERAT;
    uint16_t r  = (idx + 256 - dt) & 0xFF;
    int16_t out = buf[r];

    int16_t pout = ((gyo + out) >> 1) * 70 / 100;

    ASHWRITER(pout);
    DACWRITER(pout);

    l = !l;
    buf[idx] = gyo + (out >> 1);
    idx = (idx + 1) & 0xFF;
}

void IRAM_ATTR fico() {
    static int16_t gyo, pout, filt_out, dist_out;
    static uint32_t t;
    static bool lastskp = 0;
    static uint32_t delayskp;

    INTABRUPT;

    gyo = ADCREADER;
    pout = dellius(t, gyo, 0);

    int16_t cv = EARTHREAD >> 4;
    if (cv < 1) cv = 1;
    if (cv > 128) cv = 128;

    if (FLIPPERAT) {
        if (SKIPPERAT) filt_out += ((int32_t)(pout - filt_out) * cv) >> 8;
        else filt_out += ((int32_t)(pout - filt_out) * cv) >> 9;
    } else {
        filt_out += ((int32_t)(pout - filt_out) * cv) >> 9;
    }

    int32_t tmp = filt_out + gyo;
    if (tmp > 32767) tmp = 32767;
    if (tmp < -32768) tmp = -32768;
    dist_out = tmp >> 1;

    DACWRITER(filt_out);
    ASHWRITER(dist_out);

    uint32_t gate_val = 0;
    if (FLIPPERAT) gate_val |= 0x1;
    if (SKIPPERAT) gate_val |= 0x2;
    gate_val |= (EARTHREAD & 0xFF) << 8;
    YELLOWERS(gate_val);

    if (FLIPPERAT) t++;
    else t--;
    t &= 0x1FFFF;

    if (SKIPPERAT) {
        if (!lastskp) delayskp = t;
        lastskp = 1;
    } else {
        if (lastskp) t = delayskp;
        lastskp = 0;
    }

    REG(I2S_CONF_REG)[0] &= ~BIT(5);
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

///3layer grain coco
void IRAM_ATTR ccc() {
    INTABRUPT;
    DACWRITER(pout);
    gyo = ADCREADER;
    static int t1 = 0;
    static int t2 = 1024;
    static int t3 = 2048;
    static bool toggle23 = false;
    static int last_flip = 0;
    static int delayskp = 0;
    static int lastskp = 0;
    int spd1 = 1;   // layer1 speed
    int spd2 = 1;   // layer2 speed
    int spd3 = 1;   // layer3 speed

    if (SKIPPERAT) {
        static int mode = 0;
        if (!lastskp) {
            mode = (mode + 1) & 3;
        }
        lastskp = 1;

        switch (mode) {
            case 0: // normal
                spd1 = spd2 = spd3 = 1;
                break;
            case 1: // octave +
                spd1 = spd2 = spd3 = 2;
                break;
            case 2: // fifth +
                spd1 = spd2 = spd3 = 3; 
                break;
            case 3: // octave -
                spd1 = spd2 = spd3 = -1;
                break;
        }
    } else {
        lastskp = 0;
    }

    if (FLIPPERAT) {
        if (!last_flip) toggle23 = !toggle23;
        last_flip = 1;
    } else {
        last_flip = 0;
    }

    int16_t o1 = dellius(t1, gyo, lamp);
    int16_t o2 = 0;
    int16_t o3 = 0;

    if (toggle23) {
        o2 = dellius(t2, gyo, lamp);  // 再生
    } else {
        o3 = dellius(t3, gyo, lamp);  // 再生
    }

    pout = (o1 + o2 + o3) / 3;
    int dir = FLIPPERAT ? 1 : -1;
    t1 += dir * spd1;
    t2 += dir * spd2;
    t3 += dir * spd3;
    t1 &= 0x1FFFF;
    t2 &= 0x1FFFF;
    t3 &= 0x1FFFF;
    if (SKIPPERAT) {
        if (lastskp == 1) { /* already stored */ }
        else delayskp = t1;
    } else {
        if (lastskp) t1 = delayskp;
    }

    REG(I2S_CONF_REG)[0] &= ~BIT(5);
    adc_read = EARTHREAD;
    int16_t ash = pout >> 4;
    ASHWRITER(ash);    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
    YELLOWERS(t1);
}

///degital crackle
void IRAM_ATTR crackle() {
    static int16_t fb = 0, last_cr = 0, last_dac = 0;
    static int32_t chaos = 0, tri_phase = 0;
    static int low_speed_counter = 0;

    INTABRUPT;

    auto crackle_on_ear = [&](int16_t ear, bool flipp, bool skipp, bool lamp) -> int16_t {
        int32_t touch, chaos_delta = 0, fb_delta = 0;

        if (!lamp) {
            touch = (int32_t)ear - 2048;
            if (++low_speed_counter >= 20) {
                int16_t lfo = ((tri_phase >> 6) & 0xFF) - 128;
                chaos_delta = lfo;
                fb_delta = (lfo >> 2);
                low_speed_counter = 0;
                tri_phase += 2;
            }
        } else {
            touch = (ear >> 3) - 64;
            int16_t low = ((tri_phase >> 8) & 0xFF) - 128;
            int16_t fast = ((tri_phase >> 2) & 0xFF) - 128;
            chaos_delta = low + (fast >> 2);
            fb_delta = (low >> 1) + (fast >> 3);
            tri_phase += 4;
        }

        int32_t x = chaos + touch + chaos_delta + fb;
        if (x > 30000) x = 30000 - (x - 30000);
        if (x < -30000) x = -30000 - (x + 30000);
        chaos = x;

        int32_t y = chaos * 2 + fb_delta;
        if (y > 32767) y = 32767;
        if (y < -32768) y = -32768;
        fb += ((y >> 3) - fb) >> 2;

        int16_t out = (last_cr + (int16_t)y) >> 1;
        last_cr = out;

        if (flipp) {
            int32_t rev = -chaos + ((tri_phase & 0x3FF) - 512);
            int32_t d = ((chaos - rev) * 3) >> 2;
            out += (int16_t)d;
            chaos = rev + (d >> 3);
        }

        if (skipp) {
            if (out > 3000) out = 15000 - out;
            if (out < -3000) out = -15000 - out;
            out >>= 1;
        }

        if (flipp && skipp) {
            out += ((tri_phase >> 2) & 0x7FF) - 1024;
        }

        return out;
    };

    int16_t gyo = ADCREADER;
    int16_t cr = crackle_on_ear(EARTHREAD, FLIPPERAT, SKIPPERAT, lamp);

    int16_t cr_out = !lamp ? (cr * EARTHREAD) >> 12 : (cr * (EARTHREAD >> 3)) >> 8;

    int32_t temp = gyo * 2;
    if (temp > 32767) temp = 32767;
    if (temp < -32768) temp = -32768;
    int16_t out_dac = (last_dac + (int16_t)temp) >> 1;
    last_dac = out_dac;

    DACWRITER(out_dac);
    ASHWRITER(cr_out);
    YELLOWERS(cr_out);

    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
}


