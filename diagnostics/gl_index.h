#ifndef TC_GL_INDEX_H
#define TC_GL_INDEX_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>

static inline size_t tcIndexWidth(unsigned type) {
    switch(type) {
        case 0x1401: return 1; /* UNSIGNED_BYTE */
        case 0x1403: return 2; /* UNSIGNED_SHORT */
        case 0x1405: return 4; /* UNSIGNED_INT */
        default: return 0;
    }
}
/* Convert to uint32_t, preserving fixed restart markers before applying base.
 * Negative resulting indices and sentinel collisions are rejected explicitly.
 * The caller owns disjoint input/output and supplies exact element counts. */
static inline int tcRebaseIndices(const void *input, unsigned type, size_t count,
                                  int32_t base, int restart, uint32_t *out) {
    size_t width=tcIndexWidth(type);
    if(!width || !input || !out || count>SIZE_MAX/width || count>SIZE_MAX/sizeof(*out))return 0;
    const unsigned char *src=input;
    const uint32_t marker=width==1?UINT8_MAX:width==2?UINT16_MAX:UINT32_MAX;
    for(size_t i=0;i<count;i++) {
        uint32_t v=0;
        if(width==1)v=src[i];
        else if(width==2){uint16_t x;memcpy(&x,src+i*2,2);v=x;}
        else memcpy(&v,src+i*4,4);
        if(restart && v==marker){out[i]=UINT32_MAX;continue;}
        int64_t sum=(int64_t)v+base;
        if(sum<0 || sum>UINT32_MAX || (restart && sum==UINT32_MAX))return 0;
        out[i]=(uint32_t)sum;
    }
    return 1;
}
#endif
