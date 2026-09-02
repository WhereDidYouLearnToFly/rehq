;=============================================================================
; Call-site sugar for the gfx modules
;=============================================================================
; A macro belongs here only when a routine cannot state its arguments in
; registers. draw8x8_panel used to need one - it read its coordinates out of
; memory - and that indirection is exactly how it drifted out of step with its
; own call site. It takes BC/DE/HL now, so it needs no macro.
;-----------------------------------------------------------------------------

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
