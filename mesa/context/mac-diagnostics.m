// Compiled against real macOS Cocoa/OpenGL, then retargeted to iOS.
#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <dlfcn.h>
#import <string.h>
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
        glViewport(0,0,w,h);glDrawBuffer(GL_FRONT);glReadBuffer(GL_FRONT);
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
void TCMacDiagnostics(NSView *view){
    NSMutableString *r=[NSMutableString stringWithString:@"Mac ARM64 + Mesa desktop GL"];
    NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFAOpenGLProfile,NSOpenGLProfileVersion3_2Core,0};
    NSOpenGLPixelFormat *fmt=[[NSOpenGLPixelFormat alloc]initWithAttributes:attrs];
    NSOpenGLContext *ctx=fmt?[[NSOpenGLContext alloc]initWithFormat:fmt shareContext:nil]:nil;
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
        BOOL lookup=b&&CFBundleGetFunctionPointerForName(b,CFSTR("glTexBuffer"))&&CFBundleGetFunctionPointerForName(b,CFSTR("glDrawElementsBaseVertex"))&&CFBundleGetFunctionPointerForName(b,CFSTR("glShaderSource"));
        if(b)CFRelease(b);
        [r appendFormat:@"\nDesktop GL bundle lookup: %@",lookup?@"PASS":@"FAIL"];
        void (*size)(id,int *,int *)=dlsym(RTLD_DEFAULT,"TCMesaDrawableSize");
        BOOL (*present)(id)=dlsym(RTLD_DEFAULT,"TCMesaPresentResult");
        BOOL (*center)(id,unsigned char *)=dlsym(RTLD_DEFAULT,"TCMesaCenterBGRA");
        int w=0,h=0;if(size)size(ctx,&w,&h);
        BOOL a=NO,b410=NO,shown=NO,pixels=NO;
        if(version&&w>0&&h>0){
            a=desktopDraw(@"150",w,h);b410=desktopDraw(@"410",w,h);
            if(!b410&&a)desktopDraw(@"150",w,h);
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
