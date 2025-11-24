///BBD-type delay
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

///simple short delay
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

///3-layer coco
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

///SSG/single slope genelator/Lamp-on(cycle) Lamp-off(triger-flipp mode)
void IRAM_ATTR ssg() {
    INTABRUPT;

    int16_t gyo = ADCREADER;
    int16_t ear = EARTHREAD & 0x7FF;
    static int32_t phase = 0;
    static bool rising = true; 
    static bool active = false; 
    static bool prev_skipp = false; 
    int16_t env = 0;
    if (!lamp) {
        if (SKIPPERAT && !prev_skipp && !active) {
            active = true;
            phase = 0;
            rising = true;
        }
        prev_skipp = SKIPPERAT;

        if (active) {
            int32_t step_up = 60;              
            int32_t step_down = 30 + ((ear * 1200) >> 11);
            if (rising) {
                env = (phase >> 8); 
                phase += step_up;
                if (phase >= 255 << 8) { 
                    phase = 255 << 8; 
                    rising = false; 
                }
            } else {
                env = (phase >> 8);
                phase -= step_down;
                if (phase <= 0) { 
                    phase = 0; 
                    active = false; 
                }
            }
        } 
        if (!active) {
            env = 0;
            phase = 0;
            rising = true;
        }
        ASHWRITER(env);
    }

    else {
        static int32_t cyc_phase = 0;
        static bool cyc_rising = true;
        int16_t cyc;
        int32_t step_up = 150 + ((ear * 200) >> 11); 
        int32_t step_down = 100 + ((ear * 10000) >> 11);
        if (cyc_rising) {
            cyc = (cyc_phase >> 8); // 最大255
            cyc_phase += step_up;
            if (cyc_phase >= 255 << 8) { cyc_phase = 255 << 8; cyc_rising = false; }
        } else {
            cyc = (cyc_phase >> 8);
            cyc_phase -= step_down;
            if (cyc_phase <= 0) { cyc_phase = 0; cyc_rising = true; }
        }
        ASHWRITER(cyc);
    }

    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
    YELLOWERS(0);
}

///digital crackle 
//Based on a crackle box motif. Antenna orange cv is input to brown and purple.
//Feedback is adjusted with the wet volume to produce a chirping sound.
//The antenna adjustment knob should be set to around 11 o'clock.
//Have fun with the silver and gold antenna screws. Modulation can also be achieved with flipp/skip.
//A gate is output from the yellowers....
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

