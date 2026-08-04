Workplace               equ LOWEST_PROG_START
Decompress0             equ $6000
Globals                 equ $5B00
AppStart                equ $5DC0       ; 0017; First byte of code (uncontended memory)
;ZX0                     equ $7B20       ; 00C0
;AY                      equ $7BE0       ; 006E
Beeper                  equ $5EFE       ; 003E ; End 7C97
Input                   equ $7C98       ; 0081 ; End 7D2C
Math                    equ $5EA8       ; 002f ; End 7D64
;Stack $7AFF-$7FFF
Stack                   equ $7B00
;256 BYTES?
;$8100 - 82B0; $1B0
Interrupt               equ $8100       ; 001F
                                        ; 8181 Int routine
                                        ; 8200 Int vector
;
Attributes              equ $8301       ; 00D7
DrawDisplay             equ $845D       ; 0119 ? 400
;DrawBuffer             equ $8450       ; ??? ^^^^^^
Text                    equ $85D0       ; 00A5
Fonts                   equ $8850       ; 300
Game                    equ $8700       ; 179;
HUD                     equ $8D00       ; 295
;MapControl              equ $8E2C       ;
DialogSys               equ $92BF       ;
;Collision               equ $95C0
;Player                  equ $98C0
Screen                  equ $8B6A       ;
DecompressorZX0         equ $A390
;Window                  equ $A450       ; 
Dialogs                 equ $A450 