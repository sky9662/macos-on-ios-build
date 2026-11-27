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
