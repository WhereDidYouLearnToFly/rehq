   STRUCT MenuNode
ID             BYTE $00
TEXT_ID        BYTE $00
ACTION         WORD $00
BOX            WORD $00
DEF_ATTR       BYTE $00
SEL_ATTR       BYTE $00
   ENDS

   STRUCT MenuString
SIZE             BYTE $00
    ;Text
   ENDS

   STRUCT MenuList
ACTIVE           BYTE $00
STEP             BYTE $00
SELECTED_IDX     BYTE $00
NODE_NUM         BYTE $00
STRING_NUM       BYTE $00
POS_X            BYTE $00
POS_Y            BYTE $00
   ;Nodes Pointers
   ;Strings Pointers
   ENDS

;-----------------------------------------------------------------------------
; MENU_STRING - lays down a MenuString: the length byte, then the text.
;
; The length is measured, not typed, so renaming an entry cannot leave a stale
; count behind - which is the whole reason the size lives in the string
; instead of at the call site.
;
; Needs a global label in front of it, both to be referable and because the
; two local labels below hang off it:
;
;     PLAY_GAME_TEXT:     MENU_STRING "PLAY GAME"
;-----------------------------------------------------------------------------
    MACRO MENU_STRING text?
                MenuString .end - .text
.text:          db text?
.end:
    ENDM
;-----------------------------------------------------------------------------
; ItemMenu - a menu whose entries are cards, not hand-written nodes.
;
; The armoury already knows every item's name and price: items.cards carries
; NAME_STR and COST, and the shop list is that table walked with the unpriced
; rows skipped. So an entry here is a card id, and the menu reads the rest.
; Writing a MenuNode per item would restate, in a second place, what the card
; table already says - and the two would drift the first time a price changed.
;
; The layout is columns. Each ItemColumn is a run of consecutive card ids
; drawn one per row, name left-aligned at X and price right-aligned so its
; last digit lands on COST_X:
;
;      WEAPONS      COST  ARMOUR      COST     <- HEADER, on the row above
;      DAGGER         25  HELMET       125
;      STAFF         100  SHIELD       150
;      ^X            ^COST_X
;
; "COST" is right-aligned to COST_X too, so one number fixes both.
;-----------------------------------------------------------------------------
    STRUCT ItemColumn
FIRST       BYTE $00        ; first card id; the run is FIRST..FIRST+COUNT-1
COUNT       BYTE $00
X           BYTE $00        ; column of the first character of the name
COST_X      BYTE $00        ; column of the LAST digit of the price
HEADER      WORD $0000      ; a MenuString, drawn one row above the first entry
    ENDS

;-----------------------------------------------------------------------------
; The selection is a column and a row, not a flat index, because that is what
; makes the four directions trivial: up/down is SEL_ROW +-1 wrapped inside one
; column, left/right is SEL_COL +-1 with the row clamped to the new column.
;
; SEL_ROW == that column's COUNT is the exit entry. Every column has that one
; extra row, so "down off the bottom" reaches END from anywhere and needs no
; special case - only the drawing knows the exit is somewhere else on screen.
;
; The ItemColumns follow this record back to back; init works out where from
; the struct size, so adding a field here cannot rot the offset.
;-----------------------------------------------------------------------------
    STRUCT ItemMenu
ACTIVE      BYTE $00        ; 0 = drawn, but nothing highlighted and no input
SEL_COL     BYTE $00
SEL_ROW     BYTE $00        ; == COUNT of SEL_COL means the exit entry
COL_NUM     BYTE $00        ; how many ItemColumns follow
POS_Y       BYTE $00        ; row of the first entry; headers go one row above
EXIT_X      BYTE $00        ; the exit entry is drawn on its own, not in a
EXIT_Y      BYTE $00        ; column, because that is where it looks right
EXIT_TEXT   WORD $0000      ; a MenuString
EXIT_ACTION WORD $0000      ; run when the exit entry is chosen
BUY_ACTION  WORD $0000      ; run with A = card id when an item is chosen
HERO        BYTE $00        ; party slot 0-3 whose gold is shown and spent
GOLD_X      BYTE $00        ; column of the LAST digit of the gold readout
GOLD_Y      BYTE $00
DEF_ATTR    BYTE $00
SEL_ATTR    BYTE $00
POOR_ATTR   BYTE $00        ; name AND price, when this hero cannot afford it
HDR_ATTR    BYTE $00        ; the column headers
COST_ATTR   BYTE $00        ; the price, when it is affordable and unselected;
                            ; DEF_ATTR is the name only, so the two can differ
GOLD_ATTR   BYTE $00        ; the purse
    ENDS
