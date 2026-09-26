# Setup guide

How to put this firmware on your own Cafe and play it from a computer or an iPhone.
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
| Browser | **Chrome** or **Edge** on a computer (for the web page: Web Bluetooth). Safari and Firefox won't work. |
| Optional | An iPhone (iOS 18+) and a Mac with **Xcode 16+**, for the coco duo app |

---

## 2. Get the code

- **No git:** on the GitHub page, click **Code → Download ZIP**, then unzip it.
- **With git:** `git clone https://github.com/keiodak/esp_cafe.git`

What's in the repository:

| folder | what it is |
|---|---|
| `firmware/esp_cafe_duo` | **The main firmware.** 11 presets, BLE control, firmware updates over BLE |
| `web/coco-pc.html` | Chrome page: connect, check, log, **firmware update over BLE** |
| `ios/coco-duo` | iPhone app for one or two Cafes (XY pads, preset manager, update) |
| other folders | older / test builds (see README) |

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
   --- BOOT START --- (esp_cafe_duo 3.13, last reset reason 1)
   [1b] BLE advertising, name Cafe-XXXX ...
   -> initDEL: Allocating delay buffers...
   ```
   Your Cafe's Bluetooth name is **Cafe-XXXX**; the letters come from its chip, so every Cafe has its own.

---

## 5. The web page (Chrome)

**Open it** in one of two ways:
- **Online:** `https://keiodak.github.io/esp_cafe/web/coco-pc.html` (works once the owner has turned on
  GitHub Pages, see section 9).
- **Local:** double-click `web/coco-pc.html` so it opens in Chrome.

**Allow Bluetooth for the browser:**
- **macOS:** *System Settings → Privacy & Security → Bluetooth* → turn on **Google Chrome**.
- **Windows:** Bluetooth on. Nothing else to do.
- **Linux:** if the BLE button does nothing, open `chrome://flags`, turn on
  *Experimental Web Platform features*, and restart Chrome.

**Use it:**
- **BLE** → choose *Cafe-XXXX*. The page shows `HELLO coco-duo 3.13 Cafe-XXXX ota`.
- **check** → memory, Bluetooth state, packet size (`mtu`).
- **log** → everything the Cafe answered.
- **update** → write a new firmware over Bluetooth (next section).

*(The waveform / loop / speed controls on this page are for the `esp_cafe_ble` firmware. With
`esp_cafe_duo`, use the iPhone app to play.)*

---

## 6. Updating the firmware over Bluetooth

After the first USB upload you don't need the cable any more.

1. In Arduino IDE: **Sketch → Export Compiled Binary** (Mac: ⌥⌘S).
   It writes `firmware/esp_cafe_duo/build/esp32.esp32.esp32/esp_cafe_duo.ino.bin`.
   Use this file, **not** `.merged.bin`, `.bootloader.bin` or `.partitions.bin`.
2. In Chrome: open `coco-pc.html`, press **BLE**, pick the Cafe, then press **update** and choose the `.bin`.
3. The sound stops and the lamp flickers while it writes (about 30 s for 630 KB). When the page says
   **Update done**, the Cafe restarts. Press **BLE** again and check the version in the `HELLO` line.

- **Two Cafes:** open the page in two Chrome *windows* (not tabs) and update both at the same time.
- **If it fails** (connection lost, error), nothing breaks. The Cafe restarts with its old firmware, so
  just try again.
- The iPhone app can do the same: *Preset Manager → UPDATE* (send the `.bin` to the phone with AirDrop first).

---

## 7. The iPhone app (coco duo)

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
- **Tap the middle of a bar** → **Preset Manager**: target (A / B / A+B), presets 1–11, BLE mode, tempo,
  firmware update.
- The keys at both ends of the bars change with the mode (hold, link, tap tempo, sync …).
- **WAVE** (top-right) shows the tapes and lets you load an audio file onto the tape.
- **Camera** (bottom-right) makes the pads follow movement in front of the camera.

---

## 8. Presets

Pick them from the app, or on the Cafe: long-press the button, tap N times, long-press again.
The lamp blinks the number.

| # | name | what it does |
|---|---|---|
| 1 | COCO_MOD | coco looper (start-up preset) |
| 2 | ECHO | four-tap echo, organ on YELLOW |
| 3 | **BLE** | played from the app. Modes: **GRAIN** (granular, shared score for two Cafes; MOVE = Ikue Mori-like pitch) · **COCO** (loop with EARTH FM, wobble, filter, crush) · **DELAY** (stereo / ping-pong, main = L, ASH = R, YELLOW = click; **LINK** turns two Cafes into one delay) · **NOISE** (feedback-ring noise machine) |
| 4 | RESONATOR | resonator bank |
| 5 | FORMANT | vowel filter, EARTH moves the vowel |
| 6 | SATURATOR | 8 kinds of distortion, BUTTON = next |
| 7 | HARMONY | replay in intervals (after norns' rpls): 3 buffers take turns, 2 voices play the last cycles at their own interval and timing |
| 8 | RUNGLER | coco chopped by a shift register (FLIP = clock, SKIP = data) |
| 9 | SELF_READ | the sound on the tape steers the play head |
| 10 | **MULTI** | seven effects — clean · stereo ping-pong echo · one-shot sampler (−1…+2 oct) · reverse · glitch (8 moves) · fold+octaver · howling reverb · short delay. **FLIP = next, SKIP = random**, crossfaded, LOCK = shortest time between changes, EARTH modulates each effect. Two Cafes: LINK FX (same effect) and LINK PADS (pads together), each on or off |
| 11 | **ARP_DELAY** | the app plays a sine arpeggio (7 patterns × 7 chords) — plug the iPhone's audio out into the Cafe's input — into the Cafe's stereo tap delay. Tempo is shared both ways (SKIP = tap) |

In the delays, **SKIP = tap tempo**.

---

## 9. For the repository owner: sharing

1. **Push** your commits: `git push` (from the `esp_cafe` folder).
2. **Let people see it:** on GitHub → *Settings → General → Danger Zone → Change repository visibility →
   Public*. Or keep it private and add people under *Settings → Collaborators → Add people*.
3. **Put the web page online** (people can use it without downloading anything):
   *Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: `main`, folder `/ (root)` → Save*.
   After a minute the page is at `https://keiodak.github.io/esp_cafe/web/coco-pc.html`. Web Bluetooth
   needs HTTPS, and GitHub Pages provides it.
4. **Optional, a ready-made `.bin`:** *Releases → Draft a new release*, attach `esp_cafe_duo.ino.bin`. People
   who already have a BLE-capable version can then update from the web page without Arduino IDE.

---

## 10. Troubleshooting

| what you see | what to do |
|---|---|
| Serial Monitor: `FATAL: Malloc failed`, lamp stays off | Out of memory at boot. Use this repository's latest `esp_cafe_duo`, the ESP32 core 2.0.9, and don't add big buffers. |
| BLE connects, but nothing answers (`mtu 23` in the log) | The Cafe is stuck. Power it off and on, then connect again. |
| Chrome stays on *Connecting to Cafe-XXXX …* | Turn the computer's Bluetooth off and on, or quit Chrome completely and reopen it. |
| *update*: "the Cafe did not answer U" | The Cafe doesn't have a BLE-capable firmware yet, or the Partition Scheme isn't *Default*. Upload once over USB (section 4). |
| After an update the version didn't change | Check the name: you may have connected to the other Cafe. |
| No *Partition Scheme* menu | Choose *Tools → Board → ESP32 Dev Module*. |
| Compile error: `iram0_0_seg overflowed` | The ESP32's fast memory (IRAM) is full. Use the latest `esp_cafe_duo` (its effect code runs from flash), keep *Tools → Core Debug Level* at *None*, and don't add `IRAM_ATTR` to new functions. |

---

## Credits

Original Cafe firmware: Ciat-Lonbarde (Peter Blasser). Based on **Apple π** by ieat31415. BLE link,
presets and apps by k.odk.
