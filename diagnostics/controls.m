// App-local, opt-in trackpad. Direct touch remains unchanged outside the panel.
static NSUInteger tcOverlayMouseButtons;
static void tcOverlayMouse(NSEventType type,NSInteger button,CGPoint delta){
    NSWindow *window=gWindows.lastObject;if(!window)return;
    NSEvent *e=[NSEvent new];e.type=type;e.window=window;e.locationInWindow=gMouse;
    e.buttonNumber=button;e.clickCount=1;e.deltaX=delta.x;e.deltaY=delta.y;
    e.timestamp=NSProcessInfo.processInfo.systemUptime;e.modifierFlags=gModifiers;
    ShimDispatch(e);
}
static NSString *tcOverlayKeyName(int hid){
    if(hid>=4&&hid<=29)return [NSString stringWithFormat:@"%c",'A'+hid-4];
    if(hid>=30&&hid<=39)return [NSString stringWithFormat:@"%c",hid==39?'0':'1'+hid-30];
    switch(hid){case 40:return @"Enter";case 41:return @"Esc";case 42:return @"Backspace";case 43:return @"Tab";case 44:return @"Space";
        case 79:return @"Right";case 80:return @"Left";case 81:return @"Down";case 82:return @"Up";default:return @"Invalid";}
}
static NSString *tcOverlayKeyChars(int hid){
    if(hid>=4&&hid<=29)return [NSString stringWithFormat:@"%c",'a'+hid-4];
    if(hid>=30&&hid<=39)return tcOverlayKeyName(hid);
    unichar ch=0;
    switch(hid){case 40:ch=13;break;case 41:ch=27;break;case 42:ch=127;break;case 43:ch=9;break;case 44:ch=32;break;
        case 79:ch=0xf703;break;case 80:ch=0xf702;break;case 81:ch=0xf701;break;case 82:ch=0xf700;break;}
    return ch?[NSString stringWithCharacters:&ch length:1]:@"";
}
static void tcOverlayKeyEvent(int hid,BOOL down){
    if(!tcKeyAllowed(hid))return;
    NSWindow *window=gWindows.lastObject;int code=ShimMacKeyCode(hid);
    if(!window||code<0)return;
    NSEvent *e=[NSEvent new];e.type=down?NSEventTypeKeyDown:NSEventTypeKeyUp;
    e.window=window;e.keyCode=(unsigned short)code;e.locationInWindow=gMouse;
    e.charactersIgnoringModifiers=tcOverlayKeyChars(hid);e.characters=e.charactersIgnoringModifiers;
    if(hid>=4&&hid<=29&&(gModifiers&(1u<<17)))e.characters=e.characters.uppercaseString;
    e.modifierFlags=gModifiers;e.timestamp=NSProcessInfo.processInfo.systemUptime;
    ShimDispatch(e);
}
// A transparent hit-test layer: only its visible buttons consume touches.
@interface TCFloatingKeys : UIView
@property(nonatomic,strong) NSArray<UIButton *> *buttons;
@property(nonatomic,strong) NSMutableArray<NSValue *> *positions;
@end
@implementation TCFloatingKeys
- (CGRect)usableRect{
    CGRect safe=UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets);
    return CGRectInset(safe,4,4);
}
- (void)layoutSubviews{
    [super layoutSubviews];
    CGRect safe=[self usableRect];
    for(UIButton *button in self.buttons){
        CGPoint n=[self.positions[button.tag] CGPointValue];
        CGFloat w=MAX(0,MIN(70,safe.size.width)),h=MAX(0,MIN(44,safe.size.height));
        button.bounds=CGRectMake(0,0,w,h);
        button.center=CGPointMake(tcLayoutCenter(n.x,safe.origin.x,safe.size.width,w),
                                  tcLayoutCenter(n.y,safe.origin.y,safe.size.height,h));
    }
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    UIView *view=[super hitTest:point withEvent:event];
    return view==self?nil:view;
}
@end
@interface TCControlOverlay : NSObject { TCKeyState _heldKeys; }
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIButton *toggle;
@property(nonatomic) double sensitivity,acceleration;
@property(nonatomic,strong) NSArray<UIButton *> *keyButtons;
@property(nonatomic,strong) UIButton *remapButton;
@property(nonatomic,strong) TCFloatingKeys *floating;
@property(nonatomic,strong) UIButton *editButton;
@property(nonatomic,strong) NSArray<UIPanGestureRecognizer *> *keyDrags;
@property(nonatomic) BOOL editing;
@end
@implementation TCControlOverlay
- (UIButton *)button:(NSString *)title{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor=[UIColor colorWithWhite:0.15 alpha:0.9];b.layer.cornerRadius=8;return b;
}
- (void)mouseDown:(UIButton *)b{
    NSUInteger bit=1u<<b.tag;if(tcOverlayMouseButtons&bit)return;
    tcOverlayMouseButtons|=bit;tcOverlayMouse(b.tag?3:NSEventTypeLeftMouseDown,b.tag,CGPointZero);
}
- (void)mouseUp:(UIButton *)b{
    NSUInteger bit=1u<<b.tag;if(!(tcOverlayMouseButtons&bit))return;
    tcOverlayMouseButtons&=~bit;tcOverlayMouse(b.tag?4:NSEventTypeLeftMouseUp,b.tag,CGPointZero);
}
- (NSString *)preference:(NSInteger)slot{return [NSString stringWithFormat:@"TCControls.key.%ld",(long)slot];}
- (int)mappedKey:(NSInteger)slot{
    if(slot<0||slot>=TCKeySlotCount)return 0;
    int hid=(int)[NSUserDefaults.standardUserDefaults integerForKey:[self preference:slot]];
    if(tcKeyAllowed(hid))return hid;
    const int defaults[TCKeySlotCount]={44,41,40};return defaults[slot];
}
- (void)keyDown:(UIButton *)button{
    if(self.editing||!gWindows.lastObject)return;
    int hid=tcKeyDown(&_heldKeys,(int)button.tag,[self mappedKey:button.tag]);
    if(hid)tcOverlayKeyEvent(hid,YES);
}
- (void)keyUp:(UIButton *)button{
    int hid=tcKeyUp(&_heldKeys,(int)button.tag);if(hid)tcOverlayKeyEvent(hid,NO);
}
- (void)releaseAll{
    for(int i=0;i<TCKeySlotCount;i++){
        int hid=tcKeyUp(&_heldKeys,i);if(hid)tcOverlayKeyEvent(hid,NO);
    }
    if(tcOverlayMouseButtons&1){tcOverlayMouseButtons&=~1u;tcOverlayMouse(NSEventTypeLeftMouseUp,0,CGPointZero);}
    if(tcOverlayMouseButtons&2){tcOverlayMouseButtons&=~2u;tcOverlayMouse(4,1,CGPointZero);}
}
- (void)resign:(NSNotification *)notification{(void)notification;[self releaseAll];}
- (void)pan:(UIPanGestureRecognizer *)pan{
    if(pan.state!=UIGestureRecognizerStateChanged)return;
    UIView *root=gRootVC.view;CGPoint d=[pan translationInView:pan.view],v=[pan velocityInView:pan.view];
    [pan setTranslation:CGPointZero inView:pan.view];
    double gain=tcPointerGain(hypot(v.x,v.y),self.sensitivity,self.acceleration);
    CGPoint old=gMouse;
    gMouse=CGPointMake(tcPointerAxis(old.x,d.x,gain,root.bounds.size.width),tcPointerAxis(old.y,-d.y,gain,root.bounds.size.height));
    tcCursorUpdate();
    NSEventType type=(tcOverlayMouseButtons&1)?NSEventTypeLeftMouseDragged:(tcOverlayMouseButtons&2)?(NSEventType)7:NSEventTypeMouseMoved;
    tcOverlayMouse(type,(tcOverlayMouseButtons&1)?0:((tcOverlayMouseButtons&2)?1:0),CGPointMake(gMouse.x-old.x,old.y-gMouse.y));
}
- (NSString *)positionKey:(NSInteger)slot{return [NSString stringWithFormat:@"TCControls.position.%ld",(long)slot];}
- (CGPoint)defaultPosition:(NSInteger)slot{return CGPointMake(0.10,0.47+0.18*slot);}
- (void)loadPositions{
    self.floating.positions=[NSMutableArray new];
    for(int i=0;i<TCKeySlotCount;i++){
        CGPoint p=[self defaultPosition:i];
        NSArray *stored=[NSUserDefaults.standardUserDefaults arrayForKey:[self positionKey:i]];
        if(stored.count==2&&[stored[0] isKindOfClass:NSNumber.class]&&[stored[1] isKindOfClass:NSNumber.class]){
            double x=[stored[0] doubleValue],y=[stored[1] doubleValue];
            if(isfinite(x)&&isfinite(y))p=CGPointMake(tcClamp(x,0,1),tcClamp(y,0,1));
        }
        [self.floating.positions addObject:[NSValue valueWithCGPoint:p]];
    }
}
- (void)toggleEdit{
    [self releaseAll];self.editing=!self.editing;
    for(UIPanGestureRecognizer *drag in self.keyDrags)drag.enabled=self.editing;
    [self.editButton setTitle:self.editing?@"Done":@"Move keys" forState:UIControlStateNormal];
    for(UIButton *b in self.keyButtons){
        b.layer.borderWidth=self.editing?2:0;b.layer.borderColor=UIColor.systemYellowColor.CGColor;
    }
}
- (void)resetPositions{
    [self releaseAll];
    for(int i=0;i<TCKeySlotCount;i++)[NSUserDefaults.standardUserDefaults removeObjectForKey:[self positionKey:i]];
    [self loadPositions];[self.floating setNeedsLayout];
}
- (void)dragKey:(UIPanGestureRecognizer *)drag{
    if(!self.editing||![drag.view isKindOfClass:UIButton.class])return;
    if(drag.state!=UIGestureRecognizerStateChanged&&drag.state!=UIGestureRecognizerStateEnded)return;
    UIButton *b=(UIButton *)drag.view;
    CGRect safe=[self.floating usableRect];CGPoint d=[drag translationInView:self.floating];
    [drag setTranslation:CGPointZero inView:self.floating];
    CGPoint p=CGPointMake(tcLayoutFraction(b.center.x+d.x,safe.origin.x,safe.size.width,b.bounds.size.width),
                          tcLayoutFraction(b.center.y+d.y,safe.origin.y,safe.size.height,b.bounds.size.height));
    self.floating.positions[b.tag]=[NSValue valueWithCGPoint:p];
    [self.floating setNeedsLayout];[self.floating layoutIfNeeded];
    if(drag.state==UIGestureRecognizerStateEnded){
        [NSUserDefaults.standardUserDefaults setObject:@[@(p.x),@(p.y)] forKey:[self positionKey:b.tag]];
    }
}
- (void)togglePanel{
    if(!self.panel.hidden){[self releaseAll];if(self.editing)[self toggleEdit];}
    self.panel.hidden=!self.panel.hidden;self.floating.hidden=self.panel.hidden;
}
- (void)slider:(UISlider *)s{
    if(s.tag==0)self.sensitivity=s.value;else self.acceleration=s.value;
    [NSUserDefaults.standardUserDefaults setDouble:self.sensitivity forKey:@"TCControls.sensitivity"];
    [NSUserDefaults.standardUserDefaults setDouble:self.acceleration forKey:@"TCControls.acceleration"];
}
- (void)refreshMappings{
    NSMutableArray<UIMenu *> *slots=[NSMutableArray new];
    for(UIButton *button in self.keyButtons){
        NSInteger slot=button.tag;int selected=[self mappedKey:slot];
        NSString *name=tcOverlayKeyName(selected);
        [button setTitle:name forState:UIControlStateNormal];
        button.accessibilityLabel=[NSString stringWithFormat:@"Key %ld: %@",(long)slot+1,name];
        NSMutableArray<UIAction *> *choices=[NSMutableArray new];
        for(int hid=4;hid<=82;hid++){
            if(!tcKeyAllowed(hid))continue;
            int usage=hid;
            __weak TCControlOverlay *weakSelf=self;
            UIAction *action=[UIAction actionWithTitle:tcOverlayKeyName(usage) image:nil identifier:nil handler:^(__kindof UIAction *item){
                (void)item;TCControlOverlay *strongSelf=weakSelf;if(!strongSelf)return;
                [strongSelf releaseAll];
                [NSUserDefaults.standardUserDefaults setInteger:usage forKey:[strongSelf preference:slot]];
                [strongSelf refreshMappings];
            }];
            action.state=usage==selected?UIMenuElementStateOn:UIMenuElementStateOff;
            [choices addObject:action];
        }
        [slots addObject:[UIMenu menuWithTitle:[NSString stringWithFormat:@"Key %ld (%@)",(long)slot+1,name] children:choices]];
    }
    self.remapButton.menu=[UIMenu menuWithTitle:@"Remap keys" children:slots];
}
- (void)install:(UIView *)root{
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    self.sensitivity=[prefs objectForKey:@"TCControls.sensitivity"]?tcClamp([prefs doubleForKey:@"TCControls.sensitivity"],0.25,3):1;
    self.acceleration=[prefs objectForKey:@"TCControls.acceleration"]?tcClamp([prefs doubleForKey:@"TCControls.acceleration"],0,2):0;
    self.toggle=[self button:@"Controls"];self.toggle.translatesAutoresizingMaskIntoConstraints=NO;
    self.toggle.layer.zPosition=90001;[self.toggle addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.toggle];
    self.panel=[UIView new];self.panel.translatesAutoresizingMaskIntoConstraints=NO;
    self.panel.layer.zPosition=90000;self.panel.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.85];self.panel.layer.cornerRadius=12;
    self.panel.hidden=YES;[root addSubview:self.panel];
    UIView *pad=[UIView new];pad.backgroundColor=[UIColor colorWithWhite:0.25 alpha:0.9];pad.layer.cornerRadius=8;
    [pad addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    UILabel *label=[UILabel new];label.text=@"Trackpad";label.textColor=UIColor.whiteColor;label.textAlignment=NSTextAlignmentCenter;label.translatesAutoresizingMaskIntoConstraints=NO;
    [pad addSubview:label];[NSLayoutConstraint activateConstraints:@[[label.centerXAnchor constraintEqualToAnchor:pad.centerXAnchor],[label.centerYAnchor constraintEqualToAnchor:pad.centerYAnchor],[pad.heightAnchor constraintEqualToConstant:88]]];
    UIStackView *buttons=[[UIStackView alloc]init];buttons.spacing=4;buttons.distribution=UIStackViewDistributionFillEqually;
    for(NSInteger i=0;i<2;i++){
        UIButton *b=[self button:i?@"Right click":@"Left click"];b.tag=i;
        [b addTarget:self action:@selector(mouseDown:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(mouseUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        [buttons addArrangedSubview:b];
    }
    UIStackView *keyRow=[[UIStackView alloc]init];keyRow.spacing=4;keyRow.distribution=UIStackViewDistributionFillEqually;
    self.floating=[TCFloatingKeys new];self.floating.translatesAutoresizingMaskIntoConstraints=NO;
    self.floating.backgroundColor=UIColor.clearColor;self.floating.layer.zPosition=89999;self.floating.hidden=YES;
    [root addSubview:self.floating];
    [NSLayoutConstraint activateConstraints:@[
        [self.floating.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.floating.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.floating.topAnchor constraintEqualToAnchor:root.topAnchor],
        [self.floating.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];
    NSMutableArray<UIButton *> *keys=[NSMutableArray new];
    NSMutableArray<UIPanGestureRecognizer *> *drags=[NSMutableArray new];
    for(int i=0;i<TCKeySlotCount;i++){
        UIButton *b=[self button:@""];b.tag=i;
        b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        b.titleLabel.adjustsFontSizeToFitWidth=YES;b.titleLabel.minimumScaleFactor=0.7;
        [b addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(keyUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        UIPanGestureRecognizer *drag=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(dragKey:)];
        drag.enabled=NO;[b addGestureRecognizer:drag];[drags addObject:drag];
        [self.floating addSubview:b];[keys addObject:b];
    }
    self.keyButtons=keys;self.keyDrags=drags;self.floating.buttons=keys;
    [self loadPositions];
    self.editButton=[self button:@"Move keys"];self.editButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.editButton addTarget:self action:@selector(toggleEdit) forControlEvents:UIControlEventTouchUpInside];
    [keyRow addArrangedSubview:self.editButton];
    UIButton *reset=[self button:@"Reset"];reset.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [reset addTarget:self action:@selector(resetPositions) forControlEvents:UIControlEventTouchUpInside];[keyRow addArrangedSubview:reset];
    self.remapButton=[self button:@"Remap"];self.remapButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.remapButton.showsMenuAsPrimaryAction=YES;[keyRow addArrangedSubview:self.remapButton];
    [self refreshMappings];
    UIStackView *sliders=[[UIStackView alloc]init];sliders.spacing=4;sliders.distribution=UIStackViewDistributionFillEqually;
    for(NSInteger i=0;i<2;i++){
        UISlider *s=[UISlider new];s.tag=i;s.minimumValue=i?0:0.25;s.maximumValue=i?2:3;s.value=i?self.acceleration:self.sensitivity;
        s.accessibilityLabel=i?@"Acceleration (zero disables)":@"Sensitivity";
        [s addTarget:self action:@selector(slider:) forControlEvents:UIControlEventValueChanged];
        UILabel *l=[UILabel new];l.text=i?@"Accel":@"Speed";l.textColor=UIColor.whiteColor;l.font=[UIFont systemFontOfSize:12];l.textAlignment=NSTextAlignmentCenter;
        UIStackView *column=[[UIStackView alloc]initWithArrangedSubviews:@[l,s]];column.axis=UILayoutConstraintAxisVertical;
        [sliders addArrangedSubview:column];
    }
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[pad,buttons,keyRow,sliders]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=4;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.panel addSubview:stack];
    UILayoutGuide *safe=root.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.toggle.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],[self.toggle.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[self.toggle.widthAnchor constraintEqualToConstant:80],[self.toggle.heightAnchor constraintEqualToConstant:36],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.toggle.trailingAnchor],[self.panel.bottomAnchor constraintEqualToAnchor:self.toggle.topAnchor constant:-6],[self.panel.widthAnchor constraintEqualToConstant:260],[self.panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:4],
        [stack.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:8],[stack.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-8],[stack.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:8],[stack.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-8]
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resign:) name:UIApplicationWillResignActiveNotification object:nil];
}
@end
static TCControlOverlay *tcControls;
static void tcInstallControls(void){
    if(!NSThread.isMainThread||!gRootVC.view)return;
    if(!tcControls){tcControls=[TCControlOverlay new];[tcControls install:gRootVC.view];}
    [gRootVC.view bringSubviewToFront:tcControls.floating];
    [gRootVC.view bringSubviewToFront:tcControls.panel];[gRootVC.view bringSubviewToFront:tcControls.toggle];
}
static NSUInteger tcControlPressedButtons(void){return tcOverlayMouseButtons;}
