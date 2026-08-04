IM1_I_VALUE                 equ 63          ;$3F
IM1_INTERRUPT               equ 56          ;$38
RETURN_KEY_ROUTINE          equ 654         ;$28E
BEEPER_ROUTINE_HL_DE        equ 949         ;$3B5
DROP_TEMP_ATTRIBS           equ 3405        ;$D4D
CLEAR_SCREEN_ROUTINE        equ 3503        ;$DBF
GET_SCREEN_ADDR_FROM_ALINE  equ 3742        ;$E9E
OPEN_SCREEN                 equ 5633        ;$1601
PRINT_BC_SHORT              equ 6683        ;$1A1B            ;Print 4 digits decimal
PAUSE_BC                    equ 7997        ;$1F3D
PRINT_STRING_FROM_DE        equ 8252        ;$204C            ;Displays a string at address DE with length BC on the screen
SET_BORDER_TO_A             equ 8859        ;$22AB
ROM_FONT                    equ 15616       ;$3D00            ;96 chars * 8 bytes
DISPLAY_PIXELS              equ 16384       ;$4000
DISPLAY_ATTRS               equ 22528       ;$5800
BANK_SELECTOR               equ 23388       ;$5B1C
LAST_KEY                    equ 23560       ;$5C58            ;ASCII code of the last keypress
FONT_POINTER                equ 23606       ;$5C86            ;256 = 32 * 8 bytes, 32 is the code for first printable character
SYS_BORDER                  equ 23624       ;$5C98
BASIC48                     equ 23635       ;$5CA3
CLOCK                       equ 23672       ;$5C98            ;Incremented 50 times per second
PAPER_INK_BRIGHT0           equ 23693       ;$5CED
PAPER_INK_BRIGHT1           equ 23695       ;$5CEF
IO_CHANNELS                 equ 23734       ;$5D16
BASIC_AREA                  equ 23755       ;$5D2B
LOWEST_PROG_START           equ 24000       ;$5DC0
FAST_RAM_START              equ 32768       ;$8000
PUT_DEC_BC_TO_STACK         equ 11563       ;$2D2B
PRINT_TOP_STACK             equ 11747       ;$2DDB
;
AY_PORT_WRITE               equ 49149       ;$BFFD
AY_PORT_READ                equ 65533       ;$FFFD