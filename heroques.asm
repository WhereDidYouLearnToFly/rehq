;System
    include "sys/zxspectrum.i"
    include "sys/memmap.i"
    include "sys/system.asm"
    include "sys/stack.asm"
;Macroses
    include "core/macros/gfx_macros.asm"
    include "core/macros/macros.asm"
;Structures
    include "core/gfx/gfx_structures.i"
    include "game/menus/menu_structures.i"

    device zxspectrum128
    ; zxide: pin
    org $4000
    INCBIN "bin/ui/screen.scr"
    org AppStart                         ; Start of application

appentry:
                    ld sp, $8000
                    ld a, 0
                    out ($FE), a
                    call init_font
                    call interrupt.init_im2
                    call game.init

init_font:
                    ld hl, fonts.font-256
                    ld (FONT_POINTER), hl
                    ret

;Stack
;Core
    include "core/input/input.asm"          ; the shared layout and dispatcher
    include "core/input/keyboard.asm"       ; ...and one file per device below
    include "core/input/keys.asm"           ; digits and typing, beside the schemes
    ;include "core/input/kempston.asm"     ; joystick off: see control_selection
    include "core/input/mouse.asm"
    include "core/math.asm"
    include "core/interrupt.asm"

    ;UI
    include "game/menus/menus.asm"

    ;SFX
    include "core/audio/beeper.asm"
    include "core/audio/ay.asm"
    include "core/audio/music.asm"
    include "core/audio/ptsplay.asm"

    ;GraphX
    include "core/gfx/draw_attribs.asm"
    include "core/gfx/draw_display.asm"
    include "core/gfx/rom_text.asm"
    include "core/gfx/draw_text.asm"
    include "core/gfx/screen.asm"

    ;Game
    include "game/game.asm"

    ;Main Menu Scenes
    include "game/scenes/main_menu_scene.asm"
    include "game/scenes/input_select_scene.asm"
    include "game/scenes/settings_scene.asm"
    ;include "game/scenes/alch_shop_scene.asm"
    ;include "game/scenes/characters_scene.asm"

    ;Game Scene

    ;Data
    include "data/fonts.asm"
    include "core/zx0.asm"
    include "assets_generated.asm"

    savesna "heroques.sna", appentry



