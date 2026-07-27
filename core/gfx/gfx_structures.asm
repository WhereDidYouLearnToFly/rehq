;=============================================================================
; gfx_structures - layouts shared between graphics data and the code that
; reads it
;=============================================================================
; Placement:  no ORG - declarations only, emits no bytes.
; Depends on: nothing.
;
; These are sjasmplus STRUCTs, so the field names are byte offsets. A tile set
; laid out to match Panel8x8 can be indexed as
;
;       ld de, Panel8x8.BottomRight
;       add hl, de
;
; The field order is the same reading order display.draw_panel assumes, and
; the two must stay in step: draw_panel computes (row * 3 + col) * 8 directly
; rather than reading these names.
;=============================================================================

; A 3x3 frame of 8x8 tiles - 72 bytes. Each field is a whole tile, not a
; single byte, which is what makes the offsets come out as 0, 8, 16 ... 64.
                    STRUCT Panel8x8
TopLeft             BLOCK 8
TopCentre           BLOCK 8
TopRight            BLOCK 8
MidLeft             BLOCK 8
Centre              BLOCK 8
MidRight            BLOCK 8
BottomLeft          BLOCK 8
BottomCentre        BLOCK 8
BottomRight         BLOCK 8
                    ENDS

; The same frame in 16x16 tiles - 288 bytes. A 16x16 tile is two byte-columns
; wide by 16 lines, stored the way put_img reads it: left byte then right byte
; for each line.
                    STRUCT Panel16x16
TopLeft             BLOCK 32
TopCentre           BLOCK 32
TopRight            BLOCK 32
MidLeft             BLOCK 32
Centre              BLOCK 32
MidRight            BLOCK 32
BottomLeft          BLOCK 32
BottomCentre        BLOCK 32
BottomRight         BLOCK 32
                    ENDS

; A window's state. PixelBuffer and Program are addresses, so they are WORDs;
; everything else fits in a byte.
                    STRUCT WindowUI
X                   BYTE
Y                   BYTE
Width               BYTE
Height              BYTE
PixelBuffer         WORD
Program             WORD
Border              BYTE
Paper               BYTE
Ink                 BYTE
Temp                BYTE
                    ENDS
