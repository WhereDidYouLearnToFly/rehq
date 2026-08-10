;=============================================================================
; keyboard - the two keyboard control schemes, and the half-rows they read
;=============================================================================
; Depends on: input.asm, for the bit layout and input.update_state. Include
;             that one first.
; Namespace:  MODULE keyboard - reached as keyboard.*
;
; Both readers end at input.update_state with the accumulated byte still in
; *hardware* form - 0 means pressed - because that is the form the keyboard
; hands out and converting it twice would be one conversion too many. The
; single cpl that flips it lives there, shared with every other device.
;
; The technique in both is the same, and it is worth stating once. A row read
; gives eight lines at once, of which one or two are wanted. So each read is
; ORed with a mask that forces every uninteresting bit to 1 (released), then
; rotated until the wanted bit sits in the slot our layout gives it, then ANDed
; into the accumulator - and because pressed is 0, AND is what accumulates.
;=============================================================================

                    org $613D
                    MODULE keyboard

; Keyboard half-rows, as written to the high byte of port $FE. Public because
; the scheme chooser in input.asm polls two of them directly.
ROW_09876           equ $ef             ; 0 9 8 7 6
ROW_QWERT           equ $fb             ; Q W E R T
ROW_ASDFG           equ $fd             ; A S D F G
ROW_POIUY           equ $df             ; P O I U Y
ROW_SPACE           equ $7f             ; SPACE SYM M N B

; Declared here rather than pulled from zxspectrum.i so the module stays
; standalone. MODULE scoping keeps this distinct from any global of the same
; name, so including both is safe.
LAST_KEY            equ 23560           ; ROM system variable LAST K

;-----------------------------------------------------------------------------
; read_interface2 - Sinclair joystick 2: 6=left 7=right 8=down 9=up 0=fire,
; all on row $EF as bit 4..0. Keys 0/9/8 already land on FIRE/UP/DOWN, but 6
; and 7 sit the wrong way round for LEFT/RIGHT, so those two swap.
;-----------------------------------------------------------------------------
read_interface2:
                    ld a, ROW_09876
                    in a, ($fe)
                    or %11100000                ; bits 5-7 float (bit 6 is EAR) - force released
                    ld c, a                     ; c = raw row
                    or %00011000                ; release the LEFT/RIGHT slots
                    ld b, a

                    ld a, c                     ; key 6 (bit 4) -> LEFT (bit 3)
                    or %11101111
                    rrca
                    and b
                    ld b, a

                    ld a, c                     ; key 7 (bit 3) -> RIGHT (bit 4)
                    or %11110111
                    rlca
                    and b
                    jp input.update_state

;-----------------------------------------------------------------------------
; read_qaop - Q up, A down, O left, P right, SPACE fire.
;-----------------------------------------------------------------------------
read_qaop:
                    ld a, ROW_QWERT             ; Q (bit 0) -> UP (bit 1)
                    in a, ($fe)
                    or %11111110
                    rlca
                    ld b, a

                    ld a, ROW_ASDFG             ; A (bit 0) -> DOWN (bit 2)
                    in a, ($fe)
                    or %11111110
                    rlca
                    rlca
                    and b
                    ld b, a

                    ld a, ROW_POIUY             ; O and P share a row and go to
                    in a, ($fe)                 ; non-adjacent slots, so they are
                    ld c, a                     ; placed one at a time.

                    or %11111101                ; O (bit 1) -> LEFT (bit 3)
                    rlca
                    rlca
                    and b
                    ld b, a

                    ld a, c                     ; P (bit 0) -> RIGHT (bit 4)
                    or %11111110
                    rlca
                    rlca
                    rlca
                    rlca
                    and b
                    ld b, a

                    ld a, ROW_SPACE             ; SPACE (bit 0) -> FIRE (bit 0)
                    in a, ($fe)
                    or %11111110
                    and b
                    jp input.update_state

;-----------------------------------------------------------------------------
; wait_any_key - block until any key is pressed, via the ROM's LAST K.
; Needs interrupts enabled; the ROM handler is what fills LAST K in, so this
; is the one routine here that does not read the hardware itself.
;-----------------------------------------------------------------------------
wait_any_key:
                    ld hl, LAST_KEY
                    ld (hl), 0
.loop:
                    ld a, (hl)
                    and a
                    jr z, .loop
                    ret

                    ENDMODULE
