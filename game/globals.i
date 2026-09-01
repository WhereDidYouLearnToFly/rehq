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

;-----------------------------------------------------------------------------
; Card - the equipment, potion and artifact cards, transcribed from the deck
; in assets/original_cards/cards. Static: one row per card, never written at
; runtime. What a hero is *holding* is a card id in Hero.WEAPON_ACTIVE and
; friends, so the row is one indirection away and four heroes carrying the
; same broadsword cost four bytes, not four rows.
;
; 16 bytes. The row carries its own name, its own rules text and its own code,
; so there is exactly one place to look up a card and nothing that can fall
; out of step with a parallel table. That costs the cheap indexing the 8-byte
; records have - 31 rows at 16 bytes is 496, which does not fit in A - so
; get_card indexes through HL. Ten T-states, and not in any inner loop.
;
; COST is what the armoury charges. Zero means the card is not for sale: the
; artifacts and the potions are found, not bought, and the shop list is built
; by walking this table and skipping the zeroes. That is the only thing that
; separates the two, so there is no KIND field to fall out of step with it.
;
; ATTACK and DEFEND are what the card is worth in combat dice, and the two
; are not the same kind of number, because the deck is not symmetrical:
;
;   a WEAPON replaces the dice a hero attacks with. The Barbarian's card says
;   Attack 3 and his starting weapon is the Broadsword, which is 3 - the 3 is
;   the sword, not the man. CARD_NONE is 1, so bare hands need no special
;   case.
;
;   ARMOUR adds to the dice a hero defends with. Every hero card says Defend
;   2 with "Starting Armor: None", and chain mail, helmet and shield say they
;   combine - so they stack on top of the 2.
;
; ACTION is the card's own code, or 0 for a card that only has to sit there
; being worth dice. See the contract below.
;-----------------------------------------------------------------------------
    STRUCT Card
NAME_STR         WORD $0000     ; a MenuString, ready for print_menu_string
DESCR_STR        WORD $0000     ; the rules text - see the note below, it is
                                ; NOT in this page
ACTION           WORD $0000     ; the card's own routine, 0 = nothing to run
COST             WORD $0000     ; gold, 0 = not for sale, found only
ART_ID           BYTE $00       ; index into the card art
SLOT             BYTE $00       ; SLOT_* - which Hero field it occupies
ATTACK           BYTE $00       ; dice the weapon rolls - it replaces
DEFEND           BYTE $00       ; dice the armour adds  - it stacks
TARGET           BYTE $00       ; ST_* - what the player has to pick first
TARGET_KIND      BYTE $00       ; TK_* - and what it is allowed to be
RESIST           BYTE $00       ; how the victim shrugs it off - same rule
                                ; and same values as Spell.RESIST
FLAGS            BYTE $00       ; CF_* below
    ENDS

; SLOT_* are 1..4 on purpose: they are the offsets of the four equipment
; fields of Hero counted from the first one, so equipping is
;
;       ld e, (iy+Card.SLOT)
;       dec e                           ; SLOT_WEAPON is the first field
;       ld d, 0
;       ld hl, Hero.WEAPON_ACTIVE
;       add hl, de
;       add hl, bc                      ; BC = the hero
;
; rather than a four-way branch. The ASSERTs hold the four fields together and
; in order; break one and the build stops here.
SLOT_NONE       equ 0           ; potions, the tool kit, anything just carried
SLOT_WEAPON     equ 1
SLOT_ARMOR      equ 2
SLOT_SHIELD     equ 3
SLOT_HELMET     equ 4

    ASSERT Hero.ARMOR_ACTIVE  == Hero.WEAPON_ACTIVE + (SLOT_ARMOR  - SLOT_WEAPON)
    ASSERT Hero.SHIELD_ACTIVE == Hero.WEAPON_ACTIVE + (SLOT_SHIELD - SLOT_WEAPON)
    ASSERT Hero.HELMET_ACTIVE == Hero.WEAPON_ACTIVE + (SLOT_HELMET - SLOT_WEAPON)

; CF_NO_WIZARD sits on bit 7 for the same reason CH_ALIVE does - the shop
; filters the list by it on every redraw, and equipping tests it again:
;       ld a, (iy+Card.FLAGS)
;       add a, a
;       jr c, .not_for_the_wizard
CF_NO_WIZARD    equ %10000000   ; "May not be used by the wizard."
CF_WIZARD_ONLY  equ %01000000   ; "It can be used only by the wizard."
CF_DIAGONAL     equ %00100000   ; reaches the diagonal squares as well
CF_RANGED       equ %00010000   ; fires at anything in line of sight, but
                                ; not at an adjacent monster
CF_THROWN       equ %00001000   ; may be thrown, and is lost when it is
CF_NO_SHIELD    equ %00000100   ; two-handed - no shield with this one
CF_ONE_USE      equ %00000010   ; drunk, poured or invoked once, then gone
CF_ONCE_QUEST   equ %00000001   ; its special power fires once per quest

; ART_ID is an index into the card art, which is not placed yet: the 166
; converted images in assets/art64t_zx are 512 bytes each and will have to be
; banked before anything can draw one. The field exists so that when they are
; placed, the art can be in whatever order the packer leaves it in without the
; card table having to move. Until then a card's art id is its own id.

;-----------------------------------------------------------------------------
; DESCR_STR - the rules text off the face of the card.
;
; All fifty-one of them are about 8.8K of text, and roughly 4.8K through zx0.
; Page 5 has a hundred-odd bytes left, so they do not live here and they never
; will: they belong in a bank of their own, paged in by whatever is drawing a
; card and paged straight back out.
;
; So DESCR_STR is an address in THAT bank, not in this one. Dereferencing it
; without the bank paged in reads whatever happens to be at that address, and
; nothing will tell you. Whoever draws a card pages first.
;
; 0 means the text has not been transcribed yet, which is currently all of
; them.
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; Spell - the twenty spell cards, transcribed from the deck. Static, 16 bytes,
; the same row shape as Card and for the same reason: name, rules text and
; code all in the row, one place to look.
;
; The order is not decoration. The twelve hero spells come first, three to an
; element, because Hero.SPELLS is a WORD with one bit per spell still unspent
; - so a spell id IS its bit number, and "which spells does the elf still
; hold" is one AND against an element mask.
;
; The eight Chaos spells start at 12, which is where the twelve hero bits run
; out. That is the point: a hero cannot be handed one by accident, because
; there is no bit in SPELLS to hand them. The ASSERT in globals.asm is what
; keeps that true if the table ever grows.
;
; AMOUNT is whatever the spell counts - Body Points restored or inflicted,
; extra combat dice, turns missed. What it means is the spell's business; the
; table only carries the number so ACTION is a short routine and not a pile
; of literals.
;
; RESIST is how the victim shrugs it off, and it is one field on both records
; because the deck turned out to have exactly two rules and one of them lands
; on a card as well as a spell - the Rod of Telekinesis is resisted with Mind
; Points, word for word the way Sleep is. See RESIST_MIND below.
;-----------------------------------------------------------------------------
    STRUCT Spell
NAME_STR         WORD $0000     ; a MenuString, ready for print_menu_string
DESCR_STR        WORD $0000     ; the rules text, in the description bank
ACTION           WORD $0000     ; the spell's own routine, 0 = not written yet
ART_ID           BYTE $00       ; index into the card art, as Card.ART_ID
ELEMENT          BYTE $00       ; SE_* below
TARGET           BYTE $00       ; ST_* - what the caster has to pick
TARGET_KIND      BYTE $00       ; TK_* - and what it is allowed to be
AMOUNT           BYTE $00       ; body points, dice, turns - see above
RESIST           BYTE $00       ; RESIST_* below, or a count of red dice
FLAGS            BYTE $00       ; SF_* below
                 BLOCK 3        ; spare, keeps the stride at 16
    ENDS

SE_AIR          equ 0
SE_EARTH        equ 1
SE_FIRE         equ 2
SE_WATER        equ 3
SE_CHAOS        equ 4           ; Zargon's, never in a hero's SPELLS word

;-----------------------------------------------------------------------------
; TARGET and TARGET_KIND - what has to be picked before anything happens, and
; what it is allowed to be. Cards and spells share them, so the menu that asks
; "at what?" is one routine rather than two.
;
; ST_* is the shape of the question. The cast/use menu branches on it once;
; after that every card and every spell is the same code path, and ACTION is
; handed a target it can trust.
;-----------------------------------------------------------------------------
ST_NONE         equ 0           ; nothing to pick - a broadsword just sits
                                ; there being worth three dice
ST_SELF         equ 1           ; Escape - the caster, no choice to make
ST_ONE_HERO     equ 2           ; "may be cast on any one hero, including
                                ; yourself"
ST_ONE_MONSTER  equ 3
ST_ROOM_HEROES  equ 4           ; Cloud of Dread - every hero in the room
ST_ROOM_ALL     equ 5           ; Firestorm - everyone but the caster
ST_LINE         equ 6           ; Lightning Bolt - straight until a wall
ST_ONE_ITEM     equ 7           ; Rust - a sword or a helmet, not an artifact

; TK_* narrows it. The low bits are a KIND_ or an MT_ from this file and
; globals.asm; the top bits say which, and whether the test is inverted:
;
;       TK_KIND | KIND_UNDEAD           holy water - undead only
;       TK_TYPE | MT_ORC                orc's bane - orcs, not all greenskins
;       TK_NOT | TK_KIND | KIND_UNDEAD  sleep - "may not be used against
;                                       mummies, zombies, or skeletons"
;
; so the check is one AND for the selector and one compare, whichever it is.
TK_ANY          equ $00         ; no restriction
TK_NOT          equ $20         ; invert: everything EXCEPT what follows
TK_KIND         equ $40         ; the low bits are a KIND_ - a class of monster
TK_TYPE         equ $80         ; the low bits are an MT_  - one kind exactly
TK_SELECT       equ TK_KIND | TK_TYPE
TK_VALUE        equ $1F         ; the low bits, whichever it is

; SF_CHAOS sits on bit 7 so the hero's cast menu filters the table the same
; way everything else in this file tests bit 7:
;       ld a, (iy+Spell.FLAGS)
;       add a, a
;       jr c, .not_the_heros
SF_CHAOS        equ %10000000   ; Zargon casts it, a hero never can
SF_LASTS        equ %00100000   ; stays on the figure until broken, rather
                                ; than resolving the moment it is cast
SF_NEEDS_LOS    equ %00010000   ; the target has to be in line of sight
SF_NOT_CORRIDOR equ %00001000   ; "Not used in corridors."
SF_SELF_SAFE    equ %00000100   ; the caster is not caught in their own blast

;-----------------------------------------------------------------------------
; RESIST - Card.RESIST and Spell.RESIST, one field, one routine, two rules.
;
;   0             nothing to resist. Holy water just kills the undead.
;
;   1..6          roll that many red dice; every 5 or 6 takes a point off
;                 AMOUNT. Fire of Wrath is one die against one point, so a 5
;                 or a 6 is a clean miss and it needs no rule of its own.
;
;   RESIST_MIND   roll one red die per Mind Point of the victim; a 6 breaks
;                 it outright. Sleep, Fear, Command, Cloud of Dread - and the
;                 Rod of Telekinesis, which is a card and reads the same.
;
; The sentinel is $FF rather than a flag bit so that a card and a spell can be
; handed to the same routine without it having to know which flag set it is
; looking at. Nothing in the deck does both, and nothing does anything else.
;-----------------------------------------------------------------------------
RESIST_NONE     equ 0
RESIST_MIND     equ $FF

;-----------------------------------------------------------------------------
; The ACTION contract - one signature for every card and every spell, so the
; menu never has to know which it is holding.
;
;   IX = the hero doing it - the caster, the drinker, the one swinging
;   IY = the Card or the Spell, already found
;   HL = the target the ST_* question produced:
;           ST_NONE                 undefined, do not read it
;           ST_SELF                 the caster again
;           ST_ONE_HERO             a Hero
;           ST_ONE_MONSTER          a Monster
;           ST_ROOM_HEROES/ALL      the first figure; the routine walks
;           ST_LINE                 the square the bolt starts from
;           ST_ONE_ITEM             the Hero field holding the doomed card
;
;   returns carry set if it happened, clear if the player backed out or it
;   was refused - the caller spends the spell bit, the potion or the turn on
;   carry only.
;
; ACTION = 0 means there is nothing to run. That is not a stub: a broadsword
; genuinely has no code, its three dice are read out of the row by combat.
;-----------------------------------------------------------------------------
