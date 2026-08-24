;=============================================================================
; game - the frame loop, and the scene it is currently running
;=============================================================================
; Placement:  SLOT 1 / PAGE 5, org Game.
; Depends on: the active scene's entry points, reached only through the
;             pscene_* pointers below - nothing here names a scene.
; Namespace:  MODULE game - init/loop/onInterrupt are reached as game.*
;=============================================================================

;-----------------------------------------------------------------------------
; PERF_MARK - paint the border, so the cost of a frame is visible as a band.
;
; Red from the moment the frame's work starts, black the moment it ends: the
; height of the red band *is* the share of the frame you are spending. When it
; reaches the bottom of the screen you are over budget (69888 T-states on a
; 48K, 70908 on a 128K) and the game has started dropping frames.
;
; Costs 4 bytes and 18 T-states per mark, and only when the meter is switched
; on - with the DEFINE below commented out, not one byte is assembled.
;
; It writes port $FE, so bits 3/4 (MIC/EAR) go low with every mark. That is
; silence rather than a click while both marks agree, but it does mean this
; meter and a beeper engine cannot share a frame.
;-----------------------------------------------------------------------------
    ;DEFINE PERF_BORDER             ; comment out to remove the meter entirely

    MACRO PERF_MARK color
    IFDEF PERF_BORDER
                ld a, color
                out ($fe), a
    ENDIF
    ENDM

    SLOT 1
    PAGE 5
    ; zxide: size(130)
    org Game
    MODULE game


pscene_init:      dw input_select.init
pscene_deinit:    dw input_select.deinit
pscene_loop:      dw input_select.loop
pscene_interrupt: dw input_select.interrupt

pscene_init_call:
                ld hl, (pscene_init)
                jp (hl)

pscene_loop_call:
                ld hl, (pscene_loop)
                jp (hl)

pscene_deinit_call:
                ld hl, (pscene_deinit)
                jp (hl)

pscene_interrupt_call:
                ld hl, (pscene_interrupt)
                jp (hl)

;-----------------------------------------------------------------------------
; The scene switch. A set_ entry is jumped to, never called: it replaces the
; four pointers above and restarts the frame loop on the new scene, so there
; is no way back to whoever asked for it.
;
; The entry points travel as a four word table copied in one ldir, in the same
; order as the pscene_ words above - init, deinit, loop, interrupt. Reorder
; one list and the other has to move with it.
;-----------------------------------------------------------------------------
set_input_select_scene:
                ld hl, input_select_scene
                jr set_scene
set_main_menu_scene:
                ld hl, main_menu_scene
                jr set_scene
set_settings_scene:
                ld hl, settings_scene
                jr set_scene
set_chartacters_scene:
                ld hl, characters_scene
                jr set_scene
set_shop_scene:
                ld hl, shop_scene
                ; falls through
set_scene:
                di
                ld de, pscene_init
                ld bc, 8
                ldir
                ei
                jp init

; Not a scene yet. A set_ entry never returns, so this cannot ret - it drops
; back into the frame loop with the scene that is already running.
set_game_play_scene:
                jp loop

input_select_scene: dw input_select.init, input_select.deinit
                    dw input_select.loop, input_select.interrupt
main_menu_scene:    dw main_menu.init, main_menu.deinit
                    dw main_menu.loop, main_menu.interrupt
settings_scene:     dw settings.init, settings.deinit
                    dw settings.loop, settings.interrupt
characters_scene:   dw characters_menu.init, characters_menu.deinit
                    dw characters_menu.loop, characters_menu.interrupt
shop_scene:         dw shop_menu.init, shop_menu.deinit
                    dw shop_menu.loop, shop_menu.interrupt

init:
                call pscene_init_call

loop:
                halt
                jp pscene_loop_call

onInterrupt:
                call pscene_interrupt_call
                ret

        ENDMODULE
