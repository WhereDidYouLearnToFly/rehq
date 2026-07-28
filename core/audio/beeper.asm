        org Beeper

enable:
        ld hl, beeper.click_beep
        ld (hl), 0
        ret

disable:
        ld hl, beeper.click_beep
        ld (hl), $c9
        ret

long_beep:
        ld hl, $400
        ld de, $30
        ld (tone), hl
        ld (length), de
        jp beep

beeper.click_beep:
        ret; nop
        ld hl, $5
        ld de, $2
        ld (tone), hl
        ld (length), de
beep:
        push hl
        push de
        push af
        push ix
        ld   hl, (tone)
        ld   de, (length)
        call BEEPER_ROUTINE_HL_DE
        ld a, 0
        out (254), a
        pop ix
        pop af
        pop de
        pop hl
        ret

tone:   dw $5
length: dw $2

