;=============================================================================
; Shapes the gfx modules read out of memory
;=============================================================================
; These are offset tables, not variables - nothing is allocated here. A
; STRUCT field's value is its byte offset from the start of the blob, so
; `ld bc, Panel8x8.TopCenter : add hl, bc` walks hl from the head of a tile
; sheet to the tile named. The field sizes must therefore be the size of one
; tile on disk, not one byte: a 9-tile 8x8 sheet is 72 bytes (bin/ui/gfx/
; hq_frame.bin), and BLOCK 8 is what makes TopCenter come out as 8 rather
; than 1.
;
; Field order is reading order, which is the order the converter emits.
;
; Filler is the centre tile. No drawer reads it - draw8x8_panel lays a frame
; and leaves the interior alone - but the field is not optional: those eight
; bytes are really there in the file, and deleting it would pull BottomLeft
; and everything after it eight bytes out of place. A custom panel that wants
; a tiled interior is what it is for.
;-----------------------------------------------------------------------------

; One 8x8 tile is 8 bytes: one byte per pixel row. Sheet = 72 bytes.
    STRUCT Panel8x8
TopLeft         BLOCK 8
TopCenter       BLOCK 8
TopRight        BLOCK 8
MidLeft         BLOCK 8
Filler          BLOCK 8
MidRight        BLOCK 8
BottomLeft      BLOCK 8
BottomCenter    BLOCK 8
BottomRight     BLOCK 8
    ENDS

; One 16x16 tile is 32 bytes: two bytes per pixel row, 16 rows, stored line
; by line. Sheet = 288 bytes. No drawer reads this one yet.
    STRUCT Panel16x16
TopLeft         BLOCK 32
TopCenter       BLOCK 32
TopRight        BLOCK 32
MidLeft         BLOCK 32
Filler          BLOCK 32
MidRight        BLOCK 32
BottomLeft      BLOCK 32
BottomCenter    BLOCK 32
BottomRight     BLOCK 32
    ENDS

    STRUCT WindowUI
X       BYTE
Y       BYTE
WIDTH   BYTE
HEIGHT  BYTE
PBUFFER BYTE
PPROG   BYTE
BORDER  BYTE
PAPER   BYTE
INK     BYTE
TMP     BYTE
    ENDS
