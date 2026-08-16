;=============================================================================
; keys - the keyboard read as a keyboard: digits for menus, ASCII for typing
;=============================================================================
; Depends on: nothing. input.asm is not needed and not touched - these read
;             the hardware themselves and keep their own state.
; Namespace:  MODULE keys - every label below is reached as keys.*
;
; input.asm answers "which way is the player pushing", and the two schemes in
; keyboard.asm are five buttons that happen to be keys. This file answers the
; other question - "which *key* is down" - which is what a numbered menu entry
; and a name entry field need, and what a five-bit direction mask cannot carry.
;
; Nothing here writes input.pressed_buttons or the selected scheme, so it can
; be called next to input.check_input in the same frame whatever device the
; player picked - a mouse player can still press 3, or type a name.
;
; It also does not care about the interrupt mode. Every routine reads port $FE
; itself rather than going through the ROM's LAST K, because the IM2 handler in
; interrupt.asm does not chain to the ROM and so nothing fills LAST K in.
;
; Two entries, both edge triggered - a key reports once when it goes down and
; then reads as nothing until it is released:
;
;   keys.get_digit    a = 1..5 for a number key just pressed, 0 for none.
;   keys.read_char    a = the character of a key just pressed, 0 for none.
;
; Call either once per frame, typically from the same place that calls
; input.check_input. Calling both in one frame is fine; they keep separate
; state, so a 3 pressed during name entry does not vanish from get_digit.
;=============================================================================

                    org $64D0
                    MODULE keys

; Keyboard half-rows, as written to the high byte of port $FE. Declared here
; rather than pulled from keyboard.asm so this module stands on its own; the
; MODULE scoping keeps them distinct from the copies over there.
ROW_CSZXCV          equ $fe             ; CAPS SHIFT Z X C V
ROW_12345           equ $f7             ; 1 2 3 4 5
ROW_SPACE           equ $7f             ; SPACE SYM M N B

;=============================================================================
; The number keys 1-5
;=============================================================================
; One half-row holds all five, in bit order, so this is a single port read and
; no shuffling - which is the whole reason to have it separate from read_char
; instead of asking that one whether it just handed back a '3'.
;
; The masks follow the same three-way split as input.asm - held, just down,
; just up - because that is the shape the rest of the game already reads. A
; menu wants down_digits; something charging up a spell would want the other
; two.
;
; Keys 6-0 sit on row $EF (see keyboard.ROW_09876) in the *reverse* order -
; bit 0 is 0, bit 4 is 6 - so if a menu ever needs more than five shortcuts
; they need reversing into place rather than a second copy of this.
;=============================================================================

KEY_1               equ %00000001
KEY_2               equ %00000010
KEY_3               equ %00000100
KEY_4               equ %00001000
KEY_5               equ %00010000

;-----------------------------------------------------------------------------
; read_digits - poll row 12345 and update the three digit masks.
; Entry: -
; Exit:  a = pressed_digits. Corrupts b, d.
;-----------------------------------------------------------------------------
read_digits:
                    ld a, ROW_12345
                    in a, ($fe)
                    or %11100000                ; bits 5-7 float - force released
                    cpl                         ; now 1 = pressed
                    ld d, a                     ; d = current
                    ld a, (pressed_digits)
                    ld b, a                     ; b = previous

                    xor d
                    and d
                    ld (down_digits), a         ; set now, clear before

                    ld a, d
                    xor b
                    and b
                    ld (up_digits), a           ; set before, clear now

                    ld a, d
                    ld (pressed_digits), a
                    ret

;-----------------------------------------------------------------------------
; get_digit - the one call a numbered menu needs.
; Entry: -
; Exit:  a = 1..5 if that number key has just gone down, 0 if none has.
;        Corrupts b, d.
;
; Reads the down edge, not the held state, so holding 2 does not select twice.
; Two keys going down in the same frame report the lower number; the higher
; one is dropped rather than queued, which is the right answer for a menu -
; the alternative is acting on a keypress a frame or two after the menu it was
; meant for has gone.
;
; It polls for itself, so it is the whole call. Don't also call read_digits in
; the same frame: the second poll finds the edges already accounted for and
; the keypress disappears. Use one or the other.
;-----------------------------------------------------------------------------
get_digit:
                    call read_digits
                    ld a, (down_digits)
                    and a
                    ret z                       ; nothing new - a is already 0
                    ld b, 1
.find:
                    srl a
                    jr c, .found
                    inc b
                    jr .find
.found:
                    ld a, b
                    ret

pressed_digits:     db 0
down_digits:        db 0
up_digits:          db 0

;=============================================================================
; The whole keyboard
;=============================================================================
; read_char walks all eight half-rows and hands back a character, so anything
; that needs typing - a hero's name, a saved game slot - gets it from here.
;
; The rows are walked by rotating one mask: $FE $FD $FB $F7 $EF $DF $BF $7F is
; exactly rlc applied eight times, and it is also exactly the order the ROM
; lays the matrix out in, so char_table below is the standard 40-entry table
; with no reordering to get wrong.
;
; The two shift keys carry 0 in that table rather than a character, which is
; what marks them as modifiers - the scan skips a 0 and keeps looking, so
; CAPS held down does not read as a keypress of its own.
;
; The first key down wins. Press A while S is held and nothing comes back
; until S is released; a game that wants chords needs the matrix itself, not
; a character. For typing this is the behaviour you want - it is what stops a
; slow finger leaving the previous letter in the way of the next one.
;=============================================================================

ENTER               equ 13
DELETE              equ 12              ; CAPS SHIFT + 0, as in BASIC
BREAK               equ 27              ; CAPS SHIFT + SPACE - cancel/escape
CURSOR_LEFT         equ 8               ; CAPS SHIFT + 5..8
CURSOR_RIGHT        equ 9
CURSOR_DOWN         equ 10
CURSOR_UP           equ 11

;-----------------------------------------------------------------------------
; read_char - one character from anywhere on the keyboard.
; Entry: -
; Exit:  a = the character of a key that has just gone down, 0 if none.
;        modifiers holds the shift state of this read either way.
;        Corrupts b, c, d, e, h, l.
;
; SYMBOL SHIFT is reported in modifiers but changes nothing: a name needs
; letters, digits and a space, and the symbol layer is where the punctuation
; that would have to be filtered back out lives. To add it, give SYM its own
; branch beside the CAPS one below rather than a second table.
;-----------------------------------------------------------------------------
read_char:
                    ld c, 0                     ; c = the modifier flags
                    ld a, ROW_CSZXCV
                    in a, ($fe)
                    bit 0, a                    ; CAPS SHIFT
                    jr nz, .no_caps
                    set 0, c
.no_caps:
                    ld a, ROW_SPACE
                    in a, ($fe)
                    bit 1, a                    ; SYMBOL SHIFT
                    jr nz, .no_sym
                    set 1, c
.no_sym:
                    ld a, c
                    ld (modifiers), a

                    ld d, ROW_CSZXCV            ; rotates through all eight
                    ld e, 0                     ; index of this row's first key
                    ld b, 8
.row:
                    ld a, d
                    in a, ($fe)
                    cpl                         ; now 1 = pressed
                    and %00011111
                    jr z, .next_row

                    push bc                     ; b and c are wanted again
                    ld c, a                     ; c = this row's pressed keys
                    ld b, 5
                    ld a, e                     ; a = index into char_table
.bit:
                    srl c
                    jr c, .hit
.skip:
                    inc a
                    djnz .bit
                    pop bc
                    jr .next_row
.hit:
                    ld (found_key), a           ; the physical key, for the edge
                    ld hl, char_table
                    add a, l                    ; hl = char_table + a, without
                    ld l, a                     ; assuming the table sits clear
                    adc a, h                    ; of a page boundary
                    sub l
                    ld h, a
                    ld a, (hl)
                    and a
                    jr nz, .decode
                    ld a, (found_key)           ; a shift key - keep looking
                    jr .skip
.decode:
                    ld e, a                     ; e = the character
                    pop bc                      ; c = the modifier flags again
                    bit 0, c
                    jr z, .edge

                    ; CAPS SHIFT held. Letters are already uppercase, so the
                    ; only thing it changes is the number row, which becomes
                    ; the editing keys exactly as it does in BASIC - and those
                    ; are the ones a text field needs: delete, and the two
                    ; cursor keys to move along what has been typed.
                    ld a, e
                    cp ' '
                    jr nz, .caps_digit
                    ld e, BREAK
                    jr .edge
.caps_digit:
                    sub '0'
                    jr c, .edge
                    cp 10
                    jr nc, .edge
                    ld hl, caps_digits
                    add a, l
                    ld l, a
                    adc a, h
                    sub l
                    ld h, a
                    ld a, (hl)
                    and a
                    jr z, .edge                 ; that pair does nothing here
                    ld e, a
.edge:
                    ld a, (found_key)
                    ld hl, last_key
                    cp (hl)
                    jr z, .held
                    ld (hl), a
                    ld a, e
                    ret
.held:
                    xor a                       ; same key as last time - the
                    ret                         ; press has already been given out
.next_row:
                    ld a, e
                    add a, 5
                    ld e, a
                    rlc d
                    djnz .row

                    ; Nothing down anywhere. $FF is not a key index, so the
                    ; next press - including the same key again - reads as new.
                    ld a, $ff
                    ld (last_key), a
                    xor a
                    ret

;-----------------------------------------------------------------------------
; wait_char - block until a key goes down, then return it in a.
; Reads the hardware in a tight loop, so unlike keyboard.wait_any_key it works
; with interrupts off and under IM2. Corrupts what read_char corrupts.
;-----------------------------------------------------------------------------
wait_char:
                    call read_char
                    and a
                    jr z, wait_char
                    ret

;-----------------------------------------------------------------------------
; flush - forget what is held, so the next press reads as new.
; Call before opening a text field, or the ENTER that opened it arrives in it.
;-----------------------------------------------------------------------------
flush:
                    ld a, $ff
                    ld (last_key), a
                    xor a
                    ld (pressed_digits), a
                    ld (down_digits), a
                    ld (up_digits), a
                    ret

; The shift state of the last read_char: bit 0 CAPS SHIFT, bit 1 SYMBOL SHIFT.
modifiers:          db 0

last_key:           db $ff              ; key index held at the last read_char
found_key:          db 0                ; scratch: the index being decoded

; The matrix, in half-row order $FE $FD $FB $F7 $EF $DF $BF $7F, five keys per
; row from bit 0 up. 0 marks the two shift keys.
char_table:
                    db 0, "ZXCV"                ; CAPS SHIFT
                    db "ASDFG"
                    db "QWERT"
                    db "12345"
                    db "09876"                  ; this row runs backwards
                    db "POIUY"
                    db ENTER, "LKJH"
                    db " ", 0, "MNB"            ; SPACE, SYMBOL SHIFT

; What CAPS SHIFT + a number key means, indexed by the digit. The four that
; are 0 are EDIT, CAPS LOCK, TRUE VIDEO, INV VIDEO and GRAPHICS - real keys in
; BASIC, nothing a name field can use, so they report as no keypress at all.
caps_digits:
                    db DELETE                   ; 0
                    db 0, 0, 0, 0               ; 1 2 3 4
                    db CURSOR_LEFT              ; 5
                    db CURSOR_DOWN              ; 6
                    db CURSOR_UP                ; 7
                    db CURSOR_RIGHT             ; 8
                    db 0                        ; 9

                    ENDMODULE
