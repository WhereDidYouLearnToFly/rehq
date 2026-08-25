;=============================================================================
; save - what a saved character is, and putting one back
;=============================================================================
; Placement:  org HeroSave.
; Depends on: storage.save_block / storage.load_block, and globals for the
;             hero records. It never names a device.
; Namespace:  MODULE saveload - reached as saveload.*
;
; A hero is the 32 bytes in globals.asm - but that is not all of a character.
; The name the player typed is not in the record: Hero.NAME_ID is an index
; into globals.names and the text lives over there, so a save carrying only
; the record would come back as a stranger with the right stats.
;
; So a saved character is a small block of both, with four bytes in front of
; it saying what it is:
;
;   MAGIC    two bytes that are not going to turn up by accident, so a block
;            that is not ours is refused instead of installed
;   VERSION  bumped whenever the layout below changes, so a save from an
;            older build is refused rather than half understood
;   SLOT     which of the four it came from. The stats, the sprite and the
;            equipment are not interchangeable, so a wizard landing in the
;            barbarian is a mistake worth catching
;   HERO     the record, verbatim
;   NAME     the MenuString, length byte and all
;
; It is read into the buffer below and copied onto the live hero only once
; all three checks pass. That is the point of having a buffer at all: a tape
; can fail halfway through - which is what the carry flag coming back from
; storage is for - and a half-read block landing straight on the party would
; leave nothing to go back to.
;
; NAME_ID is deliberately NOT taken from the block. It indexes a table that
; does not travel with the save, so the destination keeps its own and only
; the text is taken.
;=============================================================================

                    org $C855
                    MODULE saveload

MAGIC               equ $5148               ; 'H','Q' in the order they land
VERSION             equ 1

buffer:
.magic:             dw 0
.version:           db 0
.slot:              db 0
.hero:              ds Hero
.name:              ds globals.NAME_MAX + 1
buffer_end:

LEN                 equ buffer_end - buffer

hero_ptr:           dw 0                    ; the live record being saved from
name_ptr:           dw 0                    ; or loaded into, and its name
want_slot:          db 0

;-----------------------------------------------------------------------------
; save_hero - ix = the Hero, hl = its name MenuString, a = its slot 0-3.
; The caller has already put the filename in storage.filename.
; Returns CF = 1 if the device is happy. Corrupts everything.
;-----------------------------------------------------------------------------
save_hero:
                    ld (want_slot), a
                    ld (name_ptr), hl
                    ld (hero_ptr), ix
;
                    ld hl, MAGIC
                    ld (buffer.magic), hl
                    ld a, VERSION
                    ld (buffer.version), a
                    ld a, (want_slot)
                    ld (buffer.slot), a
;
                    ld hl, (hero_ptr)
                    ld de, buffer.hero
                    ld bc, Hero             ; the struct name is its size
                    ldir
;
                    ld hl, (name_ptr)
                    ld de, buffer.name
                    ld bc, globals.NAME_MAX + 1
                    ldir
;
                    ld ix, buffer
                    ld de, LEN
                    jp storage.save_block

;-----------------------------------------------------------------------------
; load_hero - ix = the Hero to fill, hl = its name MenuString, a = the slot it
; must have come from.
; Returns CF = 1 if a character was loaded and installed, CF = 0 if the device
; failed or what arrived was not a character for this slot. Nothing is written
; to the live hero unless the answer is yes.
;-----------------------------------------------------------------------------
load_hero:
                    ld (want_slot), a
                    ld (name_ptr), hl
                    ld (hero_ptr), ix
;
                    ld ix, buffer
                    ld de, LEN
                    call storage.load_block
                    ret nc                  ; the device said no, and the party
                                            ; has not been touched
;
                    ld hl, (buffer.magic)
                    ld de, MAGIC
                    ld a, h
                    cp d
                    jr nz, .refuse
                    ld a, l
                    cp e
                    jr nz, .refuse
;
                    ld a, (buffer.version)
                    cp VERSION
                    jr nz, .refuse
;
                    ld a, (buffer.slot)
                    ld hl, want_slot
                    cp (hl)
                    jr nz, .refuse
;
                    ; Everything checks out, so it can go in. The name id is
                    ; held back over the copy: it points into a table that did
                    ; not travel with the save, and the destination's own is
                    ; the one that is right here.
                    ld ix, (hero_ptr)
                    ld a, (ix + Hero.NAME_ID)
                    push af
;
                    ld hl, buffer.hero
                    ld de, (hero_ptr)
                    ld bc, Hero
                    ldir
;
                    ld hl, buffer.name
                    ld de, (name_ptr)
                    ld bc, globals.NAME_MAX + 1
                    ldir
;
                    pop af
                    ld ix, (hero_ptr)
                    ld (ix + Hero.NAME_ID), a
;
                    scf
                    ret
.refuse:
                    and a                   ; it read cleanly, but it is not a
                    ret                     ; character this build can use

                    ENDMODULE
