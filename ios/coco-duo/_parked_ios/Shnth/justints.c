/*
 * justints.c — JUSTINTS (k.odk): a C port of Peter Blasser's justints (see justints.h).
 *   Copyright (c) 2021 peter blasser — MIT License (github.com/pblasser/shbobo)
 * Names follow the original's classes; each comment says which one a part comes from.
 */
#include "justints.h"
#include <stdlib.h>
#include <string.h>

#define LIM 256                       /* URPRIMLIM */
#define FORI for (int i = 0; i < 4; i++)
#define FORJ for (int j = 0; j < 4; j++)

/* ---------------- PerspexStabile: primes, numbers, the ratio list ---------------- */

static int np;                        /* the primes 2..251, ascending (truthfulprimestring) */
static int pval[64], pw[64];          /* value, weight */
static int lpf[LIM];                  /* the largest prime factor of each Numba (0: none) */
static int gval[LIM];                 /* each Numba's value (gyou[0] is 1) */

typedef struct { int n, d; float v; int prev, next; } rat;   /* RatChord */
static rat *R;
static int nR;
static int quid[LIM * LIM];
static int quad;                      /* quadrangularis: the first 1/1 */
static int built;

static int newrat(int n, int d) {
    int k = nR++;
    R[k].n = gval[n % LIM]; R[k].d = gval[d % LIM];
    R[k].v = (float)R[k].n / (float)R[k].d;
    R[k].prev = R[k].next = -1;
    return k;
}
/* RatChord::insert / ouster (recursion made a loop) */
static void rinsert(int t, int x) {
    for (;;) {
        if (!(R[x].v <= R[t].v)) return;
        int p = R[t].prev;
        if (p >= 0) {
            if (R[x].v <= R[p].v) { t = p; continue; }
            R[x].prev = p; R[p].next = x; R[t].prev = x; R[x].next = t;
        } else { R[t].prev = x; R[x].next = t; }
        return;
    }
}
static void router(int t, int x) {
    for (;;) {
        if (!(R[x].v >= R[t].v)) return;
        int nx = R[t].next;
        if (nx >= 0) {
            if (R[x].v >= R[nx].v) { t = nx; continue; }
            R[x].next = nx; R[nx].prev = x; R[t].next = x; R[x].prev = t;
        } else { R[t].next = x; R[x].prev = t; }
        return;
    }
}

void ji_tables(void) {
    if (built) return;
    /* gimmeTruth(256, 256, 0): primes below 256, weight = how many of 2..255 they divide */
    np = 0;
    for (int t = 2; t < LIM; t++) {
        int prime = 1;
        for (int i = 2; i < t; i++) if (t % i == 0) prime = 0;
        if (prime) {
            int w = 0;
            for (int j = 2; j < LIM; j++) if (j % t == 0) w++;
            pval[np] = t; pw[np] = w; np++;
        }
    }
    /* makeNumbarz: gyou[0] = 1 (no factors); the head of computeMultnas's list is the largest prime */
    gval[0] = 1; lpf[0] = 0;
    for (int i = 1; i < LIM; i++) {
        gval[i] = i;
        int v = i, big = 0;
        for (int k = 0; k < np && v > 1; k++) while (v % pval[k] == 0) { v /= pval[k]; big = pval[k]; }
        lpf[i] = big;
    }
    /* the quadrangularis, built as the original builds it (the order of equal ratios matters) */
    R = (rat *)malloc(sizeof(rat) * (LIM * LIM + 2));
    nR = 0;
    quad = newrat(1, 1);
    int oldP = quad, oldU = quad;
    quid[0] = quid[1] = quad;
    for (int i = 1; i < LIM; i++) {
        int p = newrat(i, 1);
        quid[i * LIM + 1] = quid[i * LIM] = p;
        router(oldP, p);
        oldP = p; oldU = p;
        for (int j = 2; j < LIM; j++) {
            int u = newrat(i, j);
            rinsert(oldU, u);
            oldU = u;
            quid[i * LIM + j] = u;
        }
    }
    built = 1;
}

static int limrap(int x) { x %= LIM; return x < 1 ? 1 : x; }
static int getQuid(int n, int d) { return quid[limrap(n) * LIM + limrap(d)]; }

/* ---------------- one voice: ChubberySituation and its five ---------------- */

typedef struct {
    int present;
    /* Barre */
    int buttes, lastbuttes, focii[2], queenflag, lastqueen;
    /* Chinkwonkanater */
    int radio, stritton, strittle, cinhibit, qlimm;          /* qlimm: index into the primes */
    /* SponGinger */
    int rats[4], dursz[4];
    int qsin, qdex, nacc, dacc;
    int numeM[4], denoM[4], osc[4], hys[4];
    int sbit, gingz, quizno;
    /* RoyalMinister */
    int gw[4];                                               /* gwonsz (drawing) */
    int rminh, sig[4][2], knume[4], kdeno[4], qwrth[4], queenals[4][4], kingals[4][4];
    /* RoyalFMoutarde */
    int finh, fbit, barres[4], fore, oldfore, oldbarres[4], numals[4][4], denals[4][4];
    int gsz[4][2], stereo[2], ginging[4];
} voice;

static void voice_init(voice *c) {
    memset(c, 0, sizeof *c);
    c->present = 1;
    c->strittle = 128;                                       /* Chinkwonkanater::init */
    c->qlimm = 0;
    c->rats[0] = quad;                                       /* SponGinger::init */
    c->rats[1] = R[c->rats[0]].prev;
    c->rats[2] = R[c->rats[1]].prev;
    c->rats[3] = R[c->rats[2]].prev;
    FORI { c->hys[i] = 1; c->dursz[i] = c->rats[i]; }
    c->rminh = 1;                                            /* RoyalMinister::init */
    c->finh = 1;                                             /* RoyalFMoutarde */
}
/* the copy constructors (command-d) */
static void voice_dupe(voice *c, const voice *k) {
    voice_init(c);
    c->focii[0] = k->focii[0]; c->focii[1] = k->focii[1];
    c->cinhibit = k->cinhibit; c->stritton = k->stritton; c->strittle = k->strittle; c->qlimm = k->qlimm;
    FORI c->rats[i] = k->rats[i];
    c->gingz = k->gingz; c->quizno = k->quizno; c->sbit = k->sbit;
    c->rminh = k->rminh;
    FORI FORJ { c->queenals[i][j] = k->queenals[i][j]; c->kingals[i][j] = k->kingals[i][j]; }
    c->finh = k->finh; c->fbit = k->fbit;
    FORI FORJ { c->numals[i][j] = k->numals[i][j]; c->denals[i][j] = k->denals[i][j]; }
}

/* Barre */
static int isKing(const voice *c) { return c->focii[0] != 0; }
static int isQueen(const voice *c) { return (c->focii[0] != 0) & (c->focii[1] != 0); }
static int f1(const voice *c) { return c->focii[0] - 1; }
static int f2(const voice *c) { return c->focii[1] - 1; }
static void but(voice *c, unsigned char b) {
    c->lastbuttes = c->buttes;
    c->buttes = b;
    c->lastqueen = isQueen(c);
    for (int i = 0; i < 4; i++) {
        if ((!((c->lastbuttes >> (i << 1)) & 1)) & ((c->buttes >> (i << 1)) & 1)) {
            if (c->focii[0] == i + 1) { c->focii[0] = c->focii[1]; c->focii[1] = 0; }
            else if (c->focii[1] == i + 1) c->focii[1] = 0;
            else { c->focii[1] = c->focii[0]; c->focii[0] = i + 1; }
            if (isQueen(c) & (c->focii[0] > c->focii[1])) { int s = c->focii[1]; c->focii[1] = c->focii[0]; c->focii[0] = s; }
        }
    }
    if (isQueen(c) > c->lastqueen) c->queenflag = 1;
}

/* Chinkwonkanater */
static int primeLimitRadio(int radio) {
    int k = 0, acc = pw[0];
    while (acc < ((radio << 2) + LIM)) {
        acc += pw[k];
        if (k + 1 < np) k++;
    }
    return k;
}
static int primeLimitAt(int p) {
    int k = 0;
    while (p > pval[k]) { if (k + 1 < np) k++; else break; }
    return k;
}
static void chink(voice *c, signed char b) {
    c->radio = b;
    if (!c->cinhibit) c->qlimm = primeLimitRadio(c->radio);
}
#define TING(c) ((c)->stritton == 8 ? 0 : ((c)->radio >> (c)->stritton))
static int getStrittle(voice *c) {
    int cx = TING(c) + c->strittle;
    if (cx < 0) c->strittle -= cx;
    return TING(c) + c->strittle;
}
static void changeStrittle(voice *c, int inn) {
    if (inn > c->stritton) c->strittle = getStrittle(c);
    c->stritton = inn;
}
static int checkN(const voice *c, int idx) { int l = lpf[idx]; return l == 0 || l <= pval[c->qlimm]; }
static int checkR(const voice *c, int r) {
    int acc = 1;
    if (lpf[R[r].n % LIM]) acc = lpf[R[r].n % LIM] <= pval[c->qlimm];
    if (lpf[R[r].d % LIM]) acc &= lpf[R[r].d % LIM] <= pval[c->qlimm];
    return acc;
}

/* SponGinger */
static void oscirateR(voice *c, int i, int r) {
    c->osc[i] *= R[r].d;
    c->osc[i] /= R[c->rats[i]].d;
    c->rats[i] = r;
}
static void oscirateND(voice *c, int i, int n, int d) {
    c->osc[i] *= d;
    c->osc[i] /= R[c->rats[i]].d;
    oscirateR(c, i, getQuid(n, d));
}
static void durszen(voice *c, int i) { c->dursz[i] = c->rats[i]; }

static int kingalNume(voice *c, int i, int nin) {
    int n = nin >> c->sbit;
    if (n == 0) return 0;
    if (n == -1) return 0;
    int curs = R[c->rats[i]].n, dean = R[c->rats[i]].d;
    int newt = curs + n;
    if (newt <= 0) newt = 1 - newt;
    newt = newt % LIM;
    if (newt > curs) for (; newt > curs; newt--) {
        int k = limrap(newt);
        if (checkN(c, k)) { oscirateND(c, i, gval[k], dean); return 1; }
    }
    if (newt < curs) for (; newt < curs; newt++) {
        int k = limrap(newt);
        if (checkN(c, k)) { oscirateND(c, i, gval[k], dean); return 1; }
    }
    return 0;
}
static int kingalDeno(voice *c, int i, int did) {
    int d = did >> c->sbit;
    if (d == 0) return 0;
    if (d == -1) return 0;
    int curs = R[c->rats[i]].d, dean = R[c->rats[i]].n;
    int newt = curs + d;
    if (newt <= 0) newt = 0 - newt;
    newt = newt % LIM;
    if (newt > curs) for (; newt > curs; newt--) {
        int k = limrap(newt);
        if (checkN(c, k)) { oscirateND(c, i, dean, gval[k]); return 1; }
    }
    if (newt < curs) for (; newt < curs; newt++) {
        int k = limrap(newt);
        if (checkN(c, k)) { oscirateND(c, i, dean, gval[k]); return 1; }
    }
    return 0;
}
static int queenalis(voice *c, int i, int qiq) {
    int q = qiq >> c->sbit;
    if (q == 0) return 0;
    if (q == -1) return 0;
    int curs = c->dursz[i], begg = curs;
    if (curs >= 0) {
        if (q > 0) for (; q > 0; q--) if (R[curs].next >= 0) {
            curs = R[curs].next;
            if (checkR(c, curs)) c->dursz[i] = curs;
        }
        if (q < 0) for (; q < -1; q++) if (R[curs].prev >= 0) {
            curs = R[curs].prev;
            if (checkR(c, curs)) c->dursz[i] = curs;
        }
        if (c->dursz[i] != begg) { oscirateR(c, i, c->dursz[i]); return 1; }
        c->dursz[i] = curs;
        return 1;
    }
    return 1;
}
static void queenSpon(voice *c, const int *b) {
    if (b[0] > 4) c->qsin += b[0];
    if (b[1] > 4) c->qsin -= b[1];
    if (b[2] > 4) c->qdex += b[2];
    if (b[3] > 4) c->qdex -= b[3];
    if (queenalis(c, f1(c), c->qsin >> 6)) c->qsin = 0;
    if (queenalis(c, f2(c), c->qdex >> 6)) c->qdex = 0;
}
static void kingSpon(voice *c, const int *b) {
    if (b[0] > 4) c->nacc += b[0];
    if (b[1] > 4) c->nacc -= b[1];
    if (b[2] > 4) c->dacc += b[2];
    if (b[3] > 4) c->dacc -= b[3];
    if (kingalNume(c, f1(c), c->nacc >> 6)) c->nacc = 0;
    if (kingalDeno(c, f1(c), c->dacc >> 6)) c->dacc = 0;
}
static int sging(voice *c, int i) {
    int height = (c->denoM[i] + R[c->rats[i]].d) << 10;
    if (height < (1 << 10)) height = (1 << 10);
    int height_chub = height << 1;
    int spoddy = (c->numeM[i] + R[c->rats[i]].n) * getStrittle(c);
    if (spoddy < 1) spoddy = 1;
    if (c->hys[i] == 1) c->osc[i] += spoddy;
    else c->osc[i] -= spoddy;
    int differosc = c->osc[i] - height;
    int pluserosc = -(c->osc[i] + height);
    if (c->quizno) {
        c->hys[i] = 1;
        if (differosc >= 0) c->osc[i] = (differosc % height_chub) - height;
    } else {
        if (differosc >= 0) {
            if (1 & (differosc / height_chub)) { c->hys[i] = 1; c->osc[i] = (differosc % height_chub) - height; }
            else { c->hys[i] = -1; c->osc[i] = height - (differosc % height_chub); }
        }
        if (pluserosc >= 0) {
            if (1 & (pluserosc / height_chub)) { c->hys[i] = -1; c->osc[i] = height - (differosc % height_chub); }
            else { c->hys[i] = 1; c->osc[i] = (pluserosc % height_chub) - height; }
        }
    }
    c->numeM[i] = 0;
    c->denoM[i] = 0;
    if (c->gingz) return c->osc[i] / R[c->rats[i]].d;
    return c->hys[i] << 10;
}

/* RoyalMinister */
static void modulate(voice *c, const signed char *b) {
    FORI c->gw[i] = b[i];
    if (!c->rminh) {
        FORI { c->sig[i][0] = (int)b[i] - c->sig[i][1]; c->sig[i][1] = (int)b[i]; }
        FORI FORJ {
            int k = (3 - j + i) % 4;
            if (c->kingals[i][3 - j] > 0) c->knume[i] += c->sig[k][0];
            else if (c->kingals[i][3 - j] < 0) c->kdeno[i] += c->sig[k][0];
            c->qwrth[i] += c->sig[k][0] * c->queenals[i][3 - j];
        }
        for (int i = 0; i < 4; i++) {
            if (kingalNume(c, i, c->knume[i])) { c->knume[i] = 0; durszen(c, i); }
            if (kingalDeno(c, i, c->kdeno[i])) { c->kdeno[i] = 0; durszen(c, i); }
            queenalis(c, i, c->qwrth[i]);
            c->qwrth[i] = 0;
        }
    }
}

/* RoyalFMoutarde */
static void bbarr(voice *c, const signed char *b) {
    c->fore = 0;
    FORI { c->fore += b[i]; c->barres[i] = b[i]; }
    if (isQueen(c)) queenSpon(c, c->barres);
    else if (isKing(c)) kingSpon(c, c->barres);
}
static void beging(voice *c) { c->oldfore = c->fore; FORI c->oldbarres[i] = c->barres[i]; }

#define STEREOGING(barfsplat, out, gingling) \
    { int bf_ = (barfsplat); if (bf_ >= 0) (out)[0] += bf_ * (gingling); else (out)[1] += bf_ * (gingling); }
#define TRINGING(t) (((t) > 3 ? (t) - 3 : 0) + ((t) < -3 ? (t) + 3 : 0))

static int *gingModulate(voice *c, int ii, int len) {
    c->stereo[0] = c->stereo[1] = 0;
    FORI {
        c->ginging[i] = sging(c, i);
        c->gsz[i][0] = c->gsz[i][1] = 0;
        int fb = ((c->barres[i] - c->oldbarres[i]) * ii / len) + c->oldbarres[i];
        STEREOGING(fb, c->gsz[i], c->ginging[i])
    }
    if (!c->finh) {
        FORI FORJ {
            int k = (3 - j + i) % 4;
            if (c->numals[i][3 - j] > 0) c->numeM[i] += c->gsz[k][0] >> (10 + c->fbit);
            else if (c->numals[i][3 - j] < 0) c->numeM[i] += c->gsz[k][1] >> (10 + c->fbit);
            if (c->denals[i][3 - j] > 0) c->denoM[i] += c->gsz[k][0] >> (10 + c->fbit);
            else if (c->denals[i][3 - j] < 0) c->denoM[i] += c->gsz[k][1] >> (10 + c->fbit);
        }
    }
    int ff = ((c->fore - c->oldfore) * ii / len) + c->oldfore;
    int tf = TRINGING(ff);
    if (isQueen(c)) {
        STEREOGING(tf, c->stereo, c->ginging[f1(c)])
        STEREOGING(tf, c->stereo, c->ginging[f2(c)])
    } else if (isKing(c)) {
        STEREOGING(tf, c->stereo, c->ginging[f1(c)])
    } else {
        FORI {
            int fb = ((c->barres[i] - c->oldbarres[i]) * ii / len) + c->oldbarres[i];
            STEREOGING(TRINGING(fb), c->stereo, c->ginging[i])
        }
    }
    return c->stereo;
}

/* ChubberySituation */
static void chubspon(voice *c, const signed char *bb) {
    but(c, (unsigned char)bb[7]);
    if (c->queenflag) { c->queenflag = 0; FORI durszen(c, i); }
    chink(c, bb[4]);
    bbarr(c, bb);
    modulate(c, bb);
}
static void vkey(voice *c, int k) {
    FORI durszen(c, i);
    if (k == 'q') c->finh = !c->finh;
    const char *fm = "wertyuiop";
    for (int s = 0; s < 9; s++) if (k == fm[s]) c->fbit = s;
    if (k == '[') c->gingz = !c->gingz;
    if (k == '\'') c->quizno = !c->quizno;
    const char *sp = "xcvbnm,.";
    for (int s = 0; s < 8; s++) if (k == sp[s]) changeStrittle(c, s + 1);
    if (k == 'a') c->rminh = !c->rminh;
    const char *st = "sdfghjkl;";
    for (int s = 0; s < 9; s++) if (k == st[s]) c->sbit = s;
    if (k == 'z') c->cinhibit = !c->cinhibit;
}

/* ---------------- MultiplexPotentiator: up to 16 voices ---------------- */

typedef struct {
    voice ch[JI_VOICES];
    int amt, offset, one;
    int sterge[2];
} multi;

static void multi_init(multi *m) {
    memset(m, 0, sizeof *m);
    voice_init(&m->ch[0]);
    m->amt = 1;
}
static int chubadd(multi *m) {
    if (++m->amt < 16) {
        voice_init(&m->ch[m->amt - 1]);
        if (m->amt) m->offset %= m->amt;
        return m->amt - 1;
    }
    m->amt = 15;
    return m->amt - 1;
}
static void chubdel(multi *m) {
    if (--m->amt < 0) m->amt = 0;
    else {
        for (int k = m->offset; k < m->amt; k++) m->ch[k] = m->ch[k + 1];
        m->ch[m->amt].present = 0;
    }
    if (m->amt) m->offset %= m->amt;
}
static void chubdupe(multi *m) {
    if (m->amt > 0) {
        if (m->amt++ < 16) {
            int at = m->offset % m->amt;
            voice copy;
            if (m->ch[m->offset].present) voice_dupe(&copy, &m->ch[m->offset]);
            else copy = m->ch[m->offset];
            for (int k = m->amt - 1; k > at + 1; k--) m->ch[k] = m->ch[k - 1];
            m->ch[at + 1] = copy;
        } else m->amt = 16;
    }
}
static void multi_report(multi *m, const signed char *bb) {
    if (m->one) { if (m->ch[m->offset].present) chubspon(&m->ch[m->offset], bb); }
    else for (int i = 0; i < m->amt; i++) if (m->ch[i].present) chubspon(&m->ch[i], bb);
}
static void multi_beging(multi *m) { for (int i = 0; i < m->amt; i++) if (m->ch[i].present) beging(&m->ch[i]); }
static int *multi_ging(multi *m, int ii, int len) {
    m->sterge[0] = m->sterge[1] = 0;
    if (m->one) {
        if (m->ch[m->offset].present) {
            int *a = gingModulate(&m->ch[m->offset], ii, len);
            m->sterge[0] += a[0]; m->sterge[1] += a[1];
        }
    } else for (int i = 0; i < m->amt; i++) if (m->ch[i].present) {
        int *a = gingModulate(&m->ch[i], ii, len);
        m->sterge[0] += a[0]; m->sterge[1] += a[1];
    }
    return m->sterge;
}
static void multi_key(multi *m, int cc) {
    if (cc == '\r') chubadd(m);
    if (cc == ' ') { m->offset++; if (m->amt) m->offset %= m->amt; }
    if (cc == '/') m->one = !m->one;
    if (cc == 127) chubdel(m);
    if (m->one) { if (m->ch[m->offset].present) vkey(&m->ch[m->offset], cc); }
    else for (int i = 0; i < m->amt; i++) if (m->ch[i].present) vkey(&m->ch[i], cc);
}

/* ---------------- tokens (strtok " \n\r", as the original reads a .texte) ---------------- */

typedef struct { char *s; } toks;
static char *tok(toks *t) {
    char *p = t->s;
    if (!p) return 0;
    while (*p == ' ' || *p == '\n' || *p == '\r') p++;
    if (!*p) { t->s = 0; return 0; }
    char *b = p;
    while (*p && *p != ' ' && *p != '\n' && *p != '\r') p++;
    if (*p) { *p = 0; t->s = p + 1; } else t->s = 0;
    return b;
}
static int num(const char *s) { return s ? atoi(s) : 0; }

static char *t_barre(voice *c, toks *t) {
    char *k = tok(t);
    if (k) {
        if (strncmp(k, "atrest", 5) == 0) {}
        else if (strncmp(k, "kingal", 5) == 0) { c->focii[0] = 1 + num(tok(t)); c->focii[1] = 0; }
        else if (strncmp(k, "queenal", 5) == 0) { c->focii[0] = 1 + num(tok(t)); c->focii[1] = 1 + num(tok(t)); }
        else return k;
    }
    return tok(t);
}
static char *t_chink(voice *c, toks *t) {
    char *k = tok(t);
    if (k && strncmp(k, "inhib", 5) == 0) { c->cinhibit = num(tok(t)); k = tok(t); }
    if (k && strncmp(k, "prime", 5) == 0) { c->qlimm = primeLimitAt(num(tok(t))); k = tok(t); }
    if (k && strncmp(k, "stritton", 8) == 0) { c->stritton = num(tok(t)); k = tok(t); }
    if (k && strncmp(k, "strittle", 8) == 0) { c->strittle = num(tok(t)); k = tok(t); }
    return k;
}
static char *t_spong(voice *c, toks *t) {
    char *k = tok(t);
    if (k) FORI if (k && strncmp(k, "rat", 3) == 0) {
        tok(t); tok(t);
        int n = num(tok(t)); tok(t); int d = num(tok(t));
        c->rats[i] = getQuid(n, d);
        k = tok(t);
    }
    if (k && strncmp(k, "bitsh", 5) == 0) { c->sbit = num(tok(t)); k = tok(t); }
    if (k && strncmp(k, "gingz", 5) == 0) { c->gingz = num(tok(t)); k = tok(t); }
    if (k && strncmp(k, "quizno", 6) == 0) { c->quizno = num(tok(t)); k = tok(t); }
    return k;
}
static char *t_matrix(toks *t, char *k, const char *a, const char *b, int A[4][4], int B[4][4], int *inh) {
    if (k && strncmp(k, "inhib", 5) == 0) { *inh = num(tok(t)); k = tok(t); }
    if (k) FORI {
        if (k && strncmp(k, a, 5) == 0) { tok(t); tok(t); FORJ A[i][j] = num(tok(t)); k = tok(t); }
        if (k && strncmp(k, b, 5) == 0) { tok(t); tok(t); FORJ B[i][j] = num(tok(t)); k = tok(t); }
    }
    return k;
}
static char *t_voice(voice *c, toks *t) {
    char *k = tok(t);
    if (k && strncmp(k, "barre", 5) == 0) k = t_barre(c, t);
    if (k && strncmp(k, "chink", 5) == 0) k = t_chink(c, t);
    if (k && strncmp(k, "spong", 5) == 0) k = t_spong(c, t);
    if (k && strncmp(k, "royalmi", 7) == 0) k = t_matrix(t, tok(t), "kingals", "queenals", c->kingals, c->queenals, &c->rminh);
    if (k && strncmp(k, "royalfm", 7) == 0) {
        k = t_matrix(t, tok(t), "numals", "denals", c->numals, c->denals, &c->finh);
        if (k && strncmp(k, "bitsh", 5) == 0) { c->fbit = num(tok(t)); k = tok(t); }
    }
    return k;
}

/* ---------------- LaceyBanks: ten slots ---------------- */

struct ji_engine {
    multi m[JI_SLOTS];
    int sterge[2];
    int og;                            /* offset_ging */
    signed char bb[8];
    int blk, racc;
};

ji_engine *ji_create(void) {
    ji_tables();
    ji_engine *e = (ji_engine *)calloc(1, sizeof(ji_engine));
    for (int i = 0; i < JI_SLOTS; i++) multi_init(&e->m[i]);
    e->sterge[0] = e->sterge[1] = 1;
    return e;
}
void ji_destroy(ji_engine *e) { free(e); }

void ji_key(ji_engine *e, int cc) {
    if (cc >= '0' && cc <= '9') { e->sterge[1] = e->sterge[0]; e->sterge[0] = cc - '0'; }
    multi_key(&e->m[e->sterge[0]], cc);
    if (e->sterge[0] != e->sterge[1]) multi_key(&e->m[e->sterge[1]], cc);
}
void ji_dupe_voice(ji_engine *e) {
    chubdupe(&e->m[e->sterge[0]]);
    if (e->sterge[0] != e->sterge[1]) chubdupe(&e->m[e->sterge[1]]);
}
void ji_dupe_slot(ji_engine *e) {
    multi *from = &e->m[e->sterge[0]], *to = &e->m[(e->sterge[0] + 1) % JI_SLOTS];
    if (to == from) return;
    multi fresh;
    memset(&fresh, 0, sizeof fresh);
    fresh.amt = from->amt;
    for (int k = 0; k < from->amt && k < JI_VOICES; k++)
        if (from->ch[k].present) voice_dupe(&fresh.ch[k], &from->ch[k]);
    *to = fresh;
}
int ji_load(ji_engine *e, const char *text) {
    multi *m = &e->m[e->sterge[0]];
    size_t len = strlen(text);
    char *buf = (char *)malloc(len + 1);
    if (!buf) return 0;
    memcpy(buf, text, len + 1);
    toks t = { buf };
    char *k = tok(&t);
    for (int i = 0; i < 16; i++) chubdel(m);
    for (int i = 0; i < 16; i++) {
        if (k && strncmp(k, "chubby", 6) == 0) {
            tok(&t);
            int at = chubadd(m);
            k = t_voice(&m->ch[at], &t);
        }
    }
    free(buf);
    return m->amt;
}
/* MultiplexPotentiator::textorium_trigger / ChubberySituation::text (a queen is written as one, too) */
#include <stdio.h>
int ji_save(ji_engine *e, char *out, int max) {
    multi *m = &e->m[e->sterge[0]];
    int n = 0;
#define PUT(...) do { if (n < max) { int w_ = snprintf(out + n, (size_t)(max - n), __VA_ARGS__); if (w_ > 0) n += w_; } } while (0)
    for (int k = 0; k < m->amt; k++) {
        voice *c = &m->ch[k];
        if (!c->present) continue;
        PUT("chubby %d\n barre\n", k);
        if (isQueen(c)) PUT("  queenal %d %d\n", f1(c), f2(c));
        else if (isKing(c)) PUT("  kingal %d\n", f1(c));
        else PUT("  atrest\n");
        PUT(" chinkwonkanater\n  inhibit %d\n  primelm %d\n  stritton %d\n  strittle %d\n",
            c->cinhibit, pval[c->qlimm], c->stritton, c->strittle);
        PUT(" sponginger\n");
        FORI PUT("  rat %d = %d / %d\n", i, R[c->rats[i]].n, R[c->rats[i]].d);
        PUT("  bitshift %d\n  gingzgongz %d\n  quiznoquantan %d\n", c->sbit, c->gingz, c->quizno);
        PUT(" royalminister\n  inhibit %d\n", c->rminh);
        FORI {
            PUT("  kingals %d = ", i); FORJ PUT("%d ", c->kingals[i][j]);
            PUT("\n  queenals %d = ", i); FORJ PUT("%d ", c->queenals[i][j]);
            PUT("\n");
        }
        PUT(" royalfmoutarde\n  inhibit %d\n", c->finh);
        FORI {
            PUT("  numals %d = ", i); FORJ PUT("%d ", c->numals[i][j]);
            PUT("\n  denals %d = ", i); FORJ PUT("%d ", c->denals[i][j]);
            PUT("\n");
        }
        PUT("  bitshift %d\n", c->fbit);
    }
#undef PUT
    if (n >= max) n = max - 1;
    if (max > 0) out[n < 0 ? 0 : n] = 0;
    return n;
}

void ji_set_report(ji_engine *e, const int8_t bb[8]) { memcpy(e->bb, bb, 8); }

void ji_render(ji_engine *e, float *l, float *r, int n) {
    for (int s = 0; s < n; s++) {
        e->racc += 1000;                                      /* the Shnth's report, 1000 times a second */
        if (e->racc >= JI_SR) {
            e->racc -= JI_SR;
            multi_report(&e->m[e->sterge[0]], e->bb);
            if (e->sterge[0] != e->sterge[1]) multi_report(&e->m[e->sterge[1]], e->bb);
        }
        e->og = (e->og + 1) % 2;                               /* the two slots, sample by sample */
        int *a = multi_ging(&e->m[e->sterge[e->og]], e->blk, JI_BLOCK);
        float L = (float)a[0] / (256 * 259), Rr = (float)a[1] / (256 * 259);
        l[s] = L > 1 ? 1 : (L < -1 ? -1 : L);
        r[s] = Rr > 1 ? 1 : (Rr < -1 ? -1 : Rr);
        if (++e->blk >= JI_BLOCK) {                           /* the end of a buffer: beging */
            e->blk = 0;
            multi_beging(&e->m[e->sterge[0]]);
            multi_beging(&e->m[e->sterge[1]]);
        }
    }
}

void ji_get_view(ji_engine *e, ji_view *o) {
    multi *m = &e->m[e->sterge[0]];
    memset(o, 0, sizeof *o);
    o->amt = m->amt; o->offset = m->offset; o->one = m->one;
    o->slot = e->sterge[0]; o->slot2 = e->sterge[1];
    for (int k = 0; k < m->amt && k < JI_VOICES; k++) {
        voice *c = &m->ch[k];
        ji_voice_view *v = &o->v[k];
        if (!c->present) continue;
        FORI { v->n[i] = (uint8_t)R[c->rats[i]].n; v->d[i] = (uint8_t)R[c->rats[i]].d; }
        v->king = isKing(c) ? (int8_t)f1(c) : -1;
        v->queen = isQueen(c) ? (int8_t)f2(c) : -1;
        v->prime = (uint8_t)pval[c->qlimm];
        v->fm = !c->finh; v->route = !c->rminh; v->hold = (uint8_t)c->cinhibit;
        v->ramp = (uint8_t)c->gingz; v->saw = (uint8_t)c->quizno;
        v->fmshift = (uint8_t)c->fbit; v->step = (uint8_t)c->sbit; v->speed = (uint8_t)c->stritton;
        v->officio = (uint8_t)(c->radio + 128);
        FORI {
            v->gw[i] = (int8_t)c->gw[i];
            FORJ {
                v->kingals[i][j] = (int8_t)c->kingals[i][j]; v->queenals[i][j] = (int8_t)c->queenals[i][j];
                v->numals[i][j] = (int8_t)c->numals[i][j]; v->denals[i][j] = (int8_t)c->denals[i][j];
            }
        }
    }
}

/* RMLIPPER */
static void lipper(int inn, int *ott) {
    if ((inn > 0) & (*ott > 0)) *ott = 0;
    else if (inn > 0) *ott = 1;
    if ((inn < 0) & (*ott < 0)) *ott = 0;
    else if (inn < 0) *ott = -1;
    if (inn == 0) *ott = 0;
}
void ji_toggle(ji_engine *e, int k, int which, int i, int j) {
    multi *m = &e->m[e->sterge[0]];
    if (k < 0 || k >= m->amt || !m->ch[k].present || i < 0 || i > 3 || j < 0 || j > 3) return;
    voice *c = &m->ch[k];
    switch (which) {
    case 0: lipper(1, &c->kingals[i][j]); break;
    case 1: lipper(1, &c->queenals[i][j]); break;
    case 2: lipper(-1, &c->kingals[i][j]); break;
    case 3: lipper(-1, &c->queenals[i][j]); break;
    case 4: lipper(1, &c->numals[i][j]); break;
    case 5: lipper(-1, &c->numals[i][j]); break;
    case 6: lipper(-1, &c->denals[i][j]); break;
    case 7: lipper(1, &c->denals[i][j]); break;
    }
}
