;=============================================================================
; Text on screen, by two completely different mechanisms
;=============================================================================
; Placement:  org Text (sys/memmap.i). One file, two modules, because the two
;             ways of getting a character on screen share nothing but a name.
;
;   MODULE direct_text - writes the screen directly. These poke display
;   memory themselves. No channels, no set-up, no attributes touched, no
;   scrolling and no "scroll?" prompt. Nothing to initialise before the first
;   call. This is the path a game menu wants.
;
;   MODULE rom_text - through the ROM. These drive the channel system with
;   RST $10, so they obey the current PAPER/INK, move the ROM's own cursor,
;   scroll at the bottom of the screen and can raise the "scroll?" prompt.
;   They need the 48 BASIC ROM paged in, IY = $5C3A (the ROM reaches its
;   system variables through IY), and rom_text.open_upper called once first.
;
; The two module names answer one question: who writes the bytes. That is the
; only difference between them, and it is worth being blunt about because the
; old name for the first half was a `_pix` suffix, which everybody reads as
; "pixel coordinates". It never meant that. BOTH modules are addressed in
; character cells - column 0-31, row 0-23 - because one byte of the bitmap is
; eight horizontal pixels, so putting a glyph anywhere but a byte boundary
; would need a shift and a two-byte write, and neither of these does that.
; Nothing here takes a pixel coordinate.
;
; Depends on: screen.get_pix_addr_by_bc (itself a ROM call), beeper.click_beep,
;             and FONT_POINTER, which init_font sets to `fonts.font - 256` so
;             that character code 32 is the first glyph actually stored.
;=============================================================================

                    SLOT 1
                    PAGE 5
                    org Text

;=============================================================================
                    MODULE direct_text
;=============================================================================

;-----------------------------------------------------------------------------
; draw_string - HL = NUL-terminated string, D = row, E = column.
;
; Characters below 32 are skipped rather than drawn: they are control codes in
; the ROM's world and no glyph is stored for them. Clips at the right edge
; instead of running on - column 32 is the first byte of the next pixel row,
; so without the check a long string reappears eight lines up, which is a
; bewildering thing to debug.
;-----------------------------------------------------------------------------
draw_string:
                    ld a, e
                    cp 32
                    ret nc                      ; off the right edge - clip
                    ld a, (hl)
                    and a
                    ret z
                    inc hl
                    cp 32
                    jr c, draw_string           ; a control code: skip it
                    push de
                    push hl
                    call draw_char
                    pop hl
                    pop de
                    inc e
                    jr draw_string

;-----------------------------------------------------------------------------
; draw_string_mid - HL = string, D = row. Centres it on the row.
;
; Menus are full of this, and doing it at the call site means counting the
; string by hand and recounting it every time the wording changes.
;-----------------------------------------------------------------------------
draw_string_mid:
                    call string_length
                    cp 32
                    jr c, .fits
                    ld a, 32                    ; too long to centre: start at
.fits:                                          ; column 0 and let it clip
                    neg
                    add a, 32                   ; 32 - length
                    srl a                       ; ...halved. `srl`, not `rra`:
                    ld e, a                     ; the add above can leave carry
                    jp draw_string              ; set, and rra would shift it in

;-----------------------------------------------------------------------------
; string_length - HL = NUL-terminated string. Returns A = length (0-255),
; HL unchanged.
;-----------------------------------------------------------------------------
string_length:
                    push hl
                    ld b, 0
.count:
                    ld a, (hl)
                    and a
                    jr z, .done
                    inc hl
                    inc b
                    jr .count
.done:
                    ld a, b
                    pop hl
                    ret

;-----------------------------------------------------------------------------
; draw_char - A = character code, D = row, E = column.
;-----------------------------------------------------------------------------
draw_char:
                    ld l, a
                    ld h, 0
                    add hl, hl                  ; eight bytes to a glyph
                    add hl, hl
                    add hl, hl
                    ld bc, (FONT_POINTER)       ; stored base-256, so code 32
                    add hl, bc                  ; is the first glyph in the font
                    call cell_address           ; screen address into DE
                    ld a, (invert_mask)
                    ld c, a                     ; held in a register: this is
                    ld b, 8                     ; the inner loop of every menu
.row:
                    ld a, (hl)
                    xor c
                    ld (de), a
                    inc hl
                    inc d                       ; the next pixel row of a cell
                    djnz .row                   ; is 256 bytes on
                    ret

;-----------------------------------------------------------------------------
; invert_mask - XORed into every glyph byte draw_char writes. 0 draws
; normally, $FF draws it inverted.
;
; This is how a menu marks the selected line. The alternative - painting the
; attribute cells - cannot be undone without remembering what was underneath,
; and it colours the whole 8x8 cell whether or not there is a glyph in it.
;-----------------------------------------------------------------------------
invert_mask:        db 0

;-----------------------------------------------------------------------------
; cell_address - D = row (0-23), E = column (0-31). Returns the screen address
; of that cell's top pixel row in DE.
;
; The Spectrum's layout, low byte first: E = (row & 7) * 32 + column, and the
; four `rra` are that multiply by 32 - `and 7` leaves the carry clear, so
; rotating right four times through a 9-bit path brings the three bits back up
; into the top three, which is a rotate left by five. D = $40 + (row & 24)
; picks the third: $40, $48, $50.
;-----------------------------------------------------------------------------
cell_address:
                    ld a, d
                    and %00000111
                    rra
                    rra
                    rra
                    rra
                    or e
                    ld e, a
                    ld a, d
                    and %00011000
                    or %01000000
                    ld d, a
                    ret

;-----------------------------------------------------------------------------
; The two effects work on a "strip": eight pixel rows of one character row,
; `width` bytes across, starting at a character cell. Both need the caller to
; keep column + width within 32 - a strip that runs off the right edge
; continues into the next pixel row of the same cell, because that is what the
; next address is. They live in this module because they rewrite the bitmap
; directly, but note that both reach the screen through
; screen.get_pix_addr_by_bc, which is itself a ROM call.
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; scroll_strip_left - A = width in bytes, B = column, C = row.
;
; One pixel per call, wrapping: the pixel pushed off the left edge comes back
; in on the right. Call it once a frame for a marquee.
;-----------------------------------------------------------------------------
scroll_strip_left:
                    ld (strip_width), a
                    call screen.get_pix_addr_by_bc
                    ld a, (strip_width)
                    dec a
                    add a, l                    ; start at the rightmost byte
                    ld l, a
                    jr nc, .rows
                    inc h                       ; a carry out of the low byte is
.rows:                                          ; the next pixel row, which is
                    ld c, 8                     ; where the strip really goes
.row:
                    ld d, 0
                    ld a, (strip_width)
                    ld b, a
                    and a                       ; clears carry: nothing shifts
                    push hl                     ; in from the right yet
.byte:
                    rl (hl)                     ; right to left, so every byte
                    dec hl                      ; takes the bit that fell out of
                    djnz .byte                  ; the one to its right
                    rl d                        ; d bit 0 = the pixel pushed off
                    pop hl                      ; the left edge...
                    ld a, (hl)
                    or d                        ; ...put back on the right
                    ld (hl), a
                    inc h
                    dec c
                    jr nz, .row
                    ret

;-----------------------------------------------------------------------------
; dissolve_strip - D = width in bytes, E = number of passes, B = column,
; C = row. Eats the strip away a little more on each pass.
;
; The mask comes from address $0000 onwards - the ROM read as data. Sixteen
; kilobytes of bytes with no pattern to them is a better random source than
; anything worth writing, and it costs nothing. Two things follow: it only
; clears bits, never sets them, so this can erase a strip but never restore
; it; and it wants the 48 BASIC ROM paged in, because with TR-DOS or the 128
; editor ROM in place the pattern is a different one.
;-----------------------------------------------------------------------------
dissolve_strip:
                    push de
                    call screen.get_pix_addr_by_bc
                    ld (strip_addr), hl
                    pop de
                    ld a, d
                    ld (strip_width), a
                    ld a, e
                    ld de, 0                    ; the mask reads on from here,
.pass:                                          ; pass after pass
                    ld (passes_left), a
                    ld bc, 5
                    call PAUSE_BC
                    ld hl, (strip_addr)
                    ld c, 8
.row:
                    ld a, (strip_width)
                    ld b, a
                    push hl
.byte:
                    push bc
                    ld a, (hl)
                    ld b, a
                    ld a, (de)
                    and b
                    ld (hl), a
                    inc hl
                    inc de
                    pop bc
                    djnz .byte
                    pop hl
                    inc h
                    dec c
                    jr nz, .row
                    ld a, (passes_left)
                    dec a
                    jr nz, .pass
                    ret

strip_addr:         dw 0                        ; left edge of the strip
strip_width:        db 0                        ; bytes across
passes_left:        db 0                        ; dissolve_strip only

                    ENDMODULE