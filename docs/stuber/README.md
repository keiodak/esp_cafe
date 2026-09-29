# STUBER / NOBSRINE — set aside (2026-09-29)

Both were tried as BLE modes on the Cafe and taken out. What is here is enough to pick them up again.

## STUBER (Din Datin Dudero Stuber) — last: v4.37 (commit 5b539cb), removed v4.38
- `stuber_engine.h` — the firmware engine as it stood (needs `dchunk[100]` for its state, FOURSES' `TL`/`TC` link tables and `tp_link`; `nb_exp2` is at its top).
- `StuberBoard.swift.txt` — the app's board (jacks patched by shapes / fingers, two big wheels, Q knobs); `NbKnob.swift.txt` — the big knob and slider views.
- `DDD_Charm_PCB.zip` — crucFX's Gerbers of the DDD "Charm" board (2× LM324, 4066, 22K, 1nF ×4, 1N914 ×2, ~6 transistors, 4 touch points, 9 banana holes; left/right symmetric). Not traced yet — likely one of the DDD cores (Stuber's filter pair or Srine's S&H).
- Source for the design: ieat31415's *Stuber Surfing Guide 2.0* (https://indd.adobe.com/view/publication/51b7cbb7-d997-403c-8b4c-b28ffa9a5732/px4y/publication-web-resources/pdf/Stuber_Guide_2.0.pdf).

What the guide says (as used):
- Four identical state-variable filters: B / D process the stereo audio, A / C process the two wooden wheels' gesture CV.
- The big wheels = pitch (cutoff). The small rubber knobs = Q (left inverso, right verso). Self-oscillates at ~75 % with nothing patched.
- 63 sandrodes (32 left, 31 right), androgynous, current-controlled (mido ≈ 4.5 V; verso above, inverso below).
  - LP / BP: B [40] [4], D [35] [45], A [7] [3], C [34] [12]; RES: B [21], D [44], A [1], C [20]
  - cutoff mod verso / inverso: B [11] / [24] [42], D [22] / [19], A [5] / [27], C [49] / [30]
  - Q mod verso / inverso: B [31] / [39], D [38] / [28], A [41] / [25], C [32] / [14]
  - dividers (16 flip-flops a side, slowest → fastest): left (from D) 54 50 46 62 58 60 56 52 48 2 10 8 6 16 36 26; right (from B) 37 51 47 59 55 63 61 57 53 13 15 33 17 43 9 23
  - parasites [29] left, [18] right; [0] reset button; [A] / [B] Sh'mance clocks
- Sh'mance: two 8-bit register sections (clock at [A] / [B], data from the wheels, Rungler-like) switch 16 nodes: [5][11][49][22][27][42][24][30][25][39][14][28][41][31][32][38] → 2^16 states. Unpatch [A]/[B] to lock; reset → base state; random at power.
- Outputs: filtered audio mixed with gesture CV through a stereo VCA.

What went wrong in the tries (user's notes): made-up extras (a VCA on the wheels, ENV / S&H jacks), wrong patch-point count at first, resonance defaults too low to sound. The node model (a current by potential difference, sources routed by the Sh'mance) was never checked against the real thing.

## NOBSRINE — removed v4.33
- `nobsrine_engine_v430.h` (S&H at each turn's start, two triangles per knob) / `nobsrine_engine_v431.h` (one triangle per knob, level = turning speed).
- `NOBSRINE_PCB.zip` — crucFX Gerbers; `nobsrine_netlist_partial.txt` — ICs (TL064 ×4, LM324 ×2, LM386 ×2, 4066), 86 resistors with values, 30 TO-92 (E/B/C, NPN/PNP) traced; caps and the rest paired but untyped.
- What the traced circuit showed: each knob's pot → buffer → 4066 sampling on the two edges of a Schmitt stage (the knob through a capacitor, so each turn's start in either direction samples it); differential pairs (VCAs) with a tail current from the turning; LM324 triangle cores; LM386 per side.
- User's notes on the sound: a plain single tone per side, no chord / FM-bell, no sustain, no attack shaping; the turning acts like an envelope.
