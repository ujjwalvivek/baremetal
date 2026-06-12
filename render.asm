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
    ; Wall Type 1: Stone (Grey tones: 231, 253, 245, 240)
    w1_esc_0: db 27, '[38;5;231m'
    w1_esc_0_len equ $ - w1_esc_0
    w1_esc_1: db 27, '[38;5;253m'
    w1_esc_1_len equ $ - w1_esc_1
    w1_esc_2: db 27, '[38;5;245m'
    w1_esc_2_len equ $ - w1_esc_2
    w1_esc_3: db 27, '[38;5;240m'
    w1_esc_3_len equ $ - w1_esc_3

    ; Wall Type 2: Brick (Warm red-brown: 217, 174, 131, 95)
    w2_esc_0: db 27, '[38;5;217m'
    w2_esc_0_len equ $ - w2_esc_0
    w2_esc_1: db 27, '[38;5;174m'
    w2_esc_1_len equ $ - w2_esc_1
    w2_esc_2: db 27, '[38;5;131m'
    w2_esc_2_len equ $ - w2_esc_2
    w2_esc_3: db 27, '[38;5;95m'
    w2_esc_3_len equ $ - w2_esc_3

    ; Wall Type 3: Metal (Cool steel-blue: 153, 110, 67, 60)
    w3_esc_0: db 27, '[38;5;153m'
    w3_esc_0_len equ $ - w3_esc_0
    w3_esc_1: db 27, '[38;5;110m'
    w3_esc_1_len equ $ - w3_esc_1
    w3_esc_2: db 27, '[38;5;67m'
    w3_esc_2_len equ $ - w3_esc_2
    w3_esc_3: db 27, '[38;5;60m'
    w3_esc_3_len equ $ - w3_esc_3

    ; Wall Type 4: Wood (Amber-brown: 222, 179, 136, 94)
    w4_esc_0: db 27, '[38;5;222m'
    w4_esc_0_len equ $ - w4_esc_0
    w4_esc_1: db 27, '[38;5;179m'
    w4_esc_1_len equ $ - w4_esc_1
    w4_esc_2: db 27, '[38;5;136m'
    w4_esc_2_len equ $ - w4_esc_2
    w4_esc_3: db 27, '[38;5;94m'
    w4_esc_3_len equ $ - w4_esc_3

    ; Wall Type 5: Door (Cyan accent: 123, 80, 37, 30)
    w5_esc_0: db 27, '[38;5;123m'
    w5_esc_0_len equ $ - w5_esc_0
    w5_esc_1: db 27, '[38;5;80m'
    w5_esc_1_len equ $ - w5_esc_1
    w5_esc_2: db 27, '[38;5;37m'
    w5_esc_2_len equ $ - w5_esc_2
    w5_esc_3: db 27, '[38;5;30m'
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

    ; Ceiling color: dark blue-grey
    esc_ceiling: db 27, '[38;5;236m'
    esc_ceiling_len equ $ - esc_ceiling

    ; Floor colors: near horizon (dark) → near camera (lighter)
    esc_floor_0: db 27, '[38;5;236m'       ; horizon: dark
    esc_floor_0_len equ $ - esc_floor_0
    esc_floor_1: db 27, '[38;5;240m'       ; mid
    esc_floor_1_len equ $ - esc_floor_1
    esc_floor_2: db 27, '[38;5;244m'       ; near camera: lighter
    esc_floor_2_len equ $ - esc_floor_2

    ; Color reset
    esc_color_reset: db 27, '[0m'
    esc_color_reset_len equ $ - esc_color_reset

    ; Indexed by shade tier 0-3 in wall_color_ptrs / wall_color_lens

    ; Floor color escape table: indexed by floor band 0-2

    ss_title:  db "B A R E M E T A L"
    ss_title_len equ $ - ss_title
    ss_rule:   db "----------------------"
    ss_rule_len equ $ - ss_rule
    ss_sub:    db "a raycaster in x86-64 assembly"
    ss_sub_len equ $ - ss_sub
    ss_ctrl1:  db "W / S    forward / back"
    ss_ctrl1_len equ $ - ss_ctrl1
    ss_ctrl2:  db "A / D    turn left / right"
    ss_ctrl2_len equ $ - ss_ctrl2
    ss_ctrl3:  db "E        use / toggle door"
    ss_ctrl3_len equ $ - ss_ctrl3
    ss_ctrl4:  db "Q        quit"
    ss_ctrl4_len equ $ - ss_ctrl4
    ss_prompt: db "[  press any key  ]"
    ss_prompt_len equ $ - ss_prompt

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

    ; FPS counter state
    frame_count: dq 0
    last_fps:    dq 60

section .bss

BUFFER_SIZE equ 262144          ; 256KB (extra headroom for color escapes)
frame_buffer: resb BUFFER_SIZE
global buf_pos
buf_pos:      resq 1          ; write head

MAX_SCREEN_COLS equ 512
MAX_SCREEN_ROWS equ 500        ; was 200; col_top/col_bot are now words
col_char:  resb MAX_SCREEN_COLS  ; UTF-8 third byte of wall shade block char
col_color: resb MAX_SCREEN_COLS  ; shade tier index (0=near .. 3=far)
col_wall_type: resb MAX_SCREEN_COLS ; wall type (1-5)
col_top:   resw MAX_SCREEN_COLS  ; first wall row (0-indexed interior), word
col_bot:   resw MAX_SCREEN_COLS  ; last  wall row (0-indexed interior), word
last_fps_time: resb 16

render_scr_cols: resq 1   ; = term_cols - 2
render_scr_rows: resq 1   ; = term_rows - 2

mmap_content_col: resq 1  ; = render_scr_cols - MMAP_W  (first map cell col)
mmap_border_col:  resq 1  ; = render_scr_cols - MMAP_W - 1  (│ separator)

section .text

    extern int_to_ascii
    extern term_rows
    extern term_cols
    extern player_x
    extern player_y
    extern player_angle
    extern cast_ray
    extern world_map
    extern door_state
    extern get_time
    extern elapsed_ns

FOV_HALF     equ 30         ; half of 60° FOV
FOV_TOTAL    equ 60         ; full FOV
SHADE_NEAR   equ 2048       ; perp_dist < 2 cells  → █  (cells × 1024)
SHADE_MED    equ 4096       ; perp_dist < 4 cells  → ▓
SHADE_FAR    equ 8192       ; perp_dist < 8 cells  → ▒  (else → ░)
BLOCK_FULL   equ 0x88       ; █
BLOCK_DARK   equ 0x93       ; ▓
BLOCK_MED    equ 0x92       ; ▒
BLOCK_LIGHT  equ 0x91       ; ░
WALL_DOOR    equ 5

    global render_init
    global render_frame
    global clear_buffer
    global flush_buffer
    global draw_char_at
    global draw_bytes_at
    global render_start_screen

SYS_WRITE equ 1

clear_buffer:
    push rbp
    mov rbp, rsp

    lea rax, [rel frame_buffer]
    mov [rel buf_pos], rax

    lea rsi, [rel esc_cursor_home]
    mov rcx, esc_cursor_home_len
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    mov [rel buf_pos], rdi

    lea rsi, [rel esc_sync_start]
    mov rcx, esc_sync_start_len
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    mov [rel buf_pos], rdi

    pop rbp
    ret

append_byte:
    mov rdi, [rel buf_pos]
    mov [rdi], dil
    inc rdi
    mov [rel buf_pos], rdi
    ret

append_bytes:
    push rdi
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    mov [rel buf_pos], rdi
    pop rdi
    ret

; rdi=row, rsi=col (1-indexed) → appends ESC[row;colH
append_cursor_move:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi

    mov rdi, [rel buf_pos]
    mov byte [rdi], 27
    mov byte [rdi+1], '['
    add rdi, 2
    mov [rel buf_pos], rdi

    mov rax, r12
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    mov rdi, [rel buf_pos]
    mov byte [rdi], ';'
    inc rdi
    mov [rel buf_pos], rdi

    mov rax, r13
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    mov rdi, [rel buf_pos]
    mov byte [rdi], 'H'
    inc rdi
    mov [rel buf_pos], rdi

    pop r13
    pop r12
    pop rbx
    ret

; rdi=row, rsi=col, dl=char
draw_char_at:
    push rbx
    push rdx
    call append_cursor_move
    pop rdx
    mov rdi, [rel buf_pos]
    mov [rdi], dl
    inc rdi
    mov [rel buf_pos], rdi
    pop rbx
    ret

; rdi=row, rsi=col, rdx=src, rcx=len
draw_bytes_at:
    push rbx
    push rdx
    push rcx
    call append_cursor_move
    pop rcx
    pop rsi
    call append_bytes
    pop rbx
    ret

flush_buffer:
    push rbp
    mov rbp, rsp

    ; synchronized output end: terminal paints whole frame atomically
    lea rsi, [rel esc_sync_end]
    mov rcx, esc_sync_end_len
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    mov [rel buf_pos], rdi

    mov rdx, [rel buf_pos]
    lea rsi, [rel frame_buffer]
    sub rdx, rsi

    mov rax, SYS_WRITE
    mov rdi, 1
    ; rsi already points to frame_buffer
    syscall

    pop rbp
    ret

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
    sub rsp, 40             ; 16-byte alignment + locals
                            ; [rsp]   = last_color (qword)
                            ; [rsp+8] = floor_band (byte)
                            ; [rsp+16] = mmap_ox (qword)
                            ; [rsp+24] = mmap_oy (qword)

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
    call cast_ray           ; rax = perp_dist (cells × 1024), rdx = wall type
    mov rbx, rax            ; rbx = dist
    lea rax, [rel col_wall_type]
    mov [rax + r12], dl     ; save wall type before idiv clobbers it

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

    ; Shade: pick block char variant byte + color tier by distance
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

    lea rax, [rel col_color]
    movzx rbx, byte [rax + r13]     ; rbx = color tier (0-3)
    lea rax, [rel col_wall_type]
    movzx rdx, byte [rax + r13]     ; rdx = wall type (1-5)
    dec rdx                         ; rdx = wall_type - 1 (0-4)
    shl rdx, 2                      ; rdx = (wall_type - 1) * 4
    add rdx, rbx                    ; rdx = color category index I (0-19)
    cmp rdx, [rsp]                  ; same as last_color?
    je .wall_no_color_change
    mov [rsp], rdx                  ; update last_color
    lea rsi, [rel wall_color_ptrs]
    mov rsi, [rsi + rdx*8]
    lea rcx, [rel wall_color_lens]
    mov rcx, [rcx + rdx*8]
    call append_bytes
.wall_no_color_change:

    lea rax, [rel col_char]
    movzx rbx, byte [rax + r13]
    mov rdi, [rel buf_pos]
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], bl
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.emit_ceiling:
    ; ceiling color (category 10)
    cmp qword [rsp], 10
    je .ceil_no_color_change
    mov qword [rsp], 10
    lea rsi, [rel esc_ceiling]
    mov rcx, esc_ceiling_len
    call append_bytes
.ceil_no_color_change:
    mov rdi, [rel buf_pos]
    mov byte [rdi], ' '
    inc rdi
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
    mov rdi, [rel buf_pos]
    mov byte [rdi], '.'
    inc rdi
    mov [rel buf_pos], rdi

.col_next:
    inc r13
    jmp .col_loop

.row_done:
    inc r12
    jmp .row_loop

.frame_done:
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

    call emit_color_reset
    call flush_buffer

    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; helper: append ESC[0m to buffer
emit_color_reset:
    push rsi
    push rcx
    lea rsi, [rel esc_color_reset]
    mov rcx, esc_color_reset_len
    call append_bytes
    pop rcx
    pop rsi
    ret

MMAP_W equ 16
MMAP_H equ 16


; rdi=row, rsi=ptr, rdx=len → col = max(2, (term_cols-len)/2 + 1)
draw_centered_str:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8                  ; align stack for nested calls

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    mov rax, [rel term_cols]
    sub rax, r14
    sar rax, 1
    inc rax
    cmp rax, 2
    jge .dcs_col_ok
    mov rax, 2
.dcs_col_ok:
    mov rdi, r12
    mov rsi, rax
    mov rdx, r13
    mov rcx, r14
    call draw_bytes_at

    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; called once before game loop; border already drawn by render_init
render_start_screen:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                  ; align stack

    call clear_buffer

    mov r15, [rel term_rows]
    sar r15, 1                  ; r15 = center row

    lea rdi, [r15 - 4]
    lea rsi, [rel ss_title]
    mov rdx, ss_title_len
    call draw_centered_str

    lea rdi, [r15 - 3]
    lea rsi, [rel ss_rule]
    mov rdx, ss_rule_len
    call draw_centered_str

    lea rdi, [r15 - 1]
    lea rsi, [rel ss_sub]
    mov rdx, ss_sub_len
    call draw_centered_str

    lea rdi, [r15 + 1]
    lea rsi, [rel ss_ctrl1]
    mov rdx, ss_ctrl1_len
    call draw_centered_str

    lea rdi, [r15 + 2]
    lea rsi, [rel ss_ctrl2]
    mov rdx, ss_ctrl2_len
    call draw_centered_str

    lea rdi, [r15 + 3]
    lea rsi, [rel ss_ctrl3]
    mov rdx, ss_ctrl3_len
    call draw_centered_str

    lea rdi, [r15 + 4]
    lea rsi, [rel ss_ctrl4]
    mov rdx, ss_ctrl4_len
    call draw_centered_str

    lea rdi, [r15 + 6]
    lea rsi, [rel ss_prompt]
    mov rdx, ss_prompt_len
    call draw_centered_str

    call flush_buffer

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
