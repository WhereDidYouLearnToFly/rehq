        org Math
        MODULE math
imul:
        ld e,d          ; HL = H * D
        ld a,h          ; make accumulator first multiplier.
        ld hl,0         ; zeroise total.
        ld d,h          ; zeroise high byte so de=multiplier.
        ld b,8          ; repeat 8 times.
.imul1: 
        rra             ; rotate rightmost bit into carry.
        jr nc,.imul2     ; wasn't set.
        add hl,de       ; bit was set, so add de.
        and a           ; reset carry.
.imul2:  
        rl e            ; shift de 1 bit left.
        rl d
        djnz .imul1      ; repeat 8 times.
        ret

;-----> Generate a random number
; output a=answer 0<=a<=255
math.random_to_a:
        push    hl
        push    de
        ld      hl,(RANDOM_DATA)
        ld      a,r
        ld      d,a
        ld      e,(hl)
        add     hl,de
        add     a,l
        xor     h
        ld      (RANDOM_DATA),hl
        pop     de
        pop     hl
        ret

math.init_random:
        ld a, ($5c78)
        ld (RANDOM_DATA), a
        ret

BYTE_TEMP0:     db $0
BYTE_TEMP1:     db $0

WORD_TEMP0:     dw $0
WORD_TEMP2:     dw $0
WORD_TEMP3:     dw $0
RANDOM_DATA:    dw 0

        ENDMODULE
