    SLOT 3
    PAGE 0
    org $C09B
    MODULE main_menu

MENU_PLAY               equ 0
MENU_SHOP               equ 1
MENU_CHARACTERS         equ 2
MENU_SETTINGS           equ 3

; the two titles are printed by label, not by node, so they are not in
; the string array and have no TEXT_ id - these index .strings below.
TEXT_PLAY_GAME          equ 0
TEXT_BUY_EQUIPMENT      equ 1
TEXT_CHARACTERS         equ 2
TEXT_SETTINGS           equ 3

ITEMS_COL               equ 10
ITEMS_ROW               equ 7

TITLE_ATTR                  equ 106q
PACK_ATTR                   equ 107q
ITEM_ATTR                   equ 103q
SELECTED_ATTR               equ 104q

STRING_HEROQUEST:       MENU_STRING "HEROQUEST"
STRING_PACK_TITLE:      MENU_STRING "THE CRYPT OF PERPETUAL DARKNESS"
PLAY_GAME_TEXT:         MENU_STRING "PLAY GAME"
BUY_EQUIPMENT_TEXT:     MENU_STRING "ALCHEMIST'S SHOP"
CHARACTERS_TEXT:        MENU_STRING "CHARACTERS"
SETTINGS_TEXT:          MENU_STRING "SETTINGS"

node_play:              MenuNode MENU_PLAY,       TEXT_PLAY_GAME,       play_action, 0, ITEM_ATTR, SELECTED_ATTR
node_shop:              MenuNode MENU_SHOP,       TEXT_BUY_EQUIPMENT,   shop_action, 0, ITEM_ATTR, SELECTED_ATTR
node_characters:        MenuNode MENU_CHARACTERS, TEXT_CHARACTERS,      characters_action, 0, ITEM_ATTR, SELECTED_ATTR
node_settings:          MenuNode MENU_SETTINGS,   TEXT_SETTINGS,        settings_action, 0, ITEM_ATTR, SELECTED_ATTR

main_list:              MenuList 1, 1, 0, 4, 4, ITEMS_COL, ITEMS_ROW
.nodes:                 dw node_play, node_shop, node_characters, node_settings
.strings:               dw PLAY_GAME_TEXT, BUY_EQUIPMENT_TEXT
                        dw CHARACTERS_TEXT, SETTINGS_TEXT

;=============================================================================
; Actions
;=============================================================================

play_action:
                call audio.stop                 ; the quest starts its own
                ;ld hl, game.set_game_play_scene
                ;ld (next_scene), hl
                ret

shop_action:
                ld hl, game.set_shop_scene
                ld (next_scene), hl
                ret

characters_action:
                ld hl, game.set_chartacters_scene
                ld (next_scene), hl
                ret

settings_action:
                ld hl, game.set_settings_scene
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
                    ld a, audio.TUNE_MENU       ; already playing if we came
                    call audio.play_tune        ; back from another menu
;
                    ret

deinit:
        ret

loop:
        ld hl, (next_scene)
        ld a, h
        or l                            ; only a null pointer is zero. Adding the
        jp z, game.loop                 ; two halves read $01FF as null as well
        jp (hl)

interrupt:
        call input.check_input
        ld a, (mouse.in_use)
        cp 0
        jr nz, .mouse
        call menus.keyboard_process
.mouse:
        ret

next_scene: .dw 0

        ENDMODULE
