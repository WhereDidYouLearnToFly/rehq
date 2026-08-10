            org $5DC0
            MODULE rom_text
;=============================================================================

;-----------------------------------------------------------------------------
; open_upper - open the upper screen as the print channel. Once, before
; anything else in this module.
;-----------------------------------------------------------------------------
open_upper:
                    ld a, 2                     ; stream 2 = the upper screen
                    jp OPEN_SCREEN

;-----------------------------------------------------------------------------
; print_string - DE = address, BC = length. Not NUL-terminated: the ROM's
; routine is given a length, which is why it can print a string containing 0.
;-----------------------------------------------------------------------------
print_string:
                    jp PRINT_STRING_FROM_DE

;-----------------------------------------------------------------------------
; print_number - BC = an unsigned 16-bit value, printed as decimal. Variable
; width: 100 -> 99 leaves the stale third digit on screen, so for a counter
; that can shrink, print your own fixed-width digits.
;-----------------------------------------------------------------------------
print_number:
                    call PUT_DEC_BC_TO_STACK    ; push the value on the ROM's
                    jp PRINT_TOP_STACK          ; calculator stack, then print it

;-----------------------------------------------------------------------------
; set_cursor - B = column (0-31), C = row (0-23).
;-----------------------------------------------------------------------------
set_cursor:
                    ld a, $16                   ; the AT control code...
                    rst $10
                    ld a, c                     ; ...which takes row first
                    rst $10
                    ld a, b                     ; and column second
                    rst $10
                    ret

;-----------------------------------------------------------------------------
; print_teletype_at - type a string out one character at a time, wrapping.
;   HL = NUL-terminated string
;   B  = column, C = row of the first character
;   A  = wrap width in characters (0 = never wrap)
;
; Set delay_frames first; it is the pause between characters.
;
; The wrap is by column count, not by word: a line breaks mid-word. Fixing
; that means looking ahead for the next space, which is a different routine
; and not one this needed.
;-----------------------------------------------------------------------------
print_teletype_at:
                    ld (wrap_width), a
                    ld (cursor_pos), bc
.line:
                    call set_cursor
                    call print_teletype         ; types until the string ends
                                                ; or the line fills up
                    ld a, (hl)                  ; ended exactly on the wrap
                    and a                       ; column? then there is no next
                    jr z, .done                 ; line, only a stray cursor
                    ld bc, (cursor_pos)
                    inc c                       ; same column, next row down
                    ld (cursor_pos), bc
                    ld a, (column_count)
                    and a                       ; zero means "the line filled
                    jr z, .line                 ; up", not "the string ended"
.done:
                    xor a
                    ld (column_count), a
                    ret

;-----------------------------------------------------------------------------
; print_teletype - HL = string, typed from wherever the cursor already is.
;
; Stops on the terminator, or after wrap_width characters if that is not zero.
; The caller tells the two apart by column_count: zero means the line filled
; up and there is more string left, non-zero means the string ended. That is
; the whole contract between this and print_teletype_at.
;
; Enter at print_teletype_nowrap to type a single line of any length.
;-----------------------------------------------------------------------------
print_teletype_nowrap:
                    xor a
                    ld (wrap_width), a
print_teletype:
                    ld a, (wrap_width)
                    and a
                    jr z, .no_wrap
                    ld b, a
                    ld a, (column_count)
                    cp b
                    jr nz, .count
                    xor a                       ; the line is full
                    ld (column_count), a
                    jr .erase_cursor
.count:
                    inc a
                    ld (column_count), a
.no_wrap:
                    ld a, (hl)
                    and a
                    jr nz, .print
.erase_cursor:
                    ld a, ' '                   ; wipe the block cursor, or it
                    rst $10                     ; is left sitting in the text
                    ret
.print:
                    rst $10
                    inc hl
                    push hl                     ; the ROM print routines below
                                                ; are not trusted with HL
                    ld de, CURSOR_BLOCK
                    ld bc, 4
                    call PRINT_STRING_FROM_DE
                    call DROP_TEMP_ATTRIBS
                    call beeper.click_beep
                    ld bc, (delay_frames)
                    call PAUSE_BC
                    pop hl
                    jr print_teletype

; The block cursor: PAPER (17) green (4), a space to paint the cell, then
; backspace (8) to step back over it so the next character lands there.
CURSOR_BLOCK:       db 17, 4, ' ', 8

delay_frames:       dw 1                        ; pause per character
wrap_width:         db 0                        ; 0 = never wrap
column_count:       db 0                        ; characters on this line so far
cursor_pos:         dw 0                        ; b = column, c = row of the
                                                ; line being typed

            ENDMODULE       
