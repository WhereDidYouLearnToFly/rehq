            org Interrupt

interrupt.init_im2:
              di
              ld hl, im2table
              ld de, im2table+1
              ld bc, 256
              ; Setup the i register
              ld a, h
              ld i, a
              ; Set the first entries in the table to $81
              ld a, $81
              ld (hl), a
              ; Copy to all the remaining 256 bytes
              ldir
              ; Setup IM2 mode
              im 2
              ei
              ret

interrupt.init_im1:
            di
            ld a, IM1_I_VALUE
            ld i, a
            im 1
            ei
            ret

            org $8181
im2routine:
            push          af
            push          hl
            push          bc
            push          de
            push          ix
            push          iy
            exx
            ex            af, af'
            push          af
            push          hl
            push          bc
            push          de
            call          game.onInterrupt
            pop           de
            pop           bc
            pop           hl
            pop           af
            ex            af, af'
            exx
            pop           iy
            pop           ix
            pop           de
            pop           bc
            pop           hl
            pop           af
            jp            IM1_INTERRUPT
;           ei
;           reti

; Make sure this is on a 256 byte boundary
            org           $8200
im2table:   defs          257

