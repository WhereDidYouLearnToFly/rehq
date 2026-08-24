        org $649A
    MODULE menus

;=============================================================================
; Reading the description
;=============================================================================

;-----------------------------------------------------------------------------
; get_string - A = a TEXT_ constant, returns HL = that MenuString.
; get_node   - A = 0..NODE_NUM-1, returns HL = that MenuNode.
;-----------------------------------------------------------------------------
get_string:
                    ld hl, (ptr_strings)
                    jr get_entry
get_node:
                    ld hl, (ptr_nodes)
get_entry:
                    add a, a                    ; two bytes to a pointer
                    ld e, a
                    ld d, 0
                    add hl, de
                    ld e, (hl)                  ; follow it
                    inc hl
                    ld d, (hl)
                    ex de, hl
                    ret

;-----------------------------------------------------------------------------
; print_menu_string - HL = a MenuString, B = column, C = row.
;
; The length travels with the string, so no caller counts characters. Set the
; colour in PAPER_INK_BRIGHT1 first; that is the one printing reads.
;-----------------------------------------------------------------------------
print_menu_string:
                    push hl
                    call rom_text.set_cursor
                    pop hl
                    ld c, (hl)                  ; SIZE
                    ld b, 0
                    inc hl                      ; the text follows it
                    ex de, hl
                    jp rom_text.print_string

;-----------------------------------------------------------------------------
; draw_items - print every node's text down the screen.
;-----------------------------------------------------------------------------
; The node pointer lives here rather than in IY: the colour comes from the
; node, but printing it goes through the ROM, and the ROM reaches its system
; variables as (IY+n). Park a node in IY and RST $10 writes over the node.
cur_node:           .dw 0
cur_row:            .db 0       ; POS_Y, then a STEP further down per item

draw_items:
                    ld ix, (ptr_menu)
                    ld a, (ix + MenuList.NODE_NUM)
                    ld b, a                     ; how many
                    ld c, 0                     ; which one
                    ld a, (ix + MenuList.POS_Y)
                    ld (cur_row), a             ; the first row
.next:
                    push bc
                    ld a, c
                    call get_node
                    ld (cur_node), hl
                    inc hl                      ; skip ID, want TEXT_ID
                    ld a, (hl)
                    call get_string             ; HL = the text to print
                    push hl                     ; hold it while a colour is picked
;;;;
                    ld hl, (cur_node)
                    ld de, MenuNode.DEF_ATTR
                    add hl, de
                    ld a, (ix + MenuList.ACTIVE)
                    and a                       ; an inactive list has no
                    jr z, .attribs              ; selection to highlight
                    ld a, (ix + MenuList.SELECTED_IDX)
                    cp c
                    jr nz, .attribs
                    inc hl                      ; SEL_ATTR follows DEF_ATTR
.attribs:
                    ld a, (hl)
                    ld (PAPER_INK_BRIGHT1), a
                    pop hl                      ; the text again
;;;;
                    ld a, (cur_row)
                    ld c, a                     ; row
                    ld a, (ix + MenuList.POS_X)
                    ld b, a                     ; column
                    call print_menu_string
                    ld a, (cur_row)
                    add a, (ix + MenuList.STEP) ; down to the next item
                    ld (cur_row), a
                    pop bc
                    inc c
                    djnz .next
                    ret

init_menu:
                    ld (ptr_menu), hl
                    push hl
;
                    push hl
                    pop ix
;;;;
                    ld bc, MenuList             ; the struct name is its size,
                    add hl, bc                  ; so adding a field cannot rot this
;;;;
                    ld (ptr_nodes), hl
                    ld   a, (ix + MenuList.NODE_NUM)
                    add  a, a
                    ld   c, a
                    ld   b, 0
                    add  hl, bc
                    ld   (ptr_strings), hl
;
                    pop hl
;;;;
                    ret

;---------------------------------------------------------------------------
;
;INPUT PROCESS: KEYBOARD
;---------------------------------------------------------------------------

keyboard_process:
        ld a, (input.up_buttons)
        cp 0
        jr z, .skip
;
        and input.DOWN
        cp 0
        jr nz, .down
;
        ld a, (input.up_buttons)
        and input.UP
        cp 0
        jr nz, .up
;
        ld a, (input.up_buttons)
        and input.FIRE
        cp 0
        jr nz, .fire
        jr .skip
.down:
        ld ix, (ptr_menu)
        ld a, (ix + MenuList.SELECTED_IDX)
;
        inc a
        ld b, a
        ld a, (ix + MenuList.NODE_NUM)
        cp b
        ld a, b
        jr nz, .reinit
        ld a, 0
        jr .reinit
.up:
        ld ix, (ptr_menu)
        ld a, (ix + MenuList.SELECTED_IDX)
;
        dec a
        jp p, .reinit
        ld a, (ix + MenuList.NODE_NUM)
        dec a
.reinit:
        ld (ix + MenuList.SELECTED_IDX), a
        ld  hl, (ptr_menu)
        call init_menu
        call draw_items
        jr .skip
;       
.fire:
        ld ix, (ptr_menu)
        ld a, (ix + MenuList.SELECTED_IDX)
        call get_node
        push hl
        pop ix
        ld l, (ix + MenuNode.ACTION)
        ld h, (ix + MenuNode.ACTION + 1)
        call call_hl

.skip:
        ret

call_hl:
        jp (hl)

ptr_menu:               .dw 0
ptr_nodes:              .dw 0
ptr_strings:            .dw 0

    ENDMODULE
