// App-local event source metadata. No system-wide event suppression.
__attribute__((visibility("default"))) NSString *const NSTextInputContextKeyboardSelectionDidChangeNotification=@"NSTextInputContextKeyboardSelectionDidChangeNotification";
__attribute__((visibility("default"))) CFTypeRef CGEventSourceCreate(int32_t state){
    if(state< -1||state>1)return NULL;
    return CFBridgingRetain([@{@"TCEventSourceState":@(state),@"suppressionInterval":@0.0} mutableCopy]);
}
__attribute__((visibility("default"))) void CGEventSourceSetLocalEventsSuppressionInterval(CFTypeRef source,double interval){
    if(!source||!isfinite(interval)||interval<0)return;
    id obj=(__bridge id)source;
    if([obj isKindOfClass:NSMutableDictionary.class]&&obj[@"TCEventSourceState"]){
        obj[@"suppressionInterval"]=@(interval);
        // Stored for compatibility only; the iOS app cannot suppress global events.
    }
}
// Register only the embedded compatibility bundles for the actual GLFW lookups.
// Keep them alive for the whole process; failures are logged rather than masked.
static void tcRegisterCompatibilityBundles(void) {
    static NSMutableArray *bundles;
    if(bundles)return;
    bundles=[NSMutableArray array];
    for(NSString *name in @[@"OpenGLShim.framework",@"HIToolboxShim.framework"]){
        NSURL *url=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:name];
        if(!url||![NSFileManager.defaultManager fileExistsAtPath:url.path])continue;
        CFBundleRef b=CFBundleCreate(kCFAllocatorDefault,(__bridge CFURLRef)url);
        if(b){
            CFErrorRef error=NULL;
            if(CFBundleLoadExecutableAndReturnError(b,&error)){
                [bundles addObject:(__bridge id)b];
                NSLog(@"TC registered compatibility bundle %@",CFBundleGetIdentifier(b));
            }else NSLog(@"TC compatibility bundle load failed %@: %@",name,error);
            if(error)CFRelease(error);CFRelease(b);
        }
    }
}
__attribute__((constructor)) static void tcLoadCompatibilityBundles(void){@autoreleasepool{tcRegisterCompatibilityBundles();}}
