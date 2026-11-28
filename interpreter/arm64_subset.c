#include "arm64_subset.h"

static uint64_t get(const TCRegisters *r, unsigned n, unsigned wide) {
    uint64_t v=n==31 ? 0 : r->x[n];
    return wide ? v : (uint32_t)v;
}
static void put(TCRegisters *r, unsigned n, uint64_t v, unsigned wide) {
    if(n!=31) r->x[n]=wide ? v : (uint32_t)v;
}
static int64_t displacement(uint32_t field, unsigned bits) {
    uint32_t sign=UINT32_C(1)<<(bits-1);
    return (int64_t)field - ((field&sign) ? (INT64_C(1)<<bits) : 0);
}
TCStatus tc_interpret(const uint32_t *words,size_t count,TCRegisters *r,
                      uint8_t *mem,size_t mem_size,size_t budget) {
    if(!words||!r||(!mem&&mem_size)||!count||count>65536||!budget||budget>1000000)
        return TC_ARGUMENT;
    int64_t pc=0;
    while(budget--) {
        if(pc<0||(uint64_t)pc>=count) return TC_BOUNDS;
        uint32_t op=words[(size_t)pc];
        unsigned d=op&31,n=(op>>5)&31,m=(op>>16)&31;
        int64_t next=pc+1;
        if(op==UINT32_C(0xd65f03c0)) return TC_OK; /* synthetic return boundary */
        unsigned wide=op>>31;
        uint32_t kind=op&UINT32_C(0x7fe00000);
        if(kind==0x0a000000||kind==0x2a000000||kind==0x4a000000) {
            unsigned shift=(op>>10)&63;
            if(!wide && shift>31) return TC_UNSUPPORTED;
            uint64_t a=get(r,n,wide),b=get(r,m,wide)<<shift;
            put(r,d,kind==0x0a000000 ? a&b : kind==0x2a000000 ? a|b : a^b,wide);
        } else if((op&0x7f800000)==0x11000000||(op&0x7f800000)==0x51000000) {
            if(n==31||d==31) return TC_UNSUPPORTED; /* no SP */
            uint32_t imm=(op>>10)&4095;
            if(op&(1u<<22)) imm<<=12;
            put(r,d,(op&0x40000000)?get(r,n,wide)-imm:get(r,n,wide)+imm,wide);
        } else if((op&0x3fc00000)==0x39400000||(op&0x3fc00000)==0x39000000) {
            if(n==31) return TC_UNSUPPORTED;
            unsigned bytes=1u<<(op>>30);
            uint64_t base=get(r,n,1),delta=(uint64_t)bytes*((op>>10)&4095u);
            if(base>UINT64_MAX-delta) return TC_BOUNDS;
            uint64_t offset=base+delta;
            if(offset>mem_size||mem_size-(size_t)offset<bytes) return TC_BOUNDS;
            uint8_t *p=mem+(size_t)offset;
            if(op&(1u<<22)) {
                uint64_t value=0;
                for(unsigned i=0;i<bytes;i++) value|=(uint64_t)p[i]<<(8*i);
                put(r,d,value,bytes==8);
            } else {
                uint64_t value=get(r,d,bytes==8);
                for(unsigned i=0;i<bytes;i++) p[i]=(uint8_t)(value>>(8*i));
            }
        } else if((op&0x7f000000)==0x34000000||(op&0x7f000000)==0x35000000) {
            int nonzero=get(r,d,wide)!=0;
            if(nonzero==((op>>24)&1u ? 1:0)) next=pc+displacement((op>>5)&0x7ffff,19);
        } else if((op&0xfc000000)==0x14000000) {
            next=pc+displacement(op&0x03ffffff,26);
        } else {
            return TC_UNSUPPORTED;
        }
        pc=next;
    }
    return TC_BUDGET;
}
