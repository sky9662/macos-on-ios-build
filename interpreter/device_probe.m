#import <UIKit/UIKit.h>
extern int tc_vixl_fixed_probe(void);
extern double tc_vixl_fixed_benchmark(void);
@interface TCProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation TCProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc=[UIViewController new];
    vc.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *label=[UILabel new];
    label.numberOfLines=0;
    label.textAlignment=NSTextAlignmentCenter;
    label.text=@"VIXL fixed fixtures: running…";
    label.translatesAutoresizingMaskIntoConstraints=NO;
    [vc.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
      [label.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:20],
      [label.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-20]]];
    self.window.rootViewController=vc;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
      int rc=tc_vixl_fixed_probe();
      double seconds=tc_vixl_fixed_benchmark();
      dispatch_async(dispatch_get_main_queue(), ^{
        label.text=[NSString stringWithFormat:@"VIXL fixed fixtures: %@\n2056 shared + 128 MUL cases\n10000 fixed calls: %.6f s\nNo JIT requested by probe\nNot a game integration",rc==0?@"PASS":@"FAIL",seconds];
      });
    });
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TCProbeDelegate.class)); } }
