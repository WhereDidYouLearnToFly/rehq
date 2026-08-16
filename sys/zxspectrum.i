IM1_I_VALUE                 equ 63          ;$3F
IM1_INTERRUPT               equ 56          ;$38
RETURN_KEY_ROUTINE          equ 654         ;$028E
BEEPER_ROUTINE_HL_DE        equ 949         ;$03B5           ;BEEPER
DROP_TEMP_ATTRIBS           equ 3405        ;$0D4D           ;TEMPS - copies ATTR_P over ATTR_T, see the colour sysvars below
CLEAR_SCREEN_ROUTINE        equ 3503        ;$0DAF           ;CLS
GET_SCREEN_ADDR_FROM_ALINE  equ 3742        ;$0E9E
OPEN_SCREEN                 equ 5633        ;$1601           ;CHAN-OPEN
PRINT_BC_SHORT              equ 6683        ;$1A1B            ;Print 4 digits decimal
PAUSE_BC                    equ 7997        ;$1F3D
PRINT_STRING_FROM_DE        equ 8252        ;$203C            ;Displays a string at address DE with length BC on the screen
SET_BORDER_TO_A             equ 8859        ;$229B           ;inside BORDER: OUT (FE),A then sets BORDCR
ROM_FONT                    equ 15616       ;$3D00            ;96 chars * 8 bytes
DISPLAY_PIXELS              equ 16384       ;$4000
DISPLAY_ATTRS               equ 22528       ;$5800
BANK_SELECTOR               equ 23388       ;$5B5C            ;BANKM
LAST_KEY                    equ 23560       ;$5C08            ;LAST_K - ASCII code of the last keypress
FONT_POINTER                equ 23606       ;$5C36            ;CHARS - 256 = 32 * 8 bytes, 32 is the code for first printable character
SYS_BORDER                  equ 23624       ;$5C48            ;BORDCR
BASIC48                     equ 23635       ;$5C53            ;PROG - start of the BASIC program
CLOCK                       equ 23672       ;$5C78            ;FRAMES - incremented 50 times per second
;
; Attribute byte layout, the value all four of these hold:
;
;   bit  7   6   5 4 3   2 1 0
;        F   B   P P P   I I I      F flash, B bright, P paper, I ink
;
; so 161q = $71 = %01110001 is bright yellow paper with blue ink.
;
; The two colour sysvars are a source and a working copy, not two equal slots.
; Printing reads ...BRIGHT1 (ATTR_T) and nothing else, but DROP_TEMP_ATTRIBS
; refills ATTR_T from ...BRIGHT0 (ATTR_P), and the ROM does that on its own on
; CLS and on scroll - so ATTR_T is the one that shows and ATTR_P is the one
; that survives. Set ATTR_P for a colour that should stick, ATTR_T for a single
; print that must not disturb the default, both to print now and keep it.
;
; A set bit in a MASK means "leave that bit alone" - take it from the cell that
; is already on screen instead of from the attribute. All zero = the attribute
; wins outright, which is what you want. PRINT_FLAGS holds OVER / INVERSE /
; INK 9 / PAPER 9; even bits are the temporary copies, odd bits the permanent
; ones. If a colour half-takes, these three are where to look.
;
PAPER_INK_BRIGHT0           equ 23693       ;$5C8D            ;ATTR_P - permanent attributes
PAPER_INK_BRIGHT_MASK0      equ 23694       ;$5C8E            ;MASK_P - permanent transparency mask
PAPER_INK_BRIGHT1           equ 23695       ;$5C8F            ;ATTR_T - temporary, what printing actually reads
PAPER_INK_BRIGHT_MASK1      equ 23696       ;$5C90            ;MASK_T - temporary transparency mask
PRINT_FLAGS                 equ 23697       ;$5C91            ;P_FLAG - OVER, INVERSE, INK 9, PAPER 9
IO_CHANNELS                 equ 23734       ;$5CB6            ;CHANS
BASIC_AREA                  equ 23755       ;$5CCB
LOWEST_PROG_START           equ 24000       ;$5DC0
FAST_RAM_START              equ 32768       ;$8000
PUT_DEC_BC_TO_STACK         equ 11563       ;$2D2B            ;STACK-BC
PRINT_TOP_STACK             equ 11747       ;$2DE3            ;PRINT-FP
;
AY_PORT_WRITE               equ 49149       ;$BFFD
AY_PORT_READ                equ 65533       ;$FFFD

;=============================================================================
; NOTES - the machine behind the numbers above
;=============================================================================
;
;-----------------------------------------------------------------------------
; The screen is two files, not one
;-----------------------------------------------------------------------------
; DISPLAY_PIXELS ($4000) is 6144 bytes of pure monochrome bitmap: one bit per
; pixel, 256x192, no colour in it at all. DISPLAY_ATTRS ($5800) is a separate
; 768 bytes, one byte per 8x8 cell, 32x24 of them. 6912 bytes together, and
; the two are only related by position on screen.
;
; That split is the whole character of the machine. Colour costs nothing to
; move - one byte repaints an entire cell, which is why fill_rectangle can
; recolour a nine-character title in nine writes while the pixels underneath
; stay put. It also means two colours per cell and no more, so a sprite
; crossing a cell boundary drags its colours over whatever it overlaps. That
; is attribute clash, and it is not a bug to be fixed but a budget to be
; spent: lay things out on cell boundaries and it never shows.
;
;-----------------------------------------------------------------------------
; Working out a screen address
;-----------------------------------------------------------------------------
; The display file is not linear. Consecutive addresses run left to right
; across one pixel row, but the next address down is eight pixel rows lower,
; and the screen is split into three bands of 64 lines that repeat the trick.
; For pixel row y (0-191) and cell column c (0-31) the address decodes as:
;
;     high byte   0 1 0 T T L L L        T = y bits 7-6, which third
;     low  byte   S S S C C C C C        L = y bits 2-0, pixel row in cell
;                                        S = y bits 5-3, cell row in third
;                                        C = c, the column
;
;     H = $40 | ((y >> 3) AND $18) | (y AND $07)
;     L = ((y AND $38) << 2) | c
;
; So stepping down one pixel row inside a cell is just INC H - eight of those
; before you have to do real arithmetic. That is the payoff, and the reason
; the layout was chosen. Crossing into the next cell row costs a fixup, and
; crossing a third costs another. A lookup table of the 192 row addresses
; buys the whole thing back for 384 bytes, which is what get_pix_addr does.
;
; The attribute address is ordinary by comparison:
;
;     $5800 + ((y AND $F8) << 2) + c
;
;-----------------------------------------------------------------------------
; The attribute byte
;-----------------------------------------------------------------------------
;     bit  7   6   5 4 3   2 1 0
;          F   B   P P P   I I I
;
; Colours are three bits, ordered green-red-blue from bit 2 down:
;
;     0 black    1 blue    2 red      3 magenta
;     4 green    5 cyan    6 yellow   7 white
;
; BRIGHT picks between two intensity levels for both ink and paper at once -
; there is no bright ink on normal paper within a cell. Black is black in
; both, so BRIGHT gives fifteen colours, not sixteen. FLASH swaps ink and
; paper every 16 frames, in hardware, costing nothing once set.
;
;-----------------------------------------------------------------------------
; The 8s and the 9s
;-----------------------------------------------------------------------------
; BASIC's PAPER 8 does not name a colour, it sets the paper bits in a MASK,
; meaning "keep whatever is already in that cell". INK 9 and PAPER 9 do not
; name a colour either: they set bits in PRINT_FLAGS asking for black or
; white, whichever contrasts with the other half of the cell.
;
; Both survive into machine code, because the ROM's attribute writer applies
; them on every character it prints:
;
;     new = (screen AND mask) OR (attr AND NOT mask)
;
; A mask bit of 1 means transparent, not written - the reverse of what the
; word suggests, but the same convention as sprite masking. All zero is the
; state you want, and a stray 8 or 9 left behind by earlier code is the usual
; explanation for a colour that only half takes.
;
;-----------------------------------------------------------------------------
; Why the system variables sit where they do
;-----------------------------------------------------------------------------
; RAM starts at $4000 with the screen, and the ROM parks its own state in the
; first quiet space above it: the printer buffer at $5B00, then the system
; variables from $5C00 to $5CB5, then the channel table, then BASIC. Every
; address in this file between $5B00 and $5CFF is one of those - not a ROM
; routine but a byte the ROM reads while running, which is exactly why
; writing to it changes ROM behaviour.
;
; It also fixes where machine code can live. Below $5DC0 is the ROM's, and
; overwriting it breaks the ROM out from under you - printing, the keyboard,
; the interrupt handler, all of it. LOWEST_PROG_START is that boundary.
;
;-----------------------------------------------------------------------------
; Printing through the ROM
;-----------------------------------------------------------------------------
; RST $10 prints the character in A to the current channel. Which channel
; that is comes from the last OPEN_SCREEN: stream 1 is the bottom two lines,
; stream 2 the upper 22, stream 3 the printer. Open stream 2 once and every
; RST $10 afterwards goes to the main screen.
;
; Characters below 32 are commands, not glyphs. Most take one byte after
; them, AT and TAB take two:
;
;     8  cursor left      16 INK n        20 INVERSE n
;     9  cursor right     17 PAPER n      21 OVER n
;     13 newline          18 FLASH n      22 AT row, col
;                         19 BRIGHT n     23 TAB lsb, msb
;
; The colour codes write into ATTR_T only, so they last until something calls
; DROP_TEMP_ATTRIBS - which is how the teletype routine paints a green cursor
; block and then takes it back without disturbing the text colour.
;
; Two traps. Printing past row 21 on stream 2 raises "Out of screen" rather
; than wrapping. And when the upper screen fills, the ROM stops and asks
; "scroll?" - it counts down SCR_CT at 23692 ($5C8C) and prompts when it hits
; one, so poke 255 there if you are printing enough lines to reach the
; bottom.
;
;-----------------------------------------------------------------------------
; The interrupt
;-----------------------------------------------------------------------------
; The ULA interrupts 50 times a second, at the start of each frame. Under
; IM 1 the CPU jumps to $0038, where the ROM increments the three-byte CLOCK
; counter and scans the keyboard into LAST_KEY. Both stop dead if you run
; with interrupts disabled, which is the usual reason a timing loop built on
; CLOCK never finishes.
;
;     48K   3.5    MHz, 69888 T-states per frame, 224 T per scanline
;     128K  3.5469 MHz, 70908 T-states per frame, 228 T per scanline
;
; A frame is the budget for everything. On a 48K the interrupt fires, then
; 64 lines of top border go by - about 14336 T-states - before the ULA starts
; reading the display file, and it finishes 43008 T-states later. That leaves
; roughly 14000 T-states after the interrupt to change what is about to be
; drawn, and another 12000 at the end of the frame. Redraw inside those and
; the change is seamless; redraw while the beam is passing and it tears.
;
; IM 2 replaces the fixed $0038 with a vector fetched through the I register,
; which is how a game runs its own handler without the ROM's overhead - at
; the price of providing the table and taking over the keyboard scan.
;
;-----------------------------------------------------------------------------
; Contended memory
;-----------------------------------------------------------------------------
; The ULA and the CPU share the lower 16K, and while the ULA is drawing it
; wins. Code and data in $4000-$7FFF run measurably slower than the same code
; at $8000, and by a varying amount depending on where the beam is. On the
; 128K, banks 1, 3, 5 and 7 are contended wherever they are paged in.
;
; So the screen third of RAM is the worst place for an inner loop, and
; FAST_RAM_START marks where the machine stops fighting you. Anything timed -
; music, effects, a fast blit - belongs above it.
;
;-----------------------------------------------------------------------------
; 128K paging, and the shadow at BANK_SELECTOR
;-----------------------------------------------------------------------------
; Port $7FFD chooses what appears at $C000 and which ROM is live:
;
;     bits 0-2   RAM bank 0-7 paged at $C000
;     bit  3     screen: 0 = bank 5 (the normal one), 1 = bank 7 shadow
;     bit  4     ROM: 0 = 128K editor, 1 = 48K BASIC
;     bit  5     lock paging - set it and only a reset undoes it
;
; The port is write-only. There is no way to read back what is paged, so the
; ROM keeps a copy of the last value written in BANK_SELECTOR and so must
; you: read it, modify the bits you want, write the port, store it back.
; Write a bare value instead and the next ROM routine that pages memory will
; restore whatever it thinks is current and take your bank away.
;
; Disable interrupts across the sequence if the handler can page, and be
; careful with the address: $7FFD is only partially decoded, so a stray OUT
; to another port can land on it. Use BC = $7FFD and OUT (C),A.
;
; One consequence worth stating plainly: every ROM entry point in this file
; is a 48K BASIC ROM address. They are only valid while bit 4 selects that
; ROM. Page in the 128K editor and the same addresses are different code.
;
;-----------------------------------------------------------------------------
; The sound chip
;-----------------------------------------------------------------------------
; The AY-3-8912 is addressed through two ports because it needs a register
; number and a value. Select with AY_PORT_READ ($FFFD), then write the value
; to AY_PORT_WRITE ($BFFD); reading a register means selecting it and reading
; $FFFD back. Fourteen registers: three channels of tone as 12-bit periods,
; one noise generator, a mixer, three volumes, and one envelope shared by all
; three channels - which is the constraint that shapes Spectrum music, since
; only one voice at a time can have a hardware envelope.
;
;-----------------------------------------------------------------------------
; The font
;-----------------------------------------------------------------------------
; ROM_FONT ($3D00) is 96 characters of 8x8, starting at space. FONT_POINTER
; does not hold that address: it holds the base minus 256, so that character
; code times eight plus the pointer lands on the right bitmap without first
; subtracting the 32 unprintable codes. Store your own font's address minus
; 256 there and every ROM print routine uses it from then on.
