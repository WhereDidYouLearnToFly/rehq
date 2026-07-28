;=============================================================================
; input_test - visual test bench for core/input.asm
;=============================================================================
; Open this file in zxide and press F5.
;
; It shows three rows of five blocks, one block per button, in the order
;
;       FIRE  UP  DOWN  LEFT  RIGHT
;
;   HELD   lit while the button is down
;   DOWN   lit briefly when the button goes down   (edge)
;   UP     lit briefly when the button comes up    (edge)
;
; The two edge rows latch for HOLD frames, otherwise a one-frame event would
; be invisible. If an edge row ever stays lit, or lights without the matching
; HELD block moving, the edge logic is wrong.
;
; On start it waits for a scheme: press 0 for Interface 2, SPACE for QAOP, or
; a Kempston fire button. What it prints afterwards is what got installed - so
; this also tests that control_selection picks the right reader.
;
; Expected quirk: the key that picks a scheme is also that scheme's fire
; button (0 for Interface 2, SPACE for QAOP), so FIRE reads as held the moment
; you choose, until you let go. That is the hardware, not a bug.
;
; What to check, per button, in every scheme:
;   - the right block lights (LEFT really is left)
;   - nothing else lights with it
;   - no block flickers on its own when nothing is touched (floating bus)
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

BLOCK_COL           equ 6               ; first attribute column of the blocks
ROW_HELD            equ 8
ROW_DOWN            equ 12
ROW_UP              equ 16
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

                    ei                          ; IM 1: ROM keeps LAST K and FRAMES alive

;-----------------------------------------------------------------------------
; Phase 1 - let the player choose a scheme.
;-----------------------------------------------------------------------------
                    ld de, txt_choose
                    ld bc, txt_choose_len
                    call PRINT_STRING_DE
.wait:
                    halt
                    call input.check_input
                    ld a, (input.control_selected)
                    and a
                    jr z, .wait

;-----------------------------------------------------------------------------
; Report which reader control_selection actually installed.
;-----------------------------------------------------------------------------
                    call clear_screen
                    ld de, txt_title
                    ld bc, txt_title_len
                    call PRINT_STRING_DE

                    ; hl_eq_bc leaves hl alone and ld de,nn leaves the flags
                    ; alone, so the name can be loaded between the test and
                    ; the branch that acts on it.
                    ld hl, (input.selected_controls)
                    ld bc, input.check_interface2
                    call hl_eq_bc
                    ld de, txt_interface2
                    jr z, .named
                    ld bc, input.check_qaop_space
                    call hl_eq_bc
                    ld de, txt_qaop
                    jr z, .named
                    ld de, txt_kempston
.named:
                    ld bc, SCHEME_LEN
                    call PRINT_STRING_DE

                    ld de, txt_labels
                    ld bc, txt_labels_len
                    call PRINT_STRING_DE

;-----------------------------------------------------------------------------
; Phase 2 - the live display.
;-----------------------------------------------------------------------------
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

                    jr main_loop

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
; draw_mask - paint five 2-cell blocks from a 5-bit mask.
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

                    ld b, 5
.cell:
                    ld a, ATTR_OFF
                    srl e                       ; carry = this button's bit
                    jr nc, .off
                    ld a, ATTR_ON
.off:
                    ld (hl), a                  ; three cells wide...
                    inc hl
                    ld (hl), a
                    inc hl
                    ld (hl), a
                    inc hl
                    inc hl                      ; ...then a two-cell gap,
                    inc hl                      ; so blocks sit 5 columns apart
                    djnz .cell
                    ret

;-----------------------------------------------------------------------------
; hl_eq_bc - compare hl with bc without disturbing either. Z if equal.
;-----------------------------------------------------------------------------
hl_eq_bc:
                    ld a, h
                    cp b
                    ret nz
                    ld a, l
                    cp c
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
txt_title:          db 22, 1, 8, "input.asm test bench"
txt_title_len       equ $ - txt_title

txt_choose:         db 22, 4, 4, "Choose: 0 = Interface 2"
                    db 22, 5, 4, "        SPACE = QAOP"
                    db 22, 6, 4, "        or Kempston fire"
txt_choose_len      equ $ - txt_choose

; All three scheme names are padded to the same length so one length constant
; covers them.
txt_interface2:     db 22, 4, 4, "scheme: INTERFACE 2 "
SCHEME_LEN          equ $ - txt_interface2
txt_qaop:           db 22, 4, 4, "scheme: QAOP + SPACE"
txt_kempston:       db 22, 4, 4, "scheme: KEMPSTON    "

                    ; One 5-char field per block, so these sit over the
                    ; columns draw_mask paints: 6, 11, 16, 21, 26.
txt_labels:         db 22, 6, BLOCK_COL, "FIRE UP   DOWN LEFT RGHT"
                    db 22, ROW_HELD, 0, "HELD"
                    db 22, ROW_DOWN, 0, "DOWN"
                    db 22, ROW_UP,   0, "UP"
txt_labels_len      equ $ - txt_labels

                    savesna "input_test.sna", start
