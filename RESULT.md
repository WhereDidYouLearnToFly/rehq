> **Historical document — do not read as a description of the current tree.**
>
> This is the analysis of the *pre-refactor* sources, kept for the reasoning
> behind the changes that followed. Much of what it describes no longer exists:
> `sys/memmap.i`, `sys/game.asm`, `core/sfx/beeper.asm`, `data/*.asm`,
> `macros/` and `test.asm` have all gone, and the tree is now a git repository.
>
> Spot-checking the "Bugs, worst first" list against the current sources: the
> `adc hl` / `rla` sweeps are done (the remaining `rla`s are in `core/zx0.asm`,
> where they are the bit reader and correct), `Panel8x8` / `Panel16x16` now use
> `BLOCK 8` / `BLOCK 32`, `draw_panel` stores its own arguments, every module in
> `core/` uses `MODULE`, Kempston input is implemented, and the RNG seed is a
> full word. The identifiers this document says to rename were renamed again
> during the refactor — `core/math.asm` is the authority, not the names here.
>
> Do not treat any individual item below as still-open without re-checking it
> against the file it names; the line numbers are all stale.

# re_hq — Code Analysis

Review of the Z80 / ZX Spectrum engine sources in this tree (`core/`, `data/`, `sys/`).
Build output (`out/`, `test.sna`, `test.sld`, `assets_generated.asm`) was not examined.
`core/zx0.asm` was not reviewed — assumed to be the stock ZX0 decompressor.

---

## What's here

A generic engine base — a set of reusable modules, no game layer on top yet.

| Module | Contents | State |
|---|---|---|
| `core/gfx/screen.asm` | char→screen and char→attribute address helpers, 192-entry pixel-line address table, ROM `cls`, stack-based pixel clear (`ld sp,$5800` + `push`), attribute fill | Works; two missing `ret`s |
| `core/gfx/draw_display.asm` | module `display` — `get_scaddr`, `draw_8x8` sprite blit, `draw8x8_panel` 3×3 frame drawer, `put_img_desized` arbitrary-size blit | `draw_8x8` correct; panel drawer broken, never called |
| `core/gfx/draw_attribs.asm` | six attribute wipes (centre↔side, left↔right, top↔bottom), `load_attribs`, `fill_rectangle`, self-modifying direct/reverse fill | Wipes work; both fill routines have a y==0 bug |
| `core/gfx/draw_text.asm` | ROM-channel printing, teletype printer with blinking cursor and line wrap, multiline variant, `running_line_1pix` scroller, self-contained pixel font printer | Works; depends on shared temps it doesn't own |
| `core/input.asm` | runtime control-scheme selection (Interface 2 / QAOP+Space), press/release edge detection | Interface 2 path has two bugs; Kempston is a stub |
| `core/interrupt.asm` | IM1 and IM2 setup, IM2 handler with full register save, chains to ROM `$0038` | Vector table collides with `Attributes` |
| `core/math.asm` | 8×8→16 multiply, ROM-walking RNG, shared temp storage | Works; RNG seed is half-initialised |
| `core/sfx/beeper.asm` | click and long beep via ROM, self-modifying enable/disable | Works |
| `core/zx0.asm` | ZX0 decompressor | Not reviewed |
| `sys/memmap.i` | fixed module address map | Sizes stale, no enforcement |
| `sys/zxspectrum.i` | ROM entry points and system variable equs | Fine |
| `data/*.asm` | `includebin` wrappers | Two dangling asset paths |

Routines with no caller anywhere in the tree: `draw8x8_panel`, `load_attribs`, `fill_rectangle`,
all six attribute wipes, `check_kempston`, `Math.RandomToA`.

Things worth keeping as-is:

- `screen.clear_pixels` — the stack-blitter is a good trick and the `ld (.stack+1),sp` save/restore
  around it is correct.
- The address arithmetic in `draw_8x8` is **right** in all three cases — the `+1` normal step, the
  `+32` third-crossing, and the `$F91F` negative-add for the character-row straddle. (The
  `next_seg` comment says "30 bytes"; the code does 32, and 32 is correct.)
- `update_state` in `input.asm` — the `xor`/`and` pair for down-edge and up-edge detection is clean.

---

## Bugs, worst first

### 1. `Attributes` sits inside the IM2 vector table

- `sys/memmap.i:18` — `Attributes equ $82B0`
- `core/interrupt.asm:61-62` — `im2table` is `org $8200` / `defs 257`, i.e. `$8200–$8300`

`interrupt.init_im2`'s `ldir` fills that whole range with `$81` at runtime, wiping the first
~80 bytes of `draw_attribs.asm`. The memmap comment (`; 81A3 - 0101 Int vector`) is stale — it
was written for a table at `$81A3`, not `$8200`.

**Fix:** move `im2table` to a free 256-byte-aligned page, or relocate `Attributes`.

### 2. `adc hl,rr` used everywhere `add hl,rr` was meant

Carry is whatever the caller left behind, so every one of these is randomly off by one. In tight
loops the first `adc` inherits garbage and later iterations self-clear, which is why it usually
*looks* fine.

- `core/gfx/draw_display.asm:61, 68, 75, 84, 95, 100, 129, 133`
- `core/gfx/draw_attribs.asm:7, 20, 23, 45, 59, 62, 90, 108, 116, 245`
- `core/gfx/screen.asm:19, 21`

**Fix:** mechanical — `s/adc hl,/add hl,/`. No site in this codebase wants the carry.

### 3. `rla` used as multiply-by-2

- `core/gfx/draw_display.asm:41-43, 50-52, 214-216`

`rla` rotates *through carry*. Three of them makes bit 2 of the result the incoming carry, so
`wchar * 8` is off by +4 whenever CY happened to be set.

**Fix:** `add a,a` (or `sla a`).

The single `rla` in `get_scaddr` (`draw_display.asm:18`) is fine — `xor a` clears carry first.
The `rra` chain at lines 27-29 is also fine — `and 31` masks off the polluted high bits.

### 4. `load_attribs` is broken for y == 0

- `core/gfx/draw_attribs.asm:170-172`

The `jr z, load_attribs_vertical_loop` shortcut skips far more than the Y offset. It also skips:

- `ld e, b` — the X offset
- `ld hl, (WORLD_TEMP0)` — restoring the **source data pointer**
- `pop bc` — the size
- both `BYTE_TEMP0` / `BYTE_TEMP1` setups — stride and width

So it enters the copy loop with `hl = DISPLAY_ATTRS` instead of the source data, and stale
width/stride from whatever ran last.

`fill_rectangle` (`draw_attribs.asm:219-221`) has the milder version: y == 0 silently forces x to 0.

### 5. `Panel8x8` field offsets are 1 byte apart; tiles are 8 bytes

- `core/gfx/gfx_structures.asm:1-11`

All nine fields are `BYTE`, so `Panel8x8.TopCenter` == 1. `draw8x8_panel` adds those as byte
offsets into 8×8 tile data — you get tile 0 shifted by one byte, nine times over.

**Fix:** each field needs 8 bytes (`BLOCK 8` / `DS 8`), giving offsets 0, 8, 16 … 64.

`Panel16x16` (lines 13-23) is a verbatim copy of `Panel8x8` with colons added — same nine `BYTE`
fields. For 16×16 tiles it needs 32-byte fields.

### 6. `draw8x8_panel` ignores its own arguments

- `core/gfx/draw_display.asm:36-37`

The header comment documents `hl` = data, `bc` = coords, `de` = w/h in symbols. But nothing ever
stores `bc` or `de` into `panel_xpix` / `panel_ypix` / `panel_wchar` / `panel_hchar`. The caller
has to poke those six bytes by hand for the routine to do anything.

Combined with #5, this routine has never run correctly.

### 7. Interface 2 joystick: LEFT/RIGHT swapped, and bits 5-7 are noise

- `core/input.asm:40-43`

`check_interface2` reads port `$EF` raw and falls straight into `update_state`.

On that keyboard row: bit 0 = key 0, bit 1 = key 9, bit 2 = key 8, bit 3 = key 7, bit 4 = key 6.
Sinclair joystick 2 maps 0 = fire, 9 = up, 8 = down, 7 = right, 6 = left. But `input.asm:6-7`
declares `LEFT equ $8` (bit 3 = key 7 = *right*) and `RIGHT equ $10` (bit 4 = key 6 = *left*).
**They are swapped.**

Separately, unlike `check_qaop_space` which masks each read with `or %1111111x`, this path lets
bits 5-7 through. Bit 6 is the floating EAR line — after `xor $ff` in `update_state` that becomes
phantom presses in `down_buttons` / `up_buttons`.

**Fix:** swap the two `equ`s (or the bit order), and add `or %11100000` after the `in`.

### 8. Missing `ret` in `screen.clear_pixels`

- `core/gfx/screen.asm:68`

Falls through `ei` into `screen.fill_attributes`, which falls through its `ldir` into `scaddr`,
which happens to end in `ret`. It "works" by accident while doing two loads of unintended work.
`fill_attributes` is missing its own `ret` for the same reason — so it can't be called standalone
either.

### 9. `jp IM1_INTERRUPT` without setting IY

- `core/interrupt.asm:56`

The IM2 handler hands off to the ROM ISR at `$0038`, which does all its system-variable access
IY-relative and requires `IY = $5C3A`. The handler push/pops IY but never *sets* it. Any game code
that repurposes IY will make the ROM handler scribble at a random offset.

**Fix:** `ld iy, $5C3A` immediately before the `jp`.

---

## Structural issues

### The memory map has no enforcement

`sys/memmap.i` lays out fixed `org` addresses with size comments that are stale throughout.
`Text equ $8750` with `Fonts` at `$8850` leaves 256 bytes for `draw_text.asm` — which has 14
routines and will not fit. Nothing catches this; the assembler writes one module over the next.

**Fix:** `ASSERT $ <= <NextRegionSymbol>` after every module's code, turning silent overwrites
into build errors. This is the single highest-value change in the list — it makes an entire class
of bug impossible in a fixed-address layout like this.

### Dangling references to the removed `game/` layer

- `sys/game.asm:13, 15, 17, 22` — still calls `hud.init`, `hud.clear_screen`, `hud.boot`,
  and references `hud.interrupt` in a comment. No `hud` module exists.
- `sys/game.asm:18` — `jp convos.LOGIN`. No `convos` module exists.
- `data/data.asm:8` and `data/pictures.asm:11` — both `.includebin "../../Bin/ui/vaulttek.bin"`,
  a leftover asset. `data.asm:5` also wants `frame.bin`.
- `sys/memmap.i` still reserves `Globals`, `HUD`, `MapControl`, `DialogSys`, `Collision`,
  `Player`, `Window` for code that isn't here.

### Build won't complete as it stands

- `zxide.json:4` names `main.asm` as the entry point. There is no `main.asm`.
- `macros/macros.z80asm` and `macros/gfx_macros.z80asm` are `#include`d by `sys/game.asm:4-5`.
  There is no `macros/` directory. (Their only consumer, `fill_attrib_rect`, left with `hud.asm` —
  so these includes may now just be deletable.)
- `data/data.asm:1` uses `.org Data` and `data/pictures.asm:1` uses `.org Pictures` — neither
  symbol is defined in `sys/memmap.i`.
- All `#include`s reference `.z80asm`; every file on disk is `.asm`.
- `Decompress0 equ $6000`, `DecompressorZX0 equ $A390`, and the `DecompressZX0` call in
  `sys/game.asm:10` are three names for what should be one thing.

### Shared temp globals across module boundaries

`draw_text.asm` and `draw_attribs.asm` both reference `BYTE_TEMP0`, `BYTE_TEMP1` and
`WORLD_TEMP0` — which resolve to the definitions in `core/math.asm:42-44`. Meanwhile
`draw_display.asm:6-7` defines its *own* module-local `BYTE_TEMP0`. The same identifier means two
different addresses depending on which file you're reading.

Concretely: the teletype column counter in `draw_text.asm` lives in that shared byte. Any attrib
fill interleaved with a teletype run corrupts it. For an engine base meant to be built on, this is
worth fixing before anything depends on it — give each module its own temps.

> **Done for `draw_text.asm`.** It now owns every variable it touches, and is split into two
> modules by mechanism: `direct_text` (writes display memory itself — `draw_char`,
> `draw_string`, `draw_string_mid`, `invert_mask`, `scroll_strip_left`, `dissolve_strip`) and
> `rom_text` (goes through the ROM's channels — `open_upper`, `print_string`, `print_number`,
> `set_cursor`, `print_teletype*`). The `_pix` suffix is gone; it read as "pixel coordinates"
> and never meant that. `draw_attribs.asm` and the shared temps in `core/math.asm` are still
> as described above.

### Module boundaries are a naming convention, not a mechanism

Only `draw_display.asm` actually uses `.module`. `screen.asm`, `draw_text.asm`, `draw_attribs.asm`,
`input.asm`, `math.asm` and `beeper.asm` fake it with dotted label names (`screen.cls`,
`beeper.click_beep`) or don't namespace at all (`draw_attribs.asm`'s `load_attribs`,
`fill_rectangle`, `set_direct_fill` are bare globals). Pick one approach.

### The stack overlaps code

`sys/memmap.i:9` comments `Stack $7AFF-$7FFF`, but `AppStart` … `Math` occupy `$7B00–$7D4F`. Real
headroom is ~688 bytes. The IM2 handler pushes 20 bytes on entry, plus whatever the ROM ISR uses
on top. Tight, and nothing will tell you when it isn't.

---

## Smaller items

- `core/gfx/draw_text.asm:122` — `ld hl, 0x3C00` is dead, overwritten by line 123.
- `core/math.asm:38-39` — `Math.InitRandom` writes one byte into the two-byte `RANDOM_DATA`, so the
  seed pointer is always `$00xx` and `Math.RandomToA` only ever walks 256 bytes of ROM.
- `core/gfx/draw_text.asm` — the teletype routines use `rst $10`, which needs `set_screen`
  (`OPEN_SCREEN`) called first. Worth noting in the header comment, since nothing enforces it.
- `core/gfx/draw_display.asm:206` — `put_img_desized` relies on `E` surviving
  `screen.get_display_table_by_pix_line` (it does, but incidentally). The real contract is
  `d` = width in bytes, `e` = height in character rows; worth documenting.
- `core/gfx/draw_text.asm:22` — comment says "y coordinate" on the `ld a,b` line; `b` is x.
- `core/gfx/gfx_structures.asm:30-31` — `WindowUI.PBUFFER` and `.PPROG` are `BYTE` but the names
  suggest pointers; probably want `WORD`.
- `test.asm:1` says `device zxspectrum48`; `zxide.json:3` says `"model": "128k"`.
- `core/input.asm:111` — `wait_control` spins on a flag only the ISR sets. Any entry point that
  calls it must `im 1` / `im 2` + `ei` first or it hangs forever.
- Typos in identifiers, cheap to fix now:
  - `Math.Muliply` → `Math.Multiply` (`core/math.asm:3`)
  - `WORLD_TEMP0` → `WORD_TEMP0` (`core/math.asm:44`, used in `draw_attribs.asm`)
  - `begining` → `beginning`, `lenght` → `length` (`draw_display.asm:238, 240`)
- Not a git repository.

---

## Suggested order

1. `git init` and commit current state before touching anything.
2. Get it assembling again: restore or stub `main.asm`, drop the `macros/` includes and the `hud.*`
   / `convos.LOGIN` calls in `sys/game.asm`, add `Data` and `Pictures` to the memmap, fix the
   `.z80asm` / `.asm` extension mismatch, remove the `vaulttek.bin` includes.
3. Add `ASSERT` guards after every module — makes region overflow a build error from here on.
4. The mechanical sweeps: `adc hl,` → `add hl,`, `rla` → `add a,a`.
5. Move `im2table` off `Attributes`; add `ld iy,$5C3A` before the ROM ISR chain.
6. Give each module its own temps instead of sharing `math.asm`'s.
7. Logic bugs: `load_attribs` y==0, `Panel8x8`/`Panel16x16` field sizes, `draw8x8_panel` argument
   handling, Interface 2 LEFT/RIGHT and bit masking, the two missing `ret`s.
