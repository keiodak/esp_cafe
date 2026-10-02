# parked: FOURSES / SHNTH on the Cafe (v4.71 → v4.72)

Taken out of esp_cafe_duo for now, with the app's iOS preset (../../ios/coco-duo/_parked_ios):
- `fourses_cafe.h` — FOURSES (BLE mode 7): the block from synths.h, its "O" / "T" commands and LINK OUT (tp_service)
- `shnth_*` — SHNTH (BLE mode 8): the Shbobo Shnth engine on the Cafe ("A" / "a" lines, the ring in loop())

The phone's ASH ("F 83", for the Fourses app's cup) stays in. Pool 6 (other_coco) stays: APP+CAFE's COCO+ / BOUNCE
use it; it is only left out of the default playlist. To bring them back: git show the commit that parked them.
