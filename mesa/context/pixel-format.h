#ifndef TC_MESA_PIXEL_FORMAT_H
#define TC_MESA_PIXEL_FORMAT_H
#include <stddef.h>
#include <stdint.h>
typedef struct {
    int major,minor,depth,stencil,wantsDouble;
} TCPixelFormat;
/* Bounded NSOpenGL attribute parser. The first desktop adapter supports
 * fixed RGBA8, 0/16/24/32 depth, 0/8 stencil, no MSAA or accumulation.
 * DoubleBuffer requests one logical swap surface, not two GL buffers. */
static inline int tcParsePixelFormat(const uint32_t *a,size_t limit,TCPixelFormat *out){
    if(!a||!out||!limit)return 0;
    TCPixelFormat p={3,2,24,8,0};
    for(size_t i=0;i<limit;){
        uint32_t k=a[i++];
        if(!k){*out=p;return 1;}
        switch(k){
        case 5:p.wantsDouble=1;continue;
        case 72:case 73:case 74:case 96:case 101:continue;
        case 7:case 8:case 11:case 12:case 13:case 14:case 55:case 56:case 99:break;
        default:return 0;
        }
        if(i>=limit)return 0;
        uint32_t v=a[i++];
        switch(k){
        case 7:case 14:case 55:case 56:if(v)return 0;break;
        case 8:if(v<15||v>32)return 0;break;
        case 11:if(v>8)return 0;break;
        case 12:if(v!=0&&v!=16&&v!=24&&v!=32)return 0;p.depth=(int)v;break;
        case 13:if(v!=0&&v!=8)return 0;p.stencil=(int)v;break;
        case 99:
            if(v==0x3200){p.major=3;p.minor=2;}
            else if(v==0x4100){p.major=4;p.minor=1;}
            else return 0;
            break;
        }
    }
    return 0;
}
/* OSMesa has one drawable color buffer. Never remap user FBOs. */
static inline unsigned tcMesaDrawableSelection(unsigned selection,unsigned boundFBO){
    if(boundFBO==0){
        if(selection==0x0405)return 0x0404; /* BACK -> FRONT */
        if(selection==0x0402)return 0x0400; /* BACK_LEFT -> FRONT_LEFT */
    }
    return selection;
}
#endif
