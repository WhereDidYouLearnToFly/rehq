# Getting music into MainMenu — step by step

Nothing in `game/` has ever called the audio code. All four modules are
assembled in (`heroques.asm:47-50`), no song data is, and the only audio call
site in the project is `rom_text.asm:118 call beeper.click_beep`. So this is
first use.

Do the steps in order. Each one is small enough to build and hear.

---

## The API, once

`core/audio/music.asm` is the front end. Never call `PTS.*` or `ay.*` yourself
— `ptsplay.asm:16-18` says so, and the wrapper exists because the player sets
`IY` and needs muting handled around it. The whole API, from `music.asm:27-33`:

```
music.play_pt2   hl = module address
music.play_pt3   hl = module address
music.play_ay    hl = DRIVER descriptor
music.frame      advance one frame - 50Hz, outside an interrupt
music.frame_raw  same, for callers already inside the ISR
music.stop       silence and forget
music.playing    0 when nothing is playing
```

Three of those do the job: `play_pt3` once, `frame` every frame, `stop` at the
end. Everything below is plumbing around those three.

---

## Step 0 — make the test bench run again

Do this first. `tests/sound_test.asm` is a working reference for every call
below, and it lets you hear the tunes before touching the game.

It currently does not assemble: it includes `ay.asm` and `music.asm`
(`:64-66`) but not `ptsplay.asm`. That include used to live inside `music.asm`
and was moved out in commit `150ee02`, so `PTS.INIT` is now undefined.
`music.asm:5,7` still claims it includes ptsplay — stale comment, ignore it.

Add the missing include next to the other two, assemble
`tests/sound_test.asm`, run the `.sna` **in 128K mode**, and play with it.
The keys are in `scan_key`. Confirm you can hear a PT3 tune. If you cannot,
stop here — nothing later will work either.

---

## Step 1 — silence at boot

In `appentry` (`heroques.asm:22-27`), `call music.stop` **before**
`call interrupt.init_im2`.

Why: `init_im2` ends with `ei`. A snapshot starts with whatever the AY chip
had in its registers, and once interrupts are on you may be listening to it.
`sound_test.asm:126` does the same thing and says why in a comment.

Build. Nothing audible changes — you are just proving the include chain
resolves `music.stop` from game code.

---

## Step 2 — get a module into the build

Use `music/Terminator2_DAVOS.pt3` as a placeholder. It is 2552 bytes and,
per `ptsplay.asm:58-59`, a PT3 module can sit at any address — no rounding, no
relocation.

`incbin` it at the end of `main_menu_scene.asm` under a label like `mod_menu`.
That file is `SLOT 3 / PAGE 0` at $C000 and `main_menu` ends around $C1xx, so
a 2.5K module drops in after it with room to spare and **needs no bank
switching at all**. That is the entire reason to start here rather than with
the real tunes.

Build and check the listing to confirm where it landed and that it did not
collide with anything.

---

## Step 3 — start it

In `main_menu.init`, before the `ret`:

```
                    ld hl, mod_menu
                    call music.play_pt3
```

Build, run. Music should start with the menu.

If it crashes instead: `PTS.PLAY` crashes when `INIT` was never called
(`ptsplay.asm:79-83`) — but you have not added the frame call yet, so a crash
here means the module pointer is wrong, not the ordering.

---

## Step 4 — keep it playing

Nothing advances the tune yet. A player is a state machine that writes AY
registers once per frame; without the frame call you get one chord and silence.

Top of `main_menu.loop`, before the `next_scene` test:

```
                    call music.frame
```

Why there: `game.loop` (`game.asm:106-108`) is `halt` then `jp` into the scene
loop, so this lands once per frame, right after the ISR returns — which is
exactly the 50Hz the player wants.

Why `frame` and not `frame_raw`: `frame` does its own `di … ld iy,SYSVARS …
ei`. That is correct out here and wrong inside an interrupt handler, where the
`ei` would let the next interrupt nest on top of the current one. `frame_raw`
is the version without that, for ISR callers only.

Build, run. Now it plays properly.

---

## Step 5 — stop it restarting

Go to settings, come back. The tune restarts from bar one.

Because `set_main_menu_scene` ends `jp init` (`game.asm:76`), so
`main_menu.init` — and your `play_pt3` — runs again on every return.

Guard it with the byte the module already exports:

```
                    ld a, (music.playing)
                    and a
                    jr nz, .music_running
                    ld hl, mod_menu
                    call music.play_pt3
.music_running:
```

This is also the guard that keeps `music.frame` safe: it can only ever run
after a `play_*` has happened.

---

## Step 6 — stopping when you leave

The obvious home is `main_menu.deinit`. It will never run.

`pscene_deinit_call` (`game.asm:54-56`) has **zero callers** anywhere in the
repo, and both `set_*_scene` routines end `jp init` without calling it. The
pointer is written in three places and read only inside that dead routine.

So `call music.stop` goes in the action that leaves the menu — or, if the same
tune should carry into settings, nowhere yet, and you stop it when gameplay
starts. Your call. This is worth knowing before you plan the rest of the scene
transitions: **there is currently no scene teardown hook that runs.**

---

## Step 7 — one wrapper for all three switches

Steps 5 and 6 put policy in the scene. Tune switching, the MUSIC setting and
loop control all want the same decisions in one place, so build the wrapper now
and let the scenes call it.

Home: a new `MODULE audio` in `game/`. Put it in slot 1 / page 5, in the free
region `memmap.i` already documents as *"$678C-$7AFF free, up to the stack"* —
that bank is always mapped, so any scene can call it. `globals.asm` ($65F1) is
its neighbour and holds the settings byte it reads.

Shape it as an id and a table, not raw pointers at the call sites:

```
TUNE_NONE   equ 0
TUNE_MENU   equ 1
TUNE_GAME   equ 2

tunes:      dw 0, mod_menu, mod_game     ; indexed by TUNE_*
current:    db TUNE_NONE
```

Three entries:

- **`play_tune`** — `a` = `TUNE_*`. Stores it in `current` *first*, then acts.
  If it equals `current` and `music.playing` is non-zero, return — that is
  Step 5's guard, now covering re-entry and re-selection in one test. If the
  MUSIC bit is clear, `call music.stop` and return. Otherwise look the pointer
  out of `tunes` and `call music.play_pt3`.
- **`frame`** — `call music.frame`, or return early when nothing is playing.
  Scenes call this instead of `music.frame` so the bank wrapping below has one
  home.
- **`apply`** — re-read the MUSIC bit and make reality match: stop if it went
  off, `play_tune current` if it came on. This is what the settings toggle
  calls.

Storing `current` even when music is off is the point: it is what lets the
toggle restart the right tune later.

Now `main_menu.init` becomes `ld a, TUNE_MENU / call audio.play_tune`, and
gameplay's init becomes `ld a, TUNE_GAME / call audio.play_tune`. No `stop`
needed between them — `music.play_pt3` calls `stop` itself (`music.asm:91`)
before handing the chip over.

If the two modules ever end up in different banks, the module data must be
paged in whenever `PTS.PLAY` reads it, so `audio.frame` wraps it:

```
                    SELECT_RAM_BANK n
                    call music.frame
                    SELECT_RAM_BANK 0
```

Macro at `core/macros/macros.asm:13`. It does `di`/`ei`, so it is fine from
`loop:` and wrong from inside the ISR. Not needed while both modules sit in
page 0 — but this is why `frame` is wrapped rather than called directly.

---

## Step 8 — the MUSIC on/off setting

`globals.asm:4` already declares `MUSIC equ %00100000` as a bit in
`globals.settings` (`:8`). Nothing reads it and nothing writes it. The settings
screen prints `TEXT_MUSIC_ON` as static text (`settings_scene.asm:46`) and
`TEXT_MUSIC_OFF` (`:9`) is declared but never drawn.

Three pieces:

1. **Read it** — that is `audio.play_tune` from Step 7, already done.
2. **Draw the right one** — the strings are the same length, so redrawing over
   the old line needs no clearing. Pull `settings.init`'s music line out into a
   `draw_music_line` that picks `TEXT_MUSIC_ON` or `TEXT_MUSIC_OFF` by the bit,
   sets `GREEN_ATTR` and prints at `bc = $0806` (`settings_scene.asm:44-47`).
   Call it from `init` and from the toggle.
3. **Write it** — see the flag idioms below, then `call draw_music_line` and
   `call audio.apply`.

### Setting the flags

Declare the **bit number** and derive the mask, rather than writing the mask by
hand — then both idioms are available from one definition:

```
MUSIC_BIT       equ 5
MOVEMENT_BIT    equ 6
MUSIC           equ 1 << MUSIC_BIT      ; %00100000, as now
MOVEMENT        equ 1 << MOVEMENT_BIT   ; %01000000
```

| | code | bytes / T |
|---|---|---|
| set | `ld hl, settings` / `set MUSIC_BIT,(hl)` | 5 / 25 |
| clear | `ld hl, settings` / `res MUSIC_BIT,(hl)` | 5 / 25 |
| test | `ld hl, settings` / `bit MUSIC_BIT,(hl)` / `jr z, .off` | 5 / 22 + branch |
| toggle | `ld a,(settings)` / `xor MUSIC` / `ld (settings),a` | 8 / 33 |

`set`/`res`/`bit` only reach `(hl)`, `(ix+d)` or a register — there is no
`bit n,(nn)` — so the address has to go through HL first. In exchange they do
not touch A and are a read-modify-write in one instruction.

There is no toggle instruction, so that one stays `xor` through A. Same for
testing when you want the result *in* A rather than in Z.

`~MUSIC` assembles as expected in sjasmplus ($DF) if you prefer
`and ~MUSIC` to `res`.

While you are in there: `settings.loop` currently tests `keys.up_digits` bit
patterns by hand, and `.one`/`.two`/`.three`/`.five` all fall into the same
`jp game.set_main_menu_scene`, so every digit exits. `keys.get_digit`
(`keys.asm:93-96`) already returns `a = 1..5` on the down edge, "the one call a
numbered menu needs" — use it and the branch becomes a real `cp 2` / `cp 5`.

Verify: toggle to OFF, music stops and the line reads OFF. Toggle back, the
tune starts again. Leave to the menu and return — still ON, still playing,
because `current` survived.

---

## Step 9 — loop and no-loop

Looping is already the default. `SETUP.NOLOOP EQU 1` (`ptsplay.asm:98`) is
opt-*out*, and `music.play_pt3` passes only `PTS.SETUP.TSPT3`
(`music.asm:82`), so bit 0 stays clear and the module repeats from its loop
point. Menu music needs nothing.

To play a tune **once** you have two levers, and they are not the same:

- **At start** — `music.asm:78-83` hardcodes the flags into `a` before falling
  into `start_module`. Add a module byte, say `loop_flags`, and `or` it into
  `a` there; then a `play_once` variant is one write. Cleaner than a second
  entry point that duplicates the path.
- **Mid-tune** — `PTS.SETUP` is a live variable (`ptsplay.asm:105`), written by
  `INIT` at `:169`. `ld a,(PTS.SETUP) / set 0,a / ld (PTS.SETUP),a` makes the
  currently playing tune stop when it next reaches its loop point. Useful for
  fading a menu tune out on the way into gameplay.

**Detecting the wrap is the expensive one.** Bits 6/7 of `SETUP` are set at the
loop point (`ptsplay.asm:114-116`), but only when the checker is compiled in —
and `LoopChecker=0` at `ptsplay.asm:50` compiles it out. Flipping that to 1
adds the `CHECKLP` code at `:124-125` to a module that has **zero slack**:
`PTSPlayer $845D` + `$BBD` ends at `$901A`, exactly where `DrawDisplay`
starts. So "play the fanfare, then start the loop" costs a memory-map move
before it costs any logic. Worth knowing before you design around it.

---

## Later — the real HeroQuest tunes

`music/Barry Leitch - Hero Quest - Title (AY) 1 (1991).ay` and the two in-game
files are byte-identical: one memory block holding all three tunes, selected by
the `regs` value in the descriptor — **2 = Title, 1 and 3 = the in-game pair**
(`sound_test.asm:29-36`). That is your menu/gameplay swap for free, which is
why it is worth doing eventually.

The catch is that a `.ay` block is not data, it is code assembled for a fixed
address. From `sound_test.asm:90-97`: load at `$BFF4`, offset 232 into the
file, length `$2310` — so it occupies **$BFF4-$E303**. That is all of
$C000-$E303, where `input_select` ($C000) and `main_menu` ($C096) live. It
cannot share a page with your scene code.

So this is a memory-map decision, not a wiring one: either a dedicated bank at
$C000 paged in around every frame call, or the scenes move out of page 0.
Deliberately not part of today.

When you do it, only the start call changes — `play_ay` takes `hl` = a 4-word
`DRIVER` descriptor (`music.asm:59-65`): init address, play address, SP, regs.
`frame` and `stop` are identical.

---

## Things that will bite

- **128K only.** `ay.asm:19-22`: a plain 48K has no AY, so there is simply no
  sound. If you hear nothing, check the emulator's model first.
- **No slack around the player.** `PTSPlayer equ $845D` plus `$BBD` ends at
  `$901A`, which is exactly where `DrawDisplay` starts. Nothing may grow in
  `$845D-$901A`.
- **`AYPlayer equ $5EA8`** (`memmap.i:16`) is referenced by nothing — `music.asm`
  uses a hardcoded `org $918D`. Ignore or delete.
- **Cost is undocumented.** Nothing in the source states the player's per-frame
  T-states. Switch on `PERF_BORDER` (`game/game.asm:26`) and read the red band
  rather than assuming.
