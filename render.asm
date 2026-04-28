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

; --- Per-column raycaster results (up to MAX_SCREEN_COLS columns) -----------
MAX_SCREEN_COLS equ 512
MAX_SCREEN_ROWS equ 200
col_char: resb MAX_SCREEN_COLS  ; UTF-8 third byte of wall shade block char
col_top:  resb MAX_SCREEN_COLS  ; first wall row (0-indexed interior)
col_bot:  resb MAX_SCREEN_COLS  ; last  wall row (0-indexed interior)

; --- Dynamic interior dimensions (set once per render_frame) ----------------
render_scr_cols: resq 1   ; = term_cols - 2
render_scr_rows: resq 1   ; = term_rows - 2

section .text

    extern int_to_ascii
    extern term_rows
    extern term_cols
    extern player_x
    extern player_y
    extern player_angle
    extern cast_ray
    extern world_map

; --- Rendering constants ----------------------------------------------------
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
; render_frame: Full 3D raycasted view — adapts to actual terminal dimensions
;
; Pass 1: cast one ray per interior column → col_char/top/bot arrays
; Pass 2: emit full frame row-by-row (ceiling=' ', floor='.', wall=block char)
;
; screen_cols = term_cols - 2  (capped at MAX_SCREEN_COLS)
; screen_rows = term_rows - 2  (capped at MAX_SCREEN_ROWS)
; FOV: 60° (±30° around player_angle)
; =============================================================================
render_frame:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8              ; 16-byte stack alignment

    ; --- Compute interior dimensions (clamped to array bounds) ---------------
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

    ; =========================================================================
    ; Pass 1: cast one ray per column
    ; =========================================================================
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
    ; =========================================================================
    ; Pass 2: emit full frame
    ; =========================================================================
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
    call render_minimap
    call flush_buffer

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; render_minimap: Draw 16×16 map in top-right corner of interior area.
;
; Each cell → 1 char: '#' wall, '@' player, '.' floor.
; Top-left of minimap = terminal row 2, col (term_cols - MAP_WIDTH - 1).
; Overwrites into the already-built frame buffer (called before flush).
; =============================================================================
MMAP_W equ 16
MMAP_H equ 16

render_minimap:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; minimap left col (1-indexed terminal col) = term_cols - MMAP_W
    mov r14, [rel term_cols]
    sub r14, MMAP_W           ; r14 = minimap left col (1-indexed)

    ; player map cell
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

    ; cursor: terminal row = rbx + 2, col = r14
    lea rdi, [rbx + 2]
    mov rsi, r14
    call append_cursor_move

    xor r15, r15              ; mx = 0
.mm_col:
    cmp r15, MMAP_W
    jge .mm_col_done

    ; Check if this is the player cell
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
    ; world_map[my * 16 + mx]
    mov rax, rbx
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
