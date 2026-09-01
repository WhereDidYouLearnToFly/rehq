    SLOT 3
    PAGE 0
    org $C7FC
    MODULE shop_menu

MENU_BUY                equ 0
MENU_SELL               equ 1
MENU_EXIT               equ 2

TEXT_BUY                equ 0
TEXT_SELL               equ 1
TEXT_EXIT               equ 2

ITEMS_COL               equ 5
ITEMS_ROW               equ 4

TITLE_ATTR              equ 107q
ITEM_ATTR               equ 103q
SELECTED_ATTR           equ 104q

SHOP_TITLE_TEXT:        MENU_STRING "ALCHEMIST'S SHOP"
BUY_TEXT:               MENU_STRING "BUY"
SELL_TEXT:              MENU_STRING "SELL"
EXIT_TEXT:              MENU_STRING "EXIT"

node_buy:               MenuNode MENU_BUY,  TEXT_BUY,  buy_action,  0, ITEM_ATTR, SELECTED_ATTR
node_sell:              MenuNode MENU_SELL, TEXT_SELL, sell_action, 0, ITEM_ATTR, SELECTED_ATTR
node_exit:              MenuNode MENU_EXIT, TEXT_EXIT, exit_action, 0, ITEM_ATTR, SELECTED_ATTR

shop_list:              MenuList 1, 1, 0, 3, 3, ITEMS_COL, ITEMS_ROW
.nodes:                 dw node_buy, node_sell, node_exit
.strings:               dw BUY_TEXT, SELL_TEXT, EXIT_TEXT

;=============================================================================
; Actions
;=============================================================================

buy_action:
                ret

sell_action:
                ret

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
                    ld a, TITLE_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, SHOP_TITLE_TEXT
                    ld bc, $0802
                    call menus.print_menu_string
;
                    call menus.draw_items
;
                    ret

deinit:
        ret

loop:
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
        call menus.keyboard_process
.mouse:
        ret

next_scene: .dw 0

        ENDMODULE
