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
//   -[MSGThreadViewNavBarManager updateRightBarButtonItems]        v16@0:8
//   -[MSGThreadViewNavBarManager delegate]                         @16@0:8

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

#pragma mark - State

// The switch decides whether receipts are blocked; the eye is shown for as
// long as they are. The pill only decides whether a receipt can still be
// sent by hand, which the glyph reflects.
static BOOL PSGEyeWanted(void) {
    return ![PRMPrefs isEnabled:PRMKeyMasterDisable]
        && [PRMPrefs isEnabled:PRMKeyReadAnonymously];
}

// True for both pill states that can send a receipt. On reply sends one by
// itself when a message goes out, and the eye stays available on top of that
// for the chats where nothing is sent.
static BOOL PSGManualAllowed(void) {
    return [PRMPrefs isEnabled:PRMKeyReadReceiptsManual]
        || [PRMPrefs isEnabled:PRMKeyReadOnReply];
}

#pragma mark - Target

@interface PSGReceiptEye : NSObject
@property (nonatomic, weak) UIViewController *host;
@end

@implementation PSGReceiptEye

- (void)tapped:(UIButton *)button {
    if (!PSGManualAllowed()) {
        UIImpactFeedbackGenerator *refuse = [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleRigid];
        [refuse impactOccurred];
        return;
    }

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

#pragma mark - Insertion trace

// Why the eye is recreated, measured in one pass rather than one build per
// hypothesis. Each insertion records which controller asked, which stack it
// landed in, and what became of the eye inserted before it.
//
// A short identifier stands in for each object so the trace reads without
// pointers. Addresses are only ever compared, never dereferenced, so an
// identifier survives its object. An address freed and reused would collapse
// two objects onto one identifier: within a single conversation the
// controller stays alive throughout, so the reading holds there.
static NSUInteger PSGIdentifierFor(id object,
                                   NSMutableDictionary<NSNumber *, NSNumber *> *table) {
    if (object == nil) return 0;
    NSNumber *address = @((unsigned long long)(uintptr_t)object);
    NSNumber *known = table[address];
    if (known != nil) return known.unsignedIntegerValue;
    NSUInteger next = table.count + 1;
    table[address] = @(next);
    return next;
}

// The eye inserted last time, held weakly so the trace never keeps a view
// alive and never reports a dead one as present.
static __weak UIButton *gPreviousEye = nil;

// detached  the host dropped it, so the stack was rebuilt or emptied
// other     it is still on screen in a different stack, so the search moved
// same      it is in the stack being written to, which the tag test should
//           have caught, so the tag was lost
static NSString *PSGPreviousEyeState(UIStackView *stack) {
    UIButton *previous = gPreviousEye;
    if (previous == nil) return @"none";
    if (previous.superview == nil) return @"detached";
    if (previous.superview == stack) return @"same";
    return @"other";
}

#pragma mark - Placement

// No tintColor is set: the button inherits the title view's, as the call
// buttons beside it do.
// Struck through when manual sending is off, so the state reads without
// opening settings.
static void PSGApplyEyeGlyph(UIButton *button) {
    BOOL allowed = PSGManualAllowed();
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kPSGEyeGlyph
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:allowed ? @"eye.fill" : @"eye.slash.fill"
                            withConfiguration:configuration];
    if (glyph != nil) {
        [button setImage:glyph forState:UIControlStateNormal];
    } else {
        [button setTitle:allowed ? @"Seen" : @"—" forState:UIControlStateNormal];
    }
    button.alpha = allowed ? 1.0 : 0.45;
}

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
        PSGApplyEyeGlyph(existing);
        return;
    }

    PSGReceiptEye *eye = [[PSGReceiptEye alloc] init];
    eye.host = host;
    UIButton *button = PSGMakeEyeButton(eye);

    // Held by the controller: the stack only retains the view.
    objc_setAssociatedObject(host, kPSGEyeTarget, eye, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    PSGApplyEyeGlyph(button);

    // Index 0 places it before the call buttons.
    [stack insertArrangedSubview:button atIndex:0];

    [PRMDebug noteHook:@"manual receipt"];

    static NSUInteger insertions = 0;
    static NSMutableDictionary<NSNumber *, NSNumber *> *hostIds = nil;
    static NSMutableDictionary<NSNumber *, NSNumber *> *stackIds = nil;
    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) {
        hostIds = [NSMutableDictionary dictionary];
        stackIds = [NSMutableDictionary dictionary];
        trace = [NSMutableArray array];
    }

    // Read before the new eye replaces it.
    NSString *previous = PSGPreviousEyeState(stack);
    gPreviousEye = button;
    insertions++;

    [trace addObject:[NSString stringWithFormat:@"h%lu/s%lu/%@/%@",
                      (unsigned long)PSGIdentifierFor(host, hostIds),
                      (unsigned long)PSGIdentifierFor(stack, stackIds),
                      previous, pass]];
    while (trace.count > 8) [trace removeObjectAtIndex:0];

    // One line carries the whole measurement: how many insertions, how many
    // distinct controllers and stacks were seen, and the last eight in order.
    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"%lu ins | %lu hosts | %lu stacks | %lu buttons | %@",
                         (unsigned long)insertions,
                         (unsigned long)hostIds.count,
                         (unsigned long)stackIds.count,
                         (unsigned long)stack.arrangedSubviews.count,
                         [trace componentsJoinedByString:@" "]]
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

// Measured: the host rebuilds its bar items 25 times across three
// conversations and the eye was recreated 25 times, one for one. Every
// rebuild drops it, and putting it back from viewDidLayoutSubviews puts it
// back a frame later, which is the flash.
//
// Placing it from here runs it in the same pass as the rebuild. The layout
// pass above is kept as a net for anything this does not reach, so the worst
// case is the behaviour that was already shipping.
//
// This selector is hooked in PSGThreadProbe.x as well, which only reads.
// Both chain through %orig and neither depends on running first.
%hook MSGThreadViewNavBarManager

- (void)updateRightBarButtonItems {
    %orig;

    // Inserting an arranged subview lays the bar out again, and the host may
    // answer that by rebuilding its items. The flag keeps that from becoming
    // a cycle.
    static BOOL syncing = NO;
    if (syncing) return;

    // Logos declares the hooked class forward only, so self carries an
    // incomplete type and cannot be messaged. It is held as id first; every
    // send then goes through that, as the probe already does.
    id manager = self;
    if (![manager respondsToSelector:@selector(delegate)]) return;
    id owner = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(delegate));
    if (![owner isKindOfClass:[UIViewController class]]) return;

    syncing = YES;
    PSGSyncEye((UIViewController *)owner, @"navbar");
    syncing = NO;
}

%end
