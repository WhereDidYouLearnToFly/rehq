    org Text
    MODULE text

set_screen:
            ld a, 2               ; upper screen
            call OPEN_SCREEN      ; open channel
            ret

print_de_string:
            call PRINT_STRING_FROM_DE
            ret

print_bc_number:
            call PUT_DEC_BC_TO_STACK ; stack number in bc.
            call PRINT_TOP_STACK     ; display top of calc. stack.
            ret 

setxy_from_bc:
            ld a,$16        ; ASCII control code for AT.
            rst $10         ; print it.
            ld a,c          ; vertical position.
            rst $10         ; print it.
            ld a,b          ; y coordinate.
            rst $10         ; print it.
            ret

nolimit_teletype_print_hl:              ;set LINE_LENGTH to zero
            ld a, 0
            ld (LINE_LENGTH), a
teletype_print_hl:                      ;if this is entry point then LINE_LENGTH should have max char number in the line
            ld a, (LINE_LENGTH)
            cp 0
            jr z, .nolimit
            ld b, a
            ld a, (BYTE_TEMP0)
            cp b
            jr nz, .next_char
            ld a, 0
            ld (BYTE_TEMP0), a
            jr .stop_char
.next_char:
            inc a
            ld (BYTE_TEMP0), a
.nolimit:            
            ld a, (hl)                  ;читаем из строки очередной символ
            and a                       ;проверяем на 0
            jr nz, .teletype_print0      ;если нет, продолжаем
.stop_char: ld a, ' '                   ;стираем изображение
            rst   $10                   ; «печатающего квадрата»
            ret                         ;выход
.teletype_print0:
            rst   $10                   ;печатаем считанный символ
            inc   hl                    ;перемещаем указатель текущего
                                        ;символа на следующий
            push  hl                    ;сохраняем в стеке значение указателя
            ld    de, PCURSOR           ;формируем изображение
            ld    bc, 4                 ;«печатающего квадрата»
            call  PRINT_STRING_FROM_DE
            call  DROP_TEMP_ATTRIBS     ;сбрасываем временные атрибуты
; ------------------
; Задержка
teletype_beep:
            call beeper.click_beep
            ld   bc, (DELAY)           ;пауза 1 - это 5/50 секунды
            call PAUSE_BC              ;вызов подпрограммы PAUSE
; ------------------
            pop   hl                    ;восстанавливаем значение указателя
            jr    teletype_print_hl     ;переход на начало цикла
;
PCURSOR: .db  17,4,' ',8

multiline_teletype_print_hl:            ;initial pos bc, a - line limit
            ld (LINE_LENGTH), a
            ld (WORD_TEMP0), bc
.iter0:
            call setxy_from_bc
            call teletype_print_hl      ;type until 0 or LINE_LENGTH
            ld bc, (WORD_TEMP0)
            inc c
            ld (WORD_TEMP0), bc
            ld a, (BYTE_TEMP0)
            cp 0
            jr z, .iter0
            ld a, 0
            ld (BYTE_TEMP0), a
            ret

running_line_1pix:  ;a - length, b - x pos, c - line number
            ld (BYTE_TEMP0), a
            call screen.get_pix_addr_by_bc
            ld a, (BYTE_TEMP0)
            dec a
            add a, l
            ld l, a
            ld c, 8
.loop0:
            ld d, 0
            ld a, (BYTE_TEMP0)
            ld b, a
            and a
            push hl
.loop1:     
            rl (hl)
            dec hl
            djnz .loop1
            rl d
            ; front
            pop hl
            ld a, (hl)
            or d
            ld (hl), a
            ; to back
            inc h
            dec c
            jr nz, .loop0
            ret

; Print a single character out to a screen address
;  A: Character to print
;  D: Character Y position
;  E: Character X position
;
print_char_pix:
                    ld hl, 0x3C00                ; Character set bitmap data in ROM
                    ld hl, (FONT_POINTER)        ; Character set bitmap data in ROM
;
                    ld b,0                       ; BC = character code
                    ld c, a
                    sla c                        ; Multiply by 8 by shifting
                    rl b
                    sla c
                    rl b
                    sla c
                    rl b
                    add hl, bc                   ; And add to HL to get first byte of character
                    call get_char_address_pix    ; Get screen position in DE
; Loop counter - 8 bytes per character
                    ld b, 8
.print_char_pix_L1: 
                    ld a,(hl)               ; Get the byte from the ROM into A
                    ld (de),a               ; Stick A onto the screen
                    inc hl                  ; Goto next byte of character
                    inc d                   ; Goto next line on screen
                    djnz .print_char_pix_L1     ; Loop around whilst it is Not Zero (NZ)
                    ret

; Get screen address from a character (X,Y) coordinate
; D = Y character position (0-23)
; E = X character position (0-31)
; Returns screen address in DE
;
get_char_address_pix:
                    ld a,d
                    and %00000111
                    rra
                    rra
                    rra
                    rra
                    or e
                    ld e,a
                    ld a,d
                    and %00011000
                    or %01000000
                    ld d,a
                    ret

;
;  My print routine
;  HL: Address of the string
;  D: Character Y position
;  E: Character X position
;
print_string_pix:
                    ld a, (hl)                  ; Get the character
                    cp 0                        ; CP with 0
                    ret z                       ; Ret if it is zero
                    inc hl                      ; Skip to next character in string
                    cp 32                       ; CP with 32 (space character)
                    jr c, print_string_pix ; If < 32, then don't ouput
                    push de                     ; Save screen coordinates
                    push hl                     ; And pointer to text string
                    call print_char_pix    ; Print the character
                    pop hl                      ; Pop pointer to text string
                    pop de                      ; Pop screen coordinates
                    inc e                       ; Inc to the next character position on screen
                    jr print_string_pix    ; Loop

thaw_line:  ;d - length, e - iterations, b - x pos (char num), c - y pos (line num)
            push de
            call screen.get_pix_addr_by_bc     ;hl has address to bc
            ld (WORD_TEMP0), hl
            pop de
            ld a, d
            ld (LINE_LENGTH), a                ;store length
            ld a, e
            ld (BYTE_TEMP0), a
            ld de, 0
.thaw_loop:
            ld (BYTE_TEMP0), a
            ld bc, 5
            call PAUSE_BC
            ld hl, (WORD_TEMP0)
            ld c, 8
.loop0:
            ld a, (LINE_LENGTH)
            ld b, a
            push hl
.loop1:                                      ;thaw one interation
            push bc
            ld a, (hl)
            ld b, a
            ld a, (de)
            and b
            ld (hl), a
            inc hl
            inc de
            pop bc
            djnz .loop1                    ;loop1_end
            pop hl
            inc h
            dec c
            jr nz, .loop0                  ;loop0_end
            ld a, (BYTE_TEMP0)
            dec a
            jr nz, .thaw_loop
            ret


DELAY: dw 1
WORD_TEMP0: dw 0
BYTE_TEMP0: db 0
LINE_LENGTH: db 0

    ENDMODULE