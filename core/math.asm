;=============================================================================
; math - multiply and RNG
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: nothing.
; Namespace:  MODULE math - every label below is reached as math.*
;
; Call math.init_random once at startup before the first math.random_to_a,
; otherwise the seed stays zero and the generator walks the same stretch of
; ROM from the same place on every run.
;=============================================================================

                    MODULE math

;-----------------------------------------------------------------------------
; multiply_hd_to_hl - 8x8 -> 16 unsigned multiply.
; Entry: h, d = the two multiplicands
; Exit:  hl = h * d
; Corrupts a, b, d, e.
;-----------------------------------------------------------------------------
multiply_hd_to_hl:
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
; random_to_a - generate a random number.
; Exit: a = answer, 0 <= a <= 255
; Corrupts a only - hl and de are saved and restored.
;
; The state is a pointer that walks ROM, stirred by the refresh register, so
; the byte it lands on is part of the entropy. That means the sequence is not
; reproducible from the seed alone; don't use it where a replayable stream
; matters.
;-----------------------------------------------------------------------------
random_to_a:
                    push hl
                    push de
                    ld hl, (seed)
                    ld a, r
                    ld d, a
                    ld e, (hl)
                    add hl, de
                    add a, l
                    xor h
                    ld (seed), hl
                    pop de
                    pop hl
                    ret

;-----------------------------------------------------------------------------
; init_random - seed from the ROM's frame counter.
; Corrupts hl.
;-----------------------------------------------------------------------------
init_random:
                    ld hl, ($5c78)  ; low 2 bytes of the 3-byte FRAMES counter
                    ld (seed), hl
                    ret

seed:               dw 0

                    ENDMODULE
