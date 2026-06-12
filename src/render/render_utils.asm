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
    extern sin_table
    extern cos_table

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
    global draw_pixel_str

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

; rdi=row, rsi=col, dl=shade byte (draws block)
draw_shaded_block_at:
    push rbx
    push rdx
    call append_cursor_move
    pop rdx
    mov rdi, [rel buf_pos]
    mov byte [rdi], 0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], dl
    add rdi, 3
    mov [rel buf_pos], rdi
    pop rbx
    ret

; rdi=row, rsi=col (draws solid block █)
draw_solid_block_at:
    push rbx
    call append_cursor_move
    mov rdi, [rel buf_pos]
    mov byte [rdi], 0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], 0x88
    add rdi, 3
    mov [rel buf_pos], rdi
    pop rbx
    ret

; In: rdi = row, rsi = col, rdx = sprite pointer, rcx = width, r8 = height
; Clobbers: rax, rbx, r10, r11, r12, r13, r14, r15
draw_pixel_sprite_at:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                ; screen_row
    mov r13, rsi                ; screen_col
    mov r14, rdx                ; sprite ptr
    mov r15, rcx                ; sprite width
    ; r8 is sprite height
    
    xor r10, r10                ; r10 = row_idx
.row_loop:
    cmp r10, r8
    jge .done
    
    xor rbx, rbx                ; rbx = col_idx
.col_loop:
    cmp rbx, r15
    jge .col_done
    
    ; pixel_val = sprite[row_idx * width + col_idx]
    mov rax, r10
    imul rax, r15
    add rax, rbx
    movzx eax, byte [r14 + rax]
    
    test al, al
    jz .pixel_skip
    
    ; Map pixel_val to block char: 1=0x88, 2=0x93, 3=0x92, 4=0x91
    mov dl, 0x88                ; default █
    cmp al, 1
    je .char_ok
    mov dl, 0x93                ; ▓
    cmp al, 2
    je .char_ok
    mov dl, 0x92                ; ▒
    cmp al, 3
    je .char_ok
    mov dl, 0x91                ; ░
.char_ok:
    ; Draw it!
    push r10
    push r8
    mov rdi, r12
    add rdi, r10                ; target row
    mov rsi, r13
    add rsi, rbx                ; target col
    call draw_shaded_block_at
    pop r8
    pop r10
    
.pixel_skip:
    inc rbx
    jmp .col_loop
    
.col_done:
    inc r10
    jmp .row_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
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

; rdi=row, rsi=col, rdx=src, rcx=len
draw_transparent_bytes_at:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi            ; row
    mov r13, rsi            ; col
    mov r14, rcx            ; len
    mov rbx, rdx            ; src
.loop:
    test r14, r14
    jz .done
    mov al, [rbx]
    cmp al, ' '
    je .skip
    ; Not a space, draw it!
    mov rdi, r12
    mov rsi, r13
    push rax
    call append_cursor_move
    pop rax
    mov rdi, [rel buf_pos]
    mov [rdi], al
    inc rdi
    mov [rel buf_pos], rdi
.skip:
    inc rbx
    inc r13
    dec r14
    jmp .loop
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
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

global draw_pixel_str
draw_pixel_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rdi                    ; save start_row
    push rsi                    ; save start_col
    push rdx                    ; save string_ptr
    push rcx                    ; save string_len

    xor r12, r12                ; r12 = row_idx (0..4)
.row_loop:
    cmp r12, 5
    jge .done

    ; Calculate current screen row
    mov rdi, [rsp + 24]         ; start_row
    add rdi, r12                ; rdi = start_row + row_idx
    mov rsi, [rsp + 16]         ; rsi = start_col
    call append_cursor_move

    ; Loop over each character in the string
    xor r13, r13                ; r13 = char_idx (0..string_len-1)
.char_loop:
    cmp r13, [rsp]              ; string_len
    jge .char_done

    mov rsi, [rsp + 8]          ; string_ptr
    movzx rax, byte [rsi + r13] ; rax = char
    
    ; Convert lowercase to uppercase
    cmp al, 'a'
    jl .not_lower
    cmp al, 'z'
    jg .not_lower
    sub al, 32
.not_lower:

    ; Get pattern byte: font_table + char * 5 + row_idx
    imul rax, 5
    add rax, r12
    extern font_table
    lea rdx, [rel font_table]
    movzx ebx, byte [rdx + rax] ; ebx = pattern byte (5 bits used: bits 4..0)

    ; Loop over bits 4 down to 0
    mov r14, 4                  ; r14 = bit_idx
.bit_loop:
    test r14, r14
    js .bit_done

    ; Test bit r14 in ebx
    mov rcx, r14
    mov edx, 1
    shl edx, cl
    test ebx, edx
    jz .emit_space

    ; Emit '█' (0xE2, 0x96, 0x88)
    mov rdi, [rel buf_pos]
    mov byte [rdi], 0xE2
    mov byte [rdi+1], 0x96
    mov byte [rdi+2], 0x88
    add rdi, 3
    mov [rel buf_pos], rdi
    jmp .bit_next

.emit_space:
    ; Emit ' '
    mov rdi, [rel buf_pos]
    mov byte [rdi], ' '
    inc rdi
    mov [rel buf_pos], rdi

.bit_next:
    dec r14
    jmp .bit_loop

.bit_done:
    ; Emit character spacing ' '
    mov rdi, [rel buf_pos]
    mov byte [rdi], ' '
    inc rdi
    mov [rel buf_pos], rdi

    inc r13
    jmp .char_loop

.char_done:
    inc r12
    jmp .row_loop

.done:
    add rsp, 32                 ; clean local stack args
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


