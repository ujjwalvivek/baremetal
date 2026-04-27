; =============================================================================
; math.asm: Integer to ASCII conversion
; =============================================================================

section .bss
; Small scratch buffer for digit reversal (max 20 digits for 64-bit)
digit_buf: resb 20

section .text
global int_to_ascii

; =============================================================================
; int_to_ascii: Convert unsigned integer to ASCII decimal string
; Input:  rax = value to convert
;         rdi = destination buffer pointer
; Output: rdi = pointer past last written byte
;         rax = number of bytes written
; Preserves: rbx, r12-r15 (callee-saved per SysV ABI)
; =============================================================================
int_to_ascii:
    push rbx
    push r12

    mov r12, rdi               ; save dest pointer
    mov rbx, 10                ; divisor
    xor rcx, rcx               ; digit count = 0

    ; Special case: value is 0
    test rax, rax
    jnz .divide_loop
    mov byte [rdi], '0'
    inc rdi
    mov rax, 1
    pop r12
    pop rbx
    ret

.divide_loop:
    xor rdx, rdx
    div rbx                    ; rax = quotient, rdx = remainder
    add dl, '0'                ; convert to ASCII
    mov [rel digit_buf + rcx], dl
    inc rcx
    test rax, rax
    jnz .divide_loop

    ; Digits are in digit_buf in reverse order. Write them forward.
    mov rax, rcx               ; save count for return value
.write_loop:
    dec rcx
    movzx rdx, byte [rel digit_buf + rcx]
    mov [rdi], dl
    inc rdi
    test rcx, rcx
    jnz .write_loop

    ; rdi is now past last written byte
    ; rax = number of bytes written
    pop r12
    pop rbx
    ret
