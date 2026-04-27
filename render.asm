; =============================================================================
; render.asm: Frame buffer, draw primitives, flush
; =============================================================================

section .data
    ; Cursor home: ESC[H (reposition to top-left without clearing)
    esc_cursor_home:     db 27, '[H'
    esc_cursor_home_len equ $ - esc_cursor_home

    ; Border characters
    border_horiz: db 0xE2, 0x94, 0x80          ; ─ (BOX DRAWINGS LIGHT HORIZONTAL)
    border_vert:  db 0xE2, 0x94, 0x82          ; │ (BOX DRAWINGS LIGHT VERTICAL)
    border_tl:    db 0xE2, 0x94, 0x8C          ; ┌ (TOP LEFT)
    border_tr:    db 0xE2, 0x94, 0x90          ; ┐ (TOP RIGHT)
    border_bl:    db 0xE2, 0x94, 0x94          ; └ (BOTTOM LEFT)
    border_br:    db 0xE2, 0x94, 0x98          ; ┘ (BOTTOM RIGHT)

    ; Space for clearing interior
    space_char: db ' '
    ; Pre-filled space row for bulk interior clearing (512 cols max)
    spaces_row: times 512 db ' '

section .bss

; --- Frame buffer (generous: 128KB) -----------------------------------------
BUFFER_SIZE equ 131072
frame_buffer: resb BUFFER_SIZE
global buf_pos
buf_pos:      resq 1          ; current write position in frame_buffer

; --- Last rendered player position (delta tracking) -------------------------
last_drawn_x: resq 1
last_drawn_y: resq 1

section .text

    extern int_to_ascii
    extern term_rows
    extern term_cols
    extern player_x
    extern player_y
    extern player_char
    extern player_char_len

    global render_init
    global render_frame
    global clear_buffer
    global flush_buffer
    global draw_char_at
    global draw_bytes_at

; --- Syscall numbers ---------------------------------------------------------
SYS_WRITE equ 1

; =============================================================================
; clear_buffer: Reset buffer, write cursor-home prefix
; =============================================================================
clear_buffer:
    push rbp
    mov rbp, rsp

    ; Reset write position to start of buffer
    lea rax, [rel frame_buffer]
    mov [rel buf_pos], rax

    ; Write cursor-home escape sequence as prefix
    lea rsi, [rel esc_cursor_home]
    mov rcx, esc_cursor_home_len
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    mov [rel buf_pos], rdi

    pop rbp
    ret

; =============================================================================
; append_byte: Append a single byte to buffer
; Input: dil = byte to append
; =============================================================================
append_byte:
    mov rdi, [rel buf_pos]
    mov [rdi], dil
    inc rdi
    mov [rel buf_pos], rdi
    ret

; =============================================================================
; append_bytes: Append N bytes to buffer
; Input: rsi = source pointer, rcx = count
; =============================================================================
append_bytes:
    push rdi
    mov rdi, [rel buf_pos]
    cld
    rep movsb
    mov [rel buf_pos], rdi
    pop rdi
    ret

; =============================================================================
; append_cursor_move: Write ESC[row;colH to buffer
; Input: rdi = row (1-indexed), rsi = col (1-indexed)
; =============================================================================
append_cursor_move:
    push rbx
    push r12
    push r13
    mov r12, rdi               ; save row
    mov r13, rsi               ; save col

    ; Write ESC[
    mov rdi, [rel buf_pos]
    mov byte [rdi], 27         ; ESC
    mov byte [rdi+1], '['
    add rdi, 2
    mov [rel buf_pos], rdi

    ; Write row number
    mov rax, r12
    mov rdi, [rel buf_pos]
    call int_to_ascii          ; rdi advanced past digits, rax = bytes written
    mov [rel buf_pos], rdi

    ; Write semicolon
    mov rdi, [rel buf_pos]
    mov byte [rdi], ';'
    inc rdi
    mov [rel buf_pos], rdi

    ; Write col number
    mov rax, r13
    mov rdi, [rel buf_pos]
    call int_to_ascii
    mov [rel buf_pos], rdi

    ; Write 'H'
    mov rdi, [rel buf_pos]
    mov byte [rdi], 'H'
    inc rdi
    mov [rel buf_pos], rdi

    pop r13
    pop r12
    pop rbx
    ret

; =============================================================================
; draw_char_at: Draw a single ASCII char at (row, col)
; Input: rdi = row, rsi = col, dl = character
; =============================================================================
draw_char_at:
    push rbx
    push rdx                   ; save character
    call append_cursor_move    ; rdi=row, rsi=col already set
    pop rdx
    ; Append the character byte
    mov rdi, [rel buf_pos]
    mov [rdi], dl
    inc rdi
    mov [rel buf_pos], rdi
    pop rbx
    ret

; =============================================================================
; draw_bytes_at: Draw N bytes at (row, col)
; Input: rdi = row, rsi = col, rdx = source ptr, rcx = byte count
; =============================================================================
draw_bytes_at:
    push rbx
    push rdx                   ; save source ptr
    push rcx                   ; save byte count
    call append_cursor_move
    pop rcx
    pop rsi                    ; source ptr -> rsi for append_bytes
    call append_bytes
    pop rbx
    ret

; =============================================================================
; flush_buffer: Write entire buffer to stdout in one syscall
; =============================================================================
flush_buffer:
    push rbp
    mov rbp, rsp

    ; Calculate length: buf_pos - frame_buffer
    mov rdx, [rel buf_pos]
    lea rsi, [rel frame_buffer]
    sub rdx, rsi               ; rdx = byte count

    mov rax, SYS_WRITE
    mov rdi, 1                 ; stdout
    ; rsi already points to frame_buffer
    syscall

    pop rbp
    ret

; =============================================================================
; render_init: Full redraw: border + cleared interior + player. Call once.
; =============================================================================
render_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    call clear_buffer

    ; --- Get terminal dimensions ---
    mov r14, [rel term_cols]   ; total columns
    mov r15, [rel term_rows]   ; total rows

    ; --- Draw top border: row 1 ---
    ; Top-left corner
    mov rdi, 1
    mov rsi, 1
    lea rdx, [rel border_tl]
    mov rcx, 3
    call draw_bytes_at

    ; Top horizontal line (col 2 to col-1)
    mov r12, 2                 ; current col
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

    ; Top-right corner
    mov rdi, 1
    mov rsi, r14
    lea rdx, [rel border_tr]
    mov rcx, 3
    call draw_bytes_at

    ; --- Draw side borders and clear interior: rows 2 to rows-1 ---
    mov r13, 2                 ; current row
.side_borders:
    cmp r13, r15
    jge .side_borders_end

    ; Left border
    mov rdi, r13
    mov rsi, 1
    lea rdx, [rel border_vert]
    mov rcx, 3
    call draw_bytes_at

    ; Clear interior: single cursor move + bulk space write per row
    mov rdi, r13
    mov rsi, 2
    call append_cursor_move
    mov rcx, r14
    sub rcx, 2                 ; term_cols - 2 interior columns
    lea rsi, [rel spaces_row]
    call append_bytes

    ; Right border
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rel border_vert]
    mov rcx, 3
    call draw_bytes_at

    inc r13
    jmp .side_borders
.side_borders_end:

    ; --- Draw bottom border: row = term_rows ---
    ; Bottom-left corner
    mov rdi, r15
    mov rsi, 1
    lea rdx, [rel border_bl]
    mov rcx, 3
    call draw_bytes_at

    ; Bottom horizontal line
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

    ; Bottom-right corner
    mov rdi, r15
    mov rsi, r14
    lea rdx, [rel border_br]
    mov rcx, 3
    call draw_bytes_at

    ; --- Draw player at initial position ---
    mov rdi, [rel player_y]
    mov rsi, [rel player_x]
    lea rdx, [rel player_char]
    movzx rcx, byte [rel player_char_len]
    call draw_bytes_at

    ; --- Save last drawn position ---
    mov rax, [rel player_x]
    mov [rel last_drawn_x], rax
    mov rax, [rel player_y]
    mov [rel last_drawn_y], rax

    ; --- Flush to terminal ---
    call flush_buffer

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; render_frame: Delta render: erase previous cell, draw at new cell.
; Writes ~26 bytes per frame when moving, zero when still.
; =============================================================================
render_frame:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    mov r12, [rel player_x]      ; current col
    mov r13, [rel player_y]      ; current row
    mov r14, [rel last_drawn_x]  ; previous col
    mov r15, [rel last_drawn_y]  ; previous row

    ; If position unchanged, nothing to do
    cmp r12, r14
    jne .do_update
    cmp r13, r15
    je .done

.do_update:
    ; Reset buffer (no cursor-home: targeted writes only)
    lea rax, [rel frame_buffer]
    mov [rel buf_pos], rax

    ; Erase previous player cell with a space
    mov rdi, r15
    mov rsi, r14
    mov dl, ' '
    call draw_char_at

    ; Draw player at new position
    mov rdi, r13
    mov rsi, r12
    lea rdx, [rel player_char]
    movzx rcx, byte [rel player_char_len]
    call draw_bytes_at

    ; Update stored position
    mov [rel last_drawn_x], r12
    mov [rel last_drawn_y], r13

    ; Flush (~26 bytes, single write syscall)
    call flush_buffer

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
