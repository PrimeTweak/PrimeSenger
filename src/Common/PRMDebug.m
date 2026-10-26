#import "PRMDebug.h"
#import "PRMPrefs.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSUInteger kMaxLogLines = 4000;

static NSMutableArray<NSString *> *gLog = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gHookCounts = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gActionCounts = nil;
static NSMutableDictionary<NSString *, NSString *> *gStatus = nil;

// The floating button's diameter, and the glyph's point size as a fraction
// of it. Everything else is derived, so changing the diameter keeps the
// proportions intact.
static const CGFloat kFloatingSize = 50.0;
static const CGFloat kFloatingGlyphRatio = 0.38;
static const CGFloat kFloatingEdgeInset = 16.0;

// Distance from the safe area to the bottom of the host's own button, and
// the extra rise when stacking above it: its 52pt height plus a 16pt gap.
static const CGFloat kHostSlotLift = 65.0;
static const CGFloat kStackedExtra = 68.0;

// A dragged stack stays put this long after the drag ends, then glides back.
static const NSTimeInterval kReturnDelay = 4.0;
// The closest a dragged button comes to the edge of the screen.
static const CGFloat kDragEdgeInset = 4.0;

// How far the buttons were dragged from their slots, zero at rest. They move
// as one stack, so the report button stays above the settings button.
static CGPoint gStackOffset = {0.0, 0.0};
static NSUInteger gReturnGeneration = 0;

// Raised while the keyboard is showing; the floating buttons stay hidden
// meanwhile.
static BOOL gKeyboardUp = NO;

static dispatch_queue_t gQueue = nil;
static UIButton *gButton = nil;
#if PRIMESENGER_DEBUG
static UIButton *gScope = nil;
#endif

@implementation PRMDebug

// Glides the stack back to its slots. Nothing is stored: a move is meant to
// be temporary, so a relaunch also starts from the slots.
+ (void)returnButtonToSlot {
    if (CGPointEqualToPoint(gStackOffset, CGPointZero)) return;
    gStackOffset = CGPointZero;
    gReturnGeneration++;

    UIWindow *window = gButton.window;
#if PRIMESENGER_DEBUG
    if (window == nil) window = gScope.window;
#endif
    if (window == nil) return;

    [UIView animateWithDuration:0.28
                          delay:0.0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ [self layoutStackInWindow:window]; }
                     completion:nil];
    [self setStatus:[NSString stringWithFormat:@"returned to slot, y=%.0f",
                     CGRectGetMinY([self slotInWindow:window])]
             forKey:@"floating button"];
}

+ (void)initialize {
    if (self != [PRMDebug class]) return;
    gLog = [NSMutableArray array];
    gHookCounts = [NSMutableDictionary dictionary];
    gActionCounts = [NSMutableDictionary dictionary];
    gStatus = [NSMutableDictionary dictionary];
    gQueue = dispatch_queue_create("com.primesenger.debug", DISPATCH_QUEUE_SERIAL);
}

#pragma mark - Recording

+ (void)log:(NSString *)format, ... {
    if (![self recording]) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSTimeInterval stamp = [NSDate timeIntervalSinceReferenceDate];
    dispatch_async(gQueue, ^{
        [gLog addObject:[NSString stringWithFormat:@"%8.3f  %@",
                         fmod(stamp, 1000.0), line]];
        while (gLog.count > kMaxLogLines) [gLog removeObjectAtIndex:0];
    });
}

+ (void)setStatus:(NSString *)value forKey:(NSString *)name {
    if (name.length == 0) return;
    if (![self recording]) return;
    dispatch_async(gQueue, ^{
        gStatus[name] = value ?: @"(nil)";
    });
}

+ (void)noteHook:(NSString *)name {
    if (name.length == 0) return;
    if (![self recording]) return;
    dispatch_async(gQueue, ^{
        NSInteger n = gHookCounts[name].integerValue;
        gHookCounts[name] = @(n + 1);
    });
}

+ (void)noteAction:(NSString *)name {
    if (name.length == 0) return;
    if (![self recording]) return;
    dispatch_async(gQueue, ^{
        NSInteger n = gActionCounts[name].integerValue;
        gActionCounts[name] = @(n + 1);
    });
}

#pragma mark - Runtime inspection

+ (void)dumpView:(UIView *)view depth:(NSInteger)depth counter:(NSInteger *)counter {
    if (view == nil || depth > 14 || *counter > 400) return;
    (*counter)++;

    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];

    NSString *extra = @"";
    if ([view isKindOfClass:[UILabel class]]) {
        extra = [NSString stringWithFormat:@"  \"%@\"", ((UILabel *)view).text ?: @""];
    } else if ([view isKindOfClass:[UIButton class]]) {
        extra = [NSString stringWithFormat:@"  \"%@\"",
                 [(UIButton *)view titleForState:UIControlStateNormal] ?: @""];
    }
    if (view.accessibilityLabel.length > 0) {
        extra = [extra stringByAppendingFormat:@"  a11y=\"%@\"", view.accessibilityLabel];
    }

    CGRect f = view.frame;
    [self log:@"%@%@ (%.0f,%.0f %.0fx%.0f)%@%@",
              indent, NSStringFromClass([view class]),
              f.origin.x, f.origin.y, f.size.width, f.size.height,
              view.isHidden ? @" HIDDEN" : @"", extra];

    for (UIView *child in view.subviews) {
        [self dumpView:child depth:depth + 1 counter:counter];
    }
}

#pragma mark - One-shot inspection

static NSMutableSet<NSString *> *gSeenScreens = nil;
static NSMutableArray<NSString *> *gScreenOrder = nil;

+ (void)noteScreen:(NSString *)className view:(UIView *)view {
    if (className.length == 0) return;
    if (gSeenScreens == nil) {
        gSeenScreens = [NSMutableSet set];
        gScreenOrder = [NSMutableArray array];
    }
    if ([gSeenScreens containsObject:className]) return;
    [gSeenScreens addObject:className];
    [gScreenOrder addObject:className];

    [self log:@"=== screen appeared: %@ ===", className];
    if (view != nil && [self recording]) {
        NSInteger counter = 0;
        [self dumpView:view depth:1 counter:&counter];
        [self log:@"=== %ld views in %@ ===", (long)counter, className];
    }
}

#pragma mark - Presentation

+ (UIWindow *)keyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

+ (void)arm {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(applicationDidBecomeActive)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    // Becoming active fires on every interruption. The anchor resets only
    // on a return from the background.
    [center addObserver:self
               selector:@selector(applicationWillEnterForeground)
                   name:UIApplicationWillEnterForegroundNotification
                 object:nil];

    // The keyboard moves the button's slot without a screen change, so its
    // frame changes are observed directly.
    [center addObserver:self
               selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardDidHideNotification
                 object:nil];
}

// The button is hidden while the keyboard is up and returns to the same
// place afterwards. Nothing is recalculated, so nothing can drift.
+ (void)keyboardFrameChanged:(NSNotification *)note {
    CGRect final = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat screenHeight = UIScreen.mainScreen.bounds.size.height;
    BOOL up = CGRectGetMinY(final) < screenHeight - 1.0 && final.size.height > 0.0;

    if (up == gKeyboardUp) return;
    gKeyboardUp = up;

    UIButton *button = gButton;
#if PRIMESENGER_DEBUG
    UIButton *scope = gScope;
    [UIView animateWithDuration:0.2 animations:^{ scope.alpha = up ? 0.0 : 1.0; }];
#endif
    if (button == nil) return;
    [UIView animateWithDuration:0.2 animations:^{ button.alpha = up ? 0.0 : 1.0; }];
}

+ (void)applicationWillEnterForeground {
    [self returnButtonToSlot];
}

+ (void)applicationDidBecomeActive {

    // The explorer does not survive a relaunch on its own, so the stored
    // preference is reapplied once the scene is active.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self applyFlexState];
    });
    // Placed once the window exists.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self installButton];
    });
}

// Shown on demand, and whenever the Menu tab is hidden: settings live under
// that tab, so the floating button is then the only way in.
+ (BOOL)floatingButtonWanted {
    if ([PRMPrefs isEnabled:PRMKeyFloatingButton]) return YES;
    return [PRMPrefs isEnabled:PRMKeyHideTabMenu];
}

+ (void)installButton {
    [self installFloatingButton];
#if PRIMESENGER_DEBUG
    [self installScope];
#endif
}

+ (void)installFloatingButton {
    UIWindow *window = [self keyWindow];
    if (window == nil) return;
    if (![self floatingButtonWanted]) {
        [gButton removeFromSuperview];
        gButton = nil;
        return;
    }
    if (gButton.superview == window) {
        [self positionButton:gButton inWindow:window];
        [window bringSubviewToFront:gButton];
        return;
    }
    [gButton removeFromSuperview];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.bounds = CGRectMake(0.0, 0.0, kFloatingSize, kFloatingSize);

    // Drawn like the app's own floating button: a plain light circle with a
    // soft shadow, carrying the tweak's sparkles rather than a label.
    button.backgroundColor = [UIColor systemBackgroundColor];
    button.layer.cornerRadius = kFloatingSize / 2.0;
    button.tintColor = [UIColor labelColor];
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.16;
    button.layer.shadowRadius = 10.0;
    button.layer.shadowOffset = CGSizeMake(0.0, 3.0);

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration
            configurationWithPointSize:kFloatingSize * kFloatingGlyphRatio
                                weight:UIImageSymbolWeightSemibold];
    UIImage *glyph = [UIImage systemImageNamed:@"sparkles" withConfiguration:configuration];
    [button setImage:glyph forState:UIControlStateNormal];

    button.accessibilityLabel = @"PrimeSenger";
    [button addTarget:self action:@selector(openSettings)
     forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];

    button.alpha = 0.0;
    [window addSubview:button];
    gButton = button;

    [self positionButton:button inWindow:window];
}

// Two fixed slots above the tab bar: the host's own floating button slot,
// or stacked above it while the Meta AI button is still shown.
+ (CGRect)slotInWindow:(UIWindow *)window {
    CGFloat trailing = window.bounds.size.width - window.safeAreaInsets.right
                     - kFloatingEdgeInset - kFloatingSize;
    CGFloat lift = window.safeAreaInsets.bottom + kHostSlotLift;

    // Only one condition moves it: the host being hidden by its switch.
    if (![PRMPrefs isEnabled:PRMKeyHideMetaAIButton]) lift += kStackedExtra;

    return CGRectMake(trailing,
                      window.bounds.size.height - lift - kFloatingSize,
                      kFloatingSize, kFloatingSize);
}

// The report button's slot: above the settings button while it shows, in the
// settings button's slot otherwise.
+ (CGRect)scopeSlotInWindow:(UIWindow *)window {
    CGRect slot = [self slotInWindow:window];
    if (gButton.superview != window) return slot;
    return CGRectOffset(slot, 0.0, -kStackedExtra);
}

// Both buttons at their slots, shifted together by the current drag.
+ (void)layoutStackInWindow:(UIWindow *)window {
    if (gButton.superview == window) {
        gButton.frame = CGRectOffset([self slotInWindow:window], gStackOffset.x, gStackOffset.y);
    }
#if PRIMESENGER_DEBUG
    if (gScope.superview == window) {
        gScope.frame = CGRectOffset([self scopeSlotInWindow:window], gStackOffset.x, gStackOffset.y);
    }
#endif
}

+ (void)positionButton:(UIView *)button inWindow:(UIWindow *)window {
    [self layoutStackInWindow:window];
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                              UIViewAutoresizingFlexibleTopMargin;

    if (button.alpha < 1.0 && !gKeyboardUp) {
        [UIView animateWithDuration:0.18 animations:^{ button.alpha = 1.0; }];
    }
    if (!CGPointEqualToPoint(gStackOffset, CGPointZero)) return;
    [self setStatus:[NSString stringWithFormat:@"%@ slot, y=%.0f",
                     [PRMPrefs isEnabled:PRMKeyHideMetaAIButton] ? @"host" : @"stacked",
                     CGRectGetMinY([self slotInWindow:window])]
             forKey:@"floating button"];
}

// The offset that keeps every button on screen, a few points from the edge.
+ (CGPoint)clampedOffset:(CGPoint)offset inWindow:(UIWindow *)window {
    CGRect rest = CGRectNull;
    if (gButton.superview == window) rest = CGRectUnion(rest, [self slotInWindow:window]);
#if PRIMESENGER_DEBUG
    if (gScope.superview == window) rest = CGRectUnion(rest, [self scopeSlotInWindow:window]);
#endif
    if (CGRectIsNull(rest)) return CGPointZero;

    CGRect area = CGRectInset(window.bounds, kDragEdgeInset, kDragEdgeInset);
    offset.x = MAX(CGRectGetMinX(area) - CGRectGetMinX(rest),
                   MIN(CGRectGetMaxX(area) - CGRectGetMaxX(rest), offset.x));
    offset.y = MAX(CGRectGetMinY(area) - CGRectGetMinY(rest),
                   MIN(CGRectGetMaxY(area) - CGRectGetMaxY(rest), offset.y));
    return offset;
}

// Either button drags the whole stack, which glides back to its slots a few
// seconds after the last drag ends. A new drag restarts the wait.
+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = pan.view.window;
    if (window == nil) return;
    if (pan.state == UIGestureRecognizerStateBegan) gReturnGeneration++;

    CGPoint delta = [pan translationInView:window];
    [pan setTranslation:CGPointZero inView:window];
    gStackOffset = [self clampedOffset:CGPointMake(gStackOffset.x + delta.x, gStackOffset.y + delta.y)
                              inWindow:window];
    [self layoutStackInWindow:window];

    UIGestureRecognizerState state = pan.state;
    if (state != UIGestureRecognizerStateEnded && state != UIGestureRecognizerStateCancelled) return;
    if (CGPointEqualToPoint(gStackOffset, CGPointZero)) return;

    [self setStatus:[NSString stringWithFormat:@"moved by hand, back in %.0f s", kReturnDelay]
             forKey:@"floating button"];
    NSUInteger mine = ++gReturnGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kReturnDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (mine == gReturnGeneration) [self returnButtonToSlot];
    });
}


#pragma mark - Recording

+ (BOOL)recording {
#if PRIMESENGER_DEBUG
    return [PRMPrefs isEnabled:PRMKeyDebugEnabled];
#else
    return NO;
#endif
}

+ (NSDictionary<NSString *, NSNumber *> *)actionCounts {
    __block NSDictionary *copy = nil;
    dispatch_sync(gQueue, ^{ copy = [gActionCounts copy]; });
    return copy ?: @{};
}

+ (NSDictionary<NSString *, NSString *> *)statusLines {
    __block NSDictionary *copy = nil;
    dispatch_sync(gQueue, ^{ copy = [gStatus copy]; });
    return copy ?: @{};
}

+ (NSString *)logText {
    __block NSString *text = nil;
    dispatch_sync(gQueue, ^{ text = [gLog componentsJoinedByString:@"\n"]; });
    return text ?: @"";
}

+ (void)resetCounts {
    dispatch_sync(gQueue, ^{
        [gHookCounts removeAllObjects];
        [gActionCounts removeAllObjects];
        [gStatus removeAllObjects];
        [gLog removeAllObjects];
    });
}


#if PRIMESENGER_DEBUG
// White on near-black, like PrimeFreeBird's, so it never reads as the settings button.
+ (void)installScope {
    UIWindow *window = [self keyWindow];
    if (window == nil) return;
    if (![self recording]) {
        [gScope removeFromSuperview];
        gScope = nil;
        return;
    }
    if (gScope.superview != window) {
        [gScope removeFromSuperview];
        UIButton *scope = [UIButton buttonWithType:UIButtonTypeSystem];
        scope.bounds = CGRectMake(0.0, 0.0, kFloatingSize, kFloatingSize);
        scope.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.82];
        scope.layer.cornerRadius = kFloatingSize / 2.0;
        scope.layer.borderWidth = 1.0;
        scope.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        scope.tintColor = [UIColor whiteColor];
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:kFloatingSize * kFloatingGlyphRatio
                                                            weight:UIImageSymbolWeightSemibold];
        [scope setImage:[UIImage systemImageNamed:@"stethoscope" withConfiguration:configuration]
               forState:UIControlStateNormal];
        scope.accessibilityLabel = @"Compatibility report";
        [scope addTarget:self action:@selector(openCompatibilityReport)
        forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *hold =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHold:)];
        hold.minimumPressDuration = 0.6;
        [scope addGestureRecognizer:hold];
        [scope addGestureRecognizer:
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
        [window addSubview:scope];
        gScope = scope;
    }
    [self positionScope];
    [window bringSubviewToFront:gScope];
}

// Stacked above the settings button when it is showing, in its slot otherwise.
+ (void)positionScope {
    UIButton *scope = gScope;
    UIWindow *window = scope.window;
    if (window == nil) return;
    [self layoutStackInWindow:window];
    scope.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    scope.alpha = gKeyboardUp ? 0.0 : 1.0;
}

+ (void)handleHold:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    BOOL next = ![PRMPrefs isEnabled:PRMKeyFlexEnabled];
    [PRMPrefs setEnabled:next forKey:PRMKeyFlexEnabled];
    [self applyFlexState];
}
#endif

@end

