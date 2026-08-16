        org $63F7
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
draw_items:
                    ld ix, (ptr_menu)
                    ld a, (ix + MenuList.NODE_NUM)
                    ld b, a                     ; how many
                    xor a                       ; set if to the first one
.next:
                    push bc
                    push af
                    call get_node
                    inc hl                      ; skip ID, want TEXT_ID
                    ld a, (hl)
                    call get_string             ; HL = the text to print
                    pop af
                    push af
;
                    push af
                    ld a, (ix + MenuList.ACTIVE)
                    cp 0
                    jr z, .default
                    pop af
                    push af
                    ld b, a
                    ld a, (ix + MenuList.SELECTED_IDX)
                    cp b
                    jr nz, .default
.selected:
                    ld a, (ix + MenuList.SEL_ATTR)
                    jr .attribs
.default:           ld a, (ix + MenuList.DEF_ATTR)
.attribs:
                    ld (PAPER_INK_BRIGHT1), a
                    pop af
;
                    ld b, a
                    ld a, (ix + MenuList.POS_Y)
                    add b
                    ld c, a                     ; row
                    ld a, (ix + MenuList.POS_X)
                    ld b, a
                    call print_menu_string
                    pop af
                    inc a
                    pop bc
                    djnz .next
                    ret

init_menu:
                    ld (ptr_menu), hl
                    ld ix, hl
                    push hl
;;;;
                    ld b, 0
                    ld c, MenuList.SEL_ATTR + 1
                    add hl, bc
;;;;
                    ld (ptr_nodes), hl
                    ld   a, (ix + MenuList.NODE_NUM)
                    add  a, a
                    ld   c, a
                    ld   b, 0
                    add  hl, bc
                    ld   (ptr_strings), hl
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
        jr .reinit
.reinit:
        ld (ix + MenuList.SELECTED_IDX), a
        ld  hl, (ptr_menu)
        call init_menu
        call draw_items
;
.fire:
.skip:
        ret

; is_active:              .db 0
; selected_idx:           .db 0
; node_num:               .db 0
; string_num:             .db 0
; pos_x:                  .db 0
; pos_y:                  .db 0
; def_attr:               .db 0
; sel_attr:               .db 0

ptr_menu:               .dw 0
ptr_nodes:              .dw 0
ptr_strings:            .dw 0

    ENDMODULE
