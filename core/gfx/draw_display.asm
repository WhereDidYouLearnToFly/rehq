;=============================================================================
; display - pixel blitters
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: screen (addr_from_line, addr_from_char_xy, next_line)
; Namespace:  MODULE display - every label below is reached as display.*
;
;   draw_8x8     one 8x8 tile at pixel coordinates
;   draw_8xn     a column of bytes, any height, at pixel coordinates
;   put_img      a rectangular block of bytes at character coordinates
;   draw_panel   a 3x3 tiled frame of any size
;
; Sprite data is stored the way it lands on screen: one byte per pixel line,
; top to bottom, and for put_img left to right within each line.
;
; None of these mask or clip. Drawing past the right edge wraps into the next
; character row; drawing past the bottom runs off the display file entirely.
; Clipping is the caller's job.
;=============================================================================

                    MODULE display

;-----------------------------------------------------------------------------
; draw_8x8 - blit an 8x8 tile.
; Entry: hl = tile data (8 bytes), b = x in pixels, c = y in pixels
; Corrupts a, b, c, d, e, h, l.
;
; x is rounded down to a byte boundary - this is a byte blitter, not a
; pixel-shifted one. For sub-byte placement you need pre-shifted frames.
;-----------------------------------------------------------------------------
draw_8x8:
                    ld a, 8
                    ; fall through

;-----------------------------------------------------------------------------
; draw_8xn - blit a column of bytes, one per pixel line.
; Entry: hl = data, a = height in pixel lines, b = x in pixels, c = y in pixels
; Corrupts a, b, c, d, e, h, l.
;-----------------------------------------------------------------------------
draw_8xn:
                    ld (rows), a
                    push hl                     ; addr_from_line needs hl
                    ld a, c
                    call screen.addr_from_line
                    ld a, b
                    rrca                        ; x / 8 = byte column. The bits
                    rrca                        ; rotated in at the top are
                    rrca                        ; masked off, so rrca is safe.
                    and 31
                    or l                        ; l's low 5 bits are zero here
                    ld e, a
                    ld d, h
                    pop hl                      ; hl = data, de = screen
                    ld a, (rows)
                    ld b, a
.line:
                    ld a, (hl)
                    ld (de), a
                    inc hl
                    call screen.next_line
                    djnz .line
                    ret

rows:               db 0

;-----------------------------------------------------------------------------
; put_img - blit a rectangular block of bytes.
; Entry: hl = data, b = column 0..31, c = row 0..23,
;        d = width in bytes, e = height in character rows
; Corrupts a, b, c, d, e, h, l.
;
; Height is in character rows rather than pixel lines because that is how
; images are authored; the routine multiplies up.
;-----------------------------------------------------------------------------
put_img:
                    ld (img_height), de         ; e -> img_height, d -> img_width
                    push hl
                    call screen.addr_from_char_xy
                    ex de, hl                   ; de = screen
                    pop hl                      ; hl = data
                    ld a, (img_height)
                    add a, a                    ; character rows -> pixel lines
                    add a, a
                    add a, a
                    ld c, a
.line:
                    push de                     ; remember where this line began
                    ld a, (img_width)
                    ld b, a
.byte:
                    ld a, (hl)
                    ld (de), a
                    inc hl
                    inc de
                    djnz .byte
                    pop de                      ; back to the line start...
                    call screen.next_line       ; ...then straight down
                    dec c
                    jr nz, .line
                    ret

img_height:         db 0
img_width:          db 0                        ; must stay adjacent, in this order

;-----------------------------------------------------------------------------
; draw_panel - draw a frame from a 3x3 tile set.
; Entry: hl = tile set, b = column, c = row,
;        d = width in cells, e = height in cells   (both >= 2)
; Corrupts a, b, c, d, e, h, l.
;
; The tile set is nine 8x8 tiles, 72 bytes, in reading order:
;
;       top-left     top-centre     top-right
;       mid-left     centre         mid-right
;       bottom-left  bottom-centre  bottom-right
;
; The centre tile fills the interior, so a panel covers what was underneath it.
; For a hollow frame, make the centre tile blank.
;
; Every cell goes through draw_8x8, which corrupts every register, so the loop
; state lives in memory rather than in registers.
;-----------------------------------------------------------------------------
draw_panel:
                    ld (panel_src), hl
                    ld (panel_h), de            ; e -> panel_h, d -> panel_w
                    ld a, b
                    ld (panel_x), a
                    ld a, c
                    ld (panel_y), a
                    xor a
                    ld (panel_row), a
.row:
                    xor a
                    ld (panel_col), a
.col:
                    ld a, (panel_x)             ; cell -> pixel coordinates
                    ld hl, panel_col
                    add a, (hl)
                    add a, a
                    add a, a
                    add a, a
                    ld (panel_px), a
                    ld a, (panel_y)
                    ld hl, panel_row
                    add a, (hl)
                    add a, a
                    add a, a
                    add a, a
                    ld c, a
                    ld a, (panel_px)
                    ld b, a

                    push bc
                    call select_tile            ; -> hl
                    pop bc
                    call draw_8x8

                    ld hl, panel_col            ; next column
                    inc (hl)
                    ld a, (panel_w)
                    cp (hl)
                    jr nz, .col

                    ld hl, panel_row            ; next row
                    inc (hl)
                    ld a, (panel_h)
                    cp (hl)
                    jr nz, .row
                    ret

;-----------------------------------------------------------------------------
; select_tile - pick the tile for the current panel cell.
; Exit: hl = tile address. Corrupts a, d, e.
;
; Each axis collapses to 0 (first), 1 (middle) or 2 (last), and the pair
; indexes the 3x3 set. cp sets the flags and the following ld does not disturb
; them, so the value can be loaded before the branch that selects it.
;-----------------------------------------------------------------------------
select_tile:
                    ld a, (panel_col)
                    and a
                    ld e, 0
                    jr z, .have_col
                    ld hl, panel_w
                    inc a
                    cp (hl)                     ; is this the last column?
                    ld e, 1
                    jr nz, .have_col
                    ld e, 2
.have_col:
                    ld a, (panel_row)
                    and a
                    ld d, 0
                    jr z, .have_row
                    ld hl, panel_h
                    inc a
                    cp (hl)                     ; is this the last row?
                    ld d, 1
                    jr nz, .have_row
                    ld d, 2
.have_row:
                    ld a, d                     ; index = row * 3 + col
                    add a, a
                    add a, d
                    add a, e
                    add a, a                    ; * 8 bytes per tile
                    add a, a
                    add a, a
                    ld e, a
                    ld d, 0
                    ld hl, (panel_src)
                    add hl, de
                    ret

panel_src:          dw 0
panel_h:            db 0
panel_w:            db 0                        ; must stay adjacent, in this order
panel_x:            db 0
panel_y:            db 0
panel_row:          db 0
panel_col:          db 0
panel_px:           db 0

                    ENDMODULE
