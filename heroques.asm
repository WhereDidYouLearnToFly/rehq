;System
    include "sys/zxspectrum.i"
    include "sys/memmap.i"
    include "sys/system.asm"
    include "sys/stack.asm"
;Macroses
    include "core/macros/gfx_macros.asm"
    include "core/macros/macros.asm"
;Structures
    include "core/gfx/gfx_structures.asm"


    device zxspectrum128
    ; zxide: pin
    org $4000
    INCBIN "bin/ui/screen.scr"
    org AppStart                         ; Start of application

appentry:
                    SELECT_RAM_BANK 0
                    SELECT_RAM_BANK 1
                    ld sp, $8000
                    ld a, 0
                    out ($FE), a
                    call init_font
                    call interrupt.init_im2
                    ;call game.init
wait_for_start:
                    jp wait_for_start
init_font:
                    ld hl, fonts.font-256
                    ld (FONT_POINTER), hl
                    ret


;Stack
;Core
    include "core/input.asm"
    include "core/math.asm"
    include "core/interrupt.asm"

    ;SFX
    include "core/audio/beeper.asm"

    ;GraphX
    include "core/gfx/draw_attribs.asm"
    include "core/gfx/draw_display.asm"
    include "core/gfx/draw_text.asm"
    include "core/gfx/screen.asm"

    ;Game
    include "game/game.asm"
    include "game/scenes/main_menu.asm"

    ;Data
    include "data/fonts.asm"
    include "core/zx0.asm"

    savesna "heroques.sna", appentry



