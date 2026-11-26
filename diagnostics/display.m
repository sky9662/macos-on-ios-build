// Virtual single-display view of the actual UIKit window, not desktop monitor control.
// Only the functions implemented here are advertised; cursor/gamma/HID remain unresolved.
#import <stdint.h>
typedef uint32_t TCDisplayID;
typedef CFDictionaryRef TCDisplayMode;
static NSDictionary *tcDisplaySnapshot(void) {
    __block NSDictionary *result;
    void (^measure)(void)=^{
        UIScreen *screen=gRootVC.view.window.windowScene.screen ?: UIScreen.mainScreen;
        CGSize size=gRootVC.view.bounds.size;
        if(size.width<=0||size.height<=0)size=screen.bounds.size;
        CGFloat scale=gRootVC.view.window.screen.scale;
        if(scale<=0)scale=screen.scale;
        result=@{@"width":@(size.width),@"height":@(size.height),
            @"pixelWidth":@(llround(size.width*scale)),@"pixelHeight":@(llround(size.height*scale)),
            @"hz":@(screen.maximumFramesPerSecond)};
    };
    if(NSThread.isMainThread)measure();else dispatch_sync(dispatch_get_main_queue(),measure);
    return result;
}
#define TC_EXPORT __attribute__((visibility("default")))
TC_EXPORT int32_t CGGetOnlineDisplayList(uint32_t capacity, TCDisplayID *displays,uint32_t *count){
    if(count)*count=displays?MIN(capacity,1u):1u;
    if(displays&&capacity)displays[0]=1;
    return 0;
}
TC_EXPORT TCDisplayID CGMainDisplayID(void){return 1;}
TC_EXPORT CGRect CGDisplayBounds(TCDisplayID d){
    if(d!=1)return CGRectNull;
    NSDictionary *m=tcDisplaySnapshot();return CGRectMake(0,0,[m[@"width"] doubleValue],[m[@"height"] doubleValue]);
}
TC_EXPORT TCDisplayMode CGDisplayCopyDisplayMode(TCDisplayID d){return d==1?CFBridgingRetain(tcDisplaySnapshot()):NULL;}
TC_EXPORT CFArrayRef CGDisplayCopyAllDisplayModes(TCDisplayID d,CFDictionaryRef opts){
    if(d!=1)return NULL;
    return CFBridgingRetain(@[tcDisplaySnapshot()]);
}
TC_EXPORT void CGDisplayModeRelease(TCDisplayMode m){if(m)CFRelease(m);}
static NSDictionary *tcMode(TCDisplayMode m){return (__bridge NSDictionary *)m;}
TC_EXPORT size_t CGDisplayModeGetWidth(TCDisplayMode m){return [tcMode(m)[@"width"] unsignedLongLongValue];}
TC_EXPORT size_t CGDisplayModeGetHeight(TCDisplayMode m){return [tcMode(m)[@"height"] unsignedLongLongValue];}
TC_EXPORT size_t CGDisplayModeGetPixelWidth(TCDisplayMode m){return [tcMode(m)[@"pixelWidth"] unsignedLongLongValue];}
TC_EXPORT size_t CGDisplayModeGetPixelHeight(TCDisplayMode m){return [tcMode(m)[@"pixelHeight"] unsignedLongLongValue];}
TC_EXPORT double CGDisplayModeGetRefreshRate(TCDisplayMode m){return [tcMode(m)[@"hz"] doubleValue];}
TC_EXPORT uint32_t CGDisplayModeGetIOFlags(TCDisplayMode m){return m?3:0;}
TC_EXPORT int32_t CGDisplaySetDisplayMode(TCDisplayID d,TCDisplayMode m,CFDictionaryRef opts){
    // A virtual window cannot change the physical display mode. Accept only the actual current mode.
    if(d==1&&m&&[tcMode(m) isEqualToDictionary:tcDisplaySnapshot()])return 0;
    return 1004; // kCGErrorIllegalArgument
}

// Identity of the virtual display, not invented hardware serial/model details.
TC_EXPORT uint32_t CGDisplayIsAsleep(TCDisplayID d){
    if(d!=1)return 1;
    __block BOOL inactive=NO;
    void (^f)(void)=^{inactive=UIApplication.sharedApplication.applicationState==UIApplicationStateBackground;};
    if(NSThread.isMainThread)f();else dispatch_sync(dispatch_get_main_queue(),f);
    return inactive;
}
TC_EXPORT uint32_t CGDisplayUnitNumber(TCDisplayID d){return d==1?0:UINT32_MAX;}
TC_EXPORT uint32_t CGDisplayVendorNumber(TCDisplayID d){return 0;}
TC_EXPORT uint32_t CGDisplayModelNumber(TCDisplayID d){return 0;}
TC_EXPORT TCDisplayID CGOpenGLDisplayMaskToDisplayID(uint32_t mask){return (mask&1)?1:0;}
TC_EXPORT CGSize CGDisplayScreenSize(TCDisplayID d){
    // UIKit exposes logical/pixel dimensions, not verified physical millimetres.
    return CGSizeZero;
}

// iOS has no public app API for physical display gamma ramps or exclusive
// display fade reservations. Report the documented unsupported-operation error,
// not successful changes to hardware. GLFW can choose its normal fallback.
enum { TCDisplayUnsupported=1000, TCDisplayInvalid=1004 };
TC_EXPORT uint32_t CGDisplayGammaTableCapacity(TCDisplayID display) {return 0;}
TC_EXPORT int32_t CGGetDisplayTransferByTable(TCDisplayID display,uint32_t capacity,float *red,float *green,float *blue,uint32_t *count) {
    if(count)*count=0;
    return display==1?TCDisplayUnsupported:TCDisplayInvalid;
}
TC_EXPORT int32_t CGSetDisplayTransferByTable(TCDisplayID display,uint32_t count,const float *red,const float *green,const float *blue) {
    return display==1?TCDisplayUnsupported:TCDisplayInvalid;
}
TC_EXPORT int32_t CGAcquireDisplayFadeReservation(float seconds,uint32_t *token) {
    if(!token)return TCDisplayInvalid;
    *token=0;
    return TCDisplayUnsupported;
}
TC_EXPORT int32_t CGReleaseDisplayFadeReservation(uint32_t token) {return TCDisplayInvalid;}
TC_EXPORT int32_t CGDisplayFade(uint32_t token,float duration,float start,float end,float red,float green,float blue,bool synchronous) {
    return TCDisplayUnsupported;
}
// A virtual display name is sufficient for the app's monitor list. Do not
// fabricate EDID, vendor/model identifiers, physical dimensions or serials.
TC_EXPORT CFDictionaryRef IODisplayCreateInfoDictionary(uint32_t service,uint32_t options) {
    return CFBridgingRetain(@{@"DisplayProductName":@{@"en_US":@"iOS virtual display"}});
}
