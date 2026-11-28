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
/* NZCV in the low nibble: N=8, Z=4, C=2, V=1. */
static void flags(TCRegisters *r,uint64_t a,uint64_t b,uint64_t v,unsigned wide,int sub) {
    uint64_t sign=UINT64_C(1)<<(wide?63:31);
    if(!wide){a=(uint32_t)a;b=(uint32_t)b;v=(uint32_t)v;}
    unsigned carry=sub ? a>=b : v<a;
    unsigned overflow=sub ? !!((a^b)&(a^v)&sign) : !!(~(a^b)&(a^v)&sign);
    r->nzcv=(uint8_t)((v&sign?8:0)|(v==0?4:0)|(carry?2:0)|overflow);
}
static int condition(uint8_t f,unsigned cond) {
    int n=!!(f&8),z=!!(f&4),c=!!(f&2),v=!!(f&1),yes;
    switch(cond>>1) {
        case 0:yes=z;break;
        case 1:yes=c;break;
        case 2:yes=n;break;
        case 3:yes=v;break;
        case 4:yes=c&&!z;break;
        case 5:yes=n==v;break;
        case 6:yes=!z&&n==v;break;
        default:return 0;
    }
    return yes^(cond&1);
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
        } else if((op&0x1f800000)==0x11000000) {
            unsigned set=(op>>29)&1u,sub=(op>>30)&1u;
            if(n==31||(!set&&d==31)) return TC_UNSUPPORTED; /* no SP; flag-setting Rd=31 is ZR */
            uint64_t imm=(op>>10)&4095;
            if(op&(1u<<22)) imm<<=12;
            uint64_t a=get(r,n,wide),v=sub?a-imm:a+imm;
            if(set) flags(r,a,imm,v,wide,sub);
            put(r,d,v,wide);
        } else if((op&0x1f800000)==0x12800000) {
            unsigned type=(op>>29)&3u,shift=((op>>21)&3u)*16u;
            if(type==1||(!wide&&shift>=32)) return TC_UNSUPPORTED;
            uint64_t imm=(uint64_t)((op>>5)&65535u)<<shift;
            uint64_t value=type==0?~imm:type==2?imm:
                (get(r,d,wide)&~(UINT64_C(65535)<<shift))|imm;
            put(r,d,value,wide);
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
        } else if((op&0xff000010)==0x54000000) {
            unsigned cond=op&15;
            if(cond>=14) return TC_UNSUPPORTED;
            if(condition(r->nzcv,cond)) next=pc+displacement((op>>5)&0x7ffff,19);
        } else if((op&0xfc000000)==0x14000000) {
            next=pc+displacement(op&0x03ffffff,26);
        } else {
            return TC_UNSUPPORTED;
        }
        pc=next;
    }
    return TC_BUDGET;
}
