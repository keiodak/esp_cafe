/*
 * shnth_engine.c -- portable C port of the Shbobo Shnth sound engine
 * ("wanilla" bytecode interpreter of sorce/shmat/wanilla*.s, SHBOBO=0 build).
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
 * Translation rules (see NOTES.md): every handler is a C function whose
 * local `acc` mirrors r1 (lispACC) of the asm at all times, because a nested
 * expression receives the caller's r1 (some words return it on an early list
 * end).  All arithmetic is 32-bit wrapping (done in uint32_t), shifts are asr
 * unless the asm says lsr.  State lives in one byte array laid out exactly
 * like ramus_bss.s minus the 16 KB karpBUFFA, so every aliasing quirk of the
 * firmware (waterBP[12..15]==philtBP, string/zither/melody sharing, shared
 * trigger bits) is reproduced by construction.
 */
#include "shnth_engine.h"
#include <string.h>

typedef shnth_engine E;

/* ------------------------------------------------------------------ */
/* default delay access: int16 sample index 0..8191                    */
/* ------------------------------------------------------------------ */
#ifndef SHNTH_DL_RD
#define SHNTH_DL_RD(eng, i)    ((int16_t)(eng)->dl[(i)])
#endif
#ifndef SHNTH_DL_WR
#define SHNTH_DL_WR(eng, i, v) ((eng)->dl[(i)] = (int16_t)(v))
#endif

/* ------------------------------------------------------------------ */
/* RAM layout: firmware offsets (ramus_bss.s); entries after karpBUFFA */
/* (fw 0x41C0..) are moved down by 0x4000.                             */
/* ------------------------------------------------------------------ */
enum {
    WITCH = 0x0000, TARESZ = 0x001C, BARRES = 0x0020, CHINK = 0x0028,
    TRANGWONZ = 0x002E, TOGOUPTRIG = 0x002F, TOGODNTRIG = 0x0030,
    TOGLTRIG = 0x0031, TOGLVALS = 0x0032, SWOOPTRIG = 0x0033,
    LFOGWONZ = 0x0034, FOGTRIG = 0x0035, FOGTRAN = 0x0036,
    KARPTRIG = 0x003A, ZITHTRIG = 0x003B, WATERTRIG = 0x003C,
    FOURSGWONZ = 0x003D, GEARTRIG = 0x003F, PULSETRIG = 0x0040,
    SALSATRIG = 0x0041, RUNGLERTRIG = 0x0042, JUMPSRATTRIG = 0x0043,
    TRANGOES = 0x0044, TRANSAWS = 0x0054, TOGOPLACZ = 0x0064,
    TOGOVALES = 0x006C, SWOOPVALES = 0x007C, SWOOPGWONZ = 0x008C,
    MOUNTVALES = 0x0094, NOISEVALES = 0x00B4, DUSTVALES = 0x00C4,
    DUSTRAMPS = 0x00D4, FOGVALES = 0x00E4, FOGPLACZ = 0x00EC,
    FOGNDNDZ = 0x00F0, FOGSWGWONZ = 0x0170, FOGSWVALES = 0x0180,
    FOGTRVALES = 0x01A0,
    /* karpBUFFA (fw 0x01C0, 0x4000 bytes) lives behind SHNTH_DL_RD/WR */
    ZITHNNNN = 0x01C0, ZITHSTRNG = 0x01D0, ZITHPLACZ = 0x01D4,
    KARPPLACZ = 0x01E4, ZITHPULSZ = 0x01EC, KARPPULSZ = 0x01F4,
    KARPNOISZ = 0x01FC, ZITHVALES = 0x0204, WATERQNQN = 0x020C,
    WATERVALES = 0x024C, WATERDROP = 0x0254, WATERBP = 0x0258,
    PHILTBP = 0x0270, WATERLP = 0x0278, PHILTLP = 0x0290,
    FOURSESVALE = 0x0298, SLEWVALE = 0x02A0, WHEELVALE = 0x02B0,
    GEARVALE = 0x02C0, PULSEVALE = 0x02C8, SAUCEVALE = 0x02D8,
    SAUCEPOSZ = 0x02E8, SALSAVALE = 0x02F0, MELOPLACZ = 0x0300,
    MELOPULSZ = 0x0310, WORMVALES = 0x0320, LADDERVALES = 0x0328,
    RUNGLERVALES = 0x0330, COMPRVALE = 0x0338, COMPRSWANG = 0x0340,
    LIKDCVALE = 0x0358, LIKDCSWANG = 0x0360, RAM_END = 0x0370
};
/* firmware RAM address of comprVALE (= 0x20000000 + 0x4338): the dirac
   `press` attack quirk uses it as a number */
#define COMPRVALE_ADDR 0x20004338

typedef char shnth_layout_check[(RAM_END == SHNTH_CORE_RAM &&
                                 COMPRVALE + 0x4000 == 0x4338) ? 1 : -1];

/* ------------------------------------------------------------------ */
/* arithmetic helpers (32-bit wrapping, no UB)                         */
/* ------------------------------------------------------------------ */
#define U(x) ((uint32_t)(x))
static inline int32_t wadd(int32_t a, int32_t b) { return (int32_t)(U(a) + U(b)); }
static inline int32_t wsub(int32_t a, int32_t b) { return (int32_t)(U(a) - U(b)); }
static inline int32_t wmul(int32_t a, int32_t b) { return (int32_t)(U(a) * U(b)); }
static inline int32_t wneg(int32_t a)            { return (int32_t)(0u - U(a)); }
static inline int32_t lsl(int32_t a, int n)      { return (int32_t)(U(a) << n); }
static inline int32_t lsr(int32_t a, int n)      { return (int32_t)(U(a) >> n); }
static inline int32_t clampi(int32_t x, int32_t lo, int32_t hi) { return x < lo ? lo : x > hi ? hi : x; }
static inline int32_t ssat16(int32_t x) { return clampi(x, -32768, 32767); }
static inline int32_t usat16(int32_t x) { return clampi(x, 0, 65535); }
static inline int32_t usat15(int32_t x) { return clampi(x, 0, 32767); }
/* SAT: return saturation of the variant (ssat #16 / usat #16) */
static inline int32_t SAT(int A, int32_t x) { return A ? usat16(x) : ssat16(x); }
/* ABS: RECTA reg,reg -- dirac: negate if <0 (pure 32-bit), arab: usat #16 */
static inline int32_t ABSV(int A, int32_t x) { return A ? usat16(x) : (x < 0 ? wneg(x) : x); }
/* ALSER: dirac asr 15, arab lsr 16 */
static inline int32_t SHR(int A, int32_t x) { return A ? lsr(x, 16) : (x >> 15); }
static inline int32_t HIGH(int A) { return A ? 0x10000 : 0x8000; }
/* literal argument byte b (1..254) */
static inline int32_t LIT(int A, uint32_t b) { return A ? (int32_t)(b << 8) : (int32_t)(int16_t)(uint16_t)(b << 8); }
/* signed overflow flag of a - b */
static inline int vsub(int32_t a, int32_t b) { int32_t r = wsub(a, b); return ((a ^ b) & (a ^ r)) < 0; }
static inline int32_t sdiv(int32_t n, int32_t d) {   /* Cortex-M3 sdiv, /0 = 0 */
    if (d == 0) return 0;
    if (n == INT32_MIN && d == -1) return INT32_MIN;
    return n / d;
}
static inline int32_t udiv(int32_t n, int32_t d) { return d ? (int32_t)(U(n) / U(d)) : 0; }

/* ------------------------------------------------------------------ */
/* RAM accessors                                                       */
/* ------------------------------------------------------------------ */
static inline uint32_t rd8(E *e, unsigned o)           { return e->ram.b[o]; }
static inline void     wr8(E *e, unsigned o, int32_t v) { e->ram.b[o] = (uint8_t)v; }
static inline int32_t  rd16s(E *e, unsigned o)          { return (int16_t)e->ram.h[o >> 1]; }
static inline int32_t  rd16u(E *e, unsigned o)          { return e->ram.h[o >> 1]; }
static inline int32_t  LDH(E *e, int A, unsigned o)     { return A ? rd16u(e, o) : rd16s(e, o); }
static inline void     wr16(E *e, unsigned o, int32_t v) { e->ram.h[o >> 1] = (uint16_t)v; }
static inline int32_t  rd32(E *e, unsigned o)           { return (int32_t)e->ram.w[o >> 2]; }
static inline void     wr32(E *e, unsigned o, int32_t v) { e->ram.w[o >> 2] = (uint32_t)v; }
/* bit-band access: bit i of the bytes at o */
static inline int  getbit(E *e, unsigned o, unsigned i) { return (e->ram.b[o + (i >> 3)] >> (i & 7)) & 1; }
static inline void setbit(E *e, unsigned o, unsigned i, int v) {
    uint8_t *p = &e->ram.b[o + (i >> 3)];
    if (v) *p = (uint8_t)(*p | (1u << (i & 7))); else *p = (uint8_t)(*p & ~(1u << (i & 7)));
}
/* TRIG_IDEE_TOO: level = usat(v,1) stored, returns rising edge */
static inline int trig(E *e, unsigned o, unsigned i, int32_t v) {
    int h = v >= 1, old = getbit(e, o, i);
    setbit(e, o, i, h);
    return h && !old;
}
/* delay (karpBUFFA) as int16 samples */
static inline int32_t DLLD(E *e, int A, uint32_t i) {
    int32_t v = SHNTH_DL_RD(e, i);
    return A ? (int32_t)(uint16_t)v : (int32_t)(int16_t)v;
}
#define DLST(e, i, v) SHNTH_DL_WR((e), (i), (int16_t)(v))

/* ------------------------------------------------------------------ */
/* bytecode reading (bounds checked: past the image everything is 00)  */
/* ------------------------------------------------------------------ */
static inline uint32_t RD(E *e)   { uint32_t p = e->pc++; e->nrd++; return p < e->len ? e->img[p] : 0; }
static inline uint32_t PEEK(E *e) { return e->pc < e->len ? e->img[e->pc] : 0; }

static SHNTH_HOT int32_t sexpr(E *e, int32_t acc_in);

/* ARG(v): POPSEX -- next argument; list end => return SAT(acc) from the
   enclosing handler.  A nested expression gets the current acc (r1). */
#define ARG(v) do { uint32_t b_ = RD(e); \
    if (!b_) return SAT(A, acc); \
    (v) = (b_ != 0xFF) ? LIT(A, b_) : sexpr(e, acc); } while (0)

/* LISPMULADD: acc = acc*m >> 15 (lsr 16 arab) + a, repeated */
static SHNTH_HOT int32_t muladd(E *e, int A, int32_t acc) {
    int32_t r;
    for (;;) {
        ARG(r); acc = SHR(A, wmul(acc, r));
        ARG(r); acc = wadd(acc, r);
    }
}
/* SQUISHRAMP (bar, corp): one mul/add pair (mul is asr in both variants),
   further args evaluated and discarded */
static SHNTH_HOT int32_t squish(E *e, int A, int32_t acc) {
    int32_t r;
    ARG(r); acc = wmul(acc, r) >> (A ? 16 : 15);
    ARG(r); acc = wadd(acc, r);
    for (;;) ARG(r);
}
/* SCANETTO: skip one element without evaluating it */
static inline void skip1(E *e) {
    int32_t d = 0;
    do { uint32_t b = RD(e); if (b == 0) d--; if (b == 0xFF) d++; } while (d >= 1);
}
/* SCANSOR_IDEE_END: skip to the end of the list (consumes the 00) */
static inline void skip_to_end(E *e) {
    int32_t d = 0;
    for (;;) { uint32_t b = RD(e); if (b == 0) d--; if (b == 0xFF) d++; if (d < 0) return; }
}

/* ------------------------------------------------------------------ */
/* shared oscillator / envelope / filter steps                         */
/* ------------------------------------------------------------------ */
/* TRANGO_IDEE_NUME */
static inline int32_t trango_nume(E *e, int A, int32_t acc, int32_t n, unsigned bo, unsigned bi, unsigned vo) {
    n = ABSV(A, n);
    acc = getbit(e, bo, bi) ? wadd(acc, n >> 4) : wsub(acc, n >> 4);
    wr16(e, vo, acc);
    return acc;
}
/* TRANGO_IDEE_DENO (reflect at +-d dirac, 0..d arab).  st32: 32-bit store
   (mount) instead of 16-bit. */
static inline int32_t trango_deno(E *e, int A, int32_t acc, int32_t d, unsigned bo, unsigned bi, unsigned vo, int st32) {
    int32_t t = wsub(acc, d);
    int v = vsub(acc, d), lt;
    if (acc > d) {
        setbit(e, bo, bi, 0); acc = wsub(acc, lsl(t, 1));
        if (st32) wr32(e, vo, acc); else wr16(e, vo, acc);
    }
    if (!A) { t = wadd(acc, d); lt = ((int64_t)acc + d) < 0; }
    else    { t = acc; lt = (acc < 0) ^ v; }      /* movs keeps V of the subs */
    if (lt) {
        setbit(e, bo, bi, 1); acc = wsub(acc, lsl(t, 1));
        if (st32) wr32(e, vo, acc); else wr16(e, vo, acc);
    }
    return acc;
}
/* TRANSA_IDEE_NUME / DENO */
static inline int32_t transa_nume(E *e, int A, int32_t acc, int32_t n, unsigned vo) {
    n = ABSV(A, n); acc = wadd(acc, n >> 4); wr16(e, vo, acc); return acc;
}
static inline int32_t transa_deno(E *e, int A, int32_t acc, int32_t d, unsigned vo) {
    d = ABSV(A, d);
    if (acc > d) { acc = A ? wsub(acc, d) : wsub(wsub(acc, d), d); wr16(e, vo, acc); }
    return acc;
}
/* SWOOP_IDEE_NUME / DENO (go = phase byte, vo = value) */
static inline int32_t swoop_nume(E *e, int A, int32_t acc, int32_t n, unsigned go, unsigned vo) {
    uint32_t G = rd8(e, go), g;
    n = ABSV(A, n);
    if (!A) { g = G & 3; if (g == 2) acc = wsub(acc, n >> 8); }
    else    { g = G & 1; if (g == 0) acc = wsub(acc, n >> 8); }
    if (g & 1) acc = wadd(acc, n >> 8);
    wr16(e, vo, acc);
    return acc;
}
static inline int32_t swoop_deno(E *e, int A, int32_t acc, int32_t d, unsigned go, unsigned vo) {
    d = ABSV(A, d);
    if (!A) {
        if (rd8(e, go) == 3 && acc > 0) { acc = 0; wr8(e, go, 0); }
        if (acc > d) { wr8(e, go, 2); acc = d; }
        else if ((int64_t)acc + d <= 0) { wr8(e, go, 3); acc = wsub(acc, lsl(wadd(acc, d), 1)); }
    } else {
        if (acc > d) { wr8(e, go, 0); acc = d; }
        else if (acc < 0) acc = 0;
    }
    wr16(e, vo, acc);
    return acc;
}
/* PHILTRE_IDEE_QUALITE: x -= ssat16(BP*q >> 15|16) */
static inline int32_t q_step(E *e, int A, int32_t x, int32_t q, unsigned bpo) {
    q = ABSV(A, q);
    return wsub(x, ssat16(wmul(rd16s(e, bpo), q) >> (A ? 16 : 15)));
}
/* PHILTRE_IDEE_PARAM: BP += x*f; LP += BP*f; returns LP */
static inline int32_t f_step(E *e, int A, int32_t x, int32_t f, unsigned bpo, unsigned lpo) {
    f = ABSV(A, f);
    x = ssat16(wadd(wmul(x, f) >> (A ? 16 : 15), rd16s(e, bpo)));
    wr16(e, bpo, x);
    x = ssat16(wadd(wmul(x, f) >> 15, rd16s(e, lpo)));
    wr16(e, lpo, x);
    return x;
}
/* NOISE_MEAT_IDEE4: 16-bit LCG step, stored; returns the new value as int16 */
static inline int32_t lcg(E *e, unsigned o) {
    wr16(e, o, wadd(wmul(rd16s(e, o), 25173), 13849));
    return rd16s(e, o);
}

/* ================================================================== */
/* handlers.  op = full opcode byte, A = variant, acc = caller's r1    */
/* ================================================================== */

/* 0x00-0x03: const 0, wind, corp, corpb */
static SHNTH_HOT int32_t h_mic(E *e, uint32_t op, int A, int32_t acc) {
    if (op & 2) return squish(e, A, rd16s(e, CHINK + 2 * (op & 1)));
    if (!(op & 1)) return 0;                     /* FF 00: constant 0 */
    acc = lsl(e->in_wind, 4);                    /* (ADC2_DR - ADC1_DR) << 4 */
    return muladd(e, A, acc);
}
/* 0x04-0x07: bar..bard */
static SHNTH_HOT int32_t h_bar(E *e, uint32_t op, int A, int32_t acc) {
    (void)acc;
    return squish(e, A, rd16s(e, BARRES + 2 * (op & 3)));
}
/* 0x08-0x0F: minor / major buttons */
static SHNTH_HOT int32_t h_button(E *e, uint32_t op, int A, int32_t acc) {
    unsigned bit = (op & 3) + ((op & 4) ? 4 : 0);
    acc = (e->in_buttons & (1u << bit)) ? HIGH(A) : 0;
    return muladd(e, A, acc);
}
/* 0x10-0x17: horn (TRANGO) */
static SHNTH_HOT int32_t h_horn(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = TRANGOES + 2 * i;
    int32_t n, d;
    acc = LDH(e, A, vo);
    ARG(n); acc = trango_nume(e, A, acc, n, TRANGWONZ, i, vo);
    ARG(d); acc = trango_deno(e, A, acc, ABSV(A, d), TRANGWONZ, i, vo, 0);
    return muladd(e, A, acc);
}
/* 0x18-0x1F: saw (TRANSA) */
static SHNTH_HOT int32_t h_saw(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = TRANSAWS + 2 * i;
    int32_t n, d;
    acc = LDH(e, A, vo);
    ARG(n); acc = transa_nume(e, A, acc, n, vo);
    ARG(d); acc = transa_deno(e, A, acc, d, vo);
    return muladd(e, A, acc);
}
/* 0x20-0x27: togo (sequencer) */
static SHNTH_HOT int32_t h_togo(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7;
    int32_t up, dn, v, scan, plaz, deep;
    uint32_t start;
    acc = LDH(e, A, TOGOVALES + 2 * i);
    ARG(up);
    scan = (int32_t)rd8(e, TOGOPLACZ + i);
    if (trig(e, TOGOUPTRIG, i, up)) { scan++; wr8(e, TOGOPLACZ + i, scan); }
    ARG(dn);
    scan = (int32_t)rd8(e, TOGOPLACZ + i);
    if (trig(e, TOGODNTRIG, i, dn)) { scan--; wr8(e, TOGOPLACZ + i, scan); }
    /* SCANSOR_IDEE_FRONT / _LOOP: skip (not evaluate) `scan` elements */
    start = e->pc; plaz = 0; deep = 0;
    for (;;) {
        uint32_t b;
        if (plaz == scan) break;                         /* lively */
        b = RD(e);
        if (b == 0) deep--;
        if (b == 0xFF) deep++;
        if (deep == 0) { plaz++; if (PEEK(e) != 0) continue; }
        else if (deep > 0) continue;
        /* 3: ran past the last element (or the list was empty) */
        e->pc = start;
        if (scan < 0) {
            if (plaz == 0) {
                /* empty list + down-trigger: the firmware loops forever here
                   (device hangs).  We pick element 0 (=> returns SAT(acc)). */
                scan = 0; wr8(e, TOGOPLACZ + i, 0); break;
            }
            scan = plaz - 1; plaz = 0; wr8(e, TOGOPLACZ + i, scan);
            continue;                                    /* bne 1b, deep kept */
        }
        scan = 0; plaz = 0; wr8(e, TOGOPLACZ + i, 0);
        break;
    }
    ARG(v);                         /* the selected element only */
    acc = v; wr16(e, TOGOVALES + 2 * i, v);
    skip_to_end(e);
    return acc;                     /* unsaturated (POPLTE path) */
}
/* 0x28-0x2F: toggle */
static SHNTH_HOT int32_t h_toggle(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7;
    uint32_t b;
    int32_t t;
    acc = getbit(e, TOGLVALS, i);
    b = RD(e);
    if (!b) return lsl(acc, A ? 16 : 15);           /* unsaturated */
    t = (b != 0xFF) ? LIT(A, b) : sexpr(e, acc);
    if (trig(e, TOGLTRIG, i, t)) acc ^= 1;          /* acc = bit read BEFORE t */
    setbit(e, TOGLVALS, i, acc);
    return muladd(e, A, lsl(acc, A ? 16 : 15));
}
/* 0x30-0x37: swoop */
static SHNTH_HOT int32_t h_swoop(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = SWOOPVALES + 2 * i, go = SWOOPGWONZ + i;
    int32_t t, n, d;
    acc = LDH(e, A, vo);
    ARG(t);
    if (trig(e, SWOOPTRIG, i, t)) wr8(e, go, rd8(e, go) | 1);
    ARG(n); acc = swoop_nume(e, A, acc, n, go, vo);
    ARG(d); acc = swoop_deno(e, A, acc, d, go, vo);
    return muladd(e, A, acc);
}
/* 0x38-0x3F: mount (16.16 slow triangle) */
static SHNTH_HOT int32_t h_mount(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = MOUNTVALES + 4 * i;
    int32_t n, d;
    acc = rd32(e, vo);
    acc = A ? lsr(acc, 16) : (acc >> 16);
    ARG(n);
    acc = rd32(e, vo);
    n = ABSV(A, n);
    acc = getbit(e, LFOGWONZ, i) ? wadd(acc, n) : wsub(acc, n);
    wr32(e, vo, acc);
    ARG(d);                          /* early end returns SAT(full 32-bit) */
    acc = trango_deno(e, A, acc, lsl(ABSV(A, d), 16), LFOGWONZ, i, vo, 1);
    acc = A ? lsr(acc, 16) : (acc >> 16);
    return muladd(e, A, acc);
}
/* 0x40-0x47: smoke (noise) */
static SHNTH_HOT int32_t h_smoke(E *e, uint32_t op, int A, int32_t acc) {
    unsigned vo = NOISEVALES + 2 * (op & 7);
    (void)acc;
    lcg(e, vo);
    return muladd(e, A, LDH(e, A, vo));
}
/* 0x48-0x4F: dust */
static SHNTH_HOT int32_t h_dust(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, ro = DUSTRAMPS + 2 * i, so = DUSTVALES + 2 * i;
    int32_t sp, w, thr;
    acc = LDH(e, A, ro);
    ARG(sp);
    acc = wadd(acc, ABSV(A, sp) >> 8);
    w = wadd(wmul(rd16s(e, so), 25173), 13849);
    thr = w & 0x7FFF;
    /* .ifeq ARAB (dirac): mvngt acc,thr -> restart at -thr-1; arab: 0 */
    if (acc > thr) { acc = A ? 0 : ~thr; wr16(e, so, w); }
    wr16(e, ro, acc);
    return muladd(e, A, acc);
}
/* 0x50-0x5F: fog (0x50), swamp (0x54), haze (0x58, 0x5C) */
static SHNTH_HOT int32_t h_fog(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3, kind = (op >> 2) & 3, P, m, k, g;
    int32_t t, v;
    int rise;
    acc = rd16s(e, FOGVALES + 2 * i);               /* ldrsh in both variants */
    ARG(t);
    rise = trig(e, FOGTRIG, i, t);
    P = rd8(e, FOGPLACZ + i);
    if (rise) {
        P = (P + 1) & 3; wr8(e, FOGPLACZ + i, P);
        wr8(e, FOGSWGWONZ + 4 * P + i, rd8(e, FOGSWGWONZ + 4 * P + i) | 1);
    }
    m = i + 4 * P;
    for (k = 0; k < 4; k++) {                       /* params: evaluated always, */
        ARG(v);                                     /* latched on the trigger    */
        if (rise) wr16(e, FOGNDNDZ + 32 * k + 2 * m, v);
    }
    acc = 0;
    for (g = 0; g < 4; g++) {
        int32_t en, h, hd;
        unsigned so = FOGSWVALES + 2 * (i + 4 * g), go = FOGSWGWONZ + i + 4 * g;
        unsigned ho = FOGTRVALES + 2 * (i + 4 * g), pm = 2 * (i + 4 * g);
        m = i + 4 * g;
        en = LDH(e, A, so);
        en = swoop_nume(e, A, en, LDH(e, A, FOGNDNDZ + 0 + pm), go, so);
        en = swoop_deno(e, A, en, LDH(e, A, FOGNDNDZ + 32 + pm), go, so);
        h = LDH(e, A, ho);
        if (kind < 2) h = trango_nume(e, A, h, LDH(e, A, FOGNDNDZ + 64 + pm), FOGTRAN, m, ho);
        else          h = transa_nume(e, A, h, LDH(e, A, FOGNDNDZ + 64 + pm), ho);
        hd = LDH(e, A, FOGNDNDZ + 96 + pm);
        if (kind == 1) hd = wadd(hd, en);           /* swamp */
        if (kind < 2) h = trango_deno(e, A, h, ABSV(A, hd), FOGTRAN, m, ho, 0);
        else          h = transa_deno(e, A, h, hd, ho);
        acc = wadd(acc, SHR(A, wmul(h, en)));
    }
    acc = SAT(A, acc);
    wr16(e, FOGVALES + 2 * i, acc);
    return muladd(e, A, acc);
}
/* COMBMEAT shared by string and comb */
static SHNTH_HOT int32_t combmeat(E *e, int A, unsigned i, int32_t acc) {
    int32_t nume, deno, fb, pos;
    uint32_t base = i * 2048u;
    ARG(nume);
    pos = rd16u(e, KARPPLACZ + 2 * i);
    pos = wadd(pos, A ? lsr(nume, 8) : (nume >> 8));
    pos = clampi(pos, 0, 2047);                     /* usat #11 */
    wr16(e, KARPPLACZ + 2 * i, pos);
    ARG(deno);
    deno = ABSV(A, deno);
    if (pos >= lsr(deno, 5)) pos = 0;               /* loop length deno/32 */
    if (PEEK(e) != 0) {
        ARG(fb);
        acc = wadd(acc, SHR(A, wmul(DLLD(e, A, base + pos), fb)));
        acc = SAT(A, acc >> 1);
        DLST(e, base + pos, acc);
        wr16(e, KARPPLACZ + 2 * i, pos);
        return muladd(e, A, acc);
    }
    acc = wadd(acc, DLLD(e, A, base + pos));
    acc = SAT(A, acc >> 1);
    DLST(e, base + pos, acc);
    wr16(e, KARPPLACZ + 2 * i, pos);
    (void)RD(e);                                    /* the 00 */
    return SAT(A, acc);
}
/* 0x60-0x67: string (0x60) / comb (0x64) */
static SHNTH_HOT int32_t h_karp(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3;
    int32_t v;
    acc = DLLD(e, A, i * 2048u + (uint32_t)rd16u(e, KARPPLACZ + 2 * i));
    if (!(op & 4)) {                                /* string */
        int32_t p, n;
        int rise;
        ARG(v);
        rise = trig(e, KARPTRIG, i, v);
        p = rise ? 0x7F00 : rd16s(e, KARPPULSZ + 2 * i);
        p = wmul(p, 0x7E00) >> 15;
        wr16(e, KARPPULSZ + 2 * i, p);
        n = lcg(e, KARPNOISZ + 2 * i);
        acc = wadd(acc, wmul(p, n) >> 15);          /* asr 15 in both variants */
    } else {                                        /* comb */
        ARG(v);
        acc = wadd(acc, v);
    }
    return combmeat(e, A, i, acc);
}
/* 0x68-0x6F: zither */
static SHNTH_HOT int32_t h_zither(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3, s, m, k;
    int32_t t, p, n, deno;
    int rise;
    acc = LDH(e, A, ZITHVALES + 2 * i);
    ARG(t);
    acc = 0;
    rise = trig(e, ZITHTRIG, i, t);
    s = rd8(e, ZITHSTRNG + i);
    if (rise) { s = (s + 1) & 3; wr8(e, ZITHSTRNG + i, s); }
    p = rise ? 0x7F00 : rd16s(e, ZITHPULSZ + 2 * i);
    p = wmul(p, 0x7E00) >> 15;
    wr16(e, ZITHPULSZ + 2 * i, p);
    n = lcg(e, KARPNOISZ + 2 * i);                  /* shared with string i */
    acc = wadd(acc, SHR(A, wmul(p, n)));
    m = i + 4 * rd8(e, ZITHSTRNG + i);
    ARG(deno);
    if (rise) wr8(e, ZITHNNNN + m, lsr(ABSV(A, deno), 8));
    for (k = 0; k < 4; k++) {
        uint32_t L = rd8(e, ZITHNNNN + m), q = rd8(e, ZITHPLACZ + m);
        /* "zither frag bug" fix in the asm: byte offset ((m>>2)|((m&3)<<2))*1024 */
        uint32_t base = (((m >> 2) | ((m & 3) << 2)) * 1024u) >> 1;
        int32_t a = DLLD(e, A, base + q), b;
        q++; if ((int32_t)q >= (int32_t)L) q = 0;
        wr8(e, ZITHPLACZ + m, q);
        b = DLLD(e, A, base + q);
        b = SHR(A, wmul(b, 0x7F00));
        b = wadd(b, a) >> 1;
        if (k == 0) { b = wadd(b, acc); acc = 0; }  /* excitation: current string */
        b = SAT(A, b);
        DLST(e, base + q, b);
        acc = wadd(acc, b);
        m = (m + 4) & 15;
    }
    wr16(e, ZITHVALES + 2 * i, acc);
    return muladd(e, A, acc);                       /* acc NOT saturated */
}
/* 0x70-0x77 wave (low pass), 0x7C-0x7F salt (high pass) */
static SHNTH_HOT int32_t h_philt(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3;
    int32_t inn, q, f, hp;
    acc = rd16s(e, PHILTLP + 2 * i);
    ARG(inn); acc = wsub(inn, acc);
    ARG(q);   acc = q_step(e, A, acc, q, PHILTBP + 2 * i);
    hp = acc;
    ARG(f);   acc = f_step(e, A, acc, f, PHILTBP + 2 * i, PHILTLP + 2 * i);
    if ((op & 0xFC) == 0x7C) acc = hp;              /* salt */
    return muladd(e, A, acc);
}
/* 0x78-0x7B: water (4 SVF drops, round robin) */
static SHNTH_HOT int32_t h_water(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3, d, m, k;
    int32_t t, q, r;
    int rise;
    acc = LDH(e, A, WATERVALES + 2 * i);
    ARG(t);
    rise = trig(e, WATERTRIG, i, t);
    d = rd8(e, WATERDROP + i);
    if (rise) { d = (d + 1) & 3; wr8(e, WATERDROP + i, d); }
    acc = rise ? HIGH(A) : 0;
    m = i + 4 * d;
    ARG(q); if (rise) wr16(e, WATERQNQN + 2 * m, q);
    ARG(r); if (rise) wr16(e, WATERQNQN + 32 + 2 * m, r);
    for (k = 0; k < 4; k++) {
        /* waterBP/LP have 12 entries; m = 12..15 IS philtBP/LP[0..3] */
        int32_t x, lp = rd16s(e, WATERLP + 2 * m);
        if (k == 0) { x = wsub(acc, lp); acc = 0; } else x = wneg(lp);
        x = q_step(e, A, x, LDH(e, A, WATERQNQN + 2 * m), WATERBP + 2 * m);
        x = f_step(e, A, x, LDH(e, A, WATERQNQN + 32 + 2 * m), WATERBP + 2 * m, WATERLP + 2 * m);
        acc = wadd(acc, x);
        m = (m + 4) & 15;
    }
    wr16(e, WATERVALES + 2 * i, acc);
    return muladd(e, A, acc);
}
/* 0x80-0x8F: horse (fourses) */
static SHNTH_HOT int32_t h_horse(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3, vo = FOURSESVALE + 2 * i;
    int32_t un, dn, ud, dd;
    int dir;
    acc = LDH(e, A, vo);
    ARG(un); un = ABSV(A, un);
    dir = getbit(e, FOURSGWONZ, i);                 /* read before dn is evaluated */
    if (dir == 1) acc = wadd(acc, un >> 4);
    ARG(dn); dn = ABSV(A, dn);
    if (dir != 1) acc = wsub(acc, dn >> 4);
    ARG(ud); if (acc > ud) { setbit(e, FOURSGWONZ, i, 0); acc = ud; }
    ARG(dd); if (acc < dd) { setbit(e, FOURSGWONZ, i, 1); acc = dd; }
    wr16(e, vo, acc);
    return muladd(e, A, acc);
}
/* 0x90-0x97: slew */
static SHNTH_HOT int32_t h_slew(E *e, uint32_t op, int A, int32_t acc) {
    unsigned vo = SLEWVALE + 2 * (op & 7);
    int32_t wor, up, dn;
    acc = LDH(e, A, vo);
    ARG(wor);
    ARG(up); up = ABSV(A, up);
    if (wor > acc) {
        if (wsub(wor, acc) > lsr(up, 8)) acc = wadd(acc, lsr(up, 8));
        wr16(e, vo, acc);
    }
    ARG(dn); dn = ABSV(A, dn);
    if (acc > wor) {
        if (wsub(acc, wor) > lsr(dn, 8)) acc = wsub(acc, lsr(dn, 8));
        wr16(e, vo, acc);
    }
    return muladd(e, A, acc);
}
/* 0x98-0x9F: wheel (op&3 !) */
static SHNTH_HOT int32_t h_wheel(E *e, uint32_t op, int A, int32_t acc) {
    unsigned vo = WHEELVALE + 4 * (op & 3);
    uint32_t b;
    int32_t v;
    acc = rd32(e, vo);
    b = RD(e); if (!b) return acc >> 16;            /* asr, unsaturated */
    v = (b != 0xFF) ? LIT(A, b) : sexpr(e, acc);
    acc = wadd(acc, usat16(v)); wr32(e, vo, acc);
    b = RD(e); if (!b) return acc >> 16;
    v = (b != 0xFF) ? LIT(A, b) : sexpr(e, acc);
    acc = wsub(acc, usat16(v)); wr32(e, vo, acc);
    return muladd(e, A, acc >> 16);
}
/* 0xA0-0xA7: gear */
static SHNTH_HOT int32_t h_gear(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = GEARVALE + i;
    int32_t t, d;
    acc = lsl(A ? (int32_t)rd8(e, vo) : (int32_t)(int8_t)rd8(e, vo), 8);
    ARG(t);
    if (trig(e, GEARTRIG, i, t)) { acc = wadd(acc, 0x100); wr8(e, vo, acc >> 8); }
    ARG(d); d = ABSV(A, d);
    if (acc >= d) { acc = A ? 1 : wadd(~d, 1); wr8(e, vo, acc >> 8); }
    return muladd(e, A, acc);
}
/* 0xA8-0xAF: pulse */
static SHNTH_HOT int32_t h_pulse(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = PULSEVALE + 2 * i;
    int32_t t, d;
    acc = LDH(e, A, vo);
    ARG(t);
    if (trig(e, PULSETRIG, i, t)) acc = HIGH(A);
    acc = A ? usat16(wsub(acc, 8)) : usat15(wsub(acc, 4));
    wr16(e, vo, acc);
    ARG(d); d = ABSV(A, d);
    if (acc > d) { acc = d; wr16(e, vo, acc); }
    return muladd(e, A, acc);
}
/* 0xB0-0xB7: sauce (decimator) */
static SHNTH_HOT int32_t h_sauce(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = SAUCEVALE + 2 * i;
    int32_t per, pos, inn;
    acc = LDH(e, A, vo);
    ARG(per); per = ABSV(A, per);
    pos = (int32_t)rd8(e, SAUCEPOSZ + i) + 1;
    if (pos > (per >> 8)) {
        wr8(e, SAUCEPOSZ + i, 0); acc = 0;
        ARG(inn); acc = inn; wr16(e, vo, acc);
        return muladd(e, A, acc);
    }
    wr8(e, SAUCEPOSZ + i, pos);
    skip1(e);                                       /* inn not evaluated */
    return muladd(e, A, acc);
}
/* 0xB8-0xBF: salsa (sample & hold) */
static SHNTH_HOT int32_t h_salsa(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = SALSAVALE + 2 * i;
    int32_t t, inn;
    acc = LDH(e, A, vo);
    ARG(t);
    if (trig(e, SALSATRIG, i, t)) {
        acc = 0; ARG(inn); acc = inn; wr16(e, vo, acc);
        return muladd(e, A, acc);
    }
    skip1(e);
    return muladd(e, A, acc);
}
/* 0xC0-0xC3: melody (Shtar word; byte recorder in karp region i) */
static SHNTH_HOT int32_t h_melody(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3;
    uint32_t byte = i * 4096u + (U(rd32(e, MELOPLACZ + 4 * i)) >> 20), si = byte >> 1;
    int32_t gate, inn, nume, skip, w, h, old;
    int punch = 0;
    w = SHNTH_DL_RD(e, si);
    w = (byte & 1) ? ((w >> 8) & 0xFF) : (w & 0xFF);          /* little endian */
    acc = lsl(A ? w : (int32_t)(int8_t)w, 8);
    ARG(gate); if (gate > 0) punch = 1;
    ARG(inn);
    if (punch) {
        int32_t old16 = (uint16_t)SHNTH_DL_RD(e, si), nb = (inn >> 8) & 0xFF;
        acc = inn;
        DLST(e, si, (byte & 1) ? ((old16 & 0x00FF) | (nb << 8)) : ((old16 & 0xFF00) | nb));
    }
    ARG(nume); wr32(e, MELOPLACZ + 4 * i, wadd(rd32(e, MELOPLACZ + 4 * i), nume));
    ARG(skip);
    h = clampi(skip, 0, 1); old = getbit(e, KARPTRIG, i);     /* shared with string */
    setbit(e, KARPTRIG, i, h);
    if ((h ^ old) & old) wr32(e, MELOPULSZ + 4 * i, rd32(e, MELOPLACZ + 4 * i));
    if ((h ^ old) & h)   wr32(e, MELOPLACZ + 4 * i, rd32(e, MELOPULSZ + 4 * i));
    return muladd(e, A, acc);
}
/* 0xC4-0xC7: worm (peak follower) */
static SHNTH_HOT int32_t h_worm(E *e, uint32_t op, int A, int32_t acc) {
    unsigned vo = WORMVALES + 2 * (op & 3);
    int32_t inn;
    acc = LDH(e, A, vo);
    ARG(inn);
    inn = A ? usat16(inn) : ssat16(inn < 0 ? wneg(inn) : inn);
    if (inn > acc) acc = inn;
    if (acc > 0) acc -= 1;
    wr16(e, vo, acc);
    return muladd(e, A, acc);
}
/* 0xC8-0xCB: scale (exponential table) */
static SHNTH_RODATA const uint16_t tarbass_tarball[64] = {
    4444, 4628, 4821, 5022, 5231, 5448, 5675, 5911, 6157, 6414, 6681, 6959,
    7248, 7550, 7864, 8192, 8532, 8888, 9257, 9643, 10044, 10462, 10897, 11351,
    11823, 12315, 12828, 13362, 13918, 14497, 15100, 15729,
    16384, 17065, 17776, 18515, 19286, 20088, 20925, 21795, 22702, 23647, 24631,
    25656, 26724, 27836, 28995, 30201, 31458, 32768, 34131, 35552, 37031, 38572,
    40177, 41850, 43591, 45405, 47295, 49263, 51313, 53449, 55673, 57990 };
static SHNTH_HOT int32_t h_scale(E *e, uint32_t op, int A, int32_t acc) {
    int32_t inn, k;
    (void)op;
    ARG(inn);                                       /* early: SAT(caller's acc) */
    if (!A) { k = clampi(inn >> 9, -64, 63) & ~1;   /* ldrh [tarball + k] */
              acc = tarbass_tarball[32 + k / 2] >> 1; }
    else    { k = clampi(inn >> 10, 0, 63) & ~1;    /* arab reads tarbass */
              acc = tarbass_tarball[k / 2]; }
    return muladd(e, A, acc);
}
/* 0xCC-0xCF: ladder */
static SHNTH_HOT int32_t h_ladder(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3;
    int32_t inn, v, deep = 0;
    uint32_t scan, start, guard = 0;
    acc = LDH(e, A, LADDERVALES + 2 * i);
    ARG(inn);
    scan = U(ABSV(A, inn)) >> (A ? 11 : 10);
    start = e->pc;
    if (scan && PEEK(e) != 0) {
        /* non-empty list: the walk below wraps at the end, so only
           scan mod (number of elements) matters -- count them first so a
           huge unsaturated index does not cost millions of steps */
        int32_t d = 0;
        uint32_t n = 0;
        for (;;) {
            uint32_t b = RD(e);
            if (b == 0) d--;
            if (b == 0xFF) d++;
            if (d < 0) break;
            if (d == 0) n++;
        }
        e->pc = start;
        scan %= n;
    }
    /* literal firmware walk.  With an EMPTY list the firmware runs on
       through the following bytecode (depth goes negative) and lands on
       some later element -- reproduced as is; only a walk that would leave
       the image (firmware: into zeros / code) is cut short. */
    while (scan != 0) {
        uint32_t b = RD(e);
        if (b == 0) deep--;
        if (b == 0xFF) deep++;
        if (deep == 0) { scan--; if (PEEK(e) == 0) e->pc = start; }
        if (e->pc >= e->len || ++guard > 0x100000u) { e->pc = start; break; }
    }
    ARG(v);
    acc = v; wr16(e, LADDERVALES + 2 * i, v);
    skip_to_end(e);
    return acc;
}
/* 0xD0-0xD7: rungler (8-bit shift register, no compiler word) */
static SHNTH_HOT int32_t h_rungler(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 7, vo = RUNGLERVALES + i;
    int32_t t, x;
    int rise;
    acc = lsl(A ? (int32_t)rd8(e, vo) : (int32_t)(int8_t)rd8(e, vo), 8);
    ARG(t);
    rise = trig(e, RUNGLERTRIG, i, t);
    ARG(x);
    x = clampi(lsl(x, 8), 0, 511);                  /* usat #9, lsl 8 */
    if (rise) {
        x ^= lsr(acc & 0x8000, 7);
        acc = x | lsl(acc, 1);
        wr8(e, vo, lsr(acc, 8));
    }
    return muladd(e, A, acc);
}
/* 0xE0-0xE3: press (compressor); also reached by 0xD8-0xDF (dirac) */
static SHNTH_HOT int32_t h_press(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3, so = COMPRSWANG + 4 * i;
    int32_t att, dec, thr, env, mag;
    acc = LDH(e, A, COMPRVALE + 2 * i);             /* never written: 0 */
    ARG(att); acc = att;                            /* (this is `inn`) */
    ARG(att);
    /* dirac RECTA wor,ret only writes when ret<0: otherwise lispWOR still
       holds &comprVALE = 0x20004338 -> attack step 0x20004338<<4 = 0x43380 */
    att = A ? usat16(att) : (att < 0 ? wneg(att) : COMPRVALE_ADDR);
    ARG(dec); dec = ABSV(A, dec);
    env = rd32(e, so);
    /* dirac RECTA r6,acc: for inn >= 0 r6 keeps whatever the previous code
       left there.  In the only known patch using press (MatthewAshmore) r6
       is then 0 or -1, both of which mean "no attack"; we use 0.  So dirac
       press only attacks on negative input peaks, like the hardware. */
    mag = A ? usat16(acc) : (acc < 0 ? wneg(acc) : 0);
#ifdef SHNTH_TRACE_PRESS
    if (!A && acc >= 0) SHNTH_TRACE_PRESS(e);
#endif
    if (mag > (env >> 16)) env = wadd(env, lsl(att, 4)); else env = wsub(env, dec);
    if (env < 0) env = 0;
    wr32(e, so, env);
    ARG(thr);
    acc = SAT(A, SHR(A, wmul(acc, wsub(thr, env >> 16))));
    return muladd(e, A, acc);
}
/* 0xE4-0xE7: leak (DC blocker) */
static SHNTH_HOT int32_t h_leak(E *e, uint32_t op, int A, int32_t acc) {
    unsigned i = op & 3, so = LIKDCSWANG + 4 * i;
    int32_t nu, hi, f, dc;
    uint32_t k, F;
    acc = LDH(e, A, LIKDCVALE + 2 * i);             /* never written: 0 */
    ARG(nu); acc = nu;
    ARG(nu);
    k = U(ABSV(A, nu)) >> 8;
    F = k << 16;
    if (!A) {
        int32_t T = (int32_t)(0x80000000u - F);
        hi = (int32_t)(((int64_t)rd32(e, so) * (int64_t)T) >> 32);       /* smull */
    } else {
        uint32_t T = 0u - F;
        hi = (int32_t)(((uint64_t)U(rd32(e, so)) * (uint64_t)T) >> 32); /* umull */
    }
    f = wadd(wmul(acc, (int32_t)k), hi);
    wr32(e, so, A ? f : lsl(f, 1));
    dc = SAT(A, SHR(A, f));
    acc = SAT(A, wsub(acc, dc));
    return muladd(e, A, acc);
}
/* 0xE8-0xEF: reflect / return / and / xor */
static SHNTH_HOT int32_t h_shaper(E *e, uint32_t op, int A, int32_t acc) {
    int32_t inn, oth, r, q, t;
    ARG(inn);                                       /* early: SAT(caller's acc) */
    acc = inn;
    ARG(oth);
    switch (op & 3) {
    case 0:                                         /* reflect */
        r = ABSV(A, oth);
        if (!A) {
            q = sdiv(acc, r);
            if (q == 0) { acc = wsub(acc, wmul(sdiv(acc, ABSV(A, r)), ABSV(A, r))); break; }
            if (q < 0) t = wmul(wsub(q, 1), r);
            else { q = wadd(q, 1); t = wmul(q, r); }
            acc = (q & 2) ? wsub(t, acc) : wsub(acc, t);
        } else {
            q = udiv(acc, r); t = wmul(q, r);
            acc = (q & 1) ? wsub(t, acc) : wsub(acc, t);
        }
        break;
    case 1:                                         /* return (modulo) */
        r = ABSV(A, oth);
        q = A ? udiv(acc, r) : sdiv(acc, r);
        acc = wsub(acc, wmul(q, r));
        break;
    case 2: acc &= oth; break;
    default: acc ^= oth; break;
    }
    return muladd(e, A, acc);
}
/* 0xF0-0xF3: left, right, square/negwon, modo */
static SHNTH_HOT int32_t h_nuts(E *e, uint32_t op, int A, int32_t acc) {
    int32_t v, wor;
    switch (op & 3) {
    case 0:                          /* left -> r11 (the asm swap "reverse RITE LEFT") */
        acc = e->r11;
        for (;;) { ARG(v); e->r11 = wadd(e->r11, v); acc = e->r11; }
    case 1:                          /* right -> r10 */
        acc = e->r10;
        for (;;) { ARG(v); e->r10 = wadd(e->r10, v); acc = e->r10; }
    case 2:                          /* square inn ref ; (negwon) = -256 / 0xFF00 */
        acc = A ? 0xFF00 : -256;
        ARG(wor);
        /* movs wor,ret ; gt -- V is 0 after any POPSEX in practice */
        acc = (wor > 0) ? HIGH(A) : 0;
        ARG(v);
        acc = (wor > v) ? HIGH(A) : 0;
        return muladd(e, A, acc);
    default:                         /* modo */
        acc = 0;
        ARG(v); acc = v;
        ARG(v); acc = wmul(acc, v >> 8);
        return muladd(e, A, acc);
    }
}
/* 0xF4-0xF7: srate, mul, add, tar */
static SHNTH_HOT int32_t h_srate(E *e, uint32_t op, int A, int32_t acc) {
    int32_t v, wor;
    switch (op & 3) {
    case 0: {                        /* srate */
        int b = !getbit(e, JUMPSRATTRIG, 0);
        setbit(e, JUMPSRATTRIG, 0, b);
        acc = lsl(b, A ? 16 : 15);
        wor = 0;
        for (;;) {
            int64_t s;
            ARG(v);
            s = (int64_t)wor + v;
            wor = wadd(wor, v);
            if (s <= 0) wor = wsub(1, wor);         /* adds ; rsble wor, wor, 1 */
            /* SYST_RVR is 24 bits; RELOAD 0 would stop the SysTick (device
               freezes) -- we keep 1 instead. */
            e->reload = (U(wor) & 0x00FFFFFFu) ? (U(wor) & 0x00FFFFFFu) : 1u;
        }
    }
    case 1:                          /* mul */
        acc = 0;
        ARG(v); acc = v;
        return muladd(e, A, acc);
    case 2:                          /* add (saturating sum) */
        acc = 0;
        ARG(v); acc = v;
        for (;;) { ARG(v); acc = SAT(A, wadd(acc, v)); }
    default:                         /* tar */
        acc = (e->in_buttons & SHNTH_BTN_TAR) ? HIGH(A) : 0;
        return muladd(e, A, acc);
    }
}
/* 0xF8-0xFB: bend, jump, pan, short */
static SHNTH_HOT int32_t h_bend(E *e, uint32_t op, int A, int32_t acc) {
    int32_t v, w;
    switch (op & 3) {
    case 0:                          /* bend: witch += (int8)(v>>8), every arg */
        for (;;) {
            ARG(v);
            acc = wadd((int32_t)rd8(e, WITCH), (int8_t)(uint8_t)lsr(v, 8));
            wr8(e, WITCH, acc);
        }
    case 1: {                        /* jump */
        int level, old;
        acc = 0;
        while (PEEK(e) != 0) { ARG(v); acc = wadd(acc, v); }
        level = acc != 0;            /* TRIG_IDEE_PRIMITIF: any nonzero */
        old = getbit(e, JUMPSRATTRIG, 1);
        setbit(e, JUMPSRATTRIG, 1, level);
        if (level && !old) {
            acc = wadd((int32_t)rd8(e, WITCH), (int8_t)(uint8_t)lsr(acc, 8));
            if (acc < 0) acc = (int32_t)(e->len > 1 ? e->img[1] : 0);   /* -> vexamt */
            wr8(e, WITCH, acc);
            e->odr = (uint16_t)lsl(acc, 8);         /* LEDs show the preset */
        }
        for (;;) ARG(v);             /* reads the 00 -> SAT(acc) */
    }
    case 2:                          /* pan inn place ... */
        for (;;) {
            ARG(v); acc = v;
            ARG(v);
            w = SHR(A, wmul(acc, usat15(v)));
            e->r10 = wadd(e->r10, w);
            w = SHR(A, wmul(acc, usat15(A ? wsub(0x10000, v) : wneg(v))));
            e->r11 = wadd(e->r11, w);
        }
    default:                         /* short bigg smal [ignored] ... */
        for (;;) {
            ARG(v); acc = v;
            ARG(v); acc = wadd(acc, A ? lsr(v, 8) : (v >> 8));
            ARG(v);
        }
    }
}
/* 0xFC-0xFF: dirac, arab, lights */
static SHNTH_HOT int32_t h_dirac(E *e, uint32_t op, int A, int32_t acc) {
    int32_t v;
    acc = 0;
    if (op & 2) {                    /* lights: sum of args -> GPIOC_ODR */
        for (;;) { ARG(v); acc = wadd(acc, v); e->odr = (uint16_t)acc; }
    }
    for (;;) {                       /* dirac / arab */
        uint32_t b;
        e->sin = (uint8_t)(op & 1);  /* set before EACH argument */
        b = RD(e);
        if (!b) { e->sin = 0; return acc; }          /* raw sum, sin forced 0 */
        v = (b != 0xFF) ? LIT(A, b) : sexpr(e, acc);  /* literal: THIS variant */
        acc = wadd(acc, v);
    }
}

typedef int32_t (*handler_fn)(E *, uint32_t, int, int32_t);
static SHNTH_RODATA const handler_fn slot[64] = {
    h_mic, h_bar, h_button, h_button,               /* 00 */
    h_horn, h_horn, h_saw, h_saw,                   /* 10 */
    h_togo, h_togo, h_toggle, h_toggle,             /* 20 */
    h_swoop, h_swoop, h_mount, h_mount,             /* 30 */
    h_smoke, h_smoke, h_dust, h_dust,               /* 40 */
    h_fog, h_fog, h_fog, h_fog,                     /* 50 */
    h_karp, h_karp, h_zither, h_zither,             /* 60 */
    h_philt, h_philt, h_water, h_philt,             /* 70 */
    h_horse, h_horse, h_horse, h_horse,             /* 80 */
    h_slew, h_slew, h_wheel, h_wheel,               /* 90 */
    h_gear, h_gear, h_pulse, h_pulse,               /* A0 */
    h_sauce, h_sauce, h_salsa, h_salsa,             /* B0 */
    h_melody, h_worm, h_scale, h_ladder,            /* C0 */
    h_rungler, h_rungler, h_press, h_press,         /* D0: D8-DF empty -> dirac press */
    h_press, h_leak, h_shaper, h_shaper,            /* E0 */
    h_nuts, h_srate, h_bend, h_dirac                /* F0 */
};

/* STM32 cycle model (estimate): body cost per 4-opcode slot, excluding the
   argument bytes (CYC_BYTE each) and the dispatch (CYC_EXPR each).  Counted
   from the asm at ~1.2 cycles/instruction (72 MHz, 2 flash wait states). */
#define CYC_ISR  80u
#define CYC_EXPR 40u
#define CYC_BYTE 10u
static SHNTH_RODATA const uint16_t slot_cyc[64] = {
    18, 15, 18, 18,   40, 40, 30, 30,   45, 45, 25, 25,   50, 50, 45, 45,
    20, 20, 30, 30,  420, 420, 420, 420, 75, 75, 260, 260, 50, 50, 230, 50,
    40, 40, 40, 40,   35, 35, 25, 25,   30, 30, 30, 30,   30, 30, 25, 25,
    50, 25, 25, 35,   30, 30, 45 + 1536, 45 + 512, /* D8-DF: slide through 0x800-0x1000 bytes of movs r0,r0 */
    45, 50, 40, 40,   12, 20, 15, 12 };

/* sexpression: called after an FF was consumed */
static SHNTH_HOT int32_t sexpr(E *e, int32_t acc_in) {
    uint32_t b, op;
    int A;
    int32_t r;
    if (e->depth >= SHNTH_MAX_DEPTH) {
        /* deeper than the C stack budget: skip this expression, value 0 */
        int32_t d = 1;
        while (d > 0) { b = RD(e); if (b == 0) d--; else if (b == 0xFF) d++;
                        if (e->pc > e->len) break; }
        return 0;
    }
    e->depth++;
#ifdef SHNTH_TRACE_ENTER
    SHNTH_TRACE_ENTER(e, acc_in);
#endif
    b = RD(e);
    op = (b != 0xFF) ? b : ((U(sexpr(e, acc_in)) >> 8) & 0xFF);   /* computed opcode */
    A = e->sin;                      /* variant fixed at dispatch */
    e->est += CYC_EXPR + slot_cyc[op >> 2];
    if ((op & 0xF8) == 0xD8) A = 0;  /* empty slots slide into the dirac press code */
    r = slot[op >> 2](e, op, A, acc_in);
#ifdef SHNTH_TRACE
    SHNTH_TRACE(e, op, A, r);
#endif
    e->depth--;
    return r;
}

/* ------------------------------------------------------------------ */
/* inputs                                                              */
/* ------------------------------------------------------------------ */
void shnth_control_bars(E *e) {           /* vectorADC.s JADERPHILTE, 2083 Hz */
    int k;
    if (e->cooked) return;
    for (k = 0; k < 4; k++) {
        int32_t x = e->in_bar[k];
        int32_t dz = x - clampi(x, -16, 15);
        wr16(e, BARRES + 2 * k, ssat16((rd16s(e, BARRES + 2 * k) * 14 + lsl(dz, 6)) >> 4));
    }
}
void shnth_control_antennae(E *e) {       /* vectorTimer.s TIMPHILTE, per capture */
    int p;
    if (e->cooked) return;
    for (p = 0; p < 2; p++) {
        int32_t d;
        if (e->in_buttons & SHNTH_BTN_TAR) wr16(e, TARESZ + 2 * p, e->in_corp[p]);
        d = (int32_t)e->in_corp[p] - rd16s(e, TARESZ + 2 * p);
        wr16(e, CHINK + 2 * p, ssat16(wadd(rd16s(e, CHINK + 2 * p), lsl(d, 6)) >> 1));
    }
}
void shnth_set_inputs(E *e, const shnth_inputs *in) {
    int k;
    for (k = 0; k < 4; k++) e->in_bar[k] = in->bar[k];
    e->in_corp[0] = in->corp[0]; e->in_corp[1] = in->corp[1];
    e->in_wind = in->wind;
    e->in_buttons = in->buttons;
    e->cooked = in->cooked ? 1 : 0;
    if (e->cooked) {
        for (k = 0; k < 4; k++) wr16(e, BARRES + 2 * k, in->bar[k]);
        wr16(e, CHINK, in->corp[0]); wr16(e, CHINK + 2, in->corp[1]);
    }
}

/* ------------------------------------------------------------------ */
/* API                                                                 */
/* ------------------------------------------------------------------ */
#define BAR_PERIOD 34560u      /* (1 regular + 4 injected) x 54 ADC clk x 128 */
#define ANT_PERIOD 2621440u    /* 65536 TIM1 ticks x 40 cycles (1.8 MHz)     */

void shnth_init(E *e, int16_t *dl) {
    memset(e, 0, sizeof *e);
    e->dl = dl;
    e->reload = SHNTH_DEFAULT_RELOAD;
    shnth_reset(e);
}
void shnth_reset(E *e) {
    memset(&e->ram, 0, sizeof e->ram);
#ifndef SHNTH_DL_EXTERNAL_CLEAR
    if (e->dl) memset(e->dl, 0, SHNTH_DL_SAMPLES * sizeof(int16_t));
#endif
    e->r10 = e->r11 = 0;
    e->reload = SHNTH_DEFAULT_RELOAD;
    e->cyc_bar = e->cyc_ant = 0;
    e->odr = 0; e->sin = 0; e->depth = 0;
    e->rs_l = e->rs_r = 0; e->rs_left = 0;
}
int shnth_load(E *e, const uint8_t *img, uint32_t len) {
    if (!img || len < 2) { e->img = 0; e->len = 0; return -1; }
    e->img = img; e->len = len;
    return (int)img[1] + 1;
}
void shnth_select(E *e, int preset) { wr8(e, WITCH, preset); }
int  shnth_preset(const E *e) { return e->ram.b[WITCH]; }
int  shnth_preset_count(const E *e) { return e->len > 1 ? e->img[1] + 1 : 0; }
uint8_t shnth_leds(const E *e) { return (uint8_t)(e->odr >> 8); }
uint32_t shnth_period_cycles(const E *e) {
    uint32_t p = e->reload + 1;
    if (e->cpu_model) {
        uint32_t est = e->last_est > 0x3FFFFFu ? 0x3FFFFFu : e->last_est;
        est = est * e->cpu_model / 100u;          /* < 2^32: est < 2^22, pct <= 1000 */
        if (est > p) p *= (est + p - 1) / p;
    }
    return p < e->min_period ? e->min_period : p;
}
uint32_t shnth_est_cycles(const E *e) { return e->last_est; }
void shnth_set_cpu_model(E *e, int percent) {
    e->cpu_model = (uint16_t)(percent < 0 ? 0 : percent > 1000 ? 1000 : percent);
}
uint32_t shnth_rate_hz(const E *e) {
    uint32_t p = shnth_period_cycles(e);
    return (SHNTH_CPU_HZ + p / 2) / p;
}
void shnth_set_max_rate(E *e, uint32_t hz) {
    e->min_period = hz ? (SHNTH_CPU_HZ + hz - 1) / hz : 0;
}

static inline int dac12(int32_t s) { return clampi(s >> 4, -2048, 2047) + 2048; }

SHNTH_HOT void shnth_tick(E *e, int *left, int *right) {
    uint32_t vex, witch, b;
    /* the input interrupts that happened during the last sample period */
    if (!e->manual_control) {
        uint32_t p = shnth_period_cycles(e);
        e->cyc_bar += p; e->cyc_ant += p;
        while (e->cyc_bar >= BAR_PERIOD) { e->cyc_bar -= BAR_PERIOD; shnth_control_bars(e); }
        while (e->cyc_ant >= ANT_PERIOD) {         /* TIM2 and TIM3 IRQ both run it */
            e->cyc_ant -= ANT_PERIOD; shnth_control_antennae(e); shnth_control_antennae(e);
        }
    }
    /* DACKER: previous sample's sums */
    *left = dac12(e->r11);
    *right = dac12(e->r10);
    e->r10 = e->r11 = 0;
    e->reload = SHNTH_DEFAULT_RELOAD;
    e->est = 0; e->nrd = 0;
    if (!e->len) { e->last_est = CYC_ISR; return; }
    /* sexpress.s */
    e->sin = 0; e->depth = 0;
    vex = e->img[1];
    witch = rd8(e, WITCH);
    if (witch > vex) { witch = 0; wr8(e, WITCH, 0); }
    if (witch == 0) e->pc = 2 * vex + 2;
    else e->pc = (2 * witch + 1 < e->len) ? (uint32_t)(e->img[2 * witch] | (e->img[2 * witch + 1] << 8)) : e->len;
    for (;;) {                                      /* overlord */
        b = RD(e);
        if (!b) break;
        if (b == 0xFF) sexpr(e, 0x20000000);        /* r1 = &witch_vectore here */
    }
    e->last_est = CYC_ISR + e->est + CYC_BYTE * e->nrd;
}

SHNTH_HOT void shnth_render(E *e, int16_t *out, int frames, uint32_t host_rate) {
    /* time unit: 1/(72e6*host_rate) s.  engine sample = period*host_rate
       units, host sample = 72e6 units.  Box filter of the ZOH output. */
    const uint64_t H = SHNTH_CPU_HZ;
    int n;
    if (!host_rate) host_rate = 44100;
    for (n = 0; n < frames; n++) {
        uint64_t need = H;
        int64_t sl = 0, sr = 0;
        while (need) {
            uint64_t take;
            if (!e->rs_left) {
                int l, r;
                shnth_tick(e, &l, &r);
                e->rs_l = (l - 2048) * 16; e->rs_r = (r - 2048) * 16;
                e->rs_left = (uint64_t)shnth_period_cycles(e) * host_rate;
            }
            take = e->rs_left < need ? e->rs_left : need;
            sl += (int64_t)e->rs_l * (int64_t)take;
            sr += (int64_t)e->rs_r * (int64_t)take;
            e->rs_left -= take; need -= take;
        }
        out[2 * n]     = (int16_t)clampi((int32_t)(sl / (int64_t)H), -32768, 32767);
        out[2 * n + 1] = (int16_t)clampi((int32_t)(sr / (int64_t)H), -32768, 32767);
    }
}
