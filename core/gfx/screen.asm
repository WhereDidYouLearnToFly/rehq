;=============================================================================
; screen - ZX Spectrum display addressing, and whole-screen clears
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: nothing.
; Namespace:  MODULE screen - every label below is reached as screen.*
;
; The display file is not linear. A pixel address is
;
;       H = 0 1 0 T T L L L      TT  = which third (0..2)
;       L = R R R C C C C C      LLL = pixel row within the character cell
;                                RRR = character row within the third
;                                CCCCC = character column
;
; so "one pixel line down" is three different operations depending on where
; you are. Two routines below are the whole answer to that:
;
;   addr_from_line   random access - any line, from scratch
;   next_line        the incremental step, for walking down a sprite
;
; next_line is the one that matters in inner loops. It is eight bytes of
; branchy arithmetic that replaces a table lookup per line, and every blitter
; in this engine is built on it.
;=============================================================================

                    MODULE screen

PIXELS              equ $4000
ATTRS               equ $5800
PIXELS_LEN          equ 6144
ATTRS_LEN           equ 768

;-----------------------------------------------------------------------------
; addr_from_line - pixel address of the leftmost byte of a pixel line.
; Entry: a  = pixel line 0..191
; Exit:  hl = screen address. Corrupts a.
;
; Computed rather than looked up. The classic 192-entry table costs 384 bytes
; and saves about 20 T-states; since the blitters call this once per sprite
; and then use next_line, the table is not worth its space here.
;-----------------------------------------------------------------------------
addr_from_line:
                    ld l, a
                    and %00000111               ; LLL - row within the cell
                    ld h, a
                    ld a, l
                    rra                         ; TT - which third, from bits 6-7
                    rra
                    rra
                    and %00011000
                    or h
                    or $40                      ; display file starts at $4000
                    ld h, a
                    ld a, l
                    and %00111000               ; RRR - char row within the third
                    rlca
                    rlca
                    ld l, a
                    ret

;-----------------------------------------------------------------------------
; addr_from_char_xy - pixel address of the top-left byte of a character cell.
; Entry: b = column 0..31, c = row 0..23
; Exit:  hl = screen address. Corrupts a.
;-----------------------------------------------------------------------------
addr_from_char_xy:
                    ld a, c
                    add a, a                    ; row * 8 = its first pixel line
                    add a, a
                    add a, a
                    call addr_from_line
                    ld a, l                     ; low 5 bits of l are zero here,
                    or b                        ; so the column just drops in
                    ld l, a
                    ret

;-----------------------------------------------------------------------------
; attr_addr_from_char_xy - attribute address of a character cell.
; Entry: b = column 0..31, c = row 0..23
; Exit:  hl = attribute address. Corrupts a, d, e.
;
; Attributes are linear, so this is a plain multiply-add - no thirds, no
; interleaving. This is why attribute effects are cheap and pixel ones are not.
;-----------------------------------------------------------------------------
attr_addr_from_char_xy:
                    ld h, 0
                    ld l, c
                    add hl, hl                  ; row * 32
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld d, 0
                    ld e, b
                    add hl, de
                    ld de, ATTRS
                    add hl, de
                    ret

;-----------------------------------------------------------------------------
; next_line - move a screen address down one pixel line, in place.
; Entry: de = screen address
; Exit:  de = the address one pixel line below. Corrupts a.
;
; inc d moves down inside the character cell. When that carries out of the
; low three bits the cell is finished, so the character row advances (e += 32).
; If *that* carries we have also crossed into the next third - which inc d
; happens to have already done, so d is left alone. If it did not, inc d
; overshot and the third has to be handed back.
;
; Wrapping off the bottom of the screen is not checked for. Callers pass a
; line count; nothing here defends against being asked for line 192.
;-----------------------------------------------------------------------------
next_line:
                    inc d                       ; next pixel row in this cell
                    ld a, d
                    and 7
                    ret nz                      ; still inside the cell - done
                    ld a, e
                    add a, 32                   ; next character row
                    ld e, a
                    ret c                       ; carried into the next third
                    ld a, d
                    sub 8                       ; undo inc d's third bump
                    ld d, a
                    ret

;-----------------------------------------------------------------------------
; clear_pixels - blank the whole pixel area.
; Corrupts a, b, c, h, l. Leaves interrupts enabled.
;
; push writes two bytes and moves SP down by two, so pointing SP at the end of
; the display file and pushing turns the stack into the fastest block-fill the
; Z80 has - 11 T-states per two bytes against LDIR's 21. The cost is that SP
; is not a stack for the duration, hence DI, and the real one is stashed in
; the instruction that restores it.
;-----------------------------------------------------------------------------
clear_pixels:
                    di
                    ld (.restore_sp + 1), sp
                    ld hl, 0                    ; the value written
                    ld sp, PIXELS + PIXELS_LEN
                    ld c, 3                     ; 3 * 256 * 8 = 6144 bytes
.third:
                    ld b, l                     ; b = 0, so djnz runs 256 times
.block:
                    push hl
                    push hl
                    push hl
                    push hl
                    djnz .block
                    dec c
                    jr nz, .third
.restore_sp:
                    ld sp, 0                    ; operand patched on entry
                    ei
                    ret

;-----------------------------------------------------------------------------
; fill_attrs - set every attribute cell.
; Entry: a = attribute byte. Corrupts b, c, d, e, h, l.
;-----------------------------------------------------------------------------
fill_attrs:
                    ld hl, ATTRS
                    ld de, ATTRS + 1
                    ld bc, ATTRS_LEN - 1
                    ld (hl), a
                    ldir
                    ret

;-----------------------------------------------------------------------------
; cls - clear pixels, set every attribute, and match the border to the paper.
; Entry: a = attribute byte. Corrupts everything except iy.
;-----------------------------------------------------------------------------
cls:
                    push af
                    call clear_pixels
                    pop af
                    push af
                    call fill_attrs
                    pop af
                    and %00111000               ; paper colour...
                    rrca
                    rrca
                    rrca                        ; ...into the border's low 3 bits
                    out ($fe), a
                    ret

                    ENDMODULE
