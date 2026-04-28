; render.asm: frame buffer, draw primitives, flush

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
    ss_ctrl3:  db "Q        quit"
    ss_ctrl3_len equ $ - ss_ctrl3
    ss_prompt: db "[  press any key  ]"
    ss_prompt_len equ $ - ss_prompt

section .bss

BUFFER_SIZE equ 131072          ; 128KB
frame_buffer: resb BUFFER_SIZE
global buf_pos
buf_pos:      resq 1          ; write head

MAX_SCREEN_COLS equ 512
MAX_SCREEN_ROWS equ 200
col_char: resb MAX_SCREEN_COLS  ; UTF-8 third byte of wall shade block char
col_top:  resb MAX_SCREEN_COLS  ; first wall row (0-indexed interior)
col_bot:  resb MAX_SCREEN_COLS  ; last  wall row (0-indexed interior)

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

FOV_HALF     equ 30         ; half of 60° FOV
FOV_TOTAL    equ 60         ; full FOV
SHADE_NEAR   equ 2048       ; perp_dist < 2 cells  → █  (cells × 1024)
SHADE_MED    equ 4096       ; perp_dist < 4 cells  → ▓
SHADE_FAR    equ 8192       ; perp_dist < 8 cells  → ▒  (else → ░)
BLOCK_FULL   equ 0x88       ; █
BLOCK_DARK   equ 0x93       ; ▓
BLOCK_MED    equ 0x92       ; ▒
BLOCK_LIGHT  equ 0x91       ; ░

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
    sub rsp, 8              ; 16-byte stack alignment

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
    call cast_ray           ; rax = perp_dist (cells × 1024)
    mov rbx, rax            ; rbx = dist

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

    ; Shade: pick block char variant byte by distance
    cmp rbx, SHADE_NEAR
    jl .shade_near
    cmp rbx, SHADE_MED
    jl .shade_dark
    cmp rbx, SHADE_FAR
    jl .shade_med
    mov al, BLOCK_LIGHT
    jmp .shade_done
.shade_near:
    mov al, BLOCK_FULL
    jmp .shade_done
.shade_dark:
    mov al, BLOCK_DARK
    jmp .shade_done
.shade_med:
    mov al, BLOCK_MED
.shade_done:

    lea rcx, [rel col_char]
    mov [rcx + r12], al
    lea rcx, [rel col_top]
    mov [rcx + r12], r14b
    lea rcx, [rel col_bot]
    mov [rcx + r12], r15b

    inc r12
    jmp .cast_loop

.cast_done:
    call clear_buffer

    xor r12, r12            ; r = 0

.row_loop:
    cmp r12, [rel render_scr_rows]
    jge .frame_done

    lea rdi, [r12 + 2]
    mov rsi, 2
    call append_cursor_move

    xor r13, r13            ; c = 0

.col_loop:
    cmp r13, [rel render_scr_cols]
    jge .row_done

    ; minimap bottom border row (r12 == MMAP_H): left=raycaster, sep=└, right=─
    cmp r12, MMAP_H
    jne .check_sep_col
    cmp r13, [rel mmap_border_col]
    jl .raycaster_col
    je .mm_corner_bl
    mov rdi, [rel buf_pos]          ; ─ horizontal bar
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x94
    mov byte [rdi+2], 0x80
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.mm_corner_bl:
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
    mov rcx, r13
    sub rcx, [rel mmap_content_col] ; rcx = minimap_x
    mov rax, [rel player_x]
    sar rax, 8
    cmp rcx, rax
    jne .mm_check_wall
    mov rax, [rel player_y]
    sar rax, 8
    cmp r12, rax
    jne .mm_check_wall
    mov rdi, [rel buf_pos]
    mov byte [rdi], '@'
    inc rdi
    mov [rel buf_pos], rdi
    jmp .col_next

.mm_vert:
    mov rdi, [rel buf_pos]          ; │ vertical separator
    mov byte [rdi],   0xE2
    mov byte [rdi+1], 0x94
    mov byte [rdi+2], 0x82
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .col_next

.mm_check_wall:
    mov rax, r12
    imul rax, MMAP_W
    add rax, rcx
    lea rbx, [rel world_map]
    movzx ebx, byte [rbx + rax]
    mov rdi, [rel buf_pos]
    test ebx, ebx
    jz .mm_floor
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
    movzx r14, byte [rax + r13]
    lea rax, [rel col_bot]
    movzx r15, byte [rax + r13]

    cmp r12, r14
    jl .emit_ceiling
    cmp r12, r15
    jg .emit_floor

    ; Wall: 3-byte UTF-8 (0xE2 0x96 + variant)
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
    mov rdi, [rel buf_pos]
    mov byte [rdi], ' '
    inc rdi
    mov [rel buf_pos], rdi
    jmp .col_next

.emit_floor:
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
    call flush_buffer

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

MMAP_W equ 16
MMAP_H equ 16

; '#'=wall '@'=player '.'=floor, 16×16, top-right corner at row 2
render_minimap:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r14, [rel term_cols]
    sub r14, MMAP_W

    mov rax, [rel player_x]
    sar rax, 8
    mov r12, rax              ; r12 = player map_x
    mov rax, [rel player_y]
    sar rax, 8
    mov r13, rax              ; r13 = player map_y

    xor rbx, rbx              ; my = 0
.mm_row:
    cmp rbx, MMAP_H
    jge .mm_done

    lea rdi, [rbx + 2]
    mov rsi, r14
    call append_cursor_move

    xor r15, r15              ; mx = 0
.mm_col:
    cmp r15, MMAP_W
    jge .mm_col_done

    cmp rbx, r13
    jne .mm_not_player
    cmp r15, r12
    jne .mm_not_player
    mov rdi, [rel buf_pos]
    mov byte [rdi], '@'
    inc rdi
    mov [rel buf_pos], rdi
    jmp .mm_next

.mm_not_player:
    mov rax, rbx              ; world_map[my * MMAP_W + mx]
    imul rax, MMAP_W
    add rax, r15
    lea rdi, [rel world_map]
    movzx rdi, byte [rdi + rax]
    mov rdi, [rel buf_pos]
    test al, al
    jz .mm_floor
    mov byte [rdi], '#'
    jmp .mm_emit
.mm_floor:
    mov byte [rdi], '.'
.mm_emit:
    inc rdi
    mov [rel buf_pos], rdi

.mm_next:
    inc r15
    jmp .mm_col

.mm_col_done:
    inc rbx
    jmp .mm_row

.mm_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

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

    lea rdi, [r15 + 5]
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
