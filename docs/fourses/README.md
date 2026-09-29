# Fourses — reverse-engineered from crucFX's Gerbers (KiCad 5)

Method: copper layers rasterised, connected copper + plated holes = nets; parts found from hole patterns
(DIP rows, TO-92 triplets, 7.62 mm resistor pairs); resistor values read from the silkscreen; pin 1 from the
mask (square pad). TO-92: pin order C-B-E; silkscreen star = PNP, dash = NPN (the only reading under which
the circuit works). Capacitor values are not on the board (guessed in the SPICE file).

## Tarpterge (verified in ngspice: the four oscillators bounce off each other)
Per horse (x4): LM358 (A = buffer of the capacitor, B = comparator), 4066 (4 switches), 13 transistors.
- POS: the timing capacitor (range switch: small cap / film cap / none), buffered by the 358's A.
- Charge: a PNP current mirror switched on by 4066 A; discharge: an NPN mirror switched by 4066 B.
- The currents: two differential pairs (NPN for up, PNP for down) whose tails are exponential current
  sources driven by the pot (470K / 10K divider → ~0.19 V of base swing ≈ ×1000): pot one way = fast up,
  slow down; the other way the opposite; the middle = equal (the asymmetric RATE knob).
  The pairs' bases (both at 4.5 V through 10K) = the RATE ladder touch nodes (100K each): unbalancing
  them moves up and down rates against each other.
- Comparator: + input = the bound (through 10K, a 4066 switch, and 2.2M hysteresis from its output),
  − input = POS. Output high → switches A (charge) and D (upper bound); low → B (discharge) and C (lower
  bound, through an NPN inverter + LED).
- Bounds: each buffer goes through 100K to the next horse's upper-bound switch and through 100K to the
  other's lower-bound switch (a touch node between 100K and 10K). H1's lower bound and H4's upper bound come
  from a fixed divider (the stack's floor and ceiling).
- 11 touch nodes per horse = 44: POS, BUF, PULSE (comparator via capacitor), THR (comparator +),
  GATE (comparator via 100K = switches A/D), NGATE (inverted via 100K = switches B/C), two bound nodes,
  three RATE ladder nodes.
- (H1's GATE → switches A/D trace looks missing on this board; the other three have it.)

## Arpserge
Same horses (4 × 358 + 4066), 11 transistors each, 103 resistors: the pot drives one tail only (a plain
rate, not the asymmetric one). 44 touch nodes.

## Intersexon
4 × LM324 + 2 × 4066 + a power section (regulators, "2073"): 42 touch nodes. Not decoded yet.
