# What changed

From the original Cafe firmware (Peter Blasser, Ciat-Lonbarde) → **Apple π** (ieat31415) → this
(`firmware/esp_cafe_duo`, k.odk). Apple π's presets are kept as they are (`ieat.h`, pool 11–35).

## The ESP32

- **Bluetooth LE** (NimBLE, Nordic UART Service): the Cafe is played and updated from a phone — see [BLE.md](BLE.md)
  for what had to change (radio clocks, timer reset, EARTH on ADC2, memory).
- **Firmware updates over Bluetooth** (OTA, a second app slot), from the app or the Chrome page.
- The tape in 128 pieces (and one in RTC memory) instead of one block; effect code from flash (IRAM was full).
- BUTTON held at power-on: no Bluetooth, the original ADC path.
- A flash counter and the version at boot and in `HELLO`.

## Presets

- **The pool and the playlist:** every preset (ours 0–10, Apple π's 11–35) is in the firmware; the phone chooses up
  to 11 for the playlist (`L`), which is also the Cafe's own BUTTON menu, kept in flash. (The audio stops for the
  moment flash is written.)
- **CHAR**: one extra setting per preset (`X`) — grit, wear, drive, vowel Q …
- New presets of our own:
  - **BLE** — played from the app, in modes switched with a fade: GRAIN (grains on a score shared by two Cafes),
    BYTE (bytebeat), DELAY (stereo / ping-pong, two Cafes as one delay), NOISE (a feedback-ring noise machine),
    SIDRAX (four plates), WAVE (a vector synth on wavetables), HABIT (the phone keeps the last minutes)
  - **MULTI** — seven effects in one (echo, sampler, reverse, glitch, fold + octaver, reverb, Karplus), FLIP = next,
    SKIP = random, crossfaded, EARTH modulates each
  - **APP+CAFE** — the phone plays into the Cafe: ARP (an arpeggiator into a tap delay), PHONE_COCO, BOX
    (a ZEITGEIST / COCO), COCO+ and BOUNCE (the Cafes play an OP-1 field over Bluetooth MIDI through the app)
  - **RUNGLER** (coco chopped by a shift register), **SELF_READ** (the tape steers its own head)
- The two Cafes can be one instrument: tempo (`K`), sync (`Z`), shared scores and seeds.
- ASH can be set from the phone (`F 83`, for the Fourses app's CAFE terminal).

## Hardware behaviour kept

The sound is made as before: one interrupt per sample, the DAC, ASH, YELLOW, the lamp, BUTTON / FLIP / SKIP / EARTH,
the preset menu on the Cafe itself.

## Parked

FOURSES and SHNTH (BLE modes 7 / 8) are out for now: `firmware/_parked_ios`.
