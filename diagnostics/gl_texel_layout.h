#ifndef TC_GL_TEXEL_LAYOUT_H
#define TC_GL_TEXEL_LAYOUT_H
#include <stddef.h>
#include <stdint.h>
#include <limits.h>
typedef struct {
    size_t width,height,fullRows,tail,bytes;
} TCTexelLayout;
/* Linear texel storage mapped to an ordinary 2D texture. The final padded
 * row is not addressable by the source renderer's valid index range. */
static inline int tcTexelLayout(size_t count,size_t bytesPerTexel,size_t maxSide,size_t widthLimit,TCTexelLayout *out) {
    if(!out||!count||count>INT_MAX||!bytesPerTexel||!maxSide||maxSide>INT_MAX||
       !widthLimit||count>SIZE_MAX/bytesPerTexel)return 0;
    size_t w=widthLimit<maxSide?widthLimit:maxSide;
    if(w>count)w=count;
    size_t rows=count/w,tail=count%w,h=rows+(tail!=0);
    if(h>maxSide)return 0;
    *out=(TCTexelLayout){w,h,rows,tail,count*bytesPerTexel};
    return 1;
}
#endif
