    STRUCT Panel8x8
TopLeft         BYTE
TopCenter       BYTE
TopRight        BYTE
MidLeft         BYTE
Filler          BYTE
MidRight        BYTE
BottomLeft      BYTE
BottomCenter    BYTE
BottomRight     BYTE
    ENDS

    STRUCT Panel16x16
TopLeft         BYTE
TopCenter       BYTE
TopRight        BYTE
MidLeft         BYTE
Filler          BYTE
MidRight        BYTE
BottomLeft      BYTE
BottomCenter    BYTE
BottomRight     BYTE
    ENDS

    STRUCT WindowUI
X       BYTE
Y       BYTE
WIDTH   BYTE
HEIGHT  BYTE
PBUFFER BYTE
PPROG   BYTE
BORDER  BYTE
PAPER   BYTE
INK     BYTE
TMP     BYTE
    ENDS