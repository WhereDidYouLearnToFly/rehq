;=============================================================================
; item_menu - the shop, and anything else that lists cards with numbers
;=============================================================================
; Placement:  MemPlan places this one. It must be page 5, because it reads
;             items.cards and globals.heroes and is called from scenes that
;             live in page 0 at slot 3 - see the note in game/items.asm.
; Depends on: items.get_card, globals.get_hero, menus.print_menu_string,
;             rom_text.print_number_padded, and ItemMenu / ItemColumn in
;             game/menus/menu_structures.i.
; Namespace:  MODULE item_menu.
;
; This is the second menu shape in the game, beside MODULE menus. The two are
; not variants of each other:
;
;   menus      one column of hand-written MenuNodes, one action each. The
;              entries are the point - PLAY GAME, SETTINGS, a character.
;   item_menu  columns of card ids. The entries are data, read out of
;              items.cards, and there is one action for all of them because
;              the only thing you do to an item is buy it.
;
; Trying to make MenuNode carry a price would mean writing a node per card
; restating the name and cost that items.cards already holds, and the shop
; would go stale the first time a price changed. So: a second type.
;
; Nothing here draws from the interrupt, and a cursor move repaints two cells
; rather than the menu. Both of those are the same bug fixed twice over - see
; the note above `pending` near the bottom of this file. It is worth reading
; before adding anything that draws.
;=============================================================================

        SLOT 1
        PAGE 5
        org $7184
    MODULE item_menu

COST_DIGITS     equ 3               ; the dearest card is 550
GOLD_DIGITS     equ 4               ; ...and 9999 gold is more than anyone has

;=============================================================================
; Reading the description
;=============================================================================

;-----------------------------------------------------------------------------
; init - HL = an ItemMenu. Everything else here reads it through ptr_menu, so
; nothing takes it as an argument twice.
;-----------------------------------------------------------------------------
init:
                    ld (ptr_menu), hl
                    ld bc, ItemMenu             ; the struct name is its size,
                    add hl, bc                  ; so adding a field cannot rot
                    ld (ptr_cols), hl           ; where the columns start
                    ret

;-----------------------------------------------------------------------------
; get_column - A = 0..COL_NUM-1, returns IY = that ItemColumn.
;-----------------------------------------------------------------------------
get_column:
                    ld l, a
                    ld h, 0
                    add hl, hl                  ; x2
                    ld d, h
                    ld e, l
                    add hl, hl                  ; x4
                    add hl, de                  ; x6 - ItemColumn is 6 bytes
                    ld de, (ptr_cols)
                    add hl, de
                    push hl
                    pop iy
                    ret

;-----------------------------------------------------------------------------
; column_count - A = column index, returns A = its COUNT. Corrupts HL, DE, IY.
;-----------------------------------------------------------------------------
column_count:
                    call get_column
                    ld a, (iy + ItemColumn.COUNT)
                    ret

;-----------------------------------------------------------------------------
; selected_card - returns A = the card id under the cursor, carry set if the
; cursor is on the exit entry instead.
;-----------------------------------------------------------------------------
selected_card:
                    ld ix, (ptr_menu)
                    ld a, (ix + ItemMenu.SEL_COL)
                    call get_column
                    ld a, (ix + ItemMenu.SEL_ROW)
                    cp (iy + ItemColumn.COUNT)
                    jr nc, .exit                ; the row past the last item
                    add a, (iy + ItemColumn.FIRST)
                    ld iy, music.SYSVARS        ; see the note in draw_entry
                    or a                        ; clear carry: a real card
                    ret
.exit:
                    ld iy, music.SYSVARS
                    scf
                    ret

;=============================================================================
; Drawing
;=============================================================================

;-----------------------------------------------------------------------------
; draw - the whole menu: headers, every entry, the exit and the gold.
;-----------------------------------------------------------------------------
draw:
                    ld ix, (ptr_menu)

                    ; This hero's purse, read once. Every entry is coloured by
                    ; whether it can be afforded, and get_hero wants IX - which
                    ; is the menu for the rest of this routine.
                    ld a, (ix + ItemMenu.HERO)
                    push ix
                    call globals.get_hero
                    ld l, (ix + Hero.GOLD)
                    ld h, (ix + Hero.GOLD + 1)
                    pop ix
                    ld (hero_gold), hl

                    ld a, (ix + ItemMenu.COL_NUM)
                    ld b, a
                    xor a
                    ld (cur_col), a
.column:
                    push bc
                    ld a, (cur_col)
                    call get_column

                    ; The column's geometry, copied out before IY is needed
                    ; for a card.
                    ld a, (iy + ItemColumn.X)
                    ld (col_x), a
                    ld a, (iy + ItemColumn.COST_X)
                    ld (col_cost_x), a
                    ld a, (iy + ItemColumn.FIRST)
                    ld (cur_card), a
                    ld a, (iy + ItemColumn.COUNT)
                    ld (cur_count), a
                    ld l, (iy + ItemColumn.HEADER)
                    ld h, (iy + ItemColumn.HEADER + 1)
                    ld iy, music.SYSVARS        ; nothing but the ROM's own
                    call draw_header            ; base may be in IY when we print

                    ld a, (ix + ItemMenu.POS_Y)
                    ld (cur_row), a
                    xor a
                    ld (cur_index), a
                    ld a, (cur_count)
                    ld b, a
.entry:
                    push bc
                    call draw_entry
                    ld hl, cur_row
                    inc (hl)
                    ld hl, cur_card
                    inc (hl)
                    ld hl, cur_index
                    inc (hl)
                    pop bc
                    djnz .entry

                    ld hl, cur_col
                    inc (hl)
                    pop bc
                    djnz .column

                    call draw_exit
                    jp draw_gold

;-----------------------------------------------------------------------------
; draw_header - HL = the column's header MenuString. Puts it at the column's X
; on the row above the first entry, with "COST" right-aligned to COST_X.
;-----------------------------------------------------------------------------
draw_header:
                    ld a, (ix + ItemMenu.HDR_ATTR)
                    ld (PAPER_INK_BRIGHT1), a
                    ld a, (ix + ItemMenu.POS_Y)
                    dec a                       ; the row above the entries
                    ld (hdr_row), a
                    ld c, a
                    ld a, (col_x)
                    ld b, a
                    call menus.print_menu_string
                    ld hl, COST_TEXT
                    ld a, (col_cost_x)
                    sub COST_WIDTH - 1          ; right-aligned, like the
                    ld b, a                     ; numbers underneath it
                    ld a, (hdr_row)
                    ld c, a
                    jp menus.print_menu_string

;-----------------------------------------------------------------------------
; draw_entry - one card: its name at col_x, its price ending on col_cost_x.
; Reads cur_card, cur_row, cur_index and cur_col.
;-----------------------------------------------------------------------------
draw_entry:
                    ld a, (cur_card)
                    call items.get_card         ; IY = that Card, briefly
                    ld l, (iy + Card.NAME_STR)
                    ld h, (iy + Card.NAME_STR + 1)
                    ld (entry_name), hl
                    ld l, (iy + Card.COST)
                    ld h, (iy + Card.COST + 1)
                    ld (entry_cost), hl
                    ld iy, music.SYSVARS        ; and straight back out again.
                                                ; RST $10 reads the ROM's own
                                                ; variables as (IY+n), so a
                                                ; card parked there is read as
                                                ; the system state - which is
                                                ; why menus.asm keeps its node
                                                ; in memory too
                    call entry_attr
                    ld (PAPER_INK_BRIGHT1), a

                    ld hl, (entry_name)
                    ld a, (col_x)
                    ld b, a
                    ld a, (cur_row)
                    ld c, a
                    call menus.print_menu_string

                    call price_attr
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, (entry_cost)
                    ld a, (col_cost_x)
                    ld b, a
                    ld a, (cur_row)
                    ld c, a
                    ld d, COST_DIGITS
                    ld e, ' '                   ; blank the leading zeros
                    jp rom_text.print_number_padded

;-----------------------------------------------------------------------------
; entry_attr - returns A = the attribute for the entry being drawn.
;
; Selected wins over unaffordable: the cursor has to stay visible even when it
; is sitting on something the hero cannot buy.
;-----------------------------------------------------------------------------
entry_attr:
                    ld a, (ix + ItemMenu.ACTIVE)
                    and a
                    jr z, .price                ; an inactive list has no cursor
                    ld a, (ix + ItemMenu.SEL_COL)
                    ld hl, cur_col
                    cp (hl)
                    jr nz, .price
                    ld a, (ix + ItemMenu.SEL_ROW)
                    ld hl, cur_index
                    cp (hl)
                    jr nz, .price
                    ld a, (ix + ItemMenu.SEL_ATTR)
                    ret
.price:
                    call can_afford
                    ld a, (ix + ItemMenu.DEF_ATTR)
                    ret nc
                    ld a, (ix + ItemMenu.POOR_ATTR)
                    ret

;-----------------------------------------------------------------------------
; price_attr - the same choice as entry_attr, but the price gets its own
; colour when it is neither selected nor out of reach: the screen reads better
; with green names and white numbers.
;-----------------------------------------------------------------------------
price_attr:
                    call entry_attr
                    cp (ix + ItemMenu.DEF_ATTR)
                    ret nz                      ; selected or unaffordable
                    ld a, (ix + ItemMenu.COST_ATTR)
                    ret

;-----------------------------------------------------------------------------
; can_afford - carry set if entry_cost is more than this hero holds.
; Corrupts HL and DE.
;-----------------------------------------------------------------------------
can_afford:
                    ld de, (entry_cost)
                    ld hl, (hero_gold)
                    or a
                    sbc hl, de                  ; gold - cost
                    ret

;-----------------------------------------------------------------------------
; draw_exit - the entry that leaves. It sits outside the columns, so the loop
; above does not reach it, but it is selected the same way: SEL_ROW at or past
; the item count of whichever column the cursor is in.
;-----------------------------------------------------------------------------
draw_exit:
                    ld a, (ix + ItemMenu.DEF_ATTR)
                    ld c, a                     ; unless the cursor is here
                    ld a, (ix + ItemMenu.ACTIVE)
                    and a
                    jr z, .paint
                    ld a, (ix + ItemMenu.SEL_COL)
                    call column_count           ; corrupts HL, DE, IY - not IX
                    ld b, a
                    ld a, (ix + ItemMenu.SEL_ROW)
                    cp b
                    jr c, .paint                ; still on an item
                    ld a, (ix + ItemMenu.SEL_ATTR)
                    ld c, a
.paint:
                    ld iy, music.SYSVARS        ; column_count left one here
                    ld a, c
                    ld (PAPER_INK_BRIGHT1), a
                    ld l, (ix + ItemMenu.EXIT_TEXT)
                    ld h, (ix + ItemMenu.EXIT_TEXT + 1)
                    ld b, (ix + ItemMenu.EXIT_X)
                    ld c, (ix + ItemMenu.EXIT_Y)
                    jp menus.print_menu_string

;-----------------------------------------------------------------------------
; draw_gold - the purse, zero padded so it never leaves a stale digit.
;-----------------------------------------------------------------------------
draw_gold:
                    ld a, (ix + ItemMenu.GOLD_ATTR)
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, (hero_gold)
                    ld a, (ix + ItemMenu.GOLD_X)
                    ld b, a
                    ld a, (ix + ItemMenu.GOLD_Y)
                    ld c, a
                    ld d, GOLD_DIGITS
                    ld e, '0'
                    jp rom_text.print_number_padded

COST_WIDTH      equ 4               ; "COST"
COST_TEXT:      MENU_STRING "COST"

;=============================================================================
; Input
;=============================================================================

;-----------------------------------------------------------------------------
; redraw_at - B = column, C = row within it. Repaints that one entry, or the
; exit entry if the row is past the column's last item.
;
; Moving the cursor changes the colour of two cells and nothing else, so a
; keypress repaints two cells. A full draw is ~180 characters through RST $10,
; and keyboard_process runs inside the interrupt handler - the same interrupt
; the music player is driven from - so a full redraw per key audibly stalls
; the music. This is the fix for that, not an optimisation.
;-----------------------------------------------------------------------------
redraw_at:
                    ld ix, (ptr_menu)
                    ld a, b
                    ld (cur_col), a
                    ld a, c
                    ld (cur_index), a
                    ld a, b
                    call get_column
                    ld a, (iy + ItemColumn.X)
                    ld (col_x), a
                    ld a, (iy + ItemColumn.COST_X)
                    ld (col_cost_x), a
                    ld a, (iy + ItemColumn.FIRST)
                    ld d, a
                    ld e, (iy + ItemColumn.COUNT)
                    ld iy, music.SYSVARS        ; before anything prints
                    ld a, (cur_index)
                    cp e
                    jp nc, draw_exit            ; the row past the last item
                    add a, d                    ; index + FIRST = the card
                    ld (cur_card), a
                    ld a, (ix + ItemMenu.POS_Y)
                    ld hl, cur_index
                    add a, (hl)
                    ld (cur_row), a
                    jp draw_entry               ; hero_gold is still whatever
                                                ; the last full draw read; only
                                                ; buying changes it, and that
                                                ; redraws in full

;-----------------------------------------------------------------------------
; repaint - the cell the cursor just left, then the one it arrived at.
;-----------------------------------------------------------------------------
repaint:
                    ld a, (job_col)             ; the snapshot tick took, not
                    ld b, a                     ; prev_*, which the interrupt
                    ld a, (job_row)             ; may already have moved on
                    ld c, a
                    call redraw_at
                    ld ix, (ptr_menu)
                    ld b, (ix + ItemMenu.SEL_COL)
                    ld c, (ix + ItemMenu.SEL_ROW)
                    jp redraw_at

;-----------------------------------------------------------------------------
; keyboard_process - one edge per call, like menus.keyboard_process.
;
; Up and down run inside one column and wrap; the row past the last item is
; the exit, so falling off the bottom of any column lands on END rather than
; jumping somewhere else. Left and right change column and keep the row, but
; a shorter column has fewer rows to keep it on - the cursor then sits on that
; column's exit row rather than on its last item, so the same key twice never
; lands somewhere unexpected.
;-----------------------------------------------------------------------------
keyboard_process:
                    ld a, (input.up_buttons)
                    and a
                    ret z
                    ld ix, (ptr_menu)
                    ld a, (ix + ItemMenu.ACTIVE)
                    and a
                    ret z                       ; drawn, but not listening
                    ; Remember the cell the cursor is leaving - but only if the
                    ; last move has actually been drawn. If it has not, the
                    ; highlighted cell on screen is still the one prev_* names,
                    ; and two moves between two frames must repaint the first
                    ; cell and the last. The one in the middle was never drawn
                    ; and must not be treated as though it was.
                    ld hl, (pending)
                    ld a, h
                    or l
                    jr nz, .keys
                    ld a, (ix + ItemMenu.SEL_COL)
                    ld (prev_col), a
                    ld a, (ix + ItemMenu.SEL_ROW)
                    ld (prev_row), a
.keys:
                    ld a, (input.up_buttons)
                    and input.DOWN
                    jr nz, .down
                    ld a, (input.up_buttons)
                    and input.UP
                    jr nz, .up
                    ld a, (input.up_buttons)
                    and input.LEFT
                    jr nz, .left
                    ld a, (input.up_buttons)
                    and input.RIGHT
                    jr nz, .right
                    ld a, (input.up_buttons)
                    and input.FIRE
                    jr nz, .fire
                    ret

.down:
                    ld a, (ix + ItemMenu.SEL_COL)
                    call column_count
                    ld b, a                     ; the exit row of this column
                    ld a, (ix + ItemMenu.SEL_ROW)
                    inc a
                    cp b
                    jr z, .set_row              ; onto the exit
                    jr c, .set_row
                    xor a                       ; past it: back to the top
                    jr .set_row
.up:
                    ld a, (ix + ItemMenu.SEL_ROW)
                    dec a
                    jp p, .set_row
                    ld a, (ix + ItemMenu.SEL_COL)
                    call column_count           ; off the top: onto the exit
.set_row:
                    ld (ix + ItemMenu.SEL_ROW), a
                    jp mark_cursor

.right:
                    ld a, (ix + ItemMenu.SEL_COL)
                    inc a
                    ld b, a
                    ld a, (ix + ItemMenu.COL_NUM)
                    cp b
                    ld a, b
                    jr nz, .set_col
                    xor a                       ; off the right: wrap
                    jr .set_col
.left:
                    ld a, (ix + ItemMenu.SEL_COL)
                    dec a
                    jp p, .set_col
                    ld a, (ix + ItemMenu.COL_NUM)
                    dec a
.set_col:
                    ld (ix + ItemMenu.SEL_COL), a
                    call column_count           ; the new column may be shorter
                    ld b, a
                    ld a, (ix + ItemMenu.SEL_ROW)
                    cp b
                    jp c, mark_cursor           ; the row exists here too
                    ld (ix + ItemMenu.SEL_ROW), b
                    jp mark_cursor

.fire:
                    call selected_card          ; carry = the exit entry
                    jr c, .run_exit
                    ld l, (ix + ItemMenu.BUY_ACTION)
                    ld h, (ix + ItemMenu.BUY_ACTION + 1)
                    jp call_hl                  ; A is still the card id
.run_exit:
                    ld l, (ix + ItemMenu.EXIT_ACTION)
                    ld h, (ix + ItemMenu.EXIT_ACTION + 1)
                    jp call_hl

call_hl:
                    jp (hl)

;=============================================================================
; Asking for a redraw instead of doing one
;=============================================================================
; Everything above runs inside the frame interrupt. See the note in menus.asm
; for why drawing there stalls the music; this menu is the one that proved it,
; at about two hundred and thirty ROM character calls for a full repaint,
; against a frame that fits maybe half that.
;
; So the handler writes the address of the drawing it wants into pending and
; returns, and tick - called once a frame from the scene's loop - runs it.
;
; Two jobs, and which one wins matters:
;
;   repaint  the cursor moved. Two cells changed colour and nothing else.
;   draw     gold changed, so every price may have crossed between affordable
;            and not. This one wins: it repaints the cursor's cells too, so a
;            purchase landing on top of a pending repaint loses nothing, while
;            the other way round would lose the recolouring.
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; mark_cursor - the cursor moved. Does nothing if a redraw is already owed:
; a pending `draw` covers this, and a pending `repaint` already names the cell
; that is lit on screen.
;-----------------------------------------------------------------------------
mark_cursor:
                    ld hl, (pending)
                    ld a, h
                    or l
                    ret nz
                    ld hl, repaint
                    ld (pending), hl
                    ret

;-----------------------------------------------------------------------------
; mark_all - gold changed. Overrides whatever was owed.
;-----------------------------------------------------------------------------
mark_all:
                    ld hl, draw
                    ld (pending), hl
                    ret

;-----------------------------------------------------------------------------
; tick - called once a frame from the scene's loop, never from an interrupt.
;
; The `di` is the part worth reading twice. menus.tick needs no such thing,
; because its job reads the selection when it runs and so cannot be stale. But
; `repaint` here needs to know the cell the cursor LEFT, and that lives in
; prev_*, which the interrupt writes. Clear pending first and the interrupt is
; free to fire in the gap: it would see nothing owed, overwrite prev_* with a
; cell that was never drawn, and the cell actually lit on screen would keep
; its highlight for good. Snapshotting prev_* and clearing pending under one
; `di` closes that. A later keypress then finds pending clear, saves prev_*
; itself, and is drawn next frame - which is correct.
;
; The window is a handful of instructions and the loop runs straight after a
; `halt`, so this would almost never happen. Almost never is the worst kind of
; bug to go looking for later.
;-----------------------------------------------------------------------------
tick:
                    di
                    ld hl, (pending)
                    ld a, h
                    or l
                    jr z, .idle
                    ld de, 0
                    ld (pending), de
                    ld a, (prev_col)
                    ld (job_col), a
                    ld a, (prev_row)
                    ld (job_row), a
                    ei
                    jp (hl)
.idle:
                    ei
                    ret

pending:            dw 0            ; a redraw for tick, or 0
job_col:            db 0            ; prev_*, snapshotted as tick claimed the
job_row:            db 0            ; job, so the interrupt cannot move it

ptr_menu:           dw 0
ptr_cols:           dw 0            ; the ItemColumns, straight after the menu
hero_gold:          dw 0            ; read once per draw, not once per entry
entry_name:         dw 0            ; the card being drawn, copied out of the
entry_cost:         dw 0            ; table so IY can go back to the ROM

cur_col:            db 0            ; the column being drawn
cur_index:          db 0            ; the row within it
cur_row:            db 0            ; ...and the screen row that lands on
cur_card:           db 0
cur_count:          db 0
col_x:              db 0            ; the column's geometry, copied out of the
col_cost_x:         db 0            ; ItemColumn so IY can hold a Card
hdr_row:            db 0
prev_col:           db 0            ; where the cursor was before this keypress
prev_row:           db 0

    ENDMODULE
