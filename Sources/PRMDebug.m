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

// Frame set by dragging. Reapplied when the button is rebuilt.
static CGRect gButtonFrame = {{0.0, 0.0}, {0.0, 0.0}};

// Set once a placement against the host's own floating button has
// succeeded. It gates the first reveal so the button is never seen moving
// into position; it does not stop later placements, or the button would
// keep a stale slot for the rest of the session.
static BOOL gButtonSettled = NO;

// Held strongly while observed: key-value observing does not survive the
// observed object being released, and a weak reference would leave a
// registration on a dead layer. Released as soon as the host changes.
// Following the host in the same render pass replaces the delayed placement
// that produced a bounce on tab changes and a moment of overlap when the
// keyboard left.
static UIView *gObservedHost = nil;

// Key-value observing takes an NSObject, and self in a class method is a
// Class. One instance stands in and hands each change back.
@interface PRMHostWatcher : NSObject
@end

static PRMHostWatcher *gHostWatcher = nil;

static dispatch_queue_t gQueue = nil;
static UIButton *gButton = nil;

// Design system components whose availability decides how the settings
// screen can be built.
static NSString *const kComponents[] = {
    @"MDSLabel", @"MDSButton", @"MDSButtonConfig", @"MDSIconButton",
    @"MDSTextField", @"MDSBadgeView", @"MDSBlurView", @"MDSBackgroundView",
    @"MDSToolbar", @"MDSSegmentedControl", @"MDSNavigationController",
    @"MDSAvatarView", @"MDSThemedTabBar", @"MDSTabBarItem",
};
static const NSUInteger kComponentCount = sizeof(kComponents) / sizeof(kComponents[0]);

// Classes the tweak hooks or intends to hook.
static NSString *const kTargets[] = {
    @"MSGSettingsViewController", @"MSGThreadListViewController",
    @"MSGThreadListDataSource", @"MSGTypingIndicatorView",
    @"MSGMessageListViewController",
                         @"MSGThreadViewController", @"MSGThreadViewNavBarManager", @"MSGStoryBucketsDataManager",
    @"LSStoryBucketViewController", @"LSComposerViewController",
    @"LSMediaViewController", @"LSRTCCallButton",
    @"_TtC15MDSModernTabBar15MDSModernTabBar",
};
static const NSUInteger kTargetCount = sizeof(kTargets) / sizeof(kTargets[0]);

@implementation PRMDebug

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
    if (![PRMPrefs isEnabled:PRMKeyDebugEnabled]) return;
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
    dispatch_async(gQueue, ^{
        gStatus[name] = value ?: @"(nil)";
    });
}

+ (void)noteHook:(NSString *)name {
    if (name.length == 0) return;
    dispatch_async(gQueue, ^{
        NSInteger n = gHookCounts[name].integerValue;
        gHookCounts[name] = @(n + 1);
    });
}

+ (void)noteAction:(NSString *)name {
    if (name.length == 0) return;
    dispatch_async(gQueue, ^{
        NSInteger n = gActionCounts[name].integerValue;
        gActionCounts[name] = @(n + 1);
    });
}

#pragma mark - Runtime inspection

+ (void)dumpCollection:(id)collection label:(NSString *)label {
    if (![PRMPrefs isEnabled:PRMKeyDebugEnabled]) return;
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

+ (void)dumpViewHierarchy {
    if (![PRMPrefs isEnabled:PRMKeyDebugEnabled]) return;
    UIWindow *window = [self keyWindow];
    if (window == nil) { [self log:@"view dump: no key window"]; return; }
    NSInteger counter = 0;
    [self log:@"--- view hierarchy ---"];
    [self dumpView:window depth:0 counter:&counter];
    [self log:@"--- %ld views ---", (long)counter];
}

#pragma mark - One-shot inspection

static NSMutableSet<NSString *> *gSeenScreens = nil;
static NSMutableArray<NSString *> *gScreenOrder = nil;

// Class-name families worth dumping in full. One scan answers every
// question a separate build would otherwise be needed to ask.
static NSString *const kScanFamilies[] = {
    @"MSGSearchBarPlaceholderProvider",
    @"MSGUniversalSearchBarCellController",
    @"MSGAvatarSearchBar",
    @"MDSSearchBar",
    @"MSGInboxRowUnit",
    @"MSGInboxRowInboxModel",
    @"MSGThreadListViewController",
    @"_TtC15MDSModernTabBar15MDSModernTabBar",
    @"MDSTabBarItem",
    @"MSGAIBotsButtonRailView",
    @"LSMediaVideoViewController",
    @"LSNetworkImageView",
    @"MSGEphemeralMediaViewController",
};
static const NSUInteger kScanFamilyCount =
    sizeof(kScanFamilies) / sizeof(kScanFamilies[0]);

// Substring patterns matched against every loaded class name.
static NSString *const kScanPatterns[] = {
    @"AIBotsEntry", @"AskMetaAI", @"MetaAIButton", @"AIHomeEntry",
    @"CTMAds", @"SponsoredRow", @"StoriesTrayRow",
};
static const NSUInteger kScanPatternCount =
    sizeof(kScanPatterns) / sizeof(kScanPatterns[0]);

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
    if (view != nil && [PRMPrefs isEnabled:PRMKeyDebugEnabled]) {
        NSInteger counter = 0;
        [self dumpView:view depth:1 counter:&counter];
        [self log:@"=== %ld views in %@ ===", (long)counter, className];
    }
}

+ (void)dumpOneClass:(NSString *)name {
    Class cls = NSClassFromString(name);
    if (cls == Nil) { [self log:@"%@: ABSENT", name]; return; }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    [self log:@"%@ : %u methods  (super %@)",
              name, count, NSStringFromClass([cls superclass]) ?: @"-"];
    for (unsigned int i = 0; i < count && i < 80; i++) {
        const char *types = method_getTypeEncoding(methods[i]);
        [self log:@"    -%@  %s", NSStringFromSelector(method_getName(methods[i])),
                  types ?: ""];
    }
    free(methods);

    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic);
    for (unsigned int i = 0; i < ic && i < 40; i++) {
        [self log:@"    ivar %s : %s",
                  ivar_getName(ivars[i]) ?: "?", ivar_getTypeEncoding(ivars[i]) ?: "?"];
    }
    free(ivars);
}

+ (void)runFullScan {
    [self log:@"########## FULL SCAN ##########"];

    [self log:@"--- named classes ---"];
    for (NSUInteger i = 0; i < kScanFamilyCount; i++) {
        [self dumpOneClass:kScanFamilies[i]];
    }

    [self log:@"--- pattern matches across every loaded class ---"];
    unsigned int total = 0;
    Class *all = objc_copyClassList(&total);
    NSUInteger hits = 0;
    for (unsigned int i = 0; i < total; i++) {
        const char *raw = class_getName(all[i]);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        for (NSUInteger p = 0; p < kScanPatternCount; p++) {
            if ([name rangeOfString:kScanPatterns[p]].location == NSNotFound) continue;
            unsigned int mc = 0;
            Method *m = class_copyMethodList(all[i], &mc);
            free(m);
            [self log:@"    %@  (%u methods)", name, mc];
            hits++;
            break;
        }
        if (hits > 200) break;
    }
    free(all);
    [self log:@"--- %lu pattern matches, %u classes loaded ---",
              (unsigned long)hits, total];

    [self log:@"--- screens seen this session ---"];
    for (NSString *name in gScreenOrder) [self log:@"    %@", name];

    [self log:@"########## END SCAN ##########"];
}

+ (NSUInteger)copyReportToPasteboard {
    NSString *text = [self report];
    [UIPasteboard generalPasteboard].string = text;
    return text.length;
}

#pragma mark - Report

+ (NSString *)report {
    __block NSString *result = nil;
    dispatch_sync(gQueue, ^{
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"PrimeSenger 1.0.1 — debug | FLEX %@",
                          [self flexAvailable] ? @"linked" : @"NOT LINKED"]];
        [lines addObject:[NSString stringWithFormat:@"logging: %@",
                          [PRMPrefs isEnabled:PRMKeyDebugEnabled] ? @"on" : @"off"]];

        [lines addObject:@""];
        [lines addObject:@"--- status ---"];
        if (gStatus.count == 0) {
            [lines addObject:@"(nothing reported yet)"];
        } else {
            for (NSString *name in [gStatus.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                [lines addObject:[NSString stringWithFormat:@"%-26s %@",
                                  name.UTF8String, gStatus[name]]];
            }
        }

        [lines addObject:@""];
        [lines addObject:@"--- hooks fired ---"];
        NSMutableSet *every = [NSMutableSet setWithArray:gHookCounts.allKeys];
        [every addObjectsFromArray:gActionCounts.allKeys];
        if (every.count == 0) {
            [lines addObject:@"(none yet)"];
        } else {
            NSArray *names = [every.allObjects sortedArrayUsingSelector:@selector(compare:)];
            for (NSString *name in names) {
                [lines addObject:[NSString stringWithFormat:@"%-34s ran %@  acted %@",
                                  name.UTF8String,
                                  gHookCounts[name] ?: @0,
                                  gActionCounts[name] ?: @0]];
            }
        }

        [lines addObject:@""];
        [lines addObject:@"--- switches ---"];
        NSArray *keys = [PRMPrefs allKeys];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in keys) {
            id raw = [defaults objectForKey:key];
            [lines addObject:[NSString stringWithFormat:@"%-34s %@   stored:%@",
                              key.UTF8String,
                              [PRMPrefs isEnabled:key] ? @"ON" : @"off",
                              raw ? raw : @"(never written)"]];
        }

        [lines addObject:@""];
        [lines addObject:@"--- design system ---"];
        for (NSUInteger i = 0; i < kComponentCount; i++) {
            Class cls = NSClassFromString(kComponents[i]);
            unsigned int n = 0;
            if (cls) { Method *m = class_copyMethodList(cls, &n); free(m); }
            [lines addObject:[NSString stringWithFormat:@"%-24s %@",
                              kComponents[i].UTF8String,
                              cls ? [NSString stringWithFormat:@"%u methods", n] : @"ABSENT"]];
        }

        [lines addObject:@""];
        [lines addObject:@"--- hook targets ---"];
        for (NSUInteger i = 0; i < kTargetCount; i++) {
            Class cls = NSClassFromString(kTargets[i]);
            unsigned int n = 0;
            if (cls) { Method *m = class_copyMethodList(cls, &n); free(m); }
            [lines addObject:[NSString stringWithFormat:@"%-42s %@",
                              kTargets[i].UTF8String,
                              cls ? [NSString stringWithFormat:@"%u methods", n] : @"ABSENT"]];
        }

        [lines addObject:@""];
        [lines addObject:[NSString stringWithFormat:@"--- log (%lu lines) ---",
                          (unsigned long)gLog.count]];
        if (gLog.count == 0) {
            [lines addObject:@"(empty — enable logging in settings)"];
        } else {
            [lines addObjectsFromArray:gLog];
        }

        result = [lines componentsJoinedByString:@"\n"];
    });
    return result;
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

// UIDesignRequiresCompatibility makes UIKit render UIGlassEffect with the
// legacy material. It is read from the bundle so the state of the build is
// visible without inspecting the IPA.
+ (void)reportDesignMode {
    id value = [[NSBundle mainBundle]
                objectForInfoDictionaryKey:@"UIDesignRequiresCompatibility"];
    NSString *state;
    if (value == nil) {
        state = @"absent, Liquid Glass available";
    } else if ([value boolValue]) {
        state = @"true, Liquid Glass rendered as legacy material";
    } else {
        state = @"false, Liquid Glass available";
    }
    [self setStatus:state forKey:@"design compatibility"];
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

    // The keyboard moves the host's floating button without changing
    // screen, so no appearance callback fires and the placement would stay
    // where the raised keyboard left it. One notification covers showing,
    // hiding and interactive dismissal; a second catches the final state.
    [centre addObserver:self
               selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];
    [centre addObserver:self
               selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardDidHideNotification
                 object:nil];
}

// The keyboard hides the host's own button without changing screen, so a
// placement is asked for once it has finished moving. Whether it is coming
// or going does not matter: a host out of sight is left alone either way.
+ (void)keyboardFrameChanged:(NSNotification *)note {
    [self refreshFloatingButton];
}

// Reported whether or not the switch is touched, so one look at the report
// says if the vendor clone made it into the dylib.
+ (void)reportFlexPresence {
    [self setStatus:[self flexAvailable] ? @"FLEXManager present, ready"
                                         : @"FLEXManager ABSENT from the dylib"
             forKey:@"flex"];
}

+ (void)applicationWillEnterForeground {
    gButtonMoved = NO;
    gButtonFrame = CGRectZero;
    gButtonSettled = NO;
}

+ (void)applicationDidBecomeActive {
    [self reportDesignMode];
    [self reportFlexPresence];
    // A ladder rather than two fixed delays: each rung retries until the
    // host's floating button can be measured, then stops. Waiting a fixed
    // time made it arrive late; a single early pass placed it wrongly.
    for (NSNumber *delay in @[@0.0, @0.15, @0.4, @0.9, @1.8, @3.0]) {
        BOOL last = [delay isEqualToNumber:@3.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (gButtonSettled) return;
            [self installButton];
            // The host may genuinely be absent on this screen, so the last
            // rung accepts the fallback position rather than never showing.
            if (last) {
                gButtonSettled = YES;
                [UIView animateWithDuration:0.18 animations:^{ gButton.alpha = 1.0; }];
            }
        });
    }
}

// Shown when the Menu tab is hidden, or when the switch requests it.
+ (BOOL)floatingButtonWanted {
    if ([PRMPrefs isEnabled:PRMKeyFloatingButton]) return YES;
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
    if (gButton.superview == window) {
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
    UIImage *bolt = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:configuration];
    if (bolt != nil) {
        [button setImage:bolt forState:UIControlStateNormal];
    } else {
        [PRMDebug log:@"bolt.fill unavailable for the floating button"];
        button.titleLabel.font =
            [UIFont monospacedSystemFontOfSize:kFloatingSize * 0.29
                                        weight:UIFontWeightSemibold];
        [button setTitle:@"PM" forState:UIControlStateNormal];
    }

    button.accessibilityLabel = @"PrimeSenger";
    [button addTarget:self action:@selector(openSettings)
     forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];

    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.6;
    [button addGestureRecognizer:hold];

    button.alpha = 0.0;
    [window addSubview:button];
    gButton = button;

    if (gButtonMoved && !CGRectIsEmpty(gButtonFrame)) {
        button.frame = gButtonFrame;
        gButtonSettled = YES;
    } else {
        [self positionButton:button inWindow:window];
    }

    if (gButtonSettled) {
        [UIView animateWithDuration:0.18 animations:^{ button.alpha = 1.0; }];
    }
}

// Bottom trailing, clear of the tab bar when one is still on screen and
// close to the edge when every tab has been hidden.
// A view is only on screen if no ancestor is hidden. The host's floating
// button is hidden through its controller's view, so its own hidden flag
// stays NO while it is off screen.
+ (BOOL)viewIsOnScreen:(UIView *)view {
    for (UIView *node = view; node != nil; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) return NO;
    }
    return view.window != nil;
}

// Locates the host's floating button for relative placement. The depth
// limit covers the deepest position it has been observed at.
+ (UIView *)metaFloatingButtonIn:(UIView *)view depth:(NSInteger)depth {
    if (view == nil || depth > 24) return nil;
    if ([NSStringFromClass([view class]) rangeOfString:@"MetaAIFAB"].location != NSNotFound
        && view.bounds.size.width > 20.0) {
        return view;
    }
    for (UIView *child in view.subviews) {
        UIView *found = [self metaFloatingButtonIn:child depth:depth + 1];
        if (found != nil) return found;
    }
    return nil;
}

+ (void)positionButton:(UIView *)button inWindow:(UIWindow *)window {
    // The host button sits 16pt above the tab bar. The same gap is used
    // between the two buttons.
    static const CGFloat kStackGap = 16.0;

    CGFloat trailing = window.bounds.size.width - window.safeAreaInsets.right
                     - kFloatingEdgeInset - kFloatingSize;

    UIView *meta = [self metaFloatingButtonIn:window depth:0];
    [self followHost:meta];

    if (meta != nil) {
        CGRect metaFrame = [meta convertRect:meta.bounds toView:window];
        BOOL metaVisible = [self viewIsOnScreen:meta];

        // Out of sight for two unrelated reasons that call for opposite
        // actions. Hidden because the user asked means the slot is free for
        // good; hidden for any other reason is a transition, and taking a
        // slot about to be reclaimed is what made the button drift.
        BOOL hostHiddenOnPurpose = [PRMPrefs isEnabled:PRMKeyHideMetaAIButton];
        if (!metaVisible && !hostHiddenOnPurpose) {
            [self setStatus:@"host out of sight temporarily, position kept"
                     forKey:@"floating button"];
            return;
        }

        CGFloat bottom = metaVisible ? CGRectGetMinY(metaFrame) - kStackGap
                                     : CGRectGetMaxY(metaFrame);
        CGRect wanted = CGRectMake(trailing, bottom - kFloatingSize,
                                   kFloatingSize, kFloatingSize);

        if (CGRectEqualToRect(wanted, button.frame)) return;
        button.frame = wanted;
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                  UIViewAutoresizingFlexibleTopMargin;
        gButtonSettled = YES;
        if (button.alpha < 1.0) {
            [UIView animateWithDuration:0.18 animations:^{ button.alpha = 1.0; }];
        }
        [self setStatus:[NSString stringWithFormat:
                         @"%@ host at y=%.0f, host %@ y=%.0f..%.0f",
                         metaVisible ? @"stacked above" : @"took slot of",
                         CGRectGetMinY(wanted), NSStringFromClass([meta class]),
                         CGRectGetMinY(metaFrame), CGRectGetMaxY(metaFrame)]
                 forKey:@"floating button"];
        return;
    }

    // Fallback when the host button is absent: 16pt above the tab bar, or
    // near the edge when no bar remains.
    BOOL barGone = [PRMPrefs isEnabled:PRMKeyHideTabChats]
                && [PRMPrefs isEnabled:PRMKeyHideTabStories]
                && [PRMPrefs isEnabled:PRMKeyHideTabNotifications]
                && [PRMPrefs isEnabled:PRMKeyHideTabMenu];

    CGFloat lift = window.safeAreaInsets.bottom + (barGone ? 8.0 : 65.0);
    button.frame = CGRectMake(trailing,
                              window.bounds.size.height - lift - kFloatingSize,
                              kFloatingSize, kFloatingSize);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                              UIViewAutoresizingFlexibleTopMargin;
    if (button.alpha < 1.0) {
        [UIView animateWithDuration:0.18 animations:^{ button.alpha = 1.0; }];
    }
    [self setStatus:[NSString stringWithFormat:
                     @"host button NOT FOUND, fallback y=%.0f, bar %@",
                     button.frame.origin.y, barGone ? @"gone" : @"present"]
             forKey:@"floating button"];
}

// Observed rather than polled: the host's own layout writes layer.position,
// and the callback lands before the frame is drawn, so the two move together
// instead of one chasing the other.
+ (void)followHost:(UIView *)host {
    if (host == gObservedHost) return;

    if (gHostWatcher == nil) gHostWatcher = [[PRMHostWatcher alloc] init];

    UIView *previous = gObservedHost;
    if (previous != nil) {
        @try {
            [previous.layer removeObserver:gHostWatcher forKeyPath:@"position"];
            [previous.layer removeObserver:gHostWatcher forKeyPath:@"hidden"];
        } @catch (NSException *ignored) {}
    }

    gObservedHost = host;
    if (host == nil) return;

    // Both on the layer: CALayer properties are observable by contract,
    // where UIView's hidden is not.
    @try {
        [host.layer addObserver:gHostWatcher forKeyPath:@"position"
                        options:NSKeyValueObservingOptionNew context:NULL];
        [host.layer addObserver:gHostWatcher forKeyPath:@"hidden"
                        options:NSKeyValueObservingOptionNew context:NULL];
    } @catch (NSException *problem) {
        gObservedHost = nil;
        [self setStatus:[NSString stringWithFormat:@"cannot observe host: %@",
                         problem.name]
                 forKey:@"floating button"];
    }
}

+ (void)hostDidMove {
    static BOOL placing = NO;
    if (placing) return;

    UIView *button = gButton;
    UIWindow *window = button.window;
    if (window == nil) return;

    placing = YES;
    [self positionButton:button inWindow:window];
    placing = NO;
}

+ (void)handleHold:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;

    UIView *button = hold.view;
    BOOL logging = [PRMPrefs isEnabled:PRMKeyDebugEnabled];

    // Green confirms the capture ran, red says logging is off and nothing
    // was recorded.
    UIColor *flash = logging
        ? [UIColor colorWithRed:0.16 green:0.72 blue:0.36 alpha:1.0]
        : [UIColor colorWithRed:0.78 green:0.22 blue:0.18 alpha:1.0];
    UIColor *restore = button.backgroundColor;
    button.backgroundColor = flash;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        button.backgroundColor = restore;
    });

    if (!logging) return;

    // Hidden for the walk so the capture describes the screen underneath.
    button.hidden = YES;
    [self dumpViewHierarchy];
    button.hidden = NO;

    // Copied immediately: one gesture captures the screen and puts the whole
    // report where it can be pasted.
    [self copyReportToPasteboard];
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

+ (void)present {
    UIWindow *window = [self keyWindow];
    if (window == nil) return;

    UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
    backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.94];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [backdrop addSubview:scroll];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textColor = [UIColor colorWithRed:0.42 green:0.96 blue:0.58 alpha:1.0];
    label.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
    label.text = [NSString stringWithFormat:@"%@\n\ntap to dismiss", [self report]];
    [scroll addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:backdrop.safeAreaLayoutGuide.topAnchor constant:10],
        [scroll.bottomAnchor constraintEqualToAnchor:backdrop.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [scroll.leadingAnchor constraintEqualToAnchor:backdrop.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:backdrop.trailingAnchor constant:-12],
        [label.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [label.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [label.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss:)];
    [backdrop addGestureRecognizer:tap];
    [window addSubview:backdrop];
}

+ (void)dismiss:(UITapGestureRecognizer *)recognizer {
    [recognizer.view removeFromSuperview];
}

@end

@implementation PRMHostWatcher

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    [PRMDebug hostDidMove];
}

@end
