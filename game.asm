; =============================================================================
; game.asm: Player state, initialization, update logic
; =============================================================================

section .data
; Player character: █ (UTF-8: 0xE2 0x96 0x88, 3 bytes)
global player_char, player_char_len
player_char:     db 0xE2, 0x96, 0x88
player_char_len: db 3

section .bss
global player_x, player_y
player_x: resq 1              ; column position (1-indexed)
player_y: resq 1              ; row position (1-indexed)

section .text
extern term_rows, term_cols
extern key_up, key_down, key_left, key_right

global init_game, update_game

; =============================================================================
; init_game: Place player at center of terminal
; =============================================================================
init_game:
    push rbp
    mov rbp, rsp

    ; Center: col = term_cols/2, row = term_rows/2
    mov rax, [rel term_cols]
    shr rax, 1                 ; divide by 2
    mov [rel player_x], rax

    mov rax, [rel term_rows]
    shr rax, 1
    mov [rel player_y], rax

    pop rbp
    ret

; =============================================================================
; update_game: Apply input to player position, clamp to playable area
; Playable area: col 2 to (term_cols-1), row 2 to (term_rows-1)
; (row 1 = top border, row term_rows = bottom border)
; (col 1 = left border, col term_cols = right border)
; =============================================================================
update_game:
    push rbp
    mov rbp, rsp

    ; Load current position
    mov rax, [rel player_x]    ; col
    mov rcx, [rel player_y]    ; row

    ; Apply movement
    cmp byte [rel key_up], 1
    jne .no_up
    dec rcx
.no_up:
    cmp byte [rel key_down], 1
    jne .no_down
    inc rcx
.no_down:
    cmp byte [rel key_left], 1
    jne .no_left
    dec rax
.no_left:
    cmp byte [rel key_right], 1
    jne .no_right
    inc rax
.no_right:

    ; Clamp column: 2 <= x <= term_cols - 1
    cmp rax, 2
    jge .col_min_ok
    mov rax, 2
.col_min_ok:
    mov rdx, [rel term_cols]
    dec rdx                    ; max col = term_cols - 1
    cmp rax, rdx
    jle .col_max_ok
    mov rax, rdx
.col_max_ok:

    ; Clamp row: 2 <= y <= term_rows - 1
    cmp rcx, 2
    jge .row_min_ok
    mov rcx, 2
.row_min_ok:
    mov rdx, [rel term_rows]
    dec rdx                    ; max row = term_rows - 1
    cmp rcx, rdx
    jle .row_max_ok
    mov rcx, rdx
.row_max_ok:

    ; Store updated position
    mov [rel player_x], rax
    mov [rel player_y], rcx

    pop rbp
    ret
