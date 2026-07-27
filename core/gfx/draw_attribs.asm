;=============================================================================
; attrs - attribute-area fills, blits and wipes
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: screen (attr_addr_from_char_xy)
; Namespace:  MODULE attrs - every label below is reached as attrs.*
;
;   fill_rect          set a rectangle to one attribute
;   copy_to_screen     blit stored attributes onto the screen
;   copy_from_screen   read them back off it
;   wipe_*             six full-screen transitions, one character row or
;                      column per frame
;
; The attribute area is linear - 32 bytes per row, 24 rows - which is why
; these are cheap enough to run every frame while the pixels stay put.
;
; The wipes call HALT to pace themselves, so interrupts must be enabled or
; they hang. They are blocking: each one runs to completion before returning.
;=============================================================================

                    MODULE attrs

ATTRS               equ $5800
ROW_BYTES           equ 32
ROWS                equ 24

;-----------------------------------------------------------------------------
; fill_rect - set a rectangle of cells to one attribute.
; Entry: a = attribute, b = column, c = row,
;        d = width in cells, e = height in cells
; Corrupts a, b, c, d, e, h, l.
;-----------------------------------------------------------------------------
fill_rect:
                    ld (rect_attr), a
                    ld (rect_h), de             ; e -> rect_h, d -> rect_w
                    call screen.attr_addr_from_char_xy
                    ld a, (rect_h)
                    ld c, a
.row:
                    push hl
                    ld a, (rect_w)
                    ld b, a
                    ld a, (rect_attr)
.cell:
                    ld (hl), a
                    inc hl
                    djnz .cell
                    pop hl
                    ld de, ROW_BYTES
                    add hl, de
                    dec c
                    jr nz, .row
                    ret

rect_attr:          db 0
rect_h:             db 0
rect_w:             db 0                        ; must stay adjacent, in this order

;-----------------------------------------------------------------------------
; copy_to_screen - blit a block of stored attributes onto the screen.
; Entry: hl = source, b = column, c = row,
;        d = width in cells, e = height in cells
; Corrupts a, b, c, d, e, h, l.
;-----------------------------------------------------------------------------
copy_to_screen:
                    call blit_setup             ; hl = data, de = screen
                    ld a, (blit_h)
                    ld c, a
.row:
                    ld a, (blit_w)
                    ld b, a
.cell:
                    ld a, (hl)
                    ld (de), a
                    inc hl
                    inc de
                    djnz .cell
                    call next_row               ; de to the next row's start
                    dec c
                    jr nz, .row
                    ret

;-----------------------------------------------------------------------------
; copy_from_screen - read a block of screen attributes into a buffer.
; Entry: hl = destination, b = column, c = row,
;        d = width in cells, e = height in cells
; Corrupts a, b, c, d, e, h, l.
;
; The mirror of copy_to_screen. These are two routines rather than one with a
; patched load/store because self-modifying code that an interrupt can land in
; the middle of is not worth the dozen bytes it saves.
;-----------------------------------------------------------------------------
copy_from_screen:
                    call blit_setup             ; hl = buffer, de = screen
                    ld a, (blit_h)
                    ld c, a
.row:
                    ld a, (blit_w)
                    ld b, a
.cell:
                    ld a, (de)
                    ld (hl), a
                    inc hl
                    inc de
                    djnz .cell
                    call next_row
                    dec c
                    jr nz, .row
                    ret

;-----------------------------------------------------------------------------
; blit_setup - shared entry work: stash the size, resolve the screen address.
; Entry: hl = data, b = column, c = row, d = width, e = height
; Exit:  hl = data (unchanged), de = screen address.
;-----------------------------------------------------------------------------
blit_setup:
                    ld (blit_h), de             ; e -> blit_h, d -> blit_w
                    push hl
                    call screen.attr_addr_from_char_xy
                    ex de, hl
                    pop hl
                    ret

;-----------------------------------------------------------------------------
; next_row - step de from the end of one row's slice to the start of the next.
; Corrupts a, h, l.
;-----------------------------------------------------------------------------
next_row:
                    push hl
                    ld a, ROW_BYTES
                    ld hl, blit_w
                    sub (hl)                    ; whatever the slice did not cover
                    ld l, a
                    ld h, 0
                    add hl, de
                    ex de, hl
                    pop hl
                    ret

blit_h:             db 0
blit_w:             db 0                        ; must stay adjacent, in this order

;=============================================================================
; Wipes. Each takes a = attribute and paces itself with HALT.
;=============================================================================

;-----------------------------------------------------------------------------
; wipe_left_to_right / wipe_right_to_left - one column per frame.
;-----------------------------------------------------------------------------
wipe_left_to_right:
                    ld (wipe_attr), a
                    ld hl, ATTRS
                    ld b, ROW_BYTES
.col:
                    push bc
                    push hl
                    call fill_column
                    pop hl
                    pop bc
                    inc hl
                    halt
                    djnz .col
                    ret

wipe_right_to_left:
                    ld (wipe_attr), a
                    ld hl, ATTRS + ROW_BYTES - 1
                    ld b, ROW_BYTES
.col:
                    push bc
                    push hl
                    call fill_column
                    pop hl
                    pop bc
                    dec hl
                    halt
                    djnz .col
                    ret

;-----------------------------------------------------------------------------
; wipe_centre_to_side / wipe_side_to_centre - two columns per frame, moving
; apart or together. The two heads are kept in memory because fill_column
; needs the registers.
;-----------------------------------------------------------------------------
wipe_centre_to_side:
                    ld (wipe_attr), a
                    ld hl, ATTRS + 15
                    ld (wipe_l), hl
                    ld hl, ATTRS + 16
                    ld (wipe_r), hl
                    ld b, ROW_BYTES / 2
.step:
                    push bc
                    call fill_both_columns
                    ld hl, (wipe_l)
                    dec hl
                    ld (wipe_l), hl
                    ld hl, (wipe_r)
                    inc hl
                    ld (wipe_r), hl
                    pop bc
                    halt
                    djnz .step
                    ret

wipe_side_to_centre:
                    ld (wipe_attr), a
                    ld hl, ATTRS
                    ld (wipe_l), hl
                    ld hl, ATTRS + ROW_BYTES - 1
                    ld (wipe_r), hl
                    ld b, ROW_BYTES / 2
.step:
                    push bc
                    call fill_both_columns
                    ld hl, (wipe_l)
                    inc hl
                    ld (wipe_l), hl
                    ld hl, (wipe_r)
                    dec hl
                    ld (wipe_r), hl
                    pop bc
                    halt
                    djnz .step
                    ret

fill_both_columns:
                    ld hl, (wipe_l)
                    call fill_column
                    ld hl, (wipe_r)
                    ; fall through

;-----------------------------------------------------------------------------
; fill_column - set every cell of one attribute column.
; Entry: hl = top cell. Corrupts a, c, d, e, h, l.
;-----------------------------------------------------------------------------
fill_column:
                    ld de, ROW_BYTES
                    ld c, ROWS
                    ld a, (wipe_attr)
.cell:
                    ld (hl), a
                    add hl, de
                    dec c
                    jr nz, .cell
                    ret

;-----------------------------------------------------------------------------
; wipe_top_to_bottom / wipe_bottom_to_top - one row per frame.
;-----------------------------------------------------------------------------
wipe_top_to_bottom:
                    ld (wipe_attr), a
                    ld hl, ATTRS
                    ld b, ROWS
.row:
                    push bc
                    ld b, ROW_BYTES
                    ld a, (wipe_attr)
.cell:
                    ld (hl), a
                    inc hl
                    djnz .cell
                    pop bc
                    halt
                    djnz .row
                    ret

wipe_bottom_to_top:
                    ld (wipe_attr), a
                    ld hl, ATTRS + (ROWS * ROW_BYTES) - 1
                    ld b, ROWS
.row:
                    push bc
                    ld b, ROW_BYTES
                    ld a, (wipe_attr)
.cell:
                    ld (hl), a
                    dec hl
                    djnz .cell
                    pop bc
                    halt
                    djnz .row
                    ret

wipe_attr:          db 0
wipe_l:             dw 0
wipe_r:             dw 0

                    ENDMODULE
