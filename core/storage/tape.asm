;=============================================================================
; tape - the storage backend that talks to a cassette recorder
;=============================================================================
; Placement:  MemPlan places this one - the org below is the answer. It is
;             the address the one fitted backend gets.
; Depends on: storage.asm, for the filename, and the 48K ROM.
; Namespace:  MODULE tape - reached as tape.*, but the game should be calling
;             storage.save_block / storage.load_block, which are these.
;
;-----------------------------------------------------------------------------
; What is actually on the tape
;-----------------------------------------------------------------------------
; The Spectrum does not have files, it has blocks, and a "file" is a
; convention: two blocks in a row, a header and then the data it describes.
;
; Every block on a tape is the same shape:
;
;   leader      several seconds of one steady tone. It is there so the loader
;               can measure the timing of the machine that recorded it, so a
;               stretched or slow tape still reads. This is the noise you hear
;               while SEARCHING, before it turns into LOADING.
;   sync        one short pulse pair saying the leader has finished and the
;               next bit is real
;   flag byte   $00 for a header, $FF for data. This is how the loader tells
;               the two apart, and how it can skip a file it is not interested
;               in without understanding anything about it
;   the bytes   the block itself
;   parity      every byte of the block XORed together. The loader recomputes
;               it and refuses the block if it disagrees, which is the whole
;               of the error checking a tape gets
;
; A header block is always 17 bytes and always this, because it is what BASIC
; writes and what every loader in existence expects to read:
;
;   byte  0     type: 0 program, 1 number array, 2 character array, 3 CODE
;   bytes 1-10  the name, space padded to exactly ten
;   bytes 11-12 the length of the data block that follows
;   bytes 13-14 param 1 - for CODE, the address it was saved from
;   bytes 15-16 param 2 - unused for CODE; BASIC writes 32768 and so do we
;
; Nothing forces the data block to be loaded back to the address in param 1,
; and this game does not: it loads into a buffer and checks what arrived
; before copying it anywhere. See game/save.asm.
;
;-----------------------------------------------------------------------------
; The two ROM routines
;-----------------------------------------------------------------------------
; All the work is done by two entry points in the 48K ROM. They are the ones
; BASIC's SAVE and LOAD use, they are why a tape written here can be read by
; an emulator or by BASIC, and there is no reason to write our own - they are
; bit-banging a port to a timing that has to match everybody else's.
;
;   SA_BYTES $04C2   a = flag byte, ix = address, de = length. Records a
;                    leader, the flag, the bytes and the parity.
;
;   LD_BYTES $0556   a = the flag byte expected, ix = address, de = length,
;                    CF = 1 to load (CF = 0 verifies against memory instead,
;                    which is not used here). Returns CF = 1 if a block with
;                    that flag, that length and a good parity arrived.
;
; Three things about them are worth knowing before they surprise you:
;
; 1. They are timing loops, so they run with interrupts disabled - they do it
;    themselves, a few instructions in. On the way out, through a shared exit
;    the ROM calls SA/LD-RET, they run EI. So they come back with interrupts
;    ON whatever they were on entry, and this file puts that back by hand.
;
; 2. That same exit checks BREAK - CAPS SHIFT and SPACE together - and if it
;    is held it does not return at all: it raises a BASIC error, and with the
;    48K ROM paged in that means the game is gone. So the prompts in the
;    scene do not offer BREAK as a way to change your mind, and there is no
;    tidy way to make it one short of not using the ROM at all.
;
; 3. With no tape playing, LD_BYTES does not time out. It waits for a leader
;    for as long as it takes, exactly as SEARCHING does in BASIC. That is the
;    intended behaviour - the player is expected to be pressing PLAY - but it
;    does mean load_block can sit there for as long as the player likes.
;
; They are ROM routines, so like every other ROM call in this build they want
; IY holding $5C3A. Nothing here disturbs it; see the note in menus.asm about
; why nothing else should either.
;
;-----------------------------------------------------------------------------
; The 128K, and what TR-DOS will have to do differently
;-----------------------------------------------------------------------------
; Those two addresses are only tape routines while the 48K BASIC ROM is the
; one paged in. This build boots with it paged - bit 4 of the value in
; BANK_SELECTOR is set, which is also why rom_text.asm can print at all - so
; nothing here has to page anything.
;
; A TR-DOS backend will not get off that lightly: its entry points live in the
; interface's own ROM, which has to be paged in around every call and put back
; afterwards. That is exactly the kind of thing that belongs in a backend and
; not in storage.asm.
;=============================================================================

                    SLOT 3
                    PAGE 0
                    org $C746
                    MODULE tape

SA_BYTES            equ $04C2
LD_BYTES            equ $0556

FLAG_HEADER         equ $00
FLAG_DATA           equ $FF

TYPE_CODE           equ 3
HEADER_LEN          equ 17
HEADER_NAME_LEN     equ 10                  ; what the ROM's field holds; the
                                            ; game's names are eight

; One header buffer, written on the way out and read into on the way back.
; Two would be two places for the layout above to be got wrong.
header:
.file_type:         db TYPE_CODE
.name:              ds HEADER_NAME_LEN, ' '
.length:            dw 0
.param1:            dw 0                    ; the address it came from
.param2:            dw 32768                ; unused for CODE, but BASIC puts
                                            ; 32768 here and tools expect it

block_addr:         dw 0                    ; what the caller asked us to move
block_len:          dw 0

;-----------------------------------------------------------------------------
; save_block - ix = address, de = length, name in storage.filename.
;
; Always reports success: nothing is read back, so there is nothing that could
; tell us the recorder was not even running.
;-----------------------------------------------------------------------------
save_block:
                    ld (block_addr), ix
                    ld (block_len), de
;
                    call build_header
                    ld ix, header
                    ld de, HEADER_LEN
                    ld a, FLAG_HEADER
                    call save_one
;
                    call gap
;
                    ld ix, (block_addr)
                    ld de, (block_len)
                    ld a, FLAG_DATA
                    call save_one
;
                    scf
                    ret

build_header:
                    ld a, TYPE_CODE          ; a load will have overwritten the
                    ld (header.file_type), a ; whole buffer with somebody's
;
                    ld hl, storage.filename
                    ld de, header.name
                    ld bc, storage.FILENAME_LEN
                    ldir
                    ld a, ' '               ; the ROM's field is ten wide and
                    ld (de), a              ; the game's names are eight
                    inc de
                    ld (de), a
;
                    ld hl, (block_len)
                    ld (header.length), hl
                    ld hl, (block_addr)
                    ld (header.param1), hl
                    ret

;-----------------------------------------------------------------------------
; load_block - ix = address, de = length, name in storage.filename.
; CF = 1 if the named block arrived intact.
;
; The search loop is the whole of finding a file on a tape: read every header
; that goes past, and when one is not ours do nothing - the data block behind
; it is then just more noise, and the next header is the next candidate. This
; is what BASIC is doing when it prints one name after another.
;-----------------------------------------------------------------------------
load_block:
                    ld (block_addr), ix
                    ld (block_len), de
.search:
                    ld ix, header
                    ld de, HEADER_LEN
                    ld a, FLAG_HEADER
                    scf                     ; load it, do not verify it
                    call load_one
                    jr nc, .search          ; noise, or a data block, or a
                                            ; header that did not survive
                    call is_ours
                    jr nz, .search
;
                    ld ix, (block_addr)
                    ld de, (block_len)
                    ld a, FLAG_DATA
                    scf
                    jp load_one             ; its answer is our answer

;-----------------------------------------------------------------------------
; is_ours - Z if the header just read is the file the caller asked for.
;
; The length is checked as well as the name. A block of the right name and the
; wrong size is from an older build of the game, and reading it into a buffer
; sized for this one would either fail on parity or quietly fill the wrong
; fields.
;-----------------------------------------------------------------------------
is_ours:
                    ld hl, storage.filename
                    ld de, header.name
                    ld b, storage.FILENAME_LEN
.next:
                    ld a, (de)
                    inc de
                    cp (hl)
                    ret nz
                    inc hl
                    djnz .next
;
                    ld hl, (header.length)
                    ld de, (block_len)
                    ld a, h
                    cp d
                    ret nz
                    ld a, l
                    cp e
                    ret

;-----------------------------------------------------------------------------
; save_one / load_one - one block, with the interrupt state put back.
;
; The DI is not strictly needed - the ROM does its own a few instructions in -
; but it means the frame handler cannot fire between deciding to save and the
; ROM getting there. The EI is needed: the ROM's exit has already done one, so
; without this the game's interrupt state would depend on which ROM path was
; taken. Neither instruction touches the flags, so the carry the ROM hands
; back is still the carry the caller sees.
;-----------------------------------------------------------------------------
save_one:
                    di
                    call SA_BYTES
                    ei
                    ret

load_one:
                    di
                    call LD_BYTES
                    ei
                    ret

;-----------------------------------------------------------------------------
; gap - about a second of silence between the header and the data block.
;
; A real recorder needs the pause: the loader has to hear the second leader
; start out of nothing, and a header running straight into its data is the
; classic way to write a tape that only loads on the emulator that made it.
; BASIC's SAVE pauses here too, with HALT - which needs interrupts, and
; interrupts are not wanted in the middle of a save, so this counts instead.
;
; The inner loop is 65536 turns of 26 T-states, about 0.48s at 3.5MHz, so two
; of them is the second.
;-----------------------------------------------------------------------------
gap:
                    ld b, 2
.outer:
                    ld hl, 0
.inner:
                    dec hl
                    ld a, h
                    or l
                    jr nz, .inner
                    djnz .outer
                    ret

                    ENDMODULE
