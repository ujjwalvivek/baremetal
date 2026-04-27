; =============================================================================
; entry.asm: Entry point, game loop, shutdown
; =============================================================================

section .data
    msg_start db 'terminal engine starting', 10
    msg_start_len equ $ - msg_start

section .text
    ; Imports from other modules
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
    extern quit_flag
    extern time_start
    extern time_current

    global _start

; --- Constants ---------------------------------------------------------------
FRAME_NS equ 16666666         ; 60fps = ~16.67ms per frame

; =============================================================================
; _start: Program entry point
; =============================================================================
_start:
    ; Initialize terminal (raw mode, hide cursor, signal handlers)
    call init_terminal

    ; Query terminal size
    call get_terminal_size

    ; Initialize game state (player at center)
    call init_game

    ; Draw border and initial scene (once: never redrawn)
    call render_init

    ; Enter game loop
    jmp .game_loop

; =============================================================================
; Game loop: fixed timestep
; =============================================================================
.game_loop:
    ; Record frame start time
    lea rdi, [rel time_start]
    call get_time

    ; Process input (non-blocking poll + read)
    call process_input

    ; Check quit flag
    cmp byte [rel quit_flag], 1
    je .shutdown

    ; Update game state
    call update_game

    ; Render frame
    call render_frame

    ; Record frame end time
    lea rdi, [rel time_current]
    call get_time

    ; Calculate elapsed nanoseconds
    lea rdi, [rel time_start]
    lea rsi, [rel time_current]
    call elapsed_ns            ; rax = elapsed ns

    ; Sleep for remaining frame budget
    mov rcx, FRAME_NS
    sub rcx, rax               ; remaining = target - elapsed
    jle .game_loop             ; if negative/zero, we're behind: skip sleep

    mov rdi, rcx
    call sleep_remaining

    jmp .game_loop

; =============================================================================
; Shutdown: Restore terminal, exit cleanly
; =============================================================================
.shutdown:
    call restore_terminal

    ; exit(0)
    mov rax, 60
    xor rdi, rdi
    syscall
