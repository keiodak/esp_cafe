/*
 * shlisp_compile.c -- library version of the Shbobo shlisp compiler
 * (sorce/shlisp/minilisp.c + situations.h + tokes.c).
 *
 * minilisp.c: "This software is in the public domain." (Rui Ueyama's
 * minilisp, mutated by Shbobo).  Shlisp language/emitter/word table from the
 * Shbobo source code (github pblasser/shbobo), MIT License:
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
 * Changes from the original (output is byte-identical for every program the
 * original compiles without crashing / hanging):
 *  - reads from a string, writes into a caller buffer, no printf / USB;
 *  - error() longjmps back to shlisp_compile instead of exit(1);
 *  - all state in one context, arena allocator freed after each call;
 *  - a few crashes of the original (NULL derefs on malformed input, division
 *    by zero in / % ~, EOF inside a list = endless loop) become errors;
 *  - integer arithmetic wraps instead of being UB; << and >> use the shift
 *    count mod 32 (what the x86 build did);
 *  - rand() is a portable copy of glibc's (TYPE_3 random_r) algorithm;
 *  - recursion depth is bounded (SHLISP_MAX_DEPTH) for small stacks.
 */
#include "shlisp_compile.h"
#include <setjmp.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

#ifndef SHLISP_MALLOC
#include <stdlib.h>
#define SHLISP_MALLOC(n) malloc(n)
#define SHLISP_FREE(p)   free(p)
#endif
#ifndef SHLISP_CHUNK
#define SHLISP_CHUNK 8192
#endif
#ifndef SHLISP_MAX_DEPTH
#define SHLISP_MAX_DEPTH 400
#endif
#define SYMBOL_MAX_LEN 200

enum { TINT = 0, TSYMBOL, TPRIMITIVE, TFUNCTION, TSPECIAL, TENV,
       TFISH, TSOUP, TTANK, TBOAT };
enum { TNIL = 1, TDOT, TCPAREN, TTRUE };

struct Obj;
typedef struct Obj *Primitive(struct Obj *env, struct Obj *args);
typedef struct Obj {
    int type;
    union {
        int value;                                              /* TINT */
        struct { struct Obj *car; struct Obj *cdr; } c;         /* cells */
        char name[1];                                           /* TSYMBOL */
        Primitive *fn;                                          /* TPRIMITIVE */
        struct { struct Obj *params; struct Obj *body; struct Obj *env; } f;
        int subtype;                                            /* TSPECIAL */
        struct { struct Obj *vars; struct Obj *up; } e;         /* TENV */
    } u;
} Obj;
#define Nil 0

typedef struct Chunk { struct Chunk *next; size_t used; } Chunk;

/* ---------------- compile context (was: globals) ---------------- */
static struct {
    const char *src; size_t pos;
    Chunk *chunks; unsigned long arena;
    Obj *Dot, *Cparen, *True, *Symbols;
    int looper, depth;
    jmp_buf jb;
    char *err; int err_max;
    /* situations.h */
    uint8_t *txt; int txt_max;
    unsigned situation_place;          /* unsigned short in the original */
    uint16_t situations_vector[256];
    uint8_t situations_plz;
    /* rand() */
    uint32_t rr[34]; int rf, rb;
} C;
static unsigned long last_arena;

/* ---------------- errors ---------------- */
static void put_err(const char *s) {
    int n = 0;
    if (!C.err || C.err_max <= 0) return;
    while (s[n] && n < C.err_max - 1) { C.err[n] = s[n]; n++; }
    C.err[n] = 0;
}
static void error2(const char *a, const char *b) {
    char buf[300]; size_t la = strlen(a), lb = b ? strlen(b) : 0;
    if (la > 90) la = 90;
    if (lb > 200) lb = 200;
    memcpy(buf, a, la); if (b) memcpy(buf + la, b, lb); buf[la + lb] = 0;
    put_err(buf);
    longjmp(C.jb, 1);
}
static void error(const char *s) { error2(s, 0); }

/* ---------------- arena ---------------- */
#define CHUNK_HDR ((sizeof(Chunk) + 7) & ~(size_t)7)
static void *arena_alloc(size_t n) {
    Chunk *c = C.chunks;
    void *p;
    n = (n + 7) & ~(size_t)7;
    if (n > SHLISP_CHUNK - 32) error("object too large");
    /* objects are sized exactly (like the original's malloc); the last 32
       bytes of a chunk stay unused and zeroed so that the original's
       over-reads of small objects (e.g. list_length on a dotted tail) stay
       inside the block and deterministic */
    if (!c || c->used + n > SHLISP_CHUNK - 32) {
        c = (Chunk *)SHLISP_MALLOC(CHUNK_HDR + SHLISP_CHUNK);
        if (!c) error("out of memory");
        memset(c, 0, CHUNK_HDR + SHLISP_CHUNK);
        c->next = C.chunks; c->used = 0; C.chunks = c;
        C.arena += CHUNK_HDR + SHLISP_CHUNK;
    }
    p = (char *)c + CHUNK_HDR + c->used;
    c->used += n;
    return p;
}
static void arena_free(void) {
    while (C.chunks) { Chunk *n = C.chunks->next; SHLISP_FREE(C.chunks); C.chunks = n; }
}

/* ---------------- glibc rand() (random_r TYPE_3) ---------------- */
static void my_srand(unsigned seed) {
    int i;
    int64_t word;                             /* `long int` in glibc (LP64) */
    uint32_t *r = C.rr;
    if (seed == 0) seed = 1;
    r[0] = seed; word = seed;
    for (i = 1; i < 31; i++) {
        int64_t hi = word / 127773, lo = word % 127773;
        word = 16807 * lo - 2836 * hi;
        if (word < 0) word += 2147483647;
        r[i] = (uint32_t)word;
    }
    C.rf = 3; C.rb = 0;                       /* fptr = &state[SEP=3], rptr = state */
    for (i = 0; i < 310; i++) {               /* discard 10*31 */
        r[C.rf] += r[C.rb];
        if (++C.rf >= 31) C.rf = 0;
        if (++C.rb >= 31) C.rb = 0;
    }
}
static int my_rand(void) {
    uint32_t *r = C.rr, v;
    r[C.rf] += r[C.rb];
    v = r[C.rf] >> 1;
    if (++C.rf >= 31) C.rf = 0;
    if (++C.rb >= 31) C.rb = 0;
    return (int)v;
}

/* ---------------- char input ---------------- */
static int getch(void) {
    unsigned char c = (unsigned char)C.src[C.pos];
    if (!c) return -1;
    C.pos++;
    return c;
}
static int peek(void) { unsigned char c = (unsigned char)C.src[C.pos]; return c ? c : -1; }
static int is_digit(int c) { return c >= '0' && c <= '9'; }
static int is_alpha(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static int is_alnum(int c) { return is_digit(c) || is_alpha(c); }
static int sympars(int c) { return c > 0 && c < 256 && strchr("/~`?,':\"|+=_!@#$%^&*-", c) != 0; }

/* ---------------- situations.h ---------------- */
static void insituate(int byte) {
    if (C.situation_place >= 65536u) error("program too large (64 KiB)");
    if ((int)C.situation_place >= C.txt_max) error("output buffer too small");
    C.txt[C.situation_place++] = (uint8_t)byte;
}
static void situatier(void) {
    if (C.situations_plz > 0)
        C.situations_vector[C.situations_plz] = (uint16_t)C.situation_place;
    C.situations_plz++;
}

/* ---------------- constructors ---------------- */
static Obj *alloc(int type, size_t size) {
    Obj *obj;
    size += offsetof(Obj, u);              /* only what this type uses */
    obj = (Obj *)arena_alloc(size);
    memset(obj, 0, size);
    obj->type = type;
    return obj;
}
static Obj *make_int(int value) { Obj *r = alloc(TINT, sizeof(int)); r->u.value = value; return r; }
static Obj *make_intd(double x) {
    if (x != x) x = 0;
    x = (x >= 0 ? (double)(long long)(x + 0.5) : (double)(long long)(x - 0.5));
    if (x > 2147483647.0) x = 2147483647.0;
    if (x < -2147483648.0) x = -2147483648.0;
    return make_int((int)x);
}
static Obj *make_symbol(const char *name) {
    Obj *sym = alloc(TSYMBOL, strlen(name) + 1);
    strcpy(sym->u.name, name);
    return sym;
}
static Obj *make_primitive(Primitive *fn) { Obj *r = alloc(TPRIMITIVE, sizeof(Primitive *)); r->u.fn = fn; return r; }
static Obj *make_function(Obj *params, Obj *body, Obj *env) {
    Obj *r = alloc(TFUNCTION, sizeof(Obj *) * 3);
    r->u.f.params = params; r->u.f.body = body; r->u.f.env = env;
    return r;
}
static Obj *make_special(int subtype) { Obj *r = alloc(TSPECIAL, sizeof(int)); r->u.subtype = subtype; return r; }
static Obj *make_env(Obj *vars, Obj *up) { Obj *r = alloc(TENV, sizeof(Obj *) * 2); r->u.e.vars = vars; r->u.e.up = up; return r; }
static Obj *cons(int type, Obj *car, Obj *cdr) {
    Obj *cell = alloc(type, sizeof(Obj *) * 2);
    cell->u.c.car = car; cell->u.c.cdr = cdr;
    return cell;
}
static Obj *tank(Obj *car, Obj *cdr) { return cons(TTANK, car, cdr); }
static Obj *acons(Obj *x, Obj *y, Obj *a) { return tank(tank(x, y), a); }

/* ---------------- reader ---------------- */
static Obj *readhui(void);
static void enter(void) { if (++C.depth > SHLISP_MAX_DEPTH) error("nesting too deep"); }
static void leave(void) { C.depth--; }

static void skip_line(void) {
    for (;;) {
        int c = getch();
        if (c == -1 || c == '\n') return;
        if (c == '\r') { if (peek() == '\n') getch(); return; }
    }
}
static Obj *readhui_list(int type) {
    Obj *obj, *head, *tail;
    enter();
    obj = readhui();
    if (obj == 0) error("Unclosed parenthesis");
    if (obj == C.Dot) error("Stray dot");
    if (obj == C.Cparen) { leave(); return cons(type, 0, 0); }
    head = tail = cons(type, obj, 0);
    for (;;) {
        obj = readhui();
        if (obj == C.Cparen) { leave(); return head; }
        if (obj == C.Dot) {
            tail->u.c.cdr = readhui();
            if (readhui() != C.Cparen) error("Closed parenthesis expected after dot");
            leave();
            return head;
        }
        /* the original appends empty cells forever at EOF here */
        if (!obj && !C.looper) error("Unclosed parenthesis");
        if (obj) tail->u.c.cdr = cons(type, obj, 0);
        else tail->u.c.cdr = cons(type, 0, 0);
        tail = tail->u.c.cdr;
    }
}
static Obj *intern(const char *name) {
    Obj *p, *sym;
    for (p = C.Symbols; p; p = p->u.c.cdr)
        if (strcmp(name, p->u.c.car->u.name) == 0) return p->u.c.car;
    sym = make_symbol(name);
    C.Symbols = tank(sym, C.Symbols);
    return sym;
}
static int readhui_number(int val) {
    unsigned v = (unsigned)val;
    while (is_digit(peek())) v = v * 10u + (unsigned)(getch() - '0');
    return (int)v;
}
static Obj *readhui_symbol(char c) {
    char buf[SYMBOL_MAX_LEN + 1];
    int len = 1;
    buf[0] = c;
    while (is_alnum(peek()) || sympars(peek())) {
        if (SYMBOL_MAX_LEN <= len) error("Symbol name too long");
        buf[len++] = (char)getch();
    }
    buf[len] = '\0';
    return intern(buf);
}
static Obj *readhui(void) {
    for (;;) {
        int c = getch();
        if (c == ' ' || c == '\n' || c == '\r' || c == '\t') continue;
        if (c == -1) { C.looper = 0; return 0; }
        if (c == ';') { skip_line(); continue; }
        if (c == '(') return readhui_list(TFISH);
        if (c == '{') return readhui_list(TSOUP);
        if (c == '[') return readhui_list(TTANK);
        if (c == '<') return readhui_list(TBOAT);
        if (c == ')' || c == '}' || c == ']' || c == '>') return C.Cparen;
        if (c == '.') return C.Dot;
        if (is_digit(c)) return make_int(readhui_number(c - '0'));
        if (c == '-') {
            if (is_digit(peek())) return make_int((int)(0u - (unsigned)readhui_number(0)));
            return readhui_symbol((char)c);
        }
        if (is_alpha(c) || sympars(c)) return readhui_symbol((char)c);
        {
            char m[2]; m[0] = (char)c; m[1] = 0;
            error2("Don't know how to handle ", m);
        }
    }
}

/* ---------------- printer = emitter ---------------- */
static Obj *eval(Obj *env, Obj *obj);
static void print(Obj *env, Obj *obj);
static void gutsprinter(Obj *env, Obj *obj) {
    for (;;) {
        if (obj->u.c.car == 0) break;
        print(env, obj->u.c.car);
        if (obj->u.c.cdr == 0) break;
        if (obj->u.c.cdr->type < TFISH) { print(env, obj->u.c.cdr); break; }
        obj = obj->u.c.cdr;
    }
}
static void print(Obj *env, Obj *obj) {
    if (obj == 0) return;                           /* "<>" */
    enter();
    switch (obj->type) {
    case TINT:
        if (obj->u.value == 0) { insituate(0xFF); insituate(0); }
        else if ((obj->u.value & 0xFF) == 0xFF) { insituate(0xFF); insituate(242); insituate(0); }
        else insituate(obj->u.value & 0xFF);
        break;
    case TFISH: insituate(0xFF); gutsprinter(env, obj); insituate(0); break;
    case TSOUP: situatier(); gutsprinter(env, obj); insituate(0); break;
    case TTANK: gutsprinter(env, obj); break;
    case TBOAT: print(env, eval(env, obj)); break;
    case TSYMBOL: print(env, eval(env, obj)); break;
    case TPRIMITIVE: case TFUNCTION: break;         /* text only */
    case TSPECIAL:
        if (obj != C.True) error("Bug: print: Unknown subtype");
        break;
    default: error("Bug: print: Unknown tag type");
    }
    leave();
}

/* ---------------- evaluator ---------------- */
static int list_length(Obj *list) {
    int len = 0;
    for (;;) {
        if (list == 0) return len;
        len++;
        if ((list->u.c.car == 0) && (list->u.c.cdr == 0)) return len;
        if (list->type < TFISH) error("length: cannot handle dotted list");
        list = list->u.c.cdr;
    }
}
static void add_variable(Obj *env, Obj *sym, Obj *val) { env->u.e.vars = acons(sym, val, env->u.e.vars); }
static Obj *push_env(Obj *env, Obj *vars, Obj *values) {
    Obj *map = 0, *p, *q;
    if (list_length(vars) != list_length(values))
        error("Cannot apply function: number of argument does not match");
    if (list_length(vars) == 0) return env;
    for (p = vars, q = values; p != 0; p = p->u.c.cdr, q = q->u.c.cdr) {
        if (p->type < TFISH || !q || q->type < TFISH) error("bad argument list");
        map = acons(p->u.c.car, q->u.c.car, map);
    }
    return make_env(map, env);
}
static Obj *progn(Obj *env, Obj *list) {
    Obj *r = 0, *lp;
    for (lp = list; lp; lp = lp->u.c.cdr) {
        if (lp->type < TFISH) error("bad body");
        r = eval(env, lp->u.c.car);
    }
    return r;
}
static Obj *eval_list(Obj *env, Obj *list) {
    Obj *head = 0, *tail = 0, *lp;
    for (lp = list; lp; lp = lp->u.c.cdr) {
        Obj *tmp;
        if (lp->type < TFISH) error("bad argument list");
        tmp = eval(env, lp->u.c.car);
        if (head == 0) head = tail = cons(list->type, tmp, 0);
        else { tail->u.c.cdr = cons(list->type, tmp, 0); tail = tail->u.c.cdr; }
    }
    return head;
}
static int is_list(Obj *obj) { return obj == 0 || obj->type >= TFISH; }
static Obj *apply(Obj *env, Obj *fn, Obj *args) {
    if (!is_list(args)) error("argument must be a list");
    if (fn->type == TPRIMITIVE) return fn->u.fn(env, args);
    if (fn->type == TFUNCTION) {
        Obj *eargs = eval_list(env, args);
        Obj *newenv = push_env(fn->u.f.env, fn->u.f.params, eargs);
        return progn(newenv, fn->u.f.body);
    }
    error("not supported");
    return 0;
}
static Obj *find(Obj *env, Obj *sym) {
    Obj *p, *cell;
    for (p = env; p; p = p->u.e.up)
        for (cell = p->u.e.vars; cell != Nil; cell = cell->u.c.cdr)
            if (sym == cell->u.c.car->u.c.car) return cell->u.c.car;
    return 0;
}
static Obj *eval(Obj *env, Obj *obj) {
    Obj *r = 0;
    if (obj == 0) return 0;
    enter();
    switch (obj->type) {
    case TINT: case TPRIMITIVE: case TFUNCTION: case TSPECIAL: case TTANK:
    case TFISH: case TSOUP:
        r = obj; break;
    case TSYMBOL: {
        Obj *bind = find(env, obj);
        if (!bind) error2("Undefined symbol: ", obj->u.name);
        r = bind->u.c.cdr; break;
    }
    case TBOAT: {
        Obj *fn = eval(env, obj->u.c.car);
        if (fn == 0) { r = 0; break; }
        if (fn->type != TPRIMITIVE && fn->type != TFUNCTION)
            error("The head of a list must be a function");
        r = apply(env, fn, obj->u.c.cdr); break;
    }
    default: error("Bug: eval: Unknown tag type");
    }
    leave();
    return r;
}

/* ---------------- primitives ---------------- */
static Obj *need_int(Obj *o, const char *what) {
    if (!o || o->type != TINT) error2(what, " takes only numbers");
    return o;
}
#define primmertypes(subn, tipe) \
static Obj *prim_##subn(Obj *env, Obj *list) { \
    Obj *cell; \
    if (list_length(list) != 2) error("Malformed " #subn); \
    cell = eval_list(env, list); \
    if (!cell || !cell->u.c.cdr) error("Malformed " #subn); \
    cell->u.c.cdr = cell->u.c.cdr->u.c.car; \
    cell->type = tipe; \
    return cell; \
}
primmertypes(fish, TFISH)
primmertypes(soup, TSOUP)
primmertypes(tank, TTANK)
primmertypes(boat, TBOAT)

static Obj *prim_car(Obj *env, Obj *list) {
    Obj *args = eval_list(env, list);
    if (!args || !args->u.c.car || args->u.c.car->type < TFISH || args->u.c.cdr) error("Malformed car");
    return args->u.c.car->u.c.car;
}
static Obj *prim_cdr(Obj *env, Obj *list) {
    Obj *args = eval_list(env, list);
    if (!args || !args->u.c.car || args->u.c.car->type < TFISH || args->u.c.cdr) error("Malformed cdr");
    return args->u.c.car->u.c.cdr;
}
static Obj *prim_setcdr(Obj *env, Obj *list) {
    Obj *args = eval_list(env, list);
    if (!args || !args->u.c.car || args->u.c.car->type < TFISH) error("Malformed cdr");
    if (args->u.c.cdr == 0) error("no settable");
    args->u.c.car->u.c.cdr = args->u.c.cdr->u.c.car;
    return 0;
}
static Obj *prim_setcar(Obj *env, Obj *list) {
    Obj *args = eval_list(env, list);
    if (!args || !args->u.c.car || args->u.c.car->type < TFISH) error("Malformed cdr");
    if (args->u.c.cdr == 0) error("no settable");
    args->u.c.car->u.c.car = args->u.c.cdr->u.c.car;
    return 0;
}
static Obj *prim_fun(Obj *env, Obj *list) {
    Obj *p;
    if (!list || list->type != TBOAT || !is_list(list->u.c.car) || !list->u.c.cdr || list->u.c.cdr->type < TFISH)
        error("Malformed lambda");
    for (p = list->u.c.car; p; p = p->u.c.cdr) {
        if (p->u.c.car == 0) break;
        if (p->u.c.car->type != TSYMBOL) error("Parameter must be a symbol");
        if (!is_list(p->u.c.cdr)) error("Parameter list is not a flat list");
    }
    return make_function(list->u.c.car, list->u.c.cdr, env);
}
static Obj *prim_def(Obj *env, Obj *list) {
    Obj *value;
    if (list_length(list) != 2 || !list->u.c.car || list->u.c.car->type != TSYMBOL) error("Malformed setq");
    value = eval(env, list->u.c.cdr->u.c.car);
    add_variable(env, list->u.c.car, value);
    return 0;
}
#define primmermath(subn, summ, EXPR) \
static Obj *prim_##subn(Obj *env, Obj *list) { \
    unsigned sum = (unsigned)(summ); Obj *args; \
    for (args = eval_list(env, list); args; args = args->u.c.cdr) { \
        unsigned v = (unsigned)need_int(args->u.c.car, #subn)->u.value; \
        sum = EXPR; \
    } \
    return make_int((int)sum); \
}
primmermath(and, -1, sum & v)
primmermath(orr, 0, sum | v)
primmermath(xor, 0, sum ^ v)
primmermath(not, -1, sum ^ v)
primmermath(add, 0, sum + v)
primmermath(mul, 1, sum * v)

/* first argument, then fold the rest with op */
#define primmerfold(subn, BODY) \
static Obj *prim_##subn(Obj *env, Obj *list) { \
    int sum = 0, furst = 1; Obj *args; \
    for (args = eval_list(env, list); args; args = args->u.c.cdr) { \
        int v = need_int(args->u.c.car, #subn)->u.value; \
        if (furst) sum = v; else { BODY; } \
        furst = 0; \
    } \
    return make_int(sum); \
}
primmerfold(mod, if (v == 0) error("mod by zero"); sum = (v == -1) ? 0 : sum % v)
primmerfold(minus, sum = (int)((unsigned)sum - (unsigned)v))
primmerfold(divide, if (v == 0) error("divide by zero"); sum = (v == -1) ? (int)(0u - (unsigned)sum) : sum / v)
primmerfold(shill, sum = (int)((unsigned)sum << (v & 31)))
primmerfold(shirr, sum = sum >> (v & 31))

static Obj *prim_euro(Obj *env, Obj *list) {
    Obj *args;
    double a, b, c, d;
    if (list_length(list) != 4) error("Malformed euro");
    args = eval_list(env, list);
    a = need_int(args->u.c.car, "euro")->u.value; args = args->u.c.cdr;
    b = need_int(args->u.c.car, "euro")->u.value; args = args->u.c.cdr;
    c = need_int(args->u.c.car, "euro")->u.value; args = args->u.c.cdr;
    d = need_int(args->u.c.car, "euro")->u.value;
    return make_intd(d * pow(a, (b / c)));
}
static Obj *prim_rand(Obj *env, Obj *list) {
    int sum = my_rand();
    Obj *args;
    for (args = eval_list(env, list); args; args = args->u.c.cdr) {
        int v = need_int(args->u.c.car, "~")->u.value;
        if (v == 0) error("~ by zero");
        sum = (v == -1) ? 0 : sum % v;
    }
    return make_int(sum);
}
static Obj *prim_print(Obj *env, Obj *list) {
    if (!list) error("Malformed $");
    print(env, eval(env, list->u.c.car));
    return 0;
}
static Obj *prim_if(Obj *env, Obj *list) {
    Obj *cond, *els;
    if (list_length(list) < 2) error("Malformed if");
    cond = eval(env, list->u.c.car);
    els = list->u.c.cdr->u.c.cdr;
    if (cond) {
        if ((cond->type == TINT) && (cond->u.value == 0))
            return els == 0 ? 0 : progn(env, els);
        return eval(env, list->u.c.cdr->u.c.car);
    }
    return els == 0 ? 0 : progn(env, els);
}
#define primmercomp(subn, oper) \
static Obj *prim_##subn(Obj *env, Obj *list) { \
    Obj *values, *x, *y; \
    if (list_length(list) != 2) error("Malformed comparison"); \
    values = eval_list(env, list); \
    if (!values || !values->u.c.cdr) error("Malformed comparison"); \
    x = values->u.c.car; y = values->u.c.cdr->u.c.car; \
    if (!x || !y || x->type != TINT || y->type != TINT) error("= only takes numbers"); \
    return x->u.value oper y->u.value ? C.True : 0; \
}
primmercomp(eq, ==)
primmercomp(gt, >)
primmercomp(lt, <)

static Obj *prim_exit(Obj *env, Obj *list) { (void)env; (void)list; C.looper = 0; return 0; }

static void add_primitive(Obj *env, const char *name, Primitive *fn) {
    add_variable(env, intern(name), make_primitive(fn));
}

/* tokes.c (uncommented MEXPTOKE / JEXPTOKE entries, same order) */
static const struct { const char *s; int v, n; } tokes[] = {
    { "wind", 0x01, 1 }, { "finger", 0x01, 1 }, { "corp", 0x02, 2 }, { "plank", 0x02, 2 },
    { "bar", 0x04, 4 }, { "top", 0x04, 1 }, { "bot", 0x05, 1 }, { "heart", 0x06, 1 },
    { "bridge", 0x07, 1 }, { "minor", 0x08, 4 }, { "brass", 0x08, 4 }, { "major", 0x0C, 4 },
    { "steel", 0x0C, 4 }, { "horn", 0x10, 8 }, { "saw", 0x18, 8 }, { "toggle", 0x28, 8 },
    { "togo", 0x20, 8 }, { "swoop", 0x30, 8 }, { "mount", 0x38, 8 }, { "smoke", 0x40, 8 },
    { "dust", 0x48, 8 }, { "fog", 0x50, 4 }, { "haze", 0x58, 4 }, { "swamp", 0x54, 4 },
    { "string", 0x60, 4 }, { "comb", 0x64, 4 }, { "zither", 0x68, 4 }, { "wave", 0x70, 8 },
    { "water", 0x78, 4 }, { "salt", 0x7C, 4 }, { "horse", 0x80, 4 }, { "slew", 0x90, 8 },
    { "wheel", 0x98, 8 }, { "gear", 0xA0, 8 }, { "pulse", 0xA8, 8 }, { "sauce", 0xB0, 8 },
    { "salsa", 0xB8, 8 }, { "melody", 0xC0, 4 }, { "worm", 0xC4, 4 }, { "scale", 0xC8, 4 },
    { "ladder", 0xCC, 4 }, { "press", 0xE0, 4 }, { "leak", 0xE4, 4 }, { "reflect", 0xE8, 1 },
    { "return", 0xE9, 1 }, { "and", 0xEA, 1 }, { "xor", 0xEB, 1 }, { "negwon", 0xF2, 1 },
    { "left", 0xF0, 1 }, { "right", 0xF1, 1 }, { "square", 0xF2, 1 }, { "modo", 0xF3, 1 },
    { "srate", 0xF4, 1 }, { "mul", 0xF5, 1 }, { "add", 0xF6, 1 }, { "tar", 0xF7, 1 },
    { "bend", 0xF8, 1 }, { "jump", 0xF9, 1 }, { "pan", 0xFA, 1 }, { "short", 0xFB, 1 },
    { "dirac", 0xFC, 1 }, { "arab", 0xFD, 1 }, { "lights", 0xFE, 1 },
};
static void define_primitives(Obj *env) {
    unsigned t;
    int i;
    for (t = 0; t < sizeof tokes / sizeof tokes[0]; t++) {
        for (i = 0; i < tokes[t].n; i++) {          /* define_grub: horn, hornb.. */
            char toke[100];
            size_t l = strlen(tokes[t].s);
            memcpy(toke, tokes[t].s, l);
            if (i > 0) toke[l++] = (char)('a' + i);
            toke[l] = 0;
            add_variable(env, intern(toke), make_int(tokes[t].v + i));
        }
    }
    add_primitive(env, "fish", prim_fish);
    add_primitive(env, "soup", prim_soup);
    add_primitive(env, "tank", prim_tank);
    add_primitive(env, "boat", prim_boat);
    add_primitive(env, "\"", prim_car);
    add_primitive(env, "@\"", prim_setcar);
    add_primitive(env, ":", prim_cdr);
    add_primitive(env, "@:", prim_setcdr);
    add_primitive(env, "+", prim_add);
    add_primitive(env, "-", prim_minus);
    add_primitive(env, "/", prim_divide);
    add_primitive(env, "*", prim_mul);
    add_primitive(env, "&", prim_and);
    add_primitive(env, "|", prim_orr);
    add_primitive(env, "^", prim_xor);
    add_primitive(env, "!", prim_not);
    add_primitive(env, "%", prim_mod);
    add_primitive(env, "~", prim_rand);
    add_primitive(env, "@", prim_def);
    add_primitive(env, "#", prim_fun);
    add_primitive(env, "?", prim_if);
    add_primitive(env, "=", prim_eq);
    add_primitive(env, ",", prim_lt);
    add_primitive(env, "'", prim_gt);
    add_primitive(env, "''", prim_shill);
    add_primitive(env, ",,", prim_shirr);
    add_primitive(env, "$", prim_print);
    add_primitive(env, "`", prim_euro);
    add_primitive(env, "exit", prim_exit);
}

/* ---------------- entry ---------------- */
int shlisp_compile_seeded(const char *source, uint8_t *out, int out_max,
                          char *err, int err_max, unsigned seed) {
    volatile int result = -1;
    memset(&C, 0, sizeof C);
    C.src = source ? source : "";
    C.err = err; C.err_max = err_max;
    C.txt = out; C.txt_max = out_max > 0 ? out_max : 0;
    C.looper = 1;
    if (err && err_max > 0) err[0] = 0;
    if (!out) { put_err("no output buffer"); return -1; }
    if (setjmp(C.jb) == 0) {
        Obj *env;
        unsigned i, hdr, total, text;
        C.Dot = make_special(TDOT);
        C.Cparen = make_special(TCPAREN);
        C.True = make_special(TTRUE);
        C.Symbols = 0;
        env = make_env(0, 0);
        add_variable(env, intern("t"), C.True);     /* define_constants */
        my_srand(seed);
        define_primitives(env);
        while (C.looper) {                          /* pooler */
            Obj *expr = readhui();
            if (!expr) continue;
            if (expr == C.Cparen) error("Stray close parenthesis");
            if (expr == C.Dot) error("Stray dot");
            C.depth = 0;
            print(env, eval(env, expr));
        }
        /* situsb() + 16 zero bytes: header first, so move the text up */
        text = C.situation_place;
        hdr = C.situations_plz ? 2u * C.situations_plz : 0u;
        total = hdr + text + 16;
        if ((long)total > (long)out_max) error("output buffer too small");
        memmove(out + hdr, out, text);
        for (i = 0; i < C.situations_plz; i++) {
            if (i == 0) { out[0] = 0; /* mastroBarcode */ out[1] = (uint8_t)(C.situations_plz - 1); }
            else {
                uint16_t v = (uint16_t)(C.situations_vector[i] + ((C.situations_plz - 1) << 1) + 2);
                out[2 * i] = (uint8_t)v; out[2 * i + 1] = (uint8_t)(v >> 8);
            }
        }
        memset(out + hdr + text, 0, 16);
        result = (int)total;
    }
    last_arena = C.arena;
    arena_free();
    return result;
}
int shlisp_compile(const char *source, uint8_t *out, int out_max, char *err, int err_max) {
    return shlisp_compile_seeded(source, out, out_max, err, err_max, 1);
}
unsigned long shlisp_last_arena_bytes(void) { return last_arena; }
