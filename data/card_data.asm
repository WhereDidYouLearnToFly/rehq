;=============================================================================
; card_data - the rules text off the face of every card, in a bank of its own
;=============================================================================
; Placement:  SLOT 3, PAGE 4, org $C000 - bank 4, borrowed. Nothing here is
;             ever executed and nothing here may be read unless the bank is
;             paged in; game/card_text.asm is what does that, and is the only
;             thing that should be reaching in.
; Depends on: MENU_STRING, from game/menus/menu_structures.i.
; Namespace:  MODULE card_data. Card.DESCR_STR and Spell.DESCR_STR in
;             game/globals.asm point straight at the labels below.
;
; GENERATED - transcribed from the scans in assets/original_cards/cards and
; re-wrapped to WRAP columns. Fix the transcription, not the wrapping.
;
; A description is a line count and then that many MenuStrings, back to back:
;
;       db  4
;       MENU_STRING "Weapon. This wide blade gives"
;       MENU_STRING "you the attack strength of 3"
;       ...
;
; so drawing one is the count in B and print_menu_string down the rows, and
; nothing has to word-wrap at runtime. The text is mixed case on purpose: the
; font has real lowercase glyphs (bin/ui/fonts/hq_font_basic.bin covers ASCII
; 32-127) and twenty-eight columns of capitals is hard to read. The card
; TITLES stay uppercase - those are the MENU_STRINGs in globals.asm.
;
; Bank 4 rather than 6: 6 is the music, and its free tail is smaller than this
; and shares the .ay's stack. Bank 4 is uncontended and otherwise unused. 1, 3
; and 7 are contended, and 7 is also the shadow screen.
;=============================================================================

WRAP                equ 28         ; columns the text was wrapped to

                    SLOT 3
                    PAGE 4
                    org $C000
                    MODULE card_data


;-----------------------------------------------------------------------------
; The equipment, potion and artifact cards
;-----------------------------------------------------------------------------
t_card_none:
                    db 2
                    MENU_STRING "No weapon. Bare hands are"
                    MENU_STRING "worth 1 Attack die."

t_card_dagger:
                    db 6
                    MENU_STRING "Weapon. This sharp knife"
                    MENU_STRING "gives you the attack"
                    MENU_STRING "strength of 1 combat die. A"
                    MENU_STRING "dagger can also be thrown at"
                    MENU_STRING "any monster you can see but"
                    MENU_STRING "is lost once it is thrown."

t_card_staff:
                    db 8
                    MENU_STRING "Weapon. This long, sturdy,"
                    MENU_STRING "wooden staff gives you the"
                    MENU_STRING "attack strength of 1 combat"
                    MENU_STRING "die. Because of its length,"
                    MENU_STRING "the staff enables you to"
                    MENU_STRING "attack diagonally. You may"
                    MENU_STRING "not use a shield when using"
                    MENU_STRING "this weapon."

t_card_shortsword:
                    db 5
                    MENU_STRING "Weapon. This short sword"
                    MENU_STRING "gives you the attack"
                    MENU_STRING "strength of 2 combat dice."
                    MENU_STRING "May not be used by the"
                    MENU_STRING "wizard."

t_card_handaxe:
                    db 6
                    MENU_STRING "Weapon. This handaxe allows"
                    MENU_STRING "you to roll 2 Attack dice."
                    MENU_STRING "It can also be thrown at any"
                    MENU_STRING "monster in your line of"
                    MENU_STRING "sight but is lost once it is"
                    MENU_STRING "thrown."

t_card_broadsword:
                    db 5
                    MENU_STRING "Weapon. This wide blade"
                    MENU_STRING "gives you the attack"
                    MENU_STRING "strength of 3 combat dice."
                    MENU_STRING "May not be used by the"
                    MENU_STRING "wizard."

t_card_longsword:
                    db 7
                    MENU_STRING "Weapon. This long blade"
                    MENU_STRING "gives you the attack"
                    MENU_STRING "strength of 3 combat dice."
                    MENU_STRING "Because of its length, the"
                    MENU_STRING "longsword enables you to"
                    MENU_STRING "attack diagonally. May not"
                    MENU_STRING "be used by the wizard."

t_card_crossbow:
                    db 10
                    MENU_STRING "Weapon. This long-range"
                    MENU_STRING "weapon gives you the attack"
                    MENU_STRING "strength of 3 combat dice."
                    MENU_STRING "You may fire at any monster"
                    MENU_STRING "that you can see. However,"
                    MENU_STRING "you cannot fire at a monster"
                    MENU_STRING "that is adjacent to you. You"
                    MENU_STRING "have an unlimited supply of"
                    MENU_STRING "arrows. May not be used by"
                    MENU_STRING "the wizard."

t_card_battle_axe:
                    db 7
                    MENU_STRING "Weapon. This heavy, double-"
                    MENU_STRING "edged axe gives you the"
                    MENU_STRING "attack strength of 4 combat"
                    MENU_STRING "dice. You may not use a"
                    MENU_STRING "shield when using this"
                    MENU_STRING "weapon. May not be used by"
                    MENU_STRING "the wizard."

t_card_helmet:
                    db 4
                    MENU_STRING "Armor. This protective"
                    MENU_STRING "headpiece gives you 1 extra"
                    MENU_STRING "Defend die. May not be worn"
                    MENU_STRING "by the wizard."

t_card_shield:
                    db 6
                    MENU_STRING "Armor. This hand-held armor"
                    MENU_STRING "gives you 1 extra Defend"
                    MENU_STRING "die. May not be used with"
                    MENU_STRING "the battle axe or the staff."
                    MENU_STRING "May not be used by the"
                    MENU_STRING "wizard."

t_card_chain_mail:
                    db 6
                    MENU_STRING "Armor. This light metal"
                    MENU_STRING "armor gives you 1 extra"
                    MENU_STRING "Defend die. May be combined"
                    MENU_STRING "with the helmet and/or"
                    MENU_STRING "shield. May not be worn by"
                    MENU_STRING "the wizard."

t_card_bracers:
                    db 5
                    MENU_STRING "Armor. These hardened"
                    MENU_STRING "leather bracers give you 1"
                    MENU_STRING "extra Defend die. May be"
                    MENU_STRING "combined with the helmet"
                    MENU_STRING "and/or shield."

t_card_tool_kit:
                    db 5
                    MENU_STRING "Disarm Traps. This tool kit"
                    MENU_STRING "gives you a 50 percent"
                    MENU_STRING "chance to disarm any"
                    MENU_STRING "searched-for-and-found (but"
                    MENU_STRING "unsprung) trap."

t_card_holy_water:
                    db 6
                    MENU_STRING "You may use the holy water"
                    MENU_STRING "instead of attacking. It"
                    MENU_STRING "kills any undead creature"
                    MENU_STRING "(skeleton, zombie, or"
                    MENU_STRING "mummy). The card is then"
                    MENU_STRING "discarded after use."

t_card_orcs_bane:
                    db 6
                    MENU_STRING "Weapon. When using this"
                    MENU_STRING "magical shortsword, you roll"
                    MENU_STRING "2 Attack die. You may attack"
                    MENU_STRING "twice if attacking an orc."
                    MENU_STRING "May not be used by the"
                    MENU_STRING "wizard."

t_card_phantom_blade:
                    db 7
                    MENU_STRING "Weapon. This ornate dagger"
                    MENU_STRING "gives you 1 Attack die. Once"
                    MENU_STRING "per quest, when you attack"
                    MENU_STRING "with the dagger your target"
                    MENU_STRING "may not defend themselves as"
                    MENU_STRING "the weapon passes through"
                    MENU_STRING "their armor."

t_card_fortunes_sword:
                    db 7
                    MENU_STRING "Weapon. This long blade"
                    MENU_STRING "enables you to attack"
                    MENU_STRING "diagonally and gives you 3"
                    MENU_STRING "Attack dice. Once per quest,"
                    MENU_STRING "the hero may use its power"
                    MENU_STRING "to reroll 1 Attack die. May"
                    MENU_STRING "not be used by the wizard."

t_card_wizards_staff:
                    db 6
                    MENU_STRING "This long ancient staff"
                    MENU_STRING "glows with a soft blue"
                    MENU_STRING "light. It can be used only"
                    MENU_STRING "by the wizard, giving them 2"
                    MENU_STRING "Attack dice and the ability"
                    MENU_STRING "to strike diagonally."

t_card_borins_armor:
                    db 9
                    MENU_STRING "Armor. This magical suit of"
                    MENU_STRING "plate mail gives you 2 extra"
                    MENU_STRING "Defend dice. Unlike normal"
                    MENU_STRING "plate mail, this mysterious,"
                    MENU_STRING "ultralight metal armor does"
                    MENU_STRING "not slow down its wearer."
                    MENU_STRING "May be combined with the"
                    MENU_STRING "helmet and/or shield. May"
                    MENU_STRING "not be used by the wizard."

t_card_wizards_cloak:
                    db 6
                    MENU_STRING "This magical cloak made of"
                    MENU_STRING "shimmery fabric is covered"
                    MENU_STRING "with mystical runes. It can"
                    MENU_STRING "be worn only by the wizard,"
                    MENU_STRING "giving them 1 extra Defend"
                    MENU_STRING "die."

t_card_spell_ring:
                    db 8
                    MENU_STRING "This ring enables a hero to"
                    MENU_STRING "cast one spell two times"
                    MENU_STRING "(not simultaneously). At the"
                    MENU_STRING "beginning of a quest, the"
                    MENU_STRING "wearer of this ring must"
                    MENU_STRING "declare which of their"
                    MENU_STRING "spells are stored in the"
                    MENU_STRING "ring."

t_card_wand_of_magic:
                    db 5
                    MENU_STRING "This magical wand allows a"
                    MENU_STRING "hero to cast two separate"
                    MENU_STRING "and different spells on"
                    MENU_STRING "their turn instead of one"
                    MENU_STRING "single spell."

t_card_ring_fortitude:
                    db 2
                    MENU_STRING "This magical ring raises a"
                    MENU_STRING "hero's Body Points by 1."

t_card_ring_return:
                    db 6
                    MENU_STRING "When invoked, this magical"
                    MENU_STRING "ring returns all heroes that"
                    MENU_STRING "the ring wearer can see to"
                    MENU_STRING "the starting point of the"
                    MENU_STRING "quest. It can only be used"
                    MENU_STRING "once."

t_card_rod_telekin:
                    db 10
                    MENU_STRING "Once per quest, you may use"
                    MENU_STRING "this rod to trap a monster"
                    MENU_STRING "within magical force. A"
                    MENU_STRING "trapped monster misses its"
                    MENU_STRING "next turn. The spell can be"
                    MENU_STRING "resisted immediately by the"
                    MENU_STRING "monster rolling 1 red die"
                    MENU_STRING "for each of their Mind"
                    MENU_STRING "Points. If a 6 is rolled, it"
                    MENU_STRING "resists the spell."

t_card_potion_healing:
                    db 11
                    MENU_STRING "In a bundle of rags, you"
                    MENU_STRING "find a small bottle of"
                    MENU_STRING "bluish liquid. You can drink"
                    MENU_STRING "this healing potion at any"
                    MENU_STRING "time, restoring the number"
                    MENU_STRING "of Body Points equal to a"
                    MENU_STRING "roll of 1 red die. You"
                    MENU_STRING "cannot, however, exceed your"
                    MENU_STRING "starting number of Body"
                    MENU_STRING "Points. This may only be"
                    MENU_STRING "used once."

t_card_potion_defense:
                    db 8
                    MENU_STRING "Amidst a collection of old"
                    MENU_STRING "bottles, you find a small"
                    MENU_STRING "vial containing a clear"
                    MENU_STRING "liquid. You can drink this"
                    MENU_STRING "potion at any time, giving"
                    MENU_STRING "you 2 extra combat dice the"
                    MENU_STRING "next time you defend. This"
                    MENU_STRING "may only be used once."

t_card_potion_strength:
                    db 7
                    MENU_STRING "You find a small purple"
                    MENU_STRING "flask. You can drink this"
                    MENU_STRING "strange smelling liquid at"
                    MENU_STRING "any time, enabling you to"
                    MENU_STRING "roll 2 extra combat dice the"
                    MENU_STRING "next time you attack. This"
                    MENU_STRING "may only be used once."

t_card_elixir_of_life:
                    db 6
                    MENU_STRING "This small bottle of pearly"
                    MENU_STRING "liquid brings a dead hero"
                    MENU_STRING "back to life, restoring all"
                    MENU_STRING "of their Body and Mind"
                    MENU_STRING "Points. This potion can only"
                    MENU_STRING "be used once."

t_card_heroic_brew:
                    db 7
                    MENU_STRING "You are surprised to find a"
                    MENU_STRING "leather bag hanging on the"
                    MENU_STRING "wall. If you drink its"
                    MENU_STRING "contents before you attack,"
                    MENU_STRING "you can make two attacks"
                    MENU_STRING "instead of one. This may"
                    MENU_STRING "only be used once."


;-----------------------------------------------------------------------------
; The spell cards
;-----------------------------------------------------------------------------
t_spell_genie:
                    db 8
                    MENU_STRING "This spell conjures up a"
                    MENU_STRING "genie who does one of the"
                    MENU_STRING "following: opens any door on"
                    MENU_STRING "the board (revealing what"
                    MENU_STRING "lies beyond) or uses 5"
                    MENU_STRING "combat dice to attack any"
                    MENU_STRING "monster within your line of"
                    MENU_STRING "sight."

t_spell_swift_wind:
                    db 7
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. Its powerful burst"
                    MENU_STRING "of energy enables that hero"
                    MENU_STRING "to roll twice as many red"
                    MENU_STRING "dice as normal the next time"
                    MENU_STRING "they move."

t_spell_tempest:
                    db 5
                    MENU_STRING "This spell creates a small"
                    MENU_STRING "whirlwind that envelops one"
                    MENU_STRING "monster of your choice. That"
                    MENU_STRING "monster then misses its next"
                    MENU_STRING "turn."

t_spell_heal_body:
                    db 7
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. Its magical power"
                    MENU_STRING "immediately restores up to 4"
                    MENU_STRING "lost Body Points, but does"
                    MENU_STRING "not give a hero more than"
                    MENU_STRING "their starting number."

t_spell_pass_thru_rock:
                    db 10
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. That hero may then"
                    MENU_STRING "move through walls on their"
                    MENU_STRING "next move. They may move"
                    MENU_STRING "through as many walls as"
                    MENU_STRING "their dice roll allows."
                    MENU_STRING "Caution! If a hero ends"
                    MENU_STRING "their move in solid rock,"
                    MENU_STRING "they are trapped forever!"

t_spell_rock_skin:
                    db 7
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. That hero may"
                    MENU_STRING "throw 1 extra combat die"
                    MENU_STRING "when defending. The spell is"
                    MENU_STRING "broken when the hero suffers"
                    MENU_STRING "1 Body Point of damage."

t_spell_ball_of_flame:
                    db 8
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one monster, enveloping"
                    MENU_STRING "it in a ball of fire. It"
                    MENU_STRING "inflicts 2 Body Points of"
                    MENU_STRING "damage. The monster then"
                    MENU_STRING "rolls 2 red dice. For each 5"
                    MENU_STRING "or 6 rolled, the damage is"
                    MENU_STRING "reduced by 1 point."

t_spell_courage:
                    db 8
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. The next time that"
                    MENU_STRING "hero attacks, they may roll"
                    MENU_STRING "2 extra combat dice. The"
                    MENU_STRING "spell is broken the moment a"
                    MENU_STRING "monster is no longer in the"
                    MENU_STRING "hero's line of sight."

t_spell_fire_of_wrath:
                    db 7
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one monster, blasting it"
                    MENU_STRING "with flames. It inflicts 1"
                    MENU_STRING "Body Point of damage, unless"
                    MENU_STRING "the monster can immediately"
                    MENU_STRING "roll a 5 or 6 using 1 red"
                    MENU_STRING "die."

t_spell_sleep:
                    db 12
                    MENU_STRING "This spell puts a monster"
                    MENU_STRING "into a deep sleep so it"
                    MENU_STRING "cannot move, attack, or"
                    MENU_STRING "defend itself. The spell can"
                    MENU_STRING "be broken at once or on a"
                    MENU_STRING "future turn by a monster"
                    MENU_STRING "rolling 1 red die for each"
                    MENU_STRING "of its Mind Points. If a 6"
                    MENU_STRING "is rolled, the spell is"
                    MENU_STRING "broken. May not be used"
                    MENU_STRING "against mummies, zombies, or"
                    MENU_STRING "skeletons."

t_spell_veil_of_mist:
                    db 6
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. On the hero's next"
                    MENU_STRING "move, they may move unseen"
                    MENU_STRING "through spaces that are"
                    MENU_STRING "occupied by monsters."

t_spell_water_healing:
                    db 7
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, including"
                    MENU_STRING "yourself. Contact with this"
                    MENU_STRING "revitalizing water restores"
                    MENU_STRING "up to 4 lost Body Points but"
                    MENU_STRING "does not give a hero more"
                    MENU_STRING "than their starting number."

t_spell_cloud_of_dread:
                    db 12
                    MENU_STRING "This spell paralyzes all"
                    MENU_STRING "heroes located in the same"
                    MENU_STRING "room or corridor. A"
                    MENU_STRING "paralyzed hero is unable to"
                    MENU_STRING "move, attack, or defend"
                    MENU_STRING "themself. The spell can be"
                    MENU_STRING "broken at once or on a"
                    MENU_STRING "future turn by each victim"
                    MENU_STRING "rolling 1 red die for each"
                    MENU_STRING "of their Mind Points. By"
                    MENU_STRING "rolling a 6, the hero frees"
                    MENU_STRING "themself."

t_spell_command:
                    db 11
                    MENU_STRING "This spell puts any one hero"
                    MENU_STRING "under Zargon's control. The"
                    MENU_STRING "spell can be broken"
                    MENU_STRING "immediately or on a future"
                    MENU_STRING "turn by the hero rolling 1"
                    MENU_STRING "red die for each of their"
                    MENU_STRING "Mind Points. If a 6 is"
                    MENU_STRING "rolled, the spell is broken."
                    MENU_STRING "Until then, Zargon can move"
                    MENU_STRING "the hero as a monster and"
                    MENU_STRING "attack other heroes."

t_spell_escape:
                    db 7
                    MENU_STRING "This spell allows the"
                    MENU_STRING "spellcaster to disappear and"
                    MENU_STRING "instantly teleport to a"
                    MENU_STRING "secret destination known"
                    MENU_STRING "only to Zargon. This safe"
                    MENU_STRING "place is marked on the quest"
                    MENU_STRING "map."

t_spell_fear:
                    db 9
                    MENU_STRING "This spell causes any one"
                    MENU_STRING "hero to become so fearful"
                    MENU_STRING "that they may only use 1"
                    MENU_STRING "Attack die. The spell can be"
                    MENU_STRING "broken by the hero on a"
                    MENU_STRING "future turn by rolling 1 red"
                    MENU_STRING "die for each of their Mind"
                    MENU_STRING "Points. If a 6 is rolled,"
                    MENU_STRING "the spell is broken."

t_spell_firestorm:
                    db 12
                    MENU_STRING "This spell creates a roomful"
                    MENU_STRING "of fire that inflicts 3 Body"
                    MENU_STRING "Points of damage on all"
                    MENU_STRING "heroes and monsters in the"
                    MENU_STRING "same room with the"
                    MENU_STRING "spellcaster. The spellcaster"
                    MENU_STRING "is unaffected. All victims"
                    MENU_STRING "immediately roll 2 red dice."
                    MENU_STRING "For each 5 or 6 rolled, the"
                    MENU_STRING "damage is reduced by 1"
                    MENU_STRING "point. Not used in"
                    MENU_STRING "corridors."

t_spell_lightning_bolt:
                    db 9
                    MENU_STRING "This spell may be cast in a"
                    MENU_STRING "horizontal, vertical, or"
                    MENU_STRING "diagonal direction. The bolt"
                    MENU_STRING "will travel in a straight"
                    MENU_STRING "line until it strikes a wall"
                    MENU_STRING "or closed door. It inflicts"
                    MENU_STRING "2 Body Points of damage on"
                    MENU_STRING "all heroes or monsters that"
                    MENU_STRING "stand in its path."

t_spell_rust:
                    db 6
                    MENU_STRING "This spell causes any one"
                    MENU_STRING "metal sword or helmet to"
                    MENU_STRING "become so thin, brittle, and"
                    MENU_STRING "useless that it can never be"
                    MENU_STRING "used again. Not effective"
                    MENU_STRING "against artifacts."

t_spell_chaos_ball_flame:
                    db 8
                    MENU_STRING "This spell may be cast on"
                    MENU_STRING "any one hero, enveloping"
                    MENU_STRING "them in a ball of fire. It"
                    MENU_STRING "inflicts 2 Body Points of"
                    MENU_STRING "damage. The hero then rolls"
                    MENU_STRING "2 red dice. For each 5 or 6"
                    MENU_STRING "rolled, the damage is"
                    MENU_STRING "reduced by 1 point."

text_end:

BYTES               equ text_end - t_card_none
MAX_BLOCK           equ 320         ; the largest single description, rounded
                                    ; up - game/card_text.asm sizes its buffer
                                    ; from this and asserts it is enough

                    ASSERT BYTES < $4000        ; it has to fit the bank
                    DISPLAY "card text: ", /D, BYTES, " bytes in bank 4"

                    ENDMODULE
