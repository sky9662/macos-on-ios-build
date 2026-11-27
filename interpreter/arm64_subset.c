#include "arm64_subset.h"

static uint32_t get(const TCRegisters *r, unsigned n) {
    return n==31 ? 0 : r->w[n];
}
static void put(TCRegisters *r, unsigned n, uint32_t v) {
    if(n!=31) r->w[n]=v;
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
        uint32_t kind=op&UINT32_C(0xffe00000);
        if(kind==0x0a000000||kind==0x2a000000||kind==0x4a000000) {
            unsigned shift=(op>>10)&63;
            if(shift>31) return TC_UNSUPPORTED;
            uint32_t a=get(r,n),b=get(r,m)<<shift;
            put(r,d,kind==0x0a000000 ? a&b : kind==0x2a000000 ? a|b : a^b);
        } else if((op&0xff800000)==0x11000000||(op&0xff800000)==0x51000000) {
            if(n==31||d==31) return TC_UNSUPPORTED; /* no SP */
            uint32_t imm=(op>>10)&4095;
            if(op&(1u<<22)) imm<<=12;
            put(r,d,(op&0x40000000)?get(r,n)-imm:get(r,n)+imm);
        } else if((op&0xffc00000)==0xb9400000||(op&0xffc00000)==0xb9000000) {
            if(n==31) return TC_UNSUPPORTED;
            uint64_t offset=(uint64_t)get(r,n)+4u*((op>>10)&4095u);
            if(offset>mem_size||mem_size-(size_t)offset<4) return TC_BOUNDS;
            uint8_t *p=mem+(size_t)offset;
            if(op&(1u<<22)) {
                uint32_t value=(uint32_t)p[0]|((uint32_t)p[1]<<8)|
                    ((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
                put(r,d,value);
            } else {
                uint32_t value=get(r,d);
                for(unsigned i=0;i<4;i++) p[i]=(uint8_t)(value>>(8*i));
            }
        } else if((op&0xff000000)==0x34000000||(op&0xff000000)==0x35000000) {
            int nonzero=get(r,d)!=0;
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
