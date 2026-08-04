    org Game
    MODULE game

pscene_init:      dw main_menu.init
pscene_deinit:    dw main_menu.deinit
pscene_loop:      dw main_menu.scene_loop
pscene_interrupt: dw main_menu.scene_interrupt

init_main_menu:
            ;ld hl, main_menu.init
            ;ld (game.pscene_init), hl
            ;
            ;ld hl, main_menu.init
            ;ld (game.pscene_deinit), hl
            ;
            ;ld hl, main_menu.init
            ;ld (game.pscene_loop), hl
            ;
            ;ld hl, main_menu.init
            ;ld (game.pscene_interrupt), hl
            ret

init:
                SELECT_RAM_BANK 1
                SELECT_ROM_BANK 0
                jp init_main_menu

main:
.game_loop:         
                ;game flow control loop
                ;
                ;indirect_call(pscene_init)
                ;indirect_call(pscene_loop)
                ;indirect_call(pscene_deinit)
                ;
                halt
                di
                ;flush
                ei
                jp .game_loop
 
onInterrupt:        ;global interrupt
                    ;call hud.interrupt
                    ;call input.check_input
                    ;indirect_call(pscene_interrupt)
                    ;call player.onInterrupt
                    ret
        ENDMODULE