# Setup guide

How to put this firmware on your own Cafe and play it from an iPhone (coco duo).
It takes about 20 minutes the first time. After that, updates go over Bluetooth.

> **Heads-up:** this replaces the firmware on your Cafe's ESP32. You can always go back by uploading the
> original firmware ([pblasser/esp_cafe](https://github.com/pblasser/esp_cafe)) or Apple π
> ([ieat31415/esp_cafe_apple_pi](https://github.com/ieat31415/esp_cafe_apple_pi)) the same way.

---

## 1. What you need

| | |
|---|---|
| Hardware | A Ciat-Lonbarde Cafe / Cafeteria (ESP32 inside) and a USB cable to its ESP32 board |
| Computer | Mac, Windows or Linux with **Arduino IDE 2.x** |
| iPhone | An iPhone (iOS 18+) and a Mac with **Xcode 16+**, for the coco duo app |

---

## 2. Get the code

- **No git:** on the GitHub page, click **Code → Download ZIP**, then unzip it.
- **With git:** `git clone https://github.com/keiodak/esp_cafe.git`

What's in the repository:

| folder | what it is |
|---|---|
| `firmware/esp_cafe_duo` | The firmware: presets, BLE control, firmware updates over BLE |
| `ios/coco-duo` | iPhone app for one or two Cafes (XY pads, preset manager, update) |

---

## 3. Arduino IDE setup (once)

1. **Add the ESP32 boards.** Open *Arduino IDE → Settings (Preferences)*, and under
   **Additional boards manager URLs** add:
   ```
   https://espressif.github.io/arduino-esp32/package_esp32_index.json
   ```
2. Open **Tools → Board → Boards Manager**, search **esp32** (by Espressif Systems) and install
   **version 2.0.9**.
   - The code was tested with **2.0.9**. The 3.x versions changed the low-level APIs this firmware
     uses, and it will probably not compile with them.
3. Open **Tools → Manage Libraries**, search **NimBLE-Arduino** (by h2zero) and install it (tested: **2.3.6**).

---

## 4. Upload the firmware over USB (first time)

1. Open `firmware/esp_cafe_duo/esp_cafe_duo.ino` in Arduino IDE.
   Keep all the files (`.ino`, `setup.h`, `stuff.h`, `synths.h`, **`build_opt.h`**) in the same folder.
   `build_opt.h` trims the Bluetooth library to what the Cafe needs (2 connections, peripheral only) and frees memory.
2. **Tools** menu:
   - **Board:** ESP32 Dev Module
   - **Partition Scheme:** *Default 4MB with spiffs*. The updates over Bluetooth need this: it keeps
     room for a second copy of the firmware. If you don't see this menu, the board isn't *ESP32 Dev
     Module* yet.
   - **Port:** the Cafe's USB port
3. Click **Upload** (→). If it can't connect, hold the ESP32's **BOOT** button while the upload starts.
4. Open **Tools → Serial Monitor** at **115200** baud and reset the Cafe. You should see:
   ```
   [fw] v4.72, flashed 1 times (this build: ...)
   [1b] BLE advertising, name Cafe-XXXX ...
   -> initDEL: Allocating delay buffers...
   ```
   Your Cafe's Bluetooth name is **Cafe-XXXX**; the letters come from its chip, so every Cafe has its own.

---

## 5. Updating the firmware over Bluetooth

After the first USB upload you don't need the cable any more.

1. In Arduino IDE: **Sketch → Export Compiled Binary** (Mac: ⌥⌘S).
   It writes `firmware/esp_cafe_duo/build/esp32.esp32.esp32/esp_cafe_duo.ino.bin`.
   Use this file, **not** `.merged.bin`, `.bootloader.bin` or `.partitions.bin`.
2. Send the `.bin` to the iPhone (AirDrop, Files), then in coco duo: *Preset Manager → UPDATE*, choose A / B / both
   and the file.
3. The sound stops and the lamp flickers while it writes (about 30 s). When it is done the Cafe restarts with the
   new version (shown in the Cafes panel).

- **If it fails** (connection lost, error), nothing breaks. The Cafe restarts with its old firmware, so
  just try again.

---

## 6. The iPhone app (coco duo)

1. Open `ios/coco-duo/CocoDuo.xcodeproj` in Xcode 16+.
2. Click the project → target **CocoDuo** → **Signing & Capabilities**:
   - **Team:** choose your own Apple ID. Add it under *Xcode → Settings → Accounts* if needed. A free
     account works.
   - **Bundle Identifier:** change `com.kodk.cocoduo` to something of your own, e.g. `com.yourname.cocoduo`.
3. Connect your iPhone, select it at the top, click **Run**.
   - First time on the phone: turn on *Settings → Privacy & Security → Developer Mode*, and trust your
     developer profile under *Settings → General → VPN & Device Management*.
   - With a free Apple ID, the app stops opening after 7 days. Run it from Xcode again to renew it.
4. In the app: allow Bluetooth → top-left key (**CAFES**) → assign a Cafe to **A** (and a second one to **B**).

**Main screen:** the top bar is Cafe A and the bottom bar is Cafe B. Between them are 8 XY pads for the
current preset.
- **Tap the middle of a bar** → **Preset Manager**: target (A / B / A+B), the playlist, PRESET DESIGN, BLE mode,
  tempo, firmware update.
- The keys at both ends of the bars change with the mode (hold, link, tap tempo, sync …).
- **WAVE** (top-right) shows the tapes and lets you load an audio file onto the tape.
- **Camera** (bottom-right) makes the pads follow movement in front of the camera.

---

## 7. Presets

See [README.md](README.md#presets). Pick them from the app, or on the Cafe: long-press the button, tap N times,
long-press again. The lamp blinks the number. In the delays, **SKIP = tap tempo**.

---

## 8. Troubleshooting

| what you see | what to do |
|---|---|
| Serial Monitor: `FATAL: Malloc failed`, lamp stays off | Out of memory at boot. Use this repository's latest `esp_cafe_duo`, the ESP32 core 2.0.9, and don't add big buffers. |
| BLE connects, but nothing answers (`mtu 23` in the log) | The Cafe is stuck. Power it off and on, then connect again. |
| *update*: "the Cafe did not answer U" | The Cafe doesn't have a BLE-capable firmware yet, or the Partition Scheme isn't *Default*. Upload once over USB (section 4). |
| After an update the version didn't change | Check the name: you may have connected to the other Cafe. |
| No *Partition Scheme* menu | Choose *Tools → Board → ESP32 Dev Module*. |
| Compile error: `iram0_0_seg overflowed` | The ESP32's fast memory (IRAM) is full. Use the latest `esp_cafe_duo` (its effect code runs from flash), keep *Tools → Core Debug Level* at *None*, and don't add `IRAM_ATTR` to new functions. |

---

## Credits

Original Cafe firmware: Ciat-Lonbarde (Peter Blasser). Based on **Apple π** by ieat31415. BLE link,
presets and apps by k.odk.
