   STRUCT MenuNode
ID             BYTE $00
TEXT_ID        BYTE $00
ACTION         WORD $00
BOX            WORD $00
   ENDS

   STRUCT MenuString
SIZE             BYTE $00
    ;Text
   ENDS

   STRUCT MenuList
ACTIVE           BYTE $00
SELECTED_IDX     BYTE $00
NODE_NUM         BYTE $00
STRING_NUM       BYTE $00
POS_X            BYTE $00
POS_Y            BYTE $00
DEF_ATTR         BYTE $00
SEL_ATTR         BYTE $00
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