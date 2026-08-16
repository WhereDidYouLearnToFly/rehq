;=============================================================================
; input - what the player is pressing, whatever they are pressing it on
;=============================================================================
; Depends on: keyboard.asm and kempston.asm, for the readers it dispatches to.
;             Include this one first; the other two reference its bit masks.
; Namespace:  MODULE input - every label below is reached as input.*
;
; This module owns everything that does not care *how* the buttons were read:
; the bit layout, the three masks, the edge detection, and the choice of which
; reader is active. One reader per device lives in its own file beside this
; one, because a device is exactly the unit that gets added, replaced or left
; out of a build - and because a file called kempston.asm is where a person
; looks for the Kempston code.
;
; Call input.check_input once per frame, typically from the interrupt handler.
; It updates three bitmasks, all sharing one layout regardless of which control
; scheme is active:
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

                    org $632D
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

;-----------------------------------------------------------------------------
; check_input - read the active scheme and update the three masks.
; Entry: -
; Exit:  a = pressed_buttons. Corrupts a, b, c, d, h, l.
;-----------------------------------------------------------------------------
check_input:
                    ld hl, (selected_controls)
                    jp (hl)

;-----------------------------------------------------------------------------
; control_selection - the default handler. Waits for the player to press a key
; that identifies which scheme they want, then installs that reader.
;
; The detection reads each device directly rather than calling its reader: a
; reader answers "which buttons are down", and what is wanted here is "is
; anybody there at all", which is a different question with a different answer
; for a missing interface.
;-----------------------------------------------------------------------------
control_selection:
                    ld a, keyboard.ROW_09876    ; key 0 -> Interface 2
                    in a, ($fe)
                    bit 0, a
                    jr z, use_interface2

                    ld a, keyboard.ROW_SPACE    ; SPACE -> QAOP
                    in a, ($fe)
                    bit 0, a
                    jr z, use_qaop

                    ; A mouse click. $FADF is decoded on all sixteen address
                    ; lines, so a Kempston joystick physically cannot answer it
                    ; - which makes this the one non-keyboard probe that
                    ; identifies its device rather than guessing at it. Read
                    ; with `in a,(c)` from a full bc for the same reason: the
                    ; `in a,(n)` form leaves the top half of the address to
                    ; whatever is in A, and this address needs all of it.
                    ld bc, mouse.BUTTONS_PORT
                    in a, (c)
                    or %11111000                ; only the three button bits
                                                ; count; a Next puts a wheel in
                                                ; the top nibble
                    cp $ff
                    jr nz, use_mouse
                    ret

                    ; --- Kempston joystick: switched off on purpose ----------
                    ;
                    ; On original hardware a Kempston joystick and a Kempston
                    ; mouse cannot coexist. The joystick answers *any* port with
                    ; A5, A6 and A7 low, so a mouse click on $001F reads back as
                    ; a joystick with its fire held, and there is no test that
                    ; separates the two. This game is played with the mouse, so
                    ; the joystick is the one that goes.
                    ;
                    ; Modern machines do not have the problem - a Next decodes
                    ; the joystick at exactly $001F and the mouse at the $xxDF
                    ; ports, so both can be fitted (zxnext spec 9.4). To bring
                    ; it back, uncomment these and the include in heroques.asm.
                    ; The `xor a` matters and is not tidiness: `in a,(n)` puts A
                    ; on the top half of the address, so without it this asks
                    ; for $BF1F rather than $001F - which a Next would not
                    ; answer at all, and on which a classic mouse hands back a
                    ; *position counter* that reads as buttons held down.
                    ;
                    ; xor a
                    ; in a, (kempston.PORT)
                    ; cp $ff
                    ; ret z
                    ; and a
                    ; ret z
                    ; jr use_kempston

use_interface2:
                    ld hl, keyboard.read_interface2
                    jr install
use_qaop:
                    ld hl, keyboard.read_qaop
                    jr install
                    ; The mouse needs two things the other schemes do not, which
                    ; is why it does not simply load hl and fall in.
                    ;
                    ; init syncs raw_x/raw_y to the interface's free-running
                    ; counters. Without it the first read measures a delta
                    ; against zero and the cursor jumps to wherever the counters
                    ; happened to be sitting.
                    ;
                    ; in_use is the game's cue that a pointer exists at all. It
                    ; can only be known here: an idle mouse and an absent one
                    ; read identically, so the click that chose it is the proof.
use_mouse:
                    call mouse.init
                    ld a, 1
                    ld (mouse.in_use), a
                    ld hl, mouse.read_scheme    ; pointer *and* buttons, one call
                    ; jr install                ; falls through
; use_kempston:
;                   ld hl, kempston.read
install:
                    ld (selected_controls), hl
                    ld a, 1
                    ld (control_selected), a
                    jp (hl)                     ; read once now, don't lose a frame

;-----------------------------------------------------------------------------
; update_state - given a in hardware form (0 = pressed), update all three
; masks. Every reader in every device file ends with a jump here, so the
; active-low inversion lives in one place and the edge logic is written once.
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
                    ld (mouse.in_use), a        ; or the game keeps drawing a
                    ret                         ; cursor for a device nobody has
                                                ; chosen since the reset

selected_controls:  dw control_selection
control_selected:   db $00
pressed_buttons:    db $00
down_buttons:       db $00
up_buttons:         db $00

                    ENDMODULE
