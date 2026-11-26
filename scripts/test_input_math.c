#include <assert.h>
#include <stdio.h>
#include "../diagnostics/input_math.h"
int main(void){
    assert(tcPointerGain(0,1,0)==1);
    assert(tcPointerGain(1000,1,0)==1);
    assert(tcPointerGain(500,1,1)==1.5);
    assert(tcPointerGain(10000,1,2)==3);
    assert(tcPointerGain(1000,99,99)==9);
    assert(tcPointerGain(NAN,1,1)==1);
    assert(tcPointerAxis(10,5,2,100)==20);
    assert(tcPointerAxis(10,-20,2,100)==0);
    assert(tcPointerAxis(90,20,2,100)==100);
    assert(tcPointerAxis(10,NAN,2,100)==10);
    assert(tcPointerAxis(10,5,2,0)==0);
    puts("11 pointer math tests passed");
    TCKeyState keys={0};
    assert(tcKeyDown(&keys,0,44)==44);
    assert(tcKeyDown(&keys,0,4)==0);
    assert(tcKeyDown(&keys,1,44)==0);
    assert(tcKeyUp(&keys,0)==0);
    assert(tcKeyUp(&keys,1)==44);
    assert(tcKeyUp(&keys,1)==0);
    assert(tcKeyDown(&keys,-1,44)==0);
    assert(tcKeyDown(&keys,3,44)==0);
    assert(tcKeyDown(&keys,0,224)==0);
    assert(tcKeyDown(&keys,0,79)==79);
    assert(tcKeyDown(&keys,2,4)==4);
    assert(tcKeyUp(&keys,0)==79);
    assert(tcKeyUp(&keys,2)==4);
    assert(!keys.held[0]&&!keys.held[1]&&!keys.held[2]);
    puts("14 key hold, duplicate mapping, invalid usage and release tests passed");
    assert(tcLayoutCenter(0,10,100,20)==20);
    assert(tcLayoutCenter(1,10,100,20)==100);
    assert(tcLayoutCenter(0.5,10,100,20)==60);
    assert(tcLayoutCenter(-2,10,100,20)==20);
    assert(tcLayoutCenter(4,10,100,20)==100);
    assert(tcLayoutCenter(NAN,10,100,20)==60);
    assert(tcLayoutCenter(0,10,10,20)==15);
    assert(tcLayoutFraction(20,10,100,20)==0);
    assert(tcLayoutFraction(100,10,100,20)==1);
    assert(tcLayoutFraction(60,10,100,20)==0.5);
    assert(tcLayoutFraction(-30,10,100,20)==0);
    assert(tcLayoutFraction(999,10,100,20)==1);
    assert(tcLayoutFraction(NAN,10,100,20)==0.5);
    assert(tcLayoutFraction(20,10,10,20)==0.5);
    puts("14 normalized layout and safe-area boundary tests passed");
    return 0;
}
