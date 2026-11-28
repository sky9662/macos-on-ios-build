#include "arm64_subset.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#ifdef TC_NATIVE_FIXTURE
extern uint32_t tc_adder(uint32_t a,uint32_t b,uint32_t carry);
extern void tc_loop(uint32_t *value,uint32_t count);
extern uint64_t tc_wide(uint64_t a,uint64_t b);
extern void tc_mem_widths(uint8_t *p);
#endif
/* Independently authored A64 instruction fixtures; see fixture.s. */
static const uint32_t adder[]={0x4a010003,0x0a010004,0x0a020065,0x2a050081,
                              0x4a020060,0x2a010400,0xd65f03c0};
static const uint32_t loop[]={0xb9400002,0x11000442,0xb9000002,0x51000421,
                             0x35ffff81,0xd65f03c0};
static const uint32_t wide_ops[]={0xca010000,0x91000400,0xaa00fc00,0xd65f03c0};
static const uint32_t widths[]={0x39400001,0x79000401,0x79400402,0xf9000402,
                                0xf9400403,0xd65f03c0};
#define LENGTH(a) (sizeof(a)/sizeof((a)[0]))
int main(void) {
    for(uint32_t a=0;a<2;a++) for(uint32_t b=0;b<2;b++) for(uint32_t c=0;c<2;c++) {
        TCRegisters r={0};r.x[0]=a;r.x[1]=b;r.x[2]=c;
        assert(tc_interpret(adder,LENGTH(adder),&r,NULL,0,32)==TC_OK);
        assert(r.x[0]==a+b+c);
#ifdef TC_NATIVE_FIXTURE
        assert(r.x[0]==tc_adder(a,b,c));
#endif
    }
    for(uint32_t i=1;i<=64;i++) {
        TCRegisters r={0};r.x[1]=i;
        uint8_t mem[]={250,0,0,0};
        assert(tc_interpret(loop,LENGTH(loop),&r,mem,sizeof(mem),512)==TC_OK);
        uint32_t result=(uint32_t)mem[0]+((uint32_t)mem[1]<<8);
        assert(result==250+i && mem[2]==0 && mem[3]==0);
#ifdef TC_NATIVE_FIXTURE
        uint32_t native=250;tc_loop(&native,i);assert(native==result);
#endif
    }
    for(unsigned i=0;i<1024;i++) {
        uint64_t a=UINT64_C(0x1234567800000000)+i,b=UINT64_C(0xfedcba9876543210)-i;
        TCRegisters r={0};r.x[0]=a;r.x[1]=b;
        assert(tc_interpret(wide_ops,LENGTH(wide_ops),&r,NULL,0,16)==TC_OK);
        uint64_t expected=(a^b)+1;expected|=expected<<63;
        assert(r.x[0]==expected);
#ifdef TC_NATIVE_FIXTURE
        assert(r.x[0]==tc_wide(a,b));
#endif
    }
    for(unsigned i=0;i<256;i++) {
        TCRegisters r={0};r.x[1]=UINT64_MAX;r.x[2]=UINT64_MAX;
        uint8_t m[16]={0};m[0]=(uint8_t)i;
        assert(tc_interpret(widths,LENGTH(widths),&r,m,sizeof(m),16)==TC_OK);
        assert(r.x[1]==i && r.x[2]==i && r.x[3]==i && m[2]==i && m[3]==0 && m[8]==i);
#ifdef TC_NATIVE_FIXTURE
        uint8_t native[16]={0};native[0]=(uint8_t)i;tc_mem_widths(native);
        assert(memcmp(m,native,sizeof(m))==0);
#endif
    }
    {
        TCRegisters r={0};r.x[0]=UINT64_MAX;
        uint8_t m[16]={0};
        assert(tc_interpret(widths,LENGTH(widths),&r,m,sizeof(m),16)==TC_BOUNDS);
        const uint32_t overflow[]={0xf9400401,0xd65f03c0};
        assert(tc_interpret(overflow,LENGTH(overflow),&r,m,sizeof(m),16)==TC_BOUNDS);
        const uint32_t wzero[]={0x11000400,0xd65f03c0};
        assert(tc_interpret(wzero,LENGTH(wzero),&r,NULL,0,16)==TC_OK && r.x[0]==0);
        const uint32_t cbnz[]={0xb5000040,0xd61f0000,0xd65f03c0};
        r.x[0]=UINT64_C(1)<<32;
        assert(tc_interpret(cbnz,LENGTH(cbnz),&r,NULL,0,16)==TC_OK);
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
    puts("PASS: 8 adders, 64 loops, 1024 wide arithmetic, 256 memory-width cases, bounds and zero-extension guards");
#ifdef TC_NATIVE_FIXTURE
    /* Host CPU-time comparison; no device or commercial workload claims. */
    uint64_t total=0;clock_t begin=clock();
    for(unsigned i=0;i<200000;i++) {
        TCRegisters r={0};r.x[1]=64;
        uint8_t m[4]={0};
        assert(tc_interpret(loop,LENGTH(loop),&r,m,sizeof(m),512)==TC_OK);
        total+=m[0];
    }
    clock_t middle=clock();
    uint64_t native_total=0;
    for(unsigned i=0;i<200000;i++) {
        uint32_t n=0;tc_loop(&n,64);native_total+=n;
    }
    clock_t finish=clock();
    assert(total==native_total && total==UINT64_C(12800000));
    printf("Synthetic benchmark: interpreted %.6f s; native %.6f s; iterations=12800000\\n",
           (double)(middle-begin)/CLOCKS_PER_SEC,(double)(finish-middle)/CLOCKS_PER_SEC);
#endif
    return 0;
}
