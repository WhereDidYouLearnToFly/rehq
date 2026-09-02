;=============================================================================
; Colour - the attribute file, and nothing else
;=============================================================================
; Placement:  MemPlan places this one - the org below is the answer.
;
; MODULE attribs writes $5800-$5AFF and never touches the bitmap. Addresses
; for a coordinate come from screen.get_attr_addr_by_bc; see the header of
; screen.asm for why they come from exactly one place.
;=============================================================================

    SLOT 2
    PAGE 2
    org $8301
    MODULE attribs

;=============================================================================
; Screen wipes
;=============================================================================
; Six effects that are one effect. Each paints a moving edge - a column or a
; row - one edge per step, pausing between steps so the sweep is visible, and
; they differ in nothing but which cell they start on, which way the edge
; travels, and how far apart the cells within one edge are. That was six
; copies of the same two nested loops; it is now one engine and six tables of
; five numbers.
;
; A table is, in order:
;
;   HEAD    first cell of the first edge
;   TAIL    first cell of the opposite edge, or 0 for a single-edge wipe
;   STEP    added to HEAD between steps; TAIL moves by -STEP, towards it
;   STRIDE  distance between cells within one edge: 32 down a column, 1 along
;           a row
;   CELLS   cells in one edge
;   STEPS   number of edges painted
;
; A column wipe is STRIDE 32 / CELLS 24, stepping by +-1 across 32 columns. A
; row wipe is STRIDE 1 / CELLS 32, stepping by +-32 down 24 rows. The
; two-edged ones are a column wipe with TAIL set and half the steps.
;-----------------------------------------------------------------------------

from_left_to_right:
            xor a
            ld hl, .params
            jp wipe
.params:    dw DISPLAY_ATTRS            ; head - column 0
            dw 0                        ; tail - none
            dw 1                        ; step  - one column right
            dw 32                       ; stride
            db 24, 32                   ; cells, steps

from_right_to_left:
            xor a
            ld hl, .params
            jp wipe
.params:    dw DISPLAY_ATTRS+31         ; head - column 31
            dw 0
            dw -1
            dw 32
            db 24, 32

from_top_to_bottom:
            xor a
            ld hl, .params
            jp wipe
.params:    dw DISPLAY_ATTRS            ; head - row 0
            dw 0
            dw 32                       ; step - one row down
            dw 1                        ; stride
            db 32, 24

from_bottom_to_top:
            xor a
            ld hl, .params
            jp wipe
.params:    dw DISPLAY_ATTRS+23*32      ; head - start of the last row
            dw 0
            dw -32
            dw 1
            db 32, 24

from_center_to_side:
            xor a
            ld hl, .params
            jp wipe
.params:    dw DISPLAY_ATTRS+15         ; head - column 15, moving left
            dw DISPLAY_ATTRS+16         ; tail - column 16, moving right
            dw -1
            dw 32
            db 24, 16                   ; sixteen steps: two columns each

from_side_to_center:
            xor a
            ld hl, .params
            jp wipe
.params:    dw DISPLAY_ATTRS            ; head - column 0, moving right
            dw DISPLAY_ATTRS+31         ; tail - column 31, moving left
            dw 1
            dw 32
            db 24, 16

;-----------------------------------------------------------------------------
; wipe - HL = a parameter table, A = the attribute to paint.
;
; The six entries above pass 0, which is what all six used to hardcode: black
; ink on black paper, i.e. the screen going out. Call this directly to sweep
; in a colour instead.
;-----------------------------------------------------------------------------
wipe:
            ld (wipe_attrib), a
            ld de, wipe_head            ; the table is the working vars, in
            ld bc, WIPE_PARAMS          ; order, so it copies straight in
            ldir
            ld a, (wipe_steps)
            ld b, a
.step:
            push bc
            ld hl, (wipe_head)
            call .edge
            ld hl, (wipe_tail)
            ld a, h
            or l                        ; 0 = single-edged, nothing to pair
            call nz, .edge
            ;
            ld de, (wipe_step)
            ld hl, (wipe_head)
            add hl, de
            ld (wipe_head), hl
            ld hl, (wipe_tail)
            ld a, h
            or l
            jr z, .settle
            or a                        ; clear carry for the sbc: the far
            sbc hl, de                  ; edge travels against the near one
            ld (wipe_tail), hl
.settle:
            ld bc, 2
            call PAUSE_BC
            pop bc
            djnz .step
            ret

;-----------------------------------------------------------------------------
; .edge - HL = the first cell of one column or row. Paints CELLS of them,
; STRIDE apart. Clobbers B, which is why .step brackets it with push/pop.
;-----------------------------------------------------------------------------
.edge:
            ld a, (wipe_cells)
            ld b, a
            ld de, (wipe_stride)
            ld a, (wipe_attrib)
.cell:
            ld (hl), a
            add hl, de
            djnz .cell
            ret

; The first six must stay in this order and be contiguous: `wipe` ldirs a
; parameter table straight over them.
wipe_head:      dw 0
wipe_tail:      dw 0
wipe_step:      dw 0
wipe_stride:    dw 0
wipe_cells:     db 0
wipe_steps:     db 0
WIPE_PARAMS     equ $ - wipe_head
wipe_attrib:    db 0            ; from A, so not part of the table

;=============================================================================
; Rectangles
;=============================================================================

;-----------------------------------------------------------------------------
; load_attribs - copy a rectangle of attribute bytes onto the screen.
; B = column, C = row, D = width, E = height, HL = source data.
;-----------------------------------------------------------------------------
load_attribs:
            ld (src_attribs), hl
            push de                 ;wxh, wanted in bc below
            call screen.get_attr_addr_by_bc
            ex de, hl               ;de - pointer to screen area
            ld hl, (src_attribs)    ;hl - pointer to attrib data
            pop bc                  ;bc - size from de
;
            ld a, b
            ld (rect_width), a
;
            ld a, $20
            sub b
            ld (row_delta), a       ;screen stride minus the width
;
.vertical_loop:
            ld a, (rect_width)
            ld b, a
.horizontal_loop:
.ldahl:     ld a, (hl)              ; these two opcodes are rewritten in
.dea:       ld (de), a              ; place by set_direct_fill /
                                    ; set_reverse_fill, below, to flip which
                                    ; way the copy runs
            inc hl
            inc de
            djnz .horizontal_loop
            push bc
            ld a, (row_delta)
            ld b, 0
            ld c, a
            ex de, hl
            add hl, bc
            ex de, hl
            pop bc
            dec c
            jr nz, .vertical_loop
            ret

;-----------------------------------------------------------------------------
; fill_rectangle - flood a rectangle with one attribute byte.
; B = column, C = row, D = width, E = height, A = attribute.
;-----------------------------------------------------------------------------
fill_rectangle:
            ld (fill_attrib), a     ;stored first - the call below uses A
            push de
            call screen.get_attr_addr_by_bc
            pop de
.vertical_loop:
            ld a, (fill_attrib)
            ld b, d
.horizontal_loop:
            ld (hl), a
            inc hl
            djnz .horizontal_loop
            push de
            ld a, $20
            sub d
            ld d, 0
            ld e, a
            add hl, de
            pop de
            dec e
            jr nz, .vertical_loop
            ret

set_direct_fill:
            ld hl, load_attribs.ldahl
            ld (hl), $7e
            ld hl, load_attribs.dea
            ld (hl), $12
            ret

set_reverse_fill:
            ld hl, load_attribs.ldahl
            ld (hl), $1a            ;set to ld a,(de)
            ld hl, load_attribs.dea
            ld (hl), $77            ;set to ld (hl),a
            ret

src_attribs:    dw $0           ; load_attribs - source, parked across the setup
rect_width:     db $0           ; load_attribs - bytes across
row_delta:      db $0           ; load_attribs - 32 minus the width
fill_attrib:    db $0           ; fill_rectangle - the byte being smeared

    ENDMODULE