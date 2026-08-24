Decompress0             equ $6000
Globals                 equ $5B00
AppStart                equ $5E44       ; 0017; First byte of code (uncontended memory)
ZX0                     equ $7B20       ; 00C0
Beeper                  equ $9237       ; 003E ; End 7C97
Input                   equ $7C98       ; 0081 ; End 7D2C
Math                    equ $80BF       ; 002f ; End 7D64
;Stack $7AFF-$7FFF
Stack                   equ $7B00
;256 BYTES?
;$8100 - 82B0; $1B0
Interrupt               equ $8100       ; 001F
PTSPlayer               equ $845D       ; 8181 Int routine
                                        ; 8200 Int vector
AY_OPS                  equ $927E
AYPlayer                equ $5EA8
Attributes              equ $8301       ; 00D7
DrawDisplay             equ $901A       ; 0119 ? 400
;DrawBuffer             equ $8450       ; ??? ^^^^^^
Text                    equ $5EDD       ; 00CB ; direct_text - writes the screen itself
RomText                 equ $6100       ; 0084 ; rom_text - prints through the ROM
Fonts                   equ $8850       ; 300
Game                    equ $5E5B       ; 179;
;Globals                $65DA-$678B     ; game/globals.asm, MODULE globals:
;                       $65DA-$6672     ;   settings, name strings, get_name
;                       $6673-$66C2     ;   monster_types, 10 x 8, static
;                       $66C3-$66FF     ;   type_of / get_monster_type
;                       $6700-$677F     ;   barbarian/dwarf/elf/wizard, 4 x 32
;                       $6780-$678B     ;   get_hero
;                       $678C-$7AFF     ; free, up to the stack
;                                       ; the hero table is placed by ALIGN 256.
;                                       ; The live monster pool is NOT here - it
;                                       ; belongs to the level; see game/globals.i
MainMenu                equ $6180       ; 00DE ; End 625E - was $5F91, which
                                        ; only had 127 bytes before mouse.asm
                                        ; at $6010. Free from here to Stack.
HUD                     equ $8D00       ; 295
;MapControl              equ $8E2C       ;
DialogSys               equ $92BF       ;
;Collision               equ $95C0
;Player                  equ $98C0
Screen                  equ $92AC       ;
DecompressorZX0         equ $8000
;Window                  equ $A450       ; 
Dialogs                 equ $A450 