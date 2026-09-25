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

// Raised while the keyboard is showing; the button then waits above it.
static BOOL gKeyboardUp = NO;



static dispatch_queue_t gQueue = nil;
static UIButton *gButton = nil;

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
                     completion:nil];
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

+ (void)dumpCollection:(id)collection label:(NSString *)label {
    if (![self recording]) return;
    if (![collection respondsToSelector:@selector(count)]) {
        [self log:@"%@: not a collection (%@)", label,
                  NSStringFromClass([collection class])];
        return;
    }

    NSArray *items = nil;
    if ([collection isKindOfClass:[NSArray class]]) {
        items = collection;
    } else if ([collection respondsToSelector:@selector(allObjects)]) {
        items = [collection allObjects];
    }
    if (items == nil) return;

    NSCountedSet *kinds = [NSCountedSet set];
    for (id item in items) [kinds addObject:NSStringFromClass([item class])];

    [self log:@"%@: %lu items", label, (unsigned long)items.count];
    for (NSString *kind in kinds) {
        [self log:@"    %ld x %@", (long)[kinds countForObject:kind], kind];
    }
}

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

#pragma mark - Report

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
    NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
    [centre addObserver:self
               selector:@selector(applicationDidBecomeActive)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    // Becoming active fires on every interruption. The anchor resets only
    // on a return from the background.
    [centre addObserver:self
               selector:@selector(applicationWillEnterForeground)
                   name:UIApplicationWillEnterForegroundNotification
                 object:nil];

    // The keyboard moves the button's slot without a screen change, so its
    // frame changes are observed directly.
    [centre addObserver:self
               selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];
    [centre addObserver:self
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

// Shown while recording, and whenever the Menu tab is hidden: settings live
// under that tab, so the button is then the only way in.
+ (BOOL)floatingButtonWanted {
    if ([self recording]) return YES;
    return [PRMPrefs isEnabled:PRMKeyHideTabMenu];
}

+ (void)installButton {
    UIWindow *window = [self keyWindow];
    if (window == nil) return;
    if (![self floatingButtonWanted]) {
        [gButton removeFromSuperview];
        gButton = nil;
        return;
    }
    NSString *wantedLabel = [self recording] ? @"Compatibility report" : @"PrimeSenger";
    if (gButton.superview == window && [gButton.accessibilityLabel isEqualToString:wantedLabel]) {
        if (!gButtonMoved) [self positionButton:gButton inWindow:window];
        [window bringSubviewToFront:gButton];
        return;
    }



    [gButton removeFromSuperview];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.bounds = CGRectMake(0.0, 0.0, kFloatingSize, kFloatingSize);

    // Drawn like the app's own floating button: a plain light circle with a
    // soft shadow, carrying the tweak's bolt rather than a label.
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
    NSString *symbol = [self recording] ? @"stethoscope" : @"bolt.fill";
    UIImage *glyph = [UIImage systemImageNamed:symbol withConfiguration:configuration];
    if (glyph != nil) {
        [button setImage:glyph forState:UIControlStateNormal];
    } else {
        button.titleLabel.font =
            [UIFont monospacedSystemFontOfSize:kFloatingSize * 0.29
                                        weight:UIFontWeightSemibold];
        [button setTitle:@"PS" forState:UIControlStateNormal];
    }

    button.accessibilityLabel = wantedLabel;
    [button addTarget:self action:@selector(buttonTapped)
     forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];

#if PRIMESENGER_DEBUG
    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.6;
    [button addGestureRecognizer:hold];
#endif

    button.alpha = 0.0;
    [window addSubview:button];
    gButton = button;

    [self positionButton:button inWindow:window];
}


// Locates the host's floating button for relative placement. The depth
// limit covers the deepest position it has been observed at.

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
    // A button the user has dragged keeps its place, across screens and
    // across launches.
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

+ (void)buttonTapped {
#if PRIMESENGER_DEBUG
    if ([self recording]) {
        [self openCompatibilityReport];
        return;
    }
#endif
    [self openSettings];
}

#if PRIMESENGER_DEBUG
+ (void)handleHold:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    BOOL next = ![PRMPrefs isEnabled:PRMKeyFlexEnabled];
    [PRMPrefs setEnabled:next forKey:PRMKeyFlexEnabled];
    [self applyFlexState];
}
#endif

@end

