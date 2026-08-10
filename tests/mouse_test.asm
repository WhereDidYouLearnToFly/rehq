;=============================================================================
; mouse_test - visual test bench for core/mouse.asm
;=============================================================================
; Open this file in zxide and press F5 (Kempston Mouse must be enabled in
; the emulator/interface). Model 128K, matching zxide.json and main.asm.
; Move the mouse and click its buttons.
;
;   - the crosshair should follow the physical mouse in the right direction on
;     both axes - in particular down should mean down, since the interface's
;     Y counter runs the opposite way to screen Y and mouse.read negates it
;   - it should not drift, and should not jump when the interface's internal
;     8-bit counters wrap
;   - it moves in 8-pixel steps horizontally and 1-pixel steps vertically.
;     That is display.draw_8x8 rounding x down to a character column, not the
;     mouse: watch the X readout, which moves one unit at a time
;   - X/Y readout at the bottom should stay in 0..255 / 0..191, clamping
;     rather than wrapping at the screen edges
;   - the three button rows work like input_test's: HELD tracks the button
;     live, DOWN/UP flash briefly on the edges. A held row that never lights,
;     or an edge row that stays stuck lit, means the masks are wrong.
;
; Known test-bench-only quirk: the crosshair is drawn with display.draw_8x8,
; which does not clip - so with the cursor allowed to reach y=191 (the
; bottom pixel line) its lowest rows draw past the end of the pixel display
; file. Harmless in this test (worst case some attribute-area garbage),
; but exactly why draw_display.asm documents clipping as the caller's job.
;
; 128K notes. Nothing in mouse.asm is machine specific - the interface is the
; same on both - but this being a 128K snapshot, three things a 48K gives away
; for free have to be set up by hand before the first ROM call or interrupt:
;
;   - ROM 1 has to be paged in. Every character this bench prints goes through
;     the 48K BASIC ROM (RST $10, CHAN_OPEN, PR_STRING) and the whole frame
;     loop is paced by that ROM's IM 1 handler at $0038. On a 128K that ROM is
;     only present while bit 4 of $7FFD is set; with ROM 0 - the 128 editor -
;     paged in instead, those addresses are unrelated code and the bench dies
;     on its first print.
;   - the screen bit has to be clear. Bit 3 of $7FFD picks which page the ULA
;     displays, and everything here draws into the display file in page 5. Get
;     it wrong and the bench runs perfectly with a blank screen.
;   - I and the interrupt mode have to be pinned. A snapshot can arrive in
;     IM 2 with a stale I, and screen.cls turns interrupts back on as it
;     leaves, so the mode has to be set before that rather than next to the
;     ei further down.
;
; The mouse ports need nothing: $FADF/$FBDF/$FFDF all have A1 high, so they
; miss both the paging latch ($7FFD) and the AY ($FFFD/$BFFD), which only
; answer with A1 low. Reads could not page anything anyway - the latch is
; write only - but the addresses are clear of it either way.
;=============================================================================

                    device zxspectrum128

; The org has to come before the includes: without it the modules assemble
; from address 0, i.e. underneath the ROM, so every call into them would land
; in the ROM instead. $8000 is page 2, which is never paged out.
                    org $8000

                    include "../core/mouse.asm"
                    include "../core/gfx/screen.asm"
                    include "../core/gfx/draw_display.asm"
                    include "../core/gfx/draw_text.asm"

ATTR_ON             equ %01000100       ; bright, black paper, green ink -> solid green
ATTR_OFF            equ %00001000       ; blue paper, black ink -> dim
ATTR_PAPER          equ %00000111       ; black paper, white ink

DISPLAY_ATTRS       equ 22528

BANK_PORT           equ $7ffd
BANK_ROM48          equ %00010000       ; ROM 1 (48K BASIC), screen page 5,
                                        ; page 0 at $C000
IM1_I_VALUE         equ 63
SYSVARS             equ $5c3a           ; what the ROM ISR expects in IY

BLOCK_COL           equ 6
ROW_HELD            equ 8
ROW_DOWN            equ 12
ROW_UP              equ 16
HOLD                equ 12              ; frames an edge stays visible

start:
                    di
                    ld sp, $7fff                ; page 5, above the display file

                    ; Put the 128K into the state the rest of this file
                    ; assumes, rather than inheriting whatever loaded the
                    ; snapshot - see the 128K notes at the top.
                    ld bc, BANK_PORT
                    ld a, BANK_ROM48
                    out (c), a

                    ld a, IM1_I_VALUE
                    ld i, a
                    im 1
                    ld iy, SYSVARS              ; the ROM ISR and the print
                                                ; routines address the system
                                                ; variables through IY

                    ld a, ATTR_PAPER
                    call screen.cls             ; leaves interrupts enabled,
                                                ; hence all of the above first

                    call rom_text.open_upper
                    ld de, txt_title
                    ld bc, txt_title_len
                    call rom_text.print_string
                    ld de, txt_labels
                    ld bc, txt_labels_len
                    call rom_text.print_string

                    call mouse.init
                    ei                          ; already on after screen.cls;
                                                ; explicit because the loop
                                                ; below halts on the ROM's IM 1
                                                ; interrupt

main_loop:
                    halt
                    call mouse.read

                    ; erase the old crosshair, draw the new one
                    ld hl, blank_tile
                    ld a, (prev_x)
                    ld b, a
                    ld a, (prev_y)
                    ld c, a
                    call display.draw_8x8

                    ld a, (mouse.x)
                    ld (prev_x), a
                    ld b, a
                    ld a, (mouse.y)
                    ld (prev_y), a
                    ld c, a
                    ld hl, cursor_tile
                    call display.draw_8x8

                    ld a, (mouse.pressed_buttons)
                    ld c, ROW_HELD
                    call draw_mask

                    ld hl, down_latch
                    ld a, (mouse.down_buttons)
                    ld c, ROW_DOWN
                    call draw_latched

                    ld hl, up_latch
                    ld a, (mouse.up_buttons)
                    ld c, ROW_UP
                    call draw_latched

                    ld a, (mouse.x)
                    ld b, XY_COL
                    ld c, ROW_XY
                    call print3

                    ld a, (mouse.y)
                    ld b, XY_COL
                    ld c, ROW_XY + 1
                    call print3

                    jr main_loop

;-----------------------------------------------------------------------------
; print3 - print a as three zero-padded decimal digits.
; Entry: a = value 0..255, b = column, c = row
; Corrupts a, b, c, d, e, h, l.
;
; Fixed width rather than the ROM's variable-width decimal print, so a
; shrinking value (e.g. 100 -> 99) doesn't leave a stale digit behind.
;-----------------------------------------------------------------------------
print3:
                    push af
                    call rom_text.set_cursor
                    pop af

                    ld b, 0
.hundreds:
                    cp 100
                    jr c, .have_hundreds
                    sub 100
                    inc b
                    jr .hundreds
.have_hundreds:
                    ld d, a
                    ld a, b
                    add a, '0'
                    rst $10

                    ld a, d
                    ld b, 0
.tens:
                    cp 10
                    jr c, .have_tens
                    sub 10
                    inc b
                    jr .tens
.have_tens:
                    ld d, a
                    ld a, b
                    add a, '0'
                    rst $10

                    ld a, d
                    add a, '0'
                    rst $10
                    ret

;-----------------------------------------------------------------------------
; draw_latched - hold an edge mask on screen for HOLD frames.
; Entry: a = this frame's edge mask, c = attribute row,
;        hl -> a 2-byte latch (mask, timer)
;-----------------------------------------------------------------------------
draw_latched:
                    and a
                    jr z, .no_event
                    ld (hl), a
                    inc hl
                    ld (hl), HOLD
                    dec hl
.no_event:
                    inc hl
                    ld a, (hl)
                    and a
                    jr z, .expired
                    dec a
                    ld (hl), a
                    dec hl
                    ld a, (hl)
                    jr draw_mask
.expired:
                    xor a
                    ; fall through

;-----------------------------------------------------------------------------
; draw_mask - paint three 2-cell blocks from a 3-bit mask.
; Entry: a = mask (bit 0 = RIGHT, bit 1 = LEFT, bit 2 = MIDDLE), c = row
; Corrupts a, b, c, d, e, h, l.
;-----------------------------------------------------------------------------
draw_mask:
                    ld e, a
                    ld h, 0
                    ld l, c
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld bc, DISPLAY_ATTRS + BLOCK_COL
                    add hl, bc

                    ld b, 3
.cell:
                    ld a, ATTR_OFF
                    srl e
                    jr nc, .off
                    ld a, ATTR_ON
.off:
                    ld (hl), a
                    inc hl
                    ld (hl), a
                    inc hl
                    ld (hl), a
                    inc hl
                    inc hl
                    inc hl
                    djnz .cell
                    ret

prev_x:             db 0
prev_y:             db 0
down_latch:         db 0, 0
up_latch:           db 0, 0

blank_tile:         db 0, 0, 0, 0, 0, 0, 0, 0
cursor_tile:        db %00011000
                    db %00011000
                    db %00011000
                    db %11111111
                    db %11111111
                    db %00011000
                    db %00011000
                    db %00011000

XY_COL              equ 4
ROW_XY              equ 19

txt_title:          db 22, 1, 8, "mouse.asm test bench"
txt_title_len       equ $ - txt_title

txt_labels:         db 22, 6, BLOCK_COL, "RGHT LEFT MID"
                    db 22, ROW_HELD, 0, "HELD"
                    db 22, ROW_DOWN, 0, "DOWN"
                    db 22, ROW_UP,   0, "UP"
                    db 22, ROW_XY,   0, "X:"
                    db 22, ROW_XY+1, 0, "Y:"
txt_labels_len      equ $ - txt_labels

                    savesna "mouse_test.sna", start
