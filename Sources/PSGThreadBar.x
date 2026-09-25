// The manual read receipt eye, placed in the call button stack so its
// position and tint come from the host. Tapping it sends one receipt.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"
#import "PSGSilence.h"
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
    return [PRMPrefs isEnabled:PRMKeyReadAnonymously];
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

// The eye is rebuilt when the bar rebuilds, so it is placed again on every
// pass rather than assumed to persist.
#pragma mark - Placement

// Inherits the title view's tint like the call buttons; struck through
// when manual sending is off.
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
        [button setTitle:allowed ? @"Seen" : @"\u2014" forState:UIControlStateNormal];
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

#pragma mark - Bell

static const NSInteger kPSGBellTag = 0x50534702;
static const char kPSGBellTarget;

// The thread key of the host, as the string PSGSilence keys on.
static NSString *PSGThreadIdentifier(UIViewController *host) {
    if (![host respondsToSelector:@selector(threadQueryKey)]) return nil;
    id key = ((id (*)(id, SEL))objc_msgSend)(host, @selector(threadQueryKey));
    return [PSGSilence identifierForThreadKey:key];
}

@interface PSGSilenceBell : NSObject
@property (nonatomic, weak) UIViewController *host;
@end

static void PSGApplyBellGlyph(UIButton *button, BOOL silenced) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kPSGEyeGlyph
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:silenced ? @"bell.slash.fill" : @"bell.fill"
                            withConfiguration:configuration];
    if (glyph != nil) {
        [button setImage:glyph forState:UIControlStateNormal];
    } else {
        [button setTitle:silenced ? @"Off" : @"On" forState:UIControlStateNormal];
    }
    button.alpha = silenced ? 1.0 : 0.45;
}

@implementation PSGSilenceBell

- (void)tapped:(UIButton *)button {
    NSString *identifier = PSGThreadIdentifier(self.host);
    if (identifier == nil) {
        [PRMDebug setStatus:@"bell: no thread key on host" forKey:@"silence bell"];
        UIImpactFeedbackGenerator *refuse = [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleRigid];
        [refuse impactOccurred];
        return;
    }
    BOOL next = ![PSGSilence isSilenced:identifier];
    [PSGSilence setSilenced:next identifier:identifier];
    PSGApplyBellGlyph(button, next);
    [PRMDebug noteAction:@"silence bell"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ -> %@ (%lu silenced)",
                         identifier, next ? @"silenced" : @"restored",
                         (unsigned long)[PSGSilence count]]
                 forKey:@"silence bell"];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

@end

static UIButton *PSGMakeBellButton(PSGSilenceBell *bell) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kPSGBellTag;
    button.accessibilityLabel = @"Silence this chat";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:kPSGEyeSide].active = YES;
    [button.heightAnchor constraintEqualToConstant:kPSGEyeSide].active = YES;
    [button addTarget:bell action:@selector(tapped:)
     forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// Placed the way the eye is, in the same stack, and kept in step with the
// stored list so a chat silenced elsewhere shows the crossed bell here.
static void PSGSyncBell(UIViewController *host, NSString *pass) {
    UIView *root = host.viewIfLoaded.window;
    if (root == nil) return;

    UIStackView *stack = PSGCallButtonStack(root, 0);
    UIButton *existing = stack ? (UIButton *)[stack viewWithTag:kPSGBellTag] : nil;

    BOOL wanted = [PRMPrefs isEnabled:PRMKeySilencedChats];
    if (!wanted) {
        [existing removeFromSuperview];
        objc_setAssociatedObject(host, &kPSGBellTarget, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (stack == nil) return;

    NSString *identifier = PSGThreadIdentifier(host);
    BOOL silenced = [PSGSilence isSilenced:identifier];

    if (existing != nil) {
        PSGApplyBellGlyph(existing, silenced);
        return;
    }

    PSGSilenceBell *bell = [[PSGSilenceBell alloc] init];
    bell.host = host;
    UIButton *button = PSGMakeBellButton(bell);
    objc_setAssociatedObject(host, &kPSGBellTarget, bell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PSGApplyBellGlyph(button, silenced);

    // After the eye when it is there, first otherwise.
    NSInteger index = [stack viewWithTag:kPSGEyeTag] != nil ? 1 : 0;
    [stack insertArrangedSubview:button atIndex:index];

    [PRMDebug noteHook:@"silence bell"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"placed at %@ | key %@ | %@",
                         pass, identifier ?: @"NONE", silenced ? @"silenced" : @"open"]
                 forKey:@"silence bell"];
}

static void PSGSyncEye(UIViewController *host, NSString *pass) {
    (void)pass;
    UIView *root = host.viewIfLoaded.window;
    if (root == nil) return;

    UIStackView *stack = PSGCallButtonStack(root, 0);
    UIButton *existing = stack ? (UIButton *)[stack viewWithTag:kPSGEyeTag] : nil;

    if (!PSGEyeWanted()) {
        [existing removeFromSuperview];
        objc_setAssociatedObject(host, kPSGEyeTarget, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (stack == nil) return;

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
}

#pragma mark - Hooks

%hook MSGThreadViewController

- (void)viewDidLoad {
    %orig;
    PSGSyncEye((UIViewController *)self, @"viewDidLoad");
    PSGSyncBell((UIViewController *)self, @"viewDidLoad");
}

// The title view is built during layout, so the stack only exists here.
- (void)viewDidLayoutSubviews {
    %orig;
    PSGSyncEye((UIViewController *)self, @"layout");
    PSGSyncBell((UIViewController *)self, @"layout");
}

%end

// The host drops the eye whenever it rebuilds its bar, so it is placed
// again in the same pass; the layout hook above is a fallback.
%hook MSGThreadViewNavBarManager

- (void)updateRightBarButtonItems {
    %orig;

    // Inserting an arranged subview lays the bar out again, and the host may
    // answer that by rebuilding its items. The flag keeps that from becoming
    // a cycle.
    static BOOL syncing = NO;
    if (syncing) return;

    // The hooked class is forward-declared, so self is held as id.
    id manager = self;
    if (![manager respondsToSelector:@selector(delegate)]) return;
    id owner = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(delegate));
    if (![owner isKindOfClass:[UIViewController class]]) return;

    syncing = YES;
    PSGSyncEye((UIViewController *)owner, @"navbar");
    PSGSyncBell((UIViewController *)owner, @"navbar");
    syncing = NO;
}

%end
