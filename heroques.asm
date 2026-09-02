;System
    include "sys/zxspectrum.i"
    include "sys/system.asm"
    include "sys/stack.asm"
;Macroses
    include "core/macros/gfx_macros.asm"
    include "core/macros/macros.asm"
;Structures
    include "core/gfx/gfx_structures.i"
    include "game/menus/menu_structures.i"
    include "game/globals.i"

    device zxspectrum128
    ; zxide: pin
    SLOT 1
    PAGE 5
    org $4000
    INCBIN "bin/ui/screen.scr"
    SLOT 1
    PAGE 5
    org $5EA7                            ; Start of application

appentry:
                    ld sp, $8000
                    ld a, 0
                    out ($FE), a
                    call init_font
;
                    ; $7FFD is write-only, so the ROM keeps a copy of the last
                    ; value written in BANK_SELECTOR and every pager has to read
                    ; it, modify it and write it back. The snapshot starts the
                    ; machine with the port at $10 - 48K ROM, bank 0 - but with
                    ; that copy at zero, so the first read-modify-write would
                    ; clear the ROM bit and page the 128K editor in underneath
                    ; every RST $10 in the game. Tell the truth before anything
                    ; pages anything.
                    ld a, $10
                    ld (BANK_SELECTOR), a
;
                    call music.stop             ; a snapshot starts with
                                                ; whatever the AY held, and
                                                ; init_im2 ends with ei
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
    ;include "core/input/kempston.asm"      ; joystick off: see control_selection
    include "core/input/mouse.asm"
    include "core/math.asm"
    include "core/interrupt.asm"

    ;Storage - the game calls storage.*, and exactly one backend answers.
    ;Uncomment to build the TR-DOS version instead of the tape one.
    ;DEFINE STORAGE_TRDOS
    include "core/storage/storage.asm"      ; the seam: the filename and the
    IFDEF STORAGE_TRDOS                     ; names the game calls
    include "core/storage/trdos.asm"
    ELSE
    include "core/storage/tape.asm"
    ENDIF

    ;UI
    include "game/menus/menus.asm"
    include "game/menus/item_menu.asm"

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
    include "game/globals.asm"
    include "game/items.asm"
    include "game/spells.asm"
    include "game/audio.asm"
    include "game/card_text.asm"
    include "game/saveload.asm"

    ;Main Menu Scenes
    include "game/scenes/main_menu_scene.asm"
    include "game/scenes/input_select_scene.asm"
    include "game/scenes/settings_scene.asm"
    include "game/scenes/alch_shop_scene.asm"
    include "game/scenes/characters_scene.asm"

    ;Game Scene

    ;Data
    include "data/fonts.asm"
    include "data/music_data.asm"
    include "data/card_data.asm"
    include "core/zx0.asm"
    include "assets_generated.asm"

    ; savesna records whichever page is mapped into slot 3 when it runs, and the last
    ; module above set PAGE 4 for the card text - which booted the machine with the
    ; descriptions at $C000 and the scenes nowhere, so game.init jumped into card text.
    ; Nothing is emitted after this; it only says what the snapshot starts with.
    SLOT 3
    PAGE 0

    savesna "heroques.sna", appentry



