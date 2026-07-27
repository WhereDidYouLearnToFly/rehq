;=============================================================================
; main - entry point, links the core modules into one image
;=============================================================================
; This is a minimal boot stub, not a game. It brings up IM1 and sits in an
; idle loop so the modules below can be exercised from a debugger or from
; interrupt.on_tick (core/interrupt.asm) once there is game code to hook in.
;=============================================================================

                    device zxspectrum128

                    org $8000

                    include "core/math.asm"
                    include "core/interrupt.asm"
                    include "core/input.asm"
                    include "core/gfx/gfx_structures.asm"
                    include "core/gfx/screen.asm"
                    include "core/gfx/draw_display.asm"
                    include "core/gfx/draw_attribs.asm"
                    include "core/gfx/draw_text.asm"
                    include "core/zx0.asm"

start:
                    di
                    ld sp, $7fff
                    call interrupt.init_im1
                    ei
.loop:              jr .loop

                    SAVESNA "main.sna", start
