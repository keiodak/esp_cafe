# esp_cafe (k.odk)

Firmware and apps for the ESP32 in the Ciat-Lonbarde Cafe: presets, a BLE link, and iPhone / Mac control.

**New here? Start with [SETUP.md](SETUP.md)**: install, upload, web page, updates over Bluetooth, iPhone app.

### firmware/ (Arduino IDE, board "ESP32 Dev Module")

| folder | what it is |
|---|---|
| `esp_cafe_duo` | **Main one.** Presets: 1 coco_mod · 2 echo · 3 BLE · 4 resonator · 5 formant · 6 saturator · 7 harmony · 8 rungler · 9 selfread · 10 multi · 11 arp_delay. Controlled over BLE by the **coco duo** iPhone app (two Cafes), firmware updates over BLE too. Needs the library *NimBLE-Arduino*. |
| `esp_cafe_ble` | coco-pc over BLE *and* USB (Mac page / coco-pc iPhone app, with WAV dump). |
| `esp_cafe_apple_pi` | coco-pc over USB serial only (no BLE). |
| `esp_ble_min` | Minimal BLE test (no audio): checks that the phone / Mac side works. |

**BLE preset (3)**, four modes switched from the phone (~6 ms fade):
- **GRAIN**: smooth (sin²) or struck grains of the tape, on a *score* shared by both Cafes. SEPARATION pulls L and R apart. FREEZE holds a moment.
- **COCO**: a play head in a loop at its own speed; EARTH = FM of the speed (slow bends to audio rate), wobble, filter, crush, overdub.
- **DELAY**: stereo / ping-pong (main out = L, ASH = R), on the BPM grid, YELLOW = click, SKIP = tap tempo, FLIP / BUTTON = hold. **LINK**: two Cafes as one delay, ping-pong goes A → B; the time steps along the grid when the clock (pitch) moves.
- **NOISE**: a Ciat-Lonbarde-ish noise machine (nothing recorded): three delay lines in a ring through soft-clip / fold / 1-bit deciders, a shift-register noise source, a gate, a filter bent by the ring. main = L, ASH = R, YELLOW = gate.
- Lamp: slow blink = phone not connected.

**HARMONY (7)**: three-layer harmonic delay — unison, a fifth down, a fifth up (pitch-shifted heads), fed back so the repeats climb and fall in fifths. main = down side, ASH = up side, YELLOW = click, SKIP = tap.

**MULTI (10)**: seven effects in one preset (clean, stereo ping-pong echo, one-shot sampler −1…+2 oct, reverse, glitch with 8 moves, fold + octaver, howling reverb). FLIP = next, SKIP = random (a seed shared by both Cafes), crossfaded, LOCK against fast gates, EARTH modulates each effect.

**ARP_DELAY (11)**: the coco duo app plays a sine arpeggiator (7 patterns, 7 chords) out of the iPhone into the Cafe's input, through MULTI's stereo echo. The tempo goes both ways: the app's BPM to the Cafes, a SKIP tap on a Cafe back to the arpeggio.

**Firmware update over BLE**: after one USB upload, *Sketch > Export Compiled Binary* and send `esp_cafe_duo.ino.bin` from the coco duo app (PRESET MANAGER > UPDATE, A / B / both) or from `web/coco-pc.html` (update button).

Text protocol (BLE, Nordic UART Service): `P Q H R W G M C Y N V K Z U` — see the comments at the top of each `.ino`.

Things learned on the way (see comments in the code):
- The original setup reset timer group 0, which on the ESP32 also stops the system clock (`esp_timer`): BLE advertises but can't connect, and `millis()` stops. The BLE builds only reset SPI3.
- With BLE running there is no single 96 KB block free: the tape is allocated in 64 pieces of 3 KB, and the small buffers live in RTC memory.
- The radio clock was switched off (`DPORT_WIFI_CLK_EN_REG = 0`) in the original setup: removed in the BLE builds.
- With Bluetooth on, the radio's power detector keeps taking the SAR ADC2. The original ADC setup converted ADC1 and ADC2 together (double mode), so every conversion stalled and EARTH read 0. In the end EARTH (ADC2 channel 0, GPIO 4 — GPIO 34 is SKIP) is read in `loop()` one conversion at a time (`adc2_get_raw`, 1000×/s) and `EARTHREAD` returns that value, so every preset gets it with Bluetooth on.

### web/coco-pc.html
Chrome page (Web Serial / Web Bluetooth): the Cafe's tape as a waveform, loop / jump / speed / REC, save WAV, boot log.

### ios/
- `coco-pc`: one Cafe over BLE (waveform, loop, speed, save & share WAV). SwiftUI, Xcode 16+.
- `coco-duo`: two Cafes, HUD look. Eight XY pads for the current preset / mode, PRESET MANAGER (1–10, target A / B / both, BLE mode, tempo, firmware UPDATE), WAVE panel with file loading onto the tape, camera mode.

### Credits
- Original Cafe firmware: Ciat-Lonbarde (Peter Blasser).
- The firmware in `firmware/` started from **Apple π** by ieat31415 (alt firmware for the Cafe), trimmed and extended. Its README is kept as `firmware/esp_cafe_apple_pi/README_apple_pi.md`.
- Additions, BLE link, presets and the apps: k.odk.

## cafe_mono (firmware/cafe_mono)

esp_cafe_duo cut down to four presets, played with the Cafe's own controls: **COCO_MOD**, **ECHO** (echo + the organ on
YELLOW, EARTH FM), **RUNGLER**, **SELF_READ**. No Bluetooth: the radio stays off and EARTH is read every sample, as in
the original firmware (full audio-rate FM on the ECHO organ). Flash it over USB (Partition Scheme: Default).
