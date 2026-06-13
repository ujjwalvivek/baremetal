; game.asm: world map, player state, DDA raycaster, door mechanics

MAP_WIDTH  equ 32
MAP_HEIGHT equ 32
NUM_SPRITES equ 8
NUM_ENEMIES equ 2

; Q8: real speed = MOVE_SPEED / 256 cells/frame  (16 = 3.75 cells/sec @ 60fps)
MOVE_SPEED equ 16

ROT_SPEED  equ 5   ; degrees per frame

; half INT64_MAX: prevents overflow when accumulating side_dist
DDA_INF    equ 0x3FFFFFFFFFFFFFFF

; Wall types: 0=open, 1=stone, 2=brick, 3=metal, 4=wood, 5=door
WALL_DOOR  equ 5

section .data

global player_char, player_char_len
player_char:     db 0xE2, 0x96, 0x88  ; █  UTF-8 3 bytes
player_char_len: db 3

global map_width, map_height
map_width:  dq MAP_WIDTH
map_height: dq MAP_HEIGHT

; World map: 32×32 bytes.  0=open, 1-4=wall types, 5=door
; Row-major: world_map[row * MAP_WIDTH + col]
;
; Layout: 4 quadrants connected by a central cross-corridor (rows/cols 15-16).
;   NW quadrant (rows 1-14, cols 1-14): brick (2) rooms
;   NE quadrant (rows 1-14, cols 17-30): metal (3) rooms
;   SW quadrant (rows 17-30, cols 1-14): wood (4) rooms
;   SE quadrant (rows 17-30, cols 17-30): stone (1) rooms
; row 7/24 and col 7/24, with doors (5) at crossing points.
; Corridor edge walls (rows 14,17 and cols 14,17) have doors for entry.
;
global world_map
world_map:
    ;       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1  ; row  0
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row  1
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row  2
    db 1,0,0,2,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,3,0,0,3,0,0,0,0,0,0,1  ; row  3  pillars
    db 1,0,0,0,0,0,0,5,0,0,0,0,0,0,5,0,0,5,0,0,0,0,0,0,5,0,0,0,0,0,0,1  ; row  4  doors
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row  5
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row  6
    db 1,2,2,2,5,2,2,2,2,2,5,2,2,2,1,0,0,1,3,3,3,5,3,3,3,3,3,5,3,3,3,1  ; row  7  h-divider
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row  8
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row  9
    db 1,0,0,0,0,0,0,5,0,0,0,0,0,0,5,0,0,5,0,0,0,0,0,0,5,0,0,0,0,0,0,1  ; row 10  doors
    db 1,0,0,0,0,0,0,2,0,0,2,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,3,0,0,0,1  ; row 11  pillars
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row 12
    db 1,0,0,0,0,0,0,2,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1  ; row 13
    db 1,1,1,1,5,1,1,1,1,1,5,1,1,1,1,0,0,1,1,1,1,5,1,1,1,1,1,5,1,1,1,1  ; row 14  corridor edge
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1  ; row 15  E-W corridor
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1  ; row 16  E-W corridor
    db 1,1,1,1,5,1,1,1,1,1,5,1,1,1,1,0,0,1,1,1,1,5,1,1,1,1,1,5,1,1,1,1  ; row 17  corridor edge
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 18
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 19
    db 1,0,0,4,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,1,0,0,1  ; row 20  pillars
    db 1,0,0,0,0,0,0,5,0,0,0,0,0,0,5,0,0,5,0,0,0,0,0,0,5,0,0,0,0,0,0,1  ; row 21  doors
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 22
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 23
    db 1,4,4,4,5,4,4,4,4,4,5,4,4,4,1,0,0,1,1,1,1,5,1,1,1,1,1,5,1,1,1,1  ; row 24  h-divider
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 25
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 26
    db 1,0,0,0,0,0,0,5,0,0,0,0,0,0,5,0,0,5,0,0,0,0,0,0,5,0,0,0,0,0,0,1  ; row 27  doors
    db 1,0,0,0,0,0,0,4,0,0,4,0,0,0,1,0,0,1,0,0,0,1,0,0,1,0,0,0,0,0,0,1  ; row 28  pillars
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 29
    db 1,0,0,0,0,0,0,4,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1  ; row 30
    db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1  ; row 31

section .bss

global player_x, player_y, player_angle, player_health, game_over_flag, victory_flag
player_x:     resq 1           ; Q8 fixed-point X  (real pos = player_x >> 8)
player_y:     resq 1           ; Q8 fixed-point Y  (real pos = player_y >> 8)
player_angle: resq 1           ; 0..359 degrees (direct LUT index)
player_health: resq 1          ; 0..100
game_over_flag: resq 1         ; 0=playing, 1=dead
victory_flag:   resq 1         ; 0=playing, 1=won

global door_state
door_state:   resb MAP_WIDTH * MAP_HEIGHT   ; 0=closed, 1=open (parallel to world_map)

section .text

extern sin_table, cos_table
extern key_up, key_down, key_left, key_right, key_use

global init_game, update_game, cast_ray, toggle_door

init_game:
    push rbp
    mov rbp, rsp

    ; corridor intersection center (15.5, 15.5) in Q8, facing east
    mov qword [rel player_x], (15 << 8) | 128
    mov qword [rel player_y], (15 << 8) | 128
    mov qword [rel player_angle], 0
    mov qword [rel player_health], 100
    mov qword [rel game_over_flag], 0
    mov qword [rel victory_flag], 0

    call load_level

    pop rbp
    ret

; Load level from level.bin if it exists
load_level:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; sys_open("level.bin", O_RDONLY)
    mov rax, 2                  ; sys_open
    lea rdi, [rel level_filename]
    xor rsi, rsi                ; O_RDONLY = 0
    xor rdx, rdx
    syscall
    test rax, rax
    js .done                    ; if failed (e.g. doesn't exist), just return and keep defaults
    
    mov rbx, rax                ; rbx = fd
    
    ; sys_read(fd, level_load_buffer, 1192)
    mov rax, 0                  ; sys_read
    mov rdi, rbx                ; fd
    lea rsi, [rel level_load_buffer]
    mov rdx, 1192
    syscall
    
    ; sys_close(fd)
    mov rax, 3                  ; sys_close
    mov rdi, rbx
    syscall

    ; Copy loaded data from buffer to active game variables
    lea rsi, [rel level_load_buffer]
    
    ; 1. player_x (offset 0)
    mov rax, [rsi]
    mov [rel player_x], rax
    
    ; 2. player_y (offset 8)
    mov rax, [rsi + 8]
    mov [rel player_y], rax
    
    ; 3. player_angle (offset 16)
    mov rax, [rsi + 16]
    mov [rel player_angle], rax
    
    ; 4. world_map (offset 24, 1024 bytes)
    lea rdi, [rel world_map]
    lea rsi, [rel level_load_buffer + 24]
    mov rcx, 1024
    rep movsb
    
    ; 5. sprite_x (offset 1048, 64 bytes)
    extern sprite_x, sprite_y, sprite_type, sprite_active
    lea rdi, [rel sprite_x]
    lea rsi, [rel level_load_buffer + 1048]
    mov rcx, 64
    rep movsb
    
    ; 6. sprite_y (offset 1112, 64 bytes)
    lea rdi, [rel sprite_y]
    lea rsi, [rel level_load_buffer + 1112]
    mov rcx, 64
    rep movsb
    
    ; 7. sprite_type (offset 1176, 8 bytes)
    lea rdi, [rel sprite_type]
    lea rsi, [rel level_load_buffer + 1176]
    mov rcx, 8
    rep movsb
    
    rep movsb

    ; Sync enemy states and positions from sprite 6 and 7
    extern enemy_x, enemy_y, enemy_state, enemy_health
    
    ; Enemy 0 (sprite 6)
    lea rax, [rel sprite_active]
    movzx ecx, byte [rax + 6]
    lea rdx, [rel enemy_state]
    mov [rdx], cl               ; if active=1, state=1 (Idle/Patrol). if active=0, state=0 (Dead)
    
    lea rax, [rel sprite_x]
    mov rcx, [rax + 6*8]
    lea rdx, [rel enemy_x]
    mov [rdx], rcx
    
    lea rax, [rel sprite_y]
    mov rcx, [rax + 6*8]
    lea rdx, [rel enemy_y]
    mov [rdx], rcx
    
    lea rdx, [rel enemy_health]
    mov byte [rdx], 100
    
    ; Enemy 1 (sprite 7)
    lea rax, [rel sprite_active]
    movzx ecx, byte [rax + 7]
    lea rdx, [rel enemy_state]
    mov [rdx + 1], cl
    
    lea rax, [rel sprite_x]
    mov rcx, [rax + 7*8]
    lea rdx, [rel enemy_x]
    mov [rdx + 8], rcx
    
    lea rax, [rel sprite_y]
    mov rcx, [rax + 7*8]
    lea rdx, [rel enemy_y]
    mov [rdx + 8], rcx
    
    lea rdx, [rel enemy_health]
    mov byte [rdx + 1], 100


.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

section .data
    level_filename db "level.bin", 0

section .bss
    level_load_buffer: resb 1192

section .text

; is_passable: check if cell at index rax is walkable
; In: rax = cell index (row*MAP_WIDTH + col)
; Out: rax = 1 (passable) or 0 (blocked)
; Clobbers: rcx
is_passable:
    lea rcx, [rel world_map]
    movzx ecx, byte [rcx + rax]
    test ecx, ecx
    jz .passable                     ; 0 = open space

    ; check if it's an open door
    cmp cl, WALL_DOOR
    jne .blocked                     ; solid wall type 1-4
    ; check door_state
    lea rcx, [rel door_state]
    cmp byte [rcx + rax], 0
    jne .passable                    ; door open → passable
.blocked:
    xor eax, eax                     ; return 0
    ret
.passable:
    mov eax, 1                       ; return 1
    ret

toggle_door:
    push rbp
    mov rbp, rsp
    push rbx

    mov rax, [rel player_angle]
    lea rbx, [rel cos_table]
    mov rbx, [rbx + rax*8]          ; cos[angle] × 1024
    lea rcx, [rel sin_table]
    mov rcx, [rcx + rax*8]          ; sin[angle] × 1024

    ; target_x = (player_x + cos*256) >> 8  (one full cell ahead)
    mov rax, [rel player_x]
    imul rdx, rbx, 256              ; cos * 256 (Q8 offset = 1 cell)
    sar rdx, 10                     ; scale down LUT factor
    add rax, rdx
    sar rax, 8                      ; map_x of target cell

    cmp rax, 0
    jl .no_toggle
    cmp rax, MAP_WIDTH
    jge .no_toggle
    mov rbx, rax                    ; rbx = target map_x

    mov rax, [rel player_y]
    imul rdx, rcx, 256
    sar rdx, 10
    add rax, rdx
    sar rax, 8                      ; map_y of target cell

    cmp rax, 0
    jl .no_toggle
    cmp rax, MAP_HEIGHT
    jge .no_toggle

    imul rax, MAP_WIDTH
    add rax, rbx                    ; rax = cell index

    lea rcx, [rel world_map]
    cmp byte [rcx + rax], WALL_DOOR
    jne .no_toggle

    lea rcx, [rel door_state]
    xor byte [rcx + rax], 1         ; flip 0↔1

.no_toggle:
    pop rbx
    pop rbp
    ret

; x and y collision checked independently → wall sliding
update_game:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    cmp qword [rel game_over_flag], 1
    je .game_over_skip_input
    cmp qword [rel victory_flag], 1
    je .game_over_skip_input

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

    movzx r12, byte [rel key_up]
    movzx r13, byte [rel key_down]
    test r12, r12
    jnz .do_move
    test r13, r13
    jz .no_move

.do_move:
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

    mov rax, [rel player_x]
    add rax, r12                     ; proposed new_x (Q8)
    mov rbx, rax
    sar rbx, 8                       ; new map_x (integer)
    mov rcx, [rel player_y]
    sar rcx, 8                       ; current map_y (integer)
    imul rcx, MAP_WIDTH
    add rcx, rbx                     ; cell index
    push rax                         ; save proposed new_x
    mov rax, rcx
    call is_passable
    test eax, eax
    pop rax                          ; restore proposed new_x
    jz .skip_x
    mov [rel player_x], rax
.skip_x:

    mov rax, [rel player_y]
    add rax, r13                     ; proposed new_y (Q8)
    mov rbx, rax
    sar rbx, 8                       ; new map_y (integer)
    mov rcx, [rel player_x]
    sar rcx, 8                       ; current map_x (integer, possibly updated)
    imul rbx, MAP_WIDTH
    add rbx, rcx                     ; cell index
    push rax                         ; save proposed new_y
    mov rax, rbx
    call is_passable
    test eax, eax
    pop rax                          ; restore proposed new_y
    jz .skip_y
    mov [rel player_y], rax
.skip_y:

.no_move:
    extern key_shoot
    extern frame_count
    extern z_buffer
    extern render_scr_cols

    ; Handle shooting
    cmp byte [rel key_shoot], 1
    jne .no_shoot
    cmp qword [rel gun_fire_timer], 0
    jne .no_shoot
    mov qword [rel gun_fire_timer], 8    ; full animation cycle lasts 8 frames
    mov byte [rel key_shoot], 0          ; consume input
    
    ; --- HITSCAN COMBAT ---
    push r14
    push r15
    
    ; Get wall distance at center of screen (Z-buffer)
    mov rax, [rel render_scr_cols]
    sar rax, 1                  ; center column
    lea rdx, [rel z_buffer]
    mov r14, [rdx + rax*8]      ; r14 = perp_dist (cells * 1024)
    sar r14, 2                  ; r14 = wall_dist in Q8 (cells * 256)
    
    mov rax, [rel player_angle]
    lea rbx, [rel cos_table]
    mov rbx, [rbx + rax*8]      ; rbx = cos (x1024)
    lea rcx, [rel sin_table]
    mov rcx, [rcx + rax*8]      ; rcx = sin (x1024)
    
    extern enemy_x, enemy_y, enemy_state, enemy_health, enemy_timer
    xor r15, r15                ; i = 0
.hitscan_loop:
    cmp r15, NUM_ENEMIES                  ; NUM_ENEMIES
    jge .hitscan_done
    
    lea rdx, [rel enemy_state]
    mov al, [rdx + r15]
    cmp al, 3                   ; 3 = Dead
    je .hitscan_next
    cmp al, 0                   ; 0 = Inactive
    je .hitscan_next
    
    ; dx = enemy_x - player_x (Q8)
    lea rdx, [rel enemy_x]
    mov r8, [rdx + r15*8]
    sub r8, [rel player_x]      ; r8 = dx
    
    ; dy = enemy_y - player_y (Q8)
    lea rdx, [rel enemy_y]
    mov r9, [rdx + r15*8]
    sub r9, [rel player_y]      ; r9 = dy
    
    ; dot = (dx*cos + dy*sin) / 1024
    mov rax, r8
    imul rax, rbx
    mov r10, rax
    mov rax, r9
    imul rax, rcx
    add r10, rax
    sar r10, 10                 ; r10 = dot product (distance in front, Q8)
    
    ; if dot <= 0, enemy is behind us
    cmp r10, 0
    jle .hitscan_next
    
    ; if dot > wall_dist, wall is blocking the shot
    cmp r10, r14
    jg .hitscan_next
    
    ; cross = (cos*dy - sin*dx) / 1024
    mov rax, rbx
    imul rax, r9
    mov r11, rax
    mov rax, rcx
    imul rax, r8
    sub r11, rax
    sar r11, 10                 ; r11 = cross product (distance from aim line, Q8)
    
    ; abs(cross)
    mov rax, r11
    sar rax, 63
    xor r11, rax
    sub r11, rax
    
    ; if abs(cross) < 64 (0.25 cells wide hitbox), it's a HIT!
    cmp r11, 64
    jge .hitscan_next
    
    ; HIT!
    lea rdx, [rel enemy_health]
    mov al, [rdx + r15]
    sub al, 34                  ; 3 shots to kill 100hp
    jns .not_dead
    xor al, al                  ; cap at 0
.not_dead:
    mov [rdx + r15], al
    
    lea rdx, [rel enemy_timer]
    mov byte [rdx + r15], 10    ; stun for 10 frames
    
    lea rdx, [rel enemy_state]
    cmp al, 0
    je .kill_enemy
    mov byte [rdx + r15], 2     ; state 2 = Hurt
    jmp .hitscan_next
.kill_enemy:
    mov byte [rdx + r15], 3     ; state 3 = Dead

.hitscan_next:
    inc r15
    jmp .hitscan_loop

.hitscan_done:
    pop r15
    pop r14
    
.game_over_skip_input:
.no_shoot:
    ; decrement gun timer
    mov rax, [rel gun_fire_timer]
    test rax, rax
    jz .flash_done
    dec rax
    mov [rel gun_fire_timer], rax
.flash_done:

    ; Update muzzle flash light (Light 2)
    mov rax, [rel player_x]
    mov [rel light_x + 16], rax
    mov rax, [rel player_y]
    mov [rel light_y + 16], rax
    
    mov rax, [rel gun_fire_timer]
    cmp rax, 4
    jl .flash_off                       ; light is only ON for the first half of the animation
    mov qword [rel light_i + 16], 10    ; bright flash
    jmp .flash_update_done
.flash_off:
    mov qword [rel light_i + 16], 0     ; light off
.flash_update_done:

    ; Update pulsing light (Light 1) based on frame_count
    mov rax, [rel frame_count]
    and rax, 16                         ; toggle every 16 frames
    jz .pulse_dim
    mov qword [rel light_i + 8], 6
    jmp .pulse_done
.pulse_dim:
    mov qword [rel light_i + 8], 1
.pulse_done:

    call update_enemies

    ; --- Check Win Condition ---
    ; Condition: open all doors AND kill all enemies on the map
    
    ; 1. Check if all enemies are dead
    xor rcx, rcx                ; index = 0
.check_enemy_alive:
    cmp rcx, NUM_ENEMIES                  ; NUM_ENEMIES
    jge .all_enemies_dead
    lea rdx, [rel enemy_state]
    mov al, [rdx + rcx]
    cmp al, 1                   ; Chase/Idle
    je .win_not_met
    cmp al, 2                   ; Hurt
    je .win_not_met
    inc rcx
    jmp .check_enemy_alive

.all_enemies_dead:
    ; 2. Check if all doors are open
    xor rcx, rcx                ; cell index = 0
.check_doors_loop:
    cmp rcx, 1024
    jge .all_doors_open         ; checked all cells and they are all open!
    
    lea rdx, [rel world_map]
    cmp byte [rdx + rcx], 5     ; WALL_DOOR = 5
    jne .next_cell
    
    lea rdx, [rel door_state]
    cmp byte [rdx + rcx], 0     ; 0 = closed
    je .win_not_met             ; closed door found -> win conditions not met!
    
.next_cell:
    inc rcx
    jmp .check_doors_loop

.all_doors_open:
    mov qword [rel victory_flag], 1
    jmp .win_done

.win_not_met:
    mov qword [rel victory_flag], 0

.win_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; --- ENEMY AI & MOVEMENT ---
update_enemies:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    extern sprite_x, sprite_y, sprite_type, enemy_sprite_idx
    
    xor r15, r15                ; i = 0
.ai_loop:
    cmp r15, NUM_ENEMIES                  ; NUM_ENEMIES
    jge .ai_done
    
    lea rdx, [rel enemy_state]
    mov al, [rdx + r15]
    cmp al, 3                   ; Dead
    je .ai_update_sprite
    cmp al, 0                   ; Inactive
    je .ai_next
    
    cmp al, 2                   ; Hurt
    jne .ai_chase
    ; Hurt state cooldown
    lea rdx, [rel enemy_timer]
    mov al, [rdx + r15]
    dec al
    mov [rdx + r15], al
    test al, al
    jnz .ai_update_sprite       ; still stunned
    lea rdx, [rel enemy_state]
    mov byte [rdx + r15], 1     ; return to Chase state
    jmp .ai_chase
    
.ai_chase:
    ; dx = player_x - enemy_x
    mov rbx, [rel player_x]
    lea rdx, [rel enemy_x]
    sub rbx, [rdx + r15*8]      ; rbx = dx
    
    ; dy = player_y - enemy_y
    mov rcx, [rel player_y]
    lea rdx, [rel enemy_y]
    sub rcx, [rdx + r15*8]      ; rcx = dy
    
    ; Rough distance: abs(dx) + abs(dy)
    mov r10, rbx
    mov rax, r10
    sar rax, 63
    xor r10, rax
    sub r10, rax
    
    mov r11, rcx
    mov rax, r11
    sar rax, 63
    xor r11, rax
    sub r11, rax
    
    add r10, r11
    
    cmp r10, 4096               ; 16 cells detection range
    jg .ai_update_sprite        ; too far, don't move
    cmp r10, 192                ; 0.75 cells attack range
    jl .ai_attack
    
    ; Move X
    mov r12, 4                  ; ENEMY_SPEED = 4 (Q8)
    test rbx, rbx
    jns .dx_pos
    neg r12
.dx_pos:
    lea rdx, [rel enemy_x]
    mov rax, [rdx + r15*8]
    add rax, r12                ; proposed new_x
    mov r13, rax
    sar r13, 8                  ; map_x
    lea rdx, [rel enemy_y]
    mov r14, [rdx + r15*8]
    sar r14, 8                  ; map_y
    imul r14, MAP_WIDTH
    add r14, r13                ; cell index
    
    push rcx                    ; is_passable clobbers rcx
    push rax
    mov rax, r14
    call is_passable
    test eax, eax
    pop rax
    pop rcx                     ; restore rcx (dy)
    
    jz .ai_move_y
    lea rdx, [rel enemy_x]
    mov [rdx + r15*8], rax      ; commit X move
    
.ai_move_y:
    mov r12, 4                  ; ENEMY_SPEED = 4
    test rcx, rcx
    jns .dy_pos
    neg r12
.dy_pos:
    lea rdx, [rel enemy_y]
    mov rax, [rdx + r15*8]
    add rax, r12                ; proposed new_y
    mov r13, rax
    sar r13, 8                  ; map_y
    lea rdx, [rel enemy_x]
    mov r14, [rdx + r15*8]
    sar r14, 8                  ; map_x (possibly updated)
    imul r13, MAP_WIDTH
    add r14, r13                ; cell index
    push rax
    mov rax, r14
    call is_passable
    test eax, eax
    pop rax
    jz .ai_update_sprite
    lea rdx, [rel enemy_y]
    mov [rdx + r15*8], rax      ; commit Y move
    jmp .ai_update_sprite

.ai_attack:
    ; Deal damage (e.g. 10 damage every 32 frames)
    mov rax, [rel frame_count]
    and rax, 31
    jnz .ai_update_sprite
    
    mov rax, [rel player_health]
    sub rax, 10
    jns .health_ok
    xor rax, rax                ; cap at 0
.health_ok:
    mov [rel player_health], rax
    cmp rax, 0
    jg .ai_update_sprite
    
    ; Game Over!
    mov qword [rel game_over_flag], 1

.ai_update_sprite:
    ; Sync enemy_x/y to sprite_x/y
    lea rdx, [rel enemy_sprite_idx]
    movzx r10, byte [rdx + r15] ; r10 = sprite index
    
    lea rdx, [rel enemy_x]
    mov rax, [rdx + r15*8]
    lea rdx, [rel sprite_x]
    mov [rdx + r10*8], rax
    
    lea rdx, [rel enemy_y]
    mov rax, [rdx + r15*8]
    lea rdx, [rel sprite_y]
    mov [rdx + r10*8], rax
    
    ; Update sprite type based on state
    lea rdx, [rel enemy_state]
    mov al, [rdx + r15]
    mov bl, 3                   ; Sprite type 3 = Alive Enemy
    cmp al, 3
    jne .set_type
    mov bl, 4                   ; Sprite type 4 = Dead Enemy
.set_type:
    lea rdx, [rel sprite_type]
    mov [rdx + r10], bl

.ai_next:
    inc r15
    jmp .ai_loop

.ai_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; In:  rdi = ray angle (0..359)
; Out: rax = perpendicular wall distance (map units × 1024), min 1
;      rdx = wall type (1-5) of the cell that was hit
; Register allocation during DDA loop:
;   r10=map_x   r11=map_y   r12=delta_x   r13=delta_y
;   r14=side_x  r15=side_y  rbx=step_x    rcx=step_y
;   rdx=side(0=x,1=y)       rsi=iteration counter
cast_ray:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    lea rax, [rel cos_table]
    mov r8, [rax + rdi*8]            ; r8 = cos[angle] (×1024)
    lea rax, [rel sin_table]
    mov r9, [rax + rdi*8]            ; r9 = sin[angle] (×1024)

    mov rax, [rel player_x]
    sar rax, 8
    mov r10, rax                     ; map_x

    mov rax, [rel player_y]
    sar rax, 8
    mov r11, rax                     ; map_y

    ; delta_dist = |1024²/ray_dir|  (0 → DDA_INF: that axis is never stepped)
    test r8, r8
    jz .ddx_zero
    mov rax, 1048576                 ; 1024 × 1024
    cqo
    idiv r8
    test rax, rax
    jns .ddx_pos
    neg rax
.ddx_pos:
    mov r12, rax
    jmp .ddx_done
.ddx_zero:
    mov r12, DDA_INF
.ddx_done:

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

    mov rsi, 64                      ; max iterations (32+32 for 32×32 map)
.dda_loop:
    dec rsi
    jz .hit_far                      ; safety: map has boundary walls so unreachable

    cmp r14, r15
    jle .dda_step_x

    add r15, r13
    add r11, rcx
    mov rdx, 1
    jmp .dda_check

.dda_step_x:                         ; equal: prefer x for determinism
    add r14, r12
    add r10, rbx
    xor rdx, rdx

.dda_check:
    cmp r10, 0
    jl .hit_far
    cmp r10, MAP_WIDTH
    jge .hit_far
    cmp r11, 0
    jl .hit_far
    cmp r11, MAP_HEIGHT
    jge .hit_far

    ; cell index = map_y * MAP_WIDTH + map_x
    mov rax, r11
    imul rax, MAP_WIDTH
    add rax, r10

    lea r8, [rel world_map]
    movzx r8, byte [r8 + rax]       ; r8 = cell value (0=open, 1-5=wall/door)
    test r8, r8
    jz .dda_loop                     ; open space, continue

    cmp r8b, WALL_DOOR
    jne .dda_wall_hit                ; solid wall types 1-4
    lea r9, [rel door_state]
    cmp byte [r9 + rax], 0
    jne .dda_loop                    ; door is open, ray passes through

.dda_wall_hit:
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
    jge .perp_ok
    mov rax, 1                       ; clamp: minimum distance 1 (avoids /0)
.perp_ok:
    mov rcx, rdx                     ; return side in rcx
    mov rdx, r8                      ; return wall type in rdx
    jmp .ray_done

.hit_far:
    mov rax, MAP_HEIGHT * 1024       ; ray escaped: return maximum distance
    mov rdx, 1                       ; default to stone
    xor rcx, rcx                     ; default side 0

.ray_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

section .data
    global num_lights
    global light_x, light_y, light_r, light_i, light_type
    
    ; 0 = static white, 1 = pulsing red, 2 = muzzle flash
    num_lights dq 3
    
    ; Light 0: Static light in central corridor (near 16, 16)
    ; Light 1: Pulsing alarm light in brick room (near 5, 5)
    ; Light 2: Muzzle flash (attached to player, initially off)
    light_x: dq 16*256 + 128,  5*256 + 128,  0
    light_y: dq 16*256 + 128,  5*256 + 128,  0
    
    ; radius squared (in 256-units) to avoid sqrt
    ; e.g. 5 cells = 5*256 = 1280. squared = 1638400
    light_r: dq 1638400, 1000000, 2000000
    
    ; Intensity (0=off, higher=brighter)
    light_i: dq 4, 3, 0
    
    ; Type for colors
    light_type: dq 0, 1, 2

    global gun_fire_timer
    gun_fire_timer dq 0
