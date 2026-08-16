;=============================================================================
; music - one front end for the two kinds of AY music this project plays
;=============================================================================
; Placement:  no ORG. The including file decides where this lands. Must be in
; RAM, twice over: it includes ptsplay, which self-modifies, and play_ay
; patches the two call instructions further down this file.
; Depends on: ay (mute), and ptsplay, which this file includes itself - the
; wrapper is meaningless without it, so nothing else has to know it exists.
; Namespace:  MODULE music - every label below is reached as music.*
;
; Two kinds, because the music in this project arrives two ways:
;
;   Tracker modules   .pt2 / .pt3 files, pure data. play_pt2 / play_pt3 hand
;                     them to the ptsplay player, which is compiled in once
;                     and reused for every module.
;
;   Driver blocks     a lump of Z80 code with the tune baked into it and its
;                     own player inside, the way a game's music bank or an
;                     .ay file's memory block is built. There is nothing to
;                     parse: play_ay calls the block's own init and then its
;                     own per-frame routine. It has to be assembled at the
;                     address it was written for.
;
; Both end up looking the same from outside: play something, then call frame
; once per frame, and stop when done.
;
;   music.play_pt2   hl = module address
;   music.play_pt3   hl = module address
;   music.play_ay    hl = driver descriptor (see the DRIVER struct below)
;   music.frame      advance one frame - call at 50Hz and nowhere else
;   music.frame_raw  same, for callers already inside an interrupt
;   music.stop       silence and forget
;   music.playing    0 when nothing is playing, otherwise non-zero
;
; Two notes on frame, both of which are about the ROM rather than the chip:
;
; The player sets IY, and the 48K ROM interrupt handler assumes IY points at
; the system variables ($5C3A). If an interrupt lands between the player
; setting IY and anything putting it back, the ROM writes its frame counter
; and keyboard state through a stale pointer, which corrupts whatever IY
; happened to be aimed at. So frame runs with interrupts off and restores IY
; before letting them back in.
;
; That also means frame ends with ei, whether or not interrupts were on when
; it was called. Called from a main loop - the usual case, halt then frame -
; that is exactly right. Called from inside an interrupt handler it is not:
; use frame_raw there, which does neither, because the handler in
; core/interrupt.asm already sets IY before chaining to the ROM.
;=============================================================================
                    SLOT 2
                    PAGE 2
                    org $918D
                    MODULE music

SYSVARS             equ $5c3a           ; what the ROM ISR expects in IY

; Descriptor for play_ay. Four words, laid out in the order an .ay file's
; song structure gives them, so a file's fields can be copied straight in.
                    STRUCT DRIVER
init                dw 0                ; call once to select and set up a tune
play                dw 0                ; call once per frame afterwards
stack               dw 0                ; SP the block wants; 0 means the top
                                        ; of RAM, since the first push wraps
regs                dw 0                ; preset registers: a = high byte
                    ENDS

;-----------------------------------------------------------------------------
; play_pt2 / play_pt3 - start a tracker module.
; Entry: hl = module address.
; Exit:  corrupts everything except the alternate set. Interrupts are on.
;
; The format cannot be told from the data alone here - ptsplay is told which
; one it is being given, and getting that wrong produces noise rather than an
; error. The PT3 path asks for TurboSound autodetection as well, which is
; what a plain PT3 module wants: it costs nothing on a single-chip module and
; picks up the two-module TS variant if one turns up.
;-----------------------------------------------------------------------------
play_pt2:
                    ld a, PTS.SETUP.PT2         ; a carries the format down to
                    jr start_module             ; the shared path below

play_pt3:
                    ld a, PTS.SETUP.TSPT3       ; PT3, plus TS autodetect

start_module:
                    di                          ; PTS.INIT rewrites its own
                                                ; code; an interrupt that
                                                ; played music halfway through
                                                ; would run it half-patched
                    push af
                    push hl
                    call stop                   ; whatever was playing, incl.
                    pop hl                      ; a driver block, goes quiet
                    pop af                      ; before the chip changes hands

                    ld de, 0                    ; no second module: TS off
                    call PTS.INIT               ; hl = module, a = format

                    ld hl, pt_frame             ; from here on, frame runs the
                    ld (frame_vector), hl       ; tracker player
                    ld a, 1
                    ld (playing), a
                    ld iy, SYSVARS              ; PTS.INIT pointed it at its
                                                ; own variables
                    ei
                    ret

;-----------------------------------------------------------------------------
; play_ay - start a driver block.
; Entry: hl = DRIVER descriptor.
; Exit:  corrupts everything. Interrupts are on.
;
; The block runs on its own stack, not ours. That is not a nicety: a block
; lifted out of a game was written to run with SP wherever that game left it,
; and some push far deeper than a caller would expect. Swapping SP for the
; duration of each call keeps that away from our stack, and costs two
; instructions per frame.
;
; The registers are preloaded from descriptor.regs before init, because that
; is how these blocks are told which tune to play - there is no argument
; convention beyond "the registers hold a number". The .ay format writes it
; as two bytes, a high and a low, and fills every register pair with them; in
; practice the block reads a, so that is what this sets, along with the pairs
; a block is most likely to look at instead.
;
; The two addresses out of the descriptor are written into the operands of
; the call instructions rather than kept in a register pair and reached
; through an indirect jump. A call has to leave a return address behind, so
; the alternatives are all worse: push a fake return address by hand, or
; build a call out of a jp and a pushed address. Patching the operand is two
; bytes and keeps both call sites a plain call - at the price of this module
; having to be in RAM, which ptsplay already required.
;-----------------------------------------------------------------------------
play_ay:
                    di                          ; the stack swap below must
                                                ; not be interrupted, and stop
                                                ; leaves the state alone
                    push hl
                    call stop                   ; corrupts hl, hence the push
                    pop hl

                    ; Unpack the descriptor. The fields are read in the order
                    ; the DRIVER struct declares them, so hl just walks
                    ; forward: init, play, stack, regs.
                    ld e, (hl)                  ; init ->
                    inc hl
                    ld d, (hl)
                    inc hl
                    ld (call_init + 1), de      ; ...the operand of call_init
                    ld e, (hl)                  ; play ->
                    inc hl
                    ld d, (hl)
                    inc hl
                    ld (call_play + 1), de      ; ...the operand of call_play,
                                                ; which every frame then uses
                    ld e, (hl)                  ; stack -> kept, because
                    inc hl                      ; ay_frame needs it again on
                    ld d, (hl)                  ; every later call
                    inc hl
                    ld (driver_sp), de
                    ld e, (hl)                  ; regs -> straight into the
                    inc hl                      ; registers below
                    ld d, (hl)

                    push de                     ; preset ix and iy from the
                    pop ix                      ; same value, the way an .ay
                    push de                     ; player would. Done before
                    pop iy                      ; the stack swap, so these
                    ld b, d                     ; pushes stay on our stack and
                    ld c, e                     ; not in the block's
                    ld h, d
                    ld l, e
                    ld a, d                     ; a = the high byte, which is
                                                ; what a block usually reads

                    ; Hand the block its own stack. Both of these address
                    ; memory directly and touch no register, which is the
                    ; reason the presets above survive the swap intact.
                    ld (host_sp), sp
                    ld sp, (driver_sp)
call_init:          call 0                      ; operand patched above
                    ld sp, (host_sp)            ; back on ours before anything
                                                ; else pushes

                    ld hl, ay_frame             ; from here on, frame runs the
                    ld (frame_vector), hl       ; block rather than ptsplay
                    ld a, 1
                    ld (playing), a
                    ld iy, SYSVARS              ; the block had it as a preset
                    ei
                    ret

;-----------------------------------------------------------------------------
; stop - silence the chip and detach whatever was playing.
; Entry: -. Exit: corrupts a, b, c, d, e, h, l. Interrupt state unchanged.
;
; Both players get silenced, not just the active one: ptsplay keeps its own
; idea of the AY registers and will write them again on any later PLAY, while
; a driver block leaves the chip however it liked. MUTE first so ptsplay's
; copy is zeroed, then ay.mute so the chip itself is quiet even if the last
; thing to touch it was a driver block.
;-----------------------------------------------------------------------------
stop:
                    xor a
                    ld (playing), a
                    ld hl, silence              ; frame becomes a no-op, so a
                    ld (frame_vector), hl       ; caller can keep calling it
                    call PTS.MUTE
                    jp ay.mute                  ; tail call: ay.mute's ret is
                                                ; this routine's

;-----------------------------------------------------------------------------
; frame - advance the music by one frame. Call once per 50Hz frame.
; Entry: -. Exit: corrupts everything except the alternate set. Interrupts on.
; See the header for why this ends with ei; use frame_raw from an ISR.
;-----------------------------------------------------------------------------
frame:
                    di
                    call frame_raw
                    ld iy, SYSVARS              ; before the first interrupt
                    ei                          ; can reach the ROM handler
                    ret

;-----------------------------------------------------------------------------
; frame_raw - the same, without touching interrupts or IY.
;
; jp (hl) rather than a call: the return address the caller pushed is still
; on the stack, so whichever routine this lands on returns straight to them.
;-----------------------------------------------------------------------------
frame_raw:
                    ld hl, (frame_vector)
                    jp (hl)

;-----------------------------------------------------------------------------
; The three things frame_vector can point at: nothing playing, a tracker
; module, or a driver block. Selected once when playback starts, so the
; per-frame path costs one indirect jump and no tests.
;-----------------------------------------------------------------------------
silence:
                    ret

pt_frame:
                    jp PTS.PLAY

; The block's own per-frame routine, run on the block's own stack for the
; same reason play_ay's init call is - see the note there. The two SP
; instructions read and write memory only, so the block is entered with
; whatever registers frame_raw left, which is what a driver called from an
; interrupt handler would expect.
ay_frame:
                    ld (host_sp), sp
                    ld sp, (driver_sp)
call_play:          call 0                      ; operand patched by play_ay
                    ld sp, (host_sp)
                    ret

frame_vector:       dw silence                  ; one of the three above
playing:            db 0                        ; for callers, not used here
host_sp:            dw 0                        ; our SP, parked for the
                                                ; duration of a block's call
driver_sp:          dw 0                        ; the SP the block asked for

                    ENDMODULE
