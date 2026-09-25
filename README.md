# esp_cafe (k.odk)

Firmware and apps for the ESP32 in the Ciat-Lonbarde Cafe: presets, a BLE link, and iPhone / Mac control.

### firmware/ (Arduino IDE, board "ESP32 Dev Module")

| folder | what it is |
|---|---|
| `esp_cafe_duo` | **Main one.** Presets: 1 coco · 2 echo · 3 duo. Controlled over BLE by the **coco duo** iPhone app (two Cafes). Needs the library *NimBLE-Arduino*. |
| `esp_cafe_ble` | coco-pc over BLE *and* USB (Mac page / coco-pc iPhone app, with WAV dump). |
| `esp_cafe_apple_pi` | coco-pc over USB serial only (no BLE). |
| `esp_ble_min` | Minimal BLE test (no audio): checks that the phone / Mac side works. |

**duo preset** (one record head, three modes switched from the phone with a ~20 ms crossfade):
- **LOOP**: a separate play head with its own speed inside a loop (fold, bias, overdub, short delay).
- **GRAIN**: smooth (sin²) or struck grains of the tape, on a *score* shared by both Cafes. SEPARATION pulls L and R apart (dice, tempo, pitch, length…). FREEZE holds a moment.
- **BENJOLIN**: two triangle oscillators, a rungler, PWM into a resonant low-pass. The tape/input can feed the filter, and PRINT records the Benjolin onto the tape.
- EARTH (AC-coupled): LOOP = speed FM · GRAIN = where grains come from · BENJOLIN = osc 1 FM.
- Lamp: slow blink = phone not connected · off = recording · on = tape held.

Text protocol (BLE, Nordic UART Service): `P Q H S L J R D X M B G Z W` — see the comments at the top of each `.ino`.

Things learned on the way (see comments in the code):
- The original setup reset timer group 0, which on the ESP32 also stops the system clock (`esp_timer`): BLE advertises but can't connect, and `millis()` stops. The BLE builds only reset SPI3.
- With BLE running there is no single 96 KB block free: the tape is allocated in 64 pieces of 3 KB, and the small buffers live in RTC memory.
- The radio clock was switched off (`DPORT_WIFI_CLK_EN_REG = 0`) in the original setup: removed in the BLE builds.

### web/coco-pc.html
Chrome page (Web Serial / Web Bluetooth): the Cafe's tape as a waveform, loop / jump / speed / REC, save WAV, boot log.

### ios/
- `coco-pc`: one Cafe over BLE (waveform, loop, speed, save & share WAV). SwiftUI, Xcode 16+.
- `coco-duo`: two Cafes, eight XY pads (top = Cafe A, bottom = Cafe B), LOOP / GRAIN / BENJOLIN, WAVE panel with file loading onto the tape, camera mode.

### Credits
- Original Cafe firmware: Ciat-Lonbarde (Peter Blasser).
- The firmware in `firmware/` started from **Apple π** by ieat31415 (alt firmware for the Cafe), trimmed and extended. Its README is kept as `firmware/esp_cafe_apple_pi/README_apple_pi.md`.
- Additions, BLE link, presets and the apps: k.odk.
