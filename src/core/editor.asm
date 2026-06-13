; editor.asm: In-game map editor written in x86-64 assembly
NUM_SPRITES equ 8
section .data
    save_filename db "level.bin", 0
    
    editor_border_top:  db "┌────────────────────────────────┐", 0
    editor_border_top_len equ $ - editor_border_top - 1
    editor_border_bot:  db "└────────────────────────────────┘", 0
    editor_border_bot_len equ $ - editor_border_bot - 1
    editor_border_side: db "│", 0
    editor_border_side_len equ $ - editor_border_side - 1
    
    editor_ctrl1: db " WASD = Move cursor | 1-4 = Wall type | 5 = Door | 0/Space = Erase", 0
    editor_ctrl1_len equ $ - editor_ctrl1 - 1
    editor_ctrl2: db " P = Player Spawn | B/L/K/E = Sprite (Barrel/Pillar/Key/Enemy) | S = Save | Q = Quit", 0
    editor_ctrl2_len equ $ - editor_ctrl2 - 1
    
    status_pfx: db " CURSOR: (", 0
    status_pfx_len equ $ - status_pfx - 1
    status_comma: db ",", 0
    status_comma_len equ $ - status_comma - 1
    status_cell: db ") | CELL: ", 0
    status_cell_len equ $ - status_cell - 1
    status_sprites: db " | SPRITES: ", 0
    status_sprites_len equ $ - status_sprites - 1
    status_slash8: db "/8", 0
    status_slash8_len equ $ - status_slash8 - 1
    status_bar_sep: db " | MSG: ", 0
    status_bar_sep_len equ $ - status_bar_sep - 1
    
    txt_empty: db "Empty", 0
    txt_empty_len equ $ - txt_empty - 1
    txt_stone: db "Stone", 0
    txt_stone_len equ $ - txt_stone - 1
    txt_brick: db "Brick", 0
    txt_brick_len equ $ - txt_brick - 1
    txt_metal: db "Metal", 0
    txt_metal_len equ $ - txt_metal - 1
    txt_wood:  db "Wood", 0
    txt_wood_len equ $ - txt_wood - 1
    txt_door:  db "Door", 0
    txt_door_len equ $ - txt_door - 1
    
    txt_saved:  db 27, '[32;1mSaved successfully!', 27, '[0m', 0
    txt_saved_len equ $ - txt_saved - 1
    txt_failed: db 27, '[31;1mFailed to save!', 27, '[0m', 0
    txt_failed_len equ $ - txt_failed - 1

    esc_clear_to_eol: db 27, '[K', 0
    esc_clear_to_eol_len equ $ - esc_clear_to_eol - 1

    cell_cursor: db 27, '[47;30m', '+', 27, '[0m', 0
    cell_cursor_len equ $ - cell_cursor - 1
    cell_player: db 27, '[35;1m', 'P', 27, '[0m', 0
    cell_player_len equ $ - cell_player - 1
    cell_barrel: db 27, '[33m', 'B', 27, '[0m', 0
    cell_barrel_len equ $ - cell_barrel - 1
    cell_pillar: db 27, '[32m', 'L', 27, '[0m', 0
    cell_pillar_len equ $ - cell_pillar - 1
    cell_key: db 27, '[33;1m', 'K', 27, '[0m', 0
    cell_key_len equ $ - cell_key - 1
    cell_enemy: db 27, '[31;1m', 'E', 27, '[0m', 0
    cell_enemy_len equ $ - cell_enemy - 1
    cell_empty: db 27, '[90m', '.', 27, '[0m', 0
    cell_empty_len equ $ - cell_empty - 1
    cell_stone: db 27, '[37m', 0xE2, 0x96, 0x88, 27, '[0m', 0
    cell_stone_len equ $ - cell_stone - 1
    cell_brick: db 27, '[31m', 0xE2, 0x96, 0x88, 27, '[0m', 0
    cell_brick_len equ $ - cell_brick - 1
    cell_metal: db 27, '[36m', 0xE2, 0x96, 0x88, 27, '[0m', 0
    cell_metal_len equ $ - cell_metal - 1
    cell_wood: db 27, '[33m', 0xE2, 0x96, 0x88, 27, '[0m', 0
    cell_wood_len equ $ - cell_wood - 1
    cell_door: db 27, '[32m', 'D', 27, '[0m', 0
    cell_door_len equ $ - cell_door - 1

section .bss
    cursor_x:   resq 1
    cursor_y:   resq 1
    scroll_y:   resq 1
    editor_msg: resb 1
    exit_editor_flag: resb 1
    editor_start_row: resq 1
    editor_start_col: resq 1

section .text
    global run_editor
    extern clear_buffer, flush_buffer, draw_bytes_at, draw_char_at
    extern append_bytes, append_cursor_move, read_key, sleep_remaining
    extern player_x, player_y, player_angle, world_map
    extern sprite_x, sprite_y, sprite_type, sprite_active
    extern int_to_ascii, buf_pos
    extern term_rows, term_cols, clear_terminal_screen, draw_screen_border

run_editor:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Clear screen initially
    call clear_terminal_screen

    ; Compute centering offsets
    mov rax, [rel term_rows]
    sub rax, 23
    sar rax, 1                  ; rax = (term_rows - 23) / 2
    cmp rax, 1
    jge .row_ok
    mov rax, 1
.row_ok:
    mov [rel editor_start_row], rax

    mov rax, [rel term_cols]
    sub rax, 34
    sar rax, 1                  ; rax = (term_cols - 34) / 2
    cmp rax, 1
    jge .col_ok
    mov rax, 1
.col_ok:
    mov [rel editor_start_col], rax

    ; Initialize editor state
    mov qword [rel cursor_x], 15
    mov qword [rel cursor_y], 15
    mov qword [rel scroll_y], 0
    mov byte [rel editor_msg], 0
    mov byte [rel exit_editor_flag], 0

.editor_loop:
    call clear_buffer
    call draw_editor
    call flush_buffer

    ; Read keys
.read_key_loop:
    call read_key
    test rax, rax
    jz .sleep_tick
    
    call handle_editor_key
    cmp byte [rel exit_editor_flag], 1
    je .editor_exit
    jmp .read_key_loop

.sleep_tick:
    mov rdi, 30000000           ; 30ms sleep
    call sleep_remaining
    jmp .editor_loop

.editor_exit:
    mov byte [rel exit_editor_flag], 0
    call clear_terminal_screen
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

handle_editor_key:
    cmp al, 'w'
    je .move_up
    cmp al, 'W'
    je .move_up
    cmp al, 's'
    je .move_down
    cmp al, 'S'
    je .move_down
    cmp al, 'a'
    je .move_left
    cmp al, 'A'
    je .move_left
    cmp al, 'd'
    je .move_right
    cmp al, 'D'
    je .move_right
    
    cmp al, '1'
    je .paint_stone
    cmp al, '2'
    je .paint_brick
    cmp al, '3'
    je .paint_metal
    cmp al, '4'
    je .paint_wood
    cmp al, '5'
    je .paint_door
    
    cmp al, '0'
    je .paint_empty
    cmp al, ' '
    je .paint_empty
    
    cmp al, 'p'
    je .place_player
    cmp al, 'P'
    je .place_player
    
    cmp al, 'b'
    je .place_barrel
    cmp al, 'B'
    je .place_barrel
    cmp al, 'l'
    je .place_pillar
    cmp al, 'L'
    je .place_pillar
    cmp al, 'k'
    je .place_key
    cmp al, 'K'
    je .place_key
    cmp al, 'e'
    je .place_enemy
    cmp al, 'E'
    je .place_enemy
    
    cmp al, 's'
    je .save_level_trigger
    cmp al, 'S'
    je .save_level_trigger
    cmp al, 'q'
    je .quit_editor
    cmp al, 'Q'
    je .quit_editor
    ret

.move_up:
    mov rax, [rel cursor_y]
    test rax, rax
    jz .move_done
    dec rax
    mov [rel cursor_y], rax
    call adjust_scroll
    jmp .move_done

.move_down:
    mov rax, [rel cursor_y]
    cmp rax, 31
    jge .move_done
    inc rax
    mov [rel cursor_y], rax
    call adjust_scroll
    jmp .move_done

.move_left:
    mov rax, [rel cursor_x]
    test rax, rax
    jz .move_done
    dec rax
    mov [rel cursor_x], rax
    jmp .move_done

.move_right:
    mov rax, [rel cursor_x]
    cmp rax, 31
    jge .move_done
    inc rax
    mov [rel cursor_x], rax
    jmp .move_done

.move_done:
    ret

.paint_stone:
    mov rdi, 1
    call paint_wall
    ret
.paint_brick:
    mov rdi, 2
    call paint_wall
    ret
.paint_metal:
    mov rdi, 3
    call paint_wall
    ret
.paint_wood:
    mov rdi, 4
    call paint_wall
    ret
.paint_door:
    mov rdi, 5
    call paint_wall
    ret
.paint_empty:
    call erase_cell
    ret

.place_player:
    mov rax, [rel cursor_x]
    shl rax, 8
    or rax, 128
    mov [rel player_x], rax
    mov rax, [rel cursor_y]
    shl rax, 8
    or rax, 128
    mov [rel player_y], rax
    mov rax, [rel cursor_y]
    imul rax, 32
    add rax, [rel cursor_x]
    lea rdx, [rel world_map]
    mov byte [rdx + rax], 0
    ret

.place_barrel:
    mov r12, 0
    call place_sprite
    ret
.place_pillar:
    mov r12, 1
    call place_sprite
    ret
.place_key:
    mov r12, 2
    call place_sprite
    ret
.place_enemy:
    mov r12, 3
    call place_sprite
    ret

.save_level_trigger:
    call save_level
    ret

.quit_editor:
    mov byte [rel exit_editor_flag], 1
    ret

adjust_scroll:
    mov rax, [rel cursor_y]
    mov rbx, [rel scroll_y]
    cmp rax, rbx
    jl .scroll_up
    lea rcx, [rbx + 18]
    cmp rax, rcx
    jge .scroll_down
    ret
.scroll_up:
    mov [rel scroll_y], rax
    ret
.scroll_down:
    sub rax, 17
    mov [rel scroll_y], rax
    ret

paint_wall:
    mov rax, [rel cursor_y]
    imul rax, 32
    add rax, [rel cursor_x]
    lea r8, [rel world_map]
    mov [r8 + rax], dil
    mov rax, [rel cursor_x]
    shl rax, 8
    or rax, 128
    mov r8, rax
    mov rax, [rel cursor_y]
    shl rax, 8
    or rax, 128
    mov r9, rax
    xor rcx, rcx
.sprite_clear_loop:
    cmp rcx, NUM_SPRITES
    jge .done
    lea r10, [rel sprite_active]
    cmp byte [r10 + rcx], 1
    jne .next
    lea r10, [rel sprite_x]
    mov rax, [r10 + rcx*8]
    cmp rax, r8
    jne .next
    lea r10, [rel sprite_y]
    mov rax, [r10 + rcx*8]
    cmp rax, r9
    jne .next
    lea r10, [rel sprite_active]
    mov byte [r10 + rcx], 0
.next:
    inc rcx
    jmp .sprite_clear_loop
.done:
    ret

place_sprite:
    push rbx
    push rcx
    push rdx
    mov rax, [rel cursor_x]
    shl rax, 8
    or rax, 128
    mov r8, rax
    mov rax, [rel cursor_y]
    shl rax, 8
    or rax, 128
    mov r9, rax
    xor rcx, rcx
.search_loop:
    cmp rcx, NUM_SPRITES
    jge .search_done
    lea r10, [rel sprite_active]
    cmp byte [r10 + rcx], 1
    jne .search_next
    lea r10, [rel sprite_x]
    mov rax, [r10 + rcx*8]
    cmp rax, r8
    jne .search_next
    lea r10, [rel sprite_y]
    mov rax, [r10 + rcx*8]
    cmp rax, r9
    je .found_existing
.search_next:
    inc rcx
    jmp .search_loop
.search_done:
    xor rcx, rcx
.inactive_loop:
    cmp rcx, NUM_SPRITES
    jge .no_slot
    lea r10, [rel sprite_active]
    cmp byte [r10 + rcx], 0
    je .found_slot
    inc rcx
    jmp .inactive_loop
.no_slot:
    mov rcx, 7
.found_slot:
.found_existing:
    lea r10, [rel sprite_active]
    mov byte [r10 + rcx], 1
    lea r10, [rel sprite_x]
    mov [r10 + rcx*8], r8
    lea r10, [rel sprite_y]
    mov [r10 + rcx*8], r9
    lea r10, [rel sprite_type]
    mov byte [r10 + rcx], r12b
    mov rax, [rel cursor_y]
    imul rax, 32
    add rax, [rel cursor_x]
    lea r10, [rel world_map]
    mov byte [r10 + rax], 0
.done:
    pop rdx
    pop rcx
    pop rbx
    ret

erase_cell:
    mov rax, [rel cursor_y]
    imul rax, 32
    add rax, [rel cursor_x]
    lea r8, [rel world_map]
    mov byte [r8 + rax], 0
    mov rax, [rel cursor_x]
    shl rax, 8
    or rax, 128
    mov r8, rax
    mov rax, [rel cursor_y]
    shl rax, 8
    or rax, 128
    mov r9, rax
    xor rcx, rcx
.erase_sprite_loop:
    cmp rcx, NUM_SPRITES
    jge .erase_done
    lea r10, [rel sprite_active]
    cmp byte [r10 + rcx], 1
    jne .erase_next
    lea r10, [rel sprite_x]
    mov rax, [r10 + rcx*8]
    cmp rax, r8
    jne .erase_next
    lea r10, [rel sprite_y]
    mov rax, [r10 + rcx*8]
    cmp rax, r9
    jne .erase_next
    lea r10, [rel sprite_active]
    mov byte [r10 + rcx], 0
.erase_next:
    inc rcx
    jmp .erase_sprite_loop
.erase_done:
    ret

draw_editor:
    call draw_screen_border

    ; Top border
    mov rdi, [rel editor_start_row]
    mov rsi, [rel editor_start_col]
    lea rdx, [rel editor_border_top]
    mov rcx, editor_border_top_len
    call draw_bytes_at
    
    xor r12, r12                ; vy = 0
.draw_row_loop:
    cmp r12, 18
    jge .draw_row_done
    
    ; Left border
    mov rdi, [rel editor_start_row]
    add rdi, r12
    inc rdi                     ; row = start_row + vy + 1
    mov rsi, [rel editor_start_col] ; col = start_col
    lea rdx, [rel editor_border_side]
    mov rcx, editor_border_side_len
    call draw_bytes_at
    
    mov rbx, r12
    add rbx, [rel scroll_y]     ; rbx = my
    
    xor r13, r13                ; mx = 0
.draw_col_loop:
    cmp r13, 32
    jge .draw_col_done
    call get_cell_draw_data
    
    mov rdi, [rel editor_start_row]
    add rdi, r12
    inc rdi                     ; row = start_row + vy + 1
    mov rsi, [rel editor_start_col]
    add rsi, r13
    inc rsi                     ; col = start_col + mx + 1
    call draw_bytes_at
    
    inc r13
    jmp .draw_col_loop
.draw_col_done:
    ; Right border
    mov rdi, [rel editor_start_row]
    add rdi, r12
    inc rdi
    mov rsi, [rel editor_start_col]
    add rsi, 33                 ; col = start_col + 33
    lea rdx, [rel editor_border_side]
    mov rcx, editor_border_side_len
    call draw_bytes_at
    
    inc r12
    jmp .draw_row_loop
.draw_row_done:
    ; Bottom border
    mov rdi, [rel editor_start_row]
    add rdi, 19                 ; row = start_row + 19
    mov rsi, [rel editor_start_col]
    lea rdx, [rel editor_border_bot]
    mov rcx, editor_border_bot_len
    call draw_bytes_at
    
    call draw_status_bar
    
    mov rdi, [rel editor_start_row]
    add rdi, 21                 ; row = start_row + 21
    mov rax, [rel term_cols]
    sub rax, 68
    sar rax, 1
    cmp rax, 1
    jge .ctrl1_col_ok
    mov rax, 1
.ctrl1_col_ok:
    mov rsi, rax
    lea rdx, [rel editor_ctrl1]
    mov rcx, editor_ctrl1_len
    call draw_bytes_at
    
    mov rdi, [rel editor_start_row]
    add rdi, 22                 ; row = start_row + 22
    mov rax, [rel term_cols]
    sub rax, 84
    sar rax, 1
    cmp rax, 1
    jge .ctrl2_col_ok
    mov rax, 1
.ctrl2_col_ok:
    mov rsi, rax
    lea rdx, [rel editor_ctrl2]
    mov rcx, editor_ctrl2_len
    call draw_bytes_at
    ret

get_cell_draw_data:
    cmp rbx, [rel cursor_y]
    jne .check_player
    cmp r13, [rel cursor_x]
    jne .check_player
    lea rdx, [rel cell_cursor]
    mov rcx, cell_cursor_len
    ret
.check_player:
    mov rax, [rel player_x]
    sar rax, 8
    cmp rax, r13
    jne .check_sprites
    mov rax, [rel player_y]
    sar rax, 8
    cmp rax, rbx
    jne .check_sprites
    lea rdx, [rel cell_player]
    mov rcx, cell_player_len
    ret
.check_sprites:
    xor r8, r8
.sprite_loop:
    cmp r8, NUM_SPRITES
    jge .check_walls
    lea r10, [rel sprite_active]
    cmp byte [r10 + r8], 1
    jne .sprite_next
    lea r10, [rel sprite_x]
    mov rax, [r10 + r8*8]
    sar rax, 8
    cmp rax, r13
    jne .sprite_next
    lea r10, [rel sprite_y]
    mov rax, [r10 + r8*8]
    sar rax, 8
    cmp rax, rbx
    je .sprite_found
.sprite_next:
    inc r8
    jmp .sprite_loop
.sprite_found:
    lea r10, [rel sprite_type]
    movzx eax, byte [r10 + r8]
    cmp al, 0
    je .sprite_barrel
    cmp al, 1
    je .sprite_pillar
    cmp al, 2
    je .sprite_key
    cmp al, 3
    je .sprite_enemy
    jmp .check_walls
.sprite_barrel:
    lea rdx, [rel cell_barrel]
    mov rcx, cell_barrel_len
    ret
.sprite_pillar:
    lea rdx, [rel cell_pillar]
    mov rcx, cell_pillar_len
    ret
.sprite_key:
    lea rdx, [rel cell_key]
    mov rcx, cell_key_len
    ret
.sprite_enemy:
    lea rdx, [rel cell_enemy]
    mov rcx, cell_enemy_len
    ret
.check_walls:
    mov rax, rbx
    imul rax, 32
    add rax, r13
    lea r8, [rel world_map]
    movzx eax, byte [r8 + rax]
    cmp al, 0
    je .wall_empty
    cmp al, 1
    je .wall_stone
    cmp al, 2
    je .wall_brick
    cmp al, 3
    je .wall_metal
    cmp al, 4
    je .wall_wood
    cmp al, 5
    je .wall_door
.wall_empty:
    lea rdx, [rel cell_empty]
    mov rcx, cell_empty_len
    ret
.wall_stone:
    lea rdx, [rel cell_stone]
    mov rcx, cell_stone_len
    ret
.wall_brick:
    lea rdx, [rel cell_brick]
    mov rcx, cell_brick_len
    ret
.wall_metal:
    lea rdx, [rel cell_metal]
    mov rcx, cell_metal_len
    ret
.wall_wood:
    lea rdx, [rel cell_wood]
    mov rcx, cell_wood_len
    ret
.wall_door:
    lea rdx, [rel cell_door]
    mov rcx, cell_door_len
    ret

draw_status_bar:
    mov rdi, [rel editor_start_row]
    add rdi, 20
    mov rax, [rel term_cols]
    sub rax, 46
    sar rax, 1
    cmp rax, 1
    jge .status_col_ok
    mov rax, 1
.status_col_ok:
    mov rsi, rax
    call append_cursor_move
    lea rsi, [rel status_pfx]
    mov rcx, status_pfx_len
    call append_bytes
    mov rax, [rel cursor_x]
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi
    lea rsi, [rel status_comma]
    mov rcx, status_comma_len
    call append_bytes
    mov rax, [rel cursor_y]
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi
    lea rsi, [rel status_cell]
    mov rcx, status_cell_len
    call append_bytes
    mov rax, [rel cursor_y]
    imul rax, 32
    add rax, [rel cursor_x]
    lea r8, [rel world_map]
    movzx eax, byte [r8 + rax]
    cmp al, 0
    je .st_empty
    cmp al, 1
    je .st_stone
    cmp al, 2
    je .st_brick
    cmp al, 3
    je .st_metal
    cmp al, 4
    je .st_wood
    cmp al, 5
    je .st_door
    jmp .st_empty
.st_empty:
    lea rsi, [rel txt_empty]
    mov rcx, txt_empty_len
    jmp .st_done
.st_stone:
    lea rsi, [rel txt_stone]
    mov rcx, txt_stone_len
    jmp .st_done
.st_brick:
    lea rsi, [rel txt_brick]
    mov rcx, txt_brick_len
    jmp .st_done
.st_metal:
    lea rsi, [rel txt_metal]
    mov rcx, txt_metal_len
    jmp .st_done
.st_wood:
    lea rsi, [rel txt_wood]
    mov rcx, txt_wood_len
    jmp .st_done
.st_door:
    lea rsi, [rel txt_door]
    mov rcx, txt_door_len
    jmp .st_done
.st_done:
    call append_bytes
    xor r8, r8
    xor rcx, rcx
.cnt_loop:
    cmp rcx, NUM_SPRITES
    jge .cnt_done
    lea r10, [rel sprite_active]
    cmp byte [r10 + rcx], 1
    jne .cnt_next
    inc r8
.cnt_next:
    inc rcx
    jmp .cnt_loop
.cnt_done:
    lea rsi, [rel status_sprites]
    mov rcx, status_sprites_len
    call append_bytes
    mov rax, r8
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi
    lea rsi, [rel status_slash8]
    mov rcx, status_slash8_len
    call append_bytes
    cmp byte [rel editor_msg], 0
    je .no_msg
    lea rsi, [rel status_bar_sep]
    mov rcx, status_bar_sep_len
    call append_bytes
    cmp byte [rel editor_msg], 1
    je .msg_saved
    cmp byte [rel editor_msg], 2
    je .msg_failed
    jmp .no_msg
.msg_saved:
    lea rsi, [rel txt_saved]
    mov rcx, txt_saved_len
    call append_bytes
    jmp .no_msg
.msg_failed:
    lea rsi, [rel txt_failed]
    mov rcx, txt_failed_len
    call append_bytes
.no_msg:
    lea rsi, [rel esc_clear_to_eol]
    mov rcx, esc_clear_to_eol_len
    call append_bytes
    ret

save_level:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 1200
    mov rdi, rsp
    mov rax, [rel player_x]
    mov [rdi], rax
    mov rax, [rel player_y]
    mov [rdi + 8], rax
    mov rax, [rel player_angle]
    mov [rdi + 16], rax
    add rdi, 24
    lea rsi, [rel world_map]
    mov rcx, 1024
    rep movsb
    mov rdi, rsp
    add rdi, 1048
    lea rsi, [rel sprite_x]
    mov rcx, 64
    rep movsb
    mov rdi, rsp
    add rdi, 1112
    lea rsi, [rel sprite_y]
    mov rcx, 64
    rep movsb
    mov rdi, rsp
    add rdi, 1176
    lea rsi, [rel sprite_type]
    mov rcx, 8
    rep movsb
    mov rdi, rsp
    add rdi, 1184
    lea rsi, [rel sprite_active]
    mov rcx, 8
    rep movsb
    mov rax, 2
    lea rdi, [rel save_filename]
    mov rsi, 0x241
    mov rdx, 420
    syscall
    test rax, rax
    js .failed
    mov rbx, rax
    mov rax, 1
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 1192
    syscall
    mov rax, 3
    mov rdi, rbx
    syscall
    mov byte [rel editor_msg], 1
    jmp .done
.failed:
    mov byte [rel editor_msg], 2
.done:
    add rsp, 1200
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
