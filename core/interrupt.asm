;=============================================================================
; interrupt - IM1 / IM2 setup and dispatch
;=============================================================================
; Placement:  init_im2/init_im1 take no ORG - the including file decides
; where they land. im2routine and im2table are pinned to fixed addresses;
; IM2 requires a page-aligned vector table and a handler address of the form
; $xx81 (every entry in the table is the byte $81, so any pair of bytes the
; CPU reads off the table lands on im2routine). Don't place other
; fixed-address code inside $8181-$8300 without moving this.
; Depends on: nothing.
; Namespace:  MODULE interrupt - init_im2/init_im1 are reached as
; interrupt.*; im2routine/im2table sit outside the module, pinned globals.
;=============================================================================
                    ; zxide: pin
                    org $8162
                    MODULE interrupt

;-----------------------------------------------------------------------------
; init_im2 - fill a 257-byte table with $81 and switch to IM2.
;-----------------------------------------------------------------------------
init_im2:
                    di
                    ld hl, im2table
                    ld de, im2table+1
                    ld bc, 256
                    ; Setup the i register
                    ld a, h
                    ld i, a
                    ; Set the first entry in the table to $81
                    ld a, $81
                    ld (hl), a
                    ; Copy to all the remaining 256 bytes
                    ldir
                    ; Setup IM2 mode
                    im 2
                    ei
                    ret

;-----------------------------------------------------------------------------
; init_im1 - switch to IM1 (the ROM's own 50Hz interrupt).
;-----------------------------------------------------------------------------
init_im1:
                    di
                    ld a, IM1_I_VALUE
                    ld i, a
                    im 1
                    ei
                    ret

                    ENDMODULE

; --- IM2 handler: fixed address, outside module scope (see Placement above) ---
; Nothing else guards the region below, so an overrun in whatever was included
; ahead of this module would silently overwrite the handler.
; zxide: pin its address is the fill byte in init_im2 doubled ($81 -> $8181)
                    ASSERT $ <= $8181
                    org $8181
im2routine:
                    push          iy          ; pushed first so it comes off
                                              ; last - see the ROM chain below
                    push          af
                    push          hl
                    push          bc
                    push          de
                    push          ix
                    exx
                    ex            af, af'
                    push          af
                    push          hl
                    push          bc
                    push          de
                    call          on_tick     ; per-frame hook
                    pop           de
                    pop           bc
                    pop           hl
                    pop           af
                    ex            af, af'
                    exx
                    pop           ix
                    pop           de
                    pop           bc
                    pop           hl
                    pop           af
                    pop           iy
                    ei
                    reti

;-----------------------------------------------------------------------------
; on_tick - per-frame hook, called with all registers preserved around it.
; Empty by default; replace this ret with a jp to game code once there is any.
;-----------------------------------------------------------------------------
on_tick:
                    jp game.onInterrupt

; Make sure this is on a 256 byte boundary
                    ; zxide: pin
                    ASSERT $ <= $8200
                    org           $8200
im2table:           defs          257
