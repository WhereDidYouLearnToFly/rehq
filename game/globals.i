;-----------------------------------------------------------------------------
; The figure records.
;
; MonsterType is the stat line - static, one per kind of monster, never
; written at runtime. Monster is one figure standing on the board: only what
; changes. All sixteen goblins of a quest share one MonsterType and cost
; eight bytes each.
;
; Hero is both at once. There are exactly four, their stats are as particular
; as their equipment, and both change during a quest, so nothing is gained by
; splitting them.
;
; The first five fields of Hero and Monster are deliberately the same, in the
; same order: FLAGS, BODY, MOVE_LEFT, X, Y. That is what lets move, draw,
; take-a-wound and who-is-on-this-square run off a single set of offsets
; whichever table the pointer came from. The ASSERTs below hold that line - if
; a field has to move, the build says so instead of the shared routines
; quietly reading the wrong byte. Deleting an ASSERT is how you decide the two
; records really have parted ways.
;
; Combat dice do *not* share an offset, because they no longer live in the
; same place: a hero's ATTACK is in the record, already carrying the weapon
; bonus, while a monster's is read from its MonsterType. Anything that rolls
; has to know which it is holding - CH_IS_HERO says.
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; MonsterType - static. One row per kind, in the table in globals.asm.
; 8 bytes, so a type id is three adds.
;-----------------------------------------------------------------------------
    STRUCT MonsterType
NAME_ID          BYTE $00       ; index into the names array
SPRITE_ID        BYTE $00
ATTACK           BYTE $00       ; combat dice
DEFEND           BYTE $00       ; combat dice
BODY             BYTE $00       ; how many it starts with
MIND             BYTE $00
MOVE             BYTE $00       ; squares per turn, fixed - monsters roll none
KIND             BYTE $00       ; KIND_* below - AI class and spell targeting
    ENDS

;-----------------------------------------------------------------------------
; Monster - one figure on the board. The variables and nothing else:
; everything static is one indirection away through TYPE.
;
; The pool of these lives with the level, not here: the quest roster says
; which figures a room holds, and opening the room turns those rows into live
; records. 8 bytes, so a slot index is three adds.
;-----------------------------------------------------------------------------
    STRUCT Monster
FLAGS            BYTE $00       ; CH_* below
BODY             BYTE $00       ; current, counts down from MonsterType.BODY
MOVE_LEFT        BYTE $00       ; squares left this turn
X                BYTE $00       ; board square
Y                BYTE $00
TYPE             BYTE $00       ; index into monster_types
AI_STATE         BYTE $00
TARGET           BYTE $00       ; hero slot it is going for
    ENDS

;-----------------------------------------------------------------------------
; Hero - the four of them, named in globals.asm rather than counted. Carries
; what a monster has no use for: equipment, gold, spells, and the maxima that
; healing tops back up to.
; 32 bytes, so walking them by index is five adds.
;-----------------------------------------------------------------------------
    STRUCT Hero
FLAGS            BYTE $00       ; CH_* below
BODY             BYTE $00       ; current, counts down to 0
MOVE_LEFT        BYTE $00       ; squares left this turn
X                BYTE $00       ; board square
Y                BYTE $00
ATTACK           BYTE $00       ; combat dice, weapon already included
DEFEND           BYTE $00       ; combat dice, armour already included
MIND             BYTE $00
MOVE_DICE        BYTE $00       ; d6 to roll at the start of the turn
SPRITE_ID        BYTE $00
NAME_ID          BYTE $00       ; index into the names array
BODY_MAX         BYTE $00       ; healing stops here
MIND_MAX         BYTE $00
WEAPON_ACTIVE    BYTE $00       ; item id, 0 = unarmed
ARMOR_ACTIVE     BYTE $00       ; item id, 0 = unarmoured
SHIELD_ACTIVE    BYTE $00
HELMET_ACTIVE    BYTE $00
GOLD             WORD $0000
SPELLS           WORD $0000     ; one bit per spell card still unspent
ITEMS            WORD $0000     ; potions and artifacts carried
                 BLOCK 9        ; spare, keeps the stride at 32
    ENDS

; The shared prefix. Break one of these and the build stops here, not in the
; middle of a routine that thought it was reading BODY.
    ASSERT Hero.FLAGS     == Monster.FLAGS
    ASSERT Hero.BODY      == Monster.BODY
    ASSERT Hero.MOVE_LEFT == Monster.MOVE_LEFT
    ASSERT Hero.X         == Monster.X
    ASSERT Hero.Y         == Monster.Y

; CH_ALIVE sits on bit 7 so the test every turn costs an add and a jump:
;       ld a, (ix+Hero.FLAGS)
;       add a, a
;       jr nc, .dead
CH_ALIVE        equ %10000000
CH_ONBOARD      equ %01000000   ; placed on the board and drawn
CH_IS_HERO      equ %00100000   ; which table this pointer came from
CH_MOVED        equ %00010000   ; cleared at the start of the turn
CH_ACTED        equ %00001000   ; attacked or cast or searched, cleared with CH_MOVED

KIND_GREENSKIN  equ 0           ; goblin, orc
KIND_UNDEAD     equ 1           ; skeleton, zombie, mummy - no mind to attack
KIND_CHAOS      equ 2           ; chaos warrior, sorcerer, gargoyle
KIND_BEAST      equ 3           ; fimir, dragon

; MAX_MONSTERS belongs to whoever owns the pool - the level - not here.
; Keep it a multiple of 32 and page-aligned and the index stays three adds.
