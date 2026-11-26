// Compiled against real macOS Cocoa/OpenGL, then retargeted to iOS.
#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <dlfcn.h>
#import <string.h>
_Static_assert(NSOpenGLPFAAccelerated==73 && NSOpenGLPFAClosestPolicy==74 && NSOpenGLPFADoubleBuffer==5 && NSOpenGLPFAColorSize==8 && NSOpenGLPFAAlphaSize==11 && NSOpenGLPFADepthSize==12 && NSOpenGLPFAStencilSize==13 && NSOpenGLPFASampleBuffers==55 && NSOpenGLPFAOpenGLProfile==99 && NSOpenGLProfileVersion3_2Core==0x3200 && NSOpenGLProfileVersion4_1Core==0x4100,"NSGL attribute ABI mismatch");
static NSOpenGLContext *visibleContext;
static GLuint shader(GLenum kind,NSString *source){
    GLuint s=glCreateShader(kind);if(!s)return 0;
    const GLchar *p=source.UTF8String;glShaderSource(s,1,&p,NULL);glCompileShader(s);
    GLint ok=0;glGetShaderiv(s,GL_COMPILE_STATUS,&ok);
    if(!ok){char log[1024]={0};glGetShaderInfoLog(s,sizeof(log),NULL,log);NSLog(@"TC shader: %s",log);glDeleteShader(s);return 0;}
    return s;
}
static BOOL desktopDraw(NSString *version,int w,int h){
    GLuint vs=shader(GL_VERTEX_SHADER,[NSString stringWithFormat:@"#version %@\nin vec2 pos;void main(){gl_Position=vec4(pos,0,1);}",version]);
    GLuint fs=shader(GL_FRAGMENT_SHADER,[NSString stringWithFormat:@"#version %@\nuniform samplerBuffer data;out vec4 color;void main(){color=texelFetch(data,1);}",version]);
    GLuint program=0,vao=0,vbo=0,ebo=0,buffer=0,tex=0;
    BOOL ok=vs&&fs;
    if(ok){
        program=glCreateProgram();glAttachShader(program,vs);glAttachShader(program,fs);
        glBindAttribLocation(program,0,"pos");glLinkProgram(program);
        GLint linked=0;glGetProgramiv(program,GL_LINK_STATUS,&linked);ok=linked!=0;
    }
    if(ok){
        glViewport(0,0,w,h);glDrawBuffer(GL_BACK);glReadBuffer(GL_BACK);
        glClearColor(0,0,0,1);glClear(GL_COLOR_BUFFER_BIT);
        const GLfloat verts[]={2,2,2,2,2,2,-1,-1,3,-1,-1,3};
        const GLushort indices[]={99,0,1,2};
        const GLfloat data[]={0,1,0,1,1,0,0,1};
        glGenVertexArrays(1,&vao);glBindVertexArray(vao);
        glGenBuffers(1,&vbo);glBindBuffer(GL_ARRAY_BUFFER,vbo);glBufferData(GL_ARRAY_BUFFER,sizeof(verts),verts,GL_STATIC_DRAW);
        glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,NULL);glEnableVertexAttribArray(0);
        glGenBuffers(1,&ebo);glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,ebo);glBufferData(GL_ELEMENT_ARRAY_BUFFER,sizeof(indices),indices,GL_STATIC_DRAW);
        glGenBuffers(1,&buffer);glBindBuffer(GL_TEXTURE_BUFFER,buffer);glBufferData(GL_TEXTURE_BUFFER,sizeof(data),data,GL_DYNAMIC_DRAW);
        glGenTextures(1,&tex);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_BUFFER,tex);glTexBuffer(GL_TEXTURE_BUFFER,GL_RGBA32F,buffer);
        glUseProgram(program);glUniform1i(glGetUniformLocation(program,"data"),0);
        glPolygonMode(GL_FRONT_AND_BACK,GL_LINE);GLint mode[2]={0};glGetIntegerv(GL_POLYGON_MODE,mode);
        glPolygonMode(GL_FRONT_AND_BACK,GL_FILL);
        glDrawElementsBaseVertex(GL_TRIANGLES,3,GL_UNSIGNED_SHORT,(const void *)sizeof(GLushort),3);
        unsigned char px[4]={0};glReadPixels(w/2,h/2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
        ok=glGetError()==GL_NO_ERROR&&mode[0]==GL_LINE&&mode[1]==GL_LINE&&px[0]>240&&px[1]<10&&px[2]<10&&px[3]>240;
        const GLfloat blue[]={0,0.25f,1,1};
        glBufferSubData(GL_TEXTURE_BUFFER,4*sizeof(GLfloat),sizeof(blue),blue);
        glDrawElementsBaseVertex(GL_TRIANGLES,3,GL_UNSIGNED_SHORT,(const void *)sizeof(GLushort),3);
        glReadPixels(w/2,h/2,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
        ok=ok&&glGetError()==GL_NO_ERROR&&px[0]<10&&px[1]>=60&&px[1]<=68&&px[2]>240&&px[3]>240;
        glFinish();
    }
    glUseProgram(0);glBindVertexArray(0);
    if(tex)glDeleteTextures(1,&tex);if(buffer)glDeleteBuffers(1,&buffer);
    if(ebo)glDeleteBuffers(1,&ebo);if(vbo)glDeleteBuffers(1,&vbo);if(vao)glDeleteVertexArrays(1,&vao);
    if(program)glDeleteProgram(program);if(vs)glDeleteShader(vs);if(fs)glDeleteShader(fs);
    return glGetError()==GL_NO_ERROR&&ok;
}
// Actual shared buffer contents and context restoration, not just handles.
static BOOL testContextLifecycle(NSOpenGLContext *primary,NSOpenGLPixelFormat *fmt,void (*size)(id,int *,int *)){
    if(!size||[NSOpenGLContext currentContext]!=primary)return NO;
    GLuint buffer=0;glGenBuffers(1,&buffer);glBindBuffer(GL_ARRAY_BUFFER,buffer);
    const GLuint initial[]={11,22,33,44};glBufferData(GL_ARRAY_BUFFER,sizeof(initial),initial,GL_STATIC_DRAW);
    BOOL ok=buffer&&glGetError()==GL_NO_ERROR;
    NSOpenGLContext *other=[[NSOpenGLContext alloc]initWithFormat:fmt shareContext:primary];
    NSView *first=[[NSView alloc]initWithFrame:NSMakeRect(0,0,24,20)];
    NSView *second=[[NSView alloc]initWithFrame:NSMakeRect(0,0,31,19)];
    [first setWantsBestResolutionOpenGLSurface:NO];[second setWantsBestResolutionOpenGLSurface:NO];
    if(other){
        [other setView:first];
        ok=ok&&[NSOpenGLContext currentContext]==primary;
        [other makeCurrentContext];
        int w=0,h=0;size(other,&w,&h);
        BOOL current=[NSOpenGLContext currentContext]==other;
        ok=ok&&current&&w==24&&h==20;
        if(current){
            GLuint actual[4]={0};
            glBindBuffer(GL_ARRAY_BUFFER,buffer);
            glGetBufferSubData(GL_ARRAY_BUFFER,0,sizeof(actual),actual);
            ok=ok&&glGetError()==GL_NO_ERROR&&!memcmp(actual,initial,sizeof(actual));
            [primary update];
            ok=ok&&[NSOpenGLContext currentContext]==other;
            [other setView:second];size(other,&w,&h);
            ok=ok&&[NSOpenGLContext currentContext]==other&&w==31&&h==19;
            glViewport(0,0,w,h);glDrawBuffer(GL_BACK);glReadBuffer(GL_BACK);
            glClearColor(0,1,0,1);glClear(GL_COLOR_BUFFER_BIT);
            unsigned char px[4]={0};glReadPixels(w-1,h-1,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
            ok=ok&&glGetError()==GL_NO_ERROR&&px[0]<10&&px[1]>240&&px[2]<10&&px[3]>240;
            glBindBuffer(GL_ARRAY_BUFFER,0);
        }
        [NSOpenGLContext clearCurrentContext];
        ok=ok&&[NSOpenGLContext currentContext]==nil;
        [primary makeCurrentContext];
        ok=ok&&[NSOpenGLContext currentContext]==primary;
        [other clearDrawable];
        ok=ok&&[NSOpenGLContext currentContext]==primary;
    }else ok=NO;
    [primary makeCurrentContext];
    if([NSOpenGLContext currentContext]!=primary)return NO;
    glBindBuffer(GL_ARRAY_BUFFER,0);
    if(buffer)glDeleteBuffers(1,&buffer);
    return glGetError()==GL_NO_ERROR&&ok;
}
void TCMacDiagnostics(NSView *view){
    NSMutableString *r=[NSMutableString stringWithString:@"Mac ARM64 + Mesa desktop GL"];
    NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFAAccelerated,NSOpenGLPFAClosestPolicy,
        NSOpenGLPFAOpenGLProfile,NSOpenGLProfileVersion3_2Core,NSOpenGLPFAColorSize,24,
        NSOpenGLPFAAlphaSize,8,NSOpenGLPFADepthSize,24,NSOpenGLPFAStencilSize,8,
        NSOpenGLPFADoubleBuffer,NSOpenGLPFASampleBuffers,0,0};
    NSOpenGLPixelFormat *fmt=[[NSOpenGLPixelFormat alloc]initWithAttributes:attrs];
    // Match the real GLFW initialization order: look up the already
    // registered framework by identifier before context construction.
    CFBundleRef registered=CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    NSURL *expected=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"OpenGLShim.framework"];
    NSURL *actual=registered?CFBridgingRelease(CFBundleCopyBundleURL(registered)):nil;
    BOOL registration=registered&&actual&&[[actual.path stringByStandardizingPath] isEqualToString:[expected.path stringByStandardizingPath]]&&
        CFBundleGetFunctionPointerForName(registered,CFSTR("glTexBuffer"));
    [r appendFormat:@"\nGLFW identifier lookup: %@",registration?@"PASS":@"FAIL"];
    [r appendFormat:@"\nPixel format: %@",fmt?@"PASS":@"FAIL"];
    NSOpenGLContext *ctx=fmt?[[NSOpenGLContext alloc]initWithFormat:fmt shareContext:nil]:nil;
    const char *(*initReport)(void)=dlsym(RTLD_DEFAULT,"TCMesaInitReport");
    if(initReport&&initReport())[r appendFormat:@"%s",initReport()];
    if(!ctx&&fmt){
        attrs[3]=NSOpenGLProfileVersion4_1Core;
        NSOpenGLPixelFormat *alternate=[[NSOpenGLPixelFormat alloc]initWithAttributes:attrs];
        NSOpenGLContext *trial=alternate?[[NSOpenGLContext alloc]initWithFormat:alternate shareContext:nil]:nil;
        if(initReport&&initReport())[r appendFormat:@"%s",initReport()];
        [r appendFormat:@"\n4.1 alternative: %@",trial?@"PASS":@"FAIL"];
    }
    if(ctx){
        [ctx setView:view];[ctx makeCurrentContext];
        const GLubyte *renderer=glGetString(GL_RENDERER),*version=glGetString(GL_VERSION);
        const GLubyte *glsl=glGetString(GL_SHADING_LANGUAGE_VERSION);
        NSString *renderName=renderer?[NSString stringWithUTF8String:(const char *)renderer]:@"unavailable";
        BOOL zink=[renderName rangeOfString:@"zink" options:NSCaseInsensitiveSearch].location!=NSNotFound;
        [r appendFormat:@"\nRenderer: %@\nZink: %@\nGL: %s\nGLSL: %s",renderName,zink?@"PASS":@"FAIL",version?(const char *)version:"unavailable",glsl?(const char *)glsl:"unavailable"];
        NSString *path=[[NSBundle.mainBundle privateFrameworksPath]stringByAppendingPathComponent:@"OpenGLShim.framework"];
        NSURL *url=[NSURL fileURLWithPath:path isDirectory:YES];
        CFBundleRef b=CFBundleCreate(kCFAllocatorDefault,(__bridge CFURLRef)url);
        void (*dynamicDraw)(GLenum)=b?(void (*)(GLenum))CFBundleGetFunctionPointerForName(b,CFSTR("glDrawBuffer")):NULL;
        BOOL lookup=b&&CFBundleGetFunctionPointerForName(b,CFSTR("glTexBuffer"))&&CFBundleGetFunctionPointerForName(b,CFSTR("glDrawElementsBaseVertex"))&&CFBundleGetFunctionPointerForName(b,CFSTR("glShaderSource"))&&dynamicDraw;
        BOOL back=NO;
        if(dynamicDraw&&version){
            dynamicDraw(GL_BACK);glReadBuffer(GL_BACK);
            GLint d=0,q=0;glGetIntegerv(GL_DRAW_BUFFER0,&d);glGetIntegerv(GL_READ_BUFFER,&q);
            back=glGetError()==GL_NO_ERROR&&(d==GL_FRONT||d==GL_FRONT_LEFT)&&(q==GL_FRONT||q==GL_FRONT_LEFT);
        }
        [r appendFormat:@"\nGLFW pixel format + GL_BACK: %@",back?@"PASS":@"FAIL"];
        if(b)CFRelease(b);
        [r appendFormat:@"\nDesktop GL bundle lookup: %@",lookup?@"PASS":@"FAIL"];
        void (*size)(id,int *,int *)=dlsym(RTLD_DEFAULT,"TCMesaDrawableSize");
        BOOL (*present)(id)=dlsym(RTLD_DEFAULT,"TCMesaPresentResult");
        BOOL (*center)(id,unsigned char *)=dlsym(RTLD_DEFAULT,"TCMesaCenterBGRA");
        NSUInteger (*frames)(id)=dlsym(RTLD_DEFAULT,"TCMesaSubmittedFrames");
        int w=0,h=0;if(size)size(ctx,&w,&h);
        BOOL a=NO,b410=NO,shown=NO,pixels=NO;
        if(version&&w>0&&h>0){
            BOOL lifecycle=testContextLifecycle(ctx,fmt,size);
            [r appendFormat:@"\nContext sharing, resize and restore: %@",lifecycle?@"PASS":@"FAIL"];
            [ctx makeCurrentContext];
            a=desktopDraw(@"150",w,h);b410=desktopDraw(@"410",w,h);
            // Seven different frames exercise all three slots twice,
            // including reuse after an earlier Metal reader.
            NSUInteger before=frames?frames(ctx):0;
            BOOL ringOK=frames&&center&&present;
            for(unsigned i=0;i<7;i++){
                float red=(i&1)?1:0,blue=(i&1)?0:1;
                glDrawBuffer(GL_BACK);glClearColor(red,0.25f,blue,1);glClear(GL_COLOR_BUFFER_BIT);
                [ctx flushBuffer];
                unsigned char bgra[4]={0};
                BOOL match=center&&center(ctx,bgra)&&
                    bgra[0]==(i&1?0:255)&&bgra[1]>=60&&bgra[1]<=68&&
                    bgra[2]==(i&1?255:0)&&bgra[3]==255;
                ringOK=ringOK&&match&&glGetError()==GL_NO_ERROR;
            }
            ringOK=ringOK&&frames&&frames(ctx)==before+7&&present&&present(ctx);
            [r appendFormat:@"\nIOSurface ring / 7 frames: %@",ringOK?@"PASS":@"FAIL"];
            if(!b410&&a)desktopDraw(@"150",w,h);
            else if(b410)desktopDraw(@"410",w,h);
            [ctx flushBuffer];shown=present&&present(ctx);
            unsigned char bgra[4]={0};pixels=center&&center(ctx,bgra)&&bgra[0]>240&&bgra[1]>=60&&bgra[1]<=68&&bgra[2]<10&&bgra[3]>240;
        }
        [r appendFormat:@"\nGLSL 150 + samplerBuffer + base vertex + update: %@\nGLSL 410 same draw: %@\nOSMesa BGRA readback: %@\nMetal present: %@",a?@"PASS":@"FAIL",b410?@"PASS":@"FAIL",pixels?@"PASS":@"FAIL",shown?@"PASS":@"FAIL"];
        if(shown)visibleContext=ctx;
        [NSOpenGLContext clearCurrentContext];
    }else [r appendString:@"\nOSMesa context creation: FAIL"];
    void (*report)(const char *)=dlsym(RTLD_DEFAULT,"TCProbeReport");
    if(report)report(r.UTF8String);else NSLog(@"%@",r);
}
