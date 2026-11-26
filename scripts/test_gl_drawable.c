#include <assert.h>
#include <stdio.h>
#include "../diagnostics/gl_drawable.h"
int main(void) {
    assert(tcGLBufferToNative(TC_GL_BACK,1)==TC_GL_COLOR_ATTACHMENT0);
    assert(tcGLBufferToNative(TC_GL_BACK,0)==TC_GL_BACK);
    assert(tcGLBufferToDesktop(TC_GL_COLOR_ATTACHMENT0,1)==TC_GL_BACK);
    assert(tcGLBufferToDesktop(TC_GL_COLOR_ATTACHMENT0,0)==TC_GL_COLOR_ATTACHMENT0);
    assert(tcGLBufferToNative(TC_GL_NONE,1)==TC_GL_NONE);
    assert(tcGLBufferToDesktop(TC_GL_NONE,1)==TC_GL_NONE);
    assert(tcGLBufferToNative(TC_GL_COLOR_ATTACHMENT0+1,0)==TC_GL_COLOR_ATTACHMENT0+1);
    assert(tcGLBufferToDesktop(TC_GL_COLOR_ATTACHMENT0+1,1)==TC_GL_COLOR_ATTACHMENT0+1);
    assert(tcGLBufferToNative(0x0404,1)==0x0404);
    assert(tcGLBufferToDesktop(tcGLBufferToNative(TC_GL_BACK,1),1)==TC_GL_BACK);
    puts("10 virtual drawable buffer selection tests passed");
    assert(tcGLMapAccess(0x88b8)==1);
    assert(tcGLMapAccess(0x88b9)==2);
    assert(tcGLMapAccess(0x88ba)==3);
    assert(tcGLMapAccess(0)==0);
    assert(tcGLMapAccess(0x88bb)==0);
    puts("5 desktop buffer mapping access tests passed");
    assert(tcGLPolygonModeError(0x0404,0x1b02)==0);
    assert(tcGLPolygonModeError(0x0405,0x1b02)==0);
    assert(tcGLPolygonModeError(0x0408,0x1b02)==0);
    assert(tcGLPolygonModeError(0x0408,0x1b00)==0x0502);
    assert(tcGLPolygonModeError(0x0408,0x1b01)==0x0502);
    assert(tcGLPolygonModeError(0,0x1b02)==0x0500);
    assert(tcGLPolygonModeError(0x0408,0)==0x0500);
    puts("7 polygon mode classification tests passed");
    return 0;
}
