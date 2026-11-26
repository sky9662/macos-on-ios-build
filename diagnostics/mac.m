#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <dlfcn.h>
#import <string.h>
static GLuint tcShader(GLenum type, NSString *text) {
    GLuint s=glCreateShader(type); const GLchar *src=text.UTF8String;
    glShaderSource(s,1,&src,NULL); glCompileShader(s);
    GLint ok=0;glGetShaderiv(s,GL_COMPILE_STATUS,&ok);
    if(!ok){char log[1024]={0};glGetShaderInfoLog(s,sizeof(log),NULL,log);NSLog(@"TC shader fail: %s",log);glDeleteShader(s);return 0;}
    return s;
}
static BOOL tcDraw(NSString *version, BOOL indexed) {
    BOOL pass=NO; GLuint vs=0,fs=0,prog=0,fbo=0,tex=0,vao=0,vbo=0,ebo=0;
    vs=tcShader(GL_VERTEX_SHADER,[NSString stringWithFormat:@"#version %@\nin vec2 pos; void main(){gl_Position=vec4(pos,0,1);}",version]);
    fs=tcShader(GL_FRAGMENT_SHADER,[NSString stringWithFormat:@"#version %@\nout vec4 color; void main(){color=vec4(1.0,0.0,0.0,1.0);}",version]);
    if(vs&&fs){
        prog=glCreateProgram();glAttachShader(prog,vs);glAttachShader(prog,fs);glBindAttribLocation(prog,0,"pos");glLinkProgram(prog);
        GLint linked=0;glGetProgramiv(prog,GL_LINK_STATUS,&linked);
        if(linked){
            glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);
            glGenTextures(1,&tex);glBindTexture(GL_TEXTURE_2D,tex);
            glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,16,16,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
            glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
            if(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE){
                const GLfloat verts[]={2,2,2,2,2,2,-1,-1,3,-1,-1,3};
                glGenVertexArrays(1,&vao);glBindVertexArray(vao);glGenBuffers(1,&vbo);
                glBindBuffer(GL_ARRAY_BUFFER,vbo);glBufferData(GL_ARRAY_BUFFER,sizeof(verts),verts,GL_STATIC_DRAW);
                glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,NULL);glEnableVertexAttribArray(0);
                glViewport(0,0,16,16);glClearColor(0,0,0,1);glClear(GL_COLOR_BUFFER_BIT);
                glUseProgram(prog);
                BOOL restored=YES;
                if(indexed){
                    const GLushort indices[]={99,0,1,2};
                    glGenBuffers(1,&ebo);glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,ebo);
                    glBufferData(GL_ELEMENT_ARRAY_BUFFER,sizeof(indices),indices,GL_STATIC_DRAW);
                    glDrawElementsBaseVertex(GL_TRIANGLES,3,GL_UNSIGNED_SHORT,(const void *)sizeof(GLushort),3);
                    GLint actual=0;glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING,&actual);
                    restored=actual==(GLint)ebo;
                }else glDrawArrays(GL_TRIANGLES,3,3);
                unsigned char px[4]={0};glReadPixels(8,8,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
                GLenum e=glGetError();pass=(restored&&e==GL_NO_ERROR&&px[0]>240&&px[1]<10&&px[2]<10&&px[3]>240);
                NSLog(@"TC GLSL %@: RGBA %u %u %u %u error %u",version,px[0],px[1],px[2],px[3],e);
            }
        }
    }
    if(ebo)glDeleteBuffers(1,&ebo);if(vbo)glDeleteBuffers(1,&vbo);if(vao)glDeleteVertexArrays(1,&vao);
    if(tex)glDeleteTextures(1,&tex);if(fbo)glDeleteFramebuffers(1,&fbo);
    if(prog)glDeleteProgram(prog);if(vs)glDeleteShader(vs);if(fs)glDeleteShader(fs);
    return pass;
}
// Verify real driver-backed writes, reads and updates through desktop API.
static BOOL tcTestMappedBuffer(void) {
    GLuint buffer=0;glGenBuffers(1,&buffer);
    if(!buffer)return NO;
    glBindBuffer(GL_ARRAY_BUFFER,buffer);
    const unsigned char initial[8]={1,2,3,4,5,6,7,8};
    unsigned char expected[8];memcpy(expected,initial,sizeof(expected));
    glBufferData(GL_ARRAY_BUFFER,sizeof(initial),NULL,GL_DYNAMIC_DRAW);
    BOOL ok=YES;
    void *p=glMapBuffer(GL_ARRAY_BUFFER,GL_WRITE_ONLY);
    if(p){memcpy(p,initial,sizeof(initial));if(!glUnmapBuffer(GL_ARRAY_BUFFER))ok=NO;}
    else ok=NO;
    if(ok){
        p=glMapBuffer(GL_ARRAY_BUFFER,GL_READ_WRITE);
        if(p){
            if(memcmp(p,initial,sizeof(initial)))ok=NO;
            else {((unsigned char *)p)[3]=99;expected[3]=99;}
            if(!glUnmapBuffer(GL_ARRAY_BUFFER))ok=NO;
        }else ok=NO;
    }
    if(ok){
        p=glMapBuffer(GL_ARRAY_BUFFER,GL_READ_ONLY);
        if(p){if(memcmp(p,expected,sizeof(expected)))ok=NO;if(!glUnmapBuffer(GL_ARRAY_BUFFER))ok=NO;}
        else ok=NO;
    }
    glBindBuffer(GL_ARRAY_BUFFER,0);glDeleteBuffers(1,&buffer);
    return glGetError()==GL_NO_ERROR&&ok;
}
// Verify ImGui's fill save/set/restore and explicit unsupported-mode error.
static BOOL tcTestPolygonFill(void) {
    GLint saved[2]={0,0},actual[2]={0,0};
    glGetIntegerv(GL_POLYGON_MODE,saved);
    glPolygonMode(GL_FRONT_AND_BACK,GL_FILL);
    glGetIntegerv(GL_POLYGON_MODE,actual);
    BOOL ok=glGetError()==GL_NO_ERROR&&saved[0]==GL_FILL&&saved[1]==GL_FILL&&actual[0]==GL_FILL&&actual[1]==GL_FILL;
    glPolygonMode(GL_FRONT_AND_BACK,GL_LINE);
    ok=(glGetError()==GL_INVALID_OPERATION)&&ok;
    glGetIntegerv(GL_POLYGON_MODE,actual);
    glPolygonMode(GL_FRONT_AND_BACK,(GLenum)saved[0]);
    return glGetError()==GL_NO_ERROR&&actual[0]==GL_FILL&&actual[1]==GL_FILL&&ok;
}
// Real color blit, separate read/draw bindings, 8x8 to 4x4 texture copy.
static BOOL tcTestBlit(void) {
    GLint oldRead=0,oldDraw=0,oldTexture=0,viewport[4]={0};
    GLfloat clear[4]={0};
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&oldRead);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&oldDraw);
    glGetIntegerv(GL_TEXTURE_BINDING_2D,&oldTexture);
    glGetIntegerv(GL_VIEWPORT,viewport);
    glGetFloatv(GL_COLOR_CLEAR_VALUE,clear);
    GLuint fbo[2]={0},tex[2]={0};
    glGenFramebuffers(2,fbo);glGenTextures(2,tex);
    BOOL ok=fbo[0]&&fbo[1]&&tex[0]&&tex[1];
    for(int i=0;i<2&&ok;i++){
        GLsizei side=i?4:8;
        glBindFramebuffer(GL_FRAMEBUFFER,fbo[i]);glBindTexture(GL_TEXTURE_2D,tex[i]);
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,side,side,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
        glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex[i],0);
        glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);
        ok=glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
        glViewport(0,0,side,side);
        glClearColor(i?0:1,0,i?1:0,1);glClear(GL_COLOR_BUFFER_BIT);
    }
    if(ok){
        glBindFramebuffer(GL_READ_FRAMEBUFFER,fbo[0]);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER,fbo[1]);
        GLint r=0,d=0;
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&r);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&d);
        glBlitFramebuffer(0,0,8,8,0,0,4,4,GL_COLOR_BUFFER_BIT,GL_NEAREST);
        glBindFramebuffer(GL_READ_FRAMEBUFFER,fbo[1]);glReadBuffer(GL_COLOR_ATTACHMENT0);
        unsigned char px[4]={0};glReadPixels(2,2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
        ok=r==(GLint)fbo[0]&&d==(GLint)fbo[1]&&px[0]>240&&px[1]<10&&px[2]<10&&px[3]>240;
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER,(GLuint)oldRead);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER,(GLuint)oldDraw);
    glBindTexture(GL_TEXTURE_2D,(GLuint)oldTexture);
    glViewport(viewport[0],viewport[1],viewport[2],viewport[3]);
    glClearColor(clear[0],clear[1],clear[2],clear[3]);
    glDeleteFramebuffers(2,fbo);glDeleteTextures(2,tex);
    return glGetError()==GL_NO_ERROR&&ok;
}
static BOOL tcTextureBufferAdvertised(void) {
    GLint n=0;glGetIntegerv(GL_NUM_EXTENSIONS,&n);
    for(GLint i=0;i<n;i++){
        const char *name=(const char *)glGetStringi(GL_EXTENSIONS,(GLuint)i);
        if(name&&(!strcmp(name,"GL_EXT_texture_buffer")||!strcmp(name,"GL_OES_texture_buffer")))return YES;
    }
    return NO;
}
// Verify the real GLES3 fallback with two rows, a partial tail, and an
// updated texel. Uses an explicitly adapted shader, not arbitrary game GLSL.
static BOOL tcTestLinearTexture(void) {
    typedef int (*UploadFn)(GLuint,GLuint,GLenum,size_t,size_t);
    NSString *path=[[NSBundle.mainBundle privateFrameworksPath] stringByAppendingPathComponent:@"OpenGLShim.framework/OpenGLShim"];
    void *lib=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
    UploadFn upload=lib?(UploadFn)dlsym(lib,"TCUploadLinearTexture2D"):NULL;
    if(!upload){if(lib)dlclose(lib);return NO;}
    GLint oldRead=0,oldDraw=0,oldTexture=0,oldPBO=0,oldVAO=0,oldVBO=0,oldProgram=0,oldActive=0,oldRow=0,viewport[4]={0};
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&oldRead);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&oldDraw);
    glGetIntegerv(GL_ACTIVE_TEXTURE,&oldActive);glActiveTexture(GL_TEXTURE0);
    glGetIntegerv(GL_TEXTURE_BINDING_2D,&oldTexture);
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&oldPBO);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH,&oldRow);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&oldVAO);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING,&oldVBO);
    glGetIntegerv(GL_CURRENT_PROGRAM,&oldProgram);
    glGetIntegerv(GL_VIEWPORT,viewport);
    GLuint data=0,tex[2]={0},fbo=0,vao=0,vbo=0,prog=0;
    GLuint vs=tcShader(GL_VERTEX_SHADER,@"#version 150\nin vec2 pos; void main(){gl_Position=vec4(pos,0,1);}");
    GLuint fs=tcShader(GL_FRAGMENT_SHADER,@"#version 150\nuniform sampler2D linearData; uniform int idx; out vec4 color; void main(){int w=textureSize(linearData,0).x; color=texelFetch(linearData,ivec2(idx%w,idx/w),0);}");
    BOOL ok=vs&&fs;
    if(ok){
        prog=glCreateProgram();glAttachShader(prog,vs);glAttachShader(prog,fs);
        glBindAttribLocation(prog,0,"pos");glLinkProgram(prog);
        GLint linked=0;glGetProgramiv(prog,GL_LINK_STATUS,&linked);ok=linked!=0;
    }
    if(ok){
        const unsigned char values[]={255,0,0,255,0,255,0,255,0,0,255,255};
        glGenTextures(2,tex);glGenBuffers(1,&data);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,data);
        glBufferData(GL_PIXEL_UNPACK_BUFFER,sizeof(values),values,GL_DYNAMIC_DRAW);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
        glBindTexture(GL_TEXTURE_2D,tex[1]);
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,4,4,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
        glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex[1],0);
        glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);
        ok=glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,data);
        glPixelStorei(GL_UNPACK_ROW_LENGTH,7);
        ok=ok&&upload(tex[0],data,GL_RGBA8,3,2);
        GLint current=0,row=0,unpack=0;
        glGetIntegerv(GL_TEXTURE_BINDING_2D,&current);glGetIntegerv(GL_UNPACK_ROW_LENGTH,&row);
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&unpack);
        ok=ok&&current==(GLint)tex[1]&&row==7&&unpack==(GLint)data;
        glPixelStorei(GL_UNPACK_ROW_LENGTH,0);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
        glBindTexture(GL_TEXTURE_2D,tex[0]);glUseProgram(prog);
        glUniform1i(glGetUniformLocation(prog,"linearData"),0);
        GLint location=glGetUniformLocation(prog,"idx");
        const GLfloat verts[]={-1,-1,3,-1,-1,3};
        glGenVertexArrays(1,&vao);glBindVertexArray(vao);glGenBuffers(1,&vbo);
        glBindBuffer(GL_ARRAY_BUFFER,vbo);glBufferData(GL_ARRAY_BUFFER,sizeof(verts),verts,GL_STATIC_DRAW);
        glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,NULL);glEnableVertexAttribArray(0);
        glViewport(0,0,4,4);
        for(int i=0;i<3&&ok;i++){
            glUniform1i(location,i);glDrawArrays(GL_TRIANGLES,0,3);
            unsigned char px[4]={0};glReadPixels(2,2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
            ok=glGetError()==GL_NO_ERROR&&memcmp(px,values+4*i,4)==0;
        }
        const unsigned char updated[]={255,255,0,255};
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,data);
        glBufferSubData(GL_PIXEL_UNPACK_BUFFER,8,4,updated);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
        ok=ok&&upload(tex[0],data,GL_RGBA8,3,2);
        if(ok){
            glUniform1i(location,2);glDrawArrays(GL_TRIANGLES,0,3);
            unsigned char px[4]={0};glReadPixels(2,2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
            ok=glGetError()==GL_NO_ERROR&&memcmp(px,updated,4)==0;
        }
        // Verify the same path with actual floating-point texture storage.
        const GLfloat floatValues[]={0,1,1,1};
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,data);
        glBufferData(GL_PIXEL_UNPACK_BUFFER,sizeof(floatValues),floatValues,GL_DYNAMIC_DRAW);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
        ok=ok&&upload(tex[0],data,GL_RGBA32F,1,1);
        if(ok){
            glUniform1i(location,0);glDrawArrays(GL_TRIANGLES,0,3);
            unsigned char px[4]={0};glReadPixels(2,2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
            ok=glGetError()==GL_NO_ERROR&&px[0]==0&&px[1]==255&&px[2]==255&&px[3]==255;
        }
    }
    glUseProgram((GLuint)oldProgram);glBindVertexArray((GLuint)oldVAO);
    glBindBuffer(GL_ARRAY_BUFFER,(GLuint)oldVBO);glBindBuffer(GL_PIXEL_UNPACK_BUFFER,(GLuint)oldPBO);
    glPixelStorei(GL_UNPACK_ROW_LENGTH,oldRow);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,(GLuint)oldRead);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,(GLuint)oldDraw);
    glBindTexture(GL_TEXTURE_2D,(GLuint)oldTexture);glActiveTexture((GLenum)oldActive);
    glViewport(viewport[0],viewport[1],viewport[2],viewport[3]);
    if(data)glDeleteBuffers(1,&data);if(vbo)glDeleteBuffers(1,&vbo);if(vao)glDeleteVertexArrays(1,&vao);
    if(fbo)glDeleteFramebuffers(1,&fbo);glDeleteTextures(2,tex);
    if(prog)glDeleteProgram(prog);if(vs)glDeleteShader(vs);if(fs)glDeleteShader(fs);
    dlclose(lib);
    return glGetError()==GL_NO_ERROR&&ok;
}
// Retain drawable for visual verification after dismissing the report.
static NSOpenGLContext *tcVisibleContext;
static void tcTestDrawable(NSView *view,NSOpenGLContext *ctx,NSMutableString *r) {
    typedef void (*SizeFn)(id,GLint *,GLint *);
    typedef BOOL (*PresentFn)(id);
    SizeFn size=(SizeFn)dlsym(RTLD_DEFAULT,"TCProbeDrawableSize");
    PresentFn present=(PresentFn)dlsym(RTLD_DEFAULT,"TCProbePresentResult");
    if(!size||!present){[r appendString:@"\nWindow drawable: FAIL (symbols)"];return;}
    [ctx setView:view];[ctx makeCurrentContext];[ctx update];
    GLint w=0,h=0;size(ctx,&w,&h);
    glBindFramebuffer(GL_FRAMEBUFFER,0);
    GLint bound=-1;glGetIntegerv(GL_FRAMEBUFFER_BINDING,&bound);
    BOOL complete=w>0&&h>0&&glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
    [r appendFormat:@"\nDefault FBO: %@ (%d x %d)",complete&&bound==0?@"PASS":@"FAIL",w,h];
    if(!complete)return;
    glDrawBuffer(GL_BACK);glReadBuffer(GL_BACK);
    GLint drawBuffer=-1,readBuffer=-1;
    glGetIntegerv(GL_DRAW_BUFFER0,&drawBuffer);glGetIntegerv(GL_READ_BUFFER,&readBuffer);
    GLenum selectionError=glGetError();
    [r appendFormat:@"\nDrawable BACK selection: %@",selectionError==GL_NO_ERROR&&drawBuffer==GL_BACK&&readBuffer==GL_BACK?@"PASS":@"FAIL"];
    glViewport(0,0,w,h);glClearColor(0.05,0.35,0.85,1);glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
    unsigned char px[4]={0};glReadPixels(w/2,h/2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
    BOOL read=glGetError()==GL_NO_ERROR&&px[2]>190&&px[0]<30;
    [r appendFormat:@"\nWindow pixel: %@",read?@"PASS":@"FAIL"];
    GLuint fbo=0;glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);
    GLint custom=0;glGetIntegerv(GL_FRAMEBUFFER_BINDING,&custom);
    GLuint texture=0;glGenTextures(1,&texture);glBindTexture(GL_TEXTURE_2D,texture);
    glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,8,8,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,texture,0);
    GLenum attachment=GL_COLOR_ATTACHMENT0;
    glDrawBuffers(1,&attachment);glReadBuffer(attachment);
    GLint customDraw=-1,customRead=-1;
    glGetIntegerv(GL_DRAW_BUFFER0,&customDraw);glGetIntegerv(GL_READ_BUFFER,&customRead);
    BOOL customOK=glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE&&customDraw==GL_COLOR_ATTACHMENT0&&customRead==GL_COLOR_ATTACHMENT0;
    glViewport(0,0,8,8);glClearColor(0,1,0,1);glClear(GL_COLOR_BUFFER_BIT);
    unsigned char green[4]={0};glReadPixels(4,4,1,1,GL_RGBA,GL_UNSIGNED_BYTE,green);
    customOK=customOK&&glGetError()==GL_NO_ERROR&&green[1]>240&&green[0]<10&&green[2]<10;
    [r appendFormat:@"\nCustom FBO buffer selection: %@",customOK?@"PASS":@"FAIL"];
    glBindFramebuffer(GL_FRAMEBUFFER,0);GLint restored=-1;glGetIntegerv(GL_FRAMEBUFFER_BINDING,&restored);
    glDrawBuffer(GL_BACK);glReadBuffer(GL_BACK);
    glDeleteTextures(1,&texture);glDeleteFramebuffers(1,&fbo);
    [r appendFormat:@"\nFBO switching: %@",custom==(GLint)fbo&&restored==0?@"PASS":@"FAIL"];
    [ctx flushBuffer];BOOL ok=present(ctx);
    [r appendFormat:@"\nWindow present: %@",ok?@"PASS":@"FAIL"];
    if(ok)tcVisibleContext=ctx;
}
void TCMacDiagnostics(NSView *view) {
    NSMutableString *r=[NSMutableString stringWithString:@"Mac ARM64 + touch: PASS (tap received)"];
    NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFAOpenGLProfile,NSOpenGLProfileVersion3_2Core,0};
    NSOpenGLPixelFormat *fmt=[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    NSOpenGLContext *ctx=fmt?[[NSOpenGLContext alloc] initWithFormat:fmt shareContext:nil]:nil;
    if(ctx){[ctx makeCurrentContext];const GLubyte *v=glGetString(GL_VERSION);
        // Resolve through the embedded library, not a static link alone.
        NSString *path=[[NSBundle.mainBundle privateFrameworksPath] stringByAppendingPathComponent:@"OpenGLShim.framework/OpenGLShim"];
        void *lib=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        const GLubyte *(*getString)(GLenum)=lib?dlsym(lib,"glGetString"):NULL;
        void *source=lib?dlsym(lib,"glShaderSource"):NULL;
        [r appendFormat:@"\nDynamic GL lookup: %@",getString&&source&&getString(GL_VERSION)?@"PASS":@"FAIL"];
        if(lib)dlclose(lib);
        if(v){[r appendFormat:@"\nGL context: %s",v];[r appendFormat:@"\nGLSL 150 draw/read: %@",tcDraw(@"150",NO)?@"PASS":@"FAIL"];[r appendFormat:@"\nGLSL 410 draw/read: %@",tcDraw(@"410",NO)?@"PASS":@"FAIL"];}
        else [r appendString:@"\nGL context: FAIL"];
        if(v){
            [r appendFormat:@"\nDesktop buffer mapping: %@",tcTestMappedBuffer()?@"PASS":@"FAIL"];
            [r appendFormat:@"\nBase-vertex indexed draw/read: %@",tcDraw(@"150",YES)?@"PASS":@"FAIL"];
            [r appendFormat:@"\nImGui polygon fill mode: %@",tcTestPolygonFill()?@"PASS":@"FAIL"];
            [r appendFormat:@"\nTexture clone framebuffer blit: %@",tcTestBlit()?@"PASS":@"FAIL"];
            [r appendFormat:@"\nTexture-buffer extension advertised: %@",tcTextureBufferAdvertised()?@"YES":@"NO"];
            [r appendFormat:@"\nGLES3 linear texture upload/fetch/update: %@",tcTestLinearTexture()?@"PASS":@"FAIL"];
            tcTestDrawable(view,ctx,r);
        }
        [NSOpenGLContext clearCurrentContext];
    }else [r appendString:@"\nGL context: FAIL"];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tc-probe-%@.txt",NSUUID.UUID.UUIDString]];
    NSError *err=nil;
    BOOL write=[@"TC roundtrip" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    BOOL read=write&&[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err] isEqualToString:@"TC roundtrip"];
    if(write)[NSFileManager.defaultManager removeItemAtPath:path error:nil];
    [r appendFormat:@"\nFile roundtrip: %@",read?@"PASS":@"FAIL"];
    void (*report)(const char *)=dlsym(RTLD_DEFAULT,"TCProbeReport");
    if(report)report(r.UTF8String);else NSLog(@"%@",r);
}
