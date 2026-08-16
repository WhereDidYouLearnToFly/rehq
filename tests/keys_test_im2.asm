;=============================================================================
; keys_test_im2 - the keys.asm bench again, this time under IM2
;=============================================================================
; Open this file in zxide and press F5.
;
; keys_test.asm runs under IM1 and only uses `halt` to pace itself. This one
; runs the real thing: core/interrupt.asm's IM2 handler, at the addresses the
; game pins it to. Everything below the heartbeat is the same bench, so the
; difference between the two files is the interrupt mode and nothing else -
; which is what makes "keys work here but not there" mean something.
;
; What to check, in this order:
;
;   1. A red band across the top of the border, every frame. That is the ISR
;      itself painting while it runs, so it is proof the handler is reached.
;      No band means the interrupt never gets there - init_im2 did not run,
;      or something is sitting on $8181/$8200-$8300.
;   2. The heartbeat cell top-right flickers. Same proof from the other side:
;      the main loop is reading a counter only the ISR increments.
;   3. Then the keyboard, exactly as in keys_test.asm: the five digit blocks
;      off get_digit, and the typed line off read_char.
;
; If 1 and 2 are alive and 3 is dead, the interrupt is fine and something is
; eating the down edge - look for a second caller of read_char/get_digit.
;
; Note what is deliberately NOT here: any chain to the ROM's $0038 handler.
; keys.asm reads port $FE for itself, so nothing it needs comes from the ROM
; interrupt. If this bench types, the keyboard does not need the chain.
;=============================================================================

                    device zxspectrum48

                    include "../sys/zxspectrum.i"   ; IM1_I_VALUE, OPEN_SCREEN...

; Same reason as the IM1 bench: an include without an org of its own would
; assemble from address 0, under the ROM where SAVESNA cannot reach it.
; keys.asm carries its own org ($6300), so this only covers what follows.
                    org $8000
                    include "../core/input/keys.asm"

; init_im2/init_im1/on_tick take no org of their own - they land wherever the
; including file has got to. They have to end below $8181, which is where
; interrupt.asm pins its handler (the ASSERTs in that file check it).
                    org $8000
                    include "../core/interrupt.asm"

; Clear of both pinned regions: the handler at $8181 and the 257-byte vector
; table at $8200-$8300. The IM1 bench sits at $8000 and ends at $810E, which
; is 115 bytes below the handler -- fine there, fatal here, because this one
; actually uses it.
                    org $8400

OPEN_UPPER_SCREEN   equ 2               ; stream 2, so RST 16 goes to the screen

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
HEART_CELL          equ DISPLAY_ATTRS + 0 * 32 + 31

BORDER_ISR          equ 2               ; red - the band the ISR paints
BORDER_IDLE         equ 0               ; black

start:
                    di
                    ld sp, $7fff

                    ld a, OPEN_UPPER_SCREEN
                    call OPEN_SCREEN

                    call clear_screen
                    ld de, txt_labels
                    ld bc, txt_labels_len
                    call PRINT_STRING_FROM_DE

                    call keys.flush             ; the key that started this is
                                                ; not the first thing typed

                    ; The whole point of this bench: the real IM2 setup, not
                    ; a bare `ei`. It fills the table, points i at it, and
                    ; enables interrupts itself.
                    call interrupt.init_im2

main_loop:
                    halt

;-----------------------------------------------------------------------------
; The heartbeat: a counter only the ISR touches, so the main loop watching it
; change proves the handler is running - the same fact the border band shows,
; from the side that can be read rather than watched.
;-----------------------------------------------------------------------------
                    ld a, (game.ticks)
                    and %00001000               ; flips about six times a second
                    ld a, ATTR_OFF
                    jr z, .dim
                    ld a, ATTR_ON
.dim:
                    ld (HEART_CELL), a

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

;=============================================================================
; The interrupt side
;=============================================================================
; interrupt.asm's on_tick is `jp game.onInterrupt`, so a bench that includes
; the real handler has to supply that symbol - which suits this one, because
; the tick is where the proof lives. It stays deliberately tiny: paint the
; border for as long as the ISR runs, count the frame, and get out. Nothing
; here reads the keyboard, and that matters - a second caller of read_char in
; the ISR would swallow the down edge the main loop is waiting for, which is
; the failure this bench is meant to be able to rule out.
;=============================================================================

                    MODULE game
onInterrupt:
                    ld a, BORDER_ISR
                    out ($fe), a

                    ld hl, ticks
                    inc (hl)

                    ld a, BORDER_IDLE
                    out ($fe), a
                    ret

ticks:              db 0
                    ENDMODULE

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
                    ld hl, DISPLAY_PIXELS
                    ld de, DISPLAY_PIXELS + 1
                    ld bc, 6144 - 1
                    ld (hl), 0
                    ldir

                    ld hl, DISPLAY_ATTRS
                    ld de, DISPLAY_ATTRS + 1
                    ld bc, 768 - 1
                    ld (hl), ATTR_PAPER
                    ldir

                    ld a, BORDER_IDLE
                    out ($fe), a
                    ret

col:                db TYPE_COL
digit_latch:        db 0
digit_timer:        db 0

; AT row,col control codes are embedded in the strings, so the whole screen
; goes up in one call.
txt_labels:         db 22, 1, 6, "keys.asm test bench - IM2"
                    db 22, 2, 6, "red band + top-right cell"
                    db 22, 3, 6, "= the ISR is running"
                    ; One 5-char field per block, over the columns draw_mask
                    ; paints: 6, 11, 16, 21, 26.
                    db 22, 4, BLOCK_COL, "1    2    3    4    5"
                    db 22, 9, 0, "read_char  ENTER clears"
                    db 22, 10, 0, "           CAPS+0 rubs out"
                    db 22, 20, 0, "CS", 22, 20, 9, "SS"
txt_labels_len      equ $ - txt_labels

                    savesna "keys_test_im2.sna", start
