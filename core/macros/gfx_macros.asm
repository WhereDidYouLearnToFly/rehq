    MACRO DRAW_PANEL8x8 xy, wh, img
            ld hl, xy
            ld a, h
            rla
            rla
            rla
            ld (display.panel_xpix), a
            ld a, l
            rla
            rla
            rla
            ld (display.panel_ypix), a
            ld hl, wh
            ld a, h
            dec a
            ld (display.panel_wchar), a
            ld a, l
            dec a
            ld (display.panel_hchar), a
            ld hl, img
            call display.draw8x8_panel
    ENDM

    MACRO FILL_ATTRIB_RECT xy, wh, attrib
        ld bc, xy
        ld de, wh
        ld a, attrib
        call attribs.fill_rectangle
    ENDM

    MACRO FILL_ATTRIB_RECT_DYNAMIC_SIZE xy, attrib
        ld bc, xy
        ld a, attrib
        call attribs.fill_rectangle
    ENDM
