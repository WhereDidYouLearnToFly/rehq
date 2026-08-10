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
    ; zxide: size(100)
    org Game
    MODULE game


pscene_init:      dw input_select.init
pscene_deinit:    dw input_select.deinit
pscene_loop:      dw input_select.scene_loop
pscene_interrupt: dw input_select.scene_interrupt

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

set_main_menu:
                ret

set_game_play:
                ret

init:
                call pscene_init_call

loop:
                halt
                PERF_MARK 1             ; red: the frame's work starts here
                call input.check_input
                PERF_MARK 2             ; red: the frame's work starts here
                call pscene_loop_call
                PERF_MARK 0             ; black: done, the rest of the frame is idle
                jp loop
onInterrupt:
                call pscene_interrupt_call
                ret

        ENDMODULE
