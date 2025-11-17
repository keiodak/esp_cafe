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

#define COCO_SIZE 512
static int16_t coco_buf[COCO_SIZE];
static uint16_t coco_idx = 0;

void IRAM_ATTR swp() {
    INTABRUPT;

    {   // --- 入力 / 基本処理 ---
        int16_t gyo = ADCREADER;
        int16_t cv = EARTHREAD;

        pout = dellius(t, gyo, lamp);
        int16_t wmp_out = gyo;

        {   // --- t カウント ---
            if (FLIPPERAT) t++;
            else t--;
            t &= 0x1FFFF;
        }

        {   // --- SKIPP レイヤー / DAC & ASH 出力 ---
            static uint8_t last_skipp = 0;
            int16_t dac_out;

            if (SKIPPERAT && !last_skipp) { 
                last_skipp = 1;

                int layer2_idx = (coco_idx + COCO_SIZE/2) & (COCO_SIZE - 1);

                // ---- レイヤー2を 1/2 で出力 ----
                dac_out = coco_buf[layer2_idx] / 2;

                if (dac_out > 32767)  dac_out = 32767;
                if (dac_out < -32768) dac_out = -32768;

            } else {
                if (!SKIPPERAT) last_skipp = 0;
                dac_out = pout;
            }

            DACWRITER(dac_out);
            ASHWRITER(wmp_out);
        }
    }

    {   // --- FLIPP: 8分割シャッフル ---
        static uint8_t last_flip = 0;
        static int16_t temp[COCO_SIZE];

        if (FLIPPERAT) {
            if (!last_flip) {

                const int PART = COCO_SIZE / 8;

                for (int i = 0; i < COCO_SIZE; i++)
                    temp[i] = coco_buf[i];

                int order[8] = {0,1,2,3,4,5,6,7};
                for (int i = 0; i < 8; i++) {
                    int r = esp_random() & 7;
                    int tmp = order[i];
                    order[i] = order[r];
                    order[r] = tmp;
                }

                for (int k = 0; k < 8; k++) {
                    int src = order[k];
                    int dst = k;
                    for (int i = 0; i < PART; i++) {
                        coco_buf[dst*PART + i] = temp[src*PART + i];
                    }
                }
            }
            last_flip = 1;
        } else {
            last_flip = 0;
        }
    }

    {   // --- バッファ書き込み ---
        coco_buf[coco_idx] = gyo;
        coco_idx = (coco_idx + 1) & (COCO_SIZE - 1);
    }

    {   // --- I2S リスタート ---
        REG(I2S_CONF_REG)[0] &= ~(BIT(5));
        REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
        REG(I2S_CONF_REG)[0] |= BIT(5);
    }

    YELLOWERS(t);
}

void IRAM_ATTR dist() {
    INTABRUPT;

    {   // --- 入力 / 基本処理 ---
        int16_t gyo = ADCREADER;
        int16_t cv  = EARTHREAD;

        // ==========================
        // 軽量ローファイ処理
        // ==========================
        static int16_t last_sample = 0;
        static uint8_t sr_cnt = 0;
        static int32_t prev = 0;

        sr_cnt++;
        if(sr_cnt >= 2){       // サンプルレートを半分に
            sr_cnt = 0;
            last_sample = gyo;
        }

        int32_t temp = (prev*3 + last_sample) >> 2;  // LPFで丸める
        prev = temp;

        gyo = (int16_t)(temp & 0xFFF0);              // ビットクラッシュ

        int16_t wmp_out = gyo;   // WMP 部分はそのまま

        pout = dellius(t, gyo, lamp);

        {   // --- t カウント ---
            if (FLIPPERAT) t++;
            else t--;
            t &= 0x1FFFF;
        }

        {   // --- SKIPP レイヤー / DAC & ASH 出力 ---
            static uint8_t last_skipp = 0;
            int16_t dac_out;

            if (SKIPPERAT && !last_skipp) { 
                last_skipp = 1;
                int layer2_idx = (coco_idx + COCO_SIZE/2) & (COCO_SIZE - 1);
                dac_out = coco_buf[layer2_idx] / 2;  // 音量半分
                if (dac_out > 32767) dac_out = 32767;
                if (dac_out < -32768) dac_out = -32768;
            } else {
                if (!SKIPPERAT) last_skipp = 0;
                dac_out = pout;
            }

            DACWRITER(dac_out);
            ASHWRITER(wmp_out);
        }
    }

    {   // --- FLIPP: 8分割シャッフル ---
        static uint8_t last_flip = 0;
        static int16_t temp[COCO_SIZE];

        if (FLIPPERAT) {
            if (!last_flip) {
                const int PART = COCO_SIZE / 8;
                for (int i = 0; i < COCO_SIZE; i++)
                    temp[i] = coco_buf[i];

                int order[8] = {0,1,2,3,4,5,6,7};
                for (int i = 0; i < 8; i++) {
                    int r = esp_random() & 7;
                    int tmp = order[i];
                    order[i] = order[r];
                    order[r] = tmp;
                }

                for (int k = 0; k < 8; k++) {
                    int src = order[k];
                    int dst = k;
                    for (int i = 0; i < PART; i++) {
                        coco_buf[dst*PART + i] = temp[src*PART + i];
                    }
                }
            }
            last_flip = 1;
        } else {
            last_flip = 0;
        }
    }

    {   // --- バッファ書き込み ---
        coco_buf[coco_idx] = gyo;
        coco_idx = (coco_idx + 1) & (COCO_SIZE - 1);
    }

    {   // --- I2S リスタート ---
        REG(I2S_CONF_REG)[0] &= ~(BIT(5));
        REG(I2S_INT_CLR_REG)[0] = 0xFFFFFFFF;
        REG(I2S_CONF_REG)[0] |= BIT(5);
    }

    YELLOWERS(t);
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
