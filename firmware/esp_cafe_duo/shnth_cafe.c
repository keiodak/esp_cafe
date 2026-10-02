/* shnth_cafe.c — SHNTH on the Cafe (k.odk): the Shbobo Shnth sound engine (a C port of Peter Blasser's firmware,
 * MIT — Copyright (c) 2021 peter blasser, github.com/pblasser/shbobo; bit-exact against the original) built for the
 * Cafe. It runs in loop() (not in the audio interrupt: its nesting needs more stack than an interrupt has) into a
 * ring the audio interrupt plays from. All its memory is borrowed from the tape (BLE mode SHNTH only): the 16 KB delay
 * is 11 of the tape's 1536-byte pieces, read and written through these two macros. */
#include <stdint.h>
int16_t *sh_dl[11];
#define SHNTH_MAX_DEPTH 24
#define SHNTH_DL_RD(e, i)    (sh_dl[(uint32_t)(i) / 768u][(uint32_t)(i) % 768u])
#define SHNTH_DL_WR(e, i, v) (sh_dl[(uint32_t)(i) / 768u][(uint32_t)(i) % 768u] = (int16_t)(v))
#define SHNTH_DL_EXTERNAL_CLEAR
#include "shnth_engine_impl.h"
