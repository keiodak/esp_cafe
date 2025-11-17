void IRAM_ATTR square3co() {
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

    t1 &= 0x1FFFF;
    t2 &= 0x1FFFF;
    t3 &= 0x1FFFF;

    // === SKIPPERATでt2/t3をランダムにずらす ===
    if (SKIPPERAT) {
        if (lastskp == 0) {
            delayskp = t1;
            int pattern = rand() & 3;
            switch (pattern) {
                case 0: t2 += 128; t3 -= 256; break;
                case 1: t2 -= 256; t3 += 128; break;
                case 2: t2 += 512; t3 += 512; break;
                case 3: t2 -= 512; t3 -= 128; break;
            }
        }
        lastskp = 1;
    } else {
        if (lastskp) t1 = delayskp;
        lastskp = 0;
    }

    // === ASH スクエアメロディー（1オクターブ高く） ===
    static int melody_phase = 0;
    static int melody_note = 0;
    static const int scale[8] = {0, 2, 4, 5, 7, 9, 11, 12}; // Ionian
    if (FLIPPERAT) {
        melody_note = scale[rand() & 7];
        melody_phase = 0;
    }
    melody_phase++;
    int16_t square = (melody_phase & (1 << (5 + (melody_note / 3)))) ? 12000 : -12000; // 高音化

    // === 出力 ===
    REG(I2S_CONF_REG)[0] &= ~BIT(5);
    adc_read = EARTHREAD;
    ASHWRITER(square);
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
    YELLOWERS(t1);
}

void IRAM_ATTR osc() {
    INTABRUPT;

    static uint32_t t = 0;
    static uint32_t c_mask = 1023;
    static uint32_t e_mask = 819;
    static uint32_t g_mask = 683;
    static bool last_skip = false;
    static bool last_flipp = false;

    bool both = SKIPPERAT && FLIPPERAT;

    // --- 同時押しで波形リセット/変更 ---
    if(both){
        c_mask = 512 + (rand() & 1023);
        e_mask = 400 + (rand() & 819);
        g_mask = 341 + (rand() & 683);
    }
    // --- SKIP押下でパターン変更 ---
    else if(SKIPPERAT && !last_skip){
        c_mask = 512 + (rand() & 1023);
        e_mask = 400 + (rand() & 819);
        g_mask = 341 + (rand() & 683);
    }
    // --- FLIPP押下で周期変化（倍速/半速） ---
    else if(FLIPPERAT && !last_flipp){
        c_mask ^= 0x3FF;  // ちょっとフェーズ/周期変化
        e_mask ^= 0x2FF;
        g_mask ^= 0x1FF;
    }

    last_skip = SKIPPERAT;
    last_flipp = FLIPPERAT;

    // --- 時間進行 ---
    t++;

    // --- Bytebeat出力 ---
    uint16_t pout = drone_pattern(t, c_mask, e_mask, g_mask);

    // --- DAC / グレーアウト出力 ---
    DACWRITER(pout);
    YELLOWERS(pout);

    // --- ADC処理 ---
    int gyo = ADCREADER;
    int adc_read = EARTHREAD;
    ASHWRITER(adc_read);

    // --- I2Sフラッシュ ---
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
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

void IRAM_ATTR hn() {
  INTABRUPT
  static uint32_t t = 0;
  static uint16_t s = 1;
  static int layerCount = 1;

  static uint8_t shiftA[3] = {8, 6, 5};
  static uint8_t shiftB[3] = {7, 9, 10};

  if (FLIPPERAT && SKIPPERAT) {
    layerCount++;
    if (layerCount > 3) layerCount = 1;

    for (int i = 0; i < 3; i++) {
      shiftA[i] = (shiftA[i] + (s & 7)) % 12 + 3; 
      shiftB[i] = (shiftB[i] + ((s >> 3) & 7)) % 12 + 3;
    }

    s ^= (s << 3) ^ (s >> 1);
  }

  int32_t mix = 0;
  for (int i = 0; i < layerCount; i++) {
    uint32_t tt = t + ((s >> (i * 3)) & 0xFF);
    uint16_t v;
    switch (i) {
      case 0: v = ((tt * ((tt >> shiftA[0]) | (tt >> shiftB[0]))) >> 4) & 0xFF; break;
      case 1: v = ((tt * ((tt >> shiftA[1]) | (tt >> shiftB[1]))) >> 4) & 0xFF; break;
      case 2: v = ((tt * ((tt >> shiftA[2]) ^ (tt >> shiftB[2]))) >> 4) & 0xFF; break;
      default: v = 0; break;
    }
    mix += (v ^ (s << (i + 1)));
  }

  mix &= 0xFF;
  DACWRITER(mix);
  YELLOWERS(mix);

  t += 1;
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

void IRAM_ATTR tentmap() {
    INTABRUPT;

    static int32_t x1 = 32000;
    static int32_t x2 = 31000;
    static uint8_t cnt1 = 0;
    static uint8_t cnt2 = 0;
    static uint16_t offset2 = 0;
    static int16_t smooth = 0;

    // -------------------------
    // 超低速 LFO（整数、1 系統）
    // -------------------------
    static uint16_t phase = 0;
    static uint16_t lfo = 32768;
    static uint8_t lfo_tick = 0;

    if (++lfo_tick >= 64) { // LFO をさらに遅く
        lfo_tick = 0;
        phase += 1;
        if (phase > 65535) phase -= 65536;
    }

    if (phase < 32768) lfo = 32768 + (phase >> 6);
    else lfo = 32768 + ((65536 - phase) >> 6);

    // -------------------------
    // Tent Map 1
    // -------------------------
    if (++cnt1 >= 32) {
        cnt1 = 0;
        if (x1 < 32768) x1 = (x1 * lfo) >> 15;
        else x1 = ((65536 - x1) * lfo) >> 15;
    }

    // -------------------------
    // Tent Map 2（微位相ずらし）
    // -------------------------
    if (++cnt2 >= 48) {
        cnt2 = 0;
        offset2 += 1;
        if (offset2 > 65535) offset2 -= 65536;

        if (x2 < 32768) x2 = ((x2 + offset2) * lfo) >> 15;
        else x2 = ((65536 - (x2 + offset2)) * lfo) >> 15;
    }

    // -------------------------
    // 合成 & スムージング（整数）
    // -------------------------
    int32_t mix = (x1 + x2) >> 1;

    smooth = (smooth * 15 + (int16_t)(mix - 32768)) >> 4;

    // -------------------------
    // ASH 出力（音量大幅ダウン）
    // -------------------------
    ASHWRITER(smooth >> 3);
}

typedef uint16_t (*BytebeatFunc2)(uint32_t, uint16_t, uint16_t);
uint16_t wallflower_mod(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = (t * ((t >> m1 | t >> m2) & (t >> 13))) ^ (t >> 5);
  return (v & 0xFF) << 8;
}
uint16_t beatnoise(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = ((t >> m1 | t >> m2) * (t >> 7 | t >> 8)) & 0xFF;
  return v << 8;
}
uint16_t wallflower_alt1(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = ((t >> m1) ^ (t >> m2)) * (t & 0x0F);
  return (v & 0xFF) << 8;
}
uint16_t wallflower_alt2(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = (t * ((t >> m1) & (t >> m2))) ^ (t >> (m1 + 1));
  return (v & 0xFF) << 8;
}
uint16_t beatnoise_alt1(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = ((t >> m1 | t >> m2) ^ (t >> 6)) & 0xFF;
  return v << 8;
}
uint16_t beatnoise_alt2(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = ((t >> m1) * (t >> m2)) & 0xFF;
  return v << 8;
}
uint16_t glitch1(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = ((t >> m1) | (t << (m2 % 16))) & 0xFF;
  return v << 8;
}
uint16_t glitch2(uint32_t t, uint16_t m1, uint16_t m2) {
  uint32_t v = ((t * (t >> m1)) ^ (t >> m2)) & 0xFF;
  return v << 8;
}
void IRAM_ATTR bytebeats2() {
  INTABRUPT;

  static uint32_t t = 0;
  static int current_pattern = 0;
  static uint16_t mod1 = 9, mod2 = 11;

  static BytebeatFunc2 patterns[] = { 
    wallflower_mod, beatnoise, wallflower_alt1, wallflower_alt2,
    beatnoise_alt1, beatnoise_alt2, glitch1, glitch2
  };
  static const int num_patterns = sizeof(patterns) / sizeof(patterns[0]);

  bool flip = FLIPPERAT;
  bool skip = SKIPPERAT;
  bool both = (flip && skip);

  // 両押しでパターン切替
  if (both) current_pattern = (current_pattern + 1) % num_patterns;

  // FLIPPでランダム変調
  if (flip && !both) { 
    mod1 = (esp_random() % 12) + 4; 
    mod2 = (esp_random() % 12) + 6; 
  }

  // SKIPPで軽い波形変調
  if (skip && !both) { 
    mod1 ^= 3; 
    mod2 ^= 5; 
  }

  // tが最大値でループしたタイミングで波形変化
  t += 1;
  if (t > 0x1FFFF) {
    t = 0;
    // 1ループごとに大きめにmodを変化
    mod1 = (mod1 + (esp_random() % 8) + 1) % 16;
    mod2 = (mod2 + (esp_random() % 8) + 1) % 16;
  }

  uint16_t pout = patterns[current_pattern](t, mod1, mod2);

  DACWRITER(pout & 0xFFF);
  YELLOWERS(pout);

  gyo = ADCREADER;
  adc_read = EARTHREAD;
  ASHWRITER(adc_read);

  REG(I2S_CONF_REG)[0] &= ~(BIT(5));
  REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
  REG(I2S_CONF_REG)[0] |= BIT(5);
}

typedef uint16_t (*BytebeatFunc)(uint32_t);
uint16_t wallflower(uint32_t t) {
  uint32_t v = (t * ((t >> 9 | t >> 13) & 25 & (t >> 6))) & 0xFF;
  return v << 8;
}
typedef uint16_t (*BytebeatFunc)(uint32_t);
uint16_t low0(uint32_t t){ return ((t & 0x1FF)==0) ? 0xFFF : 0; }
uint16_t low1(uint32_t t){ return ((t & 0x17F)==0) ? 0xFFF : 0; }
uint16_t low2(uint32_t t){ return ((t & 0x0FF)==0) ? 0xFFF : 0; }
uint16_t low3(uint32_t t){ return ((t & 0x3FF)==0) ? 0xFFF : 0; }
void IRAM_ATTR bytebeats3() {
    INTABRUPT;

    static uint32_t t = 0;
    static int current_pattern = 0;     // 今の低音パターン
    static const BytebeatFunc lows[] = {low0, low1, low2, low3};
    static const int num_lows = sizeof(lows)/sizeof(lows[0]);

    bool both_pressed = (FLIPPERAT && SKIPPERAT);

    if(both_pressed){
        current_pattern = (current_pattern + 1) % num_lows; // 同時押しでパターン切替
    }

    if(FLIPPERAT){
        t += 2;  // FLIPP単押しで早めに進める
    } else if(SKIPPERAT){
        t += 1;  // SKIPP単押しで普通に進める
    } else {
        t += 1;  // 何も押してなければ通常進行
    }

    t &= 0x1FFFF;

    uint16_t pout = lows[current_pattern](t);

    DACWRITER(pout);
    YELLOWERS(pout);

    gyo = ADCREADER;
    adc_read = EARTHREAD;
    ASHWRITER(adc_read);

    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);
}

typedef uint16_t (*BytebeatFunc)(uint32_t);
uint16_t beats4_dynamic(uint32_t t,
                        uint32_t hi_width, uint32_t mid_shift,
                        uint32_t low_width, uint32_t accent_shift,
                        uint32_t noise_mask) {

    const uint32_t s = 48000;
    uint32_t a = t / (s / 12);

    // 高速クリック（短く瞬間音）
    uint32_t hi = ((t & hi_width) == 0 && (t & 3) == 0) ? 1024 : 0;

    // 中速スネア（短く瞬間音）
    uint32_t mid = ((t & 31) == mid_shift && (t & 7) == 0) ? 2048 : 0;

    // 低速バスドラ（少し長め）
    uint32_t low = ((t & low_width) == 0) ? 3072 : 0;

    // 変則アクセント（16ループごとでもいいけど今回は4ループごと）
    uint32_t accent = ((a % 5) == accent_shift || (a % 11) == (accent_shift + 3)) ? 1500 : 0;

    // ノイズ（短く瞬間的）
    uint32_t noise = ((rand() & noise_mask) == 0 && (t & 15) == 0) ? 512 : 0;

    // 合成
    uint32_t v = hi + mid + low + accent + noise;
    if (v > 0xFFF) v = 0xFFF;

    return uint16_t(v);
}

void IRAM_ATTR bytebeats4() {
    INTABRUPT;

    static uint32_t t = 0;
    static bool last_flp = false;
    static bool last_skp = false;

    static uint32_t hi_width = 7;
    static uint32_t mid_shift = 16;
    static uint32_t low_width = 1023;
    static uint32_t accent_shift = 0;
    static uint32_t noise_mask = 15;
    static uint32_t loop_count = 0;

    // --- FLIPP: tの値を変更（ループやリズムに影響） ---
    if (FLIPPERAT && !last_flp) {
        t += 22050;  // 約0.5秒分進める
    }
    last_flp = FLIPPERAT;

    // --- SKIPP: 波形パラメータランダム化 ---
    if (SKIPPERAT && !last_skp) {
        hi_width = 4 + (rand() & 15);
        mid_shift = rand() & 31;
        low_width = 512 + (rand() & 1023);
        accent_shift = rand() & 11;
        noise_mask = 7 + (rand() & 15);
    }
    last_skp = SKIPPERAT;

    // ---- ループカウント ----
    if ((t % 48000) == 0) loop_count++;

    // ---- 4ループごとの微変化（波形 + アクセント） ----
    if ((loop_count % 4) == 0 && (t % 48000) == 0) {
        hi_width ^= 1 + (rand() & 3);
        mid_shift ^= 1 + (rand() & 7);
        low_width ^= 1 + (rand() & 31);
        noise_mask ^= 1 + (rand() & 7);
        accent_shift = rand() & 11;
    }

    // ---- bytebeat 出力 ----
    uint16_t pout = beats4_dynamic(t, hi_width, mid_shift, low_width, accent_shift, noise_mask);

    // ---- DAC / グレーアウト出力 ----
    DACWRITER(pout);
    YELLOWERS(pout);

    // ---- ADC処理 ----
    gyo = ADCREADER;
    adc_read = EARTHREAD;
    ASHWRITER(adc_read);

    // ---- I2S フラッシュ ----
    REG(I2S_CONF_REG)[0] &= ~(BIT(5));
    REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
    REG(I2S_CONF_REG)[0] |= BIT(5);

    // ---- 時間進行 ----
    t++;
}
