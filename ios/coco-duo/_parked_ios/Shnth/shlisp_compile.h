/*
 * shlisp_compile.h -- the Shbobo "shlisp" compiler (sorce/shlisp/minilisp.c +
 * situations.h + tokes.c) as a host-independent library.  No USB, no stdout.
 *
 * minilisp.c is based on Rui Ueyama's public-domain minilisp; the shlisp
 * language, word table and emitter are from the Shbobo source code
 * (github pblasser/shbobo), MIT License:
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
 * Memory: objects come from an arena of SHLISP_CHUNK-byte blocks obtained
 * with SHLISP_MALLOC / released with SHLISP_FREE (default malloc/free); all
 * of it is released before shlisp_compile returns.  Not thread-safe (one
 * compile at a time per process).  Needs <math.h> pow() for the ` primitive.
 */
#ifndef SHLISP_COMPILE_H
#define SHLISP_COMPILE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Compile shlisp source (NUL-terminated) into an upload image for
   shnth_load(): exactly the bytes the original shlisp sends over USB
   (vector table, soups, 16 trailing zeros).  Returns the image length,
   or -1 on error (message in err, NUL-terminated, truncated to err_max).
   The `~` (random) primitive uses a glibc-compatible rand() seeded with 1,
   i.e. the same numbers as the original built with srand(1). */
int shlisp_compile(const char *source, uint8_t *out, int out_max, char *err, int err_max);

/* same, with an explicit seed for `~` (the original seeds with time(0);
   pass e.g. a clock value here to get its non-deterministic behaviour). */
int shlisp_compile_seeded(const char *source, uint8_t *out, int out_max,
                          char *err, int err_max, unsigned seed);

/* bytes of arena the last compile used (for sizing on small hosts) */
unsigned long shlisp_last_arena_bytes(void);

#ifdef __cplusplus
}
#endif
#endif
