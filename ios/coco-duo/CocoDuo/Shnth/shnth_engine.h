/*
 * shnth_engine.h -- portable C port of the Shbobo Shnth sound engine
 * (the "shmat" ARM firmware bytecode interpreter, SHBOBO=0 build).
 *
 * Derived from the Shbobo source code (github pblasser/shbobo), MIT License:
 *
 *   Copyright (c) 2021 peter blasser
 *
 *   Permission is hereby granted, free of charge, to any person obtaining a
 *   copy of this software and associated documentation files (the "Software"),
 *   to deal in the Software without restriction, including without limitation
 *   the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *   and/or sell copies of the Software, and to permit persons to whom the
 *   Software is furnished to do so, subject to the following conditions:
 *   The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *   DEALINGS IN THE SOFTWARE.
 *
 * C99, no malloc, no floating point, only <stdint.h>/<string.h>.
 * Assumes two's complement, arithmetic right shift of negative ints and
 * modular int conversion (true for GCC/Clang on Xtensa, ARM, x86).
 *
 * Host compile-time hooks (define before including / on the command line):
 *   SHNTH_HOT                 attribute for per-sample functions (e.g. IRAM_ATTR)
 *   SHNTH_RODATA              attribute for the 3 small const tables used per
 *                             sample (e.g. DRAM_ATTR on ESP32 if the audio code
 *                             must run while the flash cache is disabled)
 *   SHNTH_DL_RD(eng, i)       read  int16 sample i (0..8191) of the 16 KB delay
 *   SHNTH_DL_WR(eng, i, v)    write int16 sample i of the 16 KB delay
 *     (default: eng->dl[i]; the 16 KB = 4 instances x 2048 int16 samples;
 *      instance k = samples k*2048 .. k*2048+2047, shared by string/comb/
 *      zither/melody k exactly like karpBUFFA in the firmware)
 *   SHNTH_MAX_DEPTH           max expression nesting evaluated (default 48)
 */
#ifndef SHNTH_ENGINE_H
#define SHNTH_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef SHNTH_HOT
#define SHNTH_HOT
#endif
#ifndef SHNTH_RODATA
#define SHNTH_RODATA
#endif
#ifndef SHNTH_MAX_DEPTH
#define SHNTH_MAX_DEPTH 48
#endif

#define SHNTH_CPU_HZ        72000000u   /* STM32F103 core clock              */
#define SHNTH_DEFAULT_RELOAD 0x1000u    /* -> 72e6/4097 = 17574 Hz           */
#define SHNTH_DL_SAMPLES    8192        /* 16384 bytes of int16              */
#define SHNTH_CORE_RAM      0x370       /* firmware RAM minus karpBUFFA      */

/* button bitmask for shnth_inputs.buttons */
#define SHNTH_BTN_MINOR_A  (1u << 0)    /* minor  (PA6) */
#define SHNTH_BTN_MINOR_B  (1u << 1)    /* minorb (PA7) */
#define SHNTH_BTN_MINOR_C  (1u << 2)    /* minorc (PA8) */
#define SHNTH_BTN_MINOR_D  (1u << 3)    /* minord (PA9) */
#define SHNTH_BTN_MAJOR_A  (1u << 4)    /* major  (PC4) */
#define SHNTH_BTN_MAJOR_B  (1u << 5)
#define SHNTH_BTN_MAJOR_C  (1u << 6)
#define SHNTH_BTN_MAJOR_D  (1u << 7)    /* majord (PC7) */
#define SHNTH_BTN_TAR      (1u << 8)    /* tar    (PA1), also re-tares antennae */

/*
 * Inputs.  Two modes:
 *
 * cooked == 0 (RAW, recommended): values are what the firmware's input
 *   interrupts read from the hardware; the engine applies the firmware's
 *   control-rate processing itself, clocked by the virtual 72 MHz clock that
 *   shnth_tick advances by (reload+1) cycles per sample:
 *     bar[k]  : ADC counts of bar k minus the reference channel,
 *               -4095..4095, 0 = bar at rest.  Every 34560 cycles (2083.3 Hz)
 *               dead zone (|x|<16 -> 0) + one-pole smoothing ->
 *               barres = 32*dz in steady state, saturating at |dz| >= 1024.
 *               So map an XY pad / CV to about +-1040 counts for full range.
 *     corp[k] : antenna oscillator count change per 36.4 ms gate relative to
 *               "untouched" (int16).  Every gate (27.47 Hz) the engine does
 *               (twice, like the firmware) corp = sat((corp + (raw-tare)*64)/2);
 *               while TAR is held, tare = raw (antenna zeroing).
 *               Steady state = 64*(raw-tare), saturating at +-512 counts.
 *     wind    : microphone ADC counts minus reference (-4095..4095), used
 *               live, scaled <<4 by the `wind` word.
 * cooked != 0: bar[] and corp[] are taken as the firmware's post-filter
 *   values directly (-32768..32767, 0 at rest) and written to the engine
 *   state at once; no smoothing / dead zone / tare is applied (the host does
 *   it).  wind and buttons are the same as in RAW mode.
 */
typedef struct {
    int16_t  bar[4];
    int16_t  corp[2];
    int16_t  wind;
    uint16_t buttons;     /* SHNTH_BTN_* */
    uint8_t  cooked;
} shnth_inputs;

typedef struct shnth_engine {
    /* ---- core state: firmware RAM image without karpBUFFA (880 bytes) ---- */
    union {
        uint8_t  b[SHNTH_CORE_RAM];
        uint16_t h[SHNTH_CORE_RAM / 2];
        uint32_t w[SHNTH_CORE_RAM / 4];
    } ram;
    /* ---- interpreter registers ---- */
    const uint8_t *img;   /* upload image (pointer kept, not copied) */
    uint32_t len;         /* image length in bytes */
    uint32_t pc;          /* lispCOD as offset into img */
    int32_t  r10;         /* dacLEFT  : `right` word + pan place>0 */
    int32_t  r11;         /* dacRITE  : `left` word  + pan place<0 */
    uint32_t reload;      /* SysTick RELOAD requested by this sample */
    uint32_t min_period;  /* host cap on engine rate, in 72 MHz cycles (0=none) */
    uint32_t cyc_bar, cyc_ant; /* virtual clock for the input "interrupts" */
    uint16_t odr;         /* GPIOC_ODR: LEDs are bits 8..15 */
    uint8_t  sin;         /* lispSIN: 0 dirac, 1 arab */
    uint8_t  depth;
    uint8_t  cooked;
    uint8_t  manual_control; /* 1: host calls shnth_control_* itself */
    uint16_t cpu_model;   /* 0 off, else % scale of the STM32 cycle estimate */
    uint32_t est, nrd;    /* per-tick STM32 cycle estimate accumulators */
    uint32_t last_est;    /* estimated STM32 cycles of the last tick */
    /* ---- raw inputs ---- */
    int16_t  in_bar[4], in_corp[2], in_wind;
    uint16_t in_buttons;
    /* ---- resampler state for shnth_render ---- */
    int32_t  rs_l, rs_r;        /* current held engine output (16-bit units) */
    uint64_t rs_left;           /* units of the current engine sample left */
    /* ---- the 16 KB delay (default backing store for SHNTH_DL_*) ---- */
    int16_t *dl;
} shnth_engine;

/* init: zero all state like power-up; dl = 8192 int16 samples, or NULL if
   the host overrides SHNTH_DL_RD/WR.  No image loaded -> silence. */
void     shnth_init(shnth_engine *e, int16_t *dl);
/* reset: zero all engine state + delay (like a reboot), keep the image */
void     shnth_reset(shnth_engine *e);
/* load an upload image exactly as shlisp_compile() produces it (vector
   table + soups + 16 zero bytes).  The pointer is kept: the bytes must stay
   valid.  State is NOT cleared (the firmware never clears it on upload/preset
   change).  Returns the number of presets, or -1 if the image is too short. */
int      shnth_load(shnth_engine *e, const uint8_t *img, uint32_t len);
void     shnth_select(shnth_engine *e, int preset);  /* sets witch_vectore */
int      shnth_preset(const shnth_engine *e);
int      shnth_preset_count(const shnth_engine *e);
void     shnth_set_inputs(shnth_engine *e, const shnth_inputs *in);

/* one sample.  *left / *right = 12-bit DAC codes 0..4095 centred at 2048,
   exactly what the firmware writes to the DAC: clamp(sum>>4,-2048,2047)+2048.
   Like the firmware the codes are those of the PREVIOUS sample's sums
   (one-sample latency).  left = word `left` (+pan place<0), right = word
   `right` (+pan place>0).  16-bit PCM: (code-2048)<<4. */
SHNTH_HOT void shnth_tick(shnth_engine *e, int *left, int *right);

/* rate the patch asks for after the last tick: 72e6/(reload+1), rounded;
   17574 Hz unless `srate` was evaluated.  shnth_period_cycles returns the
   exact period in 72 MHz cycles (after the host cap). */
uint32_t shnth_rate_hz(const shnth_engine *e);
uint32_t shnth_period_cycles(const shnth_engine *e);
/* cap the engine rate (srate can ask for 90+ kHz; the STM32 was CPU-bound
   there).  0 = no cap.  Affects rate_hz/period/render and the input clocks. */
void     shnth_set_max_rate(shnth_engine *e, uint32_t hz);
uint8_t  shnth_leds(const shnth_engine *e);          /* 8 LEDs, bit0 = PC8 */
/* Rough estimate of the STM32 cycles the last tick needed (ISR + bytecode;
   an uncalibrated model, see NOTES.md).  With cpu_model on, the period is
   rounded up to a multiple of (reload+1) like a SysTick that misses wraps
   while the ISR is still running -- i.e. patches whose srate asks for more
   than the 72 MHz chip could do get the (estimated) hardware rate.
   percent: 0 = off (default: the rate the patch asks for), 100 = use the
   model as is, other values scale the estimate (calibrate by ear against a
   real Shnth). */
uint32_t shnth_est_cycles(const shnth_engine *e);
void     shnth_set_cpu_model(shnth_engine *e, int percent);

/* convenience for both hosts: render n stereo frames of int16 (L,R
   interleaved) at host_rate Hz, running the engine at its own variable rate
   and box-filtering its zero-order-hold output (integer math only). */
SHNTH_HOT void shnth_render(shnth_engine *e, int16_t *out, int frames, uint32_t host_rate);

/* the firmware's input interrupts, for hosts that set manual_control=1 and
   call them themselves (bars ~2083 Hz, antennae ~27.5 Hz).  With
   manual_control=0 (default) shnth_tick calls them on its virtual clock. */
void     shnth_control_bars(shnth_engine *e);
void     shnth_control_antennae(shnth_engine *e);

#ifdef __cplusplus
}
#endif
#endif
