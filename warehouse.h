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
