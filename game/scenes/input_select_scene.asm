    SLOT 3
    PAGE 0
    org $C000
    MODULE input_select

PLATE_MSG: .db "PRESS FIRE OR CLICK MOUSE"

init:
        ld a, 0
        ld (selected), a
;
        call update_message_attribs
        call rom_text.open_upper
        ld bc, $0412
        call rom_text.set_cursor
        ld de, PLATE_MSG
        ld bc, 25
        call rom_text.print_string
        ret

deinit:
        jp game.set_main_menu_scene

selected: .db 0

loop:
            call menu_ctrl
            ld a, (selected)
            and a
            jp nz, deinit
            call toggle_color
            jp game.loop

interrupt:
            call input.check_input
            ;call ay.play_timed
            ;update counters
            ld hl, counters
            inc (hl)
            inc hl
            inc (hl)
            ret

menu_ctrl:
                ld a, (input.down_buttons)
                ld b, a
                ld a, (mouse.down_buttons)
                or b
                bit 0, a
                ret z
                ld a, 1
                ld (selected), a
                call attribs.from_center_to_side
                ret

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
                call update_message_attribs
                ret

menu_index:   .db 0
menu_attrib0: .db 100q
menu_attrib1: .db 107q
update_message_attribs:
                ;get color
                ld hl, menu_attrib0
                ld a, (menu_index)
                add a, l
                ld l, a
                ld a, (hl)
                ;attribs
                ld bc, $0412
                ld de, $1901
                call attribs.fill_rectangle
                ret


counters:
counter0:           .db 0
counter1:           .db 0

        ENDMODULE