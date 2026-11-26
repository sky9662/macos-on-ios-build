#include <assert.h>
#include <stdio.h>
#include "../diagnostics/gl_index.h"
int main(void) {
    uint32_t out[4]={0};
    uint8_t a[]={0,1,255};
    uint16_t b[]={1,65535,3};
    uint32_t c[]={0,UINT32_MAX,3};
    assert(tcIndexWidth(0x1401)==1);
    assert(tcIndexWidth(0x1403)==2);
    assert(tcIndexWidth(0x1405)==4);
    assert(tcIndexWidth(0)==0);
    assert(tcRebaseIndices(a,0x1401,3,5,0,out)&&out[0]==5&&out[2]==260);
    assert(tcRebaseIndices(b,0x1403,3,2,1,out)&&out[0]==3&&out[1]==UINT32_MAX&&out[2]==5);
    assert(tcRebaseIndices(c,0x1405,3,0,1,out)&&out[1]==UINT32_MAX);
    assert(tcRebaseIndices(b,0x1403,1,-1,0,out)&&out[0]==0);
    assert(!tcRebaseIndices(a,0x1401,1,-1,0,out));
    assert(!tcRebaseIndices(c+1,0x1405,1,1,0,out));
    uint32_t edge=UINT32_MAX-1;
    assert(!tcRebaseIndices(&edge,0x1405,1,1,1,out));
    assert(tcRebaseIndices(&edge,0x1405,1,1,0,out)&&out[0]==UINT32_MAX);
    assert(!tcRebaseIndices(a,0,1,0,0,out));
    assert(!tcRebaseIndices(NULL,0x1401,1,0,0,out));
    assert(!tcRebaseIndices(a,0x1401,1,0,0,NULL));
    assert(!tcRebaseIndices(a,0x1401,SIZE_MAX,0,0,out));
    puts("16 base-vertex index tests passed");
    return 0;
}
