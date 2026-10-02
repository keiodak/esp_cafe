# esp_cafe — coco duo (k.odk)

Firmware for the ESP32 in the Ciat-Lonbarde Cafe, and **coco duo**, the iPhone app that plays one or two Cafes
over Bluetooth.

**New here? Start with [SETUP.md](SETUP.md)** (upload over USB once, then the app; updates go over Bluetooth).

| folder | what it is |
|---|---|
| `firmware/esp_cafe_duo` | The firmware (Arduino IDE, ESP32 core 2.0.9, *ESP32 Dev Module*, library *NimBLE-Arduino*) |
| `firmware/cafe_ble` | **A small starting point to build on**: two presets (COCO_MOD, ECHO) and Bluetooth only when BUTTON is held at power-on (otherwise exactly as the original). ~1200 lines; the comments at the top of `cafe_ble.ino` say what is where |
| `ios/coco-duo` | The iPhone app (Xcode 16+, iOS 18+) |
| `web/coco-pc.html` | A Chrome page (Web Bluetooth): connect, log, firmware update over BLE |

**How the Bluetooth was done:** [BLE.md](BLE.md) · **What changed from the original / Apple π:** [CHANGES.md](CHANGES.md)

## Presets

Our own (0–10) and Apple π's (11–35) are all in the firmware; the app's PRESET DESIGN picks up to 11 of them for
the playlist (also the Cafe's BUTTON menu). Ours:

| | |
|---|---|
| COCO_MOD | coco looper · knobs + EARTH / FLIP / SKIP on the Cafe |
| ECHO | four-tap echo · organ on YELLOW · FLIP deeper · SKIP wobble |
| **BLE** | played from the app: **GRAIN · BYTE · DELAY · NOISE · SIDRAX · WAVE · HABIT** |
| RESONATOR | resonator bank |
| FORMANT | vowel filter · EARTH moves the vowel |
| SATURATOR | 8 kinds · BUTTON = next |
| RUNGLER | coco chopped by a shift register · FLIP = clock · SKIP = data |
| SELF_READ | the sound on the tape steers the head |
| **MULTI** | 7 effects · FLIP = next · SKIP = random · EARTH modulates |
| **APP+CAFE** | the phone plays into the Cafe: ARP · PHONE_COCO · BOX · COCO+ · BOUNCE (COCO+ / BOUNCE: the Cafes play an OP-1F over Bluetooth MIDI) |

## Firmware updates over Bluetooth

After one USB upload: *Sketch → Export Compiled Binary*, send `esp_cafe_duo.ino.bin` to the phone, and in the app
*PRESET MANAGER → UPDATE* (A / B / both) — or from `web/coco-pc.html` in Chrome (BLE → update).

Text protocol: Nordic UART Service, one line per command — see the comments at the top of `esp_cafe_duo.ino`.

## Credits

- Original Cafe firmware: Ciat-Lonbarde (Peter Blasser).
- The firmware started from **Apple π** by ieat31415 ([ieat31415/esp_cafe_apple_pi](https://github.com/ieat31415/esp_cafe_apple_pi)),
  trimmed and extended; its presets are in `ieat.h`.
- BLE link, presets and the app: k.odk.
