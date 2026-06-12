%include "render_data.asm"
%include "render_utils.asm"
; border + blank interior, called once at startup
render_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    call clear_buffer

    mov r14, [rel term_cols]
    mov r15, [rel term_rows]

    mov rdi, 1
    mov rsi, 1
    lea rdx, [rel border_tl]
    mov rcx, 3
    call draw_bytes_at

    mov r12, 2
.top_border:
    cmp r12, r14
    jge .top_border_end
    mov rdi, 1
    mov rsi, r12
    lea rdx, [rel border_horiz]
    mov rcx, 3
    call draw_bytes_at
    inc r12
    jmp .top_border
.top_border_end:

    mov rdi, 1
    mov rsi, r14
    lea rdx, [rel border_tr]
    mov rcx, 3
    call draw_bytes_at

    mov r13, 2
.side_borders:
    cmp r13, r15
    jge .side_borders_end

    mov rdi, r13
    mov rsi, 1
    lea rdx, [rel border_vert]
    mov rcx, 3
    call draw_bytes_at

    mov rdi, r13
    mov rsi, 2
    call append_cursor_move
    mov rcx, r14
    sub rcx, 2                 ; term_cols - 2 interior columns
    lea rsi, [rel spaces_row]
    call append_bytes

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel border_vert]
    mov rcx, 3
    call draw_bytes_at

    inc r13
    jmp .side_borders
.side_borders_end:

    mov rdi, r15
    mov rsi, 1
    lea rdx, [rel border_bl]
    mov rcx, 3
    call draw_bytes_at

    mov r12, 2
.bottom_border:
    cmp r12, r14
    jge .bottom_border_end
    mov rdi, r15
    mov rsi, r12
    lea rdx, [rel border_horiz]
    mov rcx, 3
    call draw_bytes_at
    inc r12
    jmp .bottom_border
.bottom_border_end:

    mov rdi, r15
    mov rsi, r14
    lea rdx, [rel border_br]
    mov rcx, 3
    call draw_bytes_at

    call flush_buffer

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; Pass 1: ray per column → col_char/col_top/col_bot
; Pass 2: row-major emit  ceiling=' '  floor='.'  wall=UTF-8 block
; FOV 60°, interior = term_cols/rows - 2, capped at MAX_SCREEN_COLS/ROWS
render_frame:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88             ; 16-byte alignment + locals
                            ; [rsp]   = last_color (qword)
                            ; [rsp+8] = floor_band (byte)
                            ; [rsp+16] = mmap_ox (qword)
                            ; [rsp+24] = mmap_oy (qword)
                            ; [rsp+32] = orig_col_start (qword)
                            ; [rsp+40] = orig_row_top (qword)
                            ; [rsp+48] = sprite_w (qword)
                            ; [rsp+56] = sprite_h (qword)
                            ; [rsp+64] = clamped_row_top (qword)
                            ; [rsp+72] = clamped_row_bot (qword)
                            ; [rsp+80] = unused alignment padding (qword)

    ; Initialize last_fps_time if it's 0
    mov rax, [rel last_fps_time]
    test rax, rax
    jnz .fps_init_done
    lea rdi, [rel last_fps_time]
    call get_time
.fps_init_done:

    inc qword [rel frame_count]
    mov rax, [rel frame_count]
    cmp rax, 60
    jl .fps_done

    ; Calculate FPS
    mov qword [rel frame_count], 0
    
    sub rsp, 16                     ; allocate temporary timespec
    mov rdi, rsp
    call get_time
    
    lea rdi, [rel last_fps_time]
    mov rsi, rsp
    call elapsed_ns                 ; rax = elapsed nanoseconds
    
    test rax, rax
    jle .fps_zero
    
    mov r8, rax                     ; r8 = elapsed ns
    mov rax, 60000000000            ; 60 * 1,000,000,000
    xor rdx, rdx
    div r8                          ; rax = 60,000,000,000 / elapsed_ns
    mov [rel last_fps], rax
    jmp .fps_save_time

.fps_zero:
    mov qword [rel last_fps], 999   ; default/error

.fps_save_time:
    ; copy temporary timespec (at rsp) to last_fps_time
    mov rdi, [rsp]
    mov [rel last_fps_time], rdi
    mov rdi, [rsp + 8]
    mov [rel last_fps_time + 8], rdi
    
    add rsp, 16
.fps_done:

    mov rax, [rel term_cols]
    sub rax, 2
    cmp rax, MAX_SCREEN_COLS
    jle .cols_ok
    mov rax, MAX_SCREEN_COLS
.cols_ok:
    mov [rel render_scr_cols], rax

    mov rax, [rel term_rows]
    sub rax, 2
    cmp rax, MAX_SCREEN_ROWS
    jle .rows_ok
    mov rax, MAX_SCREEN_ROWS
.rows_ok:
    mov [rel render_scr_rows], rax

    mov rax, [rel render_scr_cols]
    sub rax, MMAP_W
    mov [rel mmap_content_col], rax   ; first minimap content col
    dec rax
    mov [rel mmap_border_col], rax    ; left separator col

    xor r12, r12            ; c = 0

.cast_loop:
    mov r8, [rel render_scr_cols]
    cmp r12, r8
    jge .cast_done

    ; divisor = screen_cols - 1; guard against degenerate 1-column terminal
    mov rcx, r8
    dec rcx
    jz .cast_done

    ; ray_angle = player_angle - FOV_HALF + (c * FOV_TOTAL / (screen_cols-1))
    mov rax, r12
    imul rax, FOV_TOTAL
    cqo
    idiv rcx                ; rax = offset 0..FOV_TOTAL
    add rax, [rel player_angle]
    sub rax, FOV_HALF

    ; Normalise to 0..359
    cmp rax, 0
    jge .angle_pos
    add rax, 360
.angle_pos:
    cmp rax, 360
    jl .angle_ok
    sub rax, 360
.angle_ok:

    mov rdi, rax
    call cast_ray           ; rax = perp_dist (cells × 1024), rdx = wall type, rcx = side
    mov rbx, rax            ; rbx = dist
    lea rax, [rel col_wall_type]
    mov [rax + r12], dl     ; save wall type before idiv clobbers it
    lea rax, [rel z_buffer]
    mov [rax + r12*8], rbx  ; save wall distance to Z-buffer

    ; --- U-COORD CALCULATION ---
    push rcx
    push rdi
    push rdx
    
    lea r9, [rel cos_table]
    mov r10, [r9 + rdi*8]   ; r10 = cos(angle)
    lea r9, [rel sin_table]
    mov r11, [r9 + rdi*8]   ; r11 = sin(angle)
    
    ; Compute true_dist
    ; we need relative angle: rdi - player_angle
    mov rax, rdi
    sub rax, [rel player_angle]
    jns .rel_pos
    add rax, 360
.rel_pos:
    cmp rax, 360
    jl .rel_ok
    sub rax, 360
.rel_ok:
    lea r9, [rel cos_table]
    mov r9, [r9 + rax*8]    ; r9 = cos(relative_angle)
    
    ; true_dist = (perp_dist * 1024) / cos(rel_angle)
    mov rax, rbx
    shl rax, 10
    cqo
    idiv r9
    push r15
    mov r15, rax            ; r15 = true_dist
    
    ; Compute hit_x (r8)
    mov rax, r15            ; true_dist
    imul rax, r10           ; cos
    sar rax, 10
    add rax, [rel player_x] ; hit_x
    mov r8, rax

    ; Compute hit_y (r9)
    mov rax, r15            ; true_dist
    imul rax, r11           ; sin
    sar rax, 10
    add rax, [rel player_y] ; hit_y
    mov r9, rax
    pop r15

    cmp rcx, 0
    jne .side_y
.side_x:
    mov rax, r9             ; use hit_y for U
    jmp .calc_u
.side_y:
    mov rax, r8             ; use hit_x for U
.calc_u:
    and rax, 255            ; fraction (0-255)
    lea r10, [rel u_buffer]
    mov [r10 + r12*8], rax  ; save U (0-255)
    
    pop rdx
    pop rdi
    pop rcx
    push r8
    push r9
    ; ---------------------------

    ; wall_h = screen_rows * 1024 / dist  (capped to screen_rows)
    mov rax, [rel render_scr_rows]
    imul rax, 1024
    cqo
    idiv rbx
    mov r13, [rel render_scr_rows]
    cmp rax, r13
    jle .cap_ok
    mov rax, r13
.cap_ok:
    mov r13, rax            ; r13 = wall_h

    ; wall_top = (screen_rows - wall_h) / 2
    mov rax, [rel render_scr_rows]
    sub rax, r13
    sar rax, 1
    mov r14, rax            ; r14 = wall_top

    ; wall_bot = wall_top + wall_h - 1
    lea r15, [r14 + r13 - 1]

    ; Shade: pick color tier by distance
    cmp rbx, SHADE_NEAR
    jl .shade_near
    cmp rbx, SHADE_MED
    jl .shade_dark
    cmp rbx, SHADE_FAR
    jl .shade_med
    mov al, BLOCK_LIGHT
    mov cl, 3                   ; color tier 3 (farthest)
    jmp .shade_done
.shade_near:
    mov al, BLOCK_FULL
    mov cl, 0                   ; color tier 0 (nearest)
    jmp .shade_done
.shade_dark:
    mov al, BLOCK_DARK
    mov cl, 1                   ; color tier 1
    jmp .shade_done
.shade_med:
    mov al, BLOCK_MED
    mov cl, 2                   ; color tier 2
.shade_done:

    ; Apply Point Lights
    pop r9                      ; pop hit_y
    pop r8                      ; pop hit_x
    
    extern num_lights, light_x, light_y, light_r, light_i
    push rdi
    mov rdi, [rel num_lights]
    xor r10, r10                ; max light intensity
.light_loop:
    test rdi, rdi
    jz .light_done
    dec rdi
    
    ; dx^2
    mov rax, r8
    lea r11, [rel light_x]
    sub rax, [r11 + rdi*8]
    imul rax, rax
    ; dy^2
    mov rdx, r9
    lea r11, [rel light_y]
    sub rdx, [r11 + rdi*8]
    imul rdx, rdx
    
    add rax, rdx                ; dist^2
    lea r11, [rel light_r]
    cmp rax, [r11 + rdi*8]
    jg .light_loop
    
    lea r11, [rel light_i]
    mov rax, [r11 + rdi*8]
    cmp rax, r10
    jle .light_loop
    mov r10, rax
    jmp .light_loop

.light_done:
    pop rdi
    
    ; Apply intensity reduction to tier (cl)
    shr r10, 1                  ; tier reduction = intensity / 2
    sub cl, r10b
    jns .cl_ok
    xor cl, cl                  ; clamp to 0 (brightest)
.cl_ok:

    lea rdx, [rel col_char]
    mov [rdx + r12], al
    lea rdx, [rel col_color]
    mov [rdx + r12], cl
    lea rdx, [rel col_top]
    mov [rdx + r12*2], r14w     ; word store
    lea rdx, [rel col_bot]
    mov [rdx + r12*2], r15w     ; word store

    inc r12
    jmp .cast_loop

.cast_done:
    ; mmap_ox = clamp(player_x>>8 - 8, 0, MAP_WIDTH - 16)
    mov rax, [rel player_x]
    sar rax, 8
    sub rax, 8
    cmp rax, 0
    jge .ox_not_low
    xor rax, rax
.ox_not_low:
    cmp rax, 16
    jle .ox_not_high
    mov rax, 16
.ox_not_high:
    mov [rsp + 16], rax

    ; mmap_oy = clamp(player_y>>8 - 8, 0, MAP_HEIGHT - 16)
    mov rax, [rel player_y]
    sar rax, 8
    sub rax, 8
    cmp rax, 0
    jge .oy_not_low
    xor rax, rax
.oy_not_low:
    cmp rax, 16
    jle .oy_not_high
    mov rax, 16
.oy_not_high:
    mov [rsp + 24], rax

    call clear_buffer

    xor r12, r12            ; r = 0

.row_loop:
    cmp r12, [rel render_scr_rows]
    jge .frame_done

    lea rdi, [r12 + 2]
    mov rsi, 2
    call append_cursor_move

    ; emit color reset at start of each row to prevent bleed
    call emit_color_reset

    ; band = 0 (dark/horizon), 1 (mid), 2 (near camera/bright)
    mov rax, [rel render_scr_rows]
    sar rax, 1                  ; center = rows/2
    mov rcx, r12
    sub rcx, rax                ; rcx = row - center (signed)
    ; abs(rcx)
    mov rdx, rcx
    sar rdx, 63
    xor rcx, rdx
    sub rcx, rdx                ; rcx = abs(row - center)
    ; band: 0-5 rows from center=0, 6-15=1, 16+=2
    cmp rcx, 5
    jle .floor_band_0
    cmp rcx, 15
    jle .floor_band_1
    mov byte [rsp + 8], 2
    jmp .floor_band_done
.floor_band_0:
    mov byte [rsp + 8], 0
    jmp .floor_band_done
.floor_band_1:
    mov byte [rsp + 8], 1
.floor_band_done:
    
    ; Flash override: if gun_fire_timer > 0, force band 2
    extern gun_fire_timer
    mov rax, [rel gun_fire_timer]
    test rax, rax
    jz .floor_band_flash_done
    mov byte [rsp + 8], 2
.floor_band_flash_done:

    xor r13, r13            ; c = 0
    mov qword [rsp], -1        ; last_color = -1 (none set)

.col_loop:
    cmp r13, [rel render_scr_cols]
    jge .row_done

    ; minimap bottom border row (r12 == MMAP_H): left=raycaster, sep=└, right=─
    cmp r12, MMAP_H
    jne .check_sep_col
    cmp r13, [rel mmap_border_col]
    jl .raycaster_col
    je .mm_corner_bl
    ; emit reset before minimap border chars
    call emit_color_reset
    mov rdi, [rel buf_pos]          ; ─ horizontal bar
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x94
    mov byte [rdi+2], 0x80
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.mm_corner_bl:
    call emit_color_reset
    mov rdi, [rel buf_pos]          ; └ corner
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x94
    mov byte [rdi+2], 0x94
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.check_sep_col:
    ; flags still set from cmp r12, MMAP_H; r12 != MMAP_H here
    jg .raycaster_col              ; rows > MMAP_H: always raycaster
    cmp r13, [rel mmap_border_col]
    jl .raycaster_col
    je .mm_vert

    ; r13 > mmap_border_col → minimap content zone
    ; emit reset for minimap text
    call emit_color_reset
    mov rcx, r13
    sub rcx, [rel mmap_content_col] ; rcx = minimap_x

    ; player minimap x: rax = player_x>>8 - mmap_ox
    mov rax, [rel player_x]
    sar rax, 8
    sub rax, [rsp + 16]
    cmp rcx, rax
    jne .mm_check_wall

    ; player minimap y: rax = player_y>>8 - mmap_oy
    mov rax, [rel player_y]
    sar rax, 8
    sub rax, [rsp + 24]
    cmp r12, rax
    jne .mm_check_wall

    ; directional player marker based on player_angle
    mov rax, [rel player_angle]
    cmp rax, 45
    jl .mm_dir_east
    cmp rax, 135
    jl .mm_dir_south
    cmp rax, 225
    jl .mm_dir_west
    cmp rax, 315
    jl .mm_dir_north
.mm_dir_east:
    mov dl, '>'
    jmp .mm_dir_emit
.mm_dir_south:
    mov dl, 'v'
    jmp .mm_dir_emit
.mm_dir_west:
    mov dl, '<'
    jmp .mm_dir_emit
.mm_dir_north:
    mov dl, '^'
.mm_dir_emit:
    mov rdi, [rel buf_pos]
    mov [rdi], dl
    inc rdi
    mov [rel buf_pos], rdi
    jmp .col_next

.mm_vert:
    call emit_color_reset
    mov rdi, [rel buf_pos]          ; │ vertical separator
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x94
    mov byte [rdi+2], 0x82
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.mm_check_wall:
    mov rax, r12
    add rax, [rsp + 24]             ; rax = r12 + mmap_oy
    imul rax, MAP_WIDTH             ; rax = (r12 + mmap_oy) * MAP_WIDTH
    mov rbx, rcx
    add rbx, [rsp + 16]             ; rbx = minimap_x + mmap_ox
    add rax, rbx                    ; rax = cell index in world_map

    lea rbx, [rel world_map]
    movzx ebx, byte [rbx + rax]     ; ebx = cell value
    mov rdi, [rel buf_pos]
    test ebx, ebx
    jz .mm_floor

    cmp ebx, WALL_DOOR
    jne .mm_wall

    ; door cell: check door_state[rax]
    lea rdx, [rel door_state]
    cmp byte [rdx + rax], 0
    jne .mm_floor                    ; door open -> show floor '.'

    ; door closed -> show '+'
    mov byte [rdi], '+'
    jmp .mm_emit

.mm_wall:
    mov byte [rdi], '#'
    jmp .mm_emit

.mm_floor:
    mov byte [rdi], '.'

.mm_emit:
    inc rdi
    mov [rel buf_pos], rdi
    jmp .col_next

.raycaster_col:
    lea rax, [rel col_top]
    movzx r14, word [rax + r13*2]   ; word load
    lea rax, [rel col_bot]
    movzx r15, word [rax + r13*2]   ; word load

    cmp r12, r14
    jl .emit_ceiling
    cmp r12, r15
    jg .emit_floor

    ; In Wall:
    lea rax, [rel col_color]
    movzx rbx, byte [rax + r13]     ; rbx = color tier (0-3)
    lea rax, [rel col_wall_type]
    movzx rdx, byte [rax + r13]     ; rdx = wall type (1-5)
    
    push rdx                        ; save wall type for texture lookup

    dec rdx                         ; rdx = wall_type - 1 (0-4)
    shl rdx, 2                      ; rdx = (wall_type - 1) * 4
    add rdx, rbx                    ; rdx = color category index I (0-19)
    cmp rdx, [rsp+8]                ; check against last_color (which is at rsp+8 because we pushed rdx)
    je .wall_no_color_change
    mov [rsp+8], rdx                ; update last_color
    lea rsi, [rel wall_color_ptrs]
    mov rsi, [rsi + rdx*8]
    lea rcx, [rel wall_color_lens]
    mov rcx, [rcx + rdx*8]
    call append_bytes
.wall_no_color_change:

    pop rdx                         ; restore rdx = wall type

    ; Calculate V
    ; v = (row - wall_top) * 256 / (wall_bot - wall_top + 1)
    mov rax, r12
    sub rax, r14                    ; row - wall_top
    shl rax, 8                      ; * 256
    mov rcx, r15
    sub rcx, r14
    inc rcx                         ; wall_h
    xor r8, r8
    xchg rdx, r8                    ; move wall type to r8, clear rdx for div
    div rcx                         ; rax = V (0..255)

    ; Procedural Shader: We have V in rax (0-255)
    lea rcx, [rel u_buffer]
    mov rcx, [rcx + r13*8]          ; rcx = U (0-255)

    cmp r8, 1
    je .shader_stone
    cmp r8, 2
    je .shader_brick
    cmp r8, 3
    je .shader_metal
    cmp r8, 4
    je .shader_wood

    ; Door (Type 5): panel door with horizontal lock and borders
    mov bl, 0x88
    ; lock band
    mov r10, rax
    sub r10, 128
    jns .door_v_pos
    neg r10
.door_v_pos:
    cmp r10, 16                 ; thicker lock band
    jl .shader_dark
    ; vertical borders
    cmp rcx, 24
    jl .shader_dark
    cmp rcx, 232
    jg .shader_dark
    ; top/bottom borders
    cmp rax, 24
    jl .shader_dark
    cmp rax, 232
    jg .shader_dark
    jmp .wall_block_emit

.shader_stone:
    ; Bunker Stone: solid grid border
    mov bl, 0x93                ; default: dark shade inside
    cmp rcx, 32
    jl .shader_full
    cmp rcx, 224
    jg .shader_full
    cmp rax, 32
    jl .shader_full
    cmp rax, 224
    jg .shader_full
    jmp .wall_block_emit
    
.shader_brick:
    ; Lab Tile (Wolfenstein blue tile)
    mov bl, 0x88                ; full block base
    mov r10, rax
    and r10, 63
    cmp r10, 16
    jl .shader_med              ; horizontal mortar
    mov r10, rcx
    test rax, 64                ; offset rows
    jz .brick_no_offset
    add r10, 64
.brick_no_offset:
    and r10, 127
    cmp r10, 16
    jl .shader_med              ; vertical mortar
    jmp .wall_block_emit

.shader_metal:
    ; Sci-fi grate (XOR)
    mov r10, rax
    xor r10, rcx
    test r10, 64
    jz .shader_dark
    mov bl, 0x88
    jmp .wall_block_emit

.shader_wood:
    ; Paneling
    mov bl, 0x88
    mov r10, rcx
    and r10, 31
    cmp r10, 8
    jl .shader_dark
    jmp .wall_block_emit

.shader_full:
    mov bl, 0x88
    jmp .wall_block_emit
.shader_dark:
    mov bl, 0x93
    jmp .wall_block_emit
.shader_med:
    mov bl, 0x92
    jmp .wall_block_emit
.shader_light:
    mov bl, 0x91

.wall_block_emit:
    mov rdi, [rel buf_pos]
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], bl
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.emit_ceiling:
    ; ceiling color by band (category 10+band)
    movzx rax, byte [rsp + 8]      ; floor_band
    lea rcx, [rax + 10]             ; category = 10 + band
    cmp rcx, [rsp]
    je .ceil_no_color_change
    mov [rsp], rcx
    cmp al, 0
    je .ceil_c0
    cmp al, 1
    je .ceil_c1
    lea rsi, [rel esc_ceil_2]
    mov rcx, esc_ceil_2_len
    jmp .ceil_emit_color
.ceil_c0:
    lea rsi, [rel esc_ceil_0]
    mov rcx, esc_ceil_0_len
    jmp .ceil_emit_color
.ceil_c1:
    lea rsi, [rel esc_ceil_1]
    mov rcx, esc_ceil_1_len
.ceil_emit_color:
    call append_bytes
.ceil_no_color_change:
    mov rax, r13
    imul rax, 17
    mov rcx, r12
    imul rcx, 23
    xor rax, rcx
    and rax, 63
    
    mov rdi, [rel buf_pos]
    cmp rax, 0
    jne .ceil_empty
    mov byte [rdi], 0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], 0xAA
    add rdi, 3
    jmp .ceil_char_done
.ceil_empty:
    cmp rax, 1
    jne .ceil_space
    mov byte [rdi], '.'
    inc rdi
    jmp .ceil_char_done
.ceil_space:
    mov byte [rdi], ' '
    inc rdi
.ceil_char_done:
    mov [rel buf_pos], rdi
    jmp .col_next

.emit_floor:
    ; floor color by band (category 20+band)
    movzx rax, byte [rsp + 8]      ; floor_band
    lea rcx, [rax + 20]             ; category = 20 + band
    cmp rcx, [rsp]
    je .floor_no_color_change
    mov [rsp], rcx
    ; emit floor color escape by band
    cmp al, 0
    je .floor_c0
    cmp al, 1
    je .floor_c1
    ; band 2
    lea rsi, [rel esc_floor_2]
    mov rcx, esc_floor_2_len
    jmp .floor_emit_color
.floor_c0:
    lea rsi, [rel esc_floor_0]
    mov rcx, esc_floor_0_len
    jmp .floor_emit_color
.floor_c1:
    lea rsi, [rel esc_floor_1]
    mov rcx, esc_floor_1_len
.floor_emit_color:
    call append_bytes
.floor_no_color_change:
    ; Carpet texture
    mov rdi, [rel buf_pos]
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], 0x92       ; ▒
    add rdi, 3
    mov [rel buf_pos], rdi

.col_next:
    inc r13
    jmp .col_loop

.row_done:
    inc r12
    jmp .row_loop

.frame_done:
    ; --- STEP 1: Compute sprite camera-space transforms ---
    xor r12, r12                    ; r12 = sprite index i (0..5)
.calc_sprite_loop:
    cmp r12, NUM_SPRITES
    jge .calc_sprite_done
    
    lea rax, [rel sprite_active]
    cmp byte [rax + r12], 1
    je .sprite_is_active
    
    ; inactive sprite: set depth to 0
    lea rax, [rel sprite_depths]
    mov qword [rax + r12*8], 0
    jmp .calc_sprite_next

.sprite_is_active:
    ; dx = sprite_x[i] - player_x
    lea rax, [rel sprite_x]
    mov r8, [rax + r12*8]
    sub r8, [rel player_x]          ; r8 = dx

    ; dy = sprite_y[i] - player_y
    lea rax, [rel sprite_y]
    mov r9, [rax + r12*8]
    sub r9, [rel player_y]          ; r9 = dy

    ; cos_val = cos_table[player_angle]
    mov rcx, [rel player_angle]
    lea rax, [rel cos_table]
    mov r10, [rax + rcx*8]          ; r10 = cos_val

    ; sin_val = sin_table[player_angle]
    lea rax, [rel sin_table]
    mov r11, [rax + rcx*8]          ; r11 = sin_val

    ; trans_y = (dx * cos_val + dy * sin_val) / 256 (to get Q10)
    mov rax, r8
    imul rax, r10                   ; rax = dx * cos_val (Q18)
    mov rbx, r9
    imul rbx, r11                   ; rbx = dy * sin_val (Q18)
    add rax, rbx
    sar rax, 8                      ; rax = trans_y (Q10)

    cmp rax, 0
    jg .sprite_in_front
    
    ; behind player: depth = 0
    lea rcx, [rel sprite_depths]
    mov qword [rcx + r12*8], 0
    jmp .calc_sprite_next

.sprite_in_front:
    lea rcx, [rel sprite_depths]
    mov [rcx + r12*8], rax          ; save trans_y depth for sorting
    lea rcx, [rel sprite_trans_y]
    mov [rcx + r12*8], rax          ; save trans_y depth for projection

    ; trans_x = (-dx * sin_val + dy * cos_val) / 256 (to get Q10)
    mov rax, r8
    neg rax                         ; rax = -dx
    imul rax, r11                   ; rax = -dx * sin_val (Q18)
    mov rbx, r9
    imul rbx, r10                   ; rbx = dy * cos_val (Q18)
    add rax, rbx
    sar rax, 8                      ; rax = trans_x (Q10)
    lea rcx, [rel sprite_trans_x]
    mov [rcx + r12*8], rax          ; save trans_x

.calc_sprite_next:
    inc r12
    jmp .calc_sprite_loop
.calc_sprite_done:

    ; --- STEP 2: Sort sprites by depth (Painters' Algorithm) ---
    lea rax, [rel sprite_order]
    xor rsi, rsi
.init_order_loop:
    cmp rsi, NUM_SPRITES
    jge .init_order_done
    mov [rax + rsi], sil
    inc rsi
    jmp .init_order_loop
.init_order_done:

    mov rcx, NUM_SPRITES
.sort_outer:
    dec rcx
    jz .sort_done
    xor rsi, rsi
.sort_inner:
    lea rdx, [rel sprite_order]
    movzx rax, byte [rdx + rsi]     ; rax = sprite index A
    movzx rbx, byte [rdx + rsi + 1] ; rbx = sprite index B
    
    lea rdx, [rel sprite_depths]
    mov r8, [rdx + rax*8]           ; r8 = depth A
    mov r9, [rdx + rbx*8]           ; r9 = depth B
    
    cmp r8, r9
    jge .no_swap                    ; descending order: if depth A >= depth B, no swap
    
    ; Swap indices in sprite_order
    lea rdx, [rel sprite_order]
    mov al, [rdx + rsi]
    mov bl, [rdx + rsi + 1]
    mov [rdx + rsi], bl
    mov [rdx + rsi + 1], al
.no_swap:
    inc rsi
    cmp rsi, rcx
    jl .sort_inner
    jmp .sort_outer
.sort_done:

    ; --- STEP 3: Render visible sprites ---
    xor r12, r12                    ; r12 = loop index (0..5)
.draw_sprite_loop:
    cmp r12, NUM_SPRITES
    jge .draw_sprite_done

    lea rax, [rel sprite_order]
    movzx r13, byte [rax + r12]     ; r13 = sprite index idx (0..5)

    ; Check if sprite is active and depth > 0
    lea rax, [rel sprite_depths]
    mov rax, [rax + r13*8]          ; rax = trans_y
    cmp rax, 0
    jle .draw_sprite_next           ; either inactive or behind player

    ; r14 = trans_y (depth)
    mov r14, rax
    lea rax, [rel sprite_trans_x]
    mov r15, [rax + r13*8]          ; r15 = trans_x

    ; Projection calculations:
    ; center_col = render_scr_cols / 2
    mov rax, [rel render_scr_cols]
    sar rax, 1
    mov r8, rax                     ; r8 = center_col

    ; proj_coeff = (render_scr_cols * 866) / 1000
    mov rax, [rel render_scr_cols]
    imul rax, 866
    mov rcx, 1000
    cqo
    idiv rcx                        ; rax = proj_coeff

    ; sprite_screen_x = center_col + (trans_x * proj_coeff) / trans_y
    imul rax, r15                   ; rax = trans_x * proj_coeff
    cqo
    idiv r14                        ; rax = (trans_x * proj_coeff) / trans_y
    add rax, r8                     ; rax = sprite_screen_x (integer column)
    mov r8, rax                     ; r8 = sprite_screen_x

    ; base_h = (render_scr_rows * 1024) / trans_y
    mov rax, [rel render_scr_rows]
    imul rax, 1024
    cqo
    idiv r14                        ; rax = base_h (integer rows)
    mov r10, rax                    ; r10 = base_h

    cmp r10, 0
    jle .draw_sprite_next

    ; get sprite type
    lea rax, [rel sprite_type]
    movzx rdx, byte [rax + r13]     ; rdx = sprite type (0..2)
    
    ; sprite_w = (base_h * sprite_scale_x[type]) / 256
    lea rax, [rel sprite_scale_x]
    mov rcx, [rax + rdx*8]          ; rcx = scale_x (Q8)
    mov rax, r10                    ; base_h
    imul rax, rcx
    sar rax, 8
    mov r9, rax                     ; r9 = sprite_w

    ; sprite_h = (base_h * sprite_scale_y[type]) / 256
    lea rax, [rel sprite_scale_y]
    mov rcx, [rax + rdx*8]          ; rcx = scale_y (Q8)
    mov rax, r10                    ; base_h
    imul rax, rcx
    sar rax, 8
    mov r10, rax                    ; r10 = sprite_h

    cmp r9, 0
    jle .draw_sprite_next
    cmp r10, 0
    jle .draw_sprite_next

    ; Bounding box:
    ; col_start = sprite_screen_x - sprite_w / 2
    mov rax, r9
    sar rax, 1                      ; rax = sprite_w / 2
    mov r11, r8
    sub r11, rax                    ; r11 = col_start

    ; col_end = sprite_screen_x + sprite_w / 2
    mov rbx, r8
    add rbx, rax                    ; rbx = col_end

    ; floor_y = (render_scr_rows + base_h) / 2
    mov rax, [rel render_scr_rows]
    mov rcx, [rel render_scr_rows]
    imul rcx, 1024
    push r11
    mov r11, r14
    xchg rax, rcx
    cqo
    idiv r11                        ; rax = base_h
    pop r11
    add rax, [rel render_scr_rows]  ; rax = render_scr_rows + base_h
    sar rax, 1                      ; rax = floor_y
    
    ; align sprite bottom to floor
    mov rdx, rax                    
    dec rdx                         ; rdx = row_bot = floor_y - 1
    
    mov rcx, rdx
    sub rcx, r10                    ; rcx = row_top = row_bot - sprite_h
    
    ; swap width and height for stack usage
    xchg r9, r10

    ; Save to stack:
    mov [rsp + 32], r11             ; orig_col_start
    mov [rsp + 40], rcx             ; orig_row_top
    mov [rsp + 48], r10             ; sprite_w
    mov [rsp + 56], r9              ; sprite_h

    ; Clamp col_start (r11) to 0
    cmp r11, 0
    jge .col_start_ok
    xor r11, r11
.col_start_ok:
    mov [rsp + 80], r11             ; save clamped_col_start to stack padding

    ; Clamp col_end (rbx) to render_scr_cols - 1
    mov rax, [rel render_scr_cols]
    dec rax
    cmp rbx, rax
    jle .col_end_ok
    mov rbx, rax
.col_end_ok:

    ; Clamp row_top (rcx) to 0
    cmp rcx, 0
    jge .row_top_ok
    xor rcx, rcx
.row_top_ok:

    ; Clamp row_bot (rdx) to render_scr_rows - 1
    mov rax, [rel render_scr_rows]
    dec rax
    cmp rdx, rax
    jle .row_bot_ok
    mov rdx, rax
.row_bot_ok:

    mov [rsp + 64], rcx             ; clamped_row_top
    mov [rsp + 72], rdx             ; clamped_row_bot

    ; Get sprite color escape and emit once per sprite
    lea rax, [rel sprite_type]
    movzx rdx, byte [rax + r13]     ; rdx = sprite type
    lea rax, [rel sprite_color_ptrs]
    mov rsi, [rax + rdx*8]           ; rsi = color ptr
    lea rax, [rel sprite_color_lens]
    mov rcx, [rax + rdx*8]           ; rcx = color len
    push rdi
    call append_bytes
    pop rdi

    ; Loop row r (rdi) from clamped_row_top to clamped_row_bot
    mov rdi, [rsp + 64]
.sprite_row_loop:
    mov rax, [rsp + 72]             ; clamped_row_bot
    cmp rdi, rax
    jg .sprite_row_done

    ; Calculate V once per row:
    ; v = ((r - orig_row_top) * 256) / sprite_h
    mov rax, rdi
    sub rax, [rsp + 40]
    shl rax, 8
    cqo
    idiv qword [rsp + 56]
    mov r9, rax                     ; r9 = v
    cmp r9, 0
    jge .v_not_low
    xor r9, r9
.v_not_low:
    cmp r9, 255
    jle .v_ok
    mov r9, 255
.v_ok:

    ; Track cursor state in r15. Set to -1 to force cursor move on first write of this row.
    mov r15, -1

    ; Loop column c (rsi) from clamped_col_start to clamped_col_end (rbx)
    mov rsi, [rsp + 80]             ; rsi = clamped_col_start
.sprite_col_loop:
    cmp rsi, rbx
    jg .sprite_col_done

    ; Z-buffer check: trans_y (r14) < z_buffer[c]
    lea rax, [rel z_buffer]
    mov rax, [rax + rsi*8]
    cmp r14, rax
    jge .sprite_pixel_skip

    ; Calculate U for this column:
    ; u = ((c - orig_col_start) * 256) / sprite_w
    mov rax, rsi
    sub rax, [rsp + 32]
    shl rax, 8
    cqo
    idiv qword [rsp + 48]
    mov r8, rax                     ; r8 = u
    cmp r8, 0
    jge .u_not_low
    xor r8, r8
.u_not_low:
    cmp r8, 255
    jle .u_ok
    mov r8, 255
.u_ok:

    ; Get sprite type
    lea rax, [rel sprite_type]
    movzx rdx, byte [rax + r13]
    
    cmp rdx, 0
    je .sprite_barrel
    cmp rdx, 1
    je .sprite_pillar
    cmp rdx, 3
    je .sprite_enemy
    cmp rdx, 4
    je .sprite_corpse

.sprite_item:
    ; Diamond: |u-128| + |v-128| < 100
    mov r10, r8
    sub r10, 128
    jns .i_u_pos
    neg r10
.i_u_pos:
    mov r11, r9
    sub r11, 128
    jns .i_v_pos
    neg r11
.i_v_pos:
    add r10, r11
    cmp r10, 100
    jg .sprite_pixel_skip
    mov dl, 0x88            ; solid
    jmp .sprite_pixel_emit
    
.sprite_barrel:
    ; Drum: rounded edges, horizontal bands
    ; |u-128| < 100
    mov r10, r8
    sub r10, 128
    jns .b_u_pos
    neg r10
.b_u_pos:
    cmp r10, 100
    jg .sprite_pixel_skip
    
    ; bands at v=64..80 and v=176..192
    mov dl, 0x88            ; solid block
    cmp r9, 64
    jl .sprite_pixel_emit
    cmp r9, 80
    jl .barrel_band
    cmp r9, 176
    jl .sprite_pixel_emit
    cmp r9, 192
    jl .barrel_band
    jmp .sprite_pixel_emit
.barrel_band:
    mov dl, 0x93            ; dark shade for band
    jmp .sprite_pixel_emit

.sprite_pillar:
    ; Cylinder: simple vertical shade based on |u-128|
    ; width = 80
    mov r10, r8
    sub r10, 128
    jns .p_u_pos
    neg r10
.p_u_pos:
    cmp r10, 80
    jg .sprite_pixel_skip
    mov dl, 0x88            ; center solid
    cmp r10, 60
    jl .sprite_pixel_emit
    mov dl, 0x93            ; edge dark
    jmp .sprite_pixel_emit

.sprite_enemy:
    mov rax, r8
    sub rax, 128
    imul rax, rax
    mov r11, r9
    sub r11, 128
    imul r11, r11
    add rax, r11
    cmp rax, 8000
    jg .sprite_pixel_skip

    ; Eye cutout: |u-128| < 20 and v is near center (100..130)
    mov r10, r8
    sub r10, 128
    jns .e_u_pos
    neg r10
.e_u_pos:
    cmp r10, 20
    jg .enemy_solid
    cmp r9, 100
    jl .enemy_solid
    cmp r9, 130
    jg .enemy_solid
    jmp .sprite_pixel_skip      ; cutout

.enemy_solid:
    mov dl, 0x88                ; solid block
    jmp .sprite_pixel_emit

.sprite_corpse:
    mov rax, r8
    sub rax, 128
    imul rax, rax
    mov r11, r9
    sub r11, 128
    imul r11, r11
    add rax, r11
    cmp rax, 10000
    jg .sprite_pixel_skip
    mov dl, 0x93                ; dark block for corpse

.sprite_pixel_emit:
    cmp rsi, r15
    je .no_cursor_move

    push rsi
    push rdi
    push rdx
    lea rdi, [rdi + 2]              ; row = r + 2
    lea rsi, [rsi + 2]              ; col = c + 2
    call append_cursor_move
    pop rdx
    pop rdi
    pop rsi

.no_cursor_move:
    mov rax, [rel buf_pos]
    mov byte [rax], 0xE2
    mov byte [rax+1], 0x96
    mov byte [rax+2], dl
    add rax, 3
    mov [rel buf_pos], rax
    lea r15, [rsi + 1]

.sprite_pixel_skip:
    inc rsi                         ; next column
    jmp .sprite_col_loop

.sprite_col_done:
    inc rdi                         ; next row
    jmp .sprite_row_loop

.sprite_row_done:
    call emit_color_reset

.draw_sprite_next:
    inc r12
    jmp .draw_sprite_loop
.draw_sprite_done:
    ; --- Check Game Over Overlay ---
    extern game_over_flag
    cmp qword [rel game_over_flag], 1
    je .draw_game_over

    ; --- Draw Gun HUD ---
    extern gun_fire_timer
    
    mov rdi, [rel term_rows]
    sub rdi, 17                 ; top of gun (9 rows for gun, 8 rows for hand)
    mov rsi, [rel term_cols]
    sar rsi, 1
    sub rsi, 12                 ; left of gun (half of 24 columns wide)

    mov rax, [rel gun_fire_timer]
    test rax, rax
    jz .gun_idle

    ; Recoil: move gun down by 1 row when firing
    add rdi, 1

    ; Draw Muzzle Flash ONLY for the first half of the animation
    cmp rax, 4
    jl .no_flash_sprite

    ; Muzzle flash is drawn above the gun
    push rdi
    push rsi
    sub rdi, 6                  ; flash is 6 rows high, draw it directly above the gun
    
    push rdi
    push rsi
    lea rsi, [rel esc_flash]
    mov rcx, esc_flash_len
    call append_bytes
    pop rsi
    pop rdi
    
    lea rdx, [rel flash_sprite]
    mov rcx, flash_sprite_w
    mov r8, flash_sprite_h
    call draw_pixel_sprite_at
    
    call emit_color_reset
    pop rsi
    pop rdi

.no_flash_sprite:

.gun_idle:
    ; Draw Pistol
    push rdi
    push rsi
    
    push rdi
    push rsi
    lea rsi, [rel esc_gun]
    mov rcx, esc_gun_len
    call append_bytes
    pop rsi
    pop rdi
    
    lea rdx, [rel gun_sprite]
    mov rcx, gun_sprite_w
    mov r8, gun_sprite_h
    call draw_pixel_sprite_at
    
    pop rsi
    pop rdi
    
    ; Draw Hand
    push rdi
    push rsi
    
    add rdi, 9                  ; move down by the height of the pistol
    
    push rdi
    push rsi
    lea rsi, [rel esc_hand]
    mov rcx, esc_hand_len
    call append_bytes
    pop rsi
    pop rdi
    
    lea rdx, [rel hand_sprite]
    mov rcx, hand_sprite_w
    mov r8, hand_sprite_h
    call draw_pixel_sprite_at
    
    call emit_color_reset
    pop rsi
    pop rdi

.draw_hud:
    ; --- Draw Text HUD ---
    mov rdi, [rel term_rows]
    mov rsi, 5
    call append_cursor_move

    lea rsi, [rel hud_fps]
    mov rcx, hud_fps_len
    call append_bytes

    mov rax, [rel last_fps]
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    lea rsi, [rel hud_pos]
    mov rcx, hud_pos_len
    call append_bytes

    mov rax, [rel player_x]
    sar rax, 8
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    lea rsi, [rel hud_comma]
    mov rcx, hud_comma_len
    call append_bytes

    mov rax, [rel player_y]
    sar rax, 8
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    lea rsi, [rel hud_ang]
    mov rcx, hud_ang_len
    call append_bytes

    mov rax, [rel player_angle]
    cmp rax, 100
    jge .ang_3dig
    mov rdi, [rel buf_pos]
    mov byte [rdi], '0'
    inc rdi
    mov [rel buf_pos], rdi
    cmp rax, 10
    jge .ang_3dig
    mov rdi, [rel buf_pos]
    mov byte [rdi], '0'
    inc rdi
    mov [rel buf_pos], rdi
.ang_3dig:
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    lea rsi, [rel hud_space]
    mov rcx, hud_space_len
    call append_bytes

    ; --- HP Overlay ---
    extern player_health
    lea rsi, [rel hud_hp]
    mov rcx, hud_hp_len
    call append_bytes

    mov rax, [rel player_health]
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov byte [rdi], ' '
    inc rdi
    mov [rel buf_pos], rdi

    extern game_over_flag
    cmp qword [rel game_over_flag], 1
    jne .no_game_over_text
    
    lea rsi, [rel hud_game_over]
    mov rcx, hud_game_over_len
    call append_bytes
.no_game_over_text:

    call emit_color_reset
    jmp .frame_finish

.draw_game_over:
    ; Reset buf_pos to start of frame_buffer to wipe out the rendered frame!
    lea rax, [rel frame_buffer]
    mov [rel buf_pos], rax
    
    ; Add cursor home and sync start
    lea rsi, [rel esc_cursor_home]
    mov rcx, esc_cursor_home_len
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    
    lea rsi, [rel esc_sync_start]
    mov rcx, esc_sync_start_len
    rep movsb
    mov [rel buf_pos], rdi

    ; Set red background
    lea rsi, [rel esc_red_bg_only]
    mov rcx, esc_red_bg_only_len
    call append_bytes

    ; Fill the screen area (row 2..term_rows-1) with spaces to make it entirely red
    mov r12, 2                  ; r12 = row
.fill_row_loop:
    mov rax, [rel term_rows]
    dec rax                     ; term_rows - 1
    cmp r12, rax
    jg .fill_done

    mov rdi, r12
    mov rsi, 2
    call append_cursor_move

    ; Write term_cols - 2 spaces
    mov rcx, [rel term_cols]
    sub rcx, 2                  ; rcx = columns to fill
    mov rdi, [rel buf_pos]
.space_loop:
    mov byte [rdi], ' '
    inc rdi
    dec rcx
    jnz .space_loop
    mov [rel buf_pos], rdi

    inc r12
    jmp .fill_row_loop

.fill_done:
    ; Set black foreground for block letters
    lea rsi, [rel esc_black_fg]
    mov rcx, esc_black_fg_len
    call append_bytes

    ; Center big "GAME OVER" (9 chars * 6 - 1 = 53 cols wide, 5 rows high)
    mov rdi, [rel term_rows]
    sar rdi, 1
    sub rdi, 3                  ; row = term_rows / 2 - 3
    
    mov rsi, [rel term_cols]
    sub rsi, 53                 ; term_cols - 53
    sar rsi, 1                  ; / 2
    inc rsi                     ; + 1
    cmp rsi, 2
    jge .go_col_ok
    mov rsi, 2
.go_col_ok:

    lea rdx, [rel go_pixel_txt]
    mov rcx, go_pixel_len
    call draw_pixel_str

    ; Set yellow foreground for subtitle
    lea rsi, [rel esc_yellow_fg]
    mov rcx, esc_yellow_fg_len
    call append_bytes

    ; Center subtitle (26 chars wide)
    mov rdi, [rel term_rows]
    sar rdi, 1
    add rdi, 4                  ; row = term_rows / 2 + 4
    
    mov rsi, [rel term_cols]
    sub rsi, 26                 ; term_cols - 26
    sar rsi, 1
    inc rsi
    cmp rsi, 2
    jge .sub_col_ok
    mov rsi, 2
.sub_col_ok:

    lea rdx, [rel go_sub_txt]
    mov rcx, go_sub_len
    call draw_bytes_at

    call emit_color_reset
    jmp .draw_hud

.frame_finish:
    call flush_buffer

    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%include "render_start.asm"
