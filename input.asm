; =============================================================================
; input.asm: Non-blocking keyboard input via poll + read
; =============================================================================

section .bss
poll_fd: resb 8
key_buffer: resb 8

global key_up, key_down, key_left, key_right, quit_flag
key_up:    resb 1
key_down:  resb 1
key_left:  resb 1
key_right: resb 1
quit_flag: resb 1

section .text
SYS_READ equ 0
SYS_POLL equ 7
POLLIN   equ 0x0001

global process_input

poll_keyboard:
    mov dword [rel poll_fd], 0
    mov word [rel poll_fd + 4], POLLIN
    mov word [rel poll_fd + 6], 0
    mov rax, SYS_POLL
    lea rdi, [rel poll_fd]
    mov rsi, 1
    xor rdx, rdx
    syscall
    ret

read_key:
    call poll_keyboard
    test rax, rax
    jle .no_input
    mov rax, SYS_READ
    xor rdi, rdi
    lea rsi, [rel key_buffer]
    mov rdx, 1
    syscall
    cmp rax, 1
    jne .no_input
    movzx rax, byte [rel key_buffer]
    ret
.no_input:
    xor rax, rax
    ret

process_input:
    push rbp
    mov rbp, rsp

    ; Clear all direction flags: one direction per frame, last key wins
    mov byte [rel key_up], 0
    mov byte [rel key_down], 0
    mov byte [rel key_left], 0
    mov byte [rel key_right], 0

    ; Drain all buffered input. Each recognised key clears the others and
    ; sets only itself: so if W and D are both in the buffer, whichever
    ; arrived last is the one that moves. No diagonals, ever.
.read_loop:
    call read_key
    test al, al
    jz .done
    cmp al, 'w'
    je .set_up
    cmp al, 'W'
    je .set_up
    cmp al, 's'
    je .set_down
    cmp al, 'S'
    je .set_down
    cmp al, 'a'
    je .set_left
    cmp al, 'A'
    je .set_left
    cmp al, 'd'
    je .set_right
    cmp al, 'D'
    je .set_right
    cmp al, 'q'
    je .set_quit
    cmp al, 'Q'
    je .set_quit
    jmp .read_loop
.set_up:
    mov byte [rel key_up], 1
    mov byte [rel key_down], 0
    mov byte [rel key_left], 0
    mov byte [rel key_right], 0
    jmp .read_loop
.set_down:
    mov byte [rel key_down], 1
    mov byte [rel key_up], 0
    mov byte [rel key_left], 0
    mov byte [rel key_right], 0
    jmp .read_loop
.set_left:
    mov byte [rel key_left], 1
    mov byte [rel key_up], 0
    mov byte [rel key_down], 0
    mov byte [rel key_right], 0
    jmp .read_loop
.set_right:
    mov byte [rel key_right], 1
    mov byte [rel key_up], 0
    mov byte [rel key_down], 0
    mov byte [rel key_left], 0
    jmp .read_loop
.set_quit:
    mov byte [rel quit_flag], 1
    jmp .read_loop
.done:
    pop rbp
    ret
