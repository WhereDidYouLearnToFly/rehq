;=============================================================================
; math - multiply and RNG
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: nothing.
; Namespace:  MODULE math - every label below is reached as math.*
;=============================================================================

                    MODULE math

;-----------------------------------------------------------------------------
; Multiply.HxD.HL - 8x8 -> 16 unsigned multiply.
; Entry: h, d = the two multiplicands
; Exit:  hl = h * d
; Corrupts a, b, d, e.
;-----------------------------------------------------------------------------
Multiply.HxD.HL:
                    ld e, d         ; hl = h * d
                    ld a, h         ; make accumulator first multiplier
                    ld hl, 0        ; zeroise total
                    ld d, h         ; zeroise high byte so de = multiplier
                    ld b, 8         ; repeat 8 times
.imul1:
                    rra             ; rotate rightmost bit into carry
                    jr nc, .imul2   ; wasn't set
                    add hl, de      ; bit was set, so add de
                    and a           ; reset carry
.imul2:
                    rl e            ; shift de 1 bit left
                    rl d
                    djnz .imul1     ; repeat 8 times
                    ret

;-----------------------------------------------------------------------------
; RandomToA - generate a random number.
; Exit: a = answer, 0 <= a <= 255
; Corrupts a, hl, de.
;-----------------------------------------------------------------------------
RandomToA:
                    push hl
                    push de
                    ld hl, (RANDOM_DATA)
                    ld a, r
                    ld d, a
                    ld e, (hl)
                    add hl, de
                    add a, l
                    xor h
                    ld (RANDOM_DATA), hl
                    pop de
                    pop hl
                    ret

;-----------------------------------------------------------------------------
; InitRandom - seed RANDOM_DATA from the ROM's frame counter.
; Corrupts a, hl.
;-----------------------------------------------------------------------------
InitRandom:
                    ld hl, ($5c78)  ; low 2 bytes of the 3-byte FRAMES counter
                    ld (RANDOM_DATA), hl
                    ret

BYTE_TEMP0:         db 0
BYTE_TEMP1:         db 0
WORD_TEMP0:         dw 0
RANDOM_DATA:        dw 0

                    ENDMODULE
