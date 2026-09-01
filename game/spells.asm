;=============================================================================
; spells - the twelve hero spells and Zargon's eight
;=============================================================================
; Placement:  MemPlan places this one, in page 5, for the same reason items
;             is there: the cast menu reads it with no bank paged in.
; Depends on: globals for the STR_ names, data/card_data.asm for the rules
;             text, and game/globals.i for the Spell record itself.
; Namespace:  MODULE spells - the table is spells.list, the lookup spells.get,
;             and spells.bit turns an id into its bit in Hero.SPELLS.
;=============================================================================

    SLOT 3
    PAGE 4
    ; zxide: size(384) read by scenes in slot 3, so it cannot live in a bank -
    ;             the reader would be paged out along with the page it asked from
    org $E5E3
    MODULE spells

;-----------------------------------------------------------------------------
; spells - the twenty spell cards, transcribed from the deck. See globals.i
; for what the columns mean and why the order is what it is.
;
; Unlike cards, there is no id 0 meaning "nothing": a hero's spells are the
; bits of Hero.SPELLS, not an id, so there is never a slot that has to say it
; is empty. Spell 0 is the Genie, and it is a real spell.
;
; What the table cannot hold, and is therefore code, selected by the id:
;   GENIE               opens any door instead, if the caster would rather
;   SWIFT_WIND          doubles the move dice, it does not add to them
;   PASS_THROUGH_ROCK   walls stop costing movement; ending inside solid rock
;                       loses the hero for good
;   ROCK_SKIN           broken by the first Body Point, not by line of sight
;   COURAGE             broken when no monster is in the hero's line of sight
;   VEIL_OF_MIST        monsters stop blocking squares for one move
;   COMMAND             Zargon moves and attacks with the hero
;   ESCAPE              teleports the caster to the quest's marked square
;   RUST                destroys the weapon or helmet outright, artifacts
;                       excepted
;   LIGHTNING_BOLT      travels until a wall or a closed door, hitting
;                       everything on the way, heroes included
;-----------------------------------------------------------------------------
SP_GENIE            equ 0       ; air
SP_SWIFT_WIND       equ 1
SP_TEMPEST          equ 2
SP_HEAL_BODY        equ 3       ; earth
SP_PASS_THRU_ROCK   equ 4
SP_ROCK_SKIN        equ 5
SP_BALL_OF_FLAME    equ 6       ; fire
SP_COURAGE          equ 7
SP_FIRE_OF_WRATH    equ 8
SP_SLEEP            equ 9       ; water
SP_VEIL_OF_MIST     equ 10
SP_WATER_HEALING    equ 11

SP_CLOUD_OF_DREAD   equ 12      ; chaos - Zargon's, no bit in Hero.SPELLS
SP_COMMAND          equ 13
SP_ESCAPE           equ 14
SP_FEAR             equ 15
SP_FIRESTORM        equ 16
SP_LIGHTNING_BOLT   equ 17
SP_RUST             equ 18
SP_CHAOS_BALL_FLAME equ 19

;         NAME              DESCR_STR                          ACT ART  ELEMENT   TARGET           TARGET_KIND                      AMT RESIST       FLAGS
list:
    Spell globals.STR_GENIE,           card_data.t_spell_genie,            0, 31,  SE_AIR,   ST_ONE_MONSTER,  TK_ANY,                          5, RESIST_NONE, SF_NEEDS_LOS
    Spell globals.STR_SWIFT_WIND,      card_data.t_spell_swift_wind,       0, 32,  SE_AIR,   ST_ONE_HERO,     TK_ANY,                          2, RESIST_NONE, 0
    Spell globals.STR_TEMPEST,         card_data.t_spell_tempest,          0, 33,  SE_AIR,   ST_ONE_MONSTER,  TK_ANY,                          1, RESIST_NONE, 0
    Spell globals.STR_HEAL_BODY,       card_data.t_spell_heal_body,        0, 34,  SE_EARTH, ST_ONE_HERO,     TK_ANY,                          4, RESIST_NONE, 0
    Spell globals.STR_PASS_THRU_ROCK,  card_data.t_spell_pass_thru_rock,   0, 35,  SE_EARTH, ST_ONE_HERO,     TK_ANY,                          0, RESIST_NONE, 0
    Spell globals.STR_ROCK_SKIN,       card_data.t_spell_rock_skin,        0, 36,  SE_EARTH, ST_ONE_HERO,     TK_ANY,                          1, RESIST_NONE, SF_LASTS
    Spell globals.STR_BALL_OF_FLAME,   card_data.t_spell_ball_of_flame,    0, 37,  SE_FIRE,  ST_ONE_MONSTER,  TK_ANY,                          2, 2,           0
    Spell globals.STR_COURAGE,         card_data.t_spell_courage,          0, 38,  SE_FIRE,  ST_ONE_HERO,     TK_ANY,                          2, RESIST_NONE, SF_LASTS
    Spell globals.STR_FIRE_OF_WRATH,   card_data.t_spell_fire_of_wrath,    0, 39,  SE_FIRE,  ST_ONE_MONSTER,  TK_ANY,                          1, 1,           0
    Spell globals.STR_SLEEP,           card_data.t_spell_sleep,            0, 40,  SE_WATER, ST_ONE_MONSTER,  TK_NOT | TK_KIND | KIND_UNDEAD,  0, RESIST_MIND, SF_LASTS
    Spell globals.STR_VEIL_OF_MIST,    card_data.t_spell_veil_of_mist,     0, 41,  SE_WATER, ST_ONE_HERO,     TK_ANY,                          0, RESIST_NONE, 0
    Spell globals.STR_WATER_HEALING,   card_data.t_spell_water_healing,    0, 42,  SE_WATER, ST_ONE_HERO,     TK_ANY,                          4, RESIST_NONE, 0

    ; chaos - Zargon's, and there is no bit in Hero.SPELLS for any of them
    Spell globals.STR_CLOUD_OF_DREAD,  card_data.t_spell_cloud_of_dread,   0, 43,  SE_CHAOS, ST_ROOM_HEROES,  TK_ANY,                          0, RESIST_MIND, SF_CHAOS | SF_LASTS
    Spell globals.STR_COMMAND,         card_data.t_spell_command,          0, 44,  SE_CHAOS, ST_ONE_HERO,     TK_ANY,                          0, RESIST_MIND, SF_CHAOS | SF_LASTS
    Spell globals.STR_ESCAPE,          card_data.t_spell_escape,           0, 45,  SE_CHAOS, ST_SELF,         TK_ANY,                          0, RESIST_NONE, SF_CHAOS
    Spell globals.STR_FEAR,            card_data.t_spell_fear,             0, 46,  SE_CHAOS, ST_ONE_HERO,     TK_ANY,                          1, RESIST_MIND, SF_CHAOS | SF_LASTS
    Spell globals.STR_FIRESTORM,       card_data.t_spell_firestorm,        0, 47,  SE_CHAOS, ST_ROOM_ALL,     TK_ANY,                          3, 2,           SF_CHAOS | SF_SELF_SAFE | SF_NOT_CORRIDOR
    Spell globals.STR_LIGHTNING_BOLT,  card_data.t_spell_lightning_bolt,   0, 48,  SE_CHAOS, ST_LINE,         TK_ANY,                          2, RESIST_NONE, SF_CHAOS
    Spell globals.STR_RUST,            card_data.t_spell_rust,             0, 49,  SE_CHAOS, ST_ONE_ITEM,     TK_ANY,                          0, RESIST_NONE, SF_CHAOS
    Spell globals.STR_BALL_OF_FLAME,   card_data.t_spell_chaos_ball_flame, 0, 50,  SE_CHAOS, ST_ONE_HERO,     TK_ANY,                          2, 2,           SF_CHAOS
list_end:

SPELL_COUNT         equ (list_end - list) / Spell
SPELL_CHAOS_FIRST   equ SP_CLOUD_OF_DREAD

; A spell id is its bit in Hero.SPELLS, so the elf who is given Air and Water
; gets one OR of two constants and the cast menu is one AND. An element is
; three consecutive bits because there are three cards of each in the deck.
SPELLS_AIR          equ %0000000000000111
SPELLS_EARTH        equ %0000000000111000
SPELLS_FIRE         equ %0000000111000000
SPELLS_WATER        equ %0000111000000000
SPELLS_ALL          equ SPELLS_AIR | SPELLS_EARTH | SPELLS_FIRE | SPELLS_WATER

    ASSERT SPELL_COUNT == 20

; The line that keeps Zargon's spells out of a hero's hands: every hero spell
; has to have a bit in Hero.SPELLS, and the Chaos ones start where the bits
; stop. Add a fifth hero spell to an element and this is what says so.
    ASSERT SPELL_CHAOS_FIRST <= 16
    ASSERT SPELLS_ALL == (1 << SPELL_CHAOS_FIRST) - 1

;-----------------------------------------------------------------------------
; get_spell - A = an SP_ constant, returns IY = that Spell. Corrupts HL and DE.
; spell_bit - A = an SP_ constant, returns HL = its bit in Hero.SPELLS, so
;             holding, spending and granting are all one mask. Corrupts A
;             and B.
;
;       ld a, SP_HEAL_BODY
;       call spell_bit                  ; HL = 1 << SP_HEAL_BODY
;       ld a, (ix+Hero.SPELLS)          ; SPELLS is a word - low byte here,
;       and l                           ; high byte and H for the water ones
;-----------------------------------------------------------------------------
get_spell:
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl                      ; index * 16
                ld de, list
                add hl, de
                push hl
                pop iy
                ret

spell_bit:
                ld hl, 1
                or a                            ; spell 0 is already there
                ret z
                ld b, a
.shift:
                add hl, hl
                djnz .shift
                ret

    ENDMODULE
