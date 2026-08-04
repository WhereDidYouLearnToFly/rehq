;=============================================================================
; ay - raw access to the AY-3-8912 / YM2149 sound chip
;=============================================================================
; Placement:  no ORG. The including file decides where this lands.
; Depends on: nothing.
; Namespace:  MODULE ay - every label below is reached as ay.*
;
; The chip is addressed over two ports: the register number goes out on
; $FFFD and the data byte on $BFFD. Both are decoded on A15/A14 only, which
; is why the writes below load bc with the full port address and use the
; 16-bit out (c) form - out ($fd), a would put the accumulator on the high
; half of the bus instead, and the chip would see the wrong address.
;
; Reading back is the same select, then in a, (c) with $FFFD still on the
; bus. The chip drives the data lines, so what comes back is the register as
; the *chip* holds it, not a copy the player keeps in RAM. That makes read
; the one way to meter sound that a black-box player is producing.
;
; A plain 48K has no AY at all. The writes then go nowhere and the reads
; float, which on most hardware and emulators means $FF - so a meter built on
; read sits pegged at full rather than empty. Nothing here misbehaves, there
; is simply no sound: run anything that uses this module on a 128K.
;=============================================================================
                    org AY_OPS
                    MODULE ay

SELECT_PORT         equ $fffd           ; register select (write) / read back
DATA_PORT           equ $bffd           ; register data (write only)

; Register numbers, as the chip numbers them.
TONE_A              equ 0               ; and 1: 12-bit period, low byte first
TONE_B              equ 2               ; and 3
TONE_C              equ 4               ; and 5
NOISE               equ 6               ; 5-bit period
MIXER               equ 7               ; active low, see MIX_* below
AMPL_A              equ 8               ; bits 0-3 level, bit 4 = use envelope
AMPL_B              equ 9
AMPL_C              equ 10
ENV_PERIOD          equ 11              ; and 12
ENV_SHAPE           equ 13              ; writing it restarts the envelope

; Mixer bits. A set bit *disables* that source, so MIX_SILENT is all ones.
MIX_TONE_A          equ %00000001
MIX_TONE_B          equ %00000010
MIX_TONE_C          equ %00000100
MIX_NOISE_A         equ %00001000
MIX_NOISE_B         equ %00010000
MIX_NOISE_C         equ %00100000
MIX_SILENT          equ %00111111

AMPL_ENVELOPE       equ %00010000       ; in an amplitude register: follow env
AMPL_LEVEL          equ %00001111       ; ...otherwise this is the fixed level

;-----------------------------------------------------------------------------
; write - set one register.
; Entry: a = register number, e = value.
; Exit:  corrupts b and c.
;-----------------------------------------------------------------------------
write:
                    ld bc, SELECT_PORT
                    out (c), a
                    ld b, DATA_PORT >> 8
                    out (c), e
                    ret

;-----------------------------------------------------------------------------
; read - read one register back off the chip.
; Entry: a = register number.
; Exit:  a = value. Corrupts b and c.
;-----------------------------------------------------------------------------
read:
                    ld bc, SELECT_PORT
                    out (c), a
                    in a, (c)
                    ret

;-----------------------------------------------------------------------------
; mute - silence the chip: every amplitude to zero, every mixer line off.
;
; Both halves matter. Amplitude alone leaves the tone generators running, so
; a player that only touches the mixer afterwards can bring the sound back
; without meaning to; the mixer alone leaves the envelope free to drive a
; channel. Entry: -. Exit: corrupts a, b, c, e.
;-----------------------------------------------------------------------------
mute:
                    ld e, 0
                    ld a, AMPL_A
                    call write
                    ld e, 0
                    ld a, AMPL_B
                    call write
                    ld e, 0
                    ld a, AMPL_C
                    call write
                    ld e, MIX_SILENT
                    ld a, MIXER
                    jp write

                    ENDMODULE
