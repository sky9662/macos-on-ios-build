// Application-local cursor: no system cursor warping or OS-level mouse capture.
// The visible overlay follows the same window-space position used by NSEvent.
static UIView *tcCursorOverlay;
static UIImageView *tcCursorImage;
static UILabel *tcCursorGlyph;
static CGPoint tcCursorHotspot;
static NSInteger tcCursorHideCount;
static BOOL tcCursorVisible=YES;
static void tcCursorUpdate(void) {
    if(!NSThread.isMainThread)return;
    UIView *root=gRootVC.view;if(!root)return;
    if(!tcCursorOverlay){
        tcCursorOverlay=[[UIView alloc]initWithFrame:CGRectMake(0,0,32,32)];
        tcCursorOverlay.userInteractionEnabled=NO;
        tcCursorOverlay.backgroundColor=UIColor.clearColor;
        tcCursorOverlay.layer.zPosition=100000;
        tcCursorGlyph=[[UILabel alloc]initWithFrame:tcCursorOverlay.bounds];
        tcCursorGlyph.text=@"↖";tcCursorGlyph.font=[UIFont boldSystemFontOfSize:26];
        tcCursorGlyph.textColor=UIColor.whiteColor;
        tcCursorGlyph.layer.shadowColor=UIColor.blackColor.CGColor;
        tcCursorGlyph.layer.shadowOpacity=1;tcCursorGlyph.layer.shadowRadius=1;
        [tcCursorOverlay addSubview:tcCursorGlyph];
        tcCursorImage=[[UIImageView alloc]initWithFrame:tcCursorOverlay.bounds];
        [tcCursorOverlay addSubview:tcCursorImage];
    }
    if(tcCursorOverlay.superview!=root)[root addSubview:tcCursorOverlay];
    [root bringSubviewToFront:tcCursorOverlay];
    tcCursorOverlay.frame=(CGRect){CGPointMake(gMouse.x-tcCursorHotspot.x,root.bounds.size.height-gMouse.y-tcCursorHotspot.y),tcCursorOverlay.bounds.size};
    tcCursorOverlay.hidden=!tcCursorVisible||tcCursorHideCount>0;
}
static void tcCursorMain(dispatch_block_t b){
    if(NSThread.isMainThread)b();else dispatch_async(dispatch_get_main_queue(),b);
}
@interface NSCursor : NSObject
@property(nonatomic,strong) NSImage *image;
@property(nonatomic) CGPoint hotSpot;
@property(nonatomic,copy) NSString *glyph;
@end
@implementation NSCursor
- (instancetype)initWithImage:(NSImage *)image hotSpot:(CGPoint)hotSpot {
    if((self=[super init])){_image=image;_hotSpot=hotSpot;_glyph=@"↖";}return self;
}
+ (instancetype)cursorWithGlyph:(NSString *)glyph {
    NSCursor *c=[self new];c.glyph=glyph;return c;
}
+ (instancetype)arrowCursor {return [self cursorWithGlyph:@"↖"];}
+ (instancetype)IBeamCursor {return [self cursorWithGlyph:@"Ⅰ"];}
+ (instancetype)crosshairCursor {return [self cursorWithGlyph:@"+"];}
+ (instancetype)pointingHandCursor {return [self cursorWithGlyph:@"☝"];}
+ (instancetype)openHandCursor {return [self cursorWithGlyph:@"✋"];}
+ (instancetype)closedHandCursor {return [self cursorWithGlyph:@"✊"];}
+ (instancetype)resizeLeftRightCursor {return [self cursorWithGlyph:@"↔"];}
+ (instancetype)resizeUpDownCursor {return [self cursorWithGlyph:@"↕"];}
+ (instancetype)operationNotAllowedCursor {return [self cursorWithGlyph:@"⊘"];}
+ (void)hide {tcCursorMain(^{tcCursorHideCount++;tcCursorUpdate();});}
+ (void)unhide {tcCursorMain(^{if(tcCursorHideCount>0)tcCursorHideCount--;tcCursorUpdate();});}
- (void)set {
    tcCursorMain(^{
        tcCursorUpdate();tcCursorHotspot=self.hotSpot;tcCursorVisible=YES;
        NSBitmapImageRep *rep=self.image.representations.firstObject;
        UIImage *image=nil;
        if(rep&&rep.storage.length>0){
            CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)rep.storage);
            CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            CGImageRef cg=CGImageCreate(rep.pixelsWide,rep.pixelsHigh,8,32,rep.bytesPerRow,space,kCGImageAlphaLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
            if(cg){image=[UIImage imageWithCGImage:cg];CGImageRelease(cg);}
            CGColorSpaceRelease(space);CGDataProviderRelease(provider);
        }
        CGSize size=image?self.image.size:CGSizeMake(32,32);
        if(size.width<=0||size.height<=0)size=CGSizeMake(32,32);
        tcCursorOverlay.bounds=(CGRect){CGPointZero,size};
        tcCursorImage.frame=tcCursorGlyph.frame=tcCursorOverlay.bounds;
        tcCursorImage.image=image;tcCursorImage.hidden=!image;
        tcCursorGlyph.text=self.glyph?:@"↖";tcCursorGlyph.hidden=image!=nil;
        tcCursorUpdate();
    });
}
@end
// The game can request a position in its own virtual display. This does not move the hardware pointer.
__attribute__((visibility("default"))) int32_t CGWarpMouseCursorPosition(CGPoint p){
    if(!isfinite(p.x)||!isfinite(p.y))return 1004;
    tcCursorMain(^{
        CGSize s=gRootVC.view.bounds.size;
        gMouse=CGPointMake(MAX(0,MIN(s.width,p.x)),MAX(0,MIN(s.height,s.height-p.y)));
        tcCursorUpdate();
    });return 0;
}
__attribute__((visibility("default"))) int32_t CGDisplayMoveCursorToPoint(uint32_t d,CGPoint p){
    return d==1?CGWarpMouseCursorPosition(p):1004;
}
__attribute__((visibility("default"))) int32_t CGAssociateMouseAndMouseCursorPosition(bool connected){
    // Relative/captured hardware pointer mode is not implemented. Return explicit failure.
    return connected?0:1000;
}
