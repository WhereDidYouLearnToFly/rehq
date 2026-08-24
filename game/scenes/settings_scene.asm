    SLOT 3
    PAGE 0
    org $C18C
    MODULE settings

TEXT_SETTINGS:          MENU_STRING "SETTINGS"
TEXT_REINIT_CTRL:       MENU_STRING "1. REINIT CONTROLS"
TEXT_MUSIC_ON:          MENU_STRING "2. MUSIC  ON "
TEXT_MUSIC_OFF:         MENU_STRING "2. MUSIC  OFF"
TEXT_MOVEMENT_NORMAL:   MENU_STRING "3. MOVEMENT NORMAL"
TEXT_MOVEMENT_FAST:     MENU_STRING "3. MOVEMENT FAST  "
TEXT_EXIT:              MENU_STRING "5. EXIT"

TEXT_REINIT_CTRL_WORK:  .db "PRESS FIRE OR CLICK MOUSE"

YELLOW_ATTR                 equ 106q
RED_ATTR                    equ 102q
MAGENTA_ATTR                equ 103q
GREEN_ATTR                  equ 104q
CYAN_ATTR                   equ 105q

;=============================================================================
; Scene
;=============================================================================

check_and_draw_music:
        ld a, GREEN_ATTR
        ld (PAPER_INK_BRIGHT1), a
        ld bc, $0806
        ld a, (globals.settings)
        bit globals.MUSIC_BIT, a
        jr z, .music_off
        ld hl, TEXT_MUSIC_ON
        jr .print
.music_off:
        ld hl, TEXT_MUSIC_OFF
.print:
        call menus.print_menu_string
        ret

check_and_draw_movement:
        ld a, RED_ATTR
        ld (PAPER_INK_BRIGHT1), a
        ld bc, $0807
        ld hl, TEXT_MOVEMENT_NORMAL
        ld a, (globals.settings)
        bit globals.MOVEMENT_BIT, a
        jr z, .movement_normal
        ld hl, TEXT_MOVEMENT_FAST
        jr .print
.movement_normal:
        ld hl, TEXT_MOVEMENT_NORMAL
.print:
        call menus.print_menu_string
        ret
init:
;
        ld a, 0
        call screen.cls_a
;
        ld a, YELLOW_ATTR
        ld (PAPER_INK_BRIGHT1), a
        ld bc, $0c03
        ld hl, TEXT_SETTINGS
        call menus.print_menu_string
;
        ld a, MAGENTA_ATTR
        ld (PAPER_INK_BRIGHT1), a
        ld bc, $0805
        ld hl, TEXT_REINIT_CTRL
        call menus.print_menu_string
;
        call check_and_draw_music
;
        call check_and_draw_movement
;
        ld a, CYAN_ATTR
        ld (PAPER_INK_BRIGHT1), a
        ld bc, $0809
        ld hl, TEXT_EXIT
        call menus.print_menu_string
;
        ret

deinit:
        ret

loop:
        ld a, (keys.up_digits)
        cp keys.KEY_1
        jr z, .one
        cp keys.KEY_2
        jr z, .two
        cp keys.KEY_3
        jr z, .three
        cp keys.KEY_5
        jr z, .five
        jr .skip                ; 4, and every key that is not one of the four
                                ; above, does nothing. Without this the fall
                                ; through landed in REINIT CONTROLS.
.one:
        call input.reset
        jp game.set_input_select_scene
.two:
        ld a, (globals.settings)
        xor globals.MUSIC
        ld (globals.settings), a
        call check_and_draw_music
        jr .skip
.three:
        ld a, (globals.settings)
        xor globals.MOVEMENT
        ld (globals.settings), a
        call check_and_draw_movement
        jr .skip
.five:
        jp game.set_main_menu_scene
.skip:
        jp game.loop

interrupt:
        call keys.read_digits
        ld (cached_digit), a
;         call input.check_input
;         ld a, mouse.in_use
;         cp 0
;         jr z, .mouse
;         call menus.keyboard_process
; .mouse:
        ret

cached_digit: .db 0

        ENDMODULE
