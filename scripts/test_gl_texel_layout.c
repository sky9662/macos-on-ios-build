#include <assert.h>
#include <stdio.h>
#include "../diagnostics/gl_texel_layout.h"
int main(void) {
    TCTexelLayout l={0};
    assert(tcTexelLayout(3,4,16,2,&l)&&l.width==2&&l.height==2&&l.fullRows==1&&l.tail==1&&l.bytes==12);
    assert(tcTexelLayout(8,16,4,4,&l)&&l.width==4&&l.height==2&&l.fullRows==2&&!l.tail&&l.bytes==128);
    assert(tcTexelLayout(1,4,8,8,&l)&&l.width==1&&l.height==1&&l.bytes==4);
    assert(tcTexelLayout(16,4,4,9,&l)&&l.width==4&&l.height==4);
    assert(!tcTexelLayout(17,4,4,4,&l));
    assert(!tcTexelLayout(0,4,4,4,&l));
    assert(!tcTexelLayout(1,0,4,4,&l));
    assert(!tcTexelLayout(1,4,0,4,&l));
    assert(!tcTexelLayout(1,4,4,0,&l));
    assert(!tcTexelLayout(1,4,4,4,NULL));
    assert(!tcTexelLayout((size_t)INT_MAX+1,1,16,16,&l));
    assert(!tcTexelLayout(2,SIZE_MAX,16,16,&l));
    puts("12 linear texture layout tests passed");
    return 0;
}
