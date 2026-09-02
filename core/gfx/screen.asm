;=============================================================================
; The screen as a coordinate space
;=============================================================================
; Placement:  MemPlan places this one - the org below is the answer.
;
; MODULE screen owns the answer to "where is this coordinate", plus the whole-
; screen state that is nobody else's business: border, default attribute, cls.
; It draws nothing. MODULE draw writes bitmap bytes, MODULE attribs writes
; colour, and both ask here for the address.
;
; That rule exists because there used to be five of these. draw.get_scaddr and
; screen.scaddr were the same routine copied; get_pix_addr_by_bc went through
; the ROM and disagreed with both; direct_text kept its own. Two of them can
; each be self-consistent and still disagree about what row 0 means, and that
; does not show up until something draws eight rows from where it belongs.
;
; There are now two implementations, and everything else wraps one of them:
;
;   ARITHMETIC - cell_address. Nine instructions, no table, no ROM, correct
;   whichever ROM is paged in. This is the default.
;
;   TABLE - main, 192 entries, one per pixel line. What earns its 384 bytes is
;   get_display_table_by_pix_line, which hands back a pointer INTO the table:
;   a routine walking consecutive pixel lines steps that pointer instead of
;   recomputing per line. put_img_desized does exactly that.
;
; Rows are counted 0-23 from the TOP and pixel lines 0-191 from the top, in
; every module. The ROM does not: CL-ADDR ($0E9E) opens with `ld a,$18/sub d`
; because the print routines number the upper screen from the bottom.
; get_pix_addr_by_bc used to call it and so answered for row 24-row - at row 0
; it returned $5800, the attribute file. Nothing here asks the ROM for an
; address any more.
;-----------------------------------------------------------------------------

    SLOT 2
    PAGE 2
    org $9222
    MODULE screen

;-----------------------------------------------------------------------------
; cell_address - D = row (0-23), E = column (0-31). Returns the screen address
; of that cell's top pixel row in DE.
;
; The Spectrum's layout, low byte first: E = (row & 7) * 32 + column, and the
; four `rra` are that multiply by 32 - `and 7` leaves the carry clear, so
; rotating right four times through a 9-bit path brings the three bits back up
; into the top three, which is a rotate left by five. D = $40 + (row & 24)
; picks the third: $40, $48, $50.
;
; The next pixel row down within a cell is `inc d`, which is why draw_char can
; call this once per character instead of once per row.
;-----------------------------------------------------------------------------
cell_address:
          ld a, d
          and %00000111
          rra
          rra
          rra
          rra
          or e
          ld e, a
          ld a, d
          and %00011000
          or %01000000
          ld d, a
          ret

;-----------------------------------------------------------------------------
; get_pix_addr_by_bc - B = column (0-31), C = row (0-23) -> HL.
;
; The same answer as cell_address, in the register convention the rest of the
; gfx modules use for a coordinate pair.
;-----------------------------------------------------------------------------
get_pix_addr_by_bc:
          ld d, c
          ld e, b
          call cell_address
          ex de, hl
          ret

;-----------------------------------------------------------------------------
; get_attr_addr_by_bc - B = column (0-31), C = row (0-23) -> HL = that cell's
; attribute byte.
;
; $5800 + row*32 + column. The three rrca are the multiply by 32, and the two
; bits that wrap out of the top come back in at the bottom - which is exactly
; the high byte of row*32, so masking splits the result into H and L with no
; 16-bit arithmetic and no call to math.imul.
;-----------------------------------------------------------------------------
get_attr_addr_by_bc:
          ld a, c
          rrca
          rrca
          rrca                  ; row*32, the top bits wrapped down into 0-1
          ld l, a
          and %00000011         ; the wrapped bits are the high byte...
          add a, $58
          ld h, a
          ld a, l
          and %11100000         ; ...and the low byte keeps the rest
          or b
          ld l, a
          ret

;-----------------------------------------------------------------------------
; get_display_table_by_pix_line - A = pixel line (0-191) -> HL = that line's
; entry in `main`, NOT the address itself.
;
; Read two bytes for the address and leave HL where it is: the next line's
; entry is two bytes on, so a caller doing eight consecutive lines pays for
; one lookup rather than eight.
;-----------------------------------------------------------------------------
get_display_table_by_pix_line:
          ld hl, main
          ld b, 0
          ld c, a
          add hl, bc
          add hl, bc
          ret

;-----------------------------------------------------------------------------
; get_pix_addr_by_pix_line - A = pixel line (0-191) -> HL = its address.
;-----------------------------------------------------------------------------
get_pix_addr_by_pix_line:
          call get_display_table_by_pix_line
          ld c, (hl)
          inc hl
          ld b, (hl)
          push bc
          pop hl
          ret

;-----------------------------------------------------------------------------
; get_addr_by_pix - B = x in pixels, C = y in pixels -> DE. HL preserved.
;
; The table's other caller. x is rounded down to a character column by the
; three rra plus `and 31`: one byte of the bitmap is eight horizontal pixels,
; so this cannot do better without a shift and a two-byte write. Only y is
; genuinely per-pixel, and that is the entire reason this exists next to
; cell_address - draw_8x8 needs a tile to land on any pixel row.
;-----------------------------------------------------------------------------
get_addr_by_pix:
          push hl
          xor a                    ; clear carry flag and accumulator.
          ld d,a                   ; empty de high byte.
          ld a,c                   ; vertical position
          rla                      ; shift left to multiply by 2.
          ld e,a                   ; place this in low byte of de pair.
          rl d                     ; shift top bit into de high byte.
          ld hl, main              ; table of screen addresses.
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

;=============================================================================
; Whole-screen state
;=============================================================================

cls:
          ld a, (attrib)                 ; blue ink (1) on yellow paper (6*8).
cls_a:
          ld (PAPER_INK_BRIGHT0), a      ; set our screen colours.
          call CLEAR_SCREEN_ROUTINE      ; clear the
          ld a, (border)
          ld (SYS_BORDER), a
          out ($fe), a                   ; write to port 254.
          ret

;-----------------------------------------------------------------------------
; clear_pixels - blank the bitmap, leaving the attributes alone, by pushing
; zeroes down through it with SP. Interrupts off for the duration.
;-----------------------------------------------------------------------------
clear_pixels:
          di                   ;disable interrupt
          ld (.stack + 1), sp  ;store current stack pointer
          ld hl, 0             ;this value will be stored on stack
          ld sp, 16384 + 6144
          ld c, 3
.loop2:
          ld b, l             ;set B to 0. it causes that DJNZ will repeat 256 times
.loop1:
          push hl             ;store hl on stack
          push hl             ;next
          push hl             ;tkjhese four push instruction stores 8 bytes on stack
          push hl
          djnz .loop1          ;repeat for next 8 bytes
          dec c
          jr nz, .loop2
.stack:
          ld sp, 0            ;parameter will overwritten
          ei
          ret                 ; do NOT fall through - fill_attributes is a
                              ; separate entry point, not the second half

;-----------------------------------------------------------------------------
; fill_attributes - flood the attribute file with `attrib`, leaving the bitmap
; alone. The other half of clear_pixels, when you want both.
;-----------------------------------------------------------------------------
fill_attributes:
          ld hl, DISPLAY_ATTRS
          ld de, DISPLAY_ATTRS+1
          ld bc, 767            ;attribute area length - 1
          ld a, (attrib)
          ld (hl), a            ;seed the first byte, then smear it along
          ldir
          ret

;-----------------------------------------------------------------------------
; main - the address of every pixel line, 0-191, in order. The point of
; holding this rather than computing it is that a caller can keep a pointer
; into it and step by two. See the header.
;-----------------------------------------------------------------------------
main:
          dw $4000,$4100,$4200,$4300,$4400,$4500,$4600,$4700
          dw $4020,$4120,$4220,$4320,$4420,$4520,$4620,$4720
          dw $4040,$4140,$4240,$4340,$4440,$4540,$4640,$4740
          dw $4060,$4160,$4260,$4360,$4460,$4560,$4660,$4760
          dw $4080,$4180,$4280,$4380,$4480,$4580,$4680,$4780
          dw $40a0,$41a0,$42a0,$43a0,$44a0,$45a0,$46a0,$47a0
          dw $40c0,$41c0,$42c0,$43c0,$44c0,$45c0,$46c0,$47c0
          dw $40e0,$41e0,$42e0,$43e0,$44e0,$45e0,$46e0,$47e0
          dw $4800,$4900,$4a00,$4b00,$4c00,$4d00,$4e00,$4f00
          dw $4820,$4920,$4a20,$4b20,$4c20,$4d20,$4e20,$4f20
          dw $4840,$4940,$4a40,$4b40,$4c40,$4d40,$4e40,$4f40
          dw $4860,$4960,$4a60,$4b60,$4c60,$4d60,$4e60,$4f60
          dw $4880,$4980,$4a80,$4b80,$4c80,$4d80,$4e80,$4f80
          dw $48a0,$49a0,$4aa0,$4ba0,$4ca0,$4da0,$4ea0,$4fa0
          dw $48c0,$49c0,$4ac0,$4bc0,$4cc0,$4dc0,$4ec0,$4fc0
          dw $48e0,$49e0,$4ae0,$4be0,$4ce0,$4de0,$4ee0,$4fe0
          dw $5000,$5100,$5200,$5300,$5400,$5500,$5600,$5700
          dw $5020,$5120,$5220,$5320,$5420,$5520,$5620,$5720
          dw $5040,$5140,$5240,$5340,$5440,$5540,$5640,$5740
          dw $5060,$5160,$5260,$5360,$5460,$5560,$5660,$5760
          dw $5080,$5180,$5280,$5380,$5480,$5580,$5680,$5780
          dw $50a0,$51a0,$52a0,$53a0,$54a0,$55a0,$56a0,$57a0
          dw $50c0,$51c0,$52c0,$53c0,$54c0,$55c0,$56c0,$57c0
          dw $50e0,$51e0,$52e0,$53e0,$54e0,$55e0,$56e0,$57e0

border:   db $00
attrib:   db 104q

    ENDMODULE
