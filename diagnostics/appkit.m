// Appended to the pinned AppKit shim for the integrated diagnostic only.
// EAGL drawable and offscreen NSOpenGLContext adapter; limited GL semantics.
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <QuartzCore/CATransaction.h>
#import <dlfcn.h>
#import <errno.h>
@interface NSOpenGLPixelFormat : NSObject
- (instancetype)initWithAttributes:(const uint32_t *)attrs;
@end
@implementation NSOpenGLPixelFormat
- (instancetype)initWithAttributes:(const uint32_t *)attrs {
    return [super init]; // probe requests core profile; only ES3 backend supported
}
@end
@interface NSOpenGLContext : NSObject
@property(nonatomic,strong) EAGLContext *tcContext;
@property(nonatomic,weak) NSView *tcView;
@property(nonatomic,strong) CAEAGLLayer *drawable;
@property(nonatomic) GLuint drawableFBO, colorRB, depthRB;
@property(nonatomic) GLint width, height;
@property(nonatomic) CGSize pointSize;
@property(nonatomic) CGFloat scale;
@property(nonatomic) GLint swapInterval;
@property(nonatomic) BOOL lastPresent;
- (instancetype)initWithFormat:(NSOpenGLPixelFormat *)format shareContext:(NSOpenGLContext *)share;
- (void)update;
- (void)clearDrawable;
@end
static NSMapTable<EAGLContext *, NSOpenGLContext *> *tcContexts;
__attribute__((visibility("default"))) GLuint TCDefaultFramebuffer(void) {
    EAGLContext *current=EAGLContext.currentContext;
    return current ? [tcContexts objectForKey:current].drawableFBO : 0;
}
@implementation NSOpenGLContext
- (instancetype)initWithFormat:(NSOpenGLPixelFormat *)format shareContext:(NSOpenGLContext *)share {
    if ((self=[super init])) {
        if (!format) return nil;
        _tcContext=share ? [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3 sharegroup:share.tcContext.sharegroup] : [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        if (!_tcContext) return nil;
        if(!tcContexts)tcContexts=[NSMapTable weakToWeakObjectsMapTable];
        [tcContexts setObject:self forKey:_tcContext];
    }
    return self;
}
- (void)deleteBuffers {
    if(_drawableFBO)glDeleteFramebuffers(1,&_drawableFBO);
    if(_colorRB)glDeleteRenderbuffers(1,&_colorRB);
    if(_depthRB)glDeleteRenderbuffers(1,&_depthRB);
    _drawableFBO=_colorRB=_depthRB=0;_width=_height=0;
}
- (void)clearDrawable {
    EAGLContext *prior=EAGLContext.currentContext;
    if([EAGLContext setCurrentContext:_tcContext])[self deleteBuffers];
    [EAGLContext setCurrentContext:prior];
    [_drawable removeFromSuperlayer];_drawable=nil;_tcView=nil;
}
- (void)dealloc { [self clearDrawable]; }
- (void)setView:(NSView *)view {
    if(_tcView==view&&_drawable)return;
    [self clearDrawable];
    if(!view)return;
    _tcView=view;
    _drawable=[CAEAGLLayer layer];_drawable.opaque=YES;
    _drawable.drawableProperties=@{kEAGLDrawablePropertyRetainedBacking:@NO,kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};
    [view.hostView.layer addSublayer:_drawable];
    [self update];
}
- (NSView *)view { return _tcView; }
- (void)update {
    if(!_drawable||!_tcView)return;
    UIView *host=_tcView.hostView;
    CGSize size=host.bounds.size;
    CGFloat scale=host.traitCollection.displayScale;
    if(scale<=0)scale=1;
    if(size.width<=0||size.height<=0)return;
    if(_drawableFBO&&CGSizeEqualToSize(size,_pointSize)&&scale==_scale)return;
    EAGLContext *prior=EAGLContext.currentContext;
    if(![EAGLContext setCurrentContext:_tcContext])return;
    GLint oldDraw=0,oldRead=0,oldRB=0;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&oldDraw);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&oldRead);
    glGetIntegerv(GL_RENDERBUFFER_BINDING,&oldRB);
    GLuint previousFBO=_drawableFBO, previousColor=_colorRB, previousDepth=_depthRB;
    [self deleteBuffers];
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _drawable.frame=host.bounds;_drawable.contentsScale=scale;
    [CATransaction commit];
    glGenRenderbuffers(1,&_colorRB);glBindRenderbuffer(GL_RENDERBUFFER,_colorRB);
    BOOL storage=[_tcContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:_drawable];
    if(storage){
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_WIDTH,&_width);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_HEIGHT,&_height);
        glGenFramebuffers(1,&_drawableFBO);glBindFramebuffer(GL_FRAMEBUFFER,_drawableFBO);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,_colorRB);
        glGenRenderbuffers(1,&_depthRB);glBindRenderbuffer(GL_RENDERBUFFER,_depthRB);
        glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,_width,_height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_RENDERBUFFER,_depthRB);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_STENCIL_ATTACHMENT,GL_RENDERBUFFER,_depthRB);
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)storage=NO;
    }
    if(!storage){[self deleteBuffers];NSLog(@"TC drawable storage failed");}
    else{_pointSize=size;_scale=scale;NSLog(@"TC drawable %d x %d",_width,_height);}
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER,(oldDraw==0||(GLuint)oldDraw==previousFBO)?_drawableFBO:(GLuint)oldDraw);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,(oldRead==0||(GLuint)oldRead==previousFBO)?_drawableFBO:(GLuint)oldRead);
    glBindRenderbuffer(GL_RENDERBUFFER,((GLuint)oldRB==previousColor||(GLuint)oldRB==previousDepth)?0:(GLuint)oldRB);
    [EAGLContext setCurrentContext:prior];
}
- (void)makeCurrentContext {
    if([EAGLContext setCurrentContext:self.tcContext]){
        [self update];
        if(_drawableFBO){
            GLint f=0;glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&f);
            if(!f)glBindFramebuffer(GL_DRAW_FRAMEBUFFER,_drawableFBO);
            glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&f);
            if(!f)glBindFramebuffer(GL_READ_FRAMEBUFFER,_drawableFBO);
        }
    }
}
+ (void)clearCurrentContext { [EAGLContext setCurrentContext:nil]; }
- (void)flushBuffer {
    _lastPresent=NO;
    if(EAGLContext.currentContext!=_tcContext||!_colorRB)return;
    GLint rb=0;glGetIntegerv(GL_RENDERBUFFER_BINDING,&rb);
    glBindRenderbuffer(GL_RENDERBUFFER,_colorRB);
    _lastPresent=[_tcContext presentRenderbuffer:GL_RENDERBUFFER];
    glBindRenderbuffer(GL_RENDERBUFFER,(GLuint)rb);
    NSLog(@"TC drawable present %@",_lastPresent?@"OK":@"FAIL");
}
- (void)setValues:(const GLint *)values forParameter:(NSInteger)param {
    if(param==222&&values)_swapInterval=*values; // stored, not enforced
}
- (void)getValues:(GLint *)values forParameter:(NSInteger)param {
    if(values&&param==222)*values=_swapInterval;
}
@end
__attribute__((visibility("default"))) BOOL TCProbePresentResult(NSOpenGLContext *ctx) {return ctx.lastPresent;}
__attribute__((visibility("default"))) void TCProbeDrawableSize(NSOpenGLContext *ctx, GLint *w, GLint *h) {*w=ctx.width;*h=ctx.height;}

__attribute__((visibility("default"))) void TCProbeReport(const char *message) {
    NSString *report=[NSString stringWithUTF8String:message] ?: @"Invalid report";
    NSMutableString *result=[report mutableCopy];
    // No executable code is generated or executed; this is only a permission probe.
    errno=0;
#ifdef MAP_JIT
    void *mem=mmap(NULL, (size_t)getpagesize(), PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
    int err=errno;
    if (mem==MAP_FAILED) [result appendFormat:@"\nJIT map only: DENIED (%d)",err];
    else { munmap(mem,(size_t)getpagesize()); [result appendString:@"\nJIT map only: OK (execution untested)"]; }
#else
    [result appendString:@"\nJIT map only: unavailable"];
#endif
    // Match the game's observed allocation request, but do not write or execute code.
#ifdef MAP_JIT
    errno=0;
    void *exact=mmap(NULL,(size_t)getpagesize(),PROT_READ|PROT_WRITE|PROT_EXEC,MAP_PRIVATE|MAP_ANON|MAP_JIT,-1,0);
    int exactErr=errno;
    if(exact==MAP_FAILED) [result appendFormat:@"\nGame-style JIT map: DENIED (%d)",exactErr];
    else {munmap(exact,(size_t)getpagesize());[result appendString:@"\nGame-style JIT map: OK (execution untested)"];}
#endif
    // The engine uses GLFW's CFBundle function lookup; test the actual embedded bundle.
    NSURL *glURL=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"OpenGLShim.framework"];
    CFBundleRef glBundle=glURL?CFBundleCreate(kCFAllocatorDefault,(__bridge CFURLRef)glURL):NULL;
    if(glBundle){
        void *source=CFBundleGetFunctionPointerForName(glBundle,CFSTR("glShaderSource"));
        void *version=CFBundleGetFunctionPointerForName(glBundle,CFSTR("glGetString"));
        [result appendFormat:@"\nGL bundle lookup: %@",source&&version?@"PASS":@"FAIL"];
        CFRelease(glBundle);
    }else [result appendString:@"\nGL bundle lookup: FAIL"];
    // OpenAL dynamically queried so missing framework is an informative result, not a crash.
    void *al=dlopen("/System/Library/Frameworks/OpenAL.framework/OpenAL",RTLD_NOW|RTLD_LOCAL);
    if (al) {
        void *(*openDevice)(const char *)=dlsym(al,"alcOpenDevice");
        void *(*createContext)(void *,const int *)=dlsym(al,"alcCreateContext");
        char (*makeCurrent)(void *)=dlsym(al,"alcMakeContextCurrent");
        void (*destroyContext)(void *)=dlsym(al,"alcDestroyContext");
        char (*closeDevice)(void *)=dlsym(al,"alcCloseDevice");
        void (*genBuffers)(int,unsigned *)=dlsym(al,"alGenBuffers");
        void (*bufferData)(unsigned,int,const void *,int,int)=dlsym(al,"alBufferData");
        void (*deleteBuffers)(int,const unsigned *)=dlsym(al,"alDeleteBuffers");
        int (*getError)(void)=dlsym(al,"alGetError");
        BOOL ok=NO;
        if(openDevice&&createContext&&makeCurrent&&destroyContext&&closeDevice&&genBuffers&&bufferData&&deleteBuffers&&getError) {
            void *dev=openDevice(NULL);
            if(dev) {
                void *ctx=createContext(dev,NULL);
                if(ctx) {
                    if(makeCurrent(ctx)) {
                        unsigned buf=0; short pcm[32]={0}; genBuffers(1,&buf);
                        if(buf) { bufferData(buf,0x1101,pcm,sizeof(pcm),22050); ok=(getError()==0); deleteBuffers(1,&buf); }
                        makeCurrent(NULL);
                    }
                    destroyContext(ctx);
                }
                closeDevice(dev);
            }
        }
        [result appendString:ok?@"\nOpenAL buffer: PASS":@"\nOpenAL buffer: FAIL"];
        dlclose(al);
    } else [result appendString:@"\nOpenAL: unavailable"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [result appendFormat:@"\nScreen: %.0f x %.0f pt",gRootVC.view.bounds.size.width,gRootVC.view.bounds.size.height];
        NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSError *err=nil;
        BOOL saved=[result writeToURL:[dir URLByAppendingPathComponent:@"TC-diagnostics.txt"] atomically:YES encoding:NSUTF8StringEncoding error:&err];
        NSLog(@"TC diagnostics: %@; saved=%d %@",result,saved,err);
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"TC compatibility diagnostics" message:result preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [gRootVC presentViewController:alert animated:YES completion:nil];
    });
}
