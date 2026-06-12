; timing.asm: clock_gettime, elapsed calculation, nanosleep

section .bss
global time_start, time_current
time_start:   resb 16    ; timespec {tv_sec, tv_nsec}
time_current: resb 16
time_sleep:   resb 16

section .text
SYS_CLOCK_GETTIME equ 228
SYS_NANOSLEEP     equ 35
CLOCK_MONOTONIC   equ 1

global get_time, elapsed_ns, sleep_remaining

get_time:
    mov rsi, rdi               ; rsi = timespec ptr
    mov rax, SYS_CLOCK_GETTIME
    mov rdi, CLOCK_MONOTONIC
    syscall
    ret

elapsed_ns:
    push rbx
    mov rax, [rsi]             ; end tv_sec
    sub rax, [rdi]             ; - start tv_sec
    imul rax, 1000000000       ; seconds -> nanoseconds
    mov rcx, [rsi + 8]         ; end tv_nsec
    sub rcx, [rdi + 8]         ; - start tv_nsec
    add rax, rcx               ; total elapsed ns
    pop rbx
    ret

sleep_remaining:
    ; Frame sleeps are always < 1s, so tv_sec=0, tv_nsec=rdi
    mov qword [rel time_sleep], 0      ; tv_sec = 0
    mov [rel time_sleep + 8], rdi      ; tv_nsec = nanoseconds
    mov rax, SYS_NANOSLEEP
    lea rdi, [rel time_sleep]
    xor rsi, rsi               ; no remainder struct
    syscall
    ret
