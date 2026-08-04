    MODULE main_menu
init:
        ld a, $0
        ld bc, $0
        ld de, $2018
        call attribs.fill_rectangle
        ;
        ld a, 0
        ld (selected), a
        ;
        ld a, 170q
        ld bc, $0
        ld de, $2018
        call attribs.fill_rectangle
        ;
        ld a, (menu_attrib0)
        ld bc, $040d
        ld de, $0a01
        call attribs.fill_rectangle
        ret

deinit:
         ld a, 1
         ld (menu_index), a
         call update_start_attribs
         ;jp game.init_epigraph
.wait:  
         jp .wait
selected: .db 0
scene_loop:
.mainloop:
            call menu_ctrl
            halt
            ld a, (selected)
            cp 0
            ret nz
            call toggle_color
            jr .mainloop

scene_interrupt:
            ;call ay.play_timed
            ;update counters
            ld hl, counters
            inc (hl)
            inc hl
            inc (hl)
            ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
menu_ctrl:
            ld a, (input.pressed_buttons)
            ld b, a
            ld a, (input.down_buttons)
            ld c, a
            ld a, (input.up_buttons)
            or b
            or c
            bit 0, a
            ret z
            ld a, 1
            ld (selected), a
            call attribs.from_center_to_side
            ret

PLATE_MSG: .dm "PRESS FIRE"


toggle_color:
                ld a, (selected)
                cp 0
                ret nz
                ld a, (counter0)
                cp 15
                ret c 
.do_toggle:
                ld a, 0
                ld (counter0), a
                ;
                ld a, (menu_index)
                xor 1
                ld (menu_index), a
                call update_start_attribs
                ret

menu_index:   .db 0
menu_attrib0: .db 100q
menu_attrib1: .db 107q
update_start_attribs:
                ;get color
                ld hl, menu_attrib0
                ld a, (menu_index)
                add a, l
                ld l, a
                ld a, (hl)
                ;attribs
                ld bc, $040d
                ld de, $0a01
                call attribs.fill_rectangle
                ret


counters:
counter0:           .db 0
counter1:           .db 0

        ENDMODULE