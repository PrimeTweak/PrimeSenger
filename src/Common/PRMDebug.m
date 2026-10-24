#import "PRMDebug.h"
#import "PRMPrefs.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSUInteger kMaxLogLines = 4000;

static NSMutableArray<NSString *> *gLog = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gHookCounts = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gActionCounts = nil;
static NSMutableDictionary<NSString *, NSString *> *gStatus = nil;
static BOOL gButtonMoved = NO;

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


// Frame set by dragging. Reapplied when the button is rebuilt.
static CGRect gButtonFrame = {{0.0, 0.0}, {0.0, 0.0}};

// Raised while the keyboard is showing; the floating buttons stay hidden
// meanwhile.
static BOOL gKeyboardUp = NO;

static dispatch_queue_t gQueue = nil;
static UIButton *gButton = nil;
#if PRIMESENGER_DEBUG
static UIButton *gScope = nil;
#endif

@implementation PRMDebug

// A dragged button holds its place until the screen changes, then glides
// back to its slot. Nothing is stored: the move is meant to be temporary.
+ (void)returnButtonToSlot {
    if (!gButtonMoved) return;
    gButtonMoved = NO;
    gButtonFrame = CGRectZero;

    UIButton *button = gButton;
    UIWindow *window = button.window;
    if (window == nil) return;

    CGRect slot = [self slotInWindow:window];
    if (CGRectEqualToRect(slot, button.frame)) return;

    [UIView animateWithDuration:0.28
                          delay:0.0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ button.frame = slot; }
                     completion:^(BOOL finished) {
#if PRIMESENGER_DEBUG
        [self positionScope];
#endif
    }];
    [self setStatus:[NSString stringWithFormat:@"returned to slot, y=%.0f",
                     CGRectGetMinY(slot)]
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
        if (!gButtonMoved) [self positionButton:gButton inWindow:window];
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

+ (void)positionButton:(UIView *)button inWindow:(UIWindow *)window {
    // A dragged button keeps its place until +returnButtonToSlot glides it
    // back. Nothing is stored, so a relaunch starts from the slot.
    if (gButtonMoved && !CGRectIsEmpty(gButtonFrame)) {
        button.frame = gButtonFrame;
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                  UIViewAutoresizingFlexibleTopMargin;
        [self setStatus:[NSString stringWithFormat:@"moved by hand, y=%.0f",
                         CGRectGetMinY(gButtonFrame)]
                 forKey:@"floating button"];
        if (button.alpha < 1.0 && !gKeyboardUp) {
            [UIView animateWithDuration:0.18 animations:^{ button.alpha = 1.0; }];
        }
        return;
    }

    CGRect slot = [self slotInWindow:window];
    if (!CGRectEqualToRect(slot, button.frame)) button.frame = slot;
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                              UIViewAutoresizingFlexibleTopMargin;

    if (button.alpha < 1.0 && !gKeyboardUp) {
        [UIView animateWithDuration:0.18 animations:^{ button.alpha = 1.0; }];
    }
    [self setStatus:[NSString stringWithFormat:@"%@ slot, y=%.0f",
                     [PRMPrefs isEnabled:PRMKeyHideMetaAIButton] ? @"host" : @"stacked",
                     CGRectGetMinY(slot)]
             forKey:@"floating button"];
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    if (view == nil || view.superview == nil) return;
    // A dragged button is not repositioned until the next foreground.
    gButtonMoved = YES;
    CGPoint delta = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + delta.x, view.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:view.superview];
    gButtonFrame = view.frame;
#if PRIMESENGER_DEBUG
    [self positionScope];
#endif
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
    BOOL stacked = gButton.superview == window;
    CGRect anchor = stacked ? gButton.frame : [self slotInWindow:window];
    CGFloat lift = stacked ? kStackedExtra : 0.0;
    scope.frame = CGRectMake(CGRectGetMinX(anchor), CGRectGetMinY(anchor) - lift,
                             kFloatingSize, kFloatingSize);
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

