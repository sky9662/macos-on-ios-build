#include <assert.h>
#include <stdio.h>
#include "../jit/Allocator/region_state.h"
int main(void) {
    unsigned char store[16]={9,9,9,9}, input[4]={1,2,3,4};
    TCRegionState r={0};
    assert(!tcRegionBegin(&r,store,16,17));
    assert(!tcRegionBegin(&r,store,16,0));
    assert(!tcRegionBegin(&r,NULL,16,4));
    assert(!tcRegionAppend(&r,input,4));
    assert(tcRegionBegin(&r,store,16,4));
    assert(r.phase==TC_REGION_STAGING && store[0]==0 && store[3]==0);
    assert(!tcRegionBegin(&r,store,16,4));
    assert(!tcRegionComplete(&r));
    assert(!tcRegionAppend(&r,input,5));
    assert(tcRegionAppend(&r,input,2));
    assert(r.written==2 && store[0]==1 && store[1]==2);
    assert(!tcRegionComplete(&r));
    assert(!tcRegionAppend(&r,input,3));
    assert(tcRegionAppend(&r,input+2,2));
    assert(!tcRegionAppend(&r,input,1));
    assert(tcRegionComplete(&r));
    assert(r.phase==TC_REGION_READY && !memcmp(store,input,4));
    assert(!tcRegionAppend(&r,input,1));
    assert(!tcRegionComplete(&r));
    tcRegionRetire(&r);
    assert(r.phase==TC_REGION_RETIRED && !r.staging && !r.size);
    assert(store[0]==0 && store[1]==0 && store[2]==0 && store[3]==0);
    assert(!tcRegionBegin(&r,store,16,4));
    tcRegionRetire(&r);
    assert(r.phase==TC_REGION_RETIRED);
    puts("23 region ownership and staging tests passed (ordinary memory only)");
    return 0;
}
