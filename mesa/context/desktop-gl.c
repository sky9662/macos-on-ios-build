// Independent OSMesa default-buffer adaptation. No GLES translation.
#include "pixel-format.h"
#include <stddef.h>
#include <stdlib.h>
typedef unsigned GLenum;
typedef int GLint;
typedef int GLsizei;
extern void (*OSMesaGetProcAddress(const char *))(void);
static GLenum selectBuffer(GLenum selection,GLenum binding){
    void (*get)(GLenum,GLint *)=(void (*)(GLenum,GLint *))OSMesaGetProcAddress("glGetIntegerv");
    if(!get)abort();
    GLint fbo=0;get(binding,&fbo);
    return tcMesaDrawableSelection(selection,(unsigned)fbo);
}
void glDrawBuffer(GLenum mode){
    void (*fn)(GLenum)=(void (*)(GLenum))OSMesaGetProcAddress("glDrawBuffer");
    if(!fn||fn==glDrawBuffer)abort();
    fn(selectBuffer(mode,0x8ca6));
}
void glReadBuffer(GLenum mode){
    void (*fn)(GLenum)=(void (*)(GLenum))OSMesaGetProcAddress("glReadBuffer");
    if(!fn||fn==glReadBuffer)abort();
    fn(selectBuffer(mode,0x8caa));
}
void glDrawBuffers(GLsizei n,const GLenum *modes){
    void (*fn)(GLsizei,const GLenum *)=(void (*)(GLsizei,const GLenum *))OSMesaGetProcAddress("glDrawBuffers");
    if(!fn||fn==glDrawBuffers)abort();
    if(n==1&&modes){
        GLenum mode=selectBuffer(modes[0],0x8ca6);
        fn(n,&mode);
    }else fn(n,modes);
}
