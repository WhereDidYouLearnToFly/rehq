;=============================================================================
; text - character output, both through the ROM and straight to pixels
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: screen (addr_from_char_xy), and the 48K ROM.
; Namespace:  MODULE text - every label below is reached as text.*
;
; There are two independent ways to print here, and they do not mix:
;
;   ROM printing        open_upper, print_string, print_number, set_cursor,
;                       print_teletype_at
;     Goes through RST $10, so it honours AT codes, INK/PAPER control codes and
;     scrolling, and costs nothing in code size. Requires open_upper first -
;     without it RST $10 writes to whatever channel was last selected.
;
;   Direct pixel print  print_char_pix, print_string_pix
;     Writes glyphs to the display file itself. No control codes, no scrolling,
;     no channel needed, and it does not disturb the ROM's cursor. Use it for
;     text at pixel positions or inside a running frame loop.
;
; Both read glyphs through the CHARS system variable, so a custom font is
; installed by pointing CHARS at it - fontbase minus 256, since code 32 is the
; first printable character.
;=============================================================================

                    MODULE text

; ROM entry points and system variables. Declared here rather than pulled from
; zxspectrum.i so the module stands alone; MODULE scoping keeps these distinct
; from any global of the same name.
OPEN_SCREEN         equ 5633            ; open a channel, a = stream
PRINT_STRING_DE     equ 8252            ; print bc bytes from (de)
DROP_TEMP_ATTRIBS   equ 3405            ; discard temporary INK/PAPER
DEC_BC_TO_STACK     equ 11563           ; push bc onto the calculator stack
PRINT_TOP_STACK     equ 11747           ; print the top of it
CHARS               equ 23606           ; font base - 256

;-----------------------------------------------------------------------------
; open_upper - select the main screen area for RST $10.
; Call once before any ROM printing. Corrupts a and more inside the ROM.
;-----------------------------------------------------------------------------
open_upper:
                    ld a, 2
                    jp OPEN_SCREEN

;-----------------------------------------------------------------------------
; print_string - print a counted string through the ROM.
; Entry: de = string, bc = length.
;-----------------------------------------------------------------------------
print_string:
                    jp PRINT_STRING_DE

;-----------------------------------------------------------------------------
; print_number - print bc as decimal through the ROM.
;-----------------------------------------------------------------------------
print_number:
                    call DEC_BC_TO_STACK
                    jp PRINT_TOP_STACK

;-----------------------------------------------------------------------------
; set_cursor - move the ROM print position.
; Entry: b = column 0..31, c = row 0..21
;
; Rows 22 and 23 belong to the lower screen and are not reachable from
; channel 2; the ROM reports "Integer out of range" rather than printing there.
;-----------------------------------------------------------------------------
set_cursor:
                    ld a, 22                    ; AT
                    rst $10
                    ld a, c                     ; row first
                    rst $10
                    ld a, b                     ; then column
                    rst $10
                    ret

;=============================================================================
; Teletype printing
;=============================================================================

;-----------------------------------------------------------------------------
; print_teletype_at - print a NUL-terminated string one character at a time,
; with a trailing cursor block and a delay between characters.
; Entry: hl = string, b = column, c = row, a = wrap width (0 = do not wrap)
; Requires: open_upper called, interrupts enabled (the delay uses HALT).
; Corrupts a, b, c, d, e, h, l.
;
; Terminates on the NUL, not on the wrap width - so the string must actually
; be terminated. Wrapping returns to the starting column on the next row.
;-----------------------------------------------------------------------------
print_teletype_at:
                    ld (tt_width), a
                    ld a, b
                    ld (tt_x), a
                    ld a, c
                    ld (tt_y), a
                    ld (tt_str), hl
.line:
                    ld a, (tt_x)
                    ld b, a
                    ld a, (tt_y)
                    ld c, a
                    call set_cursor
                    xor a
                    ld (tt_col), a
.char:
                    ld hl, (tt_str)
                    ld a, (hl)
                    and a
                    jr z, .done
                    inc hl
                    ld (tt_str), hl
                    rst $10                     ; the character itself

                    ld de, cursor_block         ; then the cursor, which the
                    ld bc, cursor_block_len     ; next character overwrites
                    call PRINT_STRING_DE
                    call DROP_TEMP_ATTRIBS

                    call on_char_hook
                    call delay

                    ld a, (tt_width)
                    and a
                    jr z, .char                 ; no wrapping
                    ld hl, tt_col
                    inc (hl)
                    cp (hl)
                    jr nz, .char
                    ld hl, tt_y                 ; wrap to the next row
                    inc (hl)
                    jr .line
.done:
                    ld a, ' '                   ; erase the cursor block
                    rst $10
                    jp DROP_TEMP_ATTRIBS

; INK 4, a space to draw the block, then backspace so the print position sits
; back on it. Printing anything next overwrites the block.
cursor_block:       db 17, 4, ' ', 8
cursor_block_len    equ $ - cursor_block

;-----------------------------------------------------------------------------
; on_char_hook - called after each teletype character. Defaults to a RET.
;
; Point on_char at a routine to make the teletype tick, click or beep without
; this module depending on a sound module:
;
;       ld hl, beeper.click
;       ld (text.on_char), hl
;-----------------------------------------------------------------------------
on_char_hook:
                    ld hl, (on_char)
                    jp (hl)

on_char:            dw hook_ret
hook_ret:           ret

;-----------------------------------------------------------------------------
; delay - wait delay_frames frames. Requires interrupts enabled.
;-----------------------------------------------------------------------------
delay:
                    ld a, (delay_frames)
                    and a
                    ret z
                    ld b, a
.loop:
                    halt
                    djnz .loop
                    ret

delay_frames:       db 2                        ; per character; 0 = as fast as it draws
tt_str:             dw 0
tt_x:               db 0
tt_y:               db 0
tt_width:           db 0
tt_col:             db 0

;=============================================================================
; Direct-to-pixel printing
;=============================================================================

;-----------------------------------------------------------------------------
; print_string_pix - print a NUL-terminated string straight to the display.
; Entry: hl = string, d = row 0..23, e = column 0..31
; Corrupts a, b, c, d, e, h, l.
;
; Characters below 32 are skipped rather than interpreted - there are no
; control codes on this path.
;-----------------------------------------------------------------------------
print_string_pix:
                    ld a, (hl)
                    and a
                    ret z
                    inc hl
                    cp 32
                    jr c, print_string_pix      ; not printable, skip it
                    push de
                    push hl
                    call print_char_pix
                    pop hl
                    pop de
                    inc e                       ; next column
                    jr print_string_pix

;-----------------------------------------------------------------------------
; print_char_pix - draw one glyph.
; Entry: a = character code, d = row 0..23, e = column 0..31
; Corrupts a, b, c, d, e, h, l.
;-----------------------------------------------------------------------------
print_char_pix:
                    ld hl, (CHARS)              ; font base - 256
                    ld b, 0
                    ld c, a
                    sla c                       ; code * 8
                    rl b
                    sla c
                    rl b
                    sla c
                    rl b
                    add hl, bc                  ; hl = glyph
                    call char_addr_pix          ; de = screen
                    ld b, 8
.line:
                    ld a, (hl)
                    ld (de), a
                    inc hl
                    inc d                       ; next pixel row of the cell
                    djnz .line
                    ret

;-----------------------------------------------------------------------------
; char_addr_pix - screen address of a character cell, from row/column already
; in d/e.
; Entry: d = row 0..23, e = column 0..31
; Exit:  de = screen address. Corrupts a.
;
; Same arithmetic as screen.addr_from_char_xy, but taking and returning de, so
; the glyph loop can keep hl on the font. rrca rather than rra: the value is
; only three bits wide, so a true 8-bit rotate places it without depending on
; the carry.
;-----------------------------------------------------------------------------
char_addr_pix:
                    ld a, d
                    and %00000111               ; row within the third...
                    rrca                        ; ...into bits 5-7
                    rrca
                    rrca
                    or e
                    ld e, a
                    ld a, d
                    and %00011000               ; which third
                    or %01000000
                    ld d, a
                    ret

;-----------------------------------------------------------------------------
; scroll_line_1pix - scroll one character row left by a single pixel, with
; the bits that fall off the left edge wrapping back in at the right.
; Entry: a = width in bytes, b = column, c = row 0..23
; Corrupts a, b, c, d, e, h, l.
;
; Works right-to-left so each RL feeds its carry into the byte to its left.
; The carry out of the leftmost byte is what wraps around.
;-----------------------------------------------------------------------------
scroll_line_1pix:
                    ld (scroll_width), a
                    call screen.addr_from_char_xy
                    ld a, (scroll_width)
                    dec a
                    add a, l                    ; hl = rightmost byte of the row
                    ld l, a
                    ld c, 8                     ; eight pixel lines in a cell
.line:
                    ld d, 0
                    ld a, (scroll_width)
                    ld b, a
                    and a                       ; clear carry before the first RL
                    push hl
.byte:
                    rl (hl)
                    dec hl
                    djnz .byte
                    rl d                        ; catch the bit that fell off
                    pop hl
                    ld a, (hl)
                    or d                        ; and wrap it in at the right
                    ld (hl), a
                    inc h                       ; next pixel row of the cell
                    dec c
                    jr nz, .line
                    ret

scroll_width:       db 0

                    ENDMODULE
