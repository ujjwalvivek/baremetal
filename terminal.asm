; =============================================================================
; terminal.asm: Raw mode, signal handlers, terminal size, cleanup
; =============================================================================

section .data

; --- Escape sequences (no null terminators: we use write() with lengths) ----
esc_hide_cursor:   db 27, '[?25l'
esc_hide_cursor_len equ $ - esc_hide_cursor

esc_show_cursor:   db 27, '[?25h'
esc_show_cursor_len equ $ - esc_show_cursor

esc_clear_screen:  db 27, '[2J'
esc_clear_screen_len equ $ - esc_clear_screen

esc_reset_color:   db 27, '[0m'
esc_reset_color_len equ $ - esc_reset_color

esc_alt_on:        db 27, '[?1049h'
esc_alt_on_len     equ $ - esc_alt_on

esc_alt_off:       db 27, '[?1049l'
esc_alt_off_len    equ $ - esc_alt_off

; --- sigaction struct for rt_sigaction ----------------------------------------
; struct sigaction {
;     void     (*sa_handler)(int);     offset 0   (8 bytes, pointer)
;     uint64_t   sa_flags;             offset 8   (8 bytes)
;     void     (*sa_restorer)(void);   offset 16  (8 bytes, pointer)
;     sigset_t   sa_mask;              offset 24  (8 bytes for kernel)
; }
; Total: 32 bytes (kernel version)

SA_RESTORER equ 0x04000000
SA_SIGINFO  equ 0x00000004

section .bss

; --- termios structs (60 bytes each) -----------------------------------------
termios_orig: resb 60
termios_raw:  resb 60

; --- sigaction struct --------------------------------------------------------
sigact:       resb 32

; --- winsize struct for TIOCGWINSZ -------------------------------------------
; struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; }
winsize:      resb 8

; --- Exported terminal dimensions --------------------------------------------
global term_rows
global term_cols
term_rows:    resq 1
term_cols:    resq 1

section .text

; --- Syscall numbers ---------------------------------------------------------
SYS_WRITE        equ 1
SYS_IOCTL        equ 16
SYS_RT_SIGACTION equ 13
SYS_RT_SIGRETURN equ 15
SYS_EXIT         equ 60

; --- ioctl request codes -----------------------------------------------------
TCGETS      equ 0x5401
TCSETS      equ 0x5402
TIOCGWINSZ  equ 0x5413

; --- termios flag bits -------------------------------------------------------
; c_iflag (offset 0)
BRKINT equ 0x0002
ICRNL  equ 0x0100
INPCK  equ 0x0010
ISTRIP equ 0x0020
IXON   equ 0x0400
IFLAG_MASK equ BRKINT | ICRNL | INPCK | ISTRIP | IXON

; c_oflag (offset 4)
OPOST  equ 0x0001

; c_lflag (offset 12)
ECHO   equ 0x0008
ICANON equ 0x0002
IEXTEN equ 0x8000
ISIG   equ 0x0001
LFLAG_MASK equ ECHO | ICANON | IEXTEN | ISIG

; --- c_cc offsets (c_cc starts at offset 17, after c_line at offset 16) ------
CC_VTIME equ 17 + 5           ; = 22
CC_VMIN  equ 17 + 6           ; = 23

; --- Signal numbers ----------------------------------------------------------
SIGINT  equ 2
SIGSEGV equ 11
SIGTERM equ 15

    global init_terminal
    global restore_terminal
    global get_terminal_size

; =============================================================================
; init_terminal: Save termios, enter raw mode, hide cursor, install signals
; =============================================================================
init_terminal:
    push rbp
    mov rbp, rsp

    ; --- Save original termios via ioctl(TCGETS) ---
    mov rax, SYS_IOCTL
    mov rdi, 0                  ; stdin
    mov rsi, TCGETS
    lea rdx, [rel termios_orig]
    syscall

    ; --- Copy original to raw ---
    lea rsi, [rel termios_orig]
    lea rdi, [rel termios_raw]
    mov rcx, 60
    cld
    rep movsb

    ; --- Modify c_iflag: clear BRKINT|ICRNL|INPCK|ISTRIP|IXON ---
    mov eax, [rel termios_raw + 0]
    and eax, ~IFLAG_MASK
    mov [rel termios_raw + 0], eax

    ; --- Modify c_oflag: clear OPOST ---
    mov eax, [rel termios_raw + 4]
    and eax, ~OPOST
    mov [rel termios_raw + 4], eax

    ; --- Modify c_lflag: clear ECHO|ICANON|IEXTEN|ISIG ---
    mov eax, [rel termios_raw + 12]
    and eax, ~LFLAG_MASK
    mov [rel termios_raw + 12], eax

    ; --- Set VMIN=0, VTIME=0 for non-blocking reads ---
    mov byte [rel termios_raw + CC_VMIN], 0
    mov byte [rel termios_raw + CC_VTIME], 0

    ; --- Apply raw termios via ioctl(TCSETS) ---
    mov rax, SYS_IOCTL
    mov rdi, 0
    mov rsi, TCSETS
    lea rdx, [rel termios_raw]
    syscall

    ; --- Enter alternate screen buffer (saves normal screen, fresh buffer for game) ---
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rel esc_alt_on]
    mov rdx, esc_alt_on_len
    syscall

    ; --- Hide cursor ---
    mov rax, SYS_WRITE
    mov rdi, 1                  ; stdout
    lea rsi, [rel esc_hide_cursor]
    mov rdx, esc_hide_cursor_len
    syscall

    ; --- Clear screen (initial) ---
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rel esc_clear_screen]
    mov rdx, esc_clear_screen_len
    syscall

    ; --- Install signal handlers for SIGINT, SIGTERM, SIGSEGV ---
    ; Build sigaction struct
    lea rax, [rel signal_handler]
    mov [rel sigact + 0], rax           ; sa_handler
    mov qword [rel sigact + 8], SA_RESTORER  ; sa_flags
    lea rax, [rel restorer_trampoline]
    mov [rel sigact + 16], rax          ; sa_restorer
    mov qword [rel sigact + 24], 0      ; sa_mask (empty)

    ; Install for SIGINT (2)
    mov rax, SYS_RT_SIGACTION
    mov rdi, SIGINT
    lea rsi, [rel sigact]
    xor rdx, rdx                ; old_act = NULL
    mov r10, 8                  ; sigsetsize
    syscall

    ; Install for SIGTERM (15)
    mov rax, SYS_RT_SIGACTION
    mov rdi, SIGTERM
    lea rsi, [rel sigact]
    xor rdx, rdx
    mov r10, 8
    syscall

    ; Install for SIGSEGV (11)
    mov rax, SYS_RT_SIGACTION
    mov rdi, SIGSEGV
    lea rsi, [rel sigact]
    xor rdx, rdx
    mov r10, 8
    syscall

    pop rbp
    ret

; =============================================================================
; restore_terminal: Restore original termios, show cursor, reset colors
; =============================================================================
restore_terminal:
    push rbp
    mov rbp, rsp

    ; Restore original termios
    mov rax, SYS_IOCTL
    mov rdi, 0
    mov rsi, TCSETS
    lea rdx, [rel termios_orig]
    syscall

    ; Show cursor
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rel esc_show_cursor]
    mov rdx, esc_show_cursor_len
    syscall

    ; Reset colors
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rel esc_reset_color]
    mov rdx, esc_reset_color_len
    syscall

    ; --- Leave alternate screen buffer (restores original terminal content) ---
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rel esc_alt_off]
    mov rdx, esc_alt_off_len
    syscall

    pop rbp
    ret

; =============================================================================
; get_terminal_size: Query terminal dimensions via ioctl(TIOCGWINSZ)
; =============================================================================
get_terminal_size:
    push rbp
    mov rbp, rsp

    mov rax, SYS_IOCTL
    mov rdi, 1                  ; stdout
    mov rsi, TIOCGWINSZ
    lea rdx, [rel winsize]
    syscall

    ; winsize: ws_row (2 bytes at offset 0), ws_col (2 bytes at offset 2)
    movzx rax, word [rel winsize]
    mov [rel term_rows], rax
    movzx rax, word [rel winsize + 2]
    mov [rel term_cols], rax

    ; Sanity fallback: if 0, default to 80x24
    cmp qword [rel term_rows], 0
    jne .rows_ok
    mov qword [rel term_rows], 24
.rows_ok:
    cmp qword [rel term_cols], 0
    jne .cols_ok
    mov qword [rel term_cols], 80
.cols_ok:

    pop rbp
    ret

; =============================================================================
; signal_handler: Restore terminal then exit(1)
; =============================================================================
signal_handler:
    ; Don't bother saving registers: we're exiting
    call restore_terminal
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

; =============================================================================
; restorer_trampoline: Required by rt_sigaction to call rt_sigreturn
; =============================================================================
restorer_trampoline:
    mov rax, SYS_RT_SIGRETURN
    syscall
