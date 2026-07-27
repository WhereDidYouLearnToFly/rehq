IM1_I_VALUE                 equ 63
IM1_INTERRUPT               equ 56
RETURN_KEY_ROUTINE          equ 654
BEEPER_ROUTINE_HL_DE        equ 949
DROP_TEMP_ATTRIBS           equ 3405
CLEAR_SCREEN_ROUTINE        equ 3503
GET_SCREEN_ADDR_FROM_ALINE  equ 3742
OPEN_SCREEN                 equ 5633
PRINT_BC_SHORT              equ 6683        ;Print 4 digits decimal
PAUSE_BC                    equ 7997
PRINT_STRING_FROM_DE        equ 8252        ;Displays a string at address DE with length BC on the screen
SET_BORDER_TO_A             equ 8859
ROM_FONT                    equ 15616       ;96 chars * 8 bytes
DISPLAY_PIXELS              equ 16384
DISPLAY_ATTRS               equ 22528
BANK_SELECTOR               equ 23388
LAST_KEY                    equ 23560       ;ASCII code of the last keypress
FONT_POINTER                equ 23606       ;256 = 32 * 8 bytes, 32 is the code for first printable character
SYS_BORDER                  equ 23624
BASIC48                     equ 23635
CLOCK                       equ 23672       ;Incremented 50 times per second
PAPER_INK_BRIGHT0           equ 23693
PAPER_INK_BRIGHT1           equ 23695
IO_CHANNELS                 equ 23734
BASIC_AREA                  equ 23755
LOWEST_PROG_START           equ 24000
FAST_RAM_START              equ 32768
PUT_DEC_BC_TO_STACK         equ 11563
PRINT_TOP_STACK             equ 11747
;
AY_PORT_WRITE               equ 49149       ;$BFFD
AY_PORT_READ                equ 65533       ;$FFFD
