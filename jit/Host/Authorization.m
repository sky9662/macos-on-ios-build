#import "Authorization.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <dlfcn.h>

// Read the actual entitlement of this process. Never create or modify it.
BOOL TCHasDebugAuthorization(void) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*ReadEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
    if (!security) return NO;
    CreateTask create = (CreateTask)dlsym(security, "SecTaskCreateFromSelf");
    ReadEntitlement read = (ReadEntitlement)dlsym(security, "SecTaskCopyValueForEntitlement");
    CFTypeRef task = create && read ? create(kCFAllocatorDefault) : NULL;
    CFTypeRef value = task ? read(task, CFSTR("get-task-allow"), NULL) : NULL;
    BOOL result = value == kCFBooleanTrue;
    if (value) CFRelease(value);
    if (task) CFRelease(task);
    dlclose(security);
    return result;
}
