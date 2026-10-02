# How the Cafe got Bluetooth

The Cafe's firmware (Peter Blasser's, and Apple π after it) owns the ESP32 completely: it programs the I2S, the
SAR ADCs and the timers by register, runs the whole sound in one interrupt, and turns the radio's clocks off. Bluetooth
had to fit around that without changing how the sound is made. This is what it took (`firmware/esp_cafe_duo`; the
details are in the comments next to the code).

## The stack

- **NimBLE-Arduino** (h2zero, tested 2.3.6) on the Arduino ESP32 core **2.0.9**. NimBLE is much smaller than
  Bluedroid; the Cafe is a peripheral only.
- `build_opt.h` trims it further: 2 connections, peripheral only (no central / observer), 1 bond, 4 CCCDs.
- One GATT service, the **Nordic UART Service** (`6E400001-…`): RX (write) for text lines from the phone,
  TX (notify) for the Cafe's replies, and a fourth characteristic `6E400004-…` for firmware updates (binary).
- The Cafe advertises as **Cafe-XXXX** (the last two bytes of its MAC): the service UUID in the advertisement, the
  name in the scan response, every 20–40 ms. After a connection it asks for a 15 ms connection interval and an MTU
  of 247.
- The radio runs on **core 0** (the BLE host task, the esp_timer task); the sound interrupt stays on **core 1**.
  The BLE callbacks only copy bytes into a ring (`ble_rb`, 1 KB); `loop()` takes whole lines out of it and runs them.
  Nothing from the radio side ever touches the sound's state directly.

## What had to change in the hardware setup

- **The radio's clocks stay on.** The original setup writes `DPORT_WIFI_CLK_EN_REG = 0`. With Bluetooth this is
  skipped (`cafe_no_ble` keeps the original behaviour).
- **Only SPI3 is reset**, not timer group 0. Resetting timer group 0 also stops the system clock (`esp_timer`):
  BLE then advertises but cannot connect, and `millis()` stops.
- **The radio is started first**, then the Cafe's own hardware setup — the radio calibrates against a clean ADC.
- **SKIP and FLIP** (GPIO 34 / 35) are given back to the digital side at every start (`rtc_gpio_deinit`): their
  analog setting survives a software restart (an update ends in one) and SKIP went dead.

## EARTH and the ADC

The original reads EARTH through the SAR's DMA pattern table, ADC1 and ADC2 converted together ("double" mode),
every sample. With Bluetooth on, the radio's power detector takes **ADC2** all the time; in double mode every
conversion then stalled and EARTH read 0.

- The pattern table runs **ADC1 only** (single mode).
- **EARTH** (ADC2 channel 0, GPIO 4) is read with the IDF driver, `adc2_get_raw`, from an **esp_timer** callback on
  core 0, **2000 times a second** — fast enough for audio-rate FM. The driver arbitrates with the radio; a reading it
  refuses is skipped (counted on the `H` line). `EARTHREAD` returns the last value, so every preset gets EARTH as
  before.
- (An esp_timer callback, not a task: the esp_timer task is there already, and a task's stack cost heap the radio
  needed.)
- Holding **BUTTON at power-on** starts the Cafe without Bluetooth: the original ADC setup, EARTH read every sample.

## Memory

With the radio running there is no longer one free block for the tape (2 × 96 KB in the original).

- The tape is **128 pieces of 1.5 KB** (1024 samples of 12 bits, packed 2 in 3 bytes), each allocated on its own,
  so it fits into the heap's gaps; the last piece lives in **RTC memory**. `dread` / `dwrite` (in IRAM) find the piece.
- Small buffers (the BLE ring, reply buffers) are in RTC memory too.
- `loop()` runs on a 6 KB stack instead of 8 KB: the 2 KB went back to the heap, which had been a few bytes short.
- IRAM was full: the effect code runs from flash; only what the interrupt calls every sample is `IRAM_ATTR`.

## The protocol

Text lines, one command each, the same set as over USB. Replies go back the way the command came.

| | |
|---|---|
| `P` | HELLO: `HELLO coco-duo <version> <name> ota` (also used to time the link) |
| `Q` · `H` | status · health (heap, MTU, interval, EARTH, ADC registers) |
| `G <id>` | go to a preset of the pool (0–35) |
| `L <ids…>` | the playlist (up to 11 pool ids; also the Cafe's own BUTTON menu), kept in flash |
| `M` `C` `Y` `N` `V` `S` `J` `B` `F` | each preset's / mode's settings, `<id> <0..1000>` |
| `X <v> <preset>` | CHAR, one per preset · `K <bpm×10>` the tempo · `Z` sync |
| `W` · `D` | write samples onto the tape (a file from the phone) · read the tape back |
| `U <size> <crc32>` | start a firmware update |

The app sends only what changed, newest first: a newer value of the same setting replaces one still waiting.
Nobody connected for a second and not advertising → it advertises again; a link the phone has not used for 20 s
is dropped, so a phone that lost the Cafe can find it again without a restart.

## Firmware updates over Bluetooth

`U <size> <crc32>` stops the sound and frees the tape's memory for a 16 KB receive ring. The phone (or the Chrome
page in `web/`) writes the binary to `6E400004-…` in pieces of `[offset, 4 bytes][data]`; `loop()` writes them to
the other app slot (OTA, partition scheme *Default 4MB with spiffs*) and answers `U A <bytes>` every 4 KB. At the
end the CRC is checked and the Cafe restarts into the new firmware; anything wrong (a lost link, a bad CRC) and it
restarts into the old one. The flash count and the build are shown at boot and in the app.
