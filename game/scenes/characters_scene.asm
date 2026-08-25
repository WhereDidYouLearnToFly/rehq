    SLOT 3
    PAGE 0
    org $C2CF
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

CHAR_MENU_COL          equ 20
CHAR_MENU_ROW          equ 18

TITLE_ATTR             equ 107q
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

RENAME_TEXT:            MENU_STRING "RENAME"
LOAD_TEXT:              MENU_STRING "LOAD"
SAVE_TEXT:              MENU_STRING "SAVE"
BACK_TEXT:              MENU_STRING "BACK"

node_char_rename:         MenuNode 0, 0,    rename_action,      0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR
node_char_load:           MenuNode 1, 1,    load_action,        0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR
node_char_save:           MenuNode 2, 2,    save_action,        0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR
node_char_back:           MenuNode 3, 3,    back_action,        0, PLAYER_MENU_ITEM_ATTR,       PLAYER_MENU_SELECTED_ATTR

char_menu:              MenuList 0, 1, 0, 4, 4, CHAR_MENU_COL, CHAR_MENU_ROW
.nodes:                 dw node_char_rename, node_char_load, node_char_save, node_char_back
.strings:               dw RENAME_TEXT, LOAD_TEXT
                        dw SAVE_TEXT, BACK_TEXT

;=============================================================================
; Actions
;=============================================================================

switch_to_char_menu:
                ld a, 1
                ld (char_menu), a
                ld a, 0
                ld (char_list), a

                ld  hl, char_menu
                push hl
                pop ix
                ld (ix + MenuList.SELECTED_IDX), a
                call menus.init_menu
                call menus.draw_items

                ret

switch_to_char_list:
                ld a, 0
                ld (char_menu), a
                ld a, 1
                ld (char_list), a

                ld a, 0
                ld bc, $1412
                ld de, $0804
                call attribs.fill_rectangle

                ld  hl, char_list
                call menus.init_menu

                ret

barbarian_action:
                call get_and_show_barbarian_name
                call switch_to_char_menu
                ret

dwarf_action:
                call get_and_show_dwarf_name
                call switch_to_char_menu
                ret

elf_action:
                call get_and_show_elf_name
                call switch_to_char_menu
                ret

wizard_action:
                call get_and_show_wizard_name
                call switch_to_char_menu
                ret

end_action:
                ld hl, game.set_main_menu_scene
                ld (next_scene), hl
                ret

rename_action:
                jp start_rename

; The two that cannot be done here. Every action above runs inside the frame
; interrupt, because that is where menus.keyboard_process runs, and a tape
; block takes seconds - so these do not do the work, they ask for it, and loop
; picks the job up between frames. See the Tape section below.
load_action:
                ld hl, do_load
                ld (pending), hl
                ret

save_action:
                ld hl, do_save
                ld (pending), hl
                ret

back_action:
                call switch_to_char_list
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
        ld hl, globals.STR_BARBARIAN
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
        ld hl, globals.STR_DWARF
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
        ld hl, globals.STR_ELF
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
        ld hl, globals.STR_WIZARD
        ld (hero_name_ptr), hl
;
        jp get_and_show_hero

;=============================================================================
; Name entry
;=============================================================================
; The four variables above are exactly what a text field needs, and the char
; list action has already filled them in for the hero it selected, so renaming
; looks nothing up: hero_name_ptr is the buffer, hero_pos one column in is
; where it prints, hero_attr is its colour.
;
; The field is the gap inside FLAG_GRFX - NAME_LEN cells at column
; hero_pos+1 - so a name is typed where it is going to live, and an empty flag
; is the whole cue that it is waiting for one. While it is being typed the
; MenuString is held at full width and padded with spaces, so printing it
; erases whatever DELETE took back; only on ENTER does the length become what
; was actually typed.
;
; Printing goes through ATTR_T and repaints the cells it covers, so nothing
; here has to touch attributes at all.
;=============================================================================
NAME_LEN        equ globals.NAME_MAX

edit_len:       .db 0                   ; characters typed so far
edit_backup:    ds NAME_LEN + 1         ; the whole MenuString, length byte and
                                        ; all - the old name may be shorter

start_rename:
                call keys.flush         ; or the FIRE that opened the field
                                        ; arrives inside it
                ld hl, (hero_name_ptr)
                ld de, edit_backup
                ld bc, NAME_LEN + 1
                ldir                    ; BREAK, and an empty ENTER, put it back
;
                xor a
                ld (edit_len), a
                ld (char_menu), a       ; ACTIVE - nothing below is selected
                call menus.draw_items   ; while the keys belong to the field
;
                ld hl, name_input
                ld (input_handler), hl
                ; falls through: the flag goes empty and the player types

blank_name:
                ld hl, (hero_name_ptr)
                ld (hl), NAME_LEN       ; full width for as long as it is being
                inc hl                  ; typed into
                ld b, NAME_LEN
                ld a, ' '
.next:
                ld (hl), a
                inc hl
                djnz .next
                ; falls through
draw_name:
                ld a, (hero_attr)
                ld (PAPER_INK_BRIGHT1), a
                ld hl, (hero_name_ptr)
                ld bc, (hero_pos)
                inc b                   ; inside the flag
                jp menus.print_menu_string

;-----------------------------------------------------------------------------
; name_input - one frame of the field. Installed in input_handler, so it is
; the only thing reading the keyboard while it is up.
;-----------------------------------------------------------------------------
name_input:
                call keys.read_char
                and a
                ret z                   ; nothing typed this frame
;
                cp keys.ENTER
                jr z, commit_name
                cp keys.BREAK
                jr z, cancel_name
                cp keys.DELETE
                jr z, .delete
;
                cp ' '                  ; letters, digits and space are the
                ret c                   ; whole alphabet of a name
                ld b, a
                ld a, (edit_len)
                cp NAME_LEN
                ret nc                  ; full - DELETE is the only way on
                call name_cell
                ld (hl), b
                inc a
                jr .redraw
.delete:
                ld a, (edit_len)
                and a
                ret z
                dec a
                call name_cell
                ld (hl), ' '
.redraw:
                ld (edit_len), a
                jr draw_name

;-----------------------------------------------------------------------------
; name_cell - a = index, returns hl = that byte of the name. a survives, so
; the caller can store the new length straight after.
;-----------------------------------------------------------------------------
name_cell:
                push af
                ld hl, (hero_name_ptr)
                inc hl                  ; past MenuString.SIZE
                add a, l                ; without assuming a name sits clear of
                ld l, a                 ; a page boundary
                adc a, h
                sub l
                ld h, a
                pop af
                ret

commit_name:
                ld a, (edit_len)
                and a
                jr z, cancel_name       ; typing nothing keeps the old name
                ld hl, (hero_name_ptr)
                ld (hl), a              ; the name is as long as what was
                jr finish_name          ; typed, not as wide as the field
cancel_name:
                ld hl, edit_backup
                ld de, (hero_name_ptr)
                ld bc, NAME_LEN + 1
                ldir
finish_name:
                ld hl, menu_input
                ld (input_handler), hl
                ld a, 1
                ld (char_menu), a       ; the sub-menu takes the keys back
                call draw_name
                jp menus.draw_items

;=============================================================================
; Tape
;=============================================================================
; SAVE and LOAD cannot happen where the other actions happen.
; menus.keyboard_process runs inside the frame interrupt, so an action runs
; there too - and a tape block takes seconds, during which the ROM hands
; interrupts back and this scene would be entered again on top of itself.
;
; So the action does not do the work: it writes the address of the job into
; pending, and loop - which is ordinary code, running between frames - picks
; it up. next_scene already works this way for leaving the scene; this is the
; same idea for staying in it and taking a while about it.
;
; While a job is running the menu must not act on keys either. That is what
; input_handler is for: it goes to ignore_input for the duration, the same
; swap the name field does, so the player mashing keys at PRESS ANY KEY does
; not also walk the menu underneath.
;=============================================================================
PROMPT_COL      equ 1
PROMPT_ROW      equ 20                  ; two lines under the char list, and
KEY_ROW         equ 21                  ; left of the sub-menu at column 20
PROMPT_WIDTH    equ 20
PROMPT_ATTR     equ 107q

TAPE_RECORD_TEXT:   MENU_STRING "PUT TAPE ON RECORD"
TAPE_PLAY_TEXT:     MENU_STRING "PLAY THE TAPE"
SAVING_TEXT:        MENU_STRING "SAVING..."
LOADING_TEXT:       MENU_STRING "LOADING..."
DONE_TEXT:          MENU_STRING "DONE"
FAILED_TEXT:        MENU_STRING "TAPE ERROR"
PRESS_KEY_TEXT:     MENU_STRING "PRESS ANY KEY"

; One per slot, eight characters, and nothing to do with what the hero is
; called. The player can rename a character between saving and loading it, and
; a file that can no longer be found under the name it was filed under is
; worse than a file with a dull name. The typed name is inside the block.
FILENAMES:      db "HQBARBAR"
                db "HQDWARF "
                db "HQELF   "
                db "HQWIZARD"

pending:        .dw 0                   ; a job for loop, or 0

;-----------------------------------------------------------------------------
; run_pending - called from loop. Runs at most one job per frame.
;-----------------------------------------------------------------------------
run_pending:
                ld hl, (pending)
                ld a, h
                or l
                ret z
                ld de, 0
                ld (pending), de        ; cleared before the job runs, so a job
                jp (hl)                 ; is free to ask for another one

ignore_input:
                ret

;-----------------------------------------------------------------------------
; The two jobs. Both are the same four steps: ask, do it, say how it went,
; put the screen back.
;-----------------------------------------------------------------------------
do_save:
                call tape_begin         ; the menu stops listening
                ld hl, TAPE_RECORD_TEXT
                call status
                call ask                ; and nothing happens until the player
                                        ; says the recorder is running
                ld hl, SAVING_TEXT
                call status
;
                call tape_args          ; which hero, and what it is filed as
                call saveload.save_hero     ; seconds, not frames
                jr tape_end             ; carry says how it went

do_load:
                call tape_begin
                ld hl, TAPE_PLAY_TEXT
                call status
                call ask
                ld hl, LOADING_TEXT
                call status
;
                call tape_args
                call saveload.load_hero     ; this one can also come back false
                                        ; having read something that is not a
                                        ; character for this slot
                ; falls through to tape_end

;-----------------------------------------------------------------------------
; tape_begin / tape_end - entered with CF from the job: 1 it worked, 0 it did
; not. Between them the menu is inert and the prompt lines are ours.
;-----------------------------------------------------------------------------
tape_end:
                ld hl, DONE_TEXT
                jr c, .report
                ld hl, FAILED_TEXT
.report:
                call status
                call ask
                call clear_prompt
;
                call audio.resume       ; from the top; there is no way to
                                        ; pick a driver block up mid-tune
;
                call get_and_show_hero  ; a load has changed the name, and the
                                        ; stats behind it
                ld hl, menu_input
                ld (input_handler), hl
                ld a, 1
                ld (char_menu), a
                jp menus.draw_items

tape_begin:
                call audio.stop         ; the ROM holds interrupts off for
                                        ; the whole block, so nothing would
                                        ; advance the tune - it would drone
                ld hl, ignore_input
                ld (input_handler), hl
                xor a
                ld (char_menu), a       ; ACTIVE - nothing is selected while
                jp menus.draw_items     ; the menu is not listening

;-----------------------------------------------------------------------------
; tape_args - set up the call: ix = the hero, hl = its name, a = its slot, and
; the filename for that slot.
;
; The slot is the char list's own selection. Nothing else needs to remember
; which hero the sub-menu was opened on, because that is exactly what the
; selection already is - and END, the fifth entry, never opens it.
;-----------------------------------------------------------------------------
tape_args:
                ld a, (char_list + MenuList.SELECTED_IDX)
                ld (slot), a
;
                add a, a                ; slot * 8 into the name table
                add a, a
                add a, a
                ld hl, FILENAMES
                add a, l
                ld l, a
                adc a, h
                sub l
                ld h, a
                call storage.set_filename
;
                ld ix, (hero_ptr)
                ld hl, (hero_name_ptr)
                ld a, (slot)
                ret

slot:           .db 0

;-----------------------------------------------------------------------------
; status      - hl = a MenuString, printed on the prompt line.
; ask         - PRESS ANY KEY under it, and wait for one.
; clear_prompt- both lines back to the background.
;
; Clearing is done with attributes, not spaces: setting a cell to ink 0 on
; paper 0 hides whatever characters are in it, which is the same trick
; switch_to_char_list uses on the sub-menu, and it is one write per cell
; instead of a print.
;-----------------------------------------------------------------------------
status:
                push hl
                ld b, 0
                ld c, PROMPT_ROW
                ld de, (PROMPT_WIDTH << 8) | 1
                xor a
                call attribs.fill_rectangle
                pop hl
                ld a, PROMPT_ATTR
                ld (PAPER_INK_BRIGHT1), a
                ld b, PROMPT_COL
                ld c, PROMPT_ROW
                jp menus.print_menu_string

ask:
                ld a, PROMPT_ATTR
                ld (PAPER_INK_BRIGHT1), a
                ld hl, PRESS_KEY_TEXT
                ld b, PROMPT_COL
                ld c, KEY_ROW
                call menus.print_menu_string
;
                call keys.flush         ; the key that got here is not the key
                call keys.wait_char     ; that answers this
;
                ld b, 0                 ; take the line back, so the next
                ld c, KEY_ROW           ; prompt does not sit under a stale
                ld de, (PROMPT_WIDTH << 8) | 1
                xor a
                jp attribs.fill_rectangle

clear_prompt:
                ld b, 0
                ld c, PROMPT_ROW
                ld de, (PROMPT_WIDTH << 8) | 2
                xor a
                jp attribs.fill_rectangle

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
        call audio.frame        ; before run_pending: a tape job blocks
                                ; for seconds, and the frame it would
                                ; have skipped is the one that stops the
                                ; music cleanly
        call run_pending                ; whatever the menu asked for that was
                                        ; too slow to do in the interrupt
        ld hl, (next_scene)
        ld a, h
        or l                            ; only a null pointer is zero. Adding the
        jp z, game.loop                 ; two halves read $01FF as null as well
        jp (hl)

; The scene has two things that read the keys - the menus, and the name field -
; and only ever one of them at a time, so which is which is a pointer rather
; than a flag tested twice a frame. The same shape as input.selected_controls
; and the pscene_ words in game.asm.
;
; The field handler does not call input.check_input at all, which is the point:
; under the QAOP scheme the direction keys are letters, so a menu that stayed
; live underneath would walk itself while a name was being typed.
interrupt:
        ld hl, (input_handler)
        jp (hl)

menu_input:
        call input.check_input
        ld a, (mouse.in_use)
        cp 0
        jr nz, .mouse
        call menus.keyboard_process
.mouse:
        ret

input_handler: .dw menu_input

next_scene: .dw 0

        ENDMODULE
