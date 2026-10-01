# Shbobo Shnth sound engine — implementation spec (from source)

Source analysed: `/tmp/shbobo` (MIT). Firmware = `sorce/shmat/*.s` (ARM Thumb‑2, STM32F103 @ 72 MHz),
host compiler = `sorce/shlisp/minilisp.c` + `situations.h` + `tokes.c`.

The **Shnth build** is `make shnth` → `main.s` assembled with `--defsym SHBOBO=0`
(`SHBOBO=1` is the Shtar, `mainth.s` is a different “thumb” board). Everything below is for
`SHBOBO=0`, i.e. every `.ifeq SHBOBO` block is the one that is assembled. `wanilla.s` /
`wanillaSRAM.s` is an alternative module-only build and is **not** the reference (its RAM map lacks
`runglerVALES`); the reference RAM map is `ramus_bss.s`.

Everything here was read from the code. Places where the code is ambiguous, buggy, or depends on
hardware not visible in the code are marked **UNCLEAR** or **QUIRK**, with the relevant lines quoted.

---------------------------------------------------------------------------------------------------

## 0. Notation used in this document

* `A` – the *variant* of the handler that is executing: `A=0` “dirac” (signed, the default),
  `A=1` “arab” (unsigned). Every module is assembled twice (`INSTORG` macro, `wanillaMACK.s`
  l.186–194): once with `ARAB=0` at slot offset `+0x000`, once with `ARAB=1` at `+0x400`. The variant
  is chosen **at dispatch time** from the global `lispSIN` (see §2) and stays fixed for the whole
  execution of that handler (including how it decodes its literal arguments), even if `lispSIN`
  changes while its arguments are being evaluated.
* All arithmetic is 32‑bit two’s complement, wrapping. `mul` is the low 32 bits of the product:
  `MUL(a,b) = (int32_t)((uint32_t)a * (uint32_t)b)`. `x >> n` on `int32_t` is arithmetic (asr);
  `(uint32_t)x >> n` is logical (lsr).
* `SAT(x)` = the return saturation of the current variant:
  `A=0: clamp(x, -32768, 32767)` (`ssat #16`); `A=1: clamp(x, 0, 65535)` (`usat #16`, negative → 0).
* `SSAT16(x)` = `clamp(x,-32768,32767)` regardless of variant.
* `ABS(x)` (asm macro `RECTARET`/`RECTA`, `wanilla10trango.s` l.6–14):
  `A=0: x<0 ? -x : x` (pure 32‑bit negate); `A=1: clamp(x,0,65535)`.
* `SHR(x)` (asm `ALSER`, `wanillaMACK.s` l.117): `A=0: x >> 15` (asr); `A=1: (uint32_t)x >> 16` (lsr).
* `LDH(p)` (asm `LOADERH`): load a 16‑bit state cell, `A=0` sign‑extended (`ldrsh`),
  `A=1` zero‑extended (`ldrh`). Stores of 16‑bit state are always plain truncation (`strh`).
* `HIGH` = `A=0: 0x8000` (32768), `A=1: 0x10000` (65536) (asm `HIGHSTATE`).
* `TRIG(bits, i, v)` (asm `TRIG_IDEE_TOO`, `wanillaMACK.s` l.87–93):
  `h = (v >= 1) ? 1 : 0` (`usat #1`: ≤0 → 0, ≥1 → 1); `old = bit i of bits`; `bit i := h`;
  returns `rising = h && !old`. The level bit is stored every time this argument is reached.
* `ARG(v)` – read the next argument of the current list (asm `POPSEX` = `POPERAMP` + `SEXY`):
  ```c
  b = *cod++;
  if (b == 0)    return SAT(acc);      // list ended: return from THIS handler with SAT(acc)
  if (b != 0xFF) v = A ? (int32_t)(b << 8) : (int32_t)(int16_t)(b << 8); // literal
  else           v = sexpr();          // nested expression, evaluated now
  ```
  i.e. **every `ARG` is an implicit early return** when the list is shorter than expected; the
  return value is `SAT(acc)` with `acc` = the handler’s local accumulator at that moment.
  (A few handlers return differently; noted per handler.)
* `MULADD(acc)` – the shared tail used by almost every word (asm `LISPMULADD`):
  ```c
  for (;;) {
     ARG(m);  acc = A ? (int32_t)((uint32_t)MUL(acc,m) >> 16) : (MUL(acc,m) >> 15);
     ARG(a);  acc = acc + a;           // no saturation in between
  }                                     // returns SAT(acc) when the list ends
  ```
  So `(word … m1 a1 m2 a2 m3 a3 …)` = repeated `acc = acc*m>>15 + a`, any number of pairs.
  Literal `1` = 256, so `mul 1` ≈ ×1/128 in dirac; `mul -1` (compiled as `negwon` = −256) ≈ ×−1/128.
  A value of 32768 (`HIGH`) times `m` gives exactly `m`.

---------------------------------------------------------------------------------------------------

## 1. Bytecode format (what shlisp emits)

### 1.1 Overall upload image

`situations.h::situsb()` emits, then `main()` appends 16 zero bytes:

```
offset 0      : 0x00                       mastroBarcode (always 0, unused by firmware)
offset 1      : N-1                        "vexamt" = number of presets ("soups") minus 1
offset 2..    : (N-1) little-endian uint16 vec[1..N-1] = start offset of soup k, measured
                                           from offset 0 of this image
offset 2N     : soup 0 bytes, soup 1 bytes, … (concatenated "situation_txt")
then          : 16 × 0x00 (padding, main(): `for (j = 0; j < 16; j++) write_bytez(0);`)
```
`vec[i] = situation_place_at_start_of_soup_i + 2*(N-1) + 2` (situsb: `situations_vector[i] +=
((situations_plz - 1) << 1) + 2;`). Soup 0 has no vector; it starts right after the header at
`2*(N-1)+2`. The firmware stores this image at flash `0x08010000` (“lispVectors”, `main.s`
`.org 0x10000`; `usb_lisprog.s` writes to `FLASH_SPACE + 0x10000 + loke`). Max 256 presets (one byte),
offsets are 16‑bit (image ≤ 64 KiB).

Transport (USB HID, only relevant if you emulate the host side): the bytes are sent in 8‑byte
`SET_REPORT` control transfers (`chubSENDATE`: `libusb_control_transfer(devh,0x20,0x09,0,0,rept,8,0)`),
the device writes them sequentially to flash (erasing each 2 KiB page when `(loke & 0x7FF)==0`),
then the host sends a `GET_REPORT` (`chubSENDEND`) which ends programming and lights all LEDs.
A trailing partial 8‑byte block is never sent (bytes are buffered in 8s), which is why 16 zeros are
appended. For the ESP32 you can use any transport; just deliver the image bytes.

### 1.2 Expression encoding

| Lisp element (as printed by `print()`) | Bytes |
|---|---|
| list `( e1 e2 … )` (“fish”) | `FF` + bytes(e1) + bytes(e2) + … + `00` |
| integer `0` | `FF 00` (an expression with opcode 0 = constant 0, see §3.1) |
| integer v with `(v & 0xFF) == 0xFF` (e.g. −1, 255, 511) | `FF F2 00` (= `(negwon)` = expression returning −256 / 0xFF00) |
| any other integer v | one byte `v & 0xFF` (truncation; −95 → `A1`, 300 → `2C`) |
| **QUIRK**: integer v ≠ 0 with `(v & 0xFF) == 0` (256, −256, 512 …) | the single byte `00` → **terminates the enclosing list** (compiler bug; `print()` only special-cases `value == 0`) |
| soup `{ e1 e2 … }` | registers a new preset start (`situatier()`), then bytes(e1)…, then `00` |
| tank `[ e1 e2 … ]` | bytes(e1) bytes(e2) … (spliced, no delimiters) |
| boat `< f args >` | compile‑time function call, its *result* is printed |
| symbol | its bound value is printed (word names are bound to their opcode integers) |

So at runtime an expression is `FF op arg* 00`, where each `arg` is either a literal byte
(`01..FE`) or a nested expression starting with `FF`. The **first element of a list is the opcode**:
`(left x)` → `FF F0 …`. Word names are plain integers bound in the compiler environment
(`define_grub`, `minilisp.c`), so `(240 x)` ≡ `(left x)`, and the opcode position may itself be any
element, e.g. a nested list → “computed opcode” (`FF FF …`) (§2.3).

**Opcode byte layout.** `op` is 8 bits. `op & 0xFC` selects a 4‑opcode “slot” (a 0x800‑byte code
block at `0x20000 + (op & 0xFC) << 9`); `op >> 4` is the module file (`ORGASM 0xN0, wanillaN0*.s`).
The low 2 bits (or 3 bits for 8‑instance words) select the **instance** (which state cell set to use)
or, for multi‑function slots, the **function** (via the `NUTTS` jump table on `op & 3`).
The compiler’s word table (`tokes.c`) names instance k (k ≥ 1) by appending letter `'a'+k`:
`horn`=0x10, `hornb`=0x11, … `hornh`=0x17. (Instance 0 has no letter; there is no “horna”.)

**Top level.** Within a soup, the firmware’s outer loop (`overlord`, `sexpress.s`) reads bytes:
`00` ends the soup (= end of this sample’s work), `FF` evaluates an expression and discards its value,
any other byte is skipped. So `left`/`right`/`pan`/`srate`/`jump`/`lights`/`bend` are ordinary
expressions with side effects; there is no special top-level form. Anything printed *before* the first
`{` ends up at the start of preset 0.

### 1.3 Compiler (shlisp) — reader and evaluator summary

Recommended for the iPhone: compile `minilisp.c` + `situations.h` + `tokes.c` unchanged (portable C;
I built it on Linux with a stub `chub.h`) and capture `write_bytez()` output — that guarantees
byte-identical images. `mimilisp.c` is the same language with a different allocator (emitter
identical). Summary of semantics if you re-implement:

* Reader (`readhui`): whitespace skipped; `;` comment to end of line; `(`→fish, `{`→soup, `[`→tank,
  `<`→boat; **any** of `) } ] >` closes the current list (no matching); `.` dotted pair;
  digits → decimal int; `-` followed by digit → negative int, else symbol; symbols are
  `[A-Za-z0-9/~`?,':"|+=_!@#$%^&*-]+` starting with a letter or one of those punctuation chars.
* Evaluation: ints, fish, soup, tank are self‑evaluating (their *elements are not evaluated* until
  printed); symbols are looked up (error if unbound); a boat `<f a b>` applies `f`.
* Each top‑level form is `print(env, eval(env, form))`. `print` of a list prints elements left to
  right, evaluating symbols/boats in the *global* env at print time, and **stops at the first element
  that is a null pointer** (`gutsprinter`: `if (obj->car == 0) break;`).
* Compile-time primitives (all used as `<op …>`): `@` define (`<@ name value>`), `#` lambda
  (`<# (params) body…>`), `?` if, `= , '` (==, <, >), `+ - * / % & | ^ !`, `'' ,,` (shift left/right),
  `~` random (`<~ 56>` = `rand() % 56`, seeded with time → **non-deterministic compile**),
  `` ` `` (`d*pow(a,b/c)` rounded), `" :` car/cdr, `@" @:` setcar/setcdr, `fish soup tank boat`
  (cons with that list type), `$` print now, `exit`.
* Word table: `tokes.c` (`MEXPTOKE(name, argdoc, help, opcode, instances)`); `JEXPTOKE` entries are
  Shtar words but are defined for the Shnth compiler too. Full list in §3.

### 1.4 Worked example: `examp/shnth/beachlanterns.txt`

Source (first soup):
```
{(left (wave (smoke (mountb 12 12 ))-95 (mountc 11 -33 )))
(jump (tar 1 ))
(right (waveb (smokeb (mountd 13 12 ))-95 (mountf 14 -33 )))
}
```
Actual compiler output (built from the repo, hex):
```
0000: 00 01 34 00 FF F0 FF 70 FF 40 FF 39 0C 0C 00 00
0010: A1 FF 3A 0B DF 00 00 00 FF F9 FF F7 01 00 00 FF
0020: F1 FF 71 FF 41 FF 3B 0D 0C 00 00 A1 FF 3D 0E DF
0030: 00 00 00 00 FF F0 FF FD FF 51 FF 49 01 00 08 54
0040: FF 41 03 16 00 05 00 00 FF 70 FF 40 FF 39 0C 0C
0050: 00 00 A1 FF 3A 0B DF 00 00 00 FF F9 FF F7 01 00
0060: 00 FF F4 12 00 FF F1 FF FD FF 50 FF 48 01 00 08
0070: 54 FF 41 03 21 00 05 00 00 FF 71 FF 41 FF 3B 0D
0080: 0C 00 00 A1 FF 3D 0E DF 00 00 00 00 00 00 00 00
0090: 00 00 00 00 00 00 00 00 00 00 00 00
```
Byte by byte:
```
00            mastroBarcode
01            vexamt = 2 soups - 1
34 00         vec[1] = 0x0034 = 52: soup 1 starts at image offset 52
                (text offset 48 + 2*(2-1) + 2)
-- soup 0 (starts at 2*1+2 = 4) --
FF F0         ( left                     F0 = left
 FF 70          ( wave                   70 = wave (instance a)
  FF 40           ( smoke                40 = smoke
   FF 39            ( mountb 12 12 )     39 = mountb, 0C = 12, 0C = 12
   0C 0C 00
  00              )                      end smoke (no add)
  A1              -95                    q  (dirac literal: (int16)(0xA1<<8) = -24320)
  FF 3A 0B DF 00  (mountc 11 -33)        3A = mountc, DF = -33
 00             )                        end wave
00            )                          end left
FF F9 FF F7 01 00 00     (jump (tar 1))  F9 = jump, F7 = tar
FF F1 FF 71 FF 41 FF 3B 0D 0C 00 00 A1 FF 3D 0E DF 00 00 00
              (right (waveb (smokeb (mountd 13 12)) -95 (mountf 14 -33)))
00            end of soup 0
-- soup 1 (offset 0x34) --
FF F0 FF FD FF 51 FF 49 01 00 08 54 FF 41 03 16 00 05 00 00
              (left (arab (fogb (dustb 1) 8 84 (smokeb 3 22) 5))
FF 70 … 00 00 (wave (smoke (mountb 12 12)) -95 (mountc 11 -33)))   ← 2nd arg of left
FF F9 FF F7 01 00 00     (jump (tar 1))
FF F4 12 00              (srate 18)
FF F1 FF FD FF 50 … 00   (right (arab (fog (dust 1) 8 84 (smokeb 3 33) 5)) (waveb …))
00            end of soup 1
00 ×16        padding
```
What soup 0 does each sample: `smoke` steps its 16‑bit LCG and multiplies by the slow triangle
`mountb` (±3072, period ≈ 262144 samples); `wave` low‑passes it with q = |−24320| and cutoff
= |mountc| (a 2nd slow triangle, ±8448); `left` adds the result to the output accumulator. `jump`
watches `(tar 1)` = 256 while the tar button is held → on its rising edge advances to the next preset.

---------------------------------------------------------------------------------------------------

## 2. The interpreter

### 2.1 Registers / calling convention (`sexpress.s`, `wanillaMACK.s`)

```
lispMEX r0  opcode byte → masked instance index inside the handler        (callee-saved*)
lispACC r1  handler’s accumulator                                          (callee-saved*)
lispWOR r2  handler’s scratch / pointer / flag that must survive nested calls (callee-saved*)
lispRET r3  value of the last argument read; RETURN VALUE of an expression
lispSIN r9  0 = dirac, 1 = arab: selects variant of the NEXT dispatched handler (global, not saved)
lispCOD r12 bytecode read pointer (global, advances monotonically, never saved)
dacLEFT r10, dacRITE r11  output accumulators (global)
workONE..workFIV r4..r8  temporaries, clobbered by any nested evaluation
```
(*) `sexpression` does `push {r0,r1,r2,lr}` on entry and every return is `pop {r0,r1,r2,pc}`,
so a handler’s MEX/ACC/WOR survive nested argument evaluation; r4–r8 do not.

**C translation rule:** implement each handler as a C function with locals `mex, acc, wor`;
everything else that the asm keeps in r4–r8 is a temporary that must be recomputed after any `ARG`.
Read/write the state memory exactly where the asm does `ldr*`/`str*` — handlers keep a *register
copy* of their state while evaluating arguments, and nested expressions referencing the same instance
see/modify memory in between (patches do this, e.g. `newhorse.txt` feeds `horse`/`horseb` into each
other).

### 2.2 Per-sample flow

The whole patch runs **once per audio sample**, inside the SysTick interrupt (`vectorSystick.s`):

```c
void systick_isr(void) {
  DAC1 = clamp(dacLEFT >> 4, -2048, 2047) + 2048;   // previous sample's sums (DACKER macro)
  DAC2 = clamp(dacRITE >> 4, -2048, 2047) + 2048;
  dacLEFT = dacRITE = 0;
  SYSTICK_RELOAD = 0x1000;                          // default rate; `srate` may overwrite below
  /* sexpress.s */
  sin = 0;
  vexamt = image[1];
  if (witch > vexamt) witch = 0;                    // witch_vectore: current preset (RAM byte)
  cod = (witch == 0) ? image + 2*vexamt + 2
                     : image + (image[2*witch] | image[2*witch+1] << 8);
  for (;;) {                                        // "overlord"
    b = *cod++;
    if (b == 0)   break;                            // end of soup = end of sample
    if (b == 0xFF) sexpr();                         // value discarded
  }
}
```
There is no separate control rate. All words run per sample; inputs are updated asynchronously by
other ISRs between samples (§4). Things only become “slower” when an expression is not reached:
non-selected `togo`/`ladder` elements, the skipped input of `sauce`/`salsa`, and arguments after an
early list end are **not evaluated**, so their state does not advance that sample.

State (all module RAM) is zeroed once at boot (`initiate.s`: zero from `bitband+0x20` to
`bitband+0xB000`) and **never reset on preset change**. `witch_vectore` (RAM offset 0) and the
antenna tare (`chinkwonkTARESZ`, offset 0x1C) are below 0x20 and are **not** zeroed at boot.

### 2.3 `sexpression` dispatch (`sexpress.s` l.36–51)

Called after a `FF` byte was consumed.
```asm
sexpression:
 push {lispMEX,lispACC,lispWOR,lr}
 ldrb lispRET, [lispCOD], 1
 cmp lispRET, 0xFF
 ite ne
 lslne lispRET, lispRET, 8
 bleq sexpression @recur MEXP          ; computed opcode
 lsr lispMEX, lispRET, 8
 and lispRET, lispMEX, 0xFC
 lsl lispRET, lispRET, 9
 add lispRET, lispRET, 0x20000
 add lispRET, lispRET, lispSIN, LSL 10
 add lispRET, lispRET, 1               ; thumb bit
 bx lispRET
```
C:
```c
int32_t sexpr(void) {
  uint8_t b = *cod++;
  uint32_t mex = (b != 0xFF) ? b : ((uint32_t)sexpr() >> 8);   // computed opcode
  int A = sin;                                                  // variant fixed now
  return handler[(mex & 0xFC)][A](mex);    // address 0x20000 + (mex&0xFC)<<9 + A*0x400
}
```
* Only the low 8 bits of `mex` matter in practice (all handlers mask with `&3`, `&7`, `tst #1/#2`);
  for a computed opcode use `op = ((uint32_t)value >> 8) & 0xFF`. E.g. `(-1 …)` compiles to
  `FF FF F2 00 …`: inner `negwon` returns −256 → `op = 0xFF` → `lights`.
* The handler for a slot of 4 opcodes occupies `0x400` bytes per variant; slots `0xD8–0xDF` are
  empty (zero‑filled, `0x0000` = `movs r0,r0`), so execution **slides into the next code**, which is
  the *dirac* `press` handler at slot 0xE0 (`mex` unchanged → instance `mex&3`) — **QUIRK**, regardless
  of `lispSIN`.
* Return: value in `lispRET` (a 32‑bit int; usually already saturated to 16 bits, exceptions noted).

### 2.4 Value conventions

* Literal byte `b` (1..254) as an argument: dirac `(int16)(b<<8)` → −32768..32512 in steps of 256
  (`b=0x80`→−32768); arab `b<<8` → 256..65024. Literal 255 and 0 cannot appear as bytes (see §1.2).
* Expression results are 16‑bit: dirac −32768..32767, arab 0..65535 (`SAT`).
* `0x7FFF`/`32768` ≈ 1.0 for `mul`‑type scaling in dirac (`>>15`); `65536` ≈ 1.0 in arab (`>>16`).

### 2.5 `dirac` / `arab` (opcodes 0xFC / 0xFD) and `lispSIN`

```asm
1: .rept 4
 and lispSIN, lispMEX, 1            ; 0 for dirac (FC), 1 for arab (FD)
 ldrb lispRET, [lispCOD], 1
 cmp lispRET, 0
 ittt eq
 moveq lispRET, lispACC
 moveq lispSIN, 0
 POPEQE
 SEXY
 add lispACC, lispACC, lispRET
```
```c
acc = 0;
for (;;) {
  sin = op & 1;                 // set before EACH argument
  b = *cod++;
  if (b == 0) { sin = 0; return acc; }    // raw sum, NOT saturated; sin forced to 0 (not restored!)
  v = literal decoded with THIS handler's variant A, or sexpr() (dispatched with the new sin);
  acc += v;
}
```
QUIRKs: (1) after `(dirac …)`/`(arab …)` returns, `sin` is 0 even if the caller was running in arab
mode, so later arguments of an enclosing arab-mode handler are dispatched dirac (literals of that
handler are still decoded with its own variant). (2) Literal args directly inside `(arab …)` called
from dirac are decoded *signed* (the dirac variant of the `arab` handler is running). (3) Return is the
unsaturated 32‑bit sum.

---------------------------------------------------------------------------------------------------

## 3. Every opcode

### 3.0 Opcode map (from `tokes.c` + `wanilla.s/main.s` ORGASM list)

| op | word(s) (compiler) | args (tokes.c) | handler (file) | instance mask |
|---|---|---|---|---|
| 00 | (literal 0) | – | const 0 (00butts) | – |
| 01 | wind | mul add | mic (00butts) | – |
| 02,03 | corp, corpb | mul add | antennae (00butts) | op&1 |
| 04–07 | bar … bard | mul add | bars (00butts) | op&3 |
| 08–0B | minor … minord | mul add | lower buttons | op&3 |
| 0C–0F | major … majord | mul add | upper buttons | op&3 |
| 10–17 | horn … hornh | nume deno mul add | TRANGO (10trango) | op&7 |
| 18–1F | saw … sawh | nume deno mul add | TRANSA (10trango) | op&7 |
| 20–27 | togo … togoh | uptrig dntrig liszt… | TOGO (20togo) | op&7 |
| 28–2F | toggle … toggleh | trig mul add | TOGGLE (20togo) | op&7 |
| 30–37 | swoop … swooph | trig nume deno mul add | SWOOP (30swoop) | op&7 |
| 38–3F | mount … mounth | nume deno mul add | MOUNT (30swoop) | op&7 |
| 40–47 | smoke … smokeh | mul add | NOISE (40dust) | op&7 |
| 48–4F | dust … dusth | speed mul add | DUST (40dust) | op&7 |
| 50–53 | fog … fogd | trig swnu swde honu hode mul add | FOG (50fog) | op&3 |
| 54–57 | swamp … swampd | same as fog | SWAMP | op&3 |
| 58–5B | haze … hazed | trig swnu swde sanu sade mul add | FOZ | op&3 |
| 5C–5F | (none) | | FOZ again (“redundant”) | op&3 |
| 60–63 | string … stringd | trig nume deno [fb] mul add | KARP (60karp) | op&3 |
| 64–67 | comb … combd | inn nume deno [fb] mul add | COMB | op&3 |
| 68–6B | zither … zitherd | trig deno mul add | ZITHER | op&3 |
| 6C–6F | (none) | | ZITHER again | op&3 |
| 70–77 | wave … waveh | inn q rate mul add | PHILT lowpass (70philt) | **op&3** (wavee..h alias wave..waved) |
| 78–7B | water … waterd | trig q rate mul add | WATER | op&3 |
| 7C–7F | salt … saltd | inn q rate mul add | HIGHPASS | op&3 (shares state with wave) |
| 80–83 | horse … horsed | upnu dnnu upde dnde mul add | FOURSES (80fourses) | op&3 |
| 84–8F | (none) | | FOURSES again | op&3 |
| 90–97 | slew … slewh | inn upp don mul add | SLEW (90slewhel) | op&7 |
| 98–9F | wheel … wheelh | upp don mul add | WHEEL | **op&3** (wheele..h alias) |
| A0–A7 | gear … gearh | trig deno mul add | GEAR (A0pulse) | op&7 |
| A8–AF | pulse … pulseh | trig deno mul add | PULSE | op&7 |
| B0–B7 | sauce … sauceh | per inn mul add | SAUCE (B0sauce) | op&7 |
| B8–BF | salsa … salsah | trig inn mul add | SALSA | op&7 |
| C0–C3 | melody (Shtar word) | gate inn nume skip mul add | MELODY (C0shtar) | op&3 |
| C4–C7 | worm (Shtar word) | inn mul add | WORM | op&3 |
| C8–CB | scale (Shtar word) | inn mul add | SCALE | – |
| CC–CF | ladder (Shtar word) | inn liszt… | LADDER | op&3 |
| D0–D7 | **no word** (use number, e.g. `(-48)`=0xD0) | trig data mul add | RUNGLER (D0rungler) | op&7 |
| D8–DF | none | | falls into dirac PRESS (§2.3) | op&3 |
| E0–E3 | press … pressd | inn att dec thresh mul add | PRESSR (E0dynamo) | op&3 |
| E4–E7 | leak … leakd | inn nume mul add | LIKDC | op&3 |
| E8 | reflect | inn oth mul add | WAVESHAPR fn 0 | – |
| E9 | return | inn oth mul add | fn 1 | – |
| EA | and | inn oth mul add | fn 2 | – |
| EB | xor | inn oth mul add | fn 3 | – |
| EC–EF | (none) | | WAVESHAPR again (same fn by op&3) | – |
| F0 | left | liszt | output (F0nuts) | – |
| F1 | right | liszt | output | – |
| F2 | square, negwon | inn oth mul add / – | comparator | – |
| F3 | modo | inn mod mul add | integer multiply | – |
| F4 | srate | inn… | sample rate | – |
| F5 | mul | inn mul add | | – |
| F6 | add | liszt | saturating sum | – |
| F7 | tar | mul add | tar button | – |
| F8 | bend | inn… | preset bend | – |
| F9 | jump | trig… | preset jump | – |
| FA | pan | inn place … | stereo | – |
| FB | short | bigg smal | 16-bit constant | – |
| FC | dirac | liszt | §2.5 | – |
| FD | arab | liszt | §2.5 | – |
| FE, FF | lights | inn… | LEDs | – |

Note `tokes.c` claims 8 instances for `wave` and `wheel`, but the firmware masks with `&3`
(`PHILT`: `and lispMEX, lispMEX, 3`; `WHEEL`: `and lispMEX, lispMEX, #3`), so e.g. `wavee` *is*
`wave`. Examples do use `wavee…waveh`, `wheele`.

### 3.1 Module 00 — inputs (`wanilla00butts.s`)

**op 00 (constant 0)**: `tst lispMEX,1; itt eq; moveq lispRET,0; POPEQE` → returns 0 immediately and
**consumes no further bytes** (so `FF 00` is a complete expression).

**op 01 `wind` (microphone)**:
```c
acc = ((int32_t)ADC2_DR - (int32_t)ADC1_DR) << 4;   // both 12-bit unsigned; range ±65520
return MULADD(acc);
```
ADC2 = channel 3 (PA3, mic), continuous; ADC1 regular = channel 2 (PA2) = reference/midpoint.

**op 02/03 `corp`/`corpb` (antennae)**: `acc = (int16)chinkwonks[op&1]; return SQUISH(acc);`
**op 04–07 `bar`..`bard`**: `acc = (int16)barres[op&3]; return SQUISH(acc);`

`SQUISH` (asm `SQUISHRAMP`) differs from MULADD: only one mul/add pair, rest evaluated and ignored:
```c
ARG(m);  acc = A ? (MUL(acc,m) >> 16) /* asr! */ : (MUL(acc,m) >> 15);
ARG(a);  acc += a;
for (;;) ARG(dummy);       // further args are evaluated (side effects happen) and discarded
```
(Loads are `ldrsh` in both variants; arab return `usat` clips negative bar/antenna values to 0.)

**op 08–0B `minor`..`minord`**: `acc = (GPIOA_IDR & (0x40 << (op&3))) ? HIGH : 0; return MULADD(acc);`
(PA6..PA9). **op 0C–0F `major`..`majord`**: same with `GPIOC_IDR & (0x10 << (op&3))` (PC4..PC7).
Pin reads 1 → “on”. (Button electrical polarity: **UNCLEAR** from code; the code treats a high pin as
pressed.) With no args they return `SAT(HIGH)` = 32767 (dirac) / 65535 (arab); `(minor 1)` = 256 when
pressed.

### 3.2 Module 10 — `horn` (triangle) and `saw` (`wanilla10trango.s`)

State: `trangoes[8]` int16, direction bits `trangwonz` (bit i: 1 = rising); `transaws[8]` int16.

**horn (TRANGO)**, `i = op&7`:
```c
acc = LDH(&trangoes[i]);
ARG(n);  n = ABS(n);
if (bit(trangwonz,i) == 1) acc += n >> 4; else acc -= n >> 4;
trangoes[i] = (int16)acc;
ARG(d);  d = ABS(d);
// top: subs t = acc - d ; gt
t = acc - d;
if ((int32_t)acc > (int32_t)d) { setbit(trangwonz,i,0); acc -= 2*t; trangoes[i] = (int16)acc; }
// bottom
if (A == 0) { t = acc + d; lt = ((int64_t)acc + d) < 0; }            // adds
else        { t = acc;     lt = ((int32_t)acc < 0) ^ V_of(acc_before_top - d); } // movs keeps V of the subs
if (lt) { setbit(trangwonz,i,1); acc -= 2*t; trangoes[i] = (int16)acc; }
return MULADD(acc);
```
Dirac: triangle between −d and +d, slope n/16 per sample, reflecting (period = 4d/(n/16) samples).
Arab: triangle between 0 and d. Initial direction bit 0 = falling. Without `d` the 16‑bit state just
wraps (stored with `strh`), giving a saw. (`V_of(x - y)` = signed overflow of the 32‑bit
subtraction; practically always 0 because values are ~17 bits.)

**saw (TRANSA)**, `i = op&7`:
```c
acc = LDH(&transaws[i]);
ARG(n); n = ABS(n); acc += n >> 4; transaws[i] = (int16)acc;
ARG(d); d = ABS(d);
if ((int32_t)acc > (int32_t)d) { acc = A ? acc - d : acc - 2*d; transaws[i] = (int16)acc; }
return MULADD(acc);
```
(asm dirac: `subgt acc, workTWO, lispRET` where `workTWO = acc - d`.) Rising saw −d..d (dirac) or 0..d.

### 3.3 Module 20 — `togo` (sequencer) and `toggle` (`wanilla20togo.s`)

State: `togoesPLACZ[8]` uint8 (step), `togoesVALES[8]` int16 (last output), bits `togouptrig`,
`togodntrig`; `toglvals` bits (toggle states), `togltrig` bits.

**togo**, `i = op&7`, args: `uptrig dntrig e0 e1 e2 …`
```c
acc = LDH(&togoesVALES[i]);
ARG(up);
scan = togoesPLACZ[i];
if (TRIG(togouptrig,i,up)) { scan++; togoesPLACZ[i] = (uint8)scan; }
ARG(dn);
scan = togoesPLACZ[i];                       // reloaded as 0..255
if (TRIG(togodntrig,i,dn)) { scan--; togoesPLACZ[i] = (uint8)scan; }   // scan may now be -1
uint8_t *start = cod; int plaz = 0, depth = 0;
for (;;) {                                   // SCANSOR_IDEE_FRONT / _LOOP
  if (plaz == scan) break;                   // found -> "lively"
  b = *cod++; if (b == 0) depth--; if (b == 0xFF) depth++;
  if (depth == 0) { plaz++; if (*cod == 0) goto wrap; continue; }
  if (depth > 0) continue;
wrap:                                        // ran past the last element (or empty list)
  cod = start;
  if (scan < 0) scan = plaz - 1; else scan = 0;   // down past 0 -> last element
  plaz = 0; togoesPLACZ[i] = (uint8)scan;
  // asm: if scan >= 0 jump straight to lively, else continue scanning (depth is NOT reset)
  if (scan >= 0) break;
}
// lively: evaluate exactly one element (the others are skipped, NOT evaluated)
ARG(v);                         // if the list is empty this returns SAT(acc)
acc = v; togoesVALES[i] = (int16)v;
depth = 0; do { b = *cod++; if (b==0) depth--; if (b==0xFF) depth++; } while (depth >= 0);
return acc;                     // returned UNSATURATED (POPLTE path: movlt lispRET, lispACC)
```
Elements are delimited by bytecode structure: a literal byte is one element, `FF … 00` (with nesting)
is one element, `FF 00` (constant 0) is one element. Note `scan` (uint8) can exceed the list length
(e.g. after a preset change); it then wraps to 0. QUIRK: empty list + down‑trigger loops forever.

**toggle**, `i = op&7`:
```c
acc = bit(toglvals,i);
b = *cod++; if (b == 0) return acc << (A ? 16 : 15);   // UNSATURATED: 32768 / 65536
trig = decode/eval(b);
if (TRIG(togltrig,i,trig)) acc ^= 1;
setbit(toglvals,i,acc);
acc <<= (A ? 16 : 15);
return MULADD(acc);
```

### 3.4 Module 30 — `swoop` (one‑shot) and `mount` (slow triangle) (`wanilla30swoop.s`)

State: `swoopVALES[8]` int16, `swoopGWONZ[8]` uint8 phase; `mountVALES[8]` int32, `lfogwonz` bits.

Shared step macros (also used by `fog`, with `G` = the phase byte, `e` = value):
```c
SWOOP_NUME(e, n, G):   // n = ABS(n)
  if (A == 0) { g = G & 3; if (g == 2) e -= n >> 8; }
  else        { g = G & 1; if (g == 0) e -= n >> 8; }   // arab: even -> falling
  if (g & 1) e += n >> 8;
  store16(e);
SWOOP_DENO(e, d, &G):  // d = ABS(d)
  if (A == 0) {
    if (G == 3 && e > 0) { e = 0; G = 0; }               // finished: back to idle
    if (e > d)               { G = 2; e = d; }           // peak reached: start falling (clamped to d)
    else if ((int64_t)e + d <= 0) { G = 3; e = e - 2*(e + d); }  // reflect at -d, rise to 0
  } else {
    if (e > d) { G = 0; e = d; }
    else if (e < 0) e = 0;
  }
  store16(e);
```
**swoop**, `i = op&7`:
```c
acc = LDH(&swoopVALES[i]);
ARG(trig); if (TRIG(swooptrig,i,trig)) swoopGWONZ[i] |= 1;
ARG(n);  SWOOP_NUME(acc, n, swoopGWONZ[i])   -> swoopVALES[i]
ARG(d);  SWOOP_DENO(acc, d, &swoopGWONZ[i])  -> swoopVALES[i]
return MULADD(acc);
```
Dirac: idle (G=0, value 0) → trigger G=1 rising by n/256 per sample → at d: G=2 falling → at −d:
G=3 rising → at >0: value 0, G=0. One full triangle cycle per trigger. Retrigger while falling
(G=2|1=3) makes it rise. Arab: attack to d then decay (G=0 → keeps falling, clamped at 0).
QUIRK: with d = 0 the dirac idle state flips to G=3 (`e + d <= 0`).

**mount**, `i = op&7`:
```c
acc32 = mountVALES[i];
b = *cod++; if (b==0) return SAT(A ? (uint32_t)acc32>>16 : acc32>>16);   // early end
n = ABS(arg);
acc32 = mountVALES[i];
if (bit(lfogwonz,i) == 1) acc32 += n; else acc32 -= n;       // NOT shifted
mountVALES[i] = acc32;
ARG(d)  → if absent returns SAT(acc32) (the full 32-bit value, saturated!)  QUIRK
d = ABS(d); D = (uint32_t)d << 16;
t = acc32 - D;
if ((int32_t)acc32 > (int32_t)D) { setbit(lfogwonz,i,0); acc32 -= 2*t; mountVALES[i] = acc32; }
if (A == 0) { t = acc32 + D; lt = ((int64_t)acc32 + (int32_t)D) < 0; }
else        { t = acc32;     lt = ((int32_t)acc32 < 0) ^ V_of(acc32_before - D); }
if (lt) { setbit(lfogwonz,i,1); acc32 -= 2*t; mountVALES[i] = acc32; }
acc = A ? (int32_t)((uint32_t)acc32 >> 16) : (acc32 >> 16);
return MULADD(acc);
```
16.16 fixed point triangle ±d (output in the same units as `horn`), 4096× slower than `horn`
for the same numbers. Note arab `d ≥ 0x8000` makes `D` negative as int32 and the signed compares
behave oddly — reproduce the flags exactly as written.

### 3.5 Module 40 — `smoke` (noise) and `dust` (`wanilla40dust.s`)

State: `noiseVALES[8]`, `dustVALES[8]` (LCG states), `dustRAMPS[8]` (int16 each).
LCG step (`NOISE_MIT_IDEE4`): `x' = (int16)old * 25173 + 13849` computed in 32 bits from the
sign‑extended old value; stored truncated to 16 bits. All states start at 0, so equal instances
produce identical sequences.

**smoke**, `i = op&7`:
```c
noiseVALES[i] = (int16)((int16)noiseVALES[i] * 25173 + 13849);
acc = LDH(&noiseVALES[i]);
return MULADD(acc);
```
**dust**, `i = op&7`:
```c
acc = LDH(&dustRAMPS[i]);
ARG(speed); speed = ABS(speed);
acc += speed >> 8;
w = (int16)dustVALES[i] * 25173 + 13849;          // candidate next random, NOT stored yet
thr = w & 0x7FFF;
if ((int32_t)acc > thr) { acc = A ? ~thr : 0; dustVALES[i] = (int16)w; }   // fire: new threshold
dustRAMPS[i] = (int16)acc;
return MULADD(acc);
```
Output is a ramp rising by speed/256 per sample that resets to 0 when it exceeds a random threshold
(0..32767) — i.e. a random-period saw; downstream trigger inputs see a rising edge right after each
reset (value goes 0 → ≥1). Arab resets to `~thr` (= −thr−1, stored as 16‑bit unsigned).

### 3.6 Module 50 — `fog` / `swamp` / `haze` granular (`wanilla50fog.s`)

State per instance i (0..3) and grain g (0..3), index `m = i + 4*g`:
`fogVALES[4]` int16 (last output), `fogPLACZ[4]` uint8 (current grain), `fogNDNDZ[4][16]` int16
(latched params k=0..3), `fogSWOOPgwonz[16]` uint8, `fogSWOOPvales[16]` int16 (envelopes),
`fogTRANGvales[16]` int16 (oscillators), `fogtran` bits 0..15 (oscillator directions), `fogtrig` bits.

`kind = (op >> 2) & 3`: 0 fog (horn osc), 1 swamp (horn osc whose deno is modulated by the envelope),
2,3 haze (saw osc).
```c
i = op & 3;
acc = (int16)fogVALES[i];                       // ldrsh in both variants
ARG(trig);
rise = TRIG(fogtrig, i, trig);
P = fogPLACZ[i];
if (rise) { P = (P + 1) & 3; fogPLACZ[i] = P; fogSWOOPgwonz[4*P + i] |= 1; }
m = i + 4*P;
for (k = 0; k < 4; k++) { ARG(v); if (rise) fogNDNDZ[k][m] = (int16)v; }  // params evaluated every
                                                                          // sample, latched on trigger
acc = 0;
for (g = 0; g < 4; g++) {                       // grains 0..3 in fixed order
  m = i + 4*g;
  e = LDH(&fogSWOOPvales[m]);
  SWOOP_NUME(e, LDH(&fogNDNDZ[0][m]), fogSWOOPgwonz[m])  -> fogSWOOPvales[m]
  SWOOP_DENO(e, LDH(&fogNDNDZ[1][m]), &fogSWOOPgwonz[m]) -> fogSWOOPvales[m]
  h = LDH(&fogTRANGvales[m]);
  hn = LDH(&fogNDNDZ[2][m]);
  if (kind < 2) TRANGO_NUME(h, hn, fogtran bit m) else TRANSA_NUME(h, hn);  -> fogTRANGvales[m]
  hd = LDH(&fogNDNDZ[3][m]);
  if (kind == 1) hd += e;                       // swamp
  if (kind < 2) TRANGO_DENO(h, hd, fogtran bit m) else TRANSA_DENO(h, hd);
  acc += SHR(MUL(h, e));                        // grain = osc × envelope
}
acc = SAT(acc); fogVALES[i] = (int16)acc;
return MULADD(acc);
```
`TRANGO_NUME/DENO`, `TRANSA_NUME/DENO` are exactly the bodies of horn/saw in §3.2 (including `ABS`
of their parameter and the `strh` stores), applied to `h` with direction bit `fogtran[m]`.
`SWOOP_*` as in §3.4 (dirac envelope = full triangle cycle 0→d→−d→0, so grains invert phase in the
second half; arab = attack/decay). If the list ends before all 4 params, the handler returns
`SAT(old fogVALES)` and no grain is processed that sample.

### 3.7 Module 60 — `string` / `comb` / `zither` (`wanilla60karp.s`)

Shared memory: `karpBUFFA` = 16384 bytes = 4 × 4096 bytes. `string i`, `comb i`, `zither i` and
`melody i` all use the **same** 4096‑byte region `karpBUFFA + i*4096` (int16 view: 2048 samples).
`karpPLACZ[4]` uint16 (string/comb position), `karpPULSZ[4]`, `zithPULSZ[4]` int16 (excitation
envelopes), `karpNOISZ[4]` int16 (LCG, shared by string i and zither i), `karptrig` bits (shared by
string i and melody i), `zithSTRNG[4]` uint8, `zithPLACZ[16]` uint8, `zithNNNN[16]` uint8,
`zithVALES[4]` int16, `zithtrig` bits.

Excitation (string and zither): `p = rise ? 0x7F00 : (int16)PULSZ[i]; p = MUL(p, 0x7E00) >> 15;
PULSZ[i] = (int16)p;` (exponential decay ×0.984375/sample) and `n = LCG step of karpNOISZ[i]`
(stored, reloaded as int16); burst = `MUL(p, n) >> 15` (string: always asr 15; zither: `SHR`).

**string**, `i = op&3`:
```c
pos = karpPLACZ[i];
acc = LDH(&buf_i[pos]);
ARG(trig); rise = TRIG(karptrig, i, trig);
acc += burst(karpPULSZ, rise);             // MUL(p,n)>>15
COMBMEAT();
```
**comb**, `i = op&3`: `pos = karpPLACZ[i]; acc = LDH(&buf_i[pos]); ARG(inn); acc += inn; COMBMEAT();`

```c
COMBMEAT:
  ARG(nume);
  pos = karpPLACZ[i] + (A ? (int32_t)((uint32_t)nume >> 8) : (nume >> 8));
  pos = clamp(pos, 0, 2047);                 // usat #11
  karpPLACZ[i] = pos;
  ARG(deno); deno = ABS(deno);
  if ((int32_t)pos >= (int32_t)((uint32_t)deno >> 5)) pos = 0;   // loop length = deno/32 samples
  if (*cod != 0) {                           // optional feedback argument present (peeked)
    ARG(fb);
    acc += SHR(MUL(LDH(&buf_i[pos]), fb));
    acc >>= 1; acc = SAT(acc);
    buf_i[pos] = (int16)acc; karpPLACZ[i] = pos;
    return MULADD(acc);
  } else {
    acc += LDH(&buf_i[pos]);                 // feedback 1.0
    acc >>= 1; acc = SAT(acc);
    buf_i[pos] = (int16)acc; karpPLACZ[i] = pos;
    cod++;  /* the 00 */  return SAT(acc);
  }
```
So: read the sample at the old position (+ excitation/input), advance the position by `nume/256`
samples per sample (dirac: may be negative, clamped at 0), wrap at `deno/32` (max 1024 in dirac,
2047 in arab), average with fb×(old sample at the new position), write back. Note the
`fb` value is the 4th arg; `mul add` follow it — so with `mul`/`add` you must give `fb`.

**zither**, `i = op&3` (four strings per instance, round-robin plucked):
```c
acc = LDH(&zithVALES[i]);
ARG(trig);
acc = 0;
rise = TRIG(zithtrig, i, trig);
s = zithSTRNG[i]; if (rise) { s = (s + 1) & 3; zithSTRNG[i] = s; }
acc += SHR(MUL(p_zith(rise), lcg_step(karpNOISZ[i])));
m = i + 4*zithSTRNG[i];
ARG(deno);                                  // early end returns SAT(burst)
len = (uint32_t)ABS(deno) >> 8;             // 0..128 dirac, 0..255 arab
if (rise) zithNNNN[m] = (uint8)len;         // length latched for the newly plucked string
for (k = 0; k < 4; k++) {
  L = zithNNNN[m]; q = zithPLACZ[m];
  int16 *bs = (int16*)(karpBUFFA + i*4096 + (m >> 2)*1024);   // asm swaps the 2-bit fields of m
  a = LDH(&bs[q]);
  q++; if ((int32_t)q >= (int32_t)L) q = 0; zithPLACZ[m] = q;
  b = LDH(&bs[q]);
  b = SHR(MUL(b, 0x7F00)) + a; b >>= 1;     // damping 0x7F00/32768 = 0.992
  if (k == 0) { b += acc; acc = 0; }         // excitation only into the current string
  b = SAT(b); bs[q] = (int16)b;
  acc += b;
  m = (m + 4) & 15;                         // next string (current, current+1, …)
}
zithVALES[i] = (int16)acc;                  // sum of 4 strings, stored truncated
return MULADD(acc);                          // acc NOT saturated before MULADD
```
(asm: `lsr workTRI, lispMEX, 2; bfi workTRI, lispMEX, 2, 2; add workONE, workONE, workTRI, lsl 10`
→ byte offset `((m>>2) | ((m&3)<<2)) * 1024` = `i*4096 + s*1024`.)

### 3.8 Module 70 — `wave` (low-pass), `salt` (high-pass), `water` (`wanilla70philt.s`)

Chamberlin state-variable filter. State `philtBP[4]`, `philtLP[4]` int16; water uses
`waterBP[16]`, `waterLP[16]`, `waterQNQN[32]` int16, `waterVALES[4]`, `waterDROP[4]` uint8.
**QUIRK (memory overlap)**: `waterBP` and `waterLP` are only 24 bytes (12 entries) in `ramus_bss.s`
and are followed directly by `philtBP`/`philtLP` (8 bytes each). Water indices 12..15 (drop slot 3 of
instance i, `m = 12+i`) therefore **are** `philtBP[i]`/`philtLP[i]`, i.e. the filter of `wave i`/`salt i`.

Common steps (asm `PHILTRE_IDEE_QUALITE` / `_PARAM`):
```c
Q_STEP(x, q, BP):    q = ABS(q); x -= SSAT16(A ? MUL(BP, q) >> 16 : MUL(BP, q) >> 15);  // asr both
F_STEP(x, f, &BP, &LP): f = ABS(f);
    x = (A ? MUL(x, f) >> 16 : MUL(x, f) >> 15) + (int16)BP;  x = SSAT16(x);  BP = x;
    x = (MUL(x, f) >> 15) + (int16)LP;                        x = SSAT16(x);  LP = x;  // always >>15
```
(`BP`, `LP` are always loaded sign-extended and saturated signed, in both variants.)

**wave**, `i = op&3`:
```c
acc = (int16)philtLP[i];
ARG(inn); acc = inn - acc;                       // early end returns SAT(LP)
ARG(q);   Q_STEP(acc, q, (int16)philtBP[i]);
ARG(f);   F_STEP(acc, f, &philtBP[i], &philtLP[i]);   // acc = new LP
return MULADD(acc);
```
**salt**, `i = op&3`: identical, but `hp = acc` after `Q_STEP`; after `F_STEP` → `return MULADD(hp)`.
`q` is damping (bigger = less resonance), `f` is the frequency coefficient (/32768).

**water**, `i = op&3` (4 “drops” = 4 SVFs pinged round‑robin):
```c
acc = LDH(&waterVALES[i]);
ARG(trig); rise = TRIG(watertrig, i, trig);
d = waterDROP[i]; if (rise) { d = (d + 1) & 3; waterDROP[i] = d; }
acc = rise ? HIGH : 0;                            // impulse
m = i + 4*d;
ARG(q); if (rise) waterQNQN[m] = (int16)q;        // latched per drop
ARG(r); if (rise) waterQNQN[16 + m] = (int16)r;
for (k = 0; k < 4; k++) {
  lp = (int16)LP16[m];                            // LP16/BP16: see overlap note
  if (k == 0) { x = acc - lp; acc = 0; } else x = -lp;
  Q_STEP(x, LDH(&waterQNQN[m]), (int16)BP16[m]);
  F_STEP(x, LDH(&waterQNQN[16+m]), &BP16[m], &LP16[m]);
  acc += x;
  m = (m + 4) & 15;
}
waterVALES[i] = (int16)acc;
return MULADD(acc);
```

### 3.9 Module 80 — `horse` (variable-slope tri, “fourses”) (`wanilla80fourses.s`)

State `foursesVALE[4]` int16, `foursgwonz` bits. `i = op&3`, args `upnu dnnu upde dnde`:
```c
acc = LDH(&foursesVALE[i]);
ARG(un); un = ABS(un); dir = bit(foursgwonz,i);
if (dir == 1) acc += un >> 4;
ARG(dn); dn = ABS(dn);
if (dir != 1) acc -= dn >> 4;               // dir read BEFORE evaluating dn
ARG(ud);                                     // NOT abs'd
if (acc > ud) { setbit(foursgwonz,i,0); acc = ud; }          // clamp (asm: acc -= acc-ud)
ARG(dd);                                     // NOT abs'd
if (acc < dd) { setbit(foursgwonz,i,1); acc = dd; }
foursesVALE[i] = (int16)acc;                 // NB: only stored if all 4 args present
return MULADD(acc);
```

### 3.10 Module 90 — `slew`, `wheel` (`wanilla90slewhel.s`)

**slew**, `i = op&7`, state `slewVALE[8]` int16:
```c
acc = LDH(&slewVALE[i]);
ARG(inn); wor = inn;
ARG(up); up = ABS(up);
t = wor - acc;
if (t > 0) { if (t > (int32_t)((uint32_t)up >> 8)) acc += (uint32_t)up >> 8;
             slewVALE[i] = (int16)acc; }          // store happens whenever t > 0
ARG(dn); dn = ABS(dn);
t = acc - wor;
if (t > 0) { if (t > (int32_t)((uint32_t)dn >> 8)) acc -= (uint32_t)dn >> 8;
             slewVALE[i] = (int16)acc; }
return MULADD(acc);
```
(Does not snap to the target; stays within one step of it.)

**wheel**, `i = op&3` (!), state `wheelVALE[4]` int32 (integrator):
```c
acc = wheelVALE[i];
b = *cod++; if (b == 0) return acc >> 16;   // asr, both variants (asm uses .ifdef ARAB, always true)
up = clamp(value, 0, 65535); acc += up; wheelVALE[i] = acc;
b = *cod++; if (b == 0) return acc >> 16;
dn = clamp(value, 0, 65535); acc -= dn; wheelVALE[i] = acc;
acc >>= 16;                                  // asr in both variants
return MULADD(acc);
```

### 3.11 Module A0 — `gear` (counter), `pulse` (decay) (`wanillaA0pulse.s`)

**gear**, `i = op&7`, state `gearVALE[8]` (int8 in dirac / uint8 in arab):
```c
acc = (A ? (int32_t)(uint8)gearVALE[i] : (int32_t)(int8)gearVALE[i]) << 8;
ARG(trig);
if (TRIG(geartrig,i,trig)) { acc += 0x100; gearVALE[i] = (uint8)(acc >> 8); }
ARG(d); d = ABS(d);
if (acc >= d) { acc = A ? 1 : (-d) /* ~d + 1 */; gearVALE[i] = (uint8)(acc >> 8); }  // asr
return MULADD(acc);
```
Dirac: counts in steps of 256 from −d up to d−256 (2d/256 distinct values); arab: 0 .. d−256 then
back to 0 (returns 1 on the reset sample). The compare runs every sample, not only on triggers.

**pulse**, `i = op&7`, state `pulseVALE[8]`:
```c
acc = LDH(&pulseVALE[i]);
ARG(trig);
if (TRIG(pulsetrig,i,trig)) acc = HIGH;
acc = A ? clamp(acc - 8, 0, 65535) : clamp(acc - 4, 0, 32767);   // every sample
pulseVALE[i] = (int16)acc;
ARG(d); d = ABS(d);
if (acc > d) { acc = d; pulseVALE[i] = (int16)acc; }             // height cap
return MULADD(acc);
```
Linear decay 4/sample (dirac, 32764 → 0 in 8191 samples) or 8/sample (arab).

### 3.12 Module B0 — `sauce` (decimator), `salsa` (sample & hold) (`wanillaB0sauce.s`)

`SKIP` (asm `SCANETTO`): `depth = 0; do { b = *cod++; if (b==0) depth--; if (b==0xFF) depth++; }
while (depth >= 1);` — skips one element **without evaluating it** (QUIRK: if the list has already
ended, it consumes the `00` and desyncs).

**sauce**, `i = op&7`, state `sauceVALE[8]` int16, `saucePOSZ[8]` uint8:
```c
acc = LDH(&sauceVALE[i]);
ARG(per); per = ABS(per);
pos = saucePOSZ[i] + 1;
if (pos > (per >> 8)) {                      // every (per>>8)+1 samples
  saucePOSZ[i] = 0; acc = 0;
  ARG(inn); acc = inn; sauceVALE[i] = (int16)acc;
  return MULADD(acc);
} else {
  saucePOSZ[i] = (uint8)pos;
  SKIP();                                    // inn not evaluated this sample
  return MULADD(acc);                        // held value
}
```
**salsa**, `i = op&7`, state `salsaVALE[8]`:
```c
acc = LDH(&salsaVALE[i]);
ARG(trig);
if (TRIG(salsatrig,i,trig)) { acc = 0; ARG(inn); acc = inn; salsaVALE[i] = (int16)acc; return MULADD(acc); }
SKIP(); return MULADD(acc);
```

### 3.13 Module C0 — Shtar words: `melody`, `worm`, `scale`, `ladder` (`wanillaC0shtar.s`)
(Not used by any Shnth example; implement last.)

**melody**, `i = op&3`, state `meloPLACZ[4]`, `meloPULSZ[4]` uint32; byte buffer = karp region i:
```c
ptr = karpBUFFA + i*4096 + (meloPLACZ[i] >> 20);
acc = (A ? (int32)(uint8)*ptr : (int32)(int8)*ptr) << 8;
ARG(gate);  rec = gate > 0;
ARG(inn);   if (rec) { acc = inn; *ptr = (uint8)(inn >> 8); }
ARG(nume);  meloPLACZ[i] += nume;            // 12.20 fixed point position
ARG(skip);  h = clamp(skip,0,1); old = bit(karptrig,i); setbit(karptrig,i,h);
            if (old && !h) meloPULSZ[i] = meloPLACZ[i];   // falling edge: remember
            if (!old && h) meloPLACZ[i] = meloPULSZ[i];   // rising edge: jump back
return MULADD(acc);
```
**worm**, `i = op&3` (peak follower), state `wormVALES[4]`:
```c
acc = LDH(&wormVALES[i]);
ARG(inn); inn = A ? clamp(inn,0,65535) : SSAT16(inn < 0 ? -inn : inn);
if (inn > acc) acc = inn;
if (acc > 0) acc -= 1;
wormVALES[i] = (int16)acc;  return MULADD(acc);
```
**scale** (exponential pitch table): `ARG(inn)` (early end returns `SAT(caller's acc)`);
dirac: `k = clamp(inn >> 9, -64, 63) & ~1; acc = T64[k/2 + 32] >> 1` where `T64 = tarbass ++ tarball`;
arab: `k = clamp(inn >> 10, 0, 63) & ~1; acc = tarball[k/2]`. `return MULADD(acc)`.
```
tarbass = 4444 4628 4821 5022 5231 5448 5675 5911 6157 6414 6681 6959 7248 7550 7864 8192
          8532 8888 9257 9643 10044 10462 10897 11351 11823 12315 12828 13362 13918 14497 15100 15729
tarball = 16384 17065 17776 18515 19286 20088 20925 21795 22702 23647 24631 25656 26724 27836 28995 30201
          31458 32768 34131 35552 37031 38572 40177 41850 43591 45405 47295 49263 51313 53449 55673 57990
```
**ladder**, `i = op&3`, args `inn e0 e1 …`, state `ladderVALES[4]`:
```c
acc = LDH(&ladderVALES[i]);
ARG(inn); scan = (uint32_t)ABS(inn) >> (A ? 11 : 10);
start = cod; depth = 0;
while (scan != 0) {
  b = *cod++; if (b==0) depth--; if (b==0xFF) depth++;
  if (depth == 0) { scan--; if (*cod == 0) cod = start; }   // wraps around the list
}
ARG(v); acc = v; ladderVALES[i] = (int16)v;
skip to end of list (as togo);  return acc;   // unsaturated
```

### 3.14 Module D0 — rungler (no compiler word; `wanillaD0rungler.s`)

`i = op&7`, state `runglerVALES[8]` (8‑bit shift registers), `runglertrig` bits:
```c
acc = (A ? (int32)(uint8)R[i] : (int32)(int8)R[i]) << 8;
ARG(trig); rise = TRIG(runglertrig, i, trig);
ARG(data); x = clamp(data << 8, 0, 511);            // usat #9 of (data<<8)
if (rise) {
  x ^= ((acc & 0x8000) >> 7);                        // XOR with old MSB (bit 7 of byte) into bit 8
  acc = x | (acc << 1);
  R[i] = (uint8)((uint32_t)acc >> 8);                // new bit0 = (data>=1) XOR old bit7
}
return MULADD(acc);
```
(`skiftregister.txt` uses it as `(-48)` = op 0xD0 with no args → returns `SAT(R[0]<<8)`.)

### 3.15 Module E0 — `press`, `leak`, `reflect`/`return`/`and`/`xor` (`wanillaE0dynamo.s`)

**press** (compressor), `i = op&3`, state `comprSWANG[4]` int32 (16.16 envelope):
```c
acc = LDH(&comprVALE[i]);        // always 0, never written
ARG(inn); acc = inn;
ARG(att);
   atk = A ? clamp(att,0,65535)
           : (att < 0 ? -att : 0x20004338);   // QUIRK, see below
ARG(dec); dec = ABS(dec);
env = comprSWANG[i];
mag = A ? clamp(acc,0,65535) : (acc < 0 ? -acc : r6 /* QUIRK */);
if ((int32_t)mag > (env >> 16)) env = env + (atk << 4); else env = env - dec;
if ((int32_t)env < 0) env = 0;
comprSWANG[i] = env;
ARG(thr);                                   // early end returns SAT(inn)
acc = SAT(SHR(MUL(acc, thr - (env >> 16))));
return MULADD(acc);
```
QUIRK (firmware bug, dirac only): `RECTA lispWOR, lispRET` / `RECTA workTRI, lispACC` with
different source/destination registers only write the destination when the source is negative:
```asm
 .macro RECTA out, reg      ; dirac
 cmp \reg, 0
 it lt
 rsblt \out, \reg, 0
```
So for `att ≥ 0` `lispWOR` keeps the RAM address of `comprVALE` = `0x20004338` (from `VAKLORD`), and
`atk<<4` = `0x00043380` (wrapped) — a fixed, very fast attack. For `inn ≥ 0`, `workTRI` (r6) holds
whatever the last executed module left there (unpredictable). Recommended: use `mag = |inn|`
(clearly the intent) and keep the `0x43380` attack for `att ≥ 0` if you want bit-faithfulness.
Only `inforumers/MatthewAshmore.txt` uses `press`.

**leak** (DC blocker), `i = op&3`, state `likdcSWANG[4]` (32‑bit):
```c
ARG(inn); acc = inn;                         // (an early end before inn returns 0)
ARG(nu);  k = (uint32_t)ABS(nu) >> 8;
F = k << 16;
if (A == 0) { T = (int32_t)(0x80000000u - F);           // Q31 (0.5 - k/65536)
              hi = (int32_t)(((int64_t)(int32_t)S * T) >> 32); }      // smull
else        { T = (uint32_t)(0u - F);
              hi = (int32_t)(((uint64_t)(uint32_t)S * T) >> 32); }    // umull
F = MUL(inn, k) + hi;
S_new = A ? F : (F << 1);  likdcSWANG[i] = S_new;
dc = SAT(SHR(F));
acc = SAT(inn - dc);
return MULADD(acc);
```
Steady state `dc ≈ inn` (S ≈ 65536·inn), coefficient ≈ k/32768 (dirac) or k/65536 (arab).
QUIRK: `nu < 256` gives k=0 → dirac T = −2³¹ (sign flipping state), arab T = 0.

**reflect / return / and / xor** (`op&3` = 0/1/2/3; no state):
```c
ARG(inn);  // early end returns SAT(caller's acc)
acc = inn;
ARG(oth);  // early end returns SAT(inn)
switch (op & 3) {
case 0: /* reflect */ r = ABS(oth);
  if (A == 0) {
    q = r ? acc / r : 0;                      // sdiv, trunc toward 0; /0 = 0 on Cortex-M3
    if (q == 0) { acc = acc - (r ? (acc / r) * r : 0); break; }   // (= acc)
    if (q < 0) t = MUL(q - 1, r); else { q += 1; t = MUL(q, r); }
    acc = (q & 2) ? t - acc : acc - t;
  } else {
    q = r ? (uint32_t)acc / (uint32_t)r : 0;  // udiv
    t = MUL(q, r);
    acc = (q & 1) ? t - acc : acc - t;
  }
  break;
case 1: /* return (modulo) */ r = ABS(oth);
  q = r ? (A ? (uint32_t)acc / (uint32_t)r : acc / r) : 0;
  acc -= MUL(q, r); break;
case 2: acc &= oth; break;                    // raw 32-bit values
case 3: acc ^= oth; break;
}
return MULADD(acc);
```

### 3.16 Module F0 — outputs and utilities (`wanillaF0nuts.s`)

Note the swap (`@july nin 13 reverse RITE LEFT!`): the word **`left` accumulates into r11
(`dacRITE`, written to DAC channel 2)** and **`right` into r10 (`dacLEFT`, DAC channel 1)**. Which DAC
channel is physically the left jack is **UNCLEAR** from code; the comment indicates the swap was made
so that the words match the jacks. Recommendation: treat word `left` → left output, `right` → right
output, and `pan` positive place → the `right`-word channel (see below).

**left (F0) / right (F1)**: `acc = OUT; for each arg v: OUT += v; acc = OUT;` → returns
`SAT(OUT)` (the running channel sum). Any number of args. `OUT` is a plain 32‑bit sum (no clipping)
until the DAC stage.

**square (F2)** (also `negwon` = `(square)` with no args):
```c
acc = A ? 0xFF00 : -256;
ARG(inn);  wor = inn;  acc = (inn > 0) ? HIGH : 0;
ARG(ref);  acc = (wor > ref) ? HIGH : 0;
return MULADD(acc);
```
(`(negwon)` → −256 dirac / 65280 arab = literal −1. `(square x)` → 32767 if x>0 else 0.)

**modo (F3)**: `acc = 0; ARG(inn); acc = inn; ARG(mod); acc = MUL(inn, mod >> 8); return MULADD(acc);`
(integer multiply by the literal value; `mod >> 8` is asr in both variants).

**srate (F4)**:
```c
bit = !bit(jumpsrattrig,0); setbit(jumpsrattrig,0,bit);   // toggles every call
acc = bit << (A ? 16 : 15);                               // returned (SAT) when args end
wor = 0;
for each arg v: { wor += v; if (wor <= 0) wor = 1 - wor; SYSTICK_RELOAD = wor; }
```
Sample rate = 72 MHz / (RELOAD + 1). `(srate 18)` → 4608 → 15 621 Hz. See §5.

**mul (F5)**: `acc = 0; ARG(inn); acc = inn; return MULADD(acc);`

**add (F6)**: `acc = 0; ARG(v); acc = v; for each further arg: acc = SAT(acc + v);` return `SAT(acc)`.

**tar (F7)**: `acc = (GPIOA_IDR & 2) ? HIGH : 0; return MULADD(acc);` (PA1).

**bend (F8)**: for each arg v: `acc = witch + (int8)(v >> 8); witch = (uint8)acc;` — adds to the
preset index **every sample** while evaluated. Returns `SAT(acc)` (with no args: `SAT(caller's acc)`).
The new preset is used from the next sample (`witch > vexamt` → 0).

**jump (F9)**:
```c
acc = 0;
while (*cod != 0) { ARG(v); acc += v; }           // sum of args
level = (acc != 0);                                // ANY nonzero, incl. negative (TRIG_IDEE_PRIMITIF)
old = bit(jumpsrattrig,1); setbit(jumpsrattrig,1,level);
if (level && !old) {
  w = witch + (int8)(acc >> 8);                    // 32-bit
  if (w < 0) w = vexamt;                           // wrap downwards to last preset
  witch = (uint8)w;                                // > vexamt is wrapped to 0 next sample
  LEDS = (w << 8) & 0xFF00;                        // GPIOC_ODR = w<<8
  cod++;  return SAT(w);
}
cod++; return SAT(acc);
```
`(jump (tar 1))` → next preset on each tar press; `(jump (minor 1))` likewise with button minor.

**pan (FA)**, pairs `inn place …`:
```c
for each pair: { ARG(inn); acc = inn; ARG(pl);
  w = clamp(pl, 0, 32767);                         OUT_right_word += SHR(MUL(inn, w));  // r10
  w = clamp(A ? 0x10000 - pl : -pl, 0, 32767);     OUT_left_word  += SHR(MUL(inn, w));  // r11
}  // returns SAT(acc) (= last inn) when the list ends
```
Dirac: place > 0 → `right`-word channel, place < 0 → `left`-word channel, **place = 0 → silent**.
Arab: place 0..32767 → both (`0x10000-pl` ≥ 32768 is clamped), place ≥ 32768 → `right`-word only.

**short (FB)**: `ARG(b); acc = b; ARG(s); acc += A ? ((uint32_t)s >> 8) : (s >> 8);`
then the next arg is read and ignored, and the cycle restarts (`acc = next arg`, …). With literals:
`(short 30 55)` = 30·256 + 55 = 7735.

**dirac (FC) / arab (FD)**: §2.5.

**lights (FE, FF)**: `acc = 0; for each arg: acc += v; LEDS = acc (low 16 bits written to GPIOC_ODR,
LEDs are PC8..PC15 = bits 8..15);` returns `SAT(acc)`.

---------------------------------------------------------------------------------------------------

## 4. Inputs

All inputs are sampled by other interrupts **between** audio samples (same NVIC priority as SysTick,
so no preemption). Clocks (`initiate.s`): HSE 8 MHz × 9 = 72 MHz, APB1 36 MHz, APB2 4.5 MHz,
ADC clock 562.5 kHz.

### 4.1 Bars (`bar`..`bard`, op 04–07) — `vectorADC.s`

ADC1: regular sequence = channel 2 (PA2, reference), continuous (`ADC1_CR2 = 3`), injected sequence
with JAUTO (`ADC1_CR1 = 0x580`: SCAN|JAUTO|JEOCIE) = channels 10,11,12,13 (PC0..PC3) →
`ADC1_JSQR = 0x0036B16A` (JL=3, JSQ1..4 = 10,11,12,13) → `barres[0..3]`. Sample time 41.5 cycles
each (`SMPR1/2` field `100`), so one regular+4 injected conversions = 5 × 54 = 270 ADC cycles →
**JEOC interrupt ≈ 2083 Hz**. In the ISR the injected offsets are set to the latest regular value:
`JOFR1..4 = ADC1_DR` (channel 2). So each `JDRk = ch(10+k) − ch2` (signed, from the previous offset).

Per ISR, for k = 0..3 (`JADERPHILTE`):
```c
x  = (int16)JDRk;                     // ≈ -4095..4095
dz = x - clamp(x, -16, 15);           // dead zone: |x| < ~16 -> 0  (ssat #5)
barres[k] = SSAT16((barres[k] * 14 + (dz << 6)) >> 4);
```
→ one-pole smoothing (×0.875 per ISR, τ ≈ 3.6 ms); steady state `bar = 32·dz`, saturating at
±32767 for |dz| ≥ 1024 counts. Bipolar (bars are flex sensors: bend either way). For the ESP32:
produce `barres` in −32768..32767 with 0 at rest, and apply the same filter at ~2 kHz (or the
equivalent per-sample coefficient).

### 4.2 Antennae (`corp`, `corpb`, op 02/03) — `vectorTimer.s` + `initiate.s`

TIM2 (antenna a, external clock ETR = PA0) and TIM3 (antenna b, ETR = PD2) count oscillator edges
(`SMCR = 0x4004`: ECE external clock mode 2 + slave reset mode on ITR0), are reset by TIM1’s TRGO and
capture the count on TRGO’s falling edge (`CCMR1 = 0x03`: IC1 ← TRC; `CCER = 0x3`). TIM1:
`PSC = 4`, ARR = 0xFFFF, `CCR1 = 0xFFFD`, PWM1 on OC1REF → TRGO. Timer clock 9 MHz /5 = 1.8 MHz →
gate ≈ 36.4 ms (**~27.5 Hz**; the source comment says 17.58 Hz — UNCLEAR which is real). Each capture
interrupt (TIM2 and TIM3 share the handler; both run it, so it probably executes twice per gate)
does, for p = 0,1 (`TIMPHILTE`):
```c
cap = TIMx_CCR1;                                  // 16-bit count
if (GPIOA_IDR & 2) tare[p] = cap;                 // tar button held => re-tare (zero) antennas
d = (int32_t)cap - (int32_t)tare[p];
chinkwonks[p] = SSAT16(((int16)chinkwonks[p] + (d << 6)) >> 1);
```
So `corp` ≈ 64 × (count change since tare), saturating at ±32767 (≈ ±512 counts), 0 after tare,
smoothed. The tare is **not initialised at boot** (RAM < 0x20), so the user presses tar. Sign of a
touch (count up or down) is **UNCLEAR** (depends on the oscillator circuit). For the ESP32: deliver a
signed 16‑bit value, 0 when untouched, growing with touch; zero it while `tar` is held.

### 4.3 Microphone (`wind`, op 01)

ADC2 continuous on channel 3 (PA3), 13.5‑cycle sample time (≈21.6 kHz conversions, comment says
41.666 kHz). `wind` reads the latest `ADC2_DR − ADC1_DR` (mic minus the channel‑2 reference),
`<< 4` → ±65520 (then `SAT` on return). No filtering.

### 4.4 Buttons

`minor`..`minord`: PA6..PA9; `major`..`majord`: PC4..PC7; `tar`: PA1 (also re-tares the antennas).
Read directly from GPIO each time the word is evaluated. Pin high = on (→ `HIGH`).

### 4.5 LEDs

8 LEDs on PC8..PC15 (`GPIOC_CRH = 0x22222222`). Written by `lights` (bits 8..15 of the sum), by `jump`
when it fires (`witch << 8`, i.e. preset number in binary), and all-on after USB programming.

---------------------------------------------------------------------------------------------------

## 5. Output and sample rate

* SysTick, CPU clock 72 MHz (`CSR = 7`: core clock, interrupt, enabled). During the ISR the
  interrupt is disabled (`CSR = 5`) but the counter keeps running, so the period is
  `RELOAD + 1` cycles as long as the patch finishes in time.
* Each ISR first sets `RELOAD = 0x1000` (default **72e6/4097 = 17 574 Hz**), then the patch may
  overwrite it with `srate` (`RELOAD = wor`, `wor ≥ 1`). The new RELOAD takes effect from the
  next counter wrap, i.e. one sample later. Boot value 0x500 is irrelevant.
* If the patch takes longer than the period, wraps are missed (no interrupt while disabled) and the
  effective period becomes a multiple of `RELOAD+1` ⇒ very small srate values (e.g. `newhorse.txt`
  `(srate 3)` = 768 → nominal 93.6 kHz) are in practice **CPU-bound** at a rate that depends on patch
  cost on the STM32 (**UNCLEAR**, not computable from the code alone). Suggested ESP32 behaviour: run
  at `fs = 72e6/(RELOAD+1)` but cap it (e.g. ≤ 48 kHz or a per-patch estimate); or render at a fixed
  hardware rate and resample from the virtual rate.
  Typical values in examples: 18 → 15.6 kHz, 30 → 9.4 kHz, `(short 30 55)` → 9.3 kHz.
* DAC: STM32 12‑bit DAC, both channels enabled without trigger (`DAC_CR = 0x00010001`), written at the
  start of the next ISR (one‑sample latency, jitter‑free):
  `code = clamp(sum >> 4, -2048, 2047) + 2048` (`ssat r,#12,r,asr #4; add #0x800`).
  So a single full-scale voice (±32767) is full DAC scale; sums clip hard. To be faithful on a 16‑bit
  codec: `out16 = clamp(sum >> 4, -2048, 2047) << 4`.
* Channels: word `left` → r11 → DAC ch2 (PA5); word `right` → r10 → DAC ch1 (PA4) (see §3.16).

---------------------------------------------------------------------------------------------------

## 6. RAM / state layout and size

Exact firmware layout (`ramus_bss.s`, base `0x20000000`, no padding). Bit arrays are accessed through
the Cortex‑M3 bit-band alias, i.e. “bit i of byte X” = `(ram[X + i/8] >> (i%8)) & 1` (instances
0..7 use one byte; `fogtran` uses bits 0..15).

```
0x0000 witch_vectore u8          (preset index; NOT zeroed at boot)
0x0001..0x001B USB bookkeeping
0x001C chinkwonkTARESZ u16[2]    (antenna tare; NOT zeroed)
0x0020 barres i16[4]   0x0028 chinkwonks i16[2]   0x002C mike(unused)
0x002E trangwonz  0x002F togouptrig 0x0030 togodntrig 0x0031 togltrig 0x0032 toglvals
0x0033 swooptrig  0x0034 lfogwonz   0x0035 fogtrig    0x0036 fogtran(u32 bits)
0x003A karptrig   0x003B zithtrig   0x003C watertrig  0x003D foursgwonz 0x003E rectrig(unused)
0x003F geartrig   0x0040 pulsetrig  0x0041 salsatrig  0x0042 runglertrig 0x0043 jumpsrattrig
0x0044 trangoes i16[8]  0x0054 transaws i16[8]  0x0064 togoesPLACZ u8[8]  0x006C togoesVALES i16[8]
0x007C swoopVALES i16[8] 0x008C swoopGWONZ u8[8] 0x0094 mountVALES i32[8]
0x00B4 noiseVALES[8] 0x00C4 dustVALES[8] 0x00D4 dustRAMPS[8]
0x00E4 fogVALES[4] 0x00EC fogPLACZ u8[4] 0x00F0 fogNDNDZ i16[4][16] 0x0170 fogSWOOPgwonz u8[16]
0x0180 fogSWOOPvales i16[16] 0x01A0 fogTRANGvales i16[16]
0x01C0 karpBUFFA 16384 bytes (4 × 4096; shared by string/comb/zither/melody instance i)
0x41C0 zithNNNN u8[16] 0x41D0 zithSTRNG u8[4] 0x41D4 zithPLACZ u8[16] 0x41E4 karpPLACZ u16[4]
0x41EC zithPULSZ[4] 0x41F4 karpPULSZ[4] 0x41FC karpNOISZ[4] 0x4204 zithVALES(=karpVALES)[4]
0x420C waterQNQN i16[32] 0x424C waterVALES[4] 0x4254 waterDROP u8[4]
0x4258 waterBP i16[12] 0x4270 philtBP i16[4]   ← waterBP[12..15] == philtBP[0..3]
0x4278 waterLP i16[12] 0x4290 philtLP i16[4]   ← waterLP[12..15] == philtLP[0..3]
0x4298 foursesVALE[4] 0x42A0 slewVALE[8] 0x42B0 wheelVALE i32[4] 0x42C0 gearVALE u8[8]
0x42C8 pulseVALE[8] 0x42D8 sauceVALE[8] 0x42E8 saucePOSZ u8[8] 0x42F0 salsaVALE[8]
0x4300 meloPLACZ u32[4] 0x4310 meloPULSZ u32[4] 0x4320 wormVALES[4] 0x4328 ladderVALES[4]
0x4330 runglerVALES u8[8] 0x4338 comprVALE[4] 0x4340 comprSWANG i32[4]
0x4350 wavVALE(unused) 0x4358 likdcVALE[4] 0x4360 likdcSWANG u32[4]
end 0x4370
```
**Total engine state ≈ 17.2 KB (0x4370 = 17 264 bytes), of which 16 KB is the string/zither delay
memory.** Everything else is ~880 bytes. The program image is typically 100 B – 4 KB (max 64 KB).
Stack: recursion depth = expression nesting depth (each level ≈ 16 bytes on the STM32; budget a few
hundred bytes in C).

Recommendation: implement the state as one `uint8_t ram[0x4370]` (little endian, like the STM32)
with these offsets and typed accessors. This reproduces every aliasing quirk for free (water↔wave,
karp↔zither↔melody, karptrig↔melody, shared LCG) and the `press` address constant.
All of it fits comfortably in 20 KB; if you must save RAM, `karpBUFFA` can only be shrunk by
dropping instances (each string/zither instance needs its full 4 KB).

---------------------------------------------------------------------------------------------------

## 7. Which words each example needs, and implementation order

Base words (instance letters stripped; `square|negwon` = op 0xF2, which also appears whenever the
number −1/255 is written; `const0` = the literal 0 = op 0x00; “computed op” = list in opcode
position). Generated by compiling each file with the repo’s shlisp and walking the bytecode.

- `beachlanterns.txt` (2 presets): arab, dust, fog, jump, left, mount, right, smoke, srate, tar, wave
- `dubotogo.txt` (5): (computed op), and, arab, bar, corp, horn, jump, left, lights, minor, mount, reflect, return, right, sauce, string, xor
- `duncan.txt` (4): bar, comb, corp, dust, fog, horn, jump, left, minor, right, smoke, wave, wind
- `inforumers/DaveSeidel.txt` (10): add, and, arab, bar, comb, corp, horn, jump, left, lights, major, minor, modo, mount, mul, square|negwon, pan, right, salt, sauce, saw, short, slew, srate, tar, toggle, water, wave, wind, xor
- `inforumers/MatthewAshmore.txt` (28): (computed op), add, and, arab, bar, comb, const0, corp, dust, fog, haze, horn, horse, jump, leak, left, lights, major, minor, modo, mount, mul, square|negwon, pan, press, reflect, right, salsa, salt, sauce, saw, short, slew, smoke, srate, string, swamp, swoop, togo, water, wave, wheel, xor, zither
- `inforumers/jesse.txt` (10): (computed op), bar, corp, jump, left, lights, major, minor, square|negwon, return, right, salt, sauce, short, srate, string, swoop, tar, togo, wave, wheel, zither
- `inforumers/khzmhz.txt` (69): (computed op), add, and, arab, bar, comb, const0, corp, dust, fog, haze, horn, horse, jump, left, lights, major, minor, modo, mount, mul, square|negwon, pan, reflect, return, right, salsa, salt, sauce, saw, short, slew, smoke, srate, string, swamp, swoop, tar, toggle, togo, water, wave, wheel, wind, xor, zither
- `inforumers/kozeoz.txt` (1): (computed op), bar, const0, corp, dust, haze, left, square|negwon, salsa, sauce, string, water, wind
- `inforumers/mengqi.txt` (5): add, and, arab, bar, const0, corp, dust, fog, horn, horse, left, lights, major, minor, mul, square|negwon, right, salt, sauce, short, slew, smoke, srate, swoop, toggle, togo, wave, wind, xor, zither
- `inforumers/notb.txt` (6): add, bar, bend, const0, corp, horn, horse, jump, left, lights, major, minor, modo, mount, mul, square|negwon, right, short, slew, smoke, srate, togo, wave, wind, zither
- `inforumers/rodrigo.txt` (4): bar, corp, horn, horse, left, lights, major, minor, mount, pan, right, saw, slew, srate, wind
- `inforumers/rovadams.txt` (2): bar, corp, horn, jump, left, minor, right, slew, wheel
- `inforumers/skiftregister.txt` (16): (computed op), add, bar, bend, comb, corp, dirac, dust, horn, jump, left, lights, major, minor, modo, mount, mul, square|negwon, pan, pulse, right, rungler(0xD0, by number), salsa, salt, sauce, saw, short, slew, smoke, srate, string, swoop, togo, water, wave, wheel, xor, zither
- `inforumers/stevek.txt` (15): add, arab, bar, comb, const0, corp, dust, horn, horse, jump, leak, left, lights, major, minor, modo, mount, mul, square|negwon, pan, pulse, right, salsa, salt, sauce, saw, short, slew, smoke, srate, string, swoop, tar, toggle, togo, water, wave, zither
- `inforumers/wednesdayayay.txt` (10): add, bar, comb, const0, corp, dust, fog, gear, haze, horn, left, major, mount, mul, square|negwon, pan, pulse, reflect, return, right, salsa, short, slew, smoke, srate, string, swamp, toggle, togo, water, wave, zither
- `inforumers/windspirit.txt` (1): add, arab, bar, const0, corp, horn, left, square|negwon
- `monreal.txt` (8): add, arab, bar, comb, corp, dust, haze, horn, jump, left, lights, minor, mul, square|negwon, right, short, smoke, srate, string, swamp, togo, wave
- `newSHNTH/ZORNO.txt` (2): bar, const0, corp, horn, left, minor, square|negwon, srate, tar, wave
- `newSHNTH/dooner.txt` (9): add, arab, bar, comb, corp, dust, fog, horn, horse, jump, left, lights, major, minor, modo, mount, mul, square|negwon, pan, right, salsa, saw, slew, smoke, srate, string, swamp, swoop, toggle, togo, wave
- `newSHNTH/kingheadAUTOPLAZ.txt` (10): bar, corp, dust, gear, horn, jump, left, major, minor, modo, mount, pulse, right, sauce, saw, slew, smoke, srate, toggle, togo, wave   (uses compile-time `<~ 56>`)
- `newSHNTH/kingheadFINALIS.txt` (10): bar, corp, dust, gear, horn, jump, left, major, minor, modo, mount, pulse, right, sauce, saw, slew, smoke, srate, toggle, togo, wave
- `newSHNTH/misophonia711.txt` (8): bar, corp, dust, fog, haze, horn, jump, left, lights, major, minor, mul, square|negwon, right, salsa, salt, saw, short, smoke, srate, swamp, wave
- `newSHNTH/neilYOUNG.txt` (1): bar, const0, dust, horn, left, major, mount, mul, square|negwon, right, saw, slew, smoke, srate, togo, wave, wind
- `newSHNTH/resist1.txt` (1): arab, bar, dust, fog, horn, left, major, minor, right, saw, smoke, srate, swoop, toggle, togo
- `newSHNTH/sidraxEMULATIONS.txt` (5): bar, corp, horn, jump, major, minor, pan
- `newSHNTH/tokyoTRAINS.txt` (7): bar, comb, const0, corp, dust, fog, gear, horn, jump, left, major, minor, mount, square|negwon, pulse, right, salsa, saw, slew, smoke, srate, string, wave
- `newSHNTH/trainsANDdrax.txt` (13): bar, comb, const0, corp, dust, fog, gear, horn, jump, left, major, minor, mount, mul, square|negwon, pan, pulse, right, salsa, saw, slew, smoke, srate, string, togo, wave, wind
- `newSHNTH/trainsofTOKYO.txt` (8): bar, comb, const0, corp, dust, fog, gear, horn, jump, left, major, minor, mount, mul, square|negwon, pulse, right, salsa, saw, slew, smoke, srate, string, togo, wave, wind
- `newhorse.txt` (4): corp, horse, jump, left, minor, right, srate
- `plumbutter.txt` (2): (computed op), arab, corp, dust, fog, horn, jump, left, lights, major, minor, mount, mul, square|negwon, right, salsa, sauce, smoke, srate, string, toggle, water, wave
- `seventee.txt` (7): add, bar, horn, jump, left, lights, major, minor, modo, square|negwon, right, saw, slew, srate, togo
- `slv.txt` (4): bar, corp, fog, gear, horn, left, square|negwon, pulse, right, srate, swamp, water, zither
- `vancouver.txt` (6): add, arab, bar, const0, corp, dust, fog, horn, jump, left, lights, minor, modo, mul, square|negwon, pan, reflect, right, salsa, sauce, saw, slew, smoke, srate, string, swoop, toggle, togo, wave, wheel
- `wraissed.txt` (15): bar, comb, const0, corp, dust, fog, horn, jump, left, lights, major, minor, mount, square|negwon, pan, reflect, right, salsa, salt, sauce, saw, slew, smoke, srate, swamp, togo, water, wave, wind, zither
- `zhongwen.txt` (9): (computed op), add, arab, bar, corp, horn, horse, jump, left, lights, major, minor, modo, mount, mul, square|negwon, pan, right, salt, saw, smoke, srate, string, togo, water, wave, zither
- `dubot` (5, no extension; same family as dubotogo): (computed op), and, arab, bar, corp, horn, jump, left, lights, minor, mount, reflect, return, right, sauce, string, xor

Files (of 36) using each word: left 35, bar 33, right 32, corp 32, horn 32, minor 30, srate 29,
jump 27, wave 25, square|negwon 25, major 24, smoke 23, dust 23, mount 21, slew 20, togo 20,
lights 19, saw 19, string 17, fog 16, mul 16, const0 16, arab 15, sauce 15, add 14, salsa 14,
comb 13, pan 13, wind 11, water 11, short 11, toggle 11, modo 11, zither 11, salt 10,
(computed op) 9, horse 9, swoop 9, pulse 9, swamp 8, reflect 7, xor 7, gear 7, tar 6, and 6,
wheel 6, haze 6, return 5, leak 2, bend 2, press 1, dirac 1, rungler 1.
(melody, worm, scale, ladder: 0.)

### Implementation order

1. **Core** (needed by everything): image/preset loader, `sexpr` + computed opcodes, literal
   decoding, `MULADD`/`SQUISH`, `SAT`, dirac/arab variants, `lispSIN` handling, DAC stage,
   `srate`, `jump`, `lights`, const0.
   Words: `left right srate jump lights tar bar corp minor major wind horn saw square/negwon mul add
   short modo arab dirac smoke dust mount swoop wave salt togo toggle slew`.
   Plays: `windspirit`, `ZORNO`, `neilYOUNG`, `seventee`.
2. **Second wave**: `fog swamp haze string comb zither sauce salsa pan water horse pulse gear
   reflect return and xor wheel bend` → plays every example except the 3 below.
3. **Rare**: `leak` (stevek, MatthewAshmore), `press` (MatthewAshmore), rungler 0xD0
   (skiftregister), then Shtar words `melody worm scale ladder` (unused).

---------------------------------------------------------------------------------------------------

## 8. Checklist of quirks to reproduce (or consciously drop)

1. Early list end = immediate return of `SAT(acc)` at that point; later state updates are skipped.
2. Return values: saturated to 16 bits, except `dirac`/`arab` (raw sum), `togo`/`ladder` (selected
   value unsaturated), `toggle` without args (`acc<<15` = 32768), `wheel` early ends (`acc>>16`),
   op 00 (0).
3. Literal 0 is `FF 00`; integers ≡ 0 mod 256 (≠0) compile to a terminating `00` (compiler bug);
   integers ≡ 255 mod 256 compile to `(negwon)`.
4. Instance aliasing: `wave e..h` = `wave a..d`; `wheel e..h` = `a..d`; `wave i`/`salt i` share a filter;
   `water` drop 3 shares that filter too; `string i`/`comb i`/`zither i`/`melody i` share 4 KB of delay
   memory; `string i`/`melody i` share a trigger bit; `string i`/`zither i` share the noise LCG.
5. Unevaluated elements (`togo`, `ladder`, `sauce`, `salsa`) do not advance their state.
6. Same instance used twice per sample is stepped twice (common in patches; it changes pitch).
7. `bend` changes the preset every sample while evaluated; `jump` triggers on any nonzero sum.
8. `press` dirac uses an address constant (0x20004338 → attack 0x43380) and an uninitialised register.
9. Opcodes 0xD8–0xDF fall into dirac `press`.
10. `left` word → DAC ch2, `right` word → DAC ch1, `pan` place>0 → `right`-word channel, place 0 silent.
11. State is never reset on preset change; all state zero at power-up (except preset index and antenna
    tare).
12. Division by zero (`reflect`/`return`) yields quotient 0.

---------------------------------------------------------------------------------------------------

## Appendix A — C skeleton of the core

```c
#include <stdint.h>
static const uint8_t *img;      // uploaded image
static const uint8_t *cod;      // read pointer
static int sin_;                // lispSIN
static int32_t outA, outB;      // outA: `right`+pan>0 (r10, DAC1); outB: `left`+pan<0 (r11, DAC2)
static uint8_t witch;           // preset index
static uint32_t reload;         // SYSTICK reload

typedef int32_t (*Handler)(uint32_t op, int A);
extern Handler table[64];       // index (op>>2)&63; each handler implements both variants

static inline int32_t SATv(int A, int32_t x){ return A ? (x<0?0:x>65535?65535:x)
                                                       : (x<-32768?-32768:x>32767?32767:x); }
static inline int32_t MUL(int32_t a,int32_t b){ return (int32_t)((uint32_t)a*(uint32_t)b); }

int32_t sexpr(void){
  uint8_t b = *cod++;
  uint32_t op = (b != 0xFF) ? b : (((uint32_t)sexpr() >> 8) & 0xFF);
  if ((op & 0xF8) == 0xD8) return table[0xE0>>2](op, 0);   // empty slots slide into dirac press
  return table[op >> 2](op, sin_);
}

/* argument fetch: returns 0 at end of list (byte 00 consumed) */
static inline int next(int A, int32_t *v){
  uint8_t b = *cod++;
  if (b == 0) return 0;
  *v = (b != 0xFF) ? (A ? (int32_t)(b << 8) : (int32_t)(int16_t)(b << 8)) : sexpr();
  return 1;
}
#define ARG(v)  do { if (!next(A, &(v))) return SATv(A, acc); } while (0)

static int32_t muladd(int A, int32_t acc){
  int32_t r;
  for (;;) {
    ARG(r); acc = A ? (int32_t)((uint32_t)MUL(acc, r) >> 16) : (MUL(acc, r) >> 15);
    ARG(r); acc += r;
  }
}

/* example handler: horn (ops 0x10..0x17); TRANSA for 0x18..0x1F in the same slot pair */
static int32_t h_horn(uint32_t op, int A){
  int i = op & 7; int32_t acc = A ? (int32_t)ram_u16(TRANGOES + 2*i) : (int32_t)ram_i16(TRANGOES + 2*i);
  int32_t n, d, t;
  ARG(n); n = ABSv(A, n);
  if (getbit(TRANGWONZ, i)) acc += n >> 4; else acc -= n >> 4;
  ram_w16(TRANGOES + 2*i, acc);
  ARG(d); d = ABSv(A, d);
  int32_t before = acc;
  t = acc - d;
  if (acc > d) { setbit(TRANGWONZ, i, 0); acc -= 2*t; ram_w16(TRANGOES + 2*i, acc); }
  int lt;
  if (!A) { lt = ((int64_t)acc + d) < 0; t = acc + d; }
  else    { int v = (((before ^ d) & (before ^ (before - d))) >> 31) & 1;   // V of subs
            lt = (acc < 0) ^ v; t = acc; }
  if (lt) { setbit(TRANGWONZ, i, 1); acc -= 2*t; ram_w16(TRANGOES + 2*i, acc); }
  return muladd(A, acc);
}

void audio_tick(void){                     // call at fs = 72e6/(reload+1)
  dac_write(clamp12(outB >> 4), clamp12(outA >> 4));   // left-word channel, right-word channel
  outA = outB = 0; reload = 0x1000; sin_ = 0;
  uint8_t vex = img[1];
  if (witch > vex) witch = 0;
  cod = witch ? img + (img[2*witch] | img[2*witch+1] << 8) : img + 2*vex + 2;
  for (;;) { uint8_t b = *cod++; if (!b) break; if (b == 0xFF) sexpr(); }
}
```
(`dac_write` with the previous sample’s sums reproduces the one-sample latency; `clamp12(x)` =
`clamp(x,-2048,2047)`.)
