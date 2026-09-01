;=============================================================================
; card_text - fetching a card's rules text out of the bank it lives in
;=============================================================================
; Placement:  org $6FA0, in page 5. That is not a preference, and it is the
;             same reason game/audio.asm is there: this module pages slot 3
;             out from under its caller. A scene lives in slot 3, so a scene
;             cannot do this for itself - the instant the bank changed, the
;             code doing the changing would be gone.
; Depends on: data/card_data.asm for the text, and nothing else.
; Namespace:  MODULE card_text - reached as card_text.*
;
; One entry point:
;
;   card_text.get   HL = a DESCR_STR out of a Card or a Spell.
;                   Returns HL = a copy of that description in page 5, which
;                   is readable with the bank gone. Carry set if there was
;                   one, clear if DESCR_STR was 0 and there is nothing to
;                   show - the buffer is left holding a count of zero either
;                   way, so a caller that ignores the flag draws nothing
;                   rather than garbage.
;
; Call it with interrupts ON, from a scene's loop. Never from an interrupt
; handler, and never with the music bank already borrowed: both would leave
; slot 3 showing the wrong bank when this one puts back what it thinks was
; there. The port is write-only, so BANK_SELECTOR is the only record.
;
;-----------------------------------------------------------------------------
; Why it copies instead of handing back a pointer
;-----------------------------------------------------------------------------
; The obvious version pages the bank in, returns the address, and lets the
; caller print from it. That cannot work here: the caller is a scene, the
; scene is in slot 3, and the scene would be gone for as long as it was
; reading. So the whole block comes out in one go - 320 bytes at the worst -
; and the bank goes straight back. Everything after the call is ordinary code
; reading ordinary memory.
;
; 320 bytes of page 5 for the largest description, against having to page a
; bank in and out around every single print_menu_string. It is not close.
;=============================================================================

                    SLOT 1
                    PAGE 5
                    org $6C37
                    MODULE card_text

TEXT_BANK           equ 4

                    ASSERT card_data.MAX_BLOCK <= 320

;-----------------------------------------------------------------------------
; get - HL = DESCR_STR, returns HL = buffer, carry set if there was any text.
; Corrupts A, BC, DE.
;-----------------------------------------------------------------------------
get:
                    ld a, h                     ; DESCR_STR 0 means the text
                    or l                        ; has not been transcribed
                    jr nz, .fetch

                    xor a
                    ld (buffer), a              ; a count of zero draws nothing
                    ld hl, buffer
                    ret                         ; and carry is clear

.fetch:
                    ld (source), hl
                    di
                    call bank_in

                    ld hl, (source)
                    ld de, buffer
                    ld a, (hl)                  ; the line count
                    ld (de), a
                    inc hl
                    inc de
                    ld b, a
                    or a
                    jr z, .out

.line:
                    ld a, (hl)                  ; this line's length byte
                    ld (de), a
                    inc hl
                    inc de
                    or a
                    jr z, .next                 ; an empty line is legal

                    ld c, a
                    push bc
                    ld b, 0
                    ldir                        ; and the text after it
                    pop bc
.next:
                    djnz .line

.out:
                    call bank_out
                    ei
                    ld hl, buffer
                    scf
                    ret

;-----------------------------------------------------------------------------
; Borrowing slot 3. Both expect interrupts to be off already and leave them
; off; get owns that, because the borrow has to cover the copy in between.
; Lifted from game/audio.asm - see the note there for why the ROM bit is
; forced.
;-----------------------------------------------------------------------------
bank_in:
                    ld a, (BANK_SELECTOR)
                    ld (saved_bank), a
                    and $08                     ; keep the screen choice; drop
                    or $10 | TEXT_BANK          ; the bank and the lock, and
                    jr set_bank                 ; force the 48K ROM

bank_out:
                    ld a, (saved_bank)
                    or $10                      ; as above
set_bank:
                    ld bc, $7ffd
                    ld (BANK_SELECTOR), a
                    out (c), a
                    ret

source:             dw 0
saved_bank:         db 0

;-----------------------------------------------------------------------------
; The copy. A line count, then that many MenuStrings - the same shape it has
; in the bank, so print_menu_string reads it unchanged.
;-----------------------------------------------------------------------------
buffer:             ds card_data.MAX_BLOCK

                    ENDMODULE
