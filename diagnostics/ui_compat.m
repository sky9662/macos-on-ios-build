// Narrow, real UIKit-backed AppKit functionality used by the game engine.
// No file panel, cursor lock, keyboard layout translation, or JIT implementation here.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

__attribute__((visibility("default"))) NSString *const NSCalibratedRGBColorSpace=@"NSCalibratedRGBColorSpace";
__attribute__((visibility("default"))) NSString *const NSPasteboardTypeString=@"public.utf8-plain-text";
__attribute__((visibility("default"))) NSString *const NSURLPboardType=@"public.url";
__attribute__((visibility("default"))) NSString *const NSPasteboardURLReadingFileURLsOnlyKey=@"NSPasteboardURLReadingFileURLsOnlyKey";

@interface NSColor : NSObject
@property(nonatomic,strong) UIColor *uiColor;
+ (instancetype)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
@end
@implementation NSColor
+ (instancetype)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    NSColor *c=[self new];c.uiColor=[UIColor colorWithRed:r green:g blue:b alpha:a];return c;
}
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    return [self colorWithCalibratedRed:r green:g blue:b alpha:a];
}
+ (instancetype)clearColor {return [self colorWithCalibratedRed:0 green:0 blue:0 alpha:0];}
+ (instancetype)blackColor {return [self colorWithCalibratedRed:0 green:0 blue:0 alpha:1];}
+ (instancetype)whiteColor {return [self colorWithCalibratedRed:1 green:1 blue:1 alpha:1];}
- (CGColorRef)CGColor {return self.uiColor.CGColor;}
@end
@implementation NSWindow (TCBackgroundColor)
- (void)setBackgroundColor:(NSColor *)color {
    UIColor *c=color.uiColor;
    if(!c)return;
    if(NSThread.isMainThread)self.contentView.hostView.backgroundColor=c;
    else dispatch_async(dispatch_get_main_queue(),^{self.contentView.hostView.backgroundColor=c;});
}
@end

@interface NSPasteboard : NSObject
@property(nonatomic,strong) UIPasteboard *board;
+ (instancetype)generalPasteboard;
@end
@implementation NSPasteboard
+ (instancetype)generalPasteboard {
    NSPasteboard *p=[self new];p.board=UIPasteboard.generalPasteboard;return p;
}
+ (instancetype)pasteboardWithUniqueName {
    NSPasteboard *p=[self new];p.board=[UIPasteboard pasteboardWithUniqueName];return p;
}
- (NSInteger)clearContents {self.board.items=@[];return self.board.changeCount;}
- (NSInteger)declareTypes:(NSArray *)types owner:(id)owner {
    // Ownership promised-data callbacks not supported. Clear actual content for explicit declaration.
    return [self clearContents];
}
- (BOOL)setString:(NSString *)value forType:(NSString *)type {
    if(!value||!type)return NO;
    if([type isEqualToString:NSPasteboardTypeString]||[type isEqualToString:@"NSStringPboardType"]){
        self.board.string=value;return YES;
    }
    if([type isEqualToString:NSURLPboardType]){
        NSURL *url=[NSURL URLWithString:value];if(!url)return NO;self.board.URL=url;return YES;
    }
    return NO;
}
- (NSString *)stringForType:(NSString *)type {
    if([type isEqualToString:NSPasteboardTypeString]||[type isEqualToString:@"NSStringPboardType"])return self.board.string;
    if([type isEqualToString:NSURLPboardType])return self.board.URL.absoluteString;
    return nil;
}
- (NSArray *)types {
    NSMutableOrderedSet *types=[NSMutableOrderedSet orderedSet];
    for(NSDictionary *item in self.board.items)[types addObjectsFromArray:item.allKeys];
    return types.array;
}
- (NSArray *)readObjectsForClasses:(NSArray *)classes options:(NSDictionary *)options {
    NSMutableArray *values=[NSMutableArray array];
    if([classes containsObject:NSString.class]&&self.board.string)[values addObject:self.board.string];
    if([classes containsObject:NSURL.class]){
        BOOL fileOnly=[options[NSPasteboardURLReadingFileURLsOnlyKey] boolValue];
        for(NSURL *url in self.board.URLs ?: @[])if(!fileOnly||url.isFileURL)[values addObject:url];
    }
    return values.count?values:nil;
}
@end

@interface NSTrackingArea : NSObject
@property(nonatomic) CGRect rect;
@property(nonatomic) NSUInteger options;
@property(nonatomic,weak) id owner;
@property(nonatomic,copy) NSDictionary *userInfo;
@end
@implementation NSTrackingArea
- (instancetype)initWithRect:(CGRect)rect options:(NSUInteger)options owner:(id)owner userInfo:(NSDictionary *)info {
    if((self=[super init])){_rect=rect;_options=options;_owner=owner;_userInfo=[info copy];}return self;
}
@end
static char tcTrackingKey;
static NSMutableArray *tcTrackingAreas(NSView *view) {
    NSMutableArray *areas=objc_getAssociatedObject(view,&tcTrackingKey);
    if(!areas){areas=[NSMutableArray array];objc_setAssociatedObject(view,&tcTrackingKey,areas,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return areas;
}
@implementation NSView (TCTrackingStorage)
- (void)tcAddTrackingArea:(id)area {if(area&&! [tcTrackingAreas(self) containsObject:area])[tcTrackingAreas(self) addObject:area];}
- (void)tcRemoveTrackingArea:(id)area {if(area)[tcTrackingAreas(self) removeObject:area];}
- (NSArray *)tcTrackingAreas {return [tcTrackingAreas(self) copy];}
@end

// Menu model only. UIKit does not display the macOS menu bar; no fake action execution.
@class NSMenu;
@interface NSMenuItem : NSObject
@property(nonatomic,copy) NSString *title,*keyEquivalent;
@property(nonatomic) SEL action;
@property(nonatomic,weak) id target;
@property(nonatomic) NSUInteger keyEquivalentModifierMask;
@property(nonatomic,strong) NSMenu *submenu;
@end
@implementation NSMenuItem
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    if((self=[super init])){_title=[title copy];_action=action;_keyEquivalent=[key copy];}return self;
}
+ (instancetype)separatorItem {return [[self alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];}
@end
@interface NSMenu : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,strong) NSMutableArray<NSMenuItem *> *items;
@end
@implementation NSMenu
- (instancetype)init {return [self initWithTitle:@""];}
- (instancetype)initWithTitle:(NSString *)title {
    if((self=[super init])){_title=[title copy];_items=[NSMutableArray array];}return self;
}
- (void)addItem:(NSMenuItem *)item {if(item)[self.items addObject:item];}
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];[self addItem:item];return item;
}
- (void)removeItem:(NSMenuItem *)item {if(item)[self.items removeObject:item];}
- (NSArray *)itemArray {return [self.items copy];}
- (NSInteger)numberOfItems {return self.items.count;}
@end
static char tcMainMenuKey,tcServicesMenuKey,tcWindowsMenuKey,tcAppleMenuKey;
@implementation NSApplication (TCMenuStorage)
- (void)setMainMenu:(NSMenu *)menu {objc_setAssociatedObject(self,&tcMainMenuKey,menu,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (NSMenu *)mainMenu {return objc_getAssociatedObject(self,&tcMainMenuKey);}
- (void)setServicesMenu:(NSMenu *)menu {objc_setAssociatedObject(self,&tcServicesMenuKey,menu,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (void)setWindowsMenu:(NSMenu *)menu {objc_setAssociatedObject(self,&tcWindowsMenuKey,menu,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (void)setAppleMenu:(NSMenu *)menu {objc_setAssociatedObject(self,&tcAppleMenuKey,menu,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
@end

// RGBA interleaved bitmap storage used by GLFW icon/cursor images.
@interface NSBitmapImageRep : NSObject
@property(nonatomic,strong) NSMutableData *storage;
@property(nonatomic) NSInteger pixelsWide,pixelsHigh,bytesPerRow;
@end
@implementation NSBitmapImageRep
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bits samplesPerPixel:(NSInteger)samples hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar colorSpaceName:(NSString *)space bitmapFormat:(NSUInteger)format bytesPerRow:(NSInteger)row bitsPerPixel:(NSInteger)bpp {
    if(w<=0||h<=0||w>16384||h>16384||bits!=8||samples!=4||!alpha||planar||(bpp&&bpp!=32))return nil;
    if(!row)row=w*4;if(row<w*4||row>16384*4||(NSUInteger)row*(NSUInteger)h>128*1024*1024)return nil;
    if((self=[super init])){
        _pixelsWide=w;_pixelsHigh=h;_bytesPerRow=row;
        _storage=[NSMutableData dataWithLength:(NSUInteger)row*(NSUInteger)h];
        if(planes&&planes[0])memcpy(_storage.mutableBytes,planes[0],_storage.length);
    }return self;
}
- (unsigned char *)bitmapData {return self.storage.mutableBytes;}
@end
@interface NSImage : NSObject
@property(nonatomic) CGSize size;
@property(nonatomic,strong) NSMutableArray<NSBitmapImageRep *> *representations;
@end
@implementation NSImage
- (instancetype)initWithSize:(CGSize)size {
    if((self=[super init])){_size=size;_representations=[NSMutableArray array];}return self;
}
- (void)addRepresentation:(NSBitmapImageRep *)rep {if(rep)[self.representations addObject:rep];}
@end
