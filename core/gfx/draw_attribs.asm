    org Attributes
    MODULE attribs

from_center_to_side:
            ld b, $10
            ld hl, DISPLAY_ATTRS
            ld de, $10
            adc hl, de
            push hl
            pop de
            dec hl
.loop:
            push hl
            push de
            ld c, 24
.vloop:
            push bc
            ;
            ld bc, $20
            ld (hl), $00
            adc hl, bc
            ex de, hl
            ld (hl), $00
            adc hl, bc
            ex de, hl
            ;
            pop bc
            dec c
            jr nz, .vloop
            ;
            push bc
            ld bc, 2
            call PAUSE_BC
            pop bc
            ;
            pop de
            pop hl
            dec hl
            inc de
            djnz .loop
            ret

from_side_to_center:
            ld b, $10
            ld hl, DISPLAY_ATTRS
            ld de, $1f
            adc hl, de
            push hl
            pop de
            ld hl, DISPLAY_ATTRS
.loop:
            push hl
            push de
            ld c, 24
.vloop:
            push bc
            ;
            ld bc, $20
            ld (hl), $00
            adc hl, bc
            ex de, hl
            ld (hl), $00
            adc hl, bc
            ex de, hl
            ;
            pop bc
            dec c
            jr nz, .vloop
            ;
            push bc
            ld bc, 2
            call PAUSE_BC
            pop bc
            ;
            pop de
            pop hl
            inc hl
            dec de
            djnz .loop
            ret

from_left_to_right:
            ld b, 32
            ld hl, DISPLAY_ATTRS
            ld de, 32
.loop:
            push hl
            ld c, 24
.vloop:
            ld (hl), $00
            adc hl, de
            dec c
            jr nz, .vloop
            ;
            push bc
            ld bc, 2
            call PAUSE_BC
            pop bc
            ;
            pop hl
            inc hl
            djnz .loop
            ret

from_right_to_left:
            ld b, 32
            ld hl, DISPLAY_ATTRS
            ld de, 32
            adc hl, de
            dec hl
.loop:
            push hl
            ld c, 24
.vloop:
            ld (hl), $00
            adc hl, de
            dec c
            jr nz, .vloop
            ;
            push bc
            ld bc, 2
            call PAUSE_BC
            pop bc
            ;
            pop hl
            dec hl
            djnz .loop
            ret

from_top_to_bottom:
            ld b, 24
            ld hl, DISPLAY_ATTRS
.loop:  
            ld c, 32
.hloop:
            ld (hl), $00
            inc hl
            dec c
            jr nz, .hloop
            ;
            push bc
            ld bc, 2
            call PAUSE_BC
            pop bc
            ;
            djnz .loop
            ret

from_bottom_to_top:
            ld b, 24
            ld hl, DISPLAY_ATTRS+767
.loop:  
            ld c, 32
.hloop:
            ld (hl), $00
            dec hl
            dec c
            jr nz, .hloop
            ;
            push bc
            ld bc, 2
            call PAUSE_BC
            pop bc
            ;
            djnz .loop
            ret

load_attribs: ;bc - position, de-wxh, hl - pointer to attrb data
            ld (WORD_TEMP0), hl
            ld hl, DISPLAY_ATTRS
            ld a, c
            cp 0
            jr z, load_attribs_vertical_loop
;;;
            push de
            ld de, $20
;
load_attribs_calc_yloop:
            add hl, de
            dec c
            jr nz, load_attribs_calc_yloop
;
            ld e, b
            add hl, de
            ex de, hl               ;de - pointer to screen area
            ld hl, (WORD_TEMP0)    ;hl - pointer to attrib data
            pop bc                  ;bc - size from de
;
            ld a, b
            ld (BYTE_TEMP1), a
;
            ld a, $20
            sub a, b
            ld (BYTE_TEMP0), a      ;delta to add
;
load_attribs_vertical_loop:
            ld a, (BYTE_TEMP1)
            ld b, a
load_attribs_horizontal_loop:
load_attribs_ldahl: ld a, (hl)
load_attribs_dea: ld (de), a
            inc hl
            inc de
            djnz load_attribs_horizontal_loop
            push bc
            ld a, (BYTE_TEMP0)
            ld b, 0
            ld c, a
            ex de, hl
            add hl, bc
            ex de, hl
            pop bc
            dec c
            jr nz, load_attribs_vertical_loop
            ret

fill_rectangle:         ;bc - position, de - WidthxHeight, a - attrib
            ld (BYTE_TEMP0), a
            ld hl, DISPLAY_ATTRS
            ld a, c
            cp 0
            jr z, fill_rectangle.vertical_loop
;;;
            push de
            ld de, $20
fill_rectangle.calc_yloop:
            add hl, de
            dec c
            jr nz, fill_rectangle.calc_yloop
            ld e, b
            add hl, de
            pop de
;;;
fill_rectangle.vertical_loop:
            ld a, (BYTE_TEMP0)
            ld b, d
fill_rectangle.horizontal_loop:
            ld (hl), a
            inc hl
            djnz fill_rectangle.horizontal_loop
            push de
            ld a, $20
            sub a, d
            ld d, 0
            ld e, a
            adc hl, de
            pop de
            dec e
            jr nz, fill_rectangle.vertical_loop
            ret

set_direct_fill:
            ld hl, load_attribs_ldahl
            ld (hl), $7e
            ld hl, load_attribs_dea
            ld (hl), $12
            ret

set_reverse_fill:
            ld hl, load_attribs_ldahl
            ld (hl), $1a            ;set to ld a,(de)
            ld hl, load_attribs_dea
            ld (hl), $77            ;set to ld (hl),a
            ret

BYTE_TEMP0:     db $0
BYTE_TEMP1:     db $0
WORD_TEMP0:     dw $0
WORD_TEMP2:     dw $0

    ENDMODULE