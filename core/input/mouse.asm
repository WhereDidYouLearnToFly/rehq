;=============================================================================
; mouse - Kempston Mouse: cursor position and button edge detection
;=============================================================================
; Depends on: nothing.
; Namespace:  MODULE mouse - every label below is reached as mouse.*
;
; Call mouse.init once at startup, then mouse.read once per frame (typically
; from the interrupt handler, same as input.check_input). After that:
;
;   mouse.x, mouse.y        cursor position in pixels, clamped to the screen -
;                            0..255, 0..191 - ready for display.draw_8x8's b/c.
;                            Note that draw_8x8 is a byte blitter: it rounds x
;                            down to a character column, so a sprite drawn
;                            straight from these snaps to 8-pixel steps
;                            horizontally while moving 1 pixel at a time
;                            vertically. x itself is exact; a smooth cursor
;                            needs 8 pre-shifted frames selected on x AND 7.
;   mouse.pressed_buttons   held down right now
;   mouse.down_buttons      went down since the last call   (edge)
;   mouse.up_buttons        came up since the last call     (edge)
;
; The three ports ($FADF/$FBDF/$FFDF) decode all 16 address lines, so they
; must be read with `in a,(c)` from a full bc, never `in a,(n)` - that form
; only guarantees the low 8 bits of the address and leaves the top 8 as
; whatever A already held, which happens to work sometimes and silently
; doesn't others.
;
; X/Y are NOT an absolute position. The interface holds two free-running
; 8-bit counters that wrap every 256 counts of physical movement; reading
; one only tells you where it is now, not how far it has moved since last
; time. mouse.read subtracts the previous raw reading from the new one (as a
; signed byte - the wraparound cancels out) and adds that delta to x/y here,
; clamping at the screen edges. Skipping this and using the raw port value
; directly is the standard mistake - the cursor jumps to the wrapped counter
; value instead of tracking motion.
;
; The Y counter also runs the opposite way to the screen: it increments as the
; mouse moves away from the user, while screen y increases downwards. read
; negates the y delta so mouse.y is already in screen space and callers never
; have to think about it.
;=============================================================================
                    org $5F8A
                    MODULE mouse

BUTTONS_PORT        equ $fadf
X_PORT              equ $fbdf
Y_PORT              equ $ffdf

; Hardware bit order, kept as-is rather than remapped to a chosen layout -
; input.asm's Interface 2 LEFT/RIGHT remap is exactly the kind of bug that
; kind of shuffling invites, and there is no benefit to it here.
BUTTON_RIGHT        equ %00000001
BUTTON_LEFT         equ %00000010
BUTTON_MIDDLE       equ %00000100

MAX_X               equ 255
MAX_Y               equ 191

;-----------------------------------------------------------------------------
; init - centre the cursor and sync to the interface's free-running counters.
; Call once before the first read, so that read's first delta is against
; where the mouse actually is rather than raw_x/raw_y's zeroed default.
;-----------------------------------------------------------------------------
init:
                    ld bc, X_PORT
                    in a, (c)
                    ld (raw_x), a
                    ld bc, Y_PORT
                    in a, (c)
                    ld (raw_y), a
                    ld a, MAX_X / 2
                    ld (x), a
                    ld a, MAX_Y / 2
                    ld (y), a
                    xor a
                    ld (pressed_buttons), a
                    ld (down_buttons), a
                    ld (up_buttons), a
                    ret

;-----------------------------------------------------------------------------
; read - poll the interface once. Updates x, y and all three button masks.
; Exit:  a = pressed_buttons. Corrupts everything.
;-----------------------------------------------------------------------------
read:
                    ld bc, X_PORT
                    in a, (c)                   ; a = new raw x
                    ld hl, raw_x
                    ld d, (hl)                  ; d = old raw x
                    ld (hl), a                  ; store new raw x
                    sub d                       ; a = signed delta x
                    ld hl, x
                    ld c, MAX_X
                    call move_axis

                    ld bc, Y_PORT
                    in a, (c)
                    ld hl, raw_y
                    ld d, (hl)
                    ld (hl), a
                    sub d                       ; a = signed delta y, counting up
                    neg                         ; ...but the interface counts up
                                                ; as the mouse moves away from the
                                                ; user, and screen y grows down
                    ld hl, y
                    ld c, MAX_Y
                    call move_axis

                    ld bc, BUTTONS_PORT
                    in a, (c)
                    cpl                         ; active LOW -> 1 = pressed
                    and %00000111
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
; read_buttons - the mouse as an input scheme, for input.check_input to install.
;
; Only the left button, and only onto FIRE. A mouse has no directions to give:
; it reports *motion*, and turning that into UP/DOWN/LEFT/RIGHT means choosing a
; threshold and a feel, which is a game decision and not a driver one. The four
; direction bits are therefore left released, and anything that wants the
; pointer reads mouse.x/mouse.y after mouse.read - a separate call, because this
; one deliberately does no delta tracking.
;
; Note the hardware bit order: LEFT is bit 1, not bit 0 (see BUTTON_LEFT above).
; FIRE is bit 0, so the byte is rotated rather than passed through. To put the
; other two buttons on FIRE2/FIRE3, keep bits 0-2 here and shift them up.
;
; Entry: -
; Exit:  via input.update_state, so a = input.pressed_buttons. Corrupts b, c, d.
;-----------------------------------------------------------------------------
read_buttons:
                    ld bc, BUTTONS_PORT
                    in a, (c)
                    or ~BUTTON_LEFT & $ff       ; release everything but LEFT...
                    rrca                        ; ...and drop it into FIRE (bit 0)
                    jp input.update_state

;-----------------------------------------------------------------------------
; read_scheme - the whole mouse for one frame. This is what input installs when
; the player picks the mouse, so a single input.check_input keeps both the
; pointer and the shared button masks up to date and nothing has to remember to
; poll the mouse separately.
;
; `read` is left alone rather than folded in here: it is also useful on its own,
; for a game that wants a cursor while the player steers with the keyboard.
;-----------------------------------------------------------------------------
read_scheme:
                    call read                   ; x/y, and the mouse's own masks
                    ; A conversion, not a second port read: `read` leaves the
                    ; buttons in pressed_buttons, in this module's bit order.
                    ld a, (pressed_buttons)     ; 1 = pressed, LEFT on bit 1
                    rrca                        ; LEFT -> bit 0, where FIRE is
                    cpl                         ; and back to 0 = pressed, which
                    or ~input.FIRE & $ff        ; is what update_state expects
                    jp input.update_state

;-----------------------------------------------------------------------------
; in_use - non-zero once the player has chosen the mouse, which is the only
; reliable way to know one is fitted: an idle mouse and an absent one read the
; same, so a click is the proof. The game tests this to decide whether to draw
; a cursor and whether the pointer means anything.
;-----------------------------------------------------------------------------
in_use:             db 0

;-----------------------------------------------------------------------------
; move_axis - apply a signed delta to one axis variable, clamped to 0..max.
; Entry: a = signed delta, hl = axis variable address, c = max value
; Exit:  (hl) updated. Corrupts a, b.
;-----------------------------------------------------------------------------
move_axis:
                    bit 7, a
                    jr nz, .negative

                    add a, (hl)
                    jr c, .clamp_max            ; overflowed the byte
                    cp c
                    jr z, .store                ; == max, fine
                    jr c, .store                ; < max, fine
.clamp_max:
                    ld a, c
                    jr .store

.negative:
                    neg
                    ld b, a
                    ld a, (hl)
                    sub b
                    jr nc, .store               ; didn't underflow
                    xor a
.store:
                    ld (hl), a
                    ret

raw_x:              db 0
raw_y:              db 0
x:                  db 0
y:                  db 0
pressed_buttons:    db 0
down_buttons:       db 0
up_buttons:         db 0

                    ENDMODULE
