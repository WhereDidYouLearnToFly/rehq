;-----------------------------------------------------------------------------
; The quest records.
;
; A quest is NOT a map. The board is one board - the same 26x19 grid of rooms
; and corridors under every quest in the book - and it belongs in board.asm,
; once. A quest is the overlay: where the doors are, who is standing behind
; them, what furniture is in the room, what a search turns up, what happens
; when a hero walks in, and what has to be done before the party may go back
; up the stairs.
;
; That split is why this file is small. The board is 22 room rectangles, 88
; bytes, shared; a quest is a header and six lists, around 200 bytes, so
; fourteen of them and their text fit in one bank with room to spare. A
; per-quest map would be 494 bytes each before a single monster was placed.
;
; Everything here is static - the rows are read out of the quest bank and
; never written there. What changes during a quest is a copy: quest.load
; walks the lists once, at the start, and builds the live arrays in RAM (see
; "The live quest" at the bottom). The runtime bits are defined here anyway,
; in the same bytes, because the copy is verbatim - the loader ldirs the row
; and the state bits start clear.
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; The board.
;
; 26 x 19 squares, and every one of them is floor: the rooms and the corridor
; tile the grid completely, there is no solid rock to test for. This is what
; is in assets/coremap_origzx.png, read off it square by square - # is a room
; square, . is corridor:
;
;       ..........................
;       .###########..###########.
;       .###########..###########.
;       .###########..###########.
;       .###########..###########.
;       .###########..###########.
;       .########........########.
;       .########.######.########.
;       .########.######.########.
;       ..........######..........
;       .########.######.########.
;       .########.######.########.
;       .########........########.
;       .###########..###########.
;       .###########..###########.
;       .###########..###########.
;       .###########..###########.
;       .###########..###########.
;       ..........................
;
; A corridor ring one square wide, a cross through the middle, and 22 rooms
; in the four quarters. Every room is a rectangle - the largest is the 6x5 in
; the centre - so the board is 22 rows of {X, Y, W, H} and nothing else.
;
; ROOM_CORRIDOR is 0 and the rooms are 1..22, which is what makes the wall
; test one compare:
;
;       two adjacent squares are separated by a wall if their room ids
;       differ, and by nothing at all if they are equal.
;
; Corridor to corridor is 0 == 0, open, so the whole ring and cross is
; connected without one wall segment being stored. Room to corridor and room
; to room differ, so they are walled - and a door is the exception the quest
; puts back. There is no wall list anywhere in this game.
;-----------------------------------------------------------------------------
BOARD_W         equ 26
BOARD_H         equ 19

ROOM_CORRIDOR   equ 0           ; the ring and the cross, all of it
ROOM_FIRST      equ 1
ROOM_COUNT      equ 22          ; board.rooms holds this many; ASSERTed there

;-----------------------------------------------------------------------------
; Room - one rectangle of the board. Static, 4 bytes.
;
; It is the redraw unit: opening a door reveals a room, and the drawer wants
; the box, not a flood fill. It is also what ST_ROOM_HEROES and ST_ROOM_ALL
; ask about, and what a Find row and a TRG_ENTER_ROOM are keyed to.
;
; "Which room is this square in" is NOT this table walked - see room_of.
;-----------------------------------------------------------------------------
    STRUCT Room
X                BYTE $00       ; top-left square
Y                BYTE $00
W                BYTE $00       ; squares, never 0
H                BYTE $00
    ENDS

;-----------------------------------------------------------------------------
; room_of - the square-to-room index, built once at boot by walking the 22
; rectangles and painting their ids into RAM. 26x19 is 494 bytes; the rows
; are padded to 32 so the address is a shift and not a multiply by 26:
;
;       square (x,y) -> room_of + (y << 5) + x
;
; 608 bytes of RAM to turn every "what room is this", every wall test and
; every step of a line of sight into one load. The rectangles stay the source
; of truth - this is derived, and nothing writes it after boot.
;-----------------------------------------------------------------------------
ROOM_OF_STRIDE  equ 32
ROOM_OF_SIZE    equ ROOM_OF_STRIDE * BOARD_H

; DIR_* - and adding 2 and masking 3 turns a direction around, which is what
; "the wall on the other side of that one" needs.
DIR_NORTH       equ 0
DIR_EAST        equ 1
DIR_SOUTH       equ 2
DIR_WEST        equ 3

;-----------------------------------------------------------------------------
; Door - a hole in the wall the room ids imply. 2 bytes.
;
; A door is a wall segment, not a square, so it could be named from either
; side of it - and would be, twice, if the author were free to pick. He is
; not: every door in this file is on the NORTH or the WEST wall of its
; square, never the south or the east. The door between (5,5) and (5,6) is
; the north wall of (5,6), the one and only way to write it, so "is there a
; door between here and there" is one walk of the list and one compare.
;
; D_OPEN is bit 7 for the same reason CH_ALIVE is: it is the hot one. Every
; step of a move and every square of a line of sight asks it.
;
;       ld a, (hl)
;       add a, a
;       jr nc, .shut
;
; A secret door is a door that is shut and not drawn until D_FOUND. While it
; is hidden it stops movement and sight exactly like the wall the room ids
; already put there, so nothing has to special-case it.
;-----------------------------------------------------------------------------
    STRUCT Door
XF               BYTE $00       ; bits 0-4 X, bit 5 D_WEST, bit 6 D_SECRET,
                                ; bit 7 D_OPEN
YF               BYTE $00       ; bits 0-4 Y, bit 5 D_FOUND, bits 6-7 spare
    ENDS

D_COORD         equ %00011111   ; the X or the Y, masked out of either byte
D_WEST          equ %00100000   ; on the west wall of the square; clear = north
D_SECRET        equ %01000000   ; not there until it is searched for
D_OPEN          equ %10000000   ; runtime - starts clear
D_FOUND         equ %00100000   ; runtime, in YF - a secret door that was found

;-----------------------------------------------------------------------------
; QuestMonster - the roster: one row per figure the quest map puts on the
; board. 3 bytes.
;
; It is not a Monster. A Monster is 8 bytes of things that change, and it is
; only worth having once the room has been opened - so the loader turns rows
; into live records lazily, and a quest with 20 figures spends 60 bytes here
; instead of 160 in the pool.
;
; The room is not a field: the square says which room it is in, through
; room_of, and a roster row that disagreed with the board would be a bug
; waiting to happen.
;
; QM_TARGET is how an objective names a figure without an id: OBJ_KILL_TARGET
; is "the one wearing this bit", and a quest has at most one. QM_NPC is the
; prisoner - Sir Ragnar and his kind: it stands on the board, it can be
; killed, and it never takes a turn of its own.
;
; A quest that needs a figure with stats of its own - the named warlord who
; is not just another orc - is the one thing this row cannot say. When the
; transcription turns one up, the answer is another MonsterType, not a fourth
; byte here: a type costs 8 bytes once and every row already points at one.
;-----------------------------------------------------------------------------
    STRUCT QuestMonster
TYPE             BYTE $00       ; bits 0-5 an MT_, bit 6 QM_NPC, bit 7 QM_TARGET
X                BYTE $00
Y                BYTE $00
    ENDS

QM_TYPE         equ %00111111
QM_NPC          equ %01000000   ; a figure to be rescued, not fought
QM_TARGET       equ %10000000   ; the one the objective is about

;-----------------------------------------------------------------------------
; Furniture - a table, a tomb, a rack, the stairway. 3 bytes on the board,
; with its size and its sprite one indirection away in FurnitureType, because
; six tombs in a quest should cost eighteen bytes and not six copies of how
; big a tomb is.
;
; ORIENT is a DIR_, and only bit 0 of it changes the footprint: a piece laid
; east-west is W x H turned round, H x W. X and Y are the top-left square the
; piece covers AFTER it is turned, so the drawer and the blocking test read
; the same two numbers and neither has to un-rotate anything.
;-----------------------------------------------------------------------------
    STRUCT Furniture
KIND             BYTE $00       ; bits 0-5 a FURN_, bits 6-7 ORIENT
X                BYTE $00
Y                BYTE $00
    ENDS

F_KIND          equ %00111111
F_ORIENT        equ %11000000
F_ORIENT_SHIFT  equ 6

;-----------------------------------------------------------------------------
; FurnitureType - static, one row per kind. 4 bytes.
;
; FF_BLOCKS is the only rule in the row. Everything else a piece of furniture
; does - what is inside it, what happens when it is searched - is a Find row
; keyed to the room, not a property of the kind: the same chest holds gold in
; one quest and a trap in the next.
;-----------------------------------------------------------------------------
    STRUCT FurnitureType
W                BYTE $00       ; squares, unrotated
H                BYTE $00
SPRITE_ID        BYTE $00
FLAGS            BYTE $00       ; FF_* below
    ENDS

FF_BLOCKS       equ %10000000   ; no figure may end its move on these squares

; FURN_* - the pieces, and nothing about them. How big one is and what it is
; drawn with is its FurnitureType row, which cannot be written until the
; sprite exists; this list is only the ids, so a quest can be written before
; the art is.
;
; FURN_NONE is 0 so an empty slot in the live pool is an empty slot and not a
; stairway.
FURN_NONE       equ 0
FURN_STAIRWAY   equ 1           ; the way in, and the way out
FURN_TABLE      equ 2
FURN_CHAIR      equ 3
FURN_THRONE     equ 4
FURN_BOOKCASE   equ 5
FURN_CUPBOARD   equ 6
FURN_CHEST      equ 7
FURN_WEAPON_RACK equ 8
FURN_RACK       equ 9           ; the torture rack
FURN_TOMB       equ 10
FURN_FIREPLACE  equ 11
FURN_ALCHEMIST  equ 12          ; the bench
FURN_SORCERER   equ 13          ; the table

; 14 up are the pieces The Crypt of Perpetual Darkness draws that the base
; game does not. Read off its ten maps - see map-ai-parsing - and named by
; what they look like, because the pack prints no key for them.
FURN_ALTAR      equ 14
FURN_BED        equ 15
FURN_CAGE       equ 16
FURN_COLUMN     equ 17
FURN_DREAD_SKULL equ 18
FURN_FORGE      equ 19
FURN_LOOM       equ 20
FURN_MACHINE    equ 21
FURN_STONE_BENCH equ 22
FURN_TOMB_SWORD equ 23         ; a tomb with a sword carved on the lid

; ...and four the maps draw that are not furniture in the rules sense. They
; are here because the parse records them, not because the rules are known.
; TRAPDOOR is the one that matters: it is drawn as a hatch standing open, 21
; of them across the pack, and in eight of the ten rooms that have no door on
; any wall it is the only thing on or beside them - so it is very likely the
; way in, and wants to be a passage rather than a piece of furniture once the
; quest notes are transcribed. RUBBLE, BARREL and LAIR_ART may be scenery and
; nothing more. None of the four has a FurnitureType yet, so nothing reads
; them; give one a meaning before giving it a sprite.
FURN_RUBBLE     equ 24
FURN_TRAPDOOR   equ 25         ; was FURN_SLAB - the printed glyph is a hatch
FURN_LAIR_ART   equ 26         ; quest 10's dragon, 9x7 squares of it
FURN_BARREL     equ 27         ; quest 8's studded cask

; F_KIND is six bits, so this list has room to 63.
    ASSERT FURN_BARREL <= F_KIND

;-----------------------------------------------------------------------------
; Trap - 3 bytes, and the state lives in the row because a sprung trap is not
; a removed trap: a pit stays open and stays dangerous, and a fallen block
; seals its square for the rest of the quest.
;-----------------------------------------------------------------------------
    STRUCT Trap
KIND             BYTE $00       ; bits 0-4 a TRAP_, bits 5-7 runtime below
X                BYTE $00
Y                BYTE $00
    ENDS

T_KIND          equ %00011111
T_FOUND         equ %00100000   ; runtime - searched out, drawn from now on
T_DISARMED      equ %01000000   ; runtime - the tool kit, or a spent block
T_SPRUNG        equ %10000000   ; runtime - somebody stepped in it

TRAP_PIT        equ 0
TRAP_SPEAR      equ 1
TRAP_BLOCK      equ 2           ; falling block: the square is wall afterwards

;-----------------------------------------------------------------------------
; Find - what a search turns up. 4 bytes, keyed to a room, in the order the
; quest book writes them.
;
; Several rows may name the same room. They are consumed in order, one per
; successful search, which is exactly what the book says: the first hero to
; search this room finds the gold, the next finds nothing. FIND_TAKEN is bit
; 7 of ROOM, so spending a row is setting a bit in the copy.
;
; PARAM is a word rather than a byte because the kinds want different things
; out of it, and one shared word is cheaper than a byte plus a rule saying
; what the byte means this time:
;
;       FIND_GOLD       the number of coins, as written
;       FIND_CARD       a CARD_ id - the artifacts the quests hand out
;       FIND_MONSTER    an MT_ - the thing that was waiting in the cupboard
;       FIND_TRAP       a TRAP_, sprung on the searcher then and there
;       FIND_TEXT       nothing but a line to print; PARAM is the string
;
; A search is one of two questions - treasure, or secret doors - and this
; table only answers the first. The second is answered by the doors: searching
; a room for secret doors sets D_FOUND on the D_SECRET doors of that room, and
; there is nothing to write down per quest.
;-----------------------------------------------------------------------------
    STRUCT Find
ROOM             BYTE $00       ; a room id, bit 7 = runtime "already taken"
KIND             BYTE $00       ; FIND_* below
PARAM            WORD $0000     ; see above
    ENDS

FIND_ROOM       equ %01111111
FIND_TAKEN      equ %10000000   ; runtime

FIND_NOTHING    equ 0
FIND_GOLD       equ 1
FIND_CARD       equ 2
FIND_MONSTER    equ 3
FIND_TRAP       equ 4
FIND_TEXT       equ 5

;-----------------------------------------------------------------------------
; Trigger - the story. 6 bytes.
;
; Find says what is in the room. This says what the quest does about it: the
; line that is read out when the party opens the north door, the ambush that
; arrives when the warlord dies, the wall that slides back when the lever is
; pulled. It is a table and not code because thirteen of the fourteen quests
; want the same half-dozen verbs with different nouns in them, and a table of
; nouns is smaller than thirteen routines.
;
; WHEN is the event, P1 and P2 the thing it is watching - a room id, a door,
; a square, an id - and ACTION with VALUE is what to do about it. TRG_FIRED
; is set on the copy the moment it goes off, so a trigger is once per quest;
; a trigger meant to repeat clears its own bit through TA_SCRIPT.
;
; The engine raises the events. It does not know what a quest is: every hook
; ends with "and tell the trigger list", the list is walked - a dozen rows,
; six bytes each - and that is the whole of the story layer.
;
; TA_SCRIPT is the escape hatch, and it is the same one Card.ACTION is: when
; a quest wants something no verb here covers, it gets a routine, and the
; routine is called with the trigger in IY. Adding a verb to this list is for
; when the second quest wants the same thing.
;-----------------------------------------------------------------------------
    STRUCT Trigger
WHEN             BYTE $00       ; bits 0-6 TRG_*, bit 7 TRG_FIRED
P1               BYTE $00       ; room, door index, or X - see the event
P2               BYTE $00       ; or Y
ACTION           BYTE $00       ; TA_* below
VALUE            WORD $0000     ; the string, the id, or the routine
    ENDS

TRG_EVENT       equ %01111111
TRG_FIRED       equ %10000000   ; runtime

TRG_QUEST_START equ 0           ; the moment the party is put down
TRG_ENTER_ROOM  equ 1           ; P1 = room. A hero, not a monster
TRG_OPEN_DOOR   equ 2           ; P1 = index into the door list
TRG_STAND_ON    equ 3           ; P1,P2 = the square a hero has stopped on
TRG_KILL_TARGET equ 4           ; the QM_TARGET figure has died
TRG_KILL_ROOM   equ 5           ; P1 = room, and nothing in it is standing
TRG_SEARCH_ROOM equ 6           ; P1 = room, treasure search, before Find
TRG_TAKE_CARD   equ 7           ; P1 = a CARD_ id somebody has picked up
TRG_HERO_DIES   equ 8

TA_TEXT         equ 0           ; VALUE is a string; print it and go on
TA_SPAWN        equ 1           ; VALUE is an MT_, at P1,P2 - the ambush
TA_OPEN_DOOR    equ 2           ; VALUE is a door index; D_OPEN | D_FOUND
TA_GIVE_CARD    equ 3           ; VALUE is a CARD_ id, to whoever fired it
TA_WIN          equ 4           ; the quest is over and it was won
TA_LOSE         equ 5
TA_SCRIPT       equ 6           ; VALUE is a routine; IY = this Trigger

;-----------------------------------------------------------------------------
; Quest - the header, and then the six lists, back to back, in this order:
;
;       Door         x N_DOORS
;       QuestMonster x N_MONSTERS
;       Furniture    x N_FURNITURE
;       Trap         x N_TRAPS
;       Find         x N_FINDS
;       Trigger      x N_TRIGGERS
;
; Counts and not pointers, because every list is walked exactly once, by
; quest.load, in this order - so the walk is already standing at the head of
; the next one, and six pointers would be six bytes a quest to say what the
; counts already said.
;
; Nothing indexes a Quest, so the header is 18 bytes and not a round 16: the
; quests are not the same length, so the quest table is a table of pointers
; and the header is whatever the fields need.
;
; START_X / START_Y is the staircase square. It is in the header rather than
; read back out of the stairway furniture because three things ask for it and
; none of them wants to search a furniture list: where the party is put down,
; where Escape teleports to, and where the Ring of Return sends everyone the
; wearer can see.
;
; SCRIPT is the quest's own routine and it is not the same thing as a
; TA_SCRIPT trigger: this one is called on load, for the quest that has to
; set something up before the first turn. 0 for the ones that do not, which
; will be most of them.
;-----------------------------------------------------------------------------
    STRUCT Quest
TITLE_STR        WORD $0000     ; a MenuString - in the quest bank, not here
BRIEF_STR        WORD $0000     ; the read-aloud text, same bank
SCRIPT           WORD $0000     ; run once on load, 0 = nothing to set up
START_X          BYTE $00       ; the staircase
START_Y          BYTE $00
WANDERING        BYTE $00       ; the MT_ this quest's wandering monster is
OBJECTIVE        BYTE $00       ; OBJ_* below
OBJ_PARAM        BYTE $00       ; what it is about, if that needs saying
FLAGS            BYTE $00       ; QF_* below
N_DOORS          BYTE $00
N_MONSTERS       BYTE $00
N_FURNITURE      BYTE $00
N_TRAPS          BYTE $00
N_FINDS          BYTE $00
N_TRIGGERS       BYTE $00
    ENDS

QUEST_LISTS     equ Quest       ; the first list starts here, past the header

;-----------------------------------------------------------------------------
; OBJ_* - what has to be done. The book writes fourteen endings, and they are
; not fourteen rules; these are the shapes they come in.
;
;   OBJ_EXIT            reach the stairs, and nothing else - The Trial. It is
;                       also the floor under most of the others, through
;                       QF_MUST_ESCAPE
;   OBJ_KILL_TARGET     kill the figure marked QM_TARGET
;   OBJ_KILL_ALL        nothing left standing
;   OBJ_RESCUE          the QM_NPC figure has to reach the stairs alive
;   OBJ_FIND            OBJ_PARAM is a CARD_ id and somebody has to be
;                       carrying it
;   OBJ_TRIGGER         a TA_WIN says so, and nothing else does
;
; This list is provisional until all fourteen are transcribed. It is meant to
; grow one entry at a time, as a quest turns out not to fit - and the quest
; that will not fit any of them ends on a TA_WIN out of its own trigger.
;-----------------------------------------------------------------------------
OBJ_EXIT        equ 0
OBJ_KILL_TARGET equ 1
OBJ_KILL_ALL    equ 2
OBJ_RESCUE      equ 3
OBJ_FIND        equ 4
OBJ_TRIGGER     equ 5

QF_MUST_ESCAPE  equ %10000000   ; the objective is not enough: every hero
                                ; still standing has to leave by the stairs
QF_NO_WANDERING equ %01000000   ; no wandering monster in this one, whatever
                                ; WANDERING says

;-----------------------------------------------------------------------------
; The live quest - what quest.load builds in RAM out of all of the above.
;
; MAX_MONSTERS is 32 because globals.i asked for a multiple of 32: 32 records
; of 8 bytes is one page, so a slot index is three adds and the offset stays
; inside a byte. The loader is what finds out that a roster is too long - it
; refuses the row rather than writing past the pool.
;
; The rest, in one place:
;
;   monsters        MAX_MONSTERS  * Monster     256    page-aligned
;   doors           MAX_DOORS     * Door         64
;   furniture       MAX_FURNITURE * Furniture    72
;   traps           MAX_TRAPS     * Trap         36
;   finds           MAX_FINDS     * Find         64
;   triggers        MAX_TRIGGERS  * Trigger      96
;   room_of         ROOM_OF_SIZE                608    built once at boot
;   seen            BOARD_H * 4                  76    one bit per square
;   searched        ROOM_COUNT bits, twice        6    treasure / secret doors
;
; Furniture is copied rather than read from the bank for one reason: it is
; read every time a square is drawn, and the drawer cannot page.
;-----------------------------------------------------------------------------
MAX_MONSTERS    equ 32
MAX_DOORS       equ 32
MAX_FURNITURE   equ 24
MAX_TRAPS       equ 12
MAX_FINDS       equ 16
MAX_TRIGGERS    equ 16

; The lists are walked with the count in B, and copied into a pool that does
; not grow. Break one of these and the build stops here.
    ASSERT MAX_MONSTERS * Monster <= 256
    ASSERT MAX_MONSTERS <= 255 && MAX_DOORS <= 255 && MAX_FURNITURE <= 255
    ASSERT MAX_TRAPS <= 255 && MAX_FINDS <= 255 && MAX_TRIGGERS <= 255

; A square packs into five bits per axis wherever a record needs it small -
; Door does. Take the board past 32 and the doors grow a byte.
    ASSERT BOARD_W <= 32 && BOARD_H <= 32

; Room ids have to leave bit 7 alone: Find.ROOM keeps its consumed flag there.
    ASSERT ROOM_COUNT < FIND_TAKEN
