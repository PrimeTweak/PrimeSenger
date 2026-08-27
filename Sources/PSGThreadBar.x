// Manual read receipt control.
//
// While Read receipts are hidden and manual mode is on, an eye is placed
// beside the call buttons. Tapping it opens the one-shot gate and invokes
// the receipt on the live message list.
//
// Measured layout of the thread bar:
//   MDSNavigationBarView            x0   440x44  tint 0.00/0.39/0.82
//     MSGNavigationThreadViewTitleView x16 364x44 tint 0.69/0.25/0.13
//       UIStackView                  x305  80x36
//         LSRTCCallButton            x305  36x36  audio
//         LSRTCCallButton            x349  36x36  video
//     UIStackView                    x388  36x44  tint 0.00/0.39/0.82
//       MSGIconBarButtonItemView            bar items
//
// The call buttons live in a stack inside the title view, not among the bar
// items, and take their tint from that view. An item added through
// navigationItem lands in the trailing stack instead, which is why it sat
// at x388 in the bar's own blue. The eye joins the call button stack, so
// position and tint both come from the host.
//
// Signatures taken from the binary:
//   -[MSGThreadViewController viewDidLoad]                         v16@0:8
//   -[MSGThreadViewController viewDidLayoutSubviews]               v16@0:8
//   -[MSGMessageListViewController _notifyObserversDidSetAsRead:]  v20@0:8B16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kPSGEyeTarget = &kPSGEyeTarget;
static const NSInteger kPSGEyeTag = 0x50534701;

// Matches the call buttons exactly.
static const CGFloat kPSGEyeSide = 36.0;
static const CGFloat kPSGEyeGlyph = 19.0;

#pragma mark - Lookups

static UIViewController *PSGMessageListIn(UIViewController *root, NSInteger depth) {
    if (root == nil || depth > 6) return nil;
    if ([NSStringFromClass([root class]) isEqualToString:@"MSGMessageListViewController"]) {
        return root;
    }
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *found = PSGMessageListIn(child, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

static BOOL PSGOnScreen(UIView *view) {
    if (view.window == nil) return NO;
    for (UIView *node = view; node != nil; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) return NO;
    }
    return YES;
}

// The stack holding the call buttons. Identified by its contents rather
// than its position, so it survives a different button set.
static UIStackView *PSGCallButtonStack(UIView *root, NSInteger depth) {
    if (root == nil || depth > 16) return nil;

    if ([root isKindOfClass:[UIStackView class]] && PSGOnScreen(root)) {
        for (UIView *child in ((UIStackView *)root).arrangedSubviews) {
            if ([NSStringFromClass([child class])
                 rangeOfString:@"RTCCallButton"].location != NSNotFound) {
                return (UIStackView *)root;
            }
        }
    }
    for (UIView *child in root.subviews) {
        UIStackView *found = PSGCallButtonStack(child, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

#pragma mark - Target

@interface PSGReceiptEye : NSObject
@property (nonatomic, weak) UIViewController *host;
@end

@implementation PSGReceiptEye

- (void)tapped:(UIButton *)button {
    UIViewController *list = PSGMessageListIn(self.host, 0);
    BOOL sent = [PSGReadReceipts sendReceiptOn:list];

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:sent ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleRigid];
    [haptic impactOccurred];

    // Dimmed rather than recoloured, so the inherited tint is kept.
    if (sent) {
        [UIView animateWithDuration:0.2 animations:^{ button.alpha = 0.4; }];
    }
    [PRMDebug noteAction:@"manual receipt"];
}

@end

#pragma mark - Placement

static BOOL PSGEyeWanted(void) {
    return ![PRMPrefs isEnabled:PRMKeyMasterDisable]
        && [PRMPrefs isEnabled:PRMKeyReadAnonymously]
        && [PRMPrefs isEnabled:PRMKeyReadReceiptsManual];
}

// No tintColor is set: the button inherits the title view's, as the call
// buttons beside it do.
static UIButton *PSGMakeEyeButton(PSGReceiptEye *eye) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kPSGEyeGlyph
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:@"eye.fill" withConfiguration:configuration];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kPSGEyeTag;
    button.accessibilityLabel = @"Mark as seen";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:kPSGEyeSide].active = YES;
    [button.heightAnchor constraintEqualToConstant:kPSGEyeSide].active = YES;
    [button addTarget:eye action:@selector(tapped:)
     forControlEvents:UIControlEventTouchUpInside];

    if (glyph != nil) {
        [button setImage:glyph forState:UIControlStateNormal];
    } else {
        [PRMDebug log:@"eye.fill unavailable, falling back to text"];
        [button setTitle:@"Seen" forState:UIControlStateNormal];
    }
    return button;
}

static void PSGSyncEye(UIViewController *host, NSString *pass) {
    UIView *root = host.viewIfLoaded.window;
    if (root == nil) return;

    UIStackView *stack = PSGCallButtonStack(root, 0);
    UIButton *existing = stack ? (UIButton *)[stack viewWithTag:kPSGEyeTag] : nil;

    if (!PSGEyeWanted()) {
        [existing removeFromSuperview];
        objc_setAssociatedObject(host, kPSGEyeTarget, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (stack == nil) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"call button stack not found at %@", pass]
                     forKey:@"thread bar"];
        return;
    }

    if (existing != nil) {
        existing.alpha = 1.0;
        return;
    }

    PSGReceiptEye *eye = [[PSGReceiptEye alloc] init];
    eye.host = host;
    UIButton *button = PSGMakeEyeButton(eye);

    // Held by the controller: the stack only retains the view.
    objc_setAssociatedObject(host, kPSGEyeTarget, eye, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Index 0 places it before the call buttons.
    [stack insertArrangedSubview:button atIndex:0];

    [PRMDebug noteHook:@"manual receipt"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"joined call stack at %@, %lu buttons",
                         pass, (unsigned long)stack.arrangedSubviews.count]
                 forKey:@"thread bar"];
}

#pragma mark - Hooks

%hook MSGThreadViewController

- (void)viewDidLoad {
    %orig;
    PSGSyncEye((UIViewController *)self, @"viewDidLoad");
}

// The title view is built during layout, so the stack only exists here.
- (void)viewDidLayoutSubviews {
    %orig;
    PSGSyncEye((UIViewController *)self, @"layout");
}

%end
