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

; SELECT_RAM_BANK - page RAM bank `mbank` in at $C000.
;
; $7FFD is write-only, so the only record of what is paged is the ROM's copy in
; BANK_SELECTOR: read it, change the bits you want, write both. Get that wrong
; and the next ROM routine to page memory takes your bank away.
;
; The ROM bit is forced rather than carried over. Every ROM address in
; sys/zxspectrum.i is a 48K BASIC ROM address - RST $10, the print routines,
; the tape routines - so this game only ever wants ROM 1, and a shadow copy
; that has not been initialised would otherwise page in the 128K editor
; underneath every one of them. That is a silent failure: the machine keeps
; running and printing stops working. Forcing the bit costs nothing and makes
; it impossible.
    MACRO SELECT_RAM_BANK mbank
        ASSERT mbank >= 0 && mbank <= 7
        di                             ; the read must be inside the section too
        ld      a,(BANK_SELECTOR)
        and     $08                    ; keep the screen choice; drop bank,
        or      $10 | mbank            ; lock, and whatever the ROM bit was
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
