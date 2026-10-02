# parked: iOS (preset 6)

coco duo's iOS preset — FOURSES (the Fourses app, `FoursesApp/`, `Fourses/` C), SHNTH and JUSTINTS (`Shnth/`) —
taken out of the app for now (commit cb9ca0a … 7bb3be3 had them in). To bring it back: move these folders into
`CocoDuo/` again, restore the bridging header (`Shnth/CocoDuo-Bridging-Header.h` here) and the app's iOS hooks
(git show the commit that parked it).
