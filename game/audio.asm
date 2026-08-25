;=============================================================================
; audio - the game's music policy, and the bank the music lives in
;=============================================================================
; Placement:  org Audio, in page 5. That is not a preference: page 5 is always
;             mapped, and this module pages slot 3 out from under its caller.
;             A scene lives in slot 3, so a scene cannot do that for itself -
;             the moment the bank changed, the code doing the changing would
;             be gone. Calling out to here first is what makes it safe.
; Depends on: music.* for playback, data/music_data.asm for the block,
;             globals.settings for the player's MUSIC choice.
; Namespace:  MODULE audio - reached as audio.*
;
; Scenes call three things and know nothing else about sound:
;
;   audio.play_tune   a = a TUNE_* id. Starts it, or does nothing if it is
;                     already the one playing, or stays silent if the player
;                     has music switched off.
;   audio.frame       once per frame, from a scene's loop - never from the
;                     interrupt handler, for the reason in music.asm.
;   audio.stop        silence, and remember what was playing so resume can
;                     put it back.
;   audio.resume      start the remembered tune again, if music is on.
;
;-----------------------------------------------------------------------------
; Borrowing slot 3
;-----------------------------------------------------------------------------
; The AY block is 9K at $C000-$E303, which is where the menu's scenes live and
; where the quest's code will live. It cannot share with either, so it has a
; bank to itself and is paged in only while it is being called - a few hundred
; T-states, fifty times a second.
;
; Two things make that safe, and both are easy to get wrong:
;
; Nothing in slot 3 may be executed or read across the swap. From the moment
; the bank goes in until it comes out, the CPU is in page 5 (here), page 2
; (music.asm and the entry stubs) and the music bank itself. That is why this
; module is not in a scene.
;
; The frame handler must not run while the bank is borrowed. The scene's
; interrupt routine is in slot 3, so entering it with the music bank paged in
; would execute song data. Interrupts are off across the swap here, and
; `borrowed` covers the one case where they cannot be - music.play_ay ends
; with its own ei, and an interrupt can be accepted in the instruction after
; it. game.onInterrupt tests the flag and returns.
;-----------------------------------------------------------------------------
; What it costs
;-----------------------------------------------------------------------------
; Memory, and where:
;
;   page 2, always mapped    12 bytes    the block's two entry stubs, at
;                                        $BFF4-$BFFF (data/music_data.asm)
;   page 5, always mapped    this module
;   bank 6, borrowed         8964 bytes  $C000-$E303, the player and all
;                                        three tunes
;
; So the music costs the menu bank and the quest bank nothing at all, which
; is the whole point of the arrangement: neither has to give up 9K, and the
; same tune keeps playing across the switch from one to the other.
;
; $E304-$FFFF of bank 6 is free for anything that only has to be readable
; while the bank is in - with one exception. The .ay asks for SP = 0, so the
; block's first push wraps to $FFFE and its stack grows down from the top of
; the bank. Leave a few hundred bytes there.
;
; Time, per frame: the two bank switches are a read of BANK_SELECTOR, an
; and/or, a ld bc, a store and an out, twice - about 60 T-states out of the
; 70908 in a 128K frame, under a tenth of a percent. The player itself costs
; hundreds of times that and is not documented anywhere; switch PERF_BORDER
; on in game/game.asm and read the red band rather than guessing.
;
; Bank 6 rather than 1, 3 or 7: those three are contended on a 128K, and 7
; is also the shadow screen. 6 is uncontended and unused by anything here.
;
; 128K only. There is no AY in a plain 48K (ay.asm:19-22), so on one of those
; this is silent rather than broken.
;=============================================================================

                    SLOT 1
                    PAGE 5
                    org $688C
                    MODULE audio

MUSIC_BANK          equ 6

; The block's two entry points, from data/music_data.asm. Both are in page 2,
; so they can be named from anywhere; what they call is not.
AY_PLAY             equ $BFF4
AY_INIT             equ $BFFB

TUNE_NONE           equ 0
TUNE_MENU           equ 1
TUNE_GAME_1         equ 2
TUNE_GAME_2         equ 3

;-----------------------------------------------------------------------------
; The DRIVER descriptors music.play_ay reads: init, play, stack, regs.
;
; All three tunes are the same block and the same two entry points - only the
; register differs, which is how the .ay format asks a driver for a particular
; tune. stack 0 means "the top of RAM", which for this block is the top of the
; music bank; music.asm swaps SP for the duration of every call.
;-----------------------------------------------------------------------------
tune_menu:          dw AY_INIT, AY_PLAY, 0, $0200   ; Title
tune_game_1:        dw AY_INIT, AY_PLAY, 0, $0100   ; In-Game 01
tune_game_2:        dw AY_INIT, AY_PLAY, 0, $0300   ; In-Game 02

tunes:              dw 0, tune_menu, tune_game_1, tune_game_2   ; by TUNE_*

current:            db TUNE_NONE            ; what should be playing, whether
                                            ; or not it is - so a player who
                                            ; switches music back on gets the
                                            ; right tune rather than silence
saved_bank:         db 0
borrowed:           db 0                    ; read by game.onInterrupt

;-----------------------------------------------------------------------------
; play_tune - a = TUNE_*. Corrupts everything.
;-----------------------------------------------------------------------------
play_tune:
                    ld hl, current
                    cp (hl)
                    jr nz, .change
                    ld a, (music.playing)   ; already the right tune, and
                    and a                   ; still going: leave it alone, or
                    ret nz                  ; every scene entry restarts it
                    ld a, (hl)
.change:
                    ld (hl), a
                    ; falls through

;-----------------------------------------------------------------------------
; resume - start `current` again, or stay quiet if music is switched off.
;-----------------------------------------------------------------------------
resume:
                    ld a, (globals.settings)
                    and globals.MUSIC
                    jr z, stop              ; switched off: silence, but
                                            ; `current` is remembered
                    ld a, (current)
                    and a
                    jr z, stop
;
                    add a, a                ; index the tunes table
                    ld e, a
                    ld d, 0
                    ld hl, tunes
                    add hl, de
                    ld e, (hl)
                    inc hl
                    ld d, (hl)
                    ex de, hl               ; hl = the DRIVER descriptor
;
                    di
                    call bank_in
                    call music.play_ay      ; ends with an ei of its own, which
                    di                      ; is why borrowed exists
                    call bank_out
                    ld iy, music.SYSVARS
                    ei
                    ret

;-----------------------------------------------------------------------------
; stop - silence the chip. `current` is left alone so resume can undo this.
;-----------------------------------------------------------------------------
stop:
                    jp music.stop           ; the block is not called, so the
                                            ; bank is not needed

;-----------------------------------------------------------------------------
; frame - one frame of music. From a scene's loop, once per frame.
;
; frame_raw rather than frame: the interrupt and IY handling music.frame does
; for itself is done here instead, once, around the bank swap as well - so
; there is no moment where interrupts are on with the music bank paged in.
;-----------------------------------------------------------------------------
frame:
                    ld a, (music.playing)
                    and a
                    ret z
;
                    di
                    call bank_in
                    call music.frame_raw
                    call bank_out
                    ld iy, music.SYSVARS    ; frame_raw leaves it wherever the
                    ei                      ; block left it
                    ret

;-----------------------------------------------------------------------------
; bank_in / bank_out - borrow slot 3 and give it back.
;
; Both expect interrupts to be off already and leave them off; the caller owns
; that, because the borrow has to cover the call in between as well. The port
; is write-only, so BANK_SELECTOR is the only record of what was there.
;-----------------------------------------------------------------------------
bank_in:
                    ld a, 1
                    ld (borrowed), a
                    ld a, (BANK_SELECTOR)
                    ld (saved_bank), a
                    and $08                 ; keep the screen choice; drop the
                    or $10 | MUSIC_BANK     ; bank and the lock, and force the
                                            ; 48K ROM - see SELECT_RAM_BANK in
                                            ; core/macros/macros.asm for why
                    jr set_bank

bank_out:
                    ld a, (saved_bank)
                    or $10                  ; as above: whatever was recorded,
                                            ; the game wants the 48K ROM
                    ld hl, borrowed
                    ld (hl), 0
set_bank:
                    ld bc, $7ffd
                    ld (BANK_SELECTOR), a
                    out (c), a
                    ret

                    ENDMODULE
