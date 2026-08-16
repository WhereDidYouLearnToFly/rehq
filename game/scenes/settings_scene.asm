    SLOT 3
    PAGE 0
    org $C156
    MODULE settings

TEXT_SETTINGS:          .db "SETTINGS"
TEXT_REINIT_CTRL:       .db "1. REINIT CONTROLS"
TEXT_MUSIC_ON:          .db "2. MUSIC: ON"
TEXT_MUSIC_OFF:         .db "2. MUSIC: OFF"
TEXT_MOVEMENT_NORMAL:   .db "3. MOVEMENT: NORMAL"
TEXT_MOVEMENT_FAST:     .db "3. MOVEMENT: FAST"
TEXT_EXIT:              .db "0. EXIT"

TEXT_REINIT_CTRL_WORK:  .db "PRESS FIRE OR CLICK MOUSE"

YELLO_ATTR                 equ 106q
RED_ATTR                   equ 107q
MAGENTA_ATTR               equ 103q
GREEN_ATTR                 equ 104q
CYAN_ATTR                  equ 105q

;=============================================================================
; Scene
;=============================================================================

init:
        ld bc, $1204
        call rom_text.set_cursor
        ld de, TEXT_SETTINGS
        ld bc, 8
        call rom_text.print_string
        ret

deinit:
        ret

loop:
        ret

interrupt:
;         call input.check_input
;         ld a, mouse.in_use
;         cp 0
;         jr z, .mouse
;         call menus.keyboard_process
; .mouse:
        ret

        ENDMODULE
