    org DrawDisplay
    MODULE draw

get_scaddr:
            push hl
            xor a                    ; clear carry flag and accumulator.
            ld d,a                   ; empty de high byte.
            ld a,c                   ; vertical position
            rla                      ; shift left to multiply by 2.
            ld e,a                   ; place this in low byte of de pair.
            rl d                     ; shift top bit into de high byte.
            ld hl, screen.main       ; table of screen addresses.
            add hl,de                ; point to table entry.
            ld e,(hl)                ; low byte of screen address.
            inc hl                   ; point to high byte.
            ld d,(hl)                ; high byte of screen address.
            ld a,b                   ; horizontal position
            rra                      ; divide by two.
            rra                      ; and again for four.
            rra                      ; shift again to divide by eight.
            and 31                   ; mask away rubbish shifted into rightmost bits.
            add a,e                  ; add to address for start of line.
            ld e,a                   ; new value of e register.
            pop hl
            ret                      ; return with screen address in de.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
draw8x8_panel:                       ; hl pointer to plate8x8 data, bc(xcoords,ycoord)
                                     ; de - wh (in symbols)
            push hl
            ;calc end coords
            ld a, (panel_wchar)
            rla
            rla
            rla
            ld l, a
            ld a, (panel_xpix)
            add a, l
            ld (panel_xpix_end), a
            ;
            ld a, (panel_hchar)
            rla
            rla
            rla
            ld l, a
            ld a, (panel_ypix)
            add a, l
            ld (panel_ypix_end), a
            ;draw corners
            pop hl
            push hl
            ld bc, Panel8x8.TopLeft
            adc hl, bc
            ld bc, (panel_ypix)
            call draw_8x8
            ;
            pop hl
            push hl
            ld bc, Panel8x8.BottomRight
            adc hl, bc
            ld bc, (panel_ypix_end)
            call draw_8x8
            ;
            pop hl
            push hl
            ld bc, Panel8x8.TopRight
            adc hl, bc
            ld a, (panel_xpix_end)
            ld b, a
            ld a, (panel_ypix)
            ld c, a
            call draw_8x8
            ;
            pop hl
            push hl
            ld bc, Panel8x8.BottomLeft
            adc hl, bc
            ld a, (panel_xpix)
            ld b, a
            ld a, (panel_ypix_end)
            ld c, a
            call draw_8x8
; ----- horizontals
            pop hl
            push hl
            ld bc, Panel8x8.TopCenter
            adc hl, bc
            ld (WORD_TEMP2), hl         ;store pointer to TopCenter tile
            pop hl
            push hl
            ld bc, Panel8x8.BottomCenter
            adc hl, bc
            ld (WORD_TEMP3), hl         ;store pointer to BottomCenter tile
            ld a, (panel_wchar)
            dec a
            ld b, a
            ld a, (panel_xpix)
            ld c, a
.horizontal_loop:
            ld a, c
            add a, $8
            ld c, a
            push bc
            ld b, c
            ld a, (panel_ypix)
            ld c, a
            push bc
            ld hl, (WORD_TEMP2)         ;top
            call draw_8x8
            pop bc
            ld a, (panel_ypix_end)
            ld c, a
            ld hl, (WORD_TEMP3)         ;bottom
            call draw_8x8
            pop bc
            djnz .horizontal_loop
; ----- verticals
            pop hl
            push hl
            ld bc, Panel8x8.MidLeft
            adc hl, bc
            ld (WORD_TEMP2), hl         ;store pointer to MidLeft tile
            pop hl
            ld bc, Panel8x8.MidRight
            adc hl, bc
            ld (WORD_TEMP3), hl         ;store pointer to MidRight tile
            ld a, (panel_hchar)
            dec a
            ld b, a
            ld a, (panel_ypix)
            ld c, a
.vertical_loop:
            ld a, c
            add a, $8
            ld c, a
            push bc
            ld a, (panel_xpix)
            ld b, a
            push bc
            ld hl, (WORD_TEMP2)         ;left
            call draw_8x8
            pop bc
            ld a, (panel_xpix_end)
            ld b, a
            ld hl, (WORD_TEMP3)         ;right
            call draw_8x8
            pop bc
            djnz .vertical_loop
            ret

panel_ypix:         .db 0
panel_xpix:         .db 0
panel_ypix_end:     .db 0
panel_xpix_end:     .db 0
panel_hchar:        .db 0
panel_wchar:        .db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

draw_8x8:                           ;from (hl) to screen pix bc(xcoords,ycoord in pixels) 
            ld a, c
            ld (BYTE_TEMP0),a
            call get_scaddr
            ld bc, $8               ;$8 - 8 bytes in 8x8 sprite
.loop:
            ldi
            ld a, c
            ld (WORD_TEMP0), hl
            cp 0
            jr nz, .next_line
            ret
.next_line:
            ld a,(BYTE_TEMP0)       ; temporary vertical coordinate.
            inc a                   ; next line down.
            ld (BYTE_TEMP0),a       ; store new position.
            and $3f                 ; are we moving to next third of screen? segment is 64 ($40) lines #3f - is last line num in seg
            jr z, .next_seg         ; yes so find next segment.
            and 7                   ; moving into character cell below? character is 8 lines (7 is last one)
            jr z, .next_row         ; yes, find next row.
            dec de                  ; not straddling 256-byte boundary here.
            inc d                   ; next row of this character cell.
.back_to_loop:
            ld hl, (WORD_TEMP0)     ;restore pixels address
            jp .loop
.next_seg:
            ex de, hl
            ld de, 31               ; next segment is 30 bytes on.
            add hl,de               ; add to screen address.
            ex de, hl
            jp .back_to_loop
.next_row:
            ex de, hl
            ld de, $F91F             ;negative
            add hl, de               ;sub
            ex de, hl
            jp .back_to_loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
put_img_desized: ;hl - pointer to data, bc - xy (pixels), de - size
            ld a, d
            ld (BYTE_TEMP0), a
            ld a, b
            ld (BYTE_TEMP1), a
            ;
            push hl
            ld a, c
            rla
            rla
            rla                        ;get line number
            call screen.get_display_table_by_pix_line
            ld c, e
            pop de                     ;de - pointer to data
                                       ;hl - pointer to table
put_img_loop:
            push bc
            ld a, 8
put_img_char_loop:
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
            ld a, (BYTE_TEMP1)
            ld b, 0
            ld c, a
            add hl, bc                  ;horizontal offset to the begining 
            ;
            ld a, (BYTE_TEMP0)          ;horizontal lenght
            ld b, a
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
put_img_line_loop:
put_img_ldade: ld a, (de)                  ;get from data
put_img_hla:   ld (hl), a                  ;set to screen
               inc hl
               inc de
            djnz put_img_line_loop
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
            pop hl                        ;hl - pointer to table
            ;
            pop af
            dec a
            jp nz, put_img_char_loop
            pop bc
            dec c
            jp nz, put_img_loop
            ret

BYTE_TEMP0:     db $0
BYTE_TEMP1:     db $0
WORD_TEMP0:     dw $0
WORD_TEMP2:     dw $0
WORD_TEMP3:     dw $0

    ENDMODULE