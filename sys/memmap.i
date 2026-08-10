Decompress0             equ $6000
Globals                 equ $5B00
AppStart                equ $5E44       ; 0017; First byte of code (uncontended memory)
ZX0                     equ $7B20       ; 00C0
Beeper                  equ $8F1E       ; 003E ; End 7C97
Input                   equ $7C98       ; 0081 ; End 7D2C
Math                    equ $80BF       ; 002f ; End 7D64
;Stack $7AFF-$7FFF
Stack                   equ $7B00
;256 BYTES?
;$8100 - 82B0; $1B0
Interrupt               equ $8100       ; 001F
PTSPlayer               equ $845D       ; 8181 Int routine
                                        ; 8200 Int vector
AY_OPS                  equ $8F65
AYPlayer                equ $5EA8
Attributes              equ $8301       ; 00D7
DrawDisplay             equ $8D01       ; 0119 ? 400
;DrawBuffer             equ $8450       ; ??? ^^^^^^
Text                    equ $5EBF       ; 00CB ; direct_text - writes the screen itself
RomText                 equ $6100       ; 0084 ; rom_text - prints through the ROM
Fonts                   equ $8850       ; 300
Game                    equ $5E5B       ; 179;
HUD                     equ $8D00       ; 295
;MapControl              equ $8E2C       ;
DialogSys               equ $92BF       ;
;Collision               equ $95C0
;Player                  equ $98C0
Screen                  equ $8F93       ;
DecompressorZX0         equ $8000
;Window                  equ $A450       ; 
Dialogs                 equ $A450 