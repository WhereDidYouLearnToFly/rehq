    SLOT 3
    PAGE 0
    org $C000
    MODULE input_select

PLATE_MSG:
        .db "PRESS FIRE OR CLICK MOUSE"
        .db 0

init:
        call update_message_attribs
        call rom_text.open_upper
        ld bc, $0412
        call rom_text.set_cursor
        ld de, PLATE_MSG
        ld bc, 25
        call rom_text.print_string

        ret

deinit:
         ld a, 1
         ld (menu_index), a
         call update_message_attribs
         ;jp game.init_epigraph
.wait:  
         jp .wait
selected: .db 0
; One frame of this scene, then back to game.loop -- which is what halts, and
; what calls input.check_input. Looping here instead (with a halt of our own)
; meant the scene was entered once and never left, so the input masks were read
; exactly once in the life of the program and every key after that went nowhere.
scene_loop:
            call menu_ctrl
            ld a, (selected)
            and a
            ret nz
            jp toggle_color

scene_interrupt:
            ;call ay.play_timed
            ;update counters
            ld hl, counters
            inc (hl)
            inc hl
            inc (hl)
            ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The press edge, not the level. Fire still held from whatever brought us here
; must not select the moment this scene appears - with `pressed_buttons` it does,
; and the screen looks like it skipped itself.
;
; `up_buttons` used to be in this OR and does not belong: it is a *release*, so
; letting go of fire counted as pressing it and a single tap fired twice.
; `down_buttons` covered `pressed_buttons` all along - a bit that went down this
; frame is also down this frame - so dropping the level test loses nothing.
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