// Real user-mediated document picker, limited synchronous AppKit facade.
// Main-thread only; no automatic access outside the app sandbox.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@interface TCPanelDelegate : NSObject<UIDocumentPickerDelegate,UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) NSArray<NSURL *> *chosen;
@property(nonatomic) BOOL done;
@end
@implementation TCPanelDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {self.chosen=urls;self.done=YES;}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {self.done=YES;}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {self.done=YES;}
@end

static BOOL tcPanelActive;
static NSMutableSet<NSURL *> *tcPanelScopes;
static UIViewController *tcPanelPresenter(void) {
    UIViewController *vc=gRootVC;
    while(vc.presentedViewController&&!vc.presentedViewController.isBeingDismissed)vc=vc.presentedViewController;
    return vc;
}
static NSArray<NSURL *> *tcPickDocuments(NSArray<UTType *> *types,BOOL multiple,BOOL copy,NSURL *directory) {
    if(!NSThread.isMainThread||tcPanelActive||!gRootVC.view.window)return nil;
    UIViewController *vc=tcPanelPresenter();if(!vc||vc.isBeingDismissed)return nil;
    tcPanelActive=YES;
    TCPanelDelegate *delegate=[TCPanelDelegate new];
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:types asCopy:copy];
    picker.delegate=delegate;picker.allowsMultipleSelection=multiple;
    if(directory)picker.directoryURL=directory;
    picker.presentationController.delegate=delegate;
    [vc presentViewController:picker animated:YES completion:nil];
    picker.presentationController.delegate=delegate;
    // A nested main run loop is needed for synchronous runModal. The actual
    // converted game's event-loop interaction remains a device-validation gate.
    while(!delegate.done&&gRootVC.view.window){
        @autoreleasepool { [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]; }
        if(!picker.presentingViewController&&!picker.isBeingPresented)break;
    }
    if(picker.presentingViewController)[picker dismissViewControllerAnimated:NO completion:nil];
    tcPanelActive=NO;
    return delegate.chosen;
}
static BOOL tcKeepScope(NSURL *url) {
    if(!url.isFileURL)return NO;
    if(!tcPanelScopes)tcPanelScopes=[NSMutableSet set];
    if([tcPanelScopes containsObject:url])return YES;
    if([url startAccessingSecurityScopedResource]){
        [tcPanelScopes addObject:url];return YES; // retained for process lifetime; Mac caller expects a usable path
    }
    // Local imported copies and app-owned files need no security scope.
    NSString *path=url.URLByResolvingSymlinksInPath.path;
    NSString *home=[NSURL fileURLWithPath:NSHomeDirectory()].URLByResolvingSymlinksInPath.path;
    return [path hasPrefix:[home stringByAppendingString:@"/"]];
}
@interface NSSavePanel : NSObject
@property(nonatomic,copy) NSArray<UTType *> *allowedContentTypes;
@property(nonatomic,copy) NSURL *directoryURL;
@property(nonatomic,copy) NSString *nameFieldStringValue,*title,*message,*prompt;
@property(nonatomic) BOOL canCreateDirectories,extensionHidden,allowsOtherFileTypes;
@property(nonatomic,strong) NSURL *URL;
+ (instancetype)savePanel;
- (NSInteger)runModal;
@end
@implementation NSSavePanel
+ (instancetype)savePanel {return [self new];}
- (NSInteger)runModal {
    self.URL=nil;
    if(!NSThread.isMainThread||tcPanelActive)return 0;
    NSString *name=self.nameFieldStringValue;
    // An empty or invalid filename must be explicitly supplied by the user.
    if(!name.length)name=@"Untitled";
    UIViewController *vc=tcPanelPresenter();if(!vc||!gRootVC.view.window)return 0;
    tcPanelActive=YES;
    __block BOOL done=NO;__block NSString *selected=nil;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:self.title.length?self.title:@"Save file" message:self.message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=name;}];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){done=YES;}]];
    [alert addAction:[UIAlertAction actionWithTitle:self.prompt.length?self.prompt:@"Choose folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){selected=[alert.textFields.firstObject.text copy];done=YES;}]];
    [vc presentViewController:alert animated:NO completion:nil];
    while(!done&&gRootVC.view.window){@autoreleasepool {[[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];}}
    if(alert.presentingViewController)[alert dismissViewControllerAnimated:NO completion:nil];
    tcPanelActive=NO;
    if(!selected.length||[selected isEqualToString:@"."]||[selected isEqualToString:@".."]||[selected containsString:@"/"]||[selected containsString:@"\\"])return 0;
    if(!selected.pathExtension.length&&self.allowedContentTypes.count==1){
        NSString *ext=self.allowedContentTypes.firstObject.preferredFilenameExtension;
        if(ext.length)selected=[selected stringByAppendingPathExtension:ext];
    }
    NSURL *folder=tcPickDocuments(@[UTTypeFolder],NO,NO,self.directoryURL).firstObject;
    if(!folder||!tcKeepScope(folder))return 0;
    NSURL *dest=[folder URLByAppendingPathComponent:selected isDirectory:NO];
    // Do not silently overwrite an existing document. The user can choose a new name.
    if([NSFileManager.defaultManager fileExistsAtPath:dest.path])return 0;
    self.URL=dest;return 1;
}
@end
@interface NSOpenPanel : NSSavePanel
@property(nonatomic) BOOL canChooseFiles,canChooseDirectories,allowsMultipleSelection;
@property(nonatomic,copy) NSArray<NSURL *> *URLs;
+ (instancetype)openPanel;
@end
@implementation NSOpenPanel
+ (instancetype)openPanel {
    NSOpenPanel *p=[self new];p.canChooseFiles=YES;return p;
}
- (NSInteger)runModal {
    self.URL=nil;self.URLs=@[];
    NSMutableArray<UTType *> *types=[NSMutableArray array];
    if(self.canChooseFiles)[types addObjectsFromArray:self.allowedContentTypes.count&&!self.allowsOtherFileTypes?self.allowedContentTypes:@[UTTypeItem]];
    if(self.canChooseDirectories)[types addObject:UTTypeFolder];
    if(!types.count)return 0;
    NSArray<NSURL *> *chosen=tcPickDocuments(types,self.allowsMultipleSelection,!self.canChooseDirectories,self.directoryURL);
    NSMutableArray<NSURL *> *usable=[NSMutableArray array];
    for(NSURL *url in chosen){
        NSNumber *isDirectory=nil;
        if(![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil])continue;
        if(isDirectory.boolValue?!self.canChooseDirectories:!self.canChooseFiles)continue;
        if(tcKeepScope(url))[usable addObject:url];
    }
    self.URLs=usable;self.URL=usable.firstObject;return self.URL?1:0;
}
@end
