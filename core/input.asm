;=============================================================================
; input - keyboard and joystick, with press/release edge detection
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: nothing.
; Namespace:  MODULE input - every label below is reached as input.*
;
; Call input.check_input once per frame, typically from the interrupt handler.
; It updates three bitmasks, all sharing one layout regardless of which
; control scheme is active:
;
;   bit 0  FIRE   bit 1  UP   bit 2  DOWN   bit 3  LEFT   bit 4  RIGHT
;   bit 5  FIRE2  bit 6  FIRE3   bit 7  START        (extended Kempston only)
;
;   input.pressed_buttons   held down right now
;   input.down_buttons      went down since the last call   (edge)
;   input.up_buttons        came up since the last call     (edge)
;
; A set bit means pressed. The raw hardware is active-low; the inversion
; happens once, in update_state, so nothing downstream has to think about it.
;
; Bits 5-7 only ever carry the three buttons an extended Kempston interface
; adds; every other scheme, and a classic Kempston interface, reads them as
; released. So code that only cares about the classic five can ignore them
; entirely, and code that wants them needs no setup to get them.
;
; Before check_input does anything useful a scheme must be chosen. Either call
; one of the use_* entries directly, or leave the default in place and let
; check_input poll for the player's choice - control_selected goes non-zero
; once they pick. input.wait_control blocks until then.
;=============================================================================

                    MODULE input

FIRE                equ %00000001
UP                  equ %00000010
DOWN                equ %00000100
LEFT                equ %00001000
RIGHT               equ %00010000

; Extended Kempston only. On a Mega Drive pad FIRE is B, FIRE2 is C and
; FIRE3 is A - the hardware numbers the fire lines in port-bit order, which
; is not the order the letters are printed on the pad.
FIRE2               equ %00100000
FIRE3               equ %01000000
START               equ %10000000

; Isolates the three lines only an extended interface drives. Written in port
; bit order, but they land on the same bit positions in our order too - they
; pass through check_kempston unrotated.
KEMPSTON_MASK       equ FIRE2|FIRE3|START

; Keyboard half-rows, as written to the high byte of port $FE.
ROW_09876           equ $ef             ; 0 9 8 7 6
ROW_QWERT           equ $fb             ; Q W E R T
ROW_ASDFG           equ $fd             ; A S D F G
ROW_POIUY           equ $df             ; P O I U Y
ROW_SPACE           equ $7f             ; SPACE SYM M N B

KEMPSTON_PORT       equ $1f

; Declared here rather than pulled from zxspectrum.i so the module stays
; standalone. MODULE scoping keeps this distinct from any global of the
; same name, so including both is safe.
LAST_KEY            equ 23560           ; ROM system variable LAST K

;-----------------------------------------------------------------------------
; check_input - read the active scheme and update the three masks.
; Entry: -
; Exit:  a = pressed_buttons. Corrupts a, b, c, d, h, l.
;-----------------------------------------------------------------------------
check_input:
                    ld hl, (selected_controls)
                    jp (hl)

;-----------------------------------------------------------------------------
; control_selection - the default handler. Waits for the player to press a
; key that identifies which scheme they want, then installs that reader.
;-----------------------------------------------------------------------------
control_selection:
                    ld a, ROW_09876             ; key 0 -> Interface 2
                    in a, ($fe)
                    bit 0, a
                    jr z, use_interface2

                    ld a, ROW_SPACE             ; SPACE -> QAOP
                    in a, ($fe)
                    bit 0, a
                    jr z, use_qaop

                    ; Kempston fire. There is no reliable way to detect the
                    ; interface itself - an absent one leaves the bus floating,
                    ; which commonly reads $FF - so require a plausible value:
                    ; some button down, but not every line at once. Any of the
                    ; eight will do, so an extended pad can be picked with A, C
                    ; or Start as readily as with fire.
                    in a, (KEMPSTON_PORT)
                    cp $ff
                    ret z
                    and a
                    ret z
                    jr use_kempston

use_interface2:
                    ld hl, check_interface2
                    jr install
use_qaop:
                    ld hl, check_qaop_space
                    jr install
use_kempston:
                    ld hl, check_kempston
install:
                    ld (selected_controls), hl
                    ld a, 1
                    ld (control_selected), a
                    jp (hl)                     ; read once now, don't lose a frame

;-----------------------------------------------------------------------------
; check_interface2 - Sinclair joystick 2: 6=left 7=right 8=down 9=up 0=fire,
; all on row $EF as bit 4..0. Keys 0/9/8 already land on FIRE/UP/DOWN, but 6
; and 7 sit the wrong way round for LEFT/RIGHT, so those two swap.
;-----------------------------------------------------------------------------
check_interface2:
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
                    jp update_state

;-----------------------------------------------------------------------------
; check_qaop_space - Q up, A down, O left, P right, SPACE fire.
; Each read is masked down to the one key it contributes, rotated into its
; slot, and ANDed in: a pressed key reads 0, so AND accumulates them.
;-----------------------------------------------------------------------------
check_qaop_space:
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
                    jp update_state

;-----------------------------------------------------------------------------
; check_kempston - port $1F, active HIGH. Classic interfaces drive five lines,
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
; The low five are an exact mirror of our bit order once inverted, so they need
; a 5-bit reversal. The top three already sit where FIRE2/FIRE3/START want
; them, so they pass straight through.
;
; One read serves both kinds of interface - there is nothing to switch on and
; no mode to select. A classic interface leaves its three unused lines at 0,
; and the cpl that turns active-HIGH into the active-LOW convention turns those
; zeroes into ones, which is exactly what "released" means downstream. So the
; extra buttons simply read as never pressed, with no special case for them.
;
; Entry: -
; Exit:  a = pressed_buttons, via update_state. Corrupts b, c, d.
;-----------------------------------------------------------------------------
check_kempston:
                    in a, (KEMPSTON_PORT)
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
                    and KEMPSTON_MASK           ; the three extra buttons, in place
                    or b                        ; merged with the reversed five
                    jp update_state

;-----------------------------------------------------------------------------
; update_state - given a in hardware form (0 = pressed), update all three
; masks. Every reader ends here, so the active-low inversion lives in one
; place and the edge logic is written once.
; Exit: a = pressed_buttons. Corrupts b, d.
;-----------------------------------------------------------------------------
update_state:
                    cpl                         ; now 1 = pressed
                    ld d, a                     ; d = current
                    ld a, (pressed_buttons)
                    ld b, a                     ; b = previous

                    xor d
                    and d
                    ld (down_buttons), a        ; set now, clear before

                    ld a, d
                    xor b
                    and b
                    ld (up_buttons), a          ; set before, clear now

                    ld a, d
                    ld (pressed_buttons), a
                    ret

;-----------------------------------------------------------------------------
; wait_any_key - block until any key is pressed, via the ROM's LAST K.
; Needs interrupts enabled; the ROM handler is what fills LAST K in.
;-----------------------------------------------------------------------------
wait_any_key:
                    ld hl, LAST_KEY
                    ld (hl), 0
.loop:
                    ld a, (hl)
                    and a
                    jr z, .loop
                    ret

;-----------------------------------------------------------------------------
; wait_control - block until a scheme has been chosen. Only useful while
; check_input is being called from the interrupt handler; on its own this
; spins forever.
;-----------------------------------------------------------------------------
wait_control:
                    ld a, (control_selected)
                    and a
                    jr z, wait_control
                    ret

;-----------------------------------------------------------------------------
; reset - forget the chosen scheme and clear all state.
;-----------------------------------------------------------------------------
reset:
                    ld hl, control_selection
                    ld (selected_controls), hl
                    xor a
                    ld (control_selected), a
                    ld (pressed_buttons), a
                    ld (down_buttons), a
                    ld (up_buttons), a
                    ret

selected_controls:  dw control_selection
control_selected:   db $00
pressed_buttons:    db $00
down_buttons:       db $00
up_buttons:         db $00

                    ENDMODULE
