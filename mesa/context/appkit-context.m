// Independent desktop GL context adapter for the Mac-compiled diagnostic.
#import <Metal/Metal.h>
#import <IOSurface/IOSurfaceRef.h>
#include <limits.h>
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
// IOSurface-backed Mesa-to-Metal buffer. Independent Mac adapter using
// the public IOSurface/OSMesa APIs; see mesa/SOURCES.md for architecture source.
@interface TCMesaSurface : NSObject
@property(nonatomic) IOSurfaceRef surface;
@property(nonatomic,strong) id<MTLTexture> texture;
@property(nonatomic,strong) id<MTLCommandBuffer> reader;
@property(nonatomic) BOOL locked;
@property(nonatomic) size_t stride,allocation;
- (instancetype)initWithDevice:(id<MTLDevice>)device width:(int)w height:(int)h;
- (void *)lockForWrite;
- (BOOL)unlockForGPU;
@end
@implementation TCMesaSurface
- (instancetype)initWithDevice:(id<MTLDevice>)device width:(int)w height:(int)h {
    if(!(self=[super init]))return nil;
    NSDictionary *properties=@{
        (__bridge NSString *)kIOSurfaceWidth:@(w),
        (__bridge NSString *)kIOSurfaceHeight:@(h),
        (__bridge NSString *)kIOSurfaceBytesPerElement:@4,
        (__bridge NSString *)kIOSurfacePixelFormat:@((uint32_t)0x42475241)
    };
    _surface=IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if(!_surface)return nil;
    _stride=IOSurfaceGetBytesPerRow(_surface);_allocation=IOSurfaceGetAllocSize(_surface);
    if(_stride<(size_t)w*4||_stride%4||_stride/4>INT_MAX||
       _allocation/(size_t)h<_stride)return nil;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:(NSUInteger)w height:(NSUInteger)h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    _texture=[device newTextureWithDescriptor:d iosurface:_surface plane:0];
    if(!_texture)return nil;
    return self;
}
- (void *)lockForWrite {
    if(_reader){
        [_reader waitUntilCompleted];
        if(_reader.status!=MTLCommandBufferStatusCompleted)
            NSLog(@"TC Mesa surface reader failed: %@",_reader.error);
        _reader=nil;
    }
    if(!_locked){
        if(IOSurfaceLock(_surface,0,NULL)!=0)return NULL;
        _locked=YES;
    }
    void *base=IOSurfaceGetBaseAddress(_surface);
    if(!base)[self unlockForGPU];
    return base;
}
- (BOOL)unlockForGPU {
    if(!_locked)return YES;
    if(IOSurfaceUnlock(_surface,0,NULL)!=0)return NO;
    _locked=NO;return YES;
}
- (void)dealloc {
    if(_reader)[_reader waitUntilCompleted];
    if(_surface){
        [self unlockForGPU];
        CFRelease(_surface);
    }
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
@property(nonatomic,strong) NSArray<TCMesaSurface *> *ring;
@property(nonatomic) NSUInteger writeSlot;
@property(nonatomic,strong) id<MTLCommandBuffer> lastFrame;
@property(nonatomic,strong) NSData *lastCenter;
@property(nonatomic) NSUInteger submittedFrames;
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
    // Keep the prior ring alive until Mesa accepts the new backing pointer.
    NSMutableArray<TCMesaSurface *> *fresh=[NSMutableArray arrayWithCapacity:3];
    size_t bytes=0;
    for(unsigned i=0;i<3;i++){
        TCMesaSurface *s=[[TCMesaSurface alloc]initWithDevice:_device width:w height:h];
        if(!s||s.allocation>192*1024*1024-bytes)return NO;
        bytes+=s.allocation;[fresh addObject:s];
    }
    void *next=[fresh[0] lockForWrite];
    if(!next)return NO;
    if(OSMesaGetCurrentContext()==_mesa) {
        void (*finish)(void)=OSMesaGetProcAddress("glFinish");
        if(!finish)return NO;
        finish();
    }
    if(!OSMesaMakeCurrent(_mesa,next,TC_UNSIGNED_BYTE,w,h))return NO;
    _ring=[fresh copy];_writeSlot=0;_pixels=next;_width=w;_height=h;
    _lastFrame=nil;_lastCenter=nil;_lastPresent=NO;
    if(OSMesaGetCurrentContext()!=_mesa)return NO;
    OSMesaPixelStore(TC_ROW_LENGTH,(int)(_ring[0].stride/4));
    OSMesaPixelStore(TC_Y_UP,0);
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
    [_layer removeFromSuperlayer];_layer=nil;_tcView=nil;_lastPresent=NO;_lastFrame=nil;_lastCenter=nil;
    // Keep the current client buffer alive until rebind or destruction.
}
- (void)dealloc {
    [self clearDrawable];
    if(_mesa){[tcMesaContexts removeObjectForKey:tcContextKey(_mesa)];OSMesaDestroyContext(_mesa);}
    _pixels=NULL;_ring=nil;
}
- (void)flushBuffer {
    _lastPresent=NO;_lastFrame=nil;_lastCenter=nil;
    if(!_layer||!_pixels||_ring.count!=3||OSMesaGetCurrentContext()!=_mesa||![NSThread isMainThread])return;
    // Main-thread adapter must never wait for an activation notification.
    // This prevents background Metal presentation, not arbitrary GL calls.
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    void (*finish)(void)=OSMesaGetProcAddress("glFinish");
    unsigned (*getError)(void)=(unsigned (*)(void))OSMesaGetProcAddress("glGetError");
    if(!finish||!getError)return;
    finish();if(getError()!=0)return;
    TCMesaSurface *finished=_ring[_writeSlot];
    NSUInteger following=(_writeSlot+1)%_ring.count;
    TCMesaSurface *next=_ring[following];
    id<CAMetalDrawable> target=[_layer nextDrawable];
    if(!target||target.texture.width!=(NSUInteger)_width||target.texture.height!=(NSUInteger)_height)return;
    id<MTLCommandBuffer> command=[_queue commandBuffer];
    id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    if(!blit)return;
    [blit copyFromTexture:finished.texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(_width,_height,1) toTexture:target.texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding];
    // Finish GL before handing its surface to Metal; lock the next slot
    // and rebind before unlocking the previous slot. A failed rebind
    // leaves the previous buffer available, with no submitted GPU work.
    void *nextBytes=[next lockForWrite];
    if(!nextBytes)return;
    NSData *center=[NSData dataWithBytes:(const uint8_t *)_pixels+(size_t)(_height/2)*finished.stride+(size_t)(_width/2)*4 length:4];
    if(!OSMesaMakeCurrent(_mesa,nextBytes,TC_UNSIGNED_BYTE,_width,_height)){
        [next unlockForGPU];return;
    }
    _pixels=nextBytes;_writeSlot=following;
    if(OSMesaGetCurrentContext()!=_mesa)return;
    OSMesaPixelStore(TC_ROW_LENGTH,(int)(next.stride/4));OSMesaPixelStore(TC_Y_UP,0);
    if(![finished unlockForGPU])return;
    [command presentDrawable:target];[command commit];
    finished.reader=command;_lastFrame=command;_lastCenter=center;_submittedFrames++;
    // The next frame can run without waiting for this command buffer.
    // Slot reuse waits for its own previous reader only.
    _lastPresent=YES;
}
- (void)setValues:(const int *)values forParameter:(NSInteger)param {
    if(param==222&&values)_swapInterval=*values;
}
- (void)getValues:(int *)values forParameter:(NSInteger)param {
    if(param==222&&values)*values=_swapInterval;
}
@end
__attribute__((visibility("default"))) BOOL TCMesaPresentResult(NSOpenGLContext *ctx){
    id<MTLCommandBuffer> frame=ctx.lastFrame;
    if(!ctx.lastPresent||!frame)return NO;
    [frame waitUntilCompleted];
    return frame.status==MTLCommandBufferStatusCompleted;
}
__attribute__((visibility("default"))) NSUInteger TCMesaSubmittedFrames(NSOpenGLContext *ctx){return ctx.submittedFrames;}
__attribute__((visibility("default"))) void TCMesaDrawableSize(NSOpenGLContext *ctx,int *w,int *h){*w=ctx.width;*h=ctx.height;}
__attribute__((visibility("default"))) BOOL TCMesaCenterBGRA(NSOpenGLContext *ctx,unsigned char *out){
    if(ctx.lastCenter.length!=4||!out)return NO;
    memcpy(out,ctx.lastCenter.bytes,4);return YES;
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
