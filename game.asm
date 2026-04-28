; =============================================================================
; game.asm: World map, player state, DDA raycaster
; =============================================================================

; --- Map dimensions ----------------------------------------------------------
MAP_WIDTH  equ 16
MAP_HEIGHT equ 16

; --- Fixed-point movement speed (Q8: real speed = MOVE_SPEED / 256 cells/frame)
; 16 = 0.0625 cells/frame = 3.75 cells/sec @ 60fps
MOVE_SPEED equ 16

; --- Rotation speed (degrees per key press per frame) ------------------------
ROT_SPEED  equ 5

; --- DDA infinity sentinel (half INT64_MAX — prevents overflow on add) -------
DDA_INF    equ 0x3FFFFFFFFFFFFFFF

section .data

global player_char, player_char_len
player_char:     db 0xE2, 0x96, 0x88  ; █  UTF-8 3 bytes
player_char_len: db 3

; World map: 16×16 bytes.  1 = wall, 0 = open space.
; Row-major: world_map[row * MAP_WIDTH + col]
;
; Layout: 4 rooms (NW/NE/SW/SE) connected by a cross-shaped corridor.
; Player starts at center (8,7) facing east.  The cross runs rows 7-8
; (E-W) and cols 7-8 (N-S), with doorways cut in every dividing wall.
;
;  NW room     N corridor   NE room
;  [1,1..5]    [col 7-8]    [9,1..5]
;  W corridor  CENTER       E corridor
;  [row 7-8]  [7-8,7-8]    [row 7-8]
;  SW room     S corridor   SE room
;  [1,10..14] [col 7-8]    [9,10..14]
global world_map
world_map:
    db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; row  0  outer wall
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row  1  NW room / NE room
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row  2
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row  3
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row  4
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row  5
    db 1,1,1,0,1,1,1,0,0,1,1,1,0,1,1,1   ; row  6  N dividing wall (doors at col 3, 12)
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1   ; row  7  E-W corridor
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1   ; row  8  E-W corridor
    db 1,1,1,0,1,1,1,0,0,1,1,1,0,1,1,1   ; row  9  S dividing wall (doors at col 3, 12)
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row 10  SW room / SE room
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row 11
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row 12
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row 13
    db 1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1   ; row 14
    db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; row 15  outer wall

section .bss

global player_x, player_y, player_angle
player_x:     resq 1           ; Q8 fixed-point X  (real pos = player_x >> 8)
player_y:     resq 1           ; Q8 fixed-point Y  (real pos = player_y >> 8)
player_angle: resq 1           ; 0..359 degrees (direct LUT index)

section .text

extern sin_table, cos_table
extern key_up, key_down, key_left, key_right

global init_game, update_game, cast_ray

; =============================================================================
; init_game: Place player at map position (4.0, 4.0), facing east (angle = 0)
; =============================================================================
init_game:
    push rbp
    mov rbp, rsp

    ; Start at center of E-W corridor (col 7.5, row 7.5), facing east.
    mov qword [rel player_x], (7 << 8) | 128   ; 7.5 in Q8
    mov qword [rel player_y], (7 << 8) | 128   ; 7.5 in Q8
    mov qword [rel player_angle], 0             ; facing east

    pop rbp
    ret

; =============================================================================
; update_game: Rotate (A/D) and move forward/back (W/S) with wall collision
;
; Rotation: key_left  (A) → angle -= ROT_SPEED mod 360
;           key_right (D) → angle += ROT_SPEED mod 360
;
; Movement: key_up    (W) → forward along player_angle
;           key_down  (S) → backward along player_angle
;
; Collision: x and y axes tested independently — enables wall sliding.
; =============================================================================
update_game:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; --- Rotation ------------------------------------------------------------
    cmp byte [rel key_left], 1
    jne .no_left
    mov rax, [rel player_angle]
    sub rax, ROT_SPEED
    jns .left_no_wrap
    add rax, 360
.left_no_wrap:
    mov [rel player_angle], rax
.no_left:

    cmp byte [rel key_right], 1
    jne .no_right
    mov rax, [rel player_angle]
    add rax, ROT_SPEED
    cmp rax, 360
    jl .right_no_wrap
    sub rax, 360
.right_no_wrap:
    mov [rel player_angle], rax
.no_right:

    ; --- Movement ------------------------------------------------------------
    movzx r12, byte [rel key_up]     ; r12 = 1 if W (forward)
    movzx r13, byte [rel key_down]   ; r13 = 1 if S (backward)
    test r12, r12
    jnz .do_move
    test r13, r13
    jz .no_move

.do_move:
    ; Load ray direction for current angle
    mov rax, [rel player_angle]
    lea rbx, [rel cos_table]
    mov rbx, [rbx + rax*8]           ; rbx = cos[angle] (×1024)
    lea rcx, [rel sin_table]
    mov rcx, [rcx + rax*8]           ; rcx = sin[angle] (×1024)

    ; If S (backward) and not W: negate direction
    test r13, r13
    jz .dir_forward
    test r12, r12
    jnz .no_move                     ; both pressed: cancel
    neg rbx
    neg rcx
.dir_forward:

    ; dx = cos[angle] * MOVE_SPEED >> 10  (result in Q8)
    mov rax, rbx
    imul rax, MOVE_SPEED
    sar rax, 10
    mov r12, rax                     ; r12 = dx (Q8)

    ; dy = sin[angle] * MOVE_SPEED >> 10  (result in Q8)
    mov rax, rcx
    imul rax, MOVE_SPEED
    sar rax, 10
    mov r13, rax                     ; r13 = dy (Q8)

    ; --- X-axis collision check ---
    mov rax, [rel player_x]
    add rax, r12                     ; proposed new_x (Q8)
    mov rbx, rax
    sar rbx, 8                       ; new map_x (integer)
    mov rcx, [rel player_y]
    sar rcx, 8                       ; current map_y (integer)
    imul rcx, MAP_WIDTH
    add rcx, rbx
    lea rbx, [rel world_map]
    movzx rbx, byte [rbx + rcx]
    test rbx, rbx
    jnz .skip_x                      ; wall: skip x movement
    mov [rel player_x], rax          ; apply x movement
.skip_x:

    ; --- Y-axis collision check ---
    mov rax, [rel player_y]
    add rax, r13                     ; proposed new_y (Q8)
    mov rbx, rax
    sar rbx, 8                       ; new map_y (integer)
    mov rcx, [rel player_x]
    sar rcx, 8                       ; current map_x (integer, possibly updated)
    imul rbx, MAP_WIDTH
    add rbx, rcx
    lea rcx, [rel world_map]
    movzx rcx, byte [rcx + rbx]
    test rcx, rcx
    jnz .skip_y                      ; wall: skip y movement
    mov [rel player_y], rax          ; apply y movement
.skip_y:

.no_move:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; cast_ray: DDA raycaster — cast a single ray, return perpendicular wall dist
;
; Input:  rdi = ray angle (0..359 degrees)
; Output: rax = perpendicular wall distance (map units × 1024), minimum 1
;
; The perpendicular distance formula (side_dist - delta_dist) already
; corrects for the fisheye effect — no separate cosine multiply needed.
;
; Register map (active ranges):
;   r8        ray_dir_x (cos[angle] ×1024)  → map-lookup scratch in loop
;   r9        ray_dir_y (sin[angle] ×1024)  → freed after setup
;   r10       map_x  — current DDA grid cell x
;   r11       map_y  — current DDA grid cell y
;   r12       delta_dist_x  (×1024, always > 0)
;   r13       delta_dist_y  (×1024, always > 0)
;   r14       side_dist_x   (×1024 accumulator)
;   r15       side_dist_y   (×1024 accumulator)
;   rbx       step_x  (+1 or -1)
;   rcx       step_y  (+1 or -1)
;   rdx       side flag: 0 = last step was x, 1 = last step was y
; =============================================================================
cast_ray:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; --- Ray direction from LUT -----------------------------------------------
    lea rax, [rel cos_table]
    mov r8, [rax + rdi*8]            ; r8 = cos[angle] (×1024)
    lea rax, [rel sin_table]
    mov r9, [rax + rdi*8]            ; r9 = sin[angle] (×1024)

    ; --- Starting map cell from Q8 player position ----------------------------
    mov rax, [rel player_x]
    sar rax, 8
    mov r10, rax                     ; map_x

    mov rax, [rel player_y]
    sar rax, 8
    mov r11, rax                     ; map_y

    ; --- delta_dist_x = |1024 * 1024 / ray_dir_x| ----------------------------
    ; ray_dir_x = 0 → ray is vertical: use DDA_INF so x is never stepped
    test r8, r8
    jz .ddx_zero
    mov rax, 1048576                 ; 1024 × 1024
    cqo
    idiv r8                          ; rax = 1024²/ray_dir_x  (signed)
    test rax, rax
    jns .ddx_pos
    neg rax
.ddx_pos:
    mov r12, rax
    jmp .ddx_done
.ddx_zero:
    mov r12, DDA_INF
.ddx_done:

    ; --- delta_dist_y = |1024 * 1024 / ray_dir_y| ----------------------------
    test r9, r9
    jz .ddy_zero
    mov rax, 1048576
    cqo
    idiv r9
    test rax, rax
    jns .ddy_pos
    neg rax
.ddy_pos:
    mov r13, rax
    jmp .ddy_done
.ddy_zero:
    mov r13, DDA_INF
.ddy_done:

    ; --- step_x and initial side_dist_x ---------------------------------------
    test r8, r8
    jz .setup_x_zero
    jns .step_x_pos

    ; ray moving left
    mov rbx, -1
    mov rax, [rel player_x]
    and rax, 0xFF                    ; fractional part (0..255)
    imul rax, r12                    ; frac × delta_dist_x
    sar rax, 8                       ; / 256 → Q8-fraction of a cell
    mov r14, rax
    jmp .setup_x_done

.step_x_pos:
    ; ray moving right
    mov rbx, 1
    mov rax, [rel player_x]
    and rax, 0xFF
    neg rax
    add rax, 256                     ; (256 - frac) = distance to next x boundary
    imul rax, r12
    sar rax, 8
    mov r14, rax
    jmp .setup_x_done

.setup_x_zero:
    mov rbx, 1                       ; step_x irrelevant when delta = DDA_INF
    mov r14, DDA_INF
.setup_x_done:

    ; --- step_y and initial side_dist_y ---------------------------------------
    test r9, r9
    jz .setup_y_zero
    jns .step_y_pos

    ; ray moving up
    mov rcx, -1
    mov rax, [rel player_y]
    and rax, 0xFF
    imul rax, r13
    sar rax, 8
    mov r15, rax
    jmp .setup_y_done

.step_y_pos:
    ; ray moving down
    mov rcx, 1
    mov rax, [rel player_y]
    and rax, 0xFF
    neg rax
    add rax, 256
    imul rax, r13
    sar rax, 8
    mov r15, rax
    jmp .setup_y_done

.setup_y_zero:
    mov rcx, 1
    mov r15, DDA_INF
.setup_y_done:

    xor rdx, rdx                     ; side = 0 (x) initially

    ; --- DDA loop -------------------------------------------------------------
    mov rsi, 32                      ; max iterations = MAP_WIDTH + MAP_HEIGHT
.dda_loop:
    dec rsi
    jz .hit_far                      ; safety: map has boundary walls so unreachable

    cmp r14, r15                     ; side_dist_x vs side_dist_y
    jle .dda_step_x

    ; Step in Y
    add r15, r13                     ; side_dist_y += delta_dist_y
    add r11, rcx                     ; map_y += step_y
    mov rdx, 1                       ; side = y
    jmp .dda_check

.dda_step_x:
    ; Step in X (or equal: prefer x for determinism)
    add r14, r12                     ; side_dist_x += delta_dist_x
    add r10, rbx                     ; map_x += step_x
    xor rdx, rdx                     ; side = x

.dda_check:
    ; Bounds check (safety net: boundary walls should prevent escape)
    cmp r10, 0
    jl .hit_far
    cmp r10, MAP_WIDTH
    jge .hit_far
    cmp r11, 0
    jl .hit_far
    cmp r11, MAP_HEIGHT
    jge .hit_far

    ; world_map[map_y * MAP_WIDTH + map_x]
    mov rax, r11
    imul rax, MAP_WIDTH
    add rax, r10
    lea r8, [rel world_map]
    movzx r8, byte [r8 + rax]       ; r8 = cell value (0 = open, 1 = wall)
    test r8, r8
    jz .dda_loop                     ; open: keep stepping

    ; Wall hit — fall through to distance calculation

    ; --- Perpendicular distance -----------------------------------------------
    ; perp_dist = side_dist_at_wall - delta_dist
    ; (this is side_dist BEFORE the step that hit the wall)
    test rdx, rdx
    jnz .perp_y
    mov rax, r14
    sub rax, r12                     ; side_dist_x - delta_dist_x
    jmp .perp_clamp
.perp_y:
    mov rax, r15
    sub rax, r13                     ; side_dist_y - delta_dist_y
.perp_clamp:
    cmp rax, 1
    jge .ray_done
    mov rax, 1                       ; clamp: minimum distance 1 (avoids /0)
    jmp .ray_done

.hit_far:
    mov rax, MAP_HEIGHT * 1024       ; ray escaped: return maximum distance

.ray_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
