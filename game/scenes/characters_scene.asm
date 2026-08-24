    SLOT 3
    PAGE 0
    org $C2BE
    MODULE characters_menu

MENU_BARBARIAN          equ 0
MENU_DWARF              equ 1
MENU_ELF                equ 2
MENU_WIZARD             equ 3
MENU_END                equ 4

TEXT_BARBARIAN          equ 0
TEXT_DWARF              equ 1
TEXT_ELF                equ 2
TEXT_WIZARD             equ 3
TEXT_END                equ 4

ITEMS_COL               equ 5
ITEMS_ROW               equ 6

TITLE_ATTR              equ 107q
;
BARBARIAN_ITEM_ATTR             equ 103q
BARBARIAN_SELECTED_ATTR         equ 130q
;
DWARF_ITEM_ATTR                 equ 105q
DWARF_SELECTED_ATTR             equ 150q
;
ELF_ITEM_ATTR                   equ 102q
ELF_SELECTED_ATTR               equ 120q
;
WIZARD_ITEM_ATTR                equ 104q
WIZARD_SELECTED_ATTR            equ 140q
;
END_ITEM_ATTR                   equ 107q
END_SELECTED_ATTR               equ 170q
;
PLAYER_MENU_ITEM_ATTR           equ 106q
PLAYER_MENU_SELECTED_ATTR       equ 160q
;
FLAG_LEFT     equ 114
FLAG_RIGHT    equ 115
FLAG_EMPTY    equ 32

FLAG_GRFX: 
            .db 8
            .db FLAG_LEFT
            .db FLAG_EMPTY
            .db FLAG_EMPTY
            .db FLAG_EMPTY
            .db FLAG_EMPTY
            .db FLAG_EMPTY
            .db FLAG_EMPTY
            .db FLAG_RIGHT
;
DEAD_GRFX: MENU_STRING "DEAD"
;
CHOOSE_PLAYER_TEXT:     MENU_STRING "CHOOSE PLAYER"
BARBARIAN_TEXT:         MENU_STRING "BARBARIAN"
DWARF_TEXT:             MENU_STRING "DWARF"
ELF_TEXT:               MENU_STRING "ELF"
WIZARD_TEXT:            MENU_STRING "WIZARD"
END_TEXT:               MENU_STRING "END"

node_barbarian:         MenuNode MENU_BARBARIAN, TEXT_BARBARIAN,  barbarian_action, 0, BARBARIAN_ITEM_ATTR, BARBARIAN_SELECTED_ATTR
node_dwarf:             MenuNode MENU_DWARF,     TEXT_DWARF,      dwarf_action,     0, DWARF_ITEM_ATTR,     DWARF_SELECTED_ATTR
node_elf:               MenuNode MENU_ELF,       TEXT_ELF,        elf_action,       0, ELF_ITEM_ATTR,       ELF_SELECTED_ATTR
node_wizard:            MenuNode MENU_WIZARD,    TEXT_WIZARD,     wizard_action,    0, WIZARD_ITEM_ATTR,    WIZARD_SELECTED_ATTR
node_end:               MenuNode MENU_END,       TEXT_END,        end_action,       0, END_ITEM_ATTR,       END_SELECTED_ATTR

char_list:              MenuList 1, 3, 0, 5, 5, ITEMS_COL, ITEMS_ROW
.nodes:                 dw node_barbarian, node_dwarf, node_elf, node_wizard, node_end
.strings:               dw BARBARIAN_TEXT
                        dw DWARF_TEXT, ELF_TEXT
                        dw WIZARD_TEXT, END_TEXT

RENAME_TEXT:         MENU_STRING "RENAME"
LOAD_TEXT:           MENU_STRING "LOAD"
SAVE_TEXT:           MENU_STRING "SAVE"
BACK_TEXT:           MENU_STRING "BACK"

node_char_rename:         MenuNode 0, 0,    rename_action,      0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR
node_char_load:           MenuNode 1, 1,    load_action,        0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR
node_char_save:           MenuNode 2, 2,    save_action,        0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR
node_char_back:           MenuNode 3, 3,    back_action,        0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR

char_menu:              MenuList 0, 1, 0, 4, 4, ITEMS_COL, ITEMS_ROW
.nodes:                 dw node_char_rename, node_char_load, node_char_save, node_char_back
.strings:               dw RENAME_TEXT, LOAD_TEXT
                        dw SAVE_TEXT, BACK_TEXT

;=============================================================================
; Actions
;=============================================================================

barbarian_action:
                ret

dwarf_action:
                ret

elf_action:
                ret

wizard_action:
                ret

end_action:
                ld hl, game.set_main_menu_scene
                ld (next_scene), hl
                ret

rename_action:
                ret

load_action:
                ret

save_action:
                ret

back_action:
                ret

;=============================================================================
; Scene
;=============================================================================
hero_attr:      .db 00
hero_temp:      .db 00
hero_pos:       .dw 00
hero_ptr:       .dw 00
hero_name_ptr:  .dw 00

show_dead_hero:
        ld a, 107q
        ld (PAPER_INK_BRIGHT1), a
        ld hl, DEAD_GRFX
        call menus.print_menu_string
        ret 

get_and_show_hero:
        ld ix, (hero_ptr)
        ld a, (ix + Hero.FLAGS)
        and CH_ALIVE
        jr z, .dead
;
        ld a, (hero_attr)
        ld (PAPER_INK_BRIGHT1), a
        ld hl, FLAG_GRFX
        ld bc, (hero_pos)
        call menus.print_menu_string
;name
        ld hl, (hero_name_ptr)
        ld bc, (hero_pos)
        inc b
        jp menus.print_menu_string
.dead:
        ld bc, (hero_pos)
        inc b
        jp show_dead_hero

get_and_show_barbarian_name:
        ld hl, globals.barbarian
        ld (hero_ptr), hl
;
        ld a, BARBARIAN_SELECTED_ATTR
        ld (hero_attr), a
;
        ld hl, $1406
        ld (hero_pos), hl
;
        ld hl,globals.STR_BARBARIAN
        ld (hero_name_ptr), hl
;
        jp get_and_show_hero

get_and_show_dwarf_name:
        ld hl, globals.dwarf
        ld (hero_ptr), hl
;
        ld a, DWARF_SELECTED_ATTR
        ld (hero_attr), a
;
        ld hl, $1409
        ld (hero_pos), hl
;
        ld hl,globals.STR_DWARF
        ld (hero_name_ptr), hl
;
        jp get_and_show_hero

get_and_show_elf_name:
        ld hl, globals.elf
        ld (hero_ptr), hl
;
        ld a, ELF_SELECTED_ATTR
        ld (hero_attr), a
;
        ld hl, $140c
        ld (hero_pos), hl
;
        ld hl,globals.STR_ELF
        ld (hero_name_ptr), hl
;
        jp get_and_show_hero


get_and_show_wizard_name:
        ld hl, globals.wizard
        ld (hero_ptr), hl
;
        ld a, WIZARD_SELECTED_ATTR
        ld (hero_attr), a
;
        ld hl, $140f
        ld (hero_pos), hl
;
        ld hl,globals.STR_WIZARD
        ld (hero_name_ptr), hl
;
        jp get_and_show_hero

init:
;
                    ld a, 0
                    call screen.cls_a
;
                    ld hl, 0
                    ld (next_scene), hl
;
                    ld  hl, char_list
                    call menus.init_menu
;
                    ld a, TITLE_ATTR
                    ld (PAPER_INK_BRIGHT1), a
                    ld hl, CHOOSE_PLAYER_TEXT
                    ld bc, $0a02
                    call menus.print_menu_string
;
                    call get_and_show_barbarian_name
                    call get_and_show_dwarf_name
                    call get_and_show_elf_name
                    call get_and_show_wizard_name
;
                    call menus.draw_items
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
