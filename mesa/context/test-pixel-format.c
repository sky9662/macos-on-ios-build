#include "pixel-format.h"
#include <assert.h>
#include <stdio.h>
int main(void){
    TCPixelFormat p;
    uint32_t common[]={73,74,99,0x4100,8,24,11,8,12,24,13,8,5,55,0,0};
    assert(tcParsePixelFormat(common,sizeof(common)/sizeof(*common),&p)&&p.major==4&&p.minor==1&&p.depth==24&&p.stencil==8&&p.wantsDouble);
    uint32_t basic[]={99,0x3200,0};assert(tcParsePixelFormat(basic,3,&p)&&p.major==3&&p.minor==2);
    uint32_t off[]={96,101,12,16,13,0,0};assert(tcParsePixelFormat(off,7,&p)&&p.depth==16&&p.stencil==0);
    uint32_t msaa[]={55,1,56,4,0};assert(!tcParsePixelFormat(msaa,5,&p));
    uint32_t legacy[]={99,0x1000,0};assert(!tcParsePixelFormat(legacy,3,&p));
    uint32_t missing[]={99};assert(!tcParsePixelFormat(missing,1,&p));
    uint32_t unknown[]={777,0};assert(!tcParsePixelFormat(unknown,2,&p));
    uint32_t baddepth[]={12,12,0};assert(!tcParsePixelFormat(baddepth,3,&p));
    uint32_t stereo[]={6,0};assert(!tcParsePixelFormat(stereo,2,&p));
    uint32_t noend[]={73,74};assert(!tcParsePixelFormat(noend,2,&p));
    assert(tcMesaDrawableSelection(0x0405,0)==0x0404);
    assert(tcMesaDrawableSelection(0x0402,0)==0x0400);
    assert(tcMesaDrawableSelection(0x0405,2)==0x0405);
    assert(tcMesaDrawableSelection(0x8ce0,2)==0x8ce0);
    assert(tcMesaDrawableSelection(0,0)==0);
    puts("15 Mesa format and drawable selection tests passed");
}
