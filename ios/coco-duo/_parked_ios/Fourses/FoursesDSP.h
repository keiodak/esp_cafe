// FoursesDSP.h — the four horses and the two resonant filters, as circuits (k.odk)
//
// The engine runs at four times the host rate and is decimated to it. The app talks to it only through these calls;
// every setter may be called from the main thread while the audio thread renders.

#ifndef FOURSES_DSP_H
#define FOURSES_DSP_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FrEngine FrEngine;

/// node ids the links use (the app's numbering)
///   0…43  TARPTERGE's touch nodes · 200…243 ARPSERGE's (fr_node_role / fr_node_horse say which)
///   46 OUT L · 47 OUT R
///   48…52 fingers (each also through 1M to the body: the mains' hum)
///   INTERSEXON: 300…307 S&H IN · 310…317 S&H GATE · 320…327 S&H OUT · 330…345 current cells (SOURCE, SINK × 8)
///   80 DUB A− · 81 DUB A+ · 82 DUB B− · 83 DUB B+ (the filters' frequency, through 220K onto their pairs)
///   100…115 a shape's own voltage (fr_set_drift), through 33K
///   90 CAFE A · 91 CAFE B (probes, 1M to 0 V: what each is joined to goes to its linked Cafe's ASH)
enum { FR_MAX_LINKS = 512 };

FrEngine *fr_create(double hostRate);
void fr_destroy(FrEngine *e);
void fr_reset(FrEngine *e);

/// renders n frames (mono buffers, not interleaved)
void fr_render(FrEngine *e, float *left, float *right, int n);

/// 0…1: the RATE pots — 0…3 TARPTERGE, 4…7 ARPSERGE (horse 0 at the bottom of each stack)
void fr_set_pot(FrEngine *e, int h, float v);
/// 0 CV · 1 LOW · 2 AUDIO
void fr_set_range(FrEngine *e, int h, int r);
/// 0…1 (0.5: the supply as it is; less: starved; more: fed)
void fr_set_starve(FrEngine *e, float v);
/// the links now: pairs of node ids and a strength 1…1000 (1000 a wire, ~2K; 1 ~10M)
void fr_set_links(FrEngine *e, const int *a, const int *b, const int *v, int n);
/// a shape's own voltage (node 100 + k), volts
void fr_set_drift(FrEngine *e, int k, float volts);
/// the filters at the end: on, frequency A / B (0…1), resonance A / B (0…1, 1 rings by itself)
void fr_set_dub(FrEngine *e, int on, float freqA, float freqB, float resA, float resB);
/// ANALOG: the output as the hardware's — hard, bright highs — its attacks held down by a compressor
void fr_set_danger(FrEngine *e, int on);
/// output level 0…1
void fr_set_level(FrEngine *e, float v);
/// the output held back this long (seconds, ≤ 0.5): CAFE's SYNC, the phone waiting for the Cafe's ASH
void fr_set_out_delay(FrEngine *e, float seconds);

/// how long each horse's output has been high since the last call (0…1), and its LED — eight: TARPTERGE, ARPSERGE
void fr_take_leds(FrEngine *e, float out[8]);
/// each horse's CV (its buffer, the triangle), on average since the last call, 0…1 of its range — the LEDs' colour
void fr_take_cv(FrEngine *e, float out[8]);
/// the output's peak (0…1) since the last call, for the level meter
float fr_take_peak(FrEngine *e);
/// CAFE A / B: the voltage on their terminals (nodes 90, 91) this instant, and its lowest / highest since the last call (volts)
void fr_take_ash(FrEngine *e, float now[2], float lo[2], float hi[2]);
/// the supply now (volts), for the meter
float fr_supply(FrEngine *e);
/// the current each node passes through its links, on average since the last call (amperes)
void fr_take_activity(FrEngine *e, const int *ids, float *out, int n);

/// what a board node is: 0 POS · 1 BUF · 2 PULSE · 3 THR · 4 GATE · 5 NGATE · 6 BOUND UP · 7 BOUND DOWN · 8/9/10 the rate ladder
int fr_node_role(int n);
int fr_node_horse(int n);

#ifdef __cplusplus
}
#endif
#endif
