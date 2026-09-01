
    ; zxide: size(1280)
    SLOT 1
    PAGE 5
    org $66A1
    MODULE globals

MUSIC_BIT       equ 5
MOVEMENT_BIT    equ 6
MUSIC           equ 1 << MUSIC_BIT 
MOVEMENT        equ 1 << MOVEMENT_BIT

settings:           .db MUSIC             ; the defaults, baked into the
                                          ; snapshot. Setting them at the start
                                          ; of a scene would undo the player's
                                          ; choice every time that scene ran.

;-----------------------------------------------------------------------------
; names - every figure's name, in one place, in MenuString form so
; menus.print_menu_string can put any of them on the screen unchanged.
;
; NAME_ID in a Hero and NAME_ID in the monster stat table are both indexes
; into this array, which is why it lives here and not in a scene: the HUD, the
; character sheet and the combat line all read the same table.
;
; Cards and spells are NOT in here. They carry a NAME_STR pointer in the row
; instead, because the array only earns its keep for records that are renamed
; or saved (a hero) or reached by an id that has to stay small (a monster).
; A card is neither, and a pointer in the row is a byte cheaper than an entry
; here plus the get_name that reads it.
;-----------------------------------------------------------------------------
NAME_BARBARIAN      equ 0
NAME_DWARF          equ 1
NAME_ELF            equ 2
NAME_WIZARD         equ 3
NAME_GOBLIN         equ 4
NAME_ORC            equ 5
NAME_FIMIR          equ 6
NAME_SKELETON       equ 7
NAME_ZOMBIE         equ 8
NAME_MUMMY          equ 9
NAME_CHAOS_WARRIOR  equ 10
NAME_GARGOYLE       equ 11
NAME_CHAOS_SORCERER equ 12
NAME_DRAGON         equ 13

NAME_MAX            equ 6

;-----------------------------------------------------------------------------
; HERO_NAME - a MenuString the player can type over. Same layout as
; MENU_STRING, so printing it is the same call, but the text is always padded
; out to NAME_MAX bytes: the name field writes the full width of the flag
; whatever is showing at the time, and a shorter literal would leave it
; writing into the next name. Spare cells are spaces, so a half-typed name
; still prints as a whole field.
;-----------------------------------------------------------------------------
    MACRO HERO_NAME text?
                MenuString .end - .text
.text:          db text?
.end:           ds NAME_MAX - (.end - .text), ' '
    ENDM

STR_BARBARIAN:      HERO_NAME "SIGMAR"
STR_DWARF:          HERO_NAME "GRUGNI"
STR_ELF:            HERO_NAME "LADRIL"
STR_WIZARD:         HERO_NAME "ZOLTAN"
STR_GOBLIN:         MENU_STRING "GOBLIN"
STR_ORC:            MENU_STRING "ORC"
STR_FIMIR:          MENU_STRING "FIMIR"
STR_SKELETON:       MENU_STRING "SKELETON"
STR_ZOMBIE:         MENU_STRING "ZOMBIE"
STR_MUMMY:          MENU_STRING "MUMMY"
STR_CHAOS_WARRIOR:  MENU_STRING "CHAOS WARRIOR"
STR_GARGOYLE:       MENU_STRING "GARGOYLE"
STR_CHAOS_SORCERER: MENU_STRING "CHAOS SORCERER"
STR_DRAGON:         MENU_STRING "DRAGON"

STR_NONE:           MENU_STRING "NONE"
STR_DAGGER:         MENU_STRING "DAGGER"
STR_STAFF:          MENU_STRING "STAFF"
STR_SHORTSWORD:     MENU_STRING "SHORTSWORD"
STR_HANDAXE:        MENU_STRING "HANDAXE"
STR_BROADSWORD:     MENU_STRING "BROADSWORD"
STR_LONGSWORD:      MENU_STRING "LONGSWORD"
STR_CROSSBOW:       MENU_STRING "CROSSBOW"
STR_BATTLE_AXE:     MENU_STRING "BATTLE AXE"
STR_HELMET:         MENU_STRING "HELMET"
STR_SHIELD:         MENU_STRING "SHIELD"
STR_CHAIN_MAIL:     MENU_STRING "CHAIN MAIL"
STR_BRACERS:        MENU_STRING "BRACERS"
STR_TOOL_KIT:       MENU_STRING "TOOL KIT"
STR_HOLY_WATER:     MENU_STRING "HOLY WATER"
STR_ORCS_BANE:      MENU_STRING "ORC'S BANE"
STR_PHANTOM_BLADE:  MENU_STRING "PHANTOM BLADE"
STR_FORTUNES_SWORD: MENU_STRING "FORTUNE'S LONGSWORD"
STR_WIZARDS_STAFF:  MENU_STRING "WIZARD'S STAFF"
STR_BORINS_ARMOR:   MENU_STRING "BORIN'S ARMOR"
STR_WIZARDS_CLOAK:  MENU_STRING "WIZARD'S CLOAK"
STR_SPELL_RING:     MENU_STRING "SPELL RING"
STR_WAND_OF_MAGIC:  MENU_STRING "WAND OF MAGIC"
STR_RING_FORTITUDE: MENU_STRING "RING OF FORTITUDE"
STR_RING_RETURN:    MENU_STRING "RING OF RETURN"
STR_ROD_TELEKIN:    MENU_STRING "ROD OF TELEKINESIS"
STR_POTION_HEALING: MENU_STRING "POTION OF HEALING"
STR_POTION_DEFENSE: MENU_STRING "POTION OF DEFENSE"
STR_POTION_STRENGTH: MENU_STRING "POTION OF STRENGTH"
STR_ELIXIR_OF_LIFE: MENU_STRING "ELIXIR OF LIFE"
STR_HEROIC_BREW:    MENU_STRING "HEROIC BREW"

STR_GENIE:          MENU_STRING "GENIE"
STR_SWIFT_WIND:     MENU_STRING "SWIFT WIND"
STR_TEMPEST:        MENU_STRING "TEMPEST"
STR_HEAL_BODY:      MENU_STRING "HEAL BODY"
STR_PASS_THRU_ROCK: MENU_STRING "PASS THROUGH ROCK"
STR_ROCK_SKIN:      MENU_STRING "ROCK SKIN"
STR_BALL_OF_FLAME:  MENU_STRING "BALL OF FLAME"
STR_COURAGE:        MENU_STRING "COURAGE"
STR_FIRE_OF_WRATH:  MENU_STRING "FIRE OF WRATH"
STR_SLEEP:          MENU_STRING "SLEEP"
STR_VEIL_OF_MIST:   MENU_STRING "VEIL OF MIST"
STR_WATER_HEALING:  MENU_STRING "WATER OF HEALING"
STR_CLOUD_OF_DREAD: MENU_STRING "CLOUD OF DREAD"
STR_COMMAND:        MENU_STRING "COMMAND"
STR_ESCAPE:         MENU_STRING "ESCAPE"
STR_FEAR:           MENU_STRING "FEAR"
STR_FIRESTORM:      MENU_STRING "FIRESTORM"
STR_LIGHTNING_BOLT: MENU_STRING "LIGHTNING BOLT"
STR_RUST:           MENU_STRING "RUST"

names:              dw STR_BARBARIAN, STR_DWARF, STR_ELF, STR_WIZARD
                    dw STR_GOBLIN, STR_ORC, STR_FIMIR, STR_SKELETON
                    dw STR_ZOMBIE, STR_MUMMY, STR_CHAOS_WARRIOR
                    dw STR_GARGOYLE, STR_CHAOS_SORCERER, STR_DRAGON
names_end:

NAME_COUNT          equ (names_end - names) / 2

;-----------------------------------------------------------------------------
; get_name - A = a NAME_ constant, returns HL = that MenuString, ready for
; menus.print_menu_string. Corrupts A and DE.
;-----------------------------------------------------------------------------
get_name:
                add a, a                        ; two bytes to a pointer
                ld e, a
                ld d, 0
                ld hl, names
                add hl, de
                ld e, (hl)                      ; follow it
                inc hl
                ld d, (hl)
                ex de, hl
                ret

;-----------------------------------------------------------------------------
; monster_types - the stat lines. Static: spawning copies BODY and MOVE out of
; here into the figure, everything else is read straight off the type, so a
; room full of orcs shares one row.
;
; The dragon is from the quest pack. The rest are the base roster, written
; from the monster reference - check them against the book before they start
; deciding fights.
;-----------------------------------------------------------------------------
MT_GOBLIN           equ 0
MT_ORC              equ 1
MT_FIMIR            equ 2
MT_SKELETON         equ 3
MT_ZOMBIE           equ 4
MT_MUMMY            equ 5
MT_CHAOS_WARRIOR    equ 6
MT_GARGOYLE         equ 7
MT_CHAOS_SORCERER   equ 8
MT_DRAGON           equ 9

;                        NAME                 SPR ATK DEF BODY MIND MOVE KIND
monster_types:
    MonsterType NAME_GOBLIN,          4,  2,  1,  1,   1,   10,  KIND_GREENSKIN
    MonsterType NAME_ORC,             5,  3,  2,  1,   2,   8,   KIND_GREENSKIN
    MonsterType NAME_FIMIR,           6,  3,  3,  2,   3,   6,   KIND_BEAST
    MonsterType NAME_SKELETON,        7,  2,  2,  1,   0,   6,   KIND_UNDEAD
    MonsterType NAME_ZOMBIE,          8,  2,  3,  1,   0,   4,   KIND_UNDEAD
    MonsterType NAME_MUMMY,           9,  3,  4,  2,   0,   4,   KIND_UNDEAD
    MonsterType NAME_CHAOS_WARRIOR,   10, 3,  4,  3,   3,   6,   KIND_CHAOS
    MonsterType NAME_GARGOYLE,        11, 4,  4,  3,   4,   6,   KIND_CHAOS
    MonsterType NAME_CHAOS_SORCERER,  12, 2,  4,  2,   4,   6,   KIND_CHAOS
    MonsterType NAME_DRAGON,          13, 5,  5,  4,   4,   7,   KIND_BEAST
monster_types_end:

MT_COUNT            equ (monster_types_end - monster_types) / MonsterType

;-----------------------------------------------------------------------------
; get_monster_type - A = an MT_ constant, returns IY = that MonsterType.
; type_of          - IX = a Monster,      returns IY = its MonsterType.
;
; IY rather than IX, so a figure and its stat line can be held at once:
;
;       call type_of
;       ld a, (iy+MonsterType.ATTACK)   ; dice it rolls
;       ld b, (ix+Monster.BODY)         ; what is left of it
;
; Both corrupt A and DE.
;-----------------------------------------------------------------------------
type_of:
                ld a, (ix+Monster.TYPE)
get_monster_type:
                add a, a
                add a, a
                add a, a                        ; index * 8
                ld e, a
                ld d, 0
                ld iy, monster_types
                add iy, de
                ret

;-----------------------------------------------------------------------------
; The party. Always these four, always in this order, so they are named rather
; than counted - but they are laid out back to back at one stride, so the turn
; loop and the four HUD panels can still walk them by index 0-3.
;
;                 FLAGS  BODY MLEFT X Y   ATK DEF MIND MDICE
;                 SPRITE NAME        BMAX MMAX   WEAPON ARMOR SHIELD HELMET
;
; The values below are the start of quest one. A second game has to write them
; back - once play begins these bytes are the live figures, not a template.
;-----------------------------------------------------------------------------
HERO_START      equ CH_ALIVE | CH_IS_HERO

                ALIGN 256
heroes:
barbarian:      Hero {HERO_START, 8, 0, 0, 0,  3, 2, 2, 2,  0, NAME_BARBARIAN, 8, 2,  0, 0, 0, 0}
dwarf:          Hero {HERO_START, 7, 0, 0, 0,  2, 2, 3, 2,  1, NAME_DWARF,     7, 3,  0, 0, 0, 0}
elf:            Hero {HERO_START, 6, 0, 0, 0,  2, 2, 4, 2,  2, NAME_ELF,       6, 4,  0, 0, 0, 0}
wizard:         Hero {HERO_START, 4, 0, 0, 0,  1, 2, 6, 2,  3, NAME_WIZARD,    4, 6,  0, 0, 0, 0}
heroes_end:

HERO_COUNT      equ (heroes_end - heroes) / Hero

;-----------------------------------------------------------------------------
; get_hero - A = slot index (0..HERO_COUNT-1), returns IX = that Hero, in the
; order they are declared above. Corrupts A.
;
; The matching get_monster lives with the pool, in the level: it is the base
; address that makes the indexing cheap, and that is the level's to know.
;-----------------------------------------------------------------------------
get_hero:
                add a, a
                add a, a
                add a, a
                add a, a
                add a, a                ; index * 32
                ld ix, heroes           ; low byte is 0 by ALIGN
                ld ixl, a
                ret

    ENDMODULE
