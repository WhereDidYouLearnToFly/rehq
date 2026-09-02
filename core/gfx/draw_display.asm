;=============================================================================
; Bitmap drawing - pixels only
;=============================================================================
; Placement:  MemPlan places this one - the org below is the answer.
;
; MODULE draw owns the screen bitmap and nothing else. It never touches
; attributes (that is MODULE attribs) and it holds no palette or border state
; (that is MODULE screen). Everything here writes bytes into display memory at
; character-column granularity: the Spectrum stores eight adjacent pixels in
; one byte, so an x of 0..255 is always rounded down to its column. Only y is
; truly per-pixel.
;
; Address math is screen's job, not this module's - screen.get_addr_by_pix for
; a pixel coordinate, screen.cell_address for a character cell. Nothing here
; computes an address itself. There were five copies of that sum once; see the
; header of screen.asm for how they disagreed.
;
; Scratch: each routine owns its own named bytes at the foot of its section.
; There is deliberately no shared TEMP pool - draw8x8_panel calls draw_8x8 in
; a loop, so a pool would need every caller to know which slots its callee
; clobbers.
;-----------------------------------------------------------------------------

    SLOT 2
    PAGE 2
    org $8FE6
    MODULE draw

;-----------------------------------------------------------------------------
; draw8x8_panel - a rectangular frame built from a 9-tile sheet.
;
; HL = the tile sheet, 72 bytes laid out as STRUCT Panel8x8.
; B  = column,  C = row      in CHARACTERS
; D  = width,   E = height   in CHARACTERS, 2 minimum
;
; Same argument shape as put_img_desized, so a panel at column 0, row 10, 32
; wide and 10 high is BC=$000a, DE=$200a.
;
; A panel is character-aligned by construction - it is built out of 8x8 tiles -
; so there is no pixel-coordinate entry point and nothing here needs one. The
; bytes below are private scratch: the prologue unpacks the arguments into
; them once, and the drawing works from there.
;
; Only the frame is drawn. Panel8x8.Filler is never read and the interior is
; left exactly as it was - the caller has either cleared it or is about to lay
; attributes over it, and for the panels drawn so far that is what is wanted.
; A custom panel needing a tiled interior wants its own drawer, or a flag
; here; do not make this one start filling, or every existing panel begins
; erasing what it frames.
;-----------------------------------------------------------------------------
draw8x8_panel:
            ld (panel_sheet), hl

            ; --- x: the first and last column, both in pixels.
            ; Working out the last column in characters and multiplying once
            ; is shorter than multiplying both and adding, and it cannot
            ; overflow: column + width-1 is at most 31, so x8 is at most 248.
            ld a, d                     ; width
            dec a
            ld (panel_wchar), a
            add a, b                    ; ...so this is the last column
            add a, a                    ; x8. NOT rla - that would rotate in
            add a, a                    ; whatever carry the caller left set
            add a, a
            ld (panel_xpix_end), a
            ld a, b
            add a, a
            add a, a
            add a, a
            ld (panel_xpix), a

            ; --- y: the same again
            ld a, e                     ; height
            dec a
            ld (panel_hchar), a
            add a, c                    ; the last row
            add a, a
            add a, a
            add a, a
            ld (panel_ypix_end), a
            ld a, c
            add a, a
            add a, a
            add a, a
            ld (panel_ypix), a

            ; --- the four corners. Two of them come out of one 16-bit read,
            ; which is what the declaration order of the vars below buys.
            ld bc, (panel_ypix)         ; c=ypix, b=xpix
            ld a, Panel8x8.TopLeft
            call .tile
            ld bc, (panel_ypix_end)     ; c=ypix_end, b=xpix_end
            ld a, Panel8x8.BottomRight
            call .tile
            ld a, (panel_xpix_end)
            ld b, a
            ld a, (panel_ypix)
            ld c, a
            ld a, Panel8x8.TopRight
            call .tile
            ld a, (panel_xpix)
            ld b, a
            ld a, (panel_ypix_end)
            ld c, a
            ld a, Panel8x8.BottomLeft
            call .tile

            ; --- top and bottom edges, one column at a time
            ld a, (panel_wchar)
            dec a                       ; centres between the two corners:
            jr z, .verticals            ; a 2-wide panel has none, and djnz
            ld b, a                     ; with b=0 would draw 256 of them
            ld a, (panel_xpix)
            ld c, a
.horizontal:
            ld a, c
            add a, $8
            ld c, a
            push bc                     ; the loop counter and the x cursor
            ld b, c
            ld a, (panel_ypix)
            ld c, a
            push bc                     ; x and y, for the second tile
            ld a, Panel8x8.TopCenter
            call .tile
            pop bc
            ld a, (panel_ypix_end)
            ld c, a
            ld a, Panel8x8.BottomCenter
            call .tile
            pop bc
            djnz .horizontal

            ; --- left and right edges, one row at a time
.verticals:
            ld a, (panel_hchar)
            dec a
            ret z                       ; a 2-high panel is corners only
            ld b, a
            ld a, (panel_ypix)
            ld c, a
.vertical:
            ld a, c
            add a, $8
            ld c, a
            push bc
            ld a, (panel_xpix)
            ld b, a
            push bc
            ld a, Panel8x8.MidLeft
            call .tile
            pop bc
            ld a, (panel_xpix_end)
            ld b, a
            ld a, Panel8x8.MidRight
            call .tile
            pop bc
            djnz .vertical
            ret

;-----------------------------------------------------------------------------
; .tile - A = an offset into the sheet, B = x pixels, C = y pixels.
;
; Every tile above is "this one, here", and doing it in one place is what
; keeps the sheet pointer out of the caller's registers: there is no push/pop
; of it around each corner, and no saved tile pointer across the loops.
; draw_8x8 eats BC, so whatever the caller still needs is on the stack.
;-----------------------------------------------------------------------------
.tile:
            push bc
            ld c, a
            ld b, 0
            ld hl, (panel_sheet)
            add hl, bc
            pop bc
            jp draw_8x8

; The declaration order of these four is load-bearing: `ld bc,(panel_ypix)`
; above reads two bytes at once to get c=ypix and b=xpix, and likewise for the
; _end pair. Keep ypix immediately before xpix.
panel_ypix:         db 0
panel_xpix:         db 0
panel_ypix_end:     db 0
panel_xpix_end:     db 0
panel_hchar:        db 0            ; height in chars, minus one
panel_wchar:        db 0            ; width in chars, minus one
panel_sheet:        dw 0            ; the 9-tile sheet this call is drawing

;-----------------------------------------------------------------------------
; draw_8x8 - one 8x8 tile. HL = 8 bytes of source, B = x pixels, C = y pixels.
;
; The address is looked up once and then walked, because stepping down one
; pixel row is nearly free: inside a character cell the next row is one page
; on, so it is `inc d` seven times out of eight. Only the two boundaries cost
; anything.
;
;   cell   ($4700 -> $4020)  every 8 lines: back up a cell, on to the next row
;   third  ($47E0 -> $4800)  every 64: on to the next third of the screen
;
; screen.get_addr_by_pix leaves BC alone, so C stays as the pixel line and
; this needs no scratch of its own - which matters, because it is called once
; per tile and a panel is dozens of them.
;-----------------------------------------------------------------------------
draw_8x8:
            call screen.get_addr_by_pix ; de = top-left byte; bc and hl kept
            ld b, 8                     ; eight pixel rows; c is still y
.row:
            ld a, (hl)
            ld (de), a
            inc hl
            inc c                       ; the line this next byte belongs on
            ld a, c
            and $3f                     ; a third is 64 lines
            jr z, .next_third
            and 7                       ; a cell is 8
            jr z, .next_cell
            inc d                       ; still inside the cell: one page on
            jr .next
.next_cell:
            ld a, e                     ; de += -$06E0
            sub $e0
            ld e, a
            ld a, d
            sbc a, $06
            ld d, a
            jr .next
.next_third:
            ld a, e                     ; de += 32
            add a, 32
            ld e, a
            jr nc, .next
            inc d
.next:
            djnz .row
            ret

;-----------------------------------------------------------------------------
; put_img_desized - a rectangular blit of arbitrary size.
;
; HL = source data, stored line by line.
; B  = column in CHARACTERS, C = row in CHARACTERS   (not pixels)
; D  = width in BYTES,       E = height in CHARACTER ROWS
;
; A 4-byte-wide, 3-row-high image at column 4, row 2 is BC=$0402, DE=$0403.
;-----------------------------------------------------------------------------
put_img_desized:
            ld a, d
            ld (img_width), a
            ld a, b
            ld (img_column), a
            ;
            push hl
            ld a, c
            add a, a
            add a, a
            add a, a                   ;char row x8 = its top pixel line
            call screen.get_display_table_by_pix_line
            ld c, e
            pop de                     ;de - pointer to data
                                       ;hl - pointer to table
.row_loop:
            push bc
            ld a, 8
.char_loop:
            push af
            ;take line address
            ld c, (hl)
            inc hl
            ld b, (hl)
            inc hl
            ;---------------------------bc has pointer to screen
            push hl                     ;store - pointer to table
            push bc                     ;bc -> hl
            pop hl                      ;hl - pointer to screen
            ld a, (img_column)
            ld b, 0
            ld c, a
            add hl, bc                  ;horizontal offset to the begining
            ;
            ld a, (img_width)           ;horizontal lenght
            ld b, a
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.line_loop:
.ldade:     ld a, (de)                  ;get from data
.hla:       ld (hl), a                  ;set to screen
            inc hl
            inc de
            djnz .line_loop
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
            pop hl                        ;hl - pointer to table
            ;
            pop af
            dec a
            jp nz, .char_loop
            pop bc
            dec c
            jp nz, .row_loop
            ret

img_width:          db 0            ; bytes across
img_column:         db 0            ; left edge, in characters

    ENDMODULE
