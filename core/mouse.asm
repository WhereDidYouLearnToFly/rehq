;=============================================================================
; mouse - Kempston Mouse: cursor position and button edge detection
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
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
