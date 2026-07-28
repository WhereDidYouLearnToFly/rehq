;=============================================================================
; main - entry point, links the core modules into one image
;=============================================================================
; This is a minimal boot stub, not a game. It brings up IM2 and sits in an
; idle loop so the modules below can be exercised from a debugger or from
; interrupt.on_tick (core/interrupt.asm) once there is game code to hook in.
;
; IM2 rather than IM1 specifically because on_tick only exists on the IM2
; path - the IM2 handler chains to the ROM's own ISR afterwards, so FRAMES,
; the keyboard scan and LAST K all keep working as they would under IM1.
;=============================================================================

                    device zxspectrum128

                    org $8000

                    include "core/math.asm"
                    include "core/interrupt.asm"
                    include "core/input.asm"
                    include "core/mouse.asm"
                    include "core/gfx/gfx_structures.asm"
                    include "core/gfx/screen.asm"
                    include "core/gfx/draw_display.asm"
                    include "core/gfx/draw_attribs.asm"
                    include "core/gfx/draw_text.asm"
                    include "core/zx0.asm"
    include "assets_generated.asm"

start:
                    di
                    ld sp, $7fff

                    ; Modules that carry state have to be primed before the
                    ; first interrupt can reach them. Per-frame reads
                    ; (input.check_input, mouse.read) belong in
                    ; interrupt.on_tick once there is game code to consume them.
                    call math.init_random
                    call mouse.init

                    call interrupt.init_im2     ; does its own ei
.loop:              jr .loop

                    SAVESNA "main.sna", start
