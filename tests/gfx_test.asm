;=============================================================================
; gfx_test - visual test bench for core/gfx
;=============================================================================
; Open this file in zxide and press F5. SPACE advances to the next stage.
;
;   1  cls            pixels blank, attributes uniform, border matches paper
;   2  draw_8xn       a full-height column - the hard test. It crosses both
;                     third boundaries (lines 64 and 128), so any break or
;                     sideways jump in it means screen.next_line is wrong.
;      draw_8x8       a row of tiles, plus two placed to straddle line 64
;                     and line 128
;   3  put_img        a rectangular block at character coordinates
;   4  draw_panel     frames at 10x6, 6x3 and the 2x2 minimum, so every tile
;                     of the 3x3 set gets selected including all four corners
;   5  direct_text.draw_string / rom_text.print_teletype_at
;   6  fill_rect      including one at row 0 with a non-zero column, which is
;                     exactly what the old version drew in the wrong place
;      copy_from_screen / copy_to_screen  - grab a region, stamp it elsewhere
;   7  the six wipes, back to back
;=============================================================================

                    device zxspectrum48

; The org has to come before the includes: without it the modules assemble
; from address 0, i.e. underneath the ROM, and SAVESNA only writes $4000-$FFFF
; - so every call into them would land in the ROM instead.
                    org $8000

                    include "../core/gfx/screen.asm"
                    include "../core/gfx/draw_display.asm"
                    include "../core/gfx/draw_attribs.asm"
                    include "../core/gfx/draw_text.asm"

SCR_CT              equ 23692           ; ROM's "lines until scroll?" counter

PAPER_BLACK_INK_W   equ %00000111
BRIGHT_GREEN        equ %01000100
BRIGHT_RED          equ %01000010
BRIGHT_YELLOW       equ %01000110

; The wipes only touch attributes, so backdrop and target have to differ in
; PAPER - two attributes with the same paper would wipe invisibly.
WIPE_FROM           equ %01001000       ; bright, blue paper
WIPE_TO             equ %00000111       ; black paper

start:
                    di
                    ld sp, $7fff
                    call rom_text.open_upper
                    ei

;-----------------------------------------------------------------------------
; 1 - cls
;-----------------------------------------------------------------------------
                    ld a, PAPER_BLACK_INK_W
                    call screen.cls
                    ld hl, msg_cls
                    ld de, $0000                ; row 0, column 0
                    call direct_text.draw_string
                    call wait_space

;-----------------------------------------------------------------------------
; 2 - draw_8xn across the whole display, then draw_8x8 on the boundaries
;-----------------------------------------------------------------------------
                    ld a, PAPER_BLACK_INK_W
                    call screen.cls

                    ld hl, tall_column          ; 192 lines, column 0
                    ld a, 192
                    ld bc, $0000                ; b = x pixels, c = y pixels
                    call display.draw_8xn

                    ld a, 14                    ; a row of tiles along line 16
                    ld (tile_count), a
                    ld b, 8
                    ld c, 16
.tile_row:
                    push bc
                    ld hl, tile_check
                    call display.draw_8x8
                    pop bc
                    ld a, b
                    add a, 16
                    ld b, a
                    ld hl, tile_count
                    dec (hl)
                    jr nz, .tile_row

                    ld hl, tile_solid           ; straddling line 64
                    ld bc, $803c                ; x = 128, y = 60
                    call display.draw_8x8
                    ld hl, tile_solid           ; straddling line 128
                    ld bc, $907c                ; x = 144, y = 124
                    call display.draw_8x8

                    ld hl, msg_blit             ; bottom row, clear of the column
                    ld de, $1702
                    call direct_text.draw_string
                    call wait_space

;-----------------------------------------------------------------------------
; 3 - put_img
;-----------------------------------------------------------------------------
                    ld a, PAPER_BLACK_INK_W
                    call screen.cls
                    ld hl, block_img
                    ld bc, $0402                ; column 4, row 2
                    ld de, $0403                ; width 4 bytes, height 3 rows
                    call display.put_img
                    ld hl, msg_img
                    ld de, $0a00
                    call direct_text.draw_string
                    call wait_space

;-----------------------------------------------------------------------------
; 4 - draw_panel
;-----------------------------------------------------------------------------
                    ld a, PAPER_BLACK_INK_W
                    call screen.cls
                    ld hl, panel_tiles
                    ld bc, $0101                ; column 1, row 1
                    ld de, $0a06                ; 10 wide, 6 high
                    call display.draw_panel

                    ld hl, panel_tiles
                    ld bc, $0d01
                    ld de, $0603                ; 6 wide, 3 high
                    call display.draw_panel

                    ld hl, panel_tiles
                    ld bc, $1501
                    ld de, $0202                ; the 2x2 minimum - corners only
                    call display.draw_panel

                    ld hl, msg_panel
                    ld de, $0a00
                    call direct_text.draw_string
                    call wait_space

;-----------------------------------------------------------------------------
; 5 - text
;-----------------------------------------------------------------------------
                    ld a, PAPER_BLACK_INK_W
                    call screen.cls
                    ld hl, msg_direct
                    ld de, $0202                ; row 2, column 2
                    call direct_text.draw_string

                    ld a, 255                   ; suppress the ROM's scroll? prompt
                    ld (SCR_CT), a
                    ld a, 2
                    ld (rom_text.delay_frames), a
                    ld hl, msg_teletype
                    ld bc, $0206                ; column 2, row 6
                    ld a, 26                    ; wrap width
                    call rom_text.print_teletype_at
                    call wait_space

;-----------------------------------------------------------------------------
; 6 - attribute fills and blits
;-----------------------------------------------------------------------------
                    ld a, PAPER_BLACK_INK_W
                    call screen.cls

                    ld a, BRIGHT_GREEN          ; row 0, column 8 - the old bug
                    ld bc, $0800
                    ld de, $0802
                    call attrs.fill_rect

                    ld a, BRIGHT_RED            ; away from both edges
                    ld bc, $0405
                    ld de, $0603
                    call attrs.fill_rect

                    ld a, BRIGHT_YELLOW
                    ld bc, $1005
                    ld de, $0403
                    call attrs.fill_rect

                    ld hl, attr_buffer          ; lift the red block...
                    ld bc, $0405
                    ld de, $0603
                    call attrs.copy_from_screen

                    ld hl, attr_buffer          ; ...and stamp it lower down
                    ld bc, $040e
                    ld de, $0603
                    call attrs.copy_to_screen

                    ld hl, msg_attr
                    ld de, $1600
                    call direct_text.draw_string
                    call wait_space

;-----------------------------------------------------------------------------
; 7 - wipes
;-----------------------------------------------------------------------------
                    ld a, WIPE_FROM
                    call wipe_backdrop
                    ld a, WIPE_TO
                    call attrs.wipe_left_to_right

                    ld a, WIPE_FROM
                    call wipe_backdrop
                    ld a, WIPE_TO
                    call attrs.wipe_right_to_left

                    ld a, WIPE_FROM
                    call wipe_backdrop
                    ld a, WIPE_TO
                    call attrs.wipe_top_to_bottom

                    ld a, WIPE_FROM
                    call wipe_backdrop
                    ld a, WIPE_TO
                    call attrs.wipe_bottom_to_top

                    ld a, WIPE_FROM
                    call wipe_backdrop
                    ld a, WIPE_TO
                    call attrs.wipe_centre_to_side

                    ld a, WIPE_FROM
                    call wipe_backdrop
                    ld a, WIPE_TO
                    call attrs.wipe_side_to_centre

                    ld a, PAPER_BLACK_INK_W
                    call screen.cls
                    ld hl, msg_done
                    ld de, $0b00
                    call direct_text.draw_string
.halt:
                    halt
                    jr .halt

;-----------------------------------------------------------------------------
; wipe_backdrop - fill the screen with a pattern so the wipe has something to
; eat into. Entry: a = attribute.
;-----------------------------------------------------------------------------
wipe_backdrop:
                    push af
                    call screen.fill_attrs
                    ld hl, tall_column
                    ld a, 192
                    ld bc, $0000
                    call display.draw_8xn
                    pop af
                    ret

;-----------------------------------------------------------------------------
; wait_space - press and release, so one press does not skip two stages.
;-----------------------------------------------------------------------------
wait_space:
                    ld a, $7f
                    in a, ($fe)
                    rra
                    jr c, wait_space
.release:
                    ld a, $7f
                    in a, ($fe)
                    rra
                    jr nc, .release
                    ret

;=============================================================================
; Data
;=============================================================================

tile_check:         db %10101010, %01010101, %10101010, %01010101
                    db %10101010, %01010101, %10101010, %01010101
tile_solid:         db %11111111, %10000001, %10111101, %10100101
                    db %10100101, %10111101, %10000001, %11111111

; 192 lines of a diagonal weave. Any discontinuity where this crosses line 64
; or line 128 is a next_line bug.
tall_column:
                    DUP 24
                    db %10000001, %01000010, %00100100, %00011000
                    db %00011000, %00100100, %01000010, %10000001
                    EDUP

; 4 bytes wide, 3 character rows high, stored line by line.
block_img:
                    DUP 24
                    db %11111111, %10000001, %10000001, %11111111
                    EDUP

; Nine 8x8 tiles in reading order, matching Panel8x8 and draw_panel.
panel_tiles:
                    db %00000000, %00111111, %00100000, %00100000     ; top-left
                    db %00100000, %00100000, %00100000, %00100000
                    db %00000000, %11111111, %00000000, %00000000     ; top-centre
                    db %00000000, %00000000, %00000000, %00000000
                    db %00000000, %11111100, %00000100, %00000100     ; top-right
                    db %00000100, %00000100, %00000100, %00000100
                    db %00100000, %00100000, %00100000, %00100000     ; mid-left
                    db %00100000, %00100000, %00100000, %00100000
                    db %00000000, %00000000, %00000000, %00000000     ; centre
                    db %00000000, %00000000, %00000000, %00000000
                    db %00000100, %00000100, %00000100, %00000100     ; mid-right
                    db %00000100, %00000100, %00000100, %00000100
                    db %00100000, %00100000, %00100000, %00100000     ; bottom-left
                    db %00100000, %00111111, %00000000, %00000000
                    db %00000000, %00000000, %00000000, %00000000     ; bottom-centre
                    db %00000000, %11111111, %00000000, %00000000
                    db %00000100, %00000100, %00000100, %00000100     ; bottom-right
                    db %00000100, %11111100, %00000000, %00000000

attr_buffer:        ds 6 * 3
tile_count:         db 0

msg_cls:            db "1 CLS - border should match paper", 0
msg_blit:           db "2 BLIT - col 0 unbroken", 0
msg_img:            db "3 PUT_IMG", 0
msg_panel:          db "4 PANEL 10x6, 6x3, 2x2", 0
msg_direct:         db "5 TEXT - written straight to screen", 0
msg_teletype:       db "Teletype with wrap at 26 columns, ending on a NUL.", 0
msg_attr:           db "6 ATTRS - green at row 0 col 8", 0
msg_done:           db "DONE", 0

                    savesna "gfx_test.sna", start
