;=============================================================================
; items - the equipment, potion and artifact cards
;=============================================================================
; Placement:  MemPlan places this one, in page 5 - the table is read by the
;             shop, the character sheet and combat, none of which can page.
;             It sat in PAGE 4 at slot 3 until the shop first read it, which
;             is the one arrangement that cannot work: every scene is PAGE 0
;             at that same slot, so paging this in would page the caller out.
;             Nothing had called get_card yet, so nothing had noticed.
;             game/spells.asm still has the same pair of directives and the
;             same problem waiting.
; Depends on: globals for the STR_ names, data/card_data.asm for the rules
;             text, and game/globals.i for the Card record itself.
; Namespace:  MODULE items - the table is items.cards, the lookup items.get.
;
; The size() below is room, not bytes emitted: four more cards fit without
; shoving anything else up the page.
;=============================================================================

    SLOT 1
    PAGE 5
    ; zxide: size(576) read by scenes in slot 3, so it cannot live in a bank -
    ;             the reader would be paged out along with the page it asked from
    org $6DC4
    MODULE items

;-----------------------------------------------------------------------------
; cards - the equipment, potions and artifacts, transcribed card by card from
; the deck in assets/original_cards/cards. Static, one row per card; what a
; hero holds is an id in Hero.WEAPON_ACTIVE and friends.
;
; CARD_NONE is a real row, not a hole. An unarmed hero has 0 in WEAPON_ACTIVE
; and 0 in ARMOR_ACTIVE, and reading row 0 gives a card worth no dice that
; nobody is forbidden - so equip, unequip and the character sheet are all the
; same code path and none of them needs a "nothing here" test.
;
; The first block is the armoury: those are the cards with a COST, and the
; shop list is nothing more than this table walked with the zeroes skipped.
; Everything after it is found in the dungeon, which is why it is free.
;
; What the cards say that this table cannot hold:
;   POTION OF HEALING   restores a roll of one red die, capped at BODY_MAX
;   ELIXIR OF LIFE      raises a dead hero at full BODY and MIND
;   HEROIC BREW         two attacks instead of one, once
;   RING OF FORTITUDE   +1 to BODY_MAX while worn
;   TOOL KIT            a 50/50 roll to disarm a found trap
;   HOLY WATER          kills any undead outright, instead of attacking
;   SPELL RING          one declared spell may be cast twice
;   WAND OF MAGIC       two different spells in one turn
;   RING OF RETURN      every hero in sight goes back to the start
;   ROD OF TELEKINESIS  a monster misses its turn unless it rolls a 6 per
;                       MIND point
;   ORCS_BANE           attacks twice when the target is an orc
;   PHANTOM_BLADE       once a quest, the target may not defend
;   FORTUNES_SWORD      once a quest, reroll one attack die
; Those are code, and the id is what selects it. The table carries only what
; every card has, so that the shop and the character sheet never have to ask
; which card they are looking at.
;-----------------------------------------------------------------------------
CARD_NONE           equ 0

CARD_DAGGER         equ 1       ; the armoury - everything with a price
CARD_STAFF          equ 2
CARD_SHORTSWORD     equ 3
CARD_HANDAXE        equ 4
CARD_BROADSWORD     equ 5
CARD_LONGSWORD      equ 6
CARD_CROSSBOW       equ 7
CARD_BATTLE_AXE     equ 8
CARD_HELMET         equ 9
CARD_SHIELD         equ 10
CARD_CHAIN_MAIL     equ 11
CARD_BRACERS        equ 12
CARD_TOOL_KIT       equ 13
CARD_HOLY_WATER     equ 14

CARD_ORCS_BANE      equ 15      ; artifacts - found, never sold
CARD_PHANTOM_BLADE  equ 16
CARD_FORTUNES_SWORD equ 17
CARD_WIZARDS_STAFF  equ 18
CARD_BORINS_ARMOR   equ 19
CARD_WIZARDS_CLOAK  equ 20
CARD_SPELL_RING     equ 21
CARD_WAND_OF_MAGIC  equ 22
CARD_RING_FORTITUDE equ 23
CARD_RING_RETURN    equ 24
CARD_ROD_TELEKIN    equ 25

CARD_POTION_HEALING equ 26      ; potions - drunk once, then gone
CARD_POTION_DEFENSE equ 27
CARD_POTION_STRENGTH equ 28
CARD_ELIXIR_OF_LIFE equ 29
CARD_HEROIC_BREW    equ 30

;        NAME              DESCR_STR                 ACT COST  ART  SLOT         ATK DEF TARGET          TARGET_KIND                      RESIST       FLAGS
cards:
    Card globals.STR_NONE,             card_data.t_card_none,            0, 0,    0,   SLOT_NONE,   1, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, 0

    ; the armoury - everything with a price
    Card globals.STR_DAGGER,           card_data.t_card_dagger,          0, 25,   1,   SLOT_WEAPON, 1, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_THROWN
    Card globals.STR_STAFF,            card_data.t_card_staff,           0, 100,  2,   SLOT_WEAPON, 1, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_DIAGONAL | CF_NO_SHIELD
    Card globals.STR_SHORTSWORD,       card_data.t_card_shortsword,      0, 150,  3,   SLOT_WEAPON, 2, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_HANDAXE,          card_data.t_card_handaxe,         0, 200,  4,   SLOT_WEAPON, 2, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_THROWN
    Card globals.STR_BROADSWORD,       card_data.t_card_broadsword,      0, 250,  5,   SLOT_WEAPON, 3, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_LONGSWORD,        card_data.t_card_longsword,       0, 350,  6,   SLOT_WEAPON, 3, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD | CF_DIAGONAL
    Card globals.STR_CROSSBOW,         card_data.t_card_crossbow,        0, 350,  7,   SLOT_WEAPON, 3, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD | CF_RANGED
    Card globals.STR_BATTLE_AXE,       card_data.t_card_battle_axe,      0, 450,  8,   SLOT_WEAPON, 4, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD | CF_NO_SHIELD
    Card globals.STR_HELMET,           card_data.t_card_helmet,          0, 125,  9,   SLOT_HELMET, 0, 1, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_SHIELD,           card_data.t_card_shield,          0, 150,  10,  SLOT_SHIELD, 0, 1, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_CHAIN_MAIL,       card_data.t_card_chain_mail,      0, 500,  11,  SLOT_ARMOR,  0, 1, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_BRACERS,          card_data.t_card_bracers,         0, 550,  12,  SLOT_ARMOR,  0, 1, ST_NONE,        TK_ANY,                          RESIST_NONE, 0
    Card globals.STR_TOOL_KIT,         card_data.t_card_tool_kit,        0, 250,  13,  SLOT_NONE,   0, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, 0
    Card globals.STR_HOLY_WATER,       card_data.t_card_holy_water,      0, 400,  14,  SLOT_NONE,   0, 0, ST_ONE_MONSTER, TK_KIND | KIND_UNDEAD,           RESIST_NONE, CF_ONE_USE

    ; artifacts - found, never sold
    Card globals.STR_ORCS_BANE,        card_data.t_card_orcs_bane,       0, 0,    15,  SLOT_WEAPON, 2, 0, ST_NONE,        TK_TYPE | globals.MT_ORC,                RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_PHANTOM_BLADE,    card_data.t_card_phantom_blade,   0, 0,    16,  SLOT_WEAPON, 1, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_ONCE_QUEST
    Card globals.STR_FORTUNES_SWORD,   card_data.t_card_fortunes_sword,  0, 0,    17,  SLOT_WEAPON, 3, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD | CF_DIAGONAL | CF_ONCE_QUEST
    Card globals.STR_WIZARDS_STAFF,    card_data.t_card_wizards_staff,   0, 0,    18,  SLOT_WEAPON, 2, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_WIZARD_ONLY | CF_DIAGONAL
    Card globals.STR_BORINS_ARMOR,     card_data.t_card_borins_armor,    0, 0,    19,  SLOT_ARMOR,  0, 2, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_NO_WIZARD
    Card globals.STR_WIZARDS_CLOAK,    card_data.t_card_wizards_cloak,   0, 0,    20,  SLOT_ARMOR,  0, 1, ST_NONE,        TK_ANY,                          RESIST_NONE, CF_WIZARD_ONLY
    Card globals.STR_SPELL_RING,       card_data.t_card_spell_ring,      0, 0,    21,  SLOT_NONE,   0, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, 0
    Card globals.STR_WAND_OF_MAGIC,    card_data.t_card_wand_of_magic,   0, 0,    22,  SLOT_NONE,   0, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, 0
    Card globals.STR_RING_FORTITUDE,   card_data.t_card_ring_fortitude,  0, 0,    23,  SLOT_NONE,   0, 0, ST_NONE,        TK_ANY,                          RESIST_NONE, 0
    Card globals.STR_RING_RETURN,      card_data.t_card_ring_return,     0, 0,    24,  SLOT_NONE,   0, 0, ST_SELF,        TK_ANY,                          RESIST_NONE, CF_ONE_USE
    Card globals.STR_ROD_TELEKIN,      card_data.t_card_rod_telekin,     0, 0,    25,  SLOT_NONE,   0, 0, ST_ONE_MONSTER, TK_ANY,                          RESIST_MIND, CF_ONCE_QUEST

    ; potions - drunk once, then gone
    Card globals.STR_POTION_HEALING,   card_data.t_card_potion_healing,  0, 0,    26,  SLOT_NONE,   0, 0, ST_ONE_HERO,    TK_ANY,                          RESIST_NONE, CF_ONE_USE
    Card globals.STR_POTION_DEFENSE,   card_data.t_card_potion_defense,  0, 0,    27,  SLOT_NONE,   0, 2, ST_ONE_HERO,    TK_ANY,                          RESIST_NONE, CF_ONE_USE
    Card globals.STR_POTION_STRENGTH,  card_data.t_card_potion_strength, 0, 0,    28,  SLOT_NONE,   2, 0, ST_ONE_HERO,    TK_ANY,                          RESIST_NONE, CF_ONE_USE
    Card globals.STR_ELIXIR_OF_LIFE,   card_data.t_card_elixir_of_life,  0, 0,    29,  SLOT_NONE,   0, 0, ST_ONE_HERO,    TK_ANY,                          RESIST_NONE, CF_ONE_USE
    Card globals.STR_HEROIC_BREW,      card_data.t_card_heroic_brew,     0, 0,    30,  SLOT_NONE,   0, 0, ST_SELF,        TK_ANY,                          RESIST_NONE, CF_ONE_USE
cards_end:

CARD_COUNT          equ (cards_end - cards) / Card

; The armoury is the head of the table, so the shop can stop as soon as COST
; runs out instead of walking the artifacts every redraw.
CARD_FOR_SALE_FIRST equ CARD_DAGGER
CARD_FOR_SALE_LAST  equ CARD_HOLY_WATER

    ASSERT CARD_COUNT == 31

;-----------------------------------------------------------------------------
; get_card - A = a CARD_ constant, returns IY = that Card. Corrupts HL and DE.
;
; IY for the same reason get_monster_type uses it: the hero is in IX and the
; card in their hand is in IY, both at once.
;
;       ld a, (ix+Hero.WEAPON_ACTIVE)
;       call get_card
;       ld a, (iy+Card.ATTACK)          ; dice the weapon is worth
;-----------------------------------------------------------------------------
get_card:
                ld l, a
                ld h, 0
                add hl, hl
                add hl, hl
                add hl, hl
                add hl, hl                      ; index * 16 - 31 rows is 496,
                ld de, cards                    ; which is why this is not
                add hl, de                      ; three adds in A
                push hl
                pop iy
                ret

    ENDMODULE
