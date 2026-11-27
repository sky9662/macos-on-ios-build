#include "arm64_subset.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#ifdef TC_NATIVE_FIXTURE
extern uint32_t tc_adder(uint32_t a,uint32_t b,uint32_t carry);
extern void tc_loop(uint32_t *value,uint32_t count);
#endif
/* Independently authored A64 instruction fixtures; see fixture.s. */
static const uint32_t adder[]={0x4a010003,0x0a010004,0x0a020065,0x2a050081,
                              0x4a020060,0x2a010400,0xd65f03c0};
static const uint32_t loop[]={0xb9400002,0x11000442,0xb9000002,0x51000421,
                             0x35ffff81,0xd65f03c0};
#define LENGTH(a) (sizeof(a)/sizeof((a)[0]))
int main(void) {
    for(uint32_t a=0;a<2;a++) for(uint32_t b=0;b<2;b++) for(uint32_t c=0;c<2;c++) {
        TCRegisters r={0};r.w[0]=a;r.w[1]=b;r.w[2]=c;
        assert(tc_interpret(adder,LENGTH(adder),&r,NULL,0,32)==TC_OK);
        assert(r.w[0]==a+b+c);
#ifdef TC_NATIVE_FIXTURE
        assert(r.w[0]==tc_adder(a,b,c));
#endif
    }
    for(uint32_t i=1;i<=64;i++) {
        TCRegisters r={0};r.w[1]=i;
        uint8_t mem[]={250,0,0,0};
        assert(tc_interpret(loop,LENGTH(loop),&r,mem,sizeof(mem),512)==TC_OK);
        uint32_t result=(uint32_t)mem[0]+((uint32_t)mem[1]<<8);
        assert(result==250+i && mem[2]==0 && mem[3]==0);
#ifdef TC_NATIVE_FIXTURE
        uint32_t native=250;tc_loop(&native,i);assert(native==result);
#endif
    }
    TCRegisters r={0};uint8_t mem[4]={1,2,3,4},before[4];memcpy(before,mem,4);
    const uint32_t jump[]={0x14000000}, bad[]={0xd61f0000}, oob[]={0xb9400402,0xd65f03c0},
                   past[]={0x14000002}, negative[]={0x17ffffff}, sp[]={0x110003e0};
    assert(tc_interpret(jump,LENGTH(jump),&r,mem,4,16)==TC_BUDGET);
    assert(tc_interpret(bad,LENGTH(bad),&r,mem,4,16)==TC_UNSUPPORTED);
    assert(tc_interpret(sp,LENGTH(sp),&r,mem,4,16)==TC_UNSUPPORTED);
    assert(tc_interpret(oob,LENGTH(oob),&r,mem,4,16)==TC_BOUNDS);
    assert(tc_interpret(past,LENGTH(past),&r,mem,4,16)==TC_BOUNDS);
    assert(tc_interpret(negative,LENGTH(negative),&r,mem,4,16)==TC_BOUNDS);
    assert(tc_interpret(adder,LENGTH(adder),&r,mem,4,0)==TC_ARGUMENT);
    assert(memcmp(mem,before,4)==0);
    puts("PASS: 8 full-adder combinations, 64 bounded memory loops, 7 rejection cases");
    return 0;
}
