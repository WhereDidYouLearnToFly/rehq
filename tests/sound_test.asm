;=============================================================================
; sound_test - test bench for core/audio: plays everything in music/
;=============================================================================
; Open this file in zxide and press F5. Keys 1-6 start a track, SPACE stops.
;
; This has to be a 128K snapshot, unlike the other benches: the AY lives on
; the 128K board and a 48K has no sound chip at all. On a 48K the code runs
; perfectly happily and in total silence, with all three meters pegged full -
; the register reads float high when there is nothing driving the bus.
;
; The six tracks are everything in music/, in the two shapes core/audio
; handles:
;
;   1-2  .pt2 and .pt3 tracker modules, handed to the ptsplay player as data
;   3    a .pt3 module carved out of SH_promise.c - see below
;   4-6  a driver block lifted out of an .ay file, which brings its own
;        player with it and only needs calling
;
; Track 3 is worth explaining. SH_promise.c is a *compiled* tune: a player
; and a module glued together into one loadable at $C000. Its first
; instruction is ld hl,$C851, the player's own "here is my data" pointer, so
; the module inside starts $851 (2129) bytes in - and that offset is where
; the "ProTracker 3.5 compilation of..." header sits, which confirms it. The
; module is position independent, so incbin from 2129 gives back plain PT3
; data for ptsplay and the compiled-in player is simply left behind. The
; alternative - loading the whole thing at $C000 - would collide with the
; .ay block below and buy nothing.
;
; Tracks 4-6 come from one .ay file. All three .ay files in music/ are
; byte-identical (same md5), and each holds all three Hero Quest tunes
; sharing a single memory block - the filenames just say which tune that copy
; was named for. So the block is embedded once, at the $BFF4 it was written
; for, and the three tunes are three descriptors differing only in the number
; handed to the block's init routine: 2 for the title, 1 and 3 for the
; in-game pair. Those numbers are the HiReg fields out of the .ay header, not
; a guess.
;
; What to check:
;   - each of 1-6 plays, and starting a new track cuts the old one cleanly
;     rather than layering it or leaving a note hanging
;   - SPACE really silences the chip. Both players get muted, so a stop
;     should be silent even straight after a driver-block track, which
;     leaves the AY however it pleased
;   - the meters move with what you hear, and drop to nothing on stop. They
;     are read back off the chip over port $FFFD rather than from any
;     player's variables, so they measure all six tracks the same way and
;     will disagree with a player that thinks it is playing but is not
;   - a channel the mixer has switched off entirely reads as silent even if
;     its amplitude register is loud - that is the mixer being honoured, not
;     a dropout
;   - the border stays black and the display does not tear: the frame's work
;     has to fit between interrupts, and the driver-block tracks do more per
;     frame than the tracker ones
;   - leave a track looping for a few minutes. A player that corrupts memory
;     usually takes a while to show it
;=============================================================================

                    device zxspectrum128

; The org has to come before the includes: without it the modules assemble
; from address 0, i.e. underneath the ROM, and every call into them would
; land in the ROM instead.
                    org $8000

                    include "../core/audio/ay.asm"
                    include "../core/audio/music.asm"

DISPLAY_ATTRS       equ 22528
OPEN_SCREEN         equ 5633
PRINT_STRING_DE     equ 8252

IM1_I_VALUE         equ 63

ATTR_PAPER          equ %00000111       ; black paper, white ink
ATTR_SELECTED       equ %01111000       ; bright white paper, black ink
ATTR_BAR            equ %01000100       ; bright green - a fixed level
ATTR_BAR_ENV        equ %01000110       ; bright yellow - level from envelope
ATTR_BAR_OFF        equ %00001000       ; blue paper, unlit part of a bar

TRACK_COUNT         equ 6
TRACK_ROW           equ 4               ; first track line
METER_ROW           equ 13              ; first meter line
BAR_COL             equ 4
BAR_CELLS           equ 16              ; one cell per amplitude step

; What the third byte of a track table entry means.
TYPE_PT2            equ 0
TYPE_PT3            equ 1
TYPE_AY             equ 2

; Where the .ay file's memory block wants to live, and the two entry points
; inside it. Both are out of the file's own song structures, not deduced:
; $BFF4 is the per-frame routine (it ends in a ret) and $BFFB is init.
AY_BLOCK            equ $bff4
AY_INTERRUPT        equ $bff4
AY_INIT             equ $bffb
AY_BLOCK_OFFSET     equ 232             ; where the block starts in the file
AY_BLOCK_LENGTH     equ $2310

; The .ay header gives this block a stack of 0. That is not "unset": SP is
; meant to be 0, so the block's first push wraps to $FFFE and it runs on the
; top of RAM. Nothing of ours lives there - the block itself ends at $E303.
AY_STACK            equ 0

start:
                    di
                    ld sp, $7fff

                    ; A snapshot could start in either interrupt mode, and
                    ; the whole bench is paced by halt waiting on the ROM's
                    ; 50Hz interrupt, so pin the mode down rather than
                    ; inherit it.
                    ld a, IM1_I_VALUE
                    ld i, a
                    im 1

                    ld a, 2                     ; upper screen, so RST $10 works
                    call OPEN_SCREEN

                    call clear_screen

                    ld de, txt_screen
                    ld bc, txt_screen_len
                    call PRINT_STRING_DE

                    call music.stop             ; silence before the first ei,
                                                ; whatever the snapshot loaded
                                                ; into the chip

                    ; The ROM interrupt handler addresses the system
                    ; variables through IY, and a snapshot starts with
                    ; whatever IY the assembler left. Point it at them before
                    ; the first interrupt can arrive. Everything after this
                    ; keeps it that way - music.frame puts it back itself.
                    ld iy, music.SYSVARS
                    ei

main_loop:
                    halt                        ; one pass per frame, paced by
                                                ; the ROM interrupt
                    call music.frame
                    call draw_meters
                    call read_keys
                    jr main_loop

;-----------------------------------------------------------------------------
; read_keys - act on 1-6 and SPACE, once per press.
;
; The edge is taken against the previous frame's key rather than a bitmask of
; held keys, which is all this needs: restarting a track every frame while a
; number is held down would stutter, and holding SPACE would just re-mute
; something already silent.
;-----------------------------------------------------------------------------
read_keys:
                    call scan_key
                    ld hl, last_key
                    cp (hl)
                    ret z                       ; nothing changed
                    ld (hl), a

                    and a
                    ret z                       ; a release, not a press
                    cp TRACK_COUNT + 1
                    jr z, stop_track            ; SPACE

                    dec a                       ; 1-6 -> 0-5
                    ld (current_track), a
                    call highlight_track

                    ld a, (current_track)
                    ld l, a                     ; three bytes per entry:
                    ld h, 0                     ; hl = a * 3 + tracks
                    ld d, h
                    ld e, l
                    add hl, hl
                    add hl, de
                    ld de, tracks
                    add hl, de

                    ld a, (hl)                  ; type
                    inc hl
                    ld e, (hl)
                    inc hl
                    ld d, (hl)
                    ex de, hl                   ; hl = module or descriptor

                    cp TYPE_PT2
                    jp z, music.play_pt2
                    cp TYPE_PT3
                    jp z, music.play_pt3
                    jp music.play_ay

stop_track:
                    ld a, $ff                   ; no track highlighted
                    ld (current_track), a
                    call highlight_track
                    jp music.stop

;-----------------------------------------------------------------------------
; scan_key - read the keys this bench uses.
; Entry: -
; Exit:  a = 1-6 for those number keys, 7 for SPACE, 0 for none. Corrupts
;        b, c, d. The keyboard reads back active low, hence the cpl.
;
; If several are down at once the lowest wins, which only matters for the
; edge detection above: a second key going down while the first is held
; changes the answer and so counts as a press.
;-----------------------------------------------------------------------------
scan_key:
                    ld bc, $f7fe                ; 1 2 3 4 5, bit 0 = key 1
                    in a, (c)
                    cpl
                    and %00011111
                    jr z, .row_six

                    ld d, 1                     ; number of the lowest bit set
.find:
                    rra
                    jr c, .found
                    inc d
                    jr .find
.found:
                    ld a, d
                    ret

.row_six:
                    ld bc, $effe                ; 0 9 8 7 6, bit 4 = key 6
                    in a, (c)
                    cpl
                    and %00010000
                    ld a, 6
                    ret nz

                    ld bc, $7ffe                ; SPACE, bit 0
                    in a, (c)
                    cpl
                    and %00000001
                    ld a, TRACK_COUNT + 1
                    ret nz

                    xor a
                    ret

;-----------------------------------------------------------------------------
; draw_meters - one bar per channel, read back off the chip.
;
; Read rather than remembered on purpose: this is the only measurement that
; works the same for a tracker module and for a driver block whose insides
; nothing here understands. See core/audio/ay.asm for the read.
;
; Two things are folded into the level. An amplitude register with bit 4 set
; means the channel follows the envelope generator, whose current output is
; not readable - that shows as a full bar in a different colour rather than a
; wrong number. And a channel with both its tone and its noise switched off
; in the mixer is silent whatever its amplitude says, so it reads as zero.
;-----------------------------------------------------------------------------
draw_meters:
                    ld a, ay.MIXER
                    call ay.read
                    ld (mixer_state), a

                    ld b, 0                     ; channel 0-2
.channel:
                    ld a, ay.AMPL_A
                    add a, b
                    push bc
                    call ay.read
                    pop bc

                    ld d, ATTR_BAR
                    bit 4, a                    ; ay.AMPL_ENVELOPE
                    jr z, .fixed
                    ld d, ATTR_BAR_ENV
                    ld a, ay.AMPL_LEVEL         ; unknown, so show it full
.fixed:
                    and ay.AMPL_LEVEL
                    ld e, a

                    ld hl, chan_mixer_mask      ; tone and noise bits for this
                    ld c, b                     ; channel, both active low
                    ld b, 0
                    add hl, bc
                    ld b, c
                    ld a, (mixer_state)
                    and (hl)
                    cp (hl)
                    jr nz, .draw
                    ld e, 0                     ; both off: nothing to hear
.draw:
                    ld a, b
                    add a, METER_ROW
                    push bc
                    call draw_bar
                    pop bc

                    inc b
                    ld a, b
                    cp 3
                    jr nz, .channel
                    ret

;-----------------------------------------------------------------------------
; draw_bar - paint one meter row.
; Entry: a = character row, e = level 0-15, d = attribute for the lit part.
; Exit:  corrupts a, b, c, h, l.
;
; Attributes rather than characters: a cell is one byte, so a bar redrawn
; every frame costs 16 writes and cannot tear against the pixels underneath.
;-----------------------------------------------------------------------------
draw_bar:
                    ld l, a
                    ld h, 0
                    add hl, hl                  ; 32 bytes per row
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld bc, DISPLAY_ATTRS + BAR_COL
                    add hl, bc

                    ld b, BAR_CELLS
                    ld c, 0
.cell:
                    ld a, c
                    cp e                        ; lit while below the level
                    ld a, d
                    jr c, .put
                    ld a, ATTR_BAR_OFF
.put:
                    ld (hl), a
                    inc hl
                    inc c
                    djnz .cell
                    ret

;-----------------------------------------------------------------------------
; highlight_track - mark which line is playing, from current_track.
; $FF means none, which is what stop leaves behind.
;-----------------------------------------------------------------------------
highlight_track:
                    ld hl, DISPLAY_ATTRS + TRACK_ROW * 32
                    ld b, TRACK_COUNT * 32      ; six rows, still fits in b
.clear:
                    ld (hl), ATTR_PAPER
                    inc hl
                    djnz .clear

                    ld a, (current_track)
                    cp $ff
                    ret z

                    add a, TRACK_ROW            ; hl = attrs + row * 32
                    ld l, a
                    ld h, 0
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld bc, DISPLAY_ATTRS
                    add hl, bc

                    ld b, 32
.row:
                    ld (hl), ATTR_SELECTED
                    inc hl
                    djnz .row
                    ret

;-----------------------------------------------------------------------------
; clear_screen - blank pixels, uniform attributes.
;-----------------------------------------------------------------------------
clear_screen:
                    ld hl, 16384
                    ld de, 16385
                    ld bc, 6144 - 1
                    ld (hl), 0
                    ldir

                    ld hl, DISPLAY_ATTRS
                    ld de, DISPLAY_ATTRS + 1
                    ld bc, 768 - 1
                    ld (hl), ATTR_PAPER
                    ldir

                    xor a                       ; black border
                    out ($fe), a
                    ret

current_track:      db $ff                      ; $ff = nothing playing
last_key:           db 0
mixer_state:        db 0

; Tone and noise enable for each channel, both active low in AY register 7.
chan_mixer_mask:    db ay.MIX_TONE_A | ay.MIX_NOISE_A
                    db ay.MIX_TONE_B | ay.MIX_NOISE_B
                    db ay.MIX_TONE_C | ay.MIX_NOISE_C

; One entry per key 1-6: what it is, and where. The order has to match the
; lines printed in txt_screen.
tracks:
                    db TYPE_PT2
                    dw mod_terminator2
                    db TYPE_PT3
                    dw mod_terminator2_davos
                    db TYPE_PT3
                    dw mod_promise
                    db TYPE_AY
                    dw ay_title
                    db TYPE_AY
                    dw ay_ingame1
                    db TYPE_AY
                    dw ay_ingame2

; The three tunes inside the one .ay block. Only the last word differs: it is
; the register preset the block's init reads to pick a tune, taken from each
; song's HiReg/LoReg in the .ay header.
ay_title:           dw AY_INIT, AY_INTERRUPT, AY_STACK, $0200
ay_ingame1:         dw AY_INIT, AY_INTERRUPT, AY_STACK, $0100
ay_ingame2:         dw AY_INIT, AY_INTERRUPT, AY_STACK, $0300

txt_screen:         db 22, 1, 5, "core/audio sound test"

                    db 22, TRACK_ROW + 0, 1, "1  Terminator 2            pt2"
                    db 22, TRACK_ROW + 1, 1, "2  Terminator 2 (DAVOS)    pt3"
                    db 22, TRACK_ROW + 2, 1, "3  Promise Respire         pt3"
                    db 22, TRACK_ROW + 3, 1, "4  Hero Quest - Title       ay"
                    db 22, TRACK_ROW + 4, 1, "5  Hero Quest - In-Game 01  ay"
                    db 22, TRACK_ROW + 5, 1, "6  Hero Quest - In-Game 02  ay"

                    db 22, 11, 1, "1-6 play      SPACE stop"

                    db 22, METER_ROW + 0, 1, "A"
                    db 22, METER_ROW + 1, 1, "B"
                    db 22, METER_ROW + 2, 1, "C"

                    db 22, 17, 1, "meters are AY registers 8/9/10"
                    db 22, 18, 1, "read back off the chip itself"
                    db 22, 20, 1, "yellow = level driven by the"
                    db 22, 21, 1, "envelope, so shown full"
txt_screen_len      equ $ - txt_screen

;-----------------------------------------------------------------------------
; The music. The tracker modules are plain data and can sit anywhere; the
; assert is what keeps them from growing into the .ay block below.
;-----------------------------------------------------------------------------
mod_terminator2:    incbin "../music/Terminator2.pt2"
mod_terminator2_davos:
                    incbin "../music/Terminator2_DAVOS.pt3"

                    ; Just the PT3 module out of the compiled file - the
                    ; player in front of it is not loaded. See the header.
mod_promise:        incbin "../music/SH_promise.c", 2129

                    ASSERT $ <= AY_BLOCK

; The .ay memory block, at the fixed address its code was assembled for. All
; three .ay files in music/ contain this same block, so which one is named
; here does not matter.
                    org AY_BLOCK
ay_block:           incbin "../music/Barry Leitch - Hero Quest - Title (AY) 1 (1991).ay", AY_BLOCK_OFFSET, AY_BLOCK_LENGTH

                    savesna "sound_test.sna", start
