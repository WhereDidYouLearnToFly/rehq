;=============================================================================
; storage - saving and loading, whatever the machine happens to have
;=============================================================================
; Placement:  MemPlan places this one - the org below is the answer.
; Depends on: nothing. The backend depends on this one, not the other way
;             round - which is why this file has no idea what a tape is.
; Namespace:  MODULE storage - every label below is reached as storage.*
;
; Getting a character off the machine and back has two halves:
;
;   what a saved character contains   game/save.asm, because only the game
;                                     knows what a hero is
;   how the bytes leave the machine   the backend this build was assembled
;                                     with - core/storage/tape.asm today,
;                                     core/storage/trdos.asm later
;
; This file is the seam. It owns the one thing every device needs and none of
; them can invent - the name the block is filed under - and it fixes the two
; entries the game calls, so nothing above here ever says the word "tape".
;
; Which device those two entries reach is decided when the build is
; assembled, not while the game runs. In heroques.asm:
;
;       ;DEFINE STORAGE_TRDOS       ; commented out = tape
;
; so only one backend is assembled and there is no vector to follow, no byte
; spent on a device that is not fitted, and no way to end up with half of one
; driver and half of the other. It is the same choice the Kempston reader in
; core/input makes by being commented out of the include list.
;
; Both backends are held to the same contract, and it is deliberately the
; smallest one both can honour - tape has no catalogue, no directory, no way
; to delete and no way to ask what is on it, so nothing above may assume one:
;
;   storage.save_block   ix = address, de = length. Writes that block under
;                        the name in storage.filename.
;   storage.load_block   ix = address, de = length. Finds the block filed
;                        under storage.filename and reads it back into ix.
;
;   Both answer CF = 1 for success and CF = 0 for failure - the convention
;   the ROM tape loader already uses, so the tape backend hands its own
;   answer straight back. Both take seconds rather than frames: see the note
;   on `pending` in game/scenes/characters_scene.asm for where they may be
;   called from.
;
; FILENAME_LEN is 8 because that is what both devices can carry. A tape
; header has room for ten characters and a TR-DOS entry for eight plus a type
; letter, so a name of eight goes to either without being cut about - and a
; name that means the same thing on both is the whole point of having one
; name at all.
;=============================================================================

                    SLOT 3
                    PAGE 0
                    org $C99A
                    MODULE storage

FILENAME_LEN        equ 8

; The two entries the game calls, aliased onto whichever backend this build
; assembled. EQU rather than a jump: it costs no bytes and there is nothing
; that can get out of step. The backend is included after this file, so these
; are forward references - which is fine, and is why the alias lives here
; rather than in a second MODULE block at the bottom of the file.
    IFDEF STORAGE_TRDOS
save_block          equ trdos.save_block
load_block          equ trdos.load_block
    ELSE
save_block          equ tape.save_block
load_block          equ tape.load_block
    ENDIF

; Space padded, never terminated: both devices store a fixed-width field, so
; there is nothing for a terminator to do except take up one of the eight.
filename:           ds FILENAME_LEN, ' '

;-----------------------------------------------------------------------------
; set_filename - hl = FILENAME_LEN characters, copied into filename.
; Corrupts bc, de, hl.
;
; Callers pass a fixed string per save slot rather than the hero's typed name:
; the player can rename a character between saving and loading it, and a file
; that can no longer be found by the name it was filed under is worse than a
; file with a dull name. The typed name travels inside the block instead.
;-----------------------------------------------------------------------------
set_filename:
                    ld de, filename
                    ld bc, FILENAME_LEN
                    ldir
                    ret

                    ENDMODULE
