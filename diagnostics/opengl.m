// Limited desktop GLSL 150/410 -> GLES 300 translator for probe-compatible shader syntax.
// Other desktop language features are NOT implemented. Unsupported shaders fail in the driver.
#import <Foundation/Foundation.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/EAGL.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdlib.h>
#include "gl_drawable.h"
#include "gl_index.h"
#include "gl_texel_layout.h"
typedef void (*ShaderSourceFn)(GLuint,GLsizei,const GLchar *const *,const GLint *);
void glShaderSource(GLuint shader,GLsizei count,const GLchar *const *strings,const GLint *lengths) {
    static ShaderSourceFn realSource;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        void *lib=dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES",RTLD_NOW|RTLD_LOCAL);
        if(lib) realSource=(ShaderSourceFn)dlsym(lib,"glShaderSource");
    });
    if(!realSource || realSource==(ShaderSourceFn)glShaderSource) { NSLog(@"TC GL: real shader source not found"); abort(); }
    if(count<=0 || !strings) {realSource(shader,count,strings,lengths);return;}
    NSMutableData *data=[NSMutableData data];
    for(GLsizei i=0;i<count;i++){
        if(!strings[i]) {realSource(shader,count,strings,lengths);return;}
        NSUInteger n=(lengths&&lengths[i]>=0)?(NSUInteger)lengths[i]:strlen(strings[i]);
        [data appendBytes:strings[i] length:n];
    }
    NSString *source=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRange first=[source rangeOfString:@"\n"];
    if(!source||first.location==NSNotFound){realSource(shader,count,strings,lengths);return;}
    NSString *header=[[source substringToIndex:first.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([@[@"#version 150",@"#version 150 core",@"#version 410",@"#version 410 core"] containsObject:header]){
        NSString *out=[@"#version 300 es\nprecision highp float;\nprecision highp int;\n" stringByAppendingString:[source substringFromIndex:NSMaxRange(first)]];
        const GLchar *s=out.UTF8String;
        realSource(shader,1,&s,NULL);
    } else realSource(shader,count,strings,lengths);
}

// Map desktop framebuffer zero to the current window drawable.
typedef GLuint (*DefaultFBOFn)(void);
static GLuint defaultFBO(void) {
    static DefaultFBOFn fn;
    if(!fn)fn=(DefaultFBOFn)dlsym(RTLD_DEFAULT,"TCDefaultFramebuffer");
    return fn?fn():0;
}
static void *tcGLSymbol(const char *name) {
    static void *lib;
    if(!lib)lib=dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES",RTLD_NOW|RTLD_LOCAL);
    void *sym=lib?dlsym(lib,name):NULL;
    if(!sym){NSLog(@"TC missing GLES symbol %s",name);abort();}
    return sym;
}
void glBindFramebuffer(GLenum target,GLuint framebuffer) {
    typedef void (*Fn)(GLenum,GLuint);
    static Fn fn;if(!fn)fn=(Fn)tcGLSymbol("glBindFramebuffer");
    if(fn==(Fn)glBindFramebuffer)abort();
    fn(target,framebuffer?framebuffer:defaultFBO());
}
typedef void (*GetIntegerFn)(GLenum,GLint *);
static GetIntegerFn tcRealGetInteger(void) {
    static GetIntegerFn fn;
    static dispatch_once_t once;
    dispatch_once(&once,^{fn=(GetIntegerFn)tcGLSymbol("glGetIntegerv");});
    if(fn==(GetIntegerFn)glGetIntegerv)abort();
    return fn;
}
static BOOL tcVirtualDefaultBound(GLenum binding) {
    GLuint f=defaultFBO();
    if(!f)return NO;
    GLint current=0;tcRealGetInteger()(binding,&current);
    return (GLuint)current==f;
}
// Preserve a shim error per EAGL context, independent of driver errors.
// Each EAGL context is used by at most one rendering thread at a time.
static char tcPolygonErrorKey;
static void tcPolygonError(GLenum error) {
    EAGLContext *ctx=[EAGLContext currentContext];
    if(ctx && !objc_getAssociatedObject(ctx,&tcPolygonErrorKey))
        objc_setAssociatedObject(ctx,&tcPolygonErrorKey,@(error),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
GLenum glGetError(void) {
    typedef GLenum (*Fn)(void);
    static Fn fn;static dispatch_once_t once;
    dispatch_once(&once,^{fn=(Fn)tcGLSymbol("glGetError");});
    if(fn==(Fn)glGetError)abort();
    GLenum driver=fn();
    if(driver!=GL_NO_ERROR)return driver;
    EAGLContext *ctx=[EAGLContext currentContext];
    NSNumber *pending=ctx?objc_getAssociatedObject(ctx,&tcPolygonErrorKey):nil;
    if(!pending)return GL_NO_ERROR;
    objc_setAssociatedObject(ctx,&tcPolygonErrorKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return (GLenum)pending.unsignedIntValue;
}
void glPolygonMode(GLenum face,GLenum mode) {
    GLenum error=(GLenum)tcGLPolygonModeError(face,mode);
    if(error){tcPolygonError(error);NSLog(@"TC GL polygon mode unsupported: face=%u mode=%u",face,mode);}
    // For GL_FILL, GLES already rasterizes triangles as filled polygons.
}
void glGetIntegerv(GLenum pname,GLint *data) {
    if(pname==0x0b40 && data && [EAGLContext currentContext]){
        // Desktop GL_POLYGON_MODE returns two values (front and back).
        data[0]=data[1]=0x1b02;return;
    }
    tcRealGetInteger()(pname,data);
    if(!data)return;
    if(pname==GL_DRAW_FRAMEBUFFER_BINDING||pname==GL_READ_FRAMEBUFFER_BINDING){
        GLuint f=defaultFBO();if(f&&(GLuint)*data==f)*data=0;
    }else if(pname==GL_DRAW_BUFFER0){
        *data=(GLint)tcGLBufferToDesktop((unsigned)*data,tcVirtualDefaultBound(GL_DRAW_FRAMEBUFFER_BINDING));
    }else if(pname==GL_READ_BUFFER){
        *data=(GLint)tcGLBufferToDesktop((unsigned)*data,tcVirtualDefaultBound(GL_READ_FRAMEBUFFER_BINDING));
    }
}
void glDrawBuffers(GLsizei n,const GLenum *bufs) {
    typedef void (*Fn)(GLsizei,const GLenum *);
    static Fn fn;static dispatch_once_t once;
    dispatch_once(&once,^{fn=(Fn)tcGLSymbol("glDrawBuffers");});
    if(fn==(Fn)glDrawBuffers)abort();
    // A single BACK selection maps to the emulated drawable color attachment.
    // Other arrays and invalid arguments go to the driver; no fake GL success.
    if(n==1&&bufs&&tcVirtualDefaultBound(GL_DRAW_FRAMEBUFFER_BINDING)){
        GLenum mapped=(GLenum)tcGLBufferToNative(bufs[0],1);
        fn(1,&mapped);
    }else fn(n,bufs);
}
// Desktop API absent from GLES. GLES glDrawBuffers supplies the equivalent
// single-target selection for supported BACK/NONE/COLOR_ATTACHMENT values.
void glDrawBuffer(GLenum buf) {glDrawBuffers(1,&buf);}
void glReadBuffer(GLenum src) {
    typedef void (*Fn)(GLenum);
    static Fn fn;static dispatch_once_t once;
    dispatch_once(&once,^{fn=(Fn)tcGLSymbol("glReadBuffer");});
    if(fn==(Fn)glReadBuffer)abort();
    fn((GLenum)tcGLBufferToNative(src,tcVirtualDefaultBound(GL_READ_FRAMEBUFFER_BINDING)));
}

// GLAD resolves this desktop function dynamically. Map the entire currently
// bound buffer using GLES3, without allocating a shadow buffer or claiming
// successful mapping if the driver refuses it. Only valid GLES buffer
// targets are supported; exact desktop error enums are not emulated.
void *glMapBuffer(GLenum target, GLenum access) {
    GLbitfield flags=(GLbitfield)tcGLMapAccess((unsigned)access);
    if(!flags)return glMapBufferRange(target,0,1,0);
    GLint64 size=0;
    glGetBufferParameteri64v(target,GL_BUFFER_SIZE,&size);
    if(size<=0)return glMapBufferRange(target,0,0,flags);
    return glMapBufferRange(target,0,(GLsizeiptr)size,flags);
}

// Desktop indexed drawing with a base vertex. Prefer a genuinely advertised
// GLES extension; otherwise use an owned temporary index buffer, not a
// vertex-pointer adjustment (which would give gl_VertexID the wrong value).
typedef void (*TCBaseVertexFn)(GLenum, GLsizei, GLenum, const void *, GLint);
static BOOL tcHasGLExtension(const char *name) {
    GLint n=0;tcRealGetInteger()(GL_NUM_EXTENSIONS,&n);
    for(GLint i=0;i<n;i++){
        const char *s=(const char *)glGetStringi(GL_EXTENSIONS,(GLuint)i);
        if(s&&!strcmp(s,name))return YES;
    }
    return NO;
}
static TCBaseVertexFn tcNativeBaseVertex(void) {
    static void *lib;static dispatch_once_t once;
    dispatch_once(&once,^{lib=dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES",RTLD_NOW|RTLD_LOCAL);});
    if(!lib)return NULL;
    TCBaseVertexFn fn=NULL;
    if(tcHasGLExtension("GL_EXT_draw_elements_base_vertex"))
        fn=(TCBaseVertexFn)dlsym(lib,"glDrawElementsBaseVertexEXT");
    if(!fn&&tcHasGLExtension("GL_OES_draw_elements_base_vertex"))
        fn=(TCBaseVertexFn)dlsym(lib,"glDrawElementsBaseVertexOES");
    return fn;
}
void glDrawElementsBaseVertex(GLenum mode,GLsizei count,GLenum type,const void *indices,GLint basevertex) {
    if(basevertex==0||count<=0){glDrawElements(mode,count,type,indices);return;}
    TCBaseVertexFn native=tcNativeBaseVertex();
    if(native){native(mode,count,type,indices,basevertex);return;}
    const size_t width=tcIndexWidth(type);
    const uintptr_t offset=(uintptr_t)indices;
    GLint binding=0;GLint64 capacity=0;
    tcRealGetInteger()(GL_ELEMENT_ARRAY_BUFFER_BINDING,&binding);
    if(!binding||!width||count>4194304){NSLog(@"TC base vertex: unsupported index source or count");return;}
    glGetBufferParameteri64v(GL_ELEMENT_ARRAY_BUFFER,GL_BUFFER_SIZE,&capacity);
    size_t bytes=(size_t)count*width;
    if(capacity<0||offset>(uint64_t)capacity||bytes>(uint64_t)capacity-offset){
        NSLog(@"TC base vertex: index range outside buffer");return;
    }
    uint32_t *rebased=malloc((size_t)count*sizeof(*rebased));
    if(!rebased){NSLog(@"TC base vertex: allocation failed");return;}
    const void *mapped=glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER,(GLintptr)offset,(GLsizeiptr)bytes,GL_MAP_READ_BIT);
    if(!mapped){free(rebased);NSLog(@"TC base vertex: source mapping failed");return;}
    int ok=tcRebaseIndices(mapped,type,(size_t)count,basevertex,glIsEnabled(GL_PRIMITIVE_RESTART_FIXED_INDEX),rebased);
    GLboolean unmapped=glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);
    if(!ok||!unmapped){free(rebased);NSLog(@"TC base vertex: invalid rebased indices or unmap failed");return;}
    GLuint temporary=0;glGenBuffers(1,&temporary);
    if(!temporary){free(rebased);NSLog(@"TC base vertex: temporary buffer creation failed");return;}
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,temporary);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER,(GLsizeiptr)((size_t)count*sizeof(*rebased)),rebased,GL_STREAM_DRAW);
    free(rebased);
    GLint64 uploaded=0;
    glGetBufferParameteri64v(GL_ELEMENT_ARRAY_BUFFER,GL_BUFFER_SIZE,&uploaded);
    if(uploaded==(GLint64)((size_t)count*sizeof(uint32_t)))
        glDrawElements(mode,count,GL_UNSIGNED_INT,NULL);
    else NSLog(@"TC base vertex: temporary index upload failed");
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,(GLuint)binding);
    glDeleteBuffers(1,&temporary);
}

// Source-level GLES3 alternative to a desktop texture buffer. This is not a
// transparent glTexBuffer shim: the caller owns the texture and uses a
// sampler2D with integer coordinates (index % width, index / width).
// Data stays in the driver's buffer storage and is uploaded via a PBO.
// Caller supplies a valid texture name and buffer name; no previous GL
// errors are allowed. Return 1 only after the real upload succeeds.
int TCUploadLinearTexture2D(GLuint texture,GLuint buffer,GLenum internalFormat,
                            size_t count,size_t widthLimit) {
    GLenum type=0;size_t texelBytes=0;
    if(internalFormat==GL_RGBA8){type=GL_UNSIGNED_BYTE;texelBytes=4;}
    else if(internalFormat==GL_RGBA32F){type=GL_FLOAT;texelBytes=16;}
    else return 0;
    if(![EAGLContext currentContext]||!texture||!buffer||!glIsBuffer(buffer))return 0;
    if(glGetError()!=GL_NO_ERROR)return 0;
    GLint maxSide=0,oldTexture=0,oldPBO=0;
    tcRealGetInteger()(GL_MAX_TEXTURE_SIZE,&maxSide);
    TCTexelLayout layout;
    if(maxSide<=0||!tcTexelLayout(count,texelBytes,(size_t)maxSide,widthLimit,&layout))return 0;
    tcRealGetInteger()(GL_TEXTURE_BINDING_2D,&oldTexture);
    tcRealGetInteger()(GL_PIXEL_UNPACK_BUFFER_BINDING,&oldPBO);
    const GLenum unpackKeys[]={GL_UNPACK_ALIGNMENT,GL_UNPACK_ROW_LENGTH,GL_UNPACK_SKIP_ROWS,
        GL_UNPACK_SKIP_PIXELS,GL_UNPACK_IMAGE_HEIGHT,GL_UNPACK_SKIP_IMAGES};
    GLint oldUnpack[6]={0};
    for(size_t i=0;i<6;i++)tcRealGetInteger()(unpackKeys[i],&oldUnpack[i]);
    int ok=0;
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,buffer);
    GLint64 bufferBytes=0;GLint mapped=0;
    glGetBufferParameteri64v(GL_PIXEL_UNPACK_BUFFER,GL_BUFFER_SIZE,&bufferBytes);
    glGetBufferParameteriv(GL_PIXEL_UNPACK_BUFFER,GL_BUFFER_MAPPED,&mapped);
    if(glGetError()!=GL_NO_ERROR||mapped||bufferBytes<0||(uint64_t)bufferBytes<layout.bytes)goto restore;
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
    for(size_t i=0;i<6;i++)glPixelStorei(unpackKeys[i],i==0?1:0);
    glBindTexture(GL_TEXTURE_2D,texture);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_BASE_LEVEL,0);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAX_LEVEL,0);
    glTexImage2D(GL_TEXTURE_2D,0,(GLint)internalFormat,(GLsizei)layout.width,
                 (GLsizei)layout.height,0,GL_RGBA,type,NULL);
    if(glGetError()!=GL_NO_ERROR)goto restore;
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,buffer);
    if(layout.fullRows)
        glTexSubImage2D(GL_TEXTURE_2D,0,0,0,(GLsizei)layout.width,
                        (GLsizei)layout.fullRows,GL_RGBA,type,(const void *)0);
    if(layout.tail) {
        uintptr_t offset=(uintptr_t)(layout.fullRows*layout.width*texelBytes);
        glTexSubImage2D(GL_TEXTURE_2D,0,0,(GLint)layout.fullRows,(GLsizei)layout.tail,
                        1,GL_RGBA,type,(const void *)offset);
    }
    ok=glGetError()==GL_NO_ERROR;
restore:
    glBindTexture(GL_TEXTURE_2D,(GLuint)oldTexture);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,(GLuint)oldPBO);
    for(size_t i=0;i<6;i++)glPixelStorei(unpackKeys[i],oldUnpack[i]);
    return glGetError()==GL_NO_ERROR&&ok;
}

// Use the real texture-buffer entry point only if the current driver
// advertises the matching extension and provides the function. On GLES3.0
// the source-level 2D path above is separate, never a fake attachment.
void glTexBuffer(GLenum target,GLenum internalformat,GLuint buffer) {
    typedef void (*Fn)(GLenum,GLenum,GLuint);
    static void *lib;static dispatch_once_t once;
    dispatch_once(&once,^{lib=dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES",RTLD_NOW|RTLD_LOCAL);});
    Fn fn=NULL;
    if(lib&&tcHasGLExtension("GL_EXT_texture_buffer"))fn=(Fn)dlsym(lib,"glTexBufferEXT");
    if(!fn&&lib&&tcHasGLExtension("GL_OES_texture_buffer"))fn=(Fn)dlsym(lib,"glTexBufferOES");
    if(fn){fn(target,internalformat,buffer);return;}
    tcPolygonError(target==0x8c2a?GL_INVALID_OPERATION:GL_INVALID_ENUM);
    NSLog(@"TC GL: native texture buffer unavailable; source-level 2D adaptation required");
}
