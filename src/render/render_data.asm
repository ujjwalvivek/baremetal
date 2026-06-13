MAP_WIDTH  equ 32
MAP_HEIGHT equ 32

section .data
    esc_cursor_home:     db 27, '[H'
    esc_cursor_home_len equ $ - esc_cursor_home

    border_horiz: db 0xE2, 0x94, 0x80          ; ─ (BOX DRAWINGS LIGHT HORIZONTAL)
    border_vert:  db 0xE2, 0x94, 0x82          ; │ (BOX DRAWINGS LIGHT VERTICAL)
    border_tl:    db 0xE2, 0x94, 0x8C          ; ┌ (TOP LEFT)
    border_tr:    db 0xE2, 0x94, 0x90          ; ┐ (TOP RIGHT)
    border_bl:    db 0xE2, 0x94, 0x94          ; └ (BOTTOM LEFT)
    border_br:    db 0xE2, 0x94, 0x98          ; ┘ (BOTTOM RIGHT)

    space_char: db ' '
    spaces_row: times 512 db ' '   ; 512-col bulk clear row

    ; Synchronized output (DEC ?2026): xterm.js holds rendering until end marker
    esc_sync_start: db 27, '[?2026h'
    esc_sync_start_len equ $ - esc_sync_start
    esc_sync_end:   db 27, '[?2026l'
    esc_sync_end_len   equ $ - esc_sync_end

    ; --- Color escapes for 5 wall types × 4 distance tiers ---
    ; Wall Type 1: Stone / Bunker (Dark Charcoal: 239, 237, 235, 233)
    w1_esc_0: db 27, '[38;5;239m'
    w1_esc_0_len equ $ - w1_esc_0
    w1_esc_1: db 27, '[38;5;237m'
    w1_esc_1_len equ $ - w1_esc_1
    w1_esc_2: db 27, '[38;5;235m'
    w1_esc_2_len equ $ - w1_esc_2
    w1_esc_3: db 27, '[38;5;233m'
    w1_esc_3_len equ $ - w1_esc_3

    ; Wall Type 2: Brick / Lab (Deep Rust: 130, 88, 52, 16)
    w2_esc_0: db 27, '[38;5;130m'
    w2_esc_0_len equ $ - w2_esc_0
    w2_esc_1: db 27, '[38;5;88m'
    w2_esc_1_len equ $ - w2_esc_1
    w2_esc_2: db 27, '[38;5;52m'
    w2_esc_2_len equ $ - w2_esc_2
    w2_esc_3: db 27, '[38;5;16m'
    w2_esc_3_len equ $ - w2_esc_3

    ; Wall Type 3: Metal / Sci-Fi (Dark Gunmetal: 66, 24, 23, 16)
    w3_esc_0: db 27, '[38;5;66m'
    w3_esc_0_len equ $ - w3_esc_0
    w3_esc_1: db 27, '[38;5;24m'
    w3_esc_1_len equ $ - w3_esc_1
    w3_esc_2: db 27, '[38;5;23m'
    w3_esc_2_len equ $ - w3_esc_2
    w3_esc_3: db 27, '[38;5;16m'
    w3_esc_3_len equ $ - w3_esc_3

    ; Wall Type 4: Wood / Paneling (Dark Moss/Grime: 100, 58, 22, 16)
    w4_esc_0: db 27, '[38;5;100m'
    w4_esc_0_len equ $ - w4_esc_0
    w4_esc_1: db 27, '[38;5;58m'
    w4_esc_1_len equ $ - w4_esc_1
    w4_esc_2: db 27, '[38;5;22m'
    w4_esc_2_len equ $ - w4_esc_2
    w4_esc_3: db 27, '[38;5;16m'
    w4_esc_3_len equ $ - w4_esc_3

    ; Wall Type 5: Door (Neon Orange accent: 208, 166, 130, 94)
    w5_esc_0: db 27, '[38;5;208m'
    w5_esc_0_len equ $ - w5_esc_0
    w5_esc_1: db 27, '[38;5;166m'
    w5_esc_1_len equ $ - w5_esc_1
    w5_esc_2: db 27, '[38;5;130m'
    w5_esc_2_len equ $ - w5_esc_2
    w5_esc_3: db 27, '[38;5;94m'
    w5_esc_3_len equ $ - w5_esc_3

wall_color_ptrs:
    dq w1_esc_0, w1_esc_1, w1_esc_2, w1_esc_3
    dq w2_esc_0, w2_esc_1, w2_esc_2, w2_esc_3
    dq w3_esc_0, w3_esc_1, w3_esc_2, w3_esc_3
    dq w4_esc_0, w4_esc_1, w4_esc_2, w4_esc_3
    dq w5_esc_0, w5_esc_1, w5_esc_2, w5_esc_3

wall_color_lens:
    dq w1_esc_0_len, w1_esc_1_len, w1_esc_2_len, w1_esc_3_len
    dq w2_esc_0_len, w2_esc_1_len, w2_esc_2_len, w2_esc_3_len
    dq w3_esc_0_len, w3_esc_1_len, w3_esc_2_len, w3_esc_3_len
    dq w4_esc_0_len, w4_esc_1_len, w4_esc_2_len, w4_esc_3_len
    dq w5_esc_0_len, w5_esc_1_len, w5_esc_2_len, w5_esc_3_len

    ; Ceiling colors: near horizon (dark) → near camera (lighter)
    esc_ceil_0: db 27, '[38;5;16m'       ; horizon: pitch black
    esc_ceil_0_len equ $ - esc_ceil_0
    esc_ceil_1: db 27, '[38;5;232m'      ; mid: darkest grey
    esc_ceil_1_len equ $ - esc_ceil_1
    esc_ceil_2: db 27, '[38;5;233m'      ; near camera: dark grey
    esc_ceil_2_len equ $ - esc_ceil_2

    ; Floor colors: near horizon (dark) → near camera (lighter)
    esc_floor_0: db 27, '[38;5;232m'     ; horizon: darkest grey
    esc_floor_0_len equ $ - esc_floor_0
    esc_floor_1: db 27, '[38;5;234m'     ; mid
    esc_floor_1_len equ $ - esc_floor_1
    esc_floor_2: db 27, '[38;5;236m'     ; near camera: grey
    esc_floor_2_len equ $ - esc_floor_2

    esc_color_reset: db 27, '[0m'
    esc_color_reset_len equ $ - esc_color_reset

    ; Gun HUD colors
    esc_flash: db 27, '[38;5;226m'   ; bright yellow
    esc_flash_len equ $ - esc_flash
    esc_gun:   db 27, '[38;5;67m'    ; Wolfenstein blue/grey
    esc_gun_len equ $ - esc_gun
    esc_hand:  db 27, '[38;5;216m'   ; Skin tone
    esc_hand_len equ $ - esc_hand
    
    gun_sprite:
        db 0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0 ; Row 0
        db 0,0,0,0,0,0,0,0,0,1,2,2,2,2,1,0,0,0,0,0,0,0,0,0 ; Row 1
        db 0,0,0,0,0,0,0,0,1,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0 ; Row 2
        db 0,0,0,0,0,0,0,1,2,2,2,3,3,2,2,2,1,0,0,0,0,0,0,0 ; Row 3
        db 0,0,0,0,0,0,1,2,2,3,3,3,3,3,3,2,2,1,0,0,0,0,0,0 ; Row 4
        db 0,0,0,0,0,1,2,2,3,3,3,4,4,3,3,3,2,2,1,0,0,0,0,0 ; Row 5
        db 0,0,0,0,1,2,2,3,3,4,4,4,4,4,4,3,3,2,2,1,0,0,0,0 ; Row 6
        db 0,0,0,1,2,2,3,3,4,4,4,4,4,4,4,4,3,3,2,2,1,0,0,0 ; Row 7
        db 0,0,1,2,2,3,3,4,4,4,4,4,4,4,4,4,4,3,3,2,2,1,0,0 ; Row 8
    gun_sprite_w equ 24
    gun_sprite_h equ 9
    
    hand_sprite:
        db 0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0 ; Row 0
        db 0,0,0,0,1,2,2,2,1,1,1,1,1,1,2,2,2,1,0,0,0,0,0,0 ; Row 1
        db 0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0 ; Row 2
        db 0,0,1,2,2,2,3,3,3,3,3,3,3,3,3,3,2,2,2,1,0,0,0,0 ; Row 3
        db 0,1,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0,0,0 ; Row 4
        db 1,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0,0 ; Row 5
        db 1,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0 ; Row 6
        db 1,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0 ; Row 7
    hand_sprite_w equ 24
    hand_sprite_h equ 8

    flash_sprite:
        db 0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0 ; Row 0
        db 0,0,0,0,0,0,0,0,0,1,2,2,2,2,1,0,0,0,0,0,0,0,0,0 ; Row 1
        db 0,0,0,0,0,0,0,0,1,2,3,3,3,3,2,1,0,0,0,0,0,0,0,0 ; Row 2
        db 0,0,0,0,0,0,0,1,2,3,3,4,4,3,3,2,1,0,0,0,0,0,0,0 ; Row 3
        db 0,0,0,0,0,0,1,2,3,3,4,4,4,4,3,3,2,1,0,0,0,0,0,0 ; Row 4
        db 0,0,0,0,0,1,2,3,4,4,4,4,4,4,4,4,3,2,1,0,0,0,0,0 ; Row 5
    flash_sprite_w equ 24
    flash_sprite_h equ 6

    ; Indexed by shade tier 0-3 in wall_color_ptrs / wall_color_lens

    ; Floor color escape table: indexed by floor band 0-2

    ss_title:  db "B A R E M E T A L"
    ss_title_len equ $ - ss_title
    ss_pixel_title: db "BAREMETAL"
    ss_pixel_title_len equ $ - ss_pixel_title
    ss_rule:   db "----------------------"
    ss_rule_len equ $ - ss_rule
    ss_sub:    db "a raycaster in x86-64 assembly"
    ss_sub_len equ $ - ss_sub
    ss_box_top:
        db 27, '[97m'                ; esc_white_fg
        db 0xE2, 0x94, 0x8C          ; ┌
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x90          ; ┐
    ss_box_top_len equ $ - ss_box_top

    ss_box_ctrl1:
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[93m', "  W / S "            ; [esc_yellow] keys (8 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[97m', "  forward / back    "   ; [esc_white] desc (20 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
    ss_box_ctrl1_len equ $ - ss_box_ctrl1

    ss_box_ctrl2:
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[93m', "  A / D "            ; [esc_yellow] keys (8 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[97m', "  turn left / right "   ; [esc_white] desc (20 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
    ss_box_ctrl2_len equ $ - ss_box_ctrl2

    ss_box_ctrl3:
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[93m', "  E     "            ; [esc_yellow] keys (8 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[97m', "  use / toggle door "   ; [esc_white] desc (20 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
    ss_box_ctrl3_len equ $ - ss_box_ctrl3

    ss_box_ctrl4:
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[93m', "  Q     "            ; [esc_yellow] keys (8 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
        db 27, '[97m', "  quit              "   ; [esc_white] desc (20 chars)
        db 27, '[97m', 0xE2, 0x94, 0x82   ; [esc_white] │
    ss_box_ctrl4_len equ $ - ss_box_ctrl4

    ss_box_div:
        db 27, '[97m'
        db 0xE2, 0x94, 0x9C          ; ├
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0xA4          ; ┤
    ss_box_div_len equ $ - ss_box_div

    ss_box_ctrl5:
        db 27, '[97m', 0xE2, 0x94, 0x82   ; │
        db 27, '[93m', "  E     "            ; keys
        db 27, '[97m', 0xE2, 0x94, 0x82   ; │
        db 27, '[97m', " toggle map editor  "   ; desc
        db 27, '[97m', 0xE2, 0x94, 0x82   ; │
    ss_box_ctrl5_len equ $ - ss_box_ctrl5

    ss_box_bot:
        db 27, '[97m'                ; esc_white_fg
        db 0xE2, 0x94, 0x94          ; └
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80, 0xE2, 0x94, 0x80
        db 0xE2, 0x94, 0x98          ; ┘
        db 27, '[0m'                 ; esc_color_reset
    ss_box_bot_len equ $ - ss_box_bot
    ss_prompt: db "[ PRESS ANY KEY TO START ]"
    ss_prompt_len equ $ - ss_prompt

    ; Minimap cell styles matching the editor
    mmap_cell_empty:  db 27, '[90m', '.', 27, '[0m'
    mmap_cell_empty_len equ $ - mmap_cell_empty

    mmap_cell_stone:  db 27, '[37m', 0xE2, 0x96, 0x88, 27, '[0m'
    mmap_cell_stone_len equ $ - mmap_cell_stone

    mmap_cell_brick:  db 27, '[31m', 0xE2, 0x96, 0x88, 27, '[0m'
    mmap_cell_brick_len equ $ - mmap_cell_brick

    mmap_cell_metal:  db 27, '[36m', 0xE2, 0x96, 0x88, 27, '[0m'
    mmap_cell_metal_len equ $ - mmap_cell_metal

    mmap_cell_wood:   db 27, '[33m', 0xE2, 0x96, 0x88, 27, '[0m'
    mmap_cell_wood_len equ $ - mmap_cell_wood

    mmap_cell_door:   db 27, '[32m', 'D', 27, '[0m'
    mmap_cell_door_len equ $ - mmap_cell_door

    mmap_cell_player_prefix: db 27, '[35;1m'
    mmap_cell_player_prefix_len equ $ - mmap_cell_player_prefix

    mmap_cell_barrel: db 27, '[33m', 'B', 27, '[0m'
    mmap_cell_barrel_len equ $ - mmap_cell_barrel

    mmap_cell_pillar: db 27, '[32m', 'L', 27, '[0m'
    mmap_cell_pillar_len equ $ - mmap_cell_pillar

    mmap_cell_key:    db 27, '[33;1m', 'K', 27, '[0m'
    mmap_cell_key_len equ $ - mmap_cell_key

    mmap_cell_enemy:  db 27, '[31;1m', 'E', 27, '[0m'
    mmap_cell_enemy_len equ $ - mmap_cell_enemy

    ; HUD strings
    hud_fps:   db " FPS:"
    hud_fps_len equ $ - hud_fps
    hud_pos:   db "  POS:"
    hud_pos_len equ $ - hud_pos
    hud_comma: db ","
    hud_comma_len equ $ - hud_comma
    hud_ang:   db "  ANG:"
    hud_ang_len equ $ - hud_ang
    hud_space: db " "
    hud_space_len equ $ - hud_space
    hud_hp:    db "  HP:"
    hud_hp_len equ $ - hud_hp
    hud_game_over: db "  GAME OVER "
    hud_game_over_len equ $ - hud_game_over

    esc_red_bg: db 27, '[41;97m'
    esc_red_bg_len equ $ - esc_red_bg
    
    esc_red_bg_only: db 27, '[41m'
    esc_red_bg_only_len equ $ - esc_red_bg_only

    esc_black_fg: db 27, '[30m'
    esc_black_fg_len equ $ - esc_black_fg

    esc_white_fg: db 27, '[97m'
    esc_white_fg_len equ $ - esc_white_fg

    esc_yellow_fg: db 27, '[93m'
    esc_yellow_fg_len equ $ - esc_yellow_fg

    go_str_pad: db "                       "
    go_str_txt: db "   GAME OVER   "
    go_str_len equ 17

    go_pixel_txt: db "GAME OVER"
    go_pixel_len equ $ - go_pixel_txt
    go_sub_txt:   db "[ PRESS Q TO QUIT ]"
    go_sub_len equ $ - go_sub_txt

    vic_pixel_txt: db "YOU WIN"
    vic_pixel_len equ $ - vic_pixel_txt
    vic_sub_txt:   db "[ PRESS Q TO QUIT ]"
    vic_sub_len equ $ - vic_sub_txt
    
    esc_green_bg_only: db 27, '[42m'
    esc_green_bg_only_len equ $ - esc_green_bg_only


    global font_table
    font_table:
        times 32 * 5 db 0   ; ASCII 0..31
        ; Space (32)
        db 0, 0, 0, 0, 0
        times (65 - 33) * 5 db 0 ; ASCII 33..64
        ; A (65)
        db 0x0E, 0x11, 0x1F, 0x11, 0x11
        ; B (66)
        db 0x1E, 0x11, 0x1E, 0x11, 0x1E
        ; C (67)
        db 0x0F, 0x10, 0x10, 0x10, 0x0F
        ; D (68)
        db 0x1D, 0x11, 0x11, 0x11, 0x1D
        ; E (69)
        db 0x1F, 0x10, 0x1E, 0x10, 0x1F
        ; F (70)
        db 0x1F, 0x10, 0x1E, 0x10, 0x10
        ; G (71)
        db 0x0F, 0x10, 0x17, 0x11, 0x0F
        ; H (72)
        db 0x11, 0x11, 0x1F, 0x11, 0x11
        ; I (73)
        db 0x0E, 0x04, 0x04, 0x04, 0x0E
        ; J (74)
        db 0x07, 0x02, 0x02, 0x12, 0x0C
        ; K (75)
        db 0x11, 0x12, 0x1C, 0x12, 0x11
        ; L (76)
        db 0x10, 0x10, 0x10, 0x10, 0x1F
        ; M (77)
        db 0x11, 0x1B, 0x15, 0x11, 0x11
        ; N (78)
        db 0x11, 0x19, 0x15, 0x13, 0x11
        ; O (79)
        db 0x0E, 0x11, 0x11, 0x11, 0x0E
        ; P (80)
        db 0x1E, 0x11, 0x1E, 0x10, 0x10
        ; Q (81)
        db 0x0E, 0x11, 0x11, 0x13, 0x0D
        ; R (82)
        db 0x1E, 0x11, 0x1E, 0x14, 0x12
        ; S (83)
        db 0x0F, 0x10, 0x0E, 0x01, 0x1E
        ; T (84)
        db 0x1F, 0x04, 0x04, 0x04, 0x04
        ; U (85)
        db 0x11, 0x11, 0x11, 0x11, 0x0E
        ; V (86)
        db 0x11, 0x11, 0x11, 0x0A, 0x04
        ; W (87)
        db 0x11, 0x11, 0x15, 0x1B, 0x11
        ; X (88)
        db 0x11, 0x0A, 0x04, 0x0A, 0x11
        ; Y (89)
        db 0x11, 0x11, 0x0A, 0x04, 0x04
        ; Z (90)
        db 0x1F, 0x02, 0x04, 0x08, 0x1F
        times (128 - 91) * 5 db 0 ; rest of ASCII

    ; FPS counter state
    global frame_count
    frame_count: dq 0
    last_fps:    dq 60

    ; --- Sprite Data ---
    NUM_SPRITES equ 8

    global sprite_x, sprite_y, sprite_type, sprite_active
    sprite_x:
        dq (13 << 8) | 128   ; Sprite 0: Barrel in NW room
        dq (18 << 8) | 128   ; Sprite 1: Barrel in NE room
        dq (6 << 8) | 128    ; Sprite 2: Pillar in SW room
        dq (25 << 8) | 128   ; Sprite 3: Pillar in SE room
        dq (15 << 8) | 128   ; Sprite 4: Key in corridor
        dq (16 << 8) | 128   ; Sprite 5: Key in corridor
        dq (24 << 8) | 128   ; Sprite 6: Enemy 0 in SE room
        dq (6 << 8) | 128    ; Sprite 7: Enemy 1 in SW room

    sprite_y:
        dq (6 << 8) | 128
        dq (6 << 8) | 128
        dq (25 << 8) | 128
        dq (25 << 8) | 128
        dq (10 << 8) | 128
        dq (22 << 8) | 128
        dq (10 << 8) | 128
        dq (22 << 8) | 128

    sprite_type:
        db 0                 ; 0 = barrel
        db 0                 ; 1 = barrel
        db 1                 ; 2 = pillar
        db 1                 ; 3 = pillar
        db 2                 ; 4 = key
        db 2                 ; 5 = key
        db 3                 ; 6 = enemy
        db 3                 ; 7 = enemy

    sprite_active:
        db 1, 1, 1, 1, 1, 1, 1, 1  ; all active

    ; Sprite ANSI colors
    esc_sprite_green: db 27, '[38;5;46m'
    esc_sprite_green_len equ $ - esc_sprite_green

    esc_sprite_white: db 27, '[38;5;250m'
    esc_sprite_white_len equ $ - esc_sprite_white

    esc_sprite_gold:  db 27, '[38;5;220m'
    esc_sprite_gold_len equ $ - esc_sprite_gold

    esc_sprite_red:   db 27, '[38;5;196m'
    esc_sprite_red_len equ $ - esc_sprite_red
    
    esc_sprite_darkred: db 27, '[38;5;52m'
    esc_sprite_darkred_len equ $ - esc_sprite_darkred

    sprite_color_ptrs:
        dq esc_sprite_green
        dq esc_sprite_white
        dq esc_sprite_gold
        dq esc_sprite_red       ; type 3: Enemy Alive
        dq esc_sprite_darkred   ; type 4: Enemy Dead

    sprite_color_lens:
        dq esc_sprite_green_len
        dq esc_sprite_white_len
        dq esc_sprite_gold_len
        dq esc_sprite_red_len
        dq esc_sprite_darkred_len

    ; Scales in Q8 (256 = 1.0 = full wall size)
    sprite_scale_x:
        dq 192, 256, 128, 192, 256   ; barrel, pillar, key, enemy, dead
    sprite_scale_y:
        dq 192, 256, 128, 192, 64    ; dead enemy is flat (scale 64)

    ; --- Enemy Logic Data ---
    NUM_ENEMIES equ 2
    global enemy_x, enemy_y, enemy_state, enemy_health, enemy_sprite_idx, enemy_timer
    
    enemy_x: dq (24 << 8) | 128, (6 << 8) | 128
    enemy_y: dq (10 << 8) | 128, (22 << 8) | 128
    enemy_state: db 1, 1       ; 1 = Idle
    enemy_health: db 100, 100
    enemy_sprite_idx: db 6, 7  ; maps to sprite_x/y indices
    enemy_timer: db 0, 0

section .bss

BUFFER_SIZE equ 262144          ; 256KB (extra headroom for color escapes)
frame_buffer: resb BUFFER_SIZE
global buf_pos, z_buffer, render_scr_cols
buf_pos:      resq 1          ; write head

MAX_SCREEN_COLS equ 512
MAX_SCREEN_ROWS equ 500        ; was 200; col_top/col_bot are now words
col_char:  resb MAX_SCREEN_COLS  ; UTF-8 third byte of wall shade block char
col_color: resb MAX_SCREEN_COLS  ; shade tier index (0=near .. 3=far)
col_wall_type: resb MAX_SCREEN_COLS ; wall type (1-5)
col_top:   resw MAX_SCREEN_COLS  ; first wall row (0-indexed interior), word
col_bot:   resw MAX_SCREEN_COLS  ; last  wall row (0-indexed interior), word
last_fps_time: resb 16
z_buffer:  resq MAX_SCREEN_COLS
u_buffer:  resq MAX_SCREEN_COLS
sprite_order:  resb NUM_SPRITES
sprite_depths: resq NUM_SPRITES
sprite_trans_x: resq NUM_SPRITES
sprite_trans_y: resq NUM_SPRITES

render_scr_cols: resq 1   ; = term_cols - 2
render_scr_rows: resq 1   ; = term_rows - 2

mmap_content_col: resq 1  ; = render_scr_cols - MMAP_W  (first map cell col)
mmap_border_col:  resq 1  ; = render_scr_cols - MMAP_W - 1  (│ separator)

