.text
.globl _tc_adder
.p2align 2
_tc_adder:
    eor w3,w0,w1
    and w4,w0,w1
    and w5,w3,w2
    orr w1,w4,w5
    eor w0,w3,w2
    orr w0,w0,w1,lsl #1
    ret
.globl _tc_loop
.p2align 2
_tc_loop:
    ldr w2,[x0]
    add w2,w2,#1
    str w2,[x0]
    sub w1,w1,#1
    cbnz w1,_tc_loop
    ret
.globl _tc_wide
.p2align 2
_tc_wide:
    eor x0,x0,x1
    add x0,x0,#1
    orr x0,x0,x0,lsl #63
    ret
.globl _tc_mem_widths
.p2align 2
_tc_mem_widths:
    ldrb w1,[x0]
    strh w1,[x0,#2]
    ldrh w2,[x0,#2]
    str x2,[x0,#8]
    ldr x3,[x0,#8]
    ret
