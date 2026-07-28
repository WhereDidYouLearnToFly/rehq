;=============================================================================
; joystick_test - test bench for the Kempston reader in core/input.asm
;=============================================================================
; Open this file in zxide and press F5. Unlike input_test this one skips the
; scheme selection and installs the Kempston reader directly, since that is
; the only reader it is here to exercise.
;
; It shows three rows of eight blocks, one block per button, in this module's
; bit order:
;
;       FIRE  UP  DOWN  LEFT  RIGHT  FIRE2  FIRE3  START
;
;   HELD   lit while the button is down
;   DOWN   lit briefly when the button goes down   (edge)
;   UP     lit briefly when the button comes up    (edge)
;
; The last three exist only on an extended interface, the kind that takes a
; Mega Drive pad. There is nothing to enable for them: the port read is eight
; bits wide either way, and a classic interface leaves those lines at 0, which
; the reader's cpl turns into "released". On classic hardware the last three
; blocks should therefore sit dark and never move.
;
; Below the blocks is the unprocessed byte from port $1F, MSB first, under a
; legend naming the line each bit is expected to carry. That readout is the
; point of this bench: the blocks show the mapping this module *assumes*, so
; the raw bits are the only way to check what the hardware actually does.
;
; What to check:
;   - each of the five classic blocks lights alone, and LEFT really is left
;   - on an extended interface all eight respond; on a classic one the last
;     three stay dark no matter what is pressed
;   - the raw readout agrees with the blocks: port bits 0-4 map to the first
;     five blocks *reversed* (port bit 0 = RIGHT), and port bits 5, 6, 7 map
;     straight through to FIRE2, FIRE3, START
;   - with nothing plugged in the readout should sit still. Bits that flicker
;     on their own are a floating bus, and any block they drive will emit a
;     phantom edge on the DOWN and UP rows every frame
;
; A caveat on the mapping: port bits 5/6/7 are C/A/Start on the common
; interfaces, but that is a convention rather than a standard - some swap A
; and Start. If the last three blocks respond to the wrong buttons, the
; interface is wired differently, and the raw readout will show it.
;=============================================================================

                    device zxspectrum48

; The org has to come before the includes: without it the modules assemble
; from address 0, i.e. underneath the ROM, and SAVESNA only writes $4000-$FFFF
; - so every call into them would land in the ROM instead.
                    org $8000

                    include "../core/input.asm"

DISPLAY_ATTRS       equ 22528
OPEN_SCREEN         equ 5633
PRINT_STRING_DE     equ 8252

ATTR_ON             equ %01000100       ; bright, black paper, green ink -> solid green
ATTR_OFF            equ %00001000       ; blue paper, black ink -> dim
ATTR_PAPER          equ %00000111       ; black paper, white ink

; Eight blocks two cells wide on a three-column pitch: 5 + 8*3 = 29 columns,
; which fits, and leaves columns 0-4 for the row labels on the left.
BLOCK_COL           equ 5
ROW_LABELS          equ 7
ROW_HELD            equ 9
ROW_DOWN            equ 12
ROW_UP              equ 15
HOLD                equ 12              ; frames an edge stays visible

start:
                    di
                    ld sp, $7fff

                    ld a, 2                     ; upper screen, so RST $10 works
                    call OPEN_SCREEN

                    call clear_screen
                    ld de, txt_title
                    ld bc, txt_title_len
                    call PRINT_STRING_DE
                    ld de, txt_labels
                    ld bc, txt_labels_len
                    call PRINT_STRING_DE

                    call input.use_kempston
                    ei                          ; IM 1: ROM keeps FRAMES alive

main_loop:
                    halt
                    call input.check_input

                    ld a, (input.pressed_buttons)
                    ld c, ROW_HELD
                    call draw_mask

                    ld hl, down_latch
                    ld a, (input.down_buttons)
                    ld c, ROW_DOWN
                    call draw_latched

                    ld hl, up_latch
                    ld a, (input.up_buttons)
                    ld c, ROW_UP
                    call draw_latched

                    call show_raw
                    jr main_loop

;-----------------------------------------------------------------------------
; show_raw - dump port $1F into the readout string, MSB first.
;-----------------------------------------------------------------------------
show_raw:
                    in a, (input.KEMPSTON_PORT)
                    ld hl, raw_bits
                    ld b, 8
.bit:
                    rlca                        ; next bit down from the top
                    ld (hl), '0'
                    jr nc, .placed
                    ld (hl), '1'
.placed:
                    inc hl
                    inc hl                      ; skip the separating space
                    djnz .bit

                    ld de, txt_raw
                    ld bc, txt_raw_len
                    jp PRINT_STRING_DE

;-----------------------------------------------------------------------------
; draw_latched - hold an edge mask on screen for HOLD frames.
; Entry: a = this frame's edge mask, c = attribute row,
;        hl -> a 2-byte latch (mask, timer)
;-----------------------------------------------------------------------------
draw_latched:
                    and a
                    jr z, .no_event
                    ld (hl), a                  ; latch the mask
                    inc hl
                    ld (hl), HOLD               ; restart the timer
                    dec hl
.no_event:
                    inc hl
                    ld a, (hl)
                    and a
                    jr z, .expired
                    dec a                       ; timer still running
                    ld (hl), a
                    dec hl
                    ld a, (hl)
                    jr draw_mask
.expired:
                    xor a                       ; nothing to show
                    ; fall through

;-----------------------------------------------------------------------------
; draw_mask - paint eight 2-cell blocks from an 8-bit mask.
; Entry: a = mask (bit 0 = leftmost block), c = attribute row 0..23
; Corrupts a, b, c, d, e, h, l.
;-----------------------------------------------------------------------------
draw_mask:
                    ld e, a                     ; e = mask
                    ld h, 0
                    ld l, c
                    add hl, hl                  ; row * 32
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    add hl, hl
                    ld bc, DISPLAY_ATTRS + BLOCK_COL
                    add hl, bc

                    ld b, 8
.cell:
                    ld a, ATTR_OFF
                    srl e                       ; carry = this button's bit
                    jr nc, .off
                    ld a, ATTR_ON
.off:
                    ld (hl), a                  ; two cells wide...
                    inc hl
                    ld (hl), a
                    inc hl
                    inc hl                      ; ...then a one-cell gap
                    djnz .cell
                    ret

;-----------------------------------------------------------------------------
; clear_screen - blank pixels, uniform attributes.
;-----------------------------------------------------------------------------
clear_screen:
                    ld hl, 16384
                    ld de, 16385
                    ld bc, 6144 - 1
                    ld (hl), 0
                    ldir

                    ld hl, DISPLAY_ATTRS
                    ld de, DISPLAY_ATTRS + 1
                    ld bc, 768 - 1
                    ld (hl), ATTR_PAPER
                    ldir

                    xor a                       ; black border
                    out ($fe), a
                    ret

down_latch:         db 0, 0                     ; mask, timer
up_latch:           db 0, 0

; AT row,col control codes are embedded in the strings, so each block places
; itself and the printing above stays a single call.
txt_title:          db 22, 1, 5, "kempston joystick test"
txt_title_len       equ $ - txt_title

                    ; One 3-char field per block, so these sit over the columns
                    ; draw_mask paints: 5, 8, 11, 14, 17, 20, 23, 26.
txt_labels:         db 22, 4, 4, "F2/F3/ST need extended"
                    db 22, ROW_LABELS, BLOCK_COL, "FR UP DN LF RT F2 F3 ST"
                    db 22, ROW_HELD, 0, "HELD"
                    db 22, ROW_DOWN, 0, "DOWN"
                    db 22, ROW_UP,   0, "UP"
                    db 22, 18, 3, "port $1F  S A C B U D L R"
txt_labels_len      equ $ - txt_labels

txt_raw:            db 22, 19, 3, "raw       "
raw_bits:           db "0 0 0 0 0 0 0 0"
txt_raw_len         equ $ - txt_raw

                    savesna "joystick_test.sna", start
