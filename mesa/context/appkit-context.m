// Independent desktop GL context adapter for the Mac-compiled diagnostic.
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CATransaction.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include "TCMesaPixelFormat.h"
typedef void *TCOSContext;
extern TCOSContext OSMesaCreateContextAttribs(const int *,TCOSContext);
extern unsigned char OSMesaMakeCurrent(TCOSContext,void *,unsigned,int,int);
extern TCOSContext OSMesaGetCurrentContext(void);
extern void OSMesaDestroyContext(TCOSContext);
extern void OSMesaPixelStore(int,int);
extern void (*OSMesaGetProcAddress(const char *))(void);
enum { TC_BGRA=1, TC_FORMAT=0x22, TC_DEPTH=0x30, TC_STENCIL=0x31,
       TC_PROFILE=0x33, TC_CORE=0x34, TC_MAJOR=0x36, TC_MINOR=0x37,
       TC_ROW_LENGTH=0x10, TC_Y_UP=0x11, TC_UNSIGNED_BYTE=0x1401 };
// GLFW locates desktop OpenGL by CFBundle identifier before creating a
// context. Register only our embedded, already linked framework. Keep the
// reference alive; do not interpose CoreFoundation lookup globally.
static CFBundleRef tcMesaGLBundle;
static void TCRegisterMesaGLBundle(void) {
    if(tcMesaGLBundle)return;
    CFURLRef base=CFBundleCopyPrivateFrameworksURL(CFBundleGetMainBundle());
    if(!base)return;
    CFURLRef url=CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault,base,CFSTR("OpenGLShim.framework"),true);
    CFRelease(base);
    if(!url)return;
    CFBundleRef candidate=CFBundleCreate(kCFAllocatorDefault,url);
    CFRelease(url);
    if(!candidate)return;
    CFStringRef identifier=CFBundleGetIdentifier(candidate);
    if(!identifier||!CFEqual(identifier,CFSTR("com.apple.opengl"))||!CFBundleLoadExecutable(candidate)){
        CFRelease(candidate);return;
    }
    tcMesaGLBundle=candidate;
    CFBundleRef registered=CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    if(registered!=candidate)NSLog(@"TC Mesa: GLFW identifier registration not confirmed");
    else NSLog(@"TC Mesa: embedded OpenGL bundle registered");
}
static char tcMesaHiDPIKey;
@interface NSView (TCMesaResolution)
- (void)setWantsBestResolutionOpenGLSurface:(BOOL)enabled;
- (BOOL)wantsBestResolutionOpenGLSurface;
@end
@implementation NSView (TCMesaResolution)
- (void)setWantsBestResolutionOpenGLSurface:(BOOL)enabled {
    objc_setAssociatedObject(self,&tcMesaHiDPIKey,@(enabled),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)wantsBestResolutionOpenGLSurface {
    NSNumber *value=objc_getAssociatedObject(self,&tcMesaHiDPIKey);
    return value?value.boolValue:YES;
}
@end
@interface NSOpenGLPixelFormat : NSObject
@property(nonatomic) int major,minor,depth,stencil,wantsDouble;
- (instancetype)initWithAttributes:(const uint32_t *)attrs;
@end
@implementation NSOpenGLPixelFormat
- (instancetype)initWithAttributes:(const uint32_t *)attrs {
    if(!(self=[super init])||!attrs)return nil;
    TCPixelFormat p;
    if(!tcParsePixelFormat(attrs,64,&p))return nil;
    _major=p.major;_minor=p.minor;_depth=p.depth;_stencil=p.stencil;_wantsDouble=p.wantsDouble;
    return self;
}
@end
@interface NSOpenGLContext : NSObject
@property(nonatomic) TCOSContext mesa;
@property(nonatomic) void *pixels;
@property(nonatomic) int width,height,swapInterval;
@property(nonatomic,weak) NSView *tcView;
@property(nonatomic,strong) CAMetalLayer *layer;
@property(nonatomic,strong) id<MTLDevice> device;
@property(nonatomic,strong) id<MTLCommandQueue> queue;
@property(nonatomic,strong) id<MTLTexture> uploadTexture;
@property(nonatomic) BOOL lastPresent;
- (instancetype)initWithFormat:(NSOpenGLPixelFormat *)format shareContext:(NSOpenGLContext *)share;
- (void)update;
- (void)clearDrawable;
- (BOOL)bindWidth:(int)w height:(int)h;
@end
// Context ownership is main-thread-only in this adapter. Derive current
// object from Mesa's actual current context, not a guessed global selection.
static NSMapTable<NSValue *,NSOpenGLContext *> *tcMesaContexts;
static NSValue *tcContextKey(TCOSContext ctx){return [NSValue valueWithPointer:ctx];}
@implementation NSOpenGLContext
+ (NSOpenGLContext *)currentContext {
    if(![NSThread isMainThread])return nil;
    TCOSContext ctx=OSMesaGetCurrentContext();
    return ctx?[tcMesaContexts objectForKey:tcContextKey(ctx)]:nil;
}
- (instancetype)initWithFormat:(NSOpenGLPixelFormat *)format shareContext:(NSOpenGLContext *)share {
    if(!(self=[super init])||!format||![NSThread isMainThread])return nil;
    // Set the real backend before creating the first OSMesa context.
    NSString *vk=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"MoltenVK.framework/MoltenVK"];
    if(![[NSFileManager defaultManager] isReadableFileAtPath:vk])return nil;
    setenv("GALLIUM_DRIVER","zink",1);
    setenv("ZINK_VULKAN_LIBRARY",vk.fileSystemRepresentation,1);
    setenv("MVK_CONFIG_LOG_LEVEL","1",0);
    const int attrs[]={TC_FORMAT,TC_BGRA,TC_DEPTH,format.depth,TC_STENCIL,format.stencil,
      TC_PROFILE,TC_CORE,TC_MAJOR,format.major,TC_MINOR,format.minor,0};
    _mesa=OSMesaCreateContextAttribs(attrs,share?share.mesa:NULL);
    if(!_mesa)return nil;
    _device=MTLCreateSystemDefaultDevice();
    _queue=[_device newCommandQueue];
    if(!_queue)return nil;
    if(!tcMesaContexts)tcMesaContexts=[NSMapTable strongToWeakObjectsMapTable];
    [tcMesaContexts setObject:self forKey:tcContextKey(_mesa)];
    return self;
}
- (BOOL)bindWidth:(int)w height:(int)h {
    if(![NSThread isMainThread]||!_mesa||w<1||h<1||w>8192||h>8192||
       (uint64_t)w*(uint64_t)h*4>128*1024*1024)return NO;
    if(_pixels&&w==_width&&h==_height)
        return OSMesaGetCurrentContext()==_mesa||
            (OSMesaMakeCurrent(_mesa,_pixels,TC_UNSIGNED_BYTE,w,h)&&OSMesaGetCurrentContext()==_mesa);
    // Allocate before disturbing the live drawable. On an allocation
    // failure the old context and its backing memory remain intact.
    void *next=calloc((size_t)w*(size_t)h,4);
    if(!next)return NO;
    if(OSMesaGetCurrentContext()==_mesa) {
        void (*finish)(void)=OSMesaGetProcAddress("glFinish");
        if(!finish){free(next);return NO;}
        finish();
    }
    if(!OSMesaMakeCurrent(_mesa,next,TC_UNSIGNED_BYTE,w,h)){
        free(next);
        return NO;
    }
    // Once Mesa accepted the pointer, preserve it until a later successful
    // rebind or destruction, even if current-context verification fails.
    free(_pixels);_pixels=next;_width=w;_height=h;_uploadTexture=nil;
    if(OSMesaGetCurrentContext()!=_mesa)return NO;
    OSMesaPixelStore(TC_ROW_LENGTH,0);OSMesaPixelStore(TC_Y_UP,0);
    return YES;
}
- (void)setView:(NSView *)view {
    if(![NSThread isMainThread])return;
    if(_tcView==view&&_layer)return;
    if(!view){[self clearDrawable];return;}
    // Replacing the surface must not unbind another context or discard
    // the previous buffer before a successful resize.
    [_layer removeFromSuperlayer];_layer=nil;_lastPresent=NO;
    _tcView=view;_layer=[CAMetalLayer layer];_layer.device=_device;
    _layer.pixelFormat=MTLPixelFormatBGRA8Unorm;_layer.framebufferOnly=NO;_layer.opaque=YES;
    [view.hostView.layer addSublayer:_layer];
    [self update];
}
- (NSView *)view {return _tcView;}
- (void)update {
    if(!_layer||!_tcView||![NSThread isMainThread])return;
    UIView *host=_tcView.hostView;
    CGFloat scale=_tcView.wantsBestResolutionOpenGLSurface?host.traitCollection.displayScale:1;
    if(scale<=0)scale=1;
    double w=ceil(host.bounds.size.width*scale),h=ceil(host.bounds.size.height*scale);
    if(!isfinite(w)||!isfinite(h)||w<1||h<1||w>8192||h>8192)return;
    TCOSContext rawPrior=OSMesaGetCurrentContext();
    NSOpenGLContext *prior=[NSOpenGLContext currentContext];
    if(rawPrior&&!prior)return; // do not steal an unmanaged Mesa context
    if(!_pixels||_width!=(int)w||_height!=(int)h){
        BOOL resized=[self bindWidth:(int)w height:(int)h];
        BOOL restored=YES;
        if(prior!=self){
            if(prior)restored=[prior bindWidth:prior.width height:prior.height];
            else restored=OSMesaMakeCurrent(NULL,NULL,0,0,0)!=0;
        }
        if(!resized||!restored){NSLog(@"TC Mesa resize/restore failed");return;}
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _layer.frame=host.bounds;_layer.contentsScale=scale;_layer.drawableSize=CGSizeMake(w,h);
    [CATransaction commit];
}
- (void)makeCurrentContext {
    if(![NSThread isMainThread])return;
    if(_layer)[self update];
    if(![self bindWidth:_width?_width:16 height:_height?_height:16])
        NSLog(@"TC Mesa makeCurrentContext failed");
}
+ (void)clearCurrentContext {
    if([NSThread isMainThread])OSMesaMakeCurrent(NULL,NULL,0,0,0);
}
- (void)clearDrawable {
    if(OSMesaGetCurrentContext()==_mesa&&_mesa){
        void (*finish)(void)=OSMesaGetProcAddress("glFinish");
        if(finish)finish();
        OSMesaMakeCurrent(NULL,NULL,0,0,0);
    }
    [_layer removeFromSuperlayer];_layer=nil;_tcView=nil;_uploadTexture=nil;_lastPresent=NO;
    // Keep the current client buffer alive until rebind or destruction.
}
- (void)dealloc {
    [self clearDrawable];
    if(_mesa){[tcMesaContexts removeObjectForKey:tcContextKey(_mesa)];OSMesaDestroyContext(_mesa);}
    free(_pixels);
}
- (void)flushBuffer {
    _lastPresent=NO;
    if(!_layer||!_pixels||OSMesaGetCurrentContext()!=_mesa||![NSThread isMainThread])return;
    void (*finish)(void)=OSMesaGetProcAddress("glFinish");
    unsigned (*getError)(void)=(unsigned (*)(void))OSMesaGetProcAddress("glGetError");
    if(!finish||!getError)return;
    finish();if(getError()!=0)return;
    id<CAMetalDrawable> target=[_layer nextDrawable];
    if(!target||target.texture.width!=(NSUInteger)_width||target.texture.height!=(NSUInteger)_height)return;
    if(!_uploadTexture){
        MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:(NSUInteger)_width height:(NSUInteger)_height mipmapped:NO];
        desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead;
        _uploadTexture=[_device newTextureWithDescriptor:desc];
    }
    if(!_uploadTexture)return;
    [_uploadTexture replaceRegion:MTLRegionMake2D(0,0,_width,_height) mipmapLevel:0 withBytes:_pixels bytesPerRow:(NSUInteger)_width*4];
    id<MTLCommandBuffer> command=[_queue commandBuffer];
    id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    if(!blit)return;
    [blit copyFromTexture:_uploadTexture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(_width,_height,1) toTexture:target.texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding];[command presentDrawable:target];[command commit];
    // Synchronous for the diagnostic only; no claim of frame-rate optimization.
    [command waitUntilCompleted];_lastPresent=command.status==MTLCommandBufferStatusCompleted;
    if(!_lastPresent)NSLog(@"TC Mesa Metal presentation failed: %@",command.error);
}
- (void)setValues:(const int *)values forParameter:(NSInteger)param {
    if(param==222&&values)_swapInterval=*values;
}
- (void)getValues:(int *)values forParameter:(NSInteger)param {
    if(param==222&&values)*values=_swapInterval;
}
@end
__attribute__((visibility("default"))) BOOL TCMesaPresentResult(NSOpenGLContext *ctx){return ctx.lastPresent;}
__attribute__((visibility("default"))) void TCMesaDrawableSize(NSOpenGLContext *ctx,int *w,int *h){*w=ctx.width;*h=ctx.height;}
__attribute__((visibility("default"))) BOOL TCMesaCenterBGRA(NSOpenGLContext *ctx,unsigned char *out){
    if(!ctx.pixels||ctx.width<1||ctx.height<1||!out)return NO;
    memcpy(out,(const unsigned char *)ctx.pixels+((size_t)(ctx.height/2)*ctx.width+ctx.width/2)*4,4);return YES;
}
__attribute__((visibility("default"))) void TCProbeReport(const char *message){
    NSString *report=[NSString stringWithUTF8String:message]?:@"Invalid report";
    dispatch_async(dispatch_get_main_queue(),^{
        NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [report writeToURL:[dir URLByAppendingPathComponent:@"TC-mesa-diagnostics.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"TC Mesa diagnostics: %@",report);
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Desktop OpenGL / Mesa" message:report preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [gRootVC presentViewController:alert animated:YES completion:nil];
    });
}
