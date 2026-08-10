;=============================================================================
; kempston - the joystick interface on port $1F, classic and extended
;=============================================================================
; Depends on: input.asm, for the bit layout and input.update_state. Include
;             that one first.
; Namespace:  MODULE kempston - reached as kempston.*
;
; Port $1F, active HIGH. Classic interfaces drive five lines,
;
;       bit  7 6 5   4 3 2 1 0
;            0 0 0   F U D L R
;
; and extended ("Mega Drive") ones drive all eight, adding three buttons above
; the classic fire:
;
;       bit  7 6 5   4 3 2 1 0
;            S A C   B U D L R          S = Start, and B/C/A are the pad's
;                                       three face buttons in port-bit order
;
; One read serves both kinds of interface - there is nothing to switch on and
; no mode to select. A classic interface leaves its three unused lines at 0,
; and the cpl that turns active-HIGH into the active-LOW convention turns those
; zeroes into ones, which is exactly what "released" means downstream. So the
; extra buttons simply read as never pressed, with no special case for them.
;=============================================================================
                    org $6168
                    MODULE kempston

; Public: the scheme chooser in input.asm reads this port directly to find out
; whether an interface is there at all.
PORT                equ $1f

; Isolates the three lines only an extended interface drives. Written in port
; bit order, but they land on the same bit positions in our order too - they
; pass through `read` unrotated.
EXTRA_BUTTONS       equ input.FIRE2 | input.FIRE3 | input.START

;-----------------------------------------------------------------------------
; read - one port read, turned into the shared button layout.
;
; The low five are an exact mirror of our bit order once inverted, so they need
; a 5-bit reversal. The top three already sit where FIRE2/FIRE3/START want
; them, so they pass straight through.
;
; Entry: -
; Exit:  a = pressed_buttons, via input.update_state. Corrupts b, c, d.
;-----------------------------------------------------------------------------
read:
                    xor a                       ; the port is (a<<8)|PORT, so A
                                                ; has to be cleared or this reads
                                                ; a Kempston mouse counter
                                                ; instead - see control_selection
                    in a, (PORT)
                    cpl                         ; active HIGH -> active LOW
                    ld d, a                     ; keep a copy for bits 5-7
                    ld b, 0
                    ld c, 5
.reverse:
                    rrca                        ; low bit out to carry...
                    rl b                        ; ...and in at the bottom of b
                    dec c
                    jr nz, .reverse

                    ; d still carries the low five in *hardware* order and b
                    ; carries the same five in ours, so the copy has to be cut
                    ; down to the extras before the merge - OR the two whole
                    ; and the orderings smear over each other.
                    ld a, d
                    and EXTRA_BUTTONS           ; the three extra buttons, in place
                    or b                        ; merged with the reversed five
                    jp input.update_state

                    ENDMODULE
