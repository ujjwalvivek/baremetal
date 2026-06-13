
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

    ; 1. Draw Title "BAREMETAL" in yellow pixel font (width = 53 cols)
    lea rsi, [rel esc_yellow_fg]
    mov rcx, esc_yellow_fg_len
    call append_bytes

    lea rdi, [r15 - 6]          ; starting row

    mov rsi, [rel term_cols]
    sub rsi, 53
    sar rsi, 1
    inc rsi
    cmp rsi, 2
    jge .title_col_ok
    mov rsi, 2
.title_col_ok:

    lea rdx, [rel ss_pixel_title]
    mov rcx, ss_pixel_title_len
    call draw_pixel_str

    ; 2. Draw Subtitle in white
    lea rsi, [rel esc_white_fg]
    mov rcx, esc_white_fg_len
    call append_bytes

    lea rdi, [r15]
    lea rsi, [rel ss_sub]
    mov rdx, ss_sub_len
    call draw_centered_str

    ; Calculate starting column for controls box (width 31)
    mov rax, [rel term_cols]
    sub rax, 31
    sar rax, 1
    inc rax
    cmp rax, 2
    jge .box_col_ok
    mov rax, 2
.box_col_ok:
    mov r12, rax                ; r12 = start column
    dec r12                     ; push one space to the left

    ; 3. Draw Controls Box
    lea rdi, [r15 + 2]
    mov rsi, r12
    lea rdx, [rel ss_box_top]
    mov rcx, ss_box_top_len
    call draw_bytes_at

    lea rdi, [r15 + 3]
    mov rsi, r12
    lea rdx, [rel ss_box_ctrl1]
    mov rcx, ss_box_ctrl1_len
    call draw_bytes_at

    lea rdi, [r15 + 4]
    mov rsi, r12
    lea rdx, [rel ss_box_ctrl2]
    mov rcx, ss_box_ctrl2_len
    call draw_bytes_at

    lea rdi, [r15 + 5]
    mov rsi, r12
    lea rdx, [rel ss_box_ctrl3]
    mov rcx, ss_box_ctrl3_len
    call draw_bytes_at

    lea rdi, [r15 + 6]
    mov rsi, r12
    lea rdx, [rel ss_box_ctrl4]
    mov rcx, ss_box_ctrl4_len
    call draw_bytes_at

    lea rdi, [r15 + 7]
    mov rsi, r12
    lea rdx, [rel ss_box_div]
    mov rcx, ss_box_div_len
    call draw_bytes_at

    lea rdi, [r15 + 8]
    mov rsi, r12
    lea rdx, [rel ss_box_ctrl5]
    mov rcx, ss_box_ctrl5_len
    call draw_bytes_at

    lea rdi, [r15 + 9]
    mov rsi, r12
    lea rdx, [rel ss_box_bot]
    mov rcx, ss_box_bot_len
    call draw_bytes_at

    ; 4. Draw Prompt in Neon Green
    lea rsi, [rel esc_sprite_green]
    mov rcx, esc_sprite_green_len
    call append_bytes

    lea rdi, [r15 + 11]
    lea rsi, [rel ss_prompt]
    mov rdx, ss_prompt_len
    call draw_centered_str

    call emit_color_reset
    call flush_buffer

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
