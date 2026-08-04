;=============================================================================
; stack - the space the stack occupies, claimed so nothing else is put there
;=============================================================================
; The stack grows *downwards* from $7FFF, so the bytes it uses are the top of
; RAM5 - and nothing in the source says so. Without this block the memory plan
; sees free space all the way to $7FFF and will happily place an asset, or pack
; a module, into the room the stack is about to need.
;
; It runs from Stack to the end of slot 1 deliberately: nothing else can use
; the top of the bank more usefully, so the stack gets all of it and the
; question of "how much is enough" never has to be answered. The measured need
; is far smaller - an interrupt costs 24 bytes on top of the current depth -
; so what is really being bought here is room to be wrong in.
;
; This block emits nothing. `; zxide: size(1280)` reserves the space in the
; plan without a single byte reaching the snapshot or a tape, which is the
; difference between claiming space and padding it with DEFS.
;
; Pinned because it is not a placement decision: the stack is at the top of
; slot 1 because slot 1 is the bank that never pages. Put it in slot 3 and the
; first bank switch pulls it out from under you - SP still points at $FFxx, but
; that is different memory now, and every RET goes somewhere else.
;
; This is bookkeeping, not a guard rail. Nothing here stops the stack growing
; past Stack - it states where it is *meant* to live so that everything else
; keeps out. If you ever want a real check, write a known byte at Stack and
; test it now and then: an overflow becomes something you detect rather than
; something you debug.
;
; NOTE: appentry must actually point SP here -
;
;     ld hl, $7FFF
;     ld sp, hl
;
; or this block reserves space the stack is not using, while the stack lives
; wherever the snapshot happened to leave SP.
;=============================================================================

; zxide: pin, size(1280) stack, grows down from $7FFF to the end of slot 1
                    org Stack
                    MODULE stack
                    ENDMODULE
