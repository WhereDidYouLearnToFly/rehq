    SLOT 3
    PAGE 0
    org $C093
    MODULE main_menu

;=============================================================================
; The menu description
;
; Three tables, all of it data. A node carries an ID and an index into the
; string table - it does not hold its own text, so retitling an entry, or
; translating the whole menu, touches only the strings.
;
; The list is the two counts followed by the pointer arrays in the order the
; struct documents: nodes first, then strings. The arrays are separate because
; they are different lengths - the two title strings are not menu entries and
; have no node.
;
; TEXT_ID indexes the string array, never the node array. Index by name and
; the distinction stays harmless.
;=============================================================================

; What an entry does. The handler is looked up from this, since MenuNode no
; longer carries a pointer.
MENU_PLAY               equ 0
MENU_SHOP               equ 1
MENU_CHARACTERS         equ 2
MENU_SETTINGS           equ 3

; Position in the string array below.
TEXT_HEROQUEST          equ 0
TEXT_PACK_TITLE         equ 1
TEXT_PLAY_GAME          equ 2
TEXT_BUY_EQUIPMENT      equ 3
TEXT_CHARACTERS         equ 4
TEXT_SETTINGS           equ 5

; Where the entries land. Placeholder layout - one column, evenly spaced.
ITEMS_COL               equ 10
ITEMS_ROW               equ 7

TITLE_ATTR                  equ 106q        ; bright yellow ink on black
PACK_ATTR                   equ 107q        ; bright white ink on black
ITEM_ATTR                   equ 103q
SELECTED_ATTR               equ 104q

STRING_HEROQUEST:       MENU_STRING "HEROQUEST"
STRING_PACK_TITLE:      MENU_STRING "THE CRYPT OF PERPETUAL DARKNESS"
PLAY_GAME_TEXT:         MENU_STRING "PLAY GAME"
BUY_EQUIPMENT_TEXT:     MENU_STRING "ALCHEMIST'S SHOP"
CHARACTERS_TEXT:        MENU_STRING "CHARACTERS"
SETTINGS_TEXT:          MENU_STRING "SETTINGS"

node_play:              MenuNode MENU_PLAY,       TEXT_PLAY_GAME,       0, 0
node_shop:              MenuNode MENU_SHOP,       TEXT_BUY_EQUIPMENT    0, 0
node_characters:        MenuNode MENU_CHARACTERS, TEXT_CHARACTERS       0, 0
node_settings:          MenuNode MENU_SETTINGS,   TEXT_SETTINGS         0, 0

main_list:              MenuList 1, 0, 4, 6, ITEMS_COL, ITEMS_ROW, ITEM_ATTR, SELECTED_ATTR
.nodes:                 dw node_play, node_shop, node_characters, node_settings
.strings:               dw STRING_HEROQUEST, STRING_PACK_TITLE
                        dw PLAY_GAME_TEXT, BUY_EQUIPMENT_TEXT
                        dw CHARACTERS_TEXT, SETTINGS_TEXT

;=============================================================================
; Scene
;=============================================================================

init:
                    ld  hl, main_list
                    call menus.init_menu
;
                    ld a, TITLE_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, STRING_HEROQUEST
                    ld bc, $0b02
                    call menus.print_menu_string
;
                    ld a, PACK_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, STRING_PACK_TITLE
                    ld bc, $0004
                    call menus.print_menu_string
;
                    call menus.draw_items
;
                    ret

deinit:
        ret

loop:
        ret

interrupt:
        call input.check_input
        ld a, (mouse.in_use)
        cp 0
        jr nz, .mouse
        call menus.keyboard_process
.mouse:
        ret

        ENDMODULE
