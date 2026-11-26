#include <assert.h>
#include <stdio.h>
#include "../jit/Allocator/layout.h"
int main(void) {
    TCJITLayout l = {64,0};
    size_t off=999;
    assert(tcJITReserve(&l, 3, 4, &off) && off==0 && l.used==3);
    assert(tcJITReserve(&l, 8, 8, &off) && off==8 && l.used==16);
    assert(tcJITReserve(&l, 48, 4, &off) && off==16 && l.used==64);
    assert(!tcJITReserve(&l, 1, 1, &off) && l.used==64);
    assert(!tcJITReserve(&l, 0, 1, &off));
    assert(!tcJITReserve(&l, 1, 3, &off));
    assert(!tcJITReserve(&l, 1, 0, &off));
    assert(!tcJITReserve(NULL, 1, 1, &off));
    assert(!tcJITReserve(&l, 1, 1, NULL));
    TCJITLayout overflow = {SIZE_MAX,SIZE_MAX-1};
    assert(!tcJITReserve(&overflow, 1, 8, &off));
    assert(tcJITContains(64,56,8));
    assert(!tcJITContains(64,56,9));
    assert(!tcJITContains(64,65,1));
    assert(!tcJITContains(SIZE_MAX,SIZE_MAX-2,3));
    assert(!tcJITContains(64,0,0));
    puts("15 source allocator layout tests passed (no executable memory)");
    return 0;
}
