;=============================================================================
; music_data - the HeroQuest AY block, cut out of the .ay file in two pieces
;=============================================================================
; Placement:  fixed, and not negotiable - see below. Both orgs are pinned so
;             the memory planner leaves them where they are.
; Depends on: nothing. game/audio.asm is what calls into it.
;
; bin/music/music.ay is an AY-file rip of the 1991 Gremlin music: a header,
; then one 8976-byte memory block that is Z80 code with its own player and all
; three tunes inside it. ingame0.ay and ingame1.ay are byte-for-byte the same
; file; there is one block, and the tune is chosen by the value handed to its
; init routine, not by which file you load.
;
;   register $02   Title        register $01 / $03   the two in-game tunes
;
; The block is code assembled for one address and cannot be moved: it runs at
; $BFF4-$E303. That is the whole reason this file exists in two halves, and
; the reason the music needs a bank of its own.
;
;   $BFF4-$BFFF   twelve bytes, the two entry stubs, in page 2. Page 2 is
;                 always mapped, so a caller can reach them whatever slot 3
;                 is showing:
;
;                     $BFF4  call $D496 / call $D513 / ret   <- play
;                     $BFFB  ld d,a / call $D3AA / ret       <- init
;
;   $C000-$E303   the other 8964 bytes - the player and all three tunes - in
;                 the music bank, paged into slot 3 only for the length of a
;                 call. See game/audio.asm for how that is done and why it is
;                 safe.
;
; The block's own stack lives at the top of the same bank: the .ay asks for
; SP = 0, so its first push wraps to $FFFE. Leave the top of the bank alone.
;=============================================================================

;-----------------------------------------------------------------------------
; Where the two offsets come from
;-----------------------------------------------------------------------------
; The .ay container is big-endian, and every pointer in it is a *signed 16-bit
; offset from the address of the pointer itself* rather than from the start of
; the file. That is the one thing to know before reading it by hand; get it
; wrong and every field looks like garbage.
;
;   byte  0-7    "ZXAYEMUL"
;   byte  8      file version        byte  9   required player version
;   byte 10-11   -> author           byte 12-13 -> misc, both NUL-terminated
;   byte 16      number of songs, minus one     byte 17  first song to play
;   byte 18-19   -> the song table, four bytes per song:
;                     +0 -> song name        +2 -> song data
;
;   song data:  +0  four channel-mapping bytes
;               +4  song length in frames     +6  fade length
;               +8  the two register bytes, high then low
;               +10 -> points     +12 -> block list
;
;   points:     stack, init, interrupt - three big-endian addresses
;   block list: address, length, -> data, repeated; a zero address ends it
;
; For this file that reads out as three songs, all pointing at one block:
;
;   song 0  "Hero Quest - Title (AY)"        registers $02 $00
;   song 1  "Hero Quest - In-Game 01 (AY)"   registers $01 $00
;   song 2  "Hero Quest - In-Game 02 (AY)"   registers $03 $00
;   all:    stack $0000  init $BFFB  interrupt $BFF4
;           block  $BFF4  length 8976  at file offset 232
;
; So 232 is where the block's bytes begin in the file, and 232 + 12 = 244 is
; where they continue after the twelve that belong in page 2. 12 + 8964 is the
; whole 8976, and the ASSERTs below are what will tell you if that ever stops
; adding up.
;-----------------------------------------------------------------------------

AY_FILE             equ 0                   ; documentation, not a value: the
                                            ; offsets below are into the file
                                            ; named in the INCBINs
AY_BLOCK_OFFSET     equ 232                 ; where the memory block starts
AY_STUB_LEN         equ 12                  ; the part that lives in page 2
AY_BODY_LEN         equ 8964                ; the part that lives in the bank

; --- the entry stubs, always mapped ------------------------------------------
                    ; zxide: pin the .ay block is assembled for this address
                    SLOT 2
                    PAGE 2
                    org $BFF4
music_ay_stub:      INCBIN "../bin/music/music.ay", AY_BLOCK_OFFSET, AY_STUB_LEN
                    ASSERT $ == $C000       ; the stubs end exactly at the slot
                                            ; boundary; if this moves, the two
                                            ; halves have come apart

; --- the player and the tunes, in the music bank -----------------------------
                    ; zxide: pin the .ay block is assembled for this address
                    SLOT 3
                    PAGE 6
                    org $C000
music_ay_body:      INCBIN "../bin/music/music.ay", AY_BLOCK_OFFSET + AY_STUB_LEN, AY_BODY_LEN
                    ASSERT $ == $E304

; Put slot 3 back the way the game expects to start. savesna records whatever
; paging state the source last left, so without this the snapshot boots with
; the music bank at $C000 instead of the menu, and the first jp into a scene
; lands in song data.
                    SLOT 3
                    PAGE 0
