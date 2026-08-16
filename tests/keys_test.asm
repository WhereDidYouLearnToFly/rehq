;=============================================================================
; keys_test - visual test bench for core/input/keys.asm
;=============================================================================
; Open this file in zxide and press F5.
;
; Top half: five blocks, one per number key. A block lights for HOLD frames
; when keys.get_digit reports that number. What to check:
;   - pressing 3 lights the third block and nothing else
;   - holding it lights the block once, not over and over - it is a down edge
;   - releasing and pressing again lights it again
;
; Bottom half: whatever keys.read_char hands back, printed as you type.
;   - every letter and digit arrives once per press, in order
;   - CAPS SHIFT + 0 rubs out the last character
;   - ENTER, or CAPS SHIFT + SPACE, clears the line
;   - the CAPS and SYM markers light while those keys are held
;   - typing fast never repeats or drops a letter, and never leaves one stuck
;
; The two halves run off separate calls in the same frame on purpose: that is
; how a scene would use them, and it is what proves they do not eat each
; other's keypresses.
;=============================================================================

                    device zxspectrum48

; The org has to come before the include, or anything without an org of its
; own assembles from address 0 - underneath the ROM, where SAVESNA cannot
; reach it. keys.asm carries its own org, so this only covers the bench below.
                    org $8000

                    include "../core/input/keys.asm"

                    org $8000

DISPLAY_ATTRS       equ 22528
OPEN_SCREEN         equ 5633
PRINT_STRING_DE     equ 8252

ATTR_ON             equ %01000100       ; bright, black paper, green ink
ATTR_OFF            equ %00001000       ; blue paper, black ink - dim
ATTR_PAPER          equ %00000111       ; black paper, white ink

BLOCK_COL           equ 6               ; first attribute column of the blocks
ROW_BLOCKS          equ 6
HOLD                equ 12              ; frames a digit stays visible

TYPE_ROW            equ 12
TYPE_COL            equ 2
TYPE_MAX            equ 28              ; last column that accepts a character

CAPS_CELL           equ DISPLAY_ATTRS + 20 * 32 + 3
SYM_CELL            equ DISPLAY_ATTRS + 20 * 32 + 11

start:
                    di
                    ld sp, $7fff

                    ld a, 2                     ; upper screen, so RST $10 works
                    call OPEN_SCREEN

                    call clear_screen
                    ld de, txt_labels
                    ld bc, txt_labels_len
                    call PRINT_STRING_DE

                    call keys.flush             ; the key that started this is
                                                ; not the first thing typed
                    ei                          ; IM 1 - the bench only needs
                                                ; halt to pace itself

main_loop:
                    halt

;-----------------------------------------------------------------------------
; The number keys.
;-----------------------------------------------------------------------------
                    call keys.get_digit
                    and a
                    jr z, .no_digit
                    dec a                       ; 1..5 -> a bit in the mask
                    ld b, a
                    ld a, 1
                    inc b
.to_mask:
                    dec b
                    jr z, .latch
                    add a, a
                    jr .to_mask
.latch:
                    ld (digit_latch), a
                    ld a, HOLD
                    ld (digit_timer), a
.no_digit:
                    ld a, (digit_timer)
                    and a
                    jr z, .expired
                    dec a
                    ld (digit_timer), a
                    ld a, (digit_latch)
                    jr .paint
.expired:
                    xor a
.paint:
                    ld c, ROW_BLOCKS
                    call draw_mask

;-----------------------------------------------------------------------------
; Everything else.
;-----------------------------------------------------------------------------
                    call keys.read_char
                    and a
                    jr z, .no_char

                    cp 32
                    jr nc, .printable
                    cp keys.DELETE
                    jr z, .backspace
                    call clear_line             ; ENTER, BREAK, cursor keys
                    jr .no_char
.backspace:
                    ld a, (col)
                    cp TYPE_COL
                    jr z, .no_char              ; nothing left to rub out
                    dec a
                    ld (col), a
                    call at_cursor
                    ld a, ' '
                    rst 16
                    jr .no_char
.printable:
                    ld b, a                     ; b = the character
                    ld a, (col)
                    cp TYPE_MAX
                    jr z, .no_char              ; line full - drop it
                    call at_cursor
                    ld a, b
                    rst 16
                    ld a, (col)
                    inc a
                    ld (col), a
.no_char:

;-----------------------------------------------------------------------------
; The shift markers, straight from what read_char saw this frame.
;-----------------------------------------------------------------------------
                    ld a, (keys.modifiers)
                    ld c, a
                    ld hl, CAPS_CELL
                    bit 0, c
                    call mark
                    ld hl, SYM_CELL
                    bit 1, c
                    call mark

                    jp main_loop

;-----------------------------------------------------------------------------
; mark - light or dim four cells from hl, on the Z flag as set by the caller.
;-----------------------------------------------------------------------------
mark:
                    ld a, ATTR_OFF
                    jr z, .paint
                    ld a, ATTR_ON
.paint:
                    ld b, 4
.cell:
                    ld (hl), a
                    inc hl
                    djnz .cell
                    ret

;-----------------------------------------------------------------------------
; at_cursor - move the ROM's print position to TYPE_ROW, (col).
;-----------------------------------------------------------------------------
at_cursor:
                    ld a, 22                    ; AT
                    rst 16
                    ld a, TYPE_ROW
                    rst 16
                    ld a, (col)
                    rst 16
                    ret

;-----------------------------------------------------------------------------
; clear_line - blank the typed line and start again at the left.
;-----------------------------------------------------------------------------
clear_line:
                    ld a, TYPE_COL
                    ld (col), a
                    ld b, TYPE_MAX - TYPE_COL + 1
.next:
                    push bc
                    call at_cursor
                    ld a, ' '
                    rst 16
                    ld a, (col)
                    inc a
                    ld (col), a
                    pop bc
                    djnz .next
                    ld a, TYPE_COL
                    ld (col), a
                    ret

;-----------------------------------------------------------------------------
; draw_mask - paint five 3-cell blocks from a 5-bit mask.
; Entry: a = mask (bit 0 = leftmost block), c = attribute row 0..23
;-----------------------------------------------------------------------------
draw_mask:
                    ld e, a                     ; e = mask
                    ld h, 0
                    ld l, c
                    add hl, hl                  ; row * 32
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld bc, DISPLAY_ATTRS + BLOCK_COL
                    add hl, bc

                    ld b, 5
.cell:
                    ld a, ATTR_OFF
                    srl e                       ; carry = this key's bit
                    jr nc, .off
                    ld a, ATTR_ON
.off:
                    ld (hl), a                  ; three cells wide...
                    inc hl
                    ld (hl), a
                    inc hl
                    ld (hl), a
                    inc hl
                    inc hl                      ; ...then a two-cell gap, so
                    inc hl                      ; blocks sit 5 columns apart
                    djnz .cell
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

col:                db TYPE_COL
digit_latch:        db 0
digit_timer:        db 0

; AT row,col control codes are embedded in the strings, so the whole screen
; goes up in one call.
txt_labels:         db 22, 1, 6, "keys.asm test bench"
                    db 22, 4, 0, "get_digit"
                    ; One 5-char field per block, over the columns draw_mask
                    ; paints: 6, 11, 16, 21, 26.
                    db 22, 4, BLOCK_COL, "1    2    3    4    5"
                    db 22, 9, 0, "read_char  ENTER clears"
                    db 22, 10, 0, "           CAPS+0 rubs out"
                    db 22, 20, 0, "CS", 22, 20, 9, "SS"
txt_labels_len      equ $ - txt_labels

                    savesna "keys_test.sna", start
