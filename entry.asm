; entry.asm: program entry point, main loop, shutdown

section .data
    msg_start db 'terminal engine starting', 10
    msg_start_len equ $ - msg_start

section .text
    extern init_terminal
    extern restore_terminal
    extern get_terminal_size
    extern process_input
    extern get_time
    extern elapsed_ns
    extern sleep_remaining
    extern init_game
    extern update_game
    extern render_init
    extern render_frame
    extern render_start_screen
    extern quit_flag
    extern any_key
    extern resize_flag
    extern time_start
    extern time_current
    extern key_use
    extern toggle_door

    global _start

FRAME_NS equ 16666666         ; 60fps target: ~16.67ms per frame

_start:
    call init_terminal
    call get_terminal_size
    call init_game
    call render_init
    call render_start_screen
.start_screen_loop:
    call process_input
    cmp byte [rel quit_flag], 1
    je .shutdown
    cmp byte [rel any_key], 1
    je .game_loop
    mov rdi, 50000000           ; 50ms poll: no busy-wait
    call sleep_remaining
    jmp .start_screen_loop

.game_loop:
    lea rdi, [rel time_start]
    call get_time

    call process_input
    cmp byte [rel quit_flag], 1
    je .shutdown

    cmp byte [rel key_use], 1
    jne .no_use
    call toggle_door
.no_use:

    ; handle terminal resize
    cmp byte [rel resize_flag], 1
    jne .no_resize
    mov byte [rel resize_flag], 0
    call get_terminal_size
    call render_init
.no_resize:

    call update_game
    call render_frame

    lea rdi, [rel time_current]
    call get_time

    lea rdi, [rel time_start]
    lea rsi, [rel time_current]
    call elapsed_ns

    mov rcx, FRAME_NS
    sub rcx, rax               ; remaining = budget - elapsed
    jle .game_loop             ; over budget: skip sleep
    mov rdi, rcx
    call sleep_remaining
    jmp .game_loop

.shutdown:
    call restore_terminal
    mov rax, 60
    xor rdi, rdi
    syscall
