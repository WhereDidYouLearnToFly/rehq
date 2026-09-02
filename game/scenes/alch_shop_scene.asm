    SLOT 3
    PAGE 0
    org $C7FC
    MODULE shop_menu

;-----------------------------------------------------------------------------
; The layout, measured off screenshots/screenshot_20260825_202813.scr. The
; panel is one row taller than that mock-up because items.cards holds eight
; weapons, not the Armoury card's seven, so the left column needs eight rows:
;
; Rows:  2 HEROQUEST, 4-8 the character list, 10 ALCHEMIST'S SHOP, 12-22 the
; panel. Nothing shares a row with anything else.
;
;   12  +-WEAPONS------COST--ARMOUR------COST-+  the headers sit ON the top
;   13  | DAGGER         25  HELMET       125 |  border row, which is what
;   ..  |                                     |  POS_Y-1 means in an ItemMenu
;   20  | BATTLE AXE    450                   |
;   21  |                END           <=0000 |
;   22  +-------------------------------------+
;
; A name has 11 columns on the left and 10 on the right before it reaches the
; price. CHAIN MAIL and HOLY WATER are exactly 10.
;-----------------------------------------------------------------------------
; The character list runs down the left from ITEMS_ROW, one row per hero plus
; END - rows 4-8. BARBARIAN is nine characters, so it reaches column 8, which
; is where the shop title used to start: the two collided on row 4, and moving
; the list down to row 6 to dodge that just moved the collision onto the panel
; instead. The title now sits on its own row between the two.
ITEMS_COL               equ 0
ITEMS_ROW               equ 4
ITEMS_ROWS              equ 5                           ; four heroes and END

TITLE_ROW               equ 2
SHOP_TITLE_ROW          equ PANEL_ROW - 2               ; clear of both
SHOP_TITLE_COL          equ 8                           ; (32-16)/2, centred

PANEL_COL               equ 0
PANEL_ROW               equ 12
PANEL_W                 equ 32
PANEL_H                 equ 11

SHOP_ROW                equ PANEL_ROW + 1               ; first item row
; The footer must land on row 21 or above: printing goes through the ROM's
; upper-screen channel, which is rows 0-21, and an AT below that raises
; "Integer out of range" rather than printing. The bottom border may sit on
; row 22 because draw8x8_panel writes the bitmap itself and never asks the ROM.
FOOTER_ROW              equ PANEL_ROW + PANEL_H - 2     ; END and the purse
WEAPONS_X               equ 1
WEAPONS_COST_X          equ 15                          ; the last digit
ARMOUR_X                equ 17
ARMOUR_COST_X           equ 30
EXIT_X                  equ ARMOUR_X
PURSE_X                 equ 25                          ; the coin, then '='
GOLD_X                  equ 30                          ; the last digit

; Attributes read out of the .scr rather than guessed at. PAPER is black
; everywhere except under the cursor, which inverts to a cyan bar.
SHOP_TITLE_ATTR         equ 107q
ITEM_ATTR               equ 102q
SELECTED_ATTR           equ 105q

HDR_ATTR                equ $05                         ; cyan
NAME_ATTR               equ 104q                        ; bright green
PRICE_ATTR              equ 107q                        ; bright white
CURSOR_ATTR             equ $28                         ; black on cyan
POOR_ATTR               equ $02                         ; red - out of reach
PURSE_ATTR              equ $06                         ; yellow
FRAME_ATTR              equ $03                         ; magenta, the panel

SHOP_TITLE_TEXT:        MENU_STRING "ALCHEMIST'S SHOP"
WEAPONS_TEXT:           MENU_STRING "WEAPONS"
ARMOUR_TEXT:            MENU_STRING "ARMOUR"
SHOP_END_TEXT:          MENU_STRING "END"
PURSE_TEXT:             MENU_STRING "<="                ; '<' is the coin glyph

node_barbarian:         MenuNode 0, 0,  select_barbarian_action,  0, ITEM_ATTR, SELECTED_ATTR
node_dwarf:             MenuNode 1, 1,  select_dwarf_action,      0, ITEM_ATTR, SELECTED_ATTR
node_elf:               MenuNode 2, 2,  select_elf_action,        0, ITEM_ATTR, SELECTED_ATTR
node_wizard:            MenuNode 3, 3,  select_wizard_action,     0, ITEM_ATTR, SELECTED_ATTR
node_end:               MenuNode 4, 4,  exit_action,              0, ITEM_ATTR, SELECTED_ATTR

shop_list:              MenuList 1, 1, 0, 5, 5, ITEMS_COL, ITEMS_ROW
.nodes:                 dw node_barbarian, node_dwarf, node_elf, node_wizard, node_end
.strings:               dw characters_menu.BARBARIAN_TEXT, characters_menu.DWARF_TEXT, characters_menu.ELF_TEXT
                        dw characters_menu.WIZARD_TEXT, characters_menu.END_TEXT

;-----------------------------------------------------------------------------
; The armoury. Both columns are runs of consecutive card ids, because that is
; how items.cards is laid out - the weapons first, then what is worn and
; carried - so a column is a first id and a count, and not one name or price
; is repeated here. Change a price in items.asm and the shop shows the new one.
;-----------------------------------------------------------------------------
shop_menu:              ItemMenu 0, 0, 0, 2, SHOP_ROW, EXIT_X, FOOTER_ROW, SHOP_END_TEXT, focus_chars, buy_action, 0, GOLD_X, FOOTER_ROW, NAME_ATTR, CURSOR_ATTR, POOR_ATTR, HDR_ATTR, PRICE_ATTR, PURSE_ATTR
.weapons:               ItemColumn items.CARD_DAGGER, 8, WEAPONS_X, WEAPONS_COST_X, WEAPONS_TEXT
.armour:                ItemColumn items.CARD_HELMET, 6, ARMOUR_X, ARMOUR_COST_X, ARMOUR_TEXT

;=============================================================================
; Actions
;=============================================================================

;=============================================================================
; Who has the keys
;=============================================================================
; Two menus on one screen and one input stream, so something has to say which
; of them a keypress belongs to. That something is input_handler: the scene's
; interrupt jumps through it rather than testing a flag, the same way
; characters_scene swaps its own handler while a name is being typed.
;
; The character list starts with the keys. Choosing a hero says who is buying
; and hands the keys down to the armoury; END in the armoury hands them back
; up; END in the character list leaves the shop.
;
; ACTIVE on each menu is a separate thing and only decides which one draws a
; cursor - both stay on screen throughout. Both are asked to redraw on a
; switch because the highlight moves between them, and asked rather than told
; because all of this runs inside the interrupt.
;=============================================================================

select_barbarian_action:
                ld a, 0
                jr set_buyer
select_dwarf_action:
                ld a, 1
                jr set_buyer
select_elf_action:
                ld a, 2
                jr set_buyer
select_wizard_action:
                ld a, 3
set_buyer:
                ld (shop_menu + ItemMenu.HERO), a
;
focus_items:
                xor a
                ld (shop_list + MenuList.ACTIVE), a
                ld a, 1
                ld (shop_menu + ItemMenu.ACTIVE), a
                ld hl, item_input
                jr set_focus
;
focus_chars:
                ld a, 1
                ld (shop_list + MenuList.ACTIVE), a
                xor a
                ld (shop_menu + ItemMenu.ACTIVE), a
                ld hl, char_input
set_focus:
                ld (input_handler), hl
                call menus.request_redraw       ; the cursor left one menu and
                jp item_menu.mark_all           ; arrived in the other, so both

char_input:
                jp menus.keyboard_process
item_input:
                jp item_menu.keyboard_process

input_handler:  dw char_input

;-----------------------------------------------------------------------------
; buy_action - A = the card id under the cursor when FIRE was pressed.
;
; Nothing is sold back, so this is a subtraction and a slot write rather than a
; transaction. The affordability test is repeated here instead of trusted from
; the colour: the menu draws what it cannot afford in red, but the action must
; not depend on having been drawn.
;-----------------------------------------------------------------------------
buy_action:
                ld (bought_card), a
                ld a, (shop_menu + ItemMenu.HERO)
                call globals.get_hero           ; ix = the buyer
                ld a, (bought_card)
                call items.get_card             ; iy = what they are buying

                ld e, (iy + Card.COST)
                ld d, (iy + Card.COST + 1)
                ld l, (ix + Hero.GOLD)
                ld h, (ix + Hero.GOLD + 1)
                or a
                sbc hl, de
                jr c, .done                     ; not enough gold
                ld (ix + Hero.GOLD), l
                ld (ix + Hero.GOLD + 1), h

                ; SLOT_* are the offsets of the four equipment fields counted
                ; from the first, so equipping is an add and not a four-way
                ; branch - see the note in game/globals.i.
                ld a, (iy + Card.SLOT)
                and a
                jr z, .done                     ; SLOT_NONE: carried, not worn
                dec a                           ; SLOT_WEAPON is the first
                ld e, a
                ld d, 0
                push ix
                pop hl
                ld bc, Hero.WEAPON_ACTIVE
                add hl, bc
                add hl, de
                ld a, (bought_card)
                ld (hl), a                      ; whatever it replaced is gone;
                                                ; there is no selling it back
.done:
                ld iy, music.SYSVARS            ; get_card left a card row here
                jp item_menu.mark_all           ; the purse changed, so every
                                                ; price may have crossed from
                                                ; affordable to not - but ask
                                                ; for it, this runs in the
                                                ; interrupt

bought_card:    db 0

exit_action:
                ld hl, game.set_main_menu_scene
                ld (next_scene), hl
                ret

;=============================================================================
; Scene
;=============================================================================

init:
;
                    ld a, 0
                    call screen.cls_a
;
                    ld hl, 0
                    ld (next_scene), hl
;
                    ld  hl, shop_list
                    call menus.init_menu
;
                    ld a, 1                     ; the character list has the
                    ld (shop_list + MenuList.ACTIVE), a
                    xor a                       ; keys to begin with; all three
                    ld (shop_menu + ItemMenu.ACTIVE), a
                    ld hl, char_input           ; of these outlive the scene,
                    ld (input_handler), hl      ; so re-entering must reset them
;
                    ld a, main_menu.TITLE_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, main_menu.STRING_HEROQUEST
                    ld bc, $0b00 | TITLE_ROW
                    call menus.print_menu_string
;
                    ; Colour the panel's cells before drawing into them.
                    ; cls_a above filled every attribute with 0 - black ink on
                    ; black paper - and draw8x8_panel writes the bitmap and
                    ; nothing else, so without this the frame is drawn in black
                    ; on black and simply does not appear. The text inside is
                    ; visible either way, because ROM printing sets the
                    ; attribute of each cell it writes.
                    ld bc, (PANEL_COL << 8) | PANEL_ROW     ; b = column, c = row
                    ld de, (PANEL_W << 8) | PANEL_H         ; d = width,  e = height
                    ld a, FRAME_ATTR
                    call attribs.fill_rectangle
;
                    ld hl, globals.hq_frame
                    ld bc, (PANEL_COL << 8) | PANEL_ROW
                    ld de, (PANEL_W << 8) | PANEL_H
                    call draw.draw8x8_panel
;
                    ld a, SHOP_TITLE_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, SHOP_TITLE_TEXT
                    ld bc, (SHOP_TITLE_COL << 8) | SHOP_TITLE_ROW
                    call menus.print_menu_string
;
                    call menus.draw_items
;
                    ; The purse label never changes, so it is painted once here
                    ; and item_menu redraws only the digits beside it.
                    ld a, PURSE_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, PURSE_TEXT
                    ld bc, (PURSE_X << 8) | FOOTER_ROW
                    call menus.print_menu_string
;
                    ld hl, shop_menu
                    call item_menu.init
                    jp item_menu.draw

deinit:
        ret

loop:
        call item_menu.tick             ; the shop's own menu, for the same
                                        ; reason game.loop calls menus.tick -
                                        ; drawing belongs out here, not in the
                                        ; interrupt. Not in game.loop because
                                        ; this is the only scene that has one.
        ld hl, (next_scene)
        ld a, h
        or l
        jp z, game.loop
        jp (hl)

interrupt:
        call input.check_input
        ld a, (mouse.in_use)
        cp 0
        jr nz, .mouse
        ld hl, (input_handler)          ; a pointer, not a flag - see above
        jp (hl)
.mouse:
        ret

next_scene: .dw 0

        ENDMODULE
