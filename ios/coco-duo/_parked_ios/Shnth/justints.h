/*
 * justints.h — JUSTINTS (k.odk): Peter Blasser's "justints" (shbobo-main/sorce/justints), the Shnth's
 * integer just-intonation synthesizer, ported from its C++ (LaceyBanks / MultiplexPotentiator /
 * ChubberySituation / Barre / Chinkwonkanater / SponGinger / RoyalMinister / RoyalFMoutarde /
 * PerspexStabile) to plain C, same integer arithmetic, same order. The drawing is left out; the
 * Shnth's USB report (8 signed bytes) comes from the screen instead.
 *
 *   Copyright (c) 2021 peter blasser — MIT License (github.com/pblasser/shbobo, LICENSE)
 *
 * Report (as the Shnth sends it, 1000 times a second):
 *   bb[0..3] bars (signed, 0 at rest, ±127 full) · bb[4] antenna (corp) · bb[5] antenna b · bb[6] mic
 *   bb[7] buttons: bit 2k = minor k, bit 2k+1 = major k  (justints uses the minor ones: king / queen)
 * Sound: 44100 Hz, stereo; the engine's buffer is 512 frames (as on the Mac).
 * Keys (ji_key), as on the computer's keyboard:
 *   0..9 slot (the last two alternate, sample by sample) · '\r' add a voice · ' ' next voice ·
 *   '/' one voice at a time · 127 delete the voice · 'q' FM on/off · w e r t y u i o p FM shift 0..8 ·
 *   'a' routing on/off · s d f g h j k l ; step shift 0..8 · x c v b n m , . antenna→speed 1..8 ·
 *   'z' hold the prime limit · '[' ramp / square · '\'' saw / triangle
 * Not thread-safe: call everything from one thread (the audio one), or lock around it.
 */
#ifndef JUSTINTS_H
#define JUSTINTS_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define JI_SR        44100
#define JI_BLOCK     512
#define JI_VOICES    16
#define JI_SLOTS     10

typedef struct ji_engine ji_engine;

/* build the ratio tables (once; ~1.3 MB) — before ji_create */
void ji_tables(void);
ji_engine *ji_create(void);
void ji_destroy(ji_engine *e);

/* a key, as typed */
void ji_key(ji_engine *e, int c);
/* command-d: copy the voice (after itself) · command-shift-d: copy the slot into the next slot */
void ji_dupe_voice(ji_engine *e);
void ji_dupe_slot(ji_engine *e);
/* a .texte (the voices of a slot) into the slot playing; returns how many voices */
int  ji_load(ji_engine *e, const char *text);
/* the voices of the slot playing, as a .texte (textorium_trigger); returns its length (out: NUL-ended) */
int  ji_save(ji_engine *e, char *out, int max);
/* the latest report (used 1000 times a second while rendering) */
void ji_set_report(ji_engine *e, const int8_t bb[8]);
/* n frames at 44100 Hz, -1..1 */
void ji_render(ji_engine *e, float *l, float *r, int n);

/* a click on a routing square (as the original's mouse): voice, which, i, j
 *   which: 0 kingal + · 1 queenal + · 2 kingal − · 3 queenal − (RoyalMinister)
 *          4 numal + · 5 numal − · 6 denal − · 7 denal + (RoyalFMoutarde)   — toggles, as RMLIPPER */
void ji_toggle(ji_engine *e, int voice, int which, int i, int j);

/* what the screen shows */
typedef struct {
    uint8_t n[4], d[4];          /* the four ratios */
    int8_t  king, queen;         /* the focused oscillators (-1 none) */
    uint8_t prime;               /* the prime limit */
    uint8_t fm, route, hold, ramp, saw; /* on / off */
    uint8_t fmshift, step, speed; /* 0..8 · 0..8 · stritton 0..8 (8 = off) */
    uint8_t officio;             /* the antenna + 128 (how the runes are drawn) */
    int8_t  gw[4];               /* the bars, as last reported (the annex colours) */
    int8_t  kingals[4][4], queenals[4][4], numals[4][4], denals[4][4];   /* the routings */
} ji_voice_view;
typedef struct {
    int amt, offset, one, slot, slot2;
    ji_voice_view v[JI_VOICES];
} ji_view;
void ji_get_view(ji_engine *e, ji_view *out);

#ifdef __cplusplus
}
#endif
#endif
