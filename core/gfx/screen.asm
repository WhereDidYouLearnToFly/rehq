    org Screen
    MODULE screen

get_pix_addr_by_bc:                                 ;bc is char x,y
          ld    a,c                               ;номер строки
          call  GET_SCREEN_ADDR_FROM_ALINE        ;получаем в HL начальный адрес
          ld    a,l                               ;берем значение младшего байта адреса
          or    b                                 ;добавляем смещение в 11 байт (знакомест)
          ld    l,a                               ;возвращаем в младший байт
          ret

get_attr_addr_by_bc:                                ;bc is char x,y
          push bc
          ld h, c
          ld d, 32
          call math.imul
          pop bc
          ld d, 0
          ld e, b
          adc hl, de
          ld de, DISPLAY_ATTRS
          adc hl, de
          ret

get_display_table_by_pix_line:                         ;a is pixel line (0-191)
          ld hl, main 
          ld b, 0
          ld c, a
          add hl, bc
          add hl, bc
          ret                                         ;result is hl has pointer to pixel addre

get_pix_addr_by_pix_line:                               ;a is pixel line (0-191)
          call get_display_table_by_pix_line
          ld c, (hl)
          inc hl
          ld b, (hl)
          push bc
          pop hl
          ret

cls:
          ld a, (attrib)         ; blue ink (1) on yellow paper (6*8).
          ld (PAPER_INK_BRIGHT0), a      ; set our screen colours.
          call CLEAR_SCREEN_ROUTINE      ; clear the 
          ld a, (border)
          ld (SYS_BORDER), a
          out ($fe), a                   ; write to port 254.
          ret

clear_pixels:
          di                   ;disable interrupt
          ld (.stack + 1), sp  ;store current stack pointer
          ld hl, 0             ;this value will be stored on stack
          ld sp, 16384 + 6144
          ld c, 3
.loop2:
          ld b, l             ;set B to 0. it causes that DJNZ will repeat 256 times
.loop1:
          push hl             ;store hl on stack
          push hl             ;next
          push hl             ;tkjhese four push instruction stores 8 bytes on stack
          push hl
          djnz .loop1          ;repeat for next 8 bytes
          dec c
          jr nz, .loop2
.stack:
          ld sp, 0            ;parameter will overwritten
          ei

fill_attributes:
          ld hl, 22528          ;pixels 
          ld de, 22528+1        ;pixels + 1
          ld bc, 767            ;pixels area length - 1
          ld a, (attrib)
          ld (hl), a            ;set first byte to '0'
          ldir                  ;copy bytes

scaddr:   ;hl has pointer to addr table
          push hl
          xor a                    ; clear carry flag and accumulator.
          ld d,a                   ; empty de high byte.
          ld a,c                   ; vertical position
          rla                      ; shift left to multiply by 2.
          ld e,a                   ; place this in low byte of de pair.
          rl d                     ; shift top bit into de high byte.
          ;ld hl, screenbuffer_addr ; table of screen addresses.
          add hl,de                ; point to table entry.
          ld e,(hl)                ; low byte of screen address.
          inc hl                   ; point to high byte.
          ld d,(hl)                ; high byte of screen address.
          ld a,b                   ; horizontal position
          rra                      ; divide by two.
          rra                      ; and again for four.
          rra                      ; shift again to divide by eight.
          and 31                   ; mask away rubbish shifted into rightmost bits.
          add a,e                  ; add to address for start of line.
          ld e,a                   ; new value of e register.
          pop hl
          ret                      ; return with screen address in de.


main:
          dw $4000,$4100,$4200,$4300,$4400,$4500,$4600,$4700
          dw $4020,$4120,$4220,$4320,$4420,$4520,$4620,$4720
          dw $4040,$4140,$4240,$4340,$4440,$4540,$4640,$4740
          dw $4060,$4160,$4260,$4360,$4460,$4560,$4660,$4760
          dw $4080,$4180,$4280,$4380,$4480,$4580,$4680,$4780
          dw $40a0,$41a0,$42a0,$43a0,$44a0,$45a0,$46a0,$47a0
          dw $40c0,$41c0,$42c0,$43c0,$44c0,$45c0,$46c0,$47c0
          dw $40e0,$41e0,$42e0,$43e0,$44e0,$45e0,$46e0,$47e0
          dw $4800,$4900,$4a00,$4b00,$4c00,$4d00,$4e00,$4f00
          dw $4820,$4920,$4a20,$4b20,$4c20,$4d20,$4e20,$4f20
          dw $4840,$4940,$4a40,$4b40,$4c40,$4d40,$4e40,$4f40
          dw $4860,$4960,$4a60,$4b60,$4c60,$4d60,$4e60,$4f60
          dw $4880,$4980,$4a80,$4b80,$4c80,$4d80,$4e80,$4f80
          dw $48a0,$49a0,$4aa0,$4ba0,$4ca0,$4da0,$4ea0,$4fa0
          dw $48c0,$49c0,$4ac0,$4bc0,$4cc0,$4dc0,$4ec0,$4fc0
          dw $48e0,$49e0,$4ae0,$4be0,$4ce0,$4de0,$4ee0,$4fe0
          dw $5000,$5100,$5200,$5300,$5400,$5500,$5600,$5700
          dw $5020,$5120,$5220,$5320,$5420,$5520,$5620,$5720
          dw $5040,$5140,$5240,$5340,$5440,$5540,$5640,$5740
          dw $5060,$5160,$5260,$5360,$5460,$5560,$5660,$5760
          dw $5080,$5180,$5280,$5380,$5480,$5580,$5680,$5780
          dw $50a0,$51a0,$52a0,$53a0,$54a0,$55a0,$56a0,$57a0
          dw $50c0,$51c0,$52c0,$53c0,$54c0,$55c0,$56c0,$57c0
          dw $50e0,$51e0,$52e0,$53e0,$54e0,$55e0,$56e0,$57e0

border:   db $00
attrib:   db 104q

    ENDMODULE
