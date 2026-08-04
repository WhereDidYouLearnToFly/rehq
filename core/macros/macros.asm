    MACRO INDIRECT_CALL paddr
        ld hl, $+14        ;3
        push hl            ;1
        ld hl, paddr       ;3
        ld a, h            ;1
        or l               ;1
        cp 0               ;2
        ret z              ;1
        push hl            ;1
        ret                ;1
    ENDM

    MACRO SELECT_RAM_BANK mbank
        ASSERT mbank >= 0 && mbank <= 7
        di                             ; the read must be inside the section too
        ld      a,(BANK_SELECTOR)
        and     $18                    ; keep screen + ROM; clear bank and lock
        or      mbank
        ld      bc,$7ffd
        ld      (BANK_SELECTOR),a
        out     (c),a
        ei
    ENDM

    MACRO SELECT_ROM_BANK mbank
        ld      a, (BANK_SELECTOR)      ;Previous value of port
        and     $ef
        IF (mbank==1)
            or $10
        ENDIF
        ld      bc, $7ffd
        di
        ld      (BANK_SELECTOR), a
        out     (c), a
        ei    
    ENDM

    MACRO DEBUG_BORDER color
    IFDEF DEBUG
        ld a, color
        out ($fe), a                   ; write to port 254.
    ENDIF
    ENDM
