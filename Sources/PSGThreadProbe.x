// Measurement only. Reports what the host's navigation bar does with the
// item this tweak adds, so the placement and the tint stop being guessed.
//
// Five questions, each answered by one line of the report:
//
//   1. Which navigation item does MSGThreadViewNavBarManager write to, and
//      how many items does it hold? One item means the host's own call
//      buttons never enter that array, which would explain an eye placed
//      past them instead of before them.
//   2. Which view class renders the added item, compared with the class
//      rendering the call buttons.
//   3. What colorSet and icon the call buttons carry, and what ours has.
//   4. The frame of every rendered bar item, so horizontal order and
//      vertical alignment are read rather than described.
//   5. Whether the image survives as a template through the wrapper.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/runtime.h>
#import <objc/message.h>

static id PSGSend(id target, SEL selector) {
    if (target == nil || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

#pragma mark - Question 1

static void PSGReportNavigationItem(id manager) {
    id delegate = PSGSend(manager, @selector(delegate));
    id navigationItem = PSGSend(delegate, @selector(navBarNavigationItem));

    UINavigationItem *own = [delegate isKindOfClass:[UIViewController class]]
                          ? ((UIViewController *)delegate).navigationItem : nil;

    NSArray *right = [navigationItem isKindOfClass:[UINavigationItem class]]
                   ? ((UINavigationItem *)navigationItem).rightBarButtonItems : nil;
    NSArray *left = [navigationItem isKindOfClass:[UINavigationItem class]]
                  ? ((UINavigationItem *)navigationItem).leftBarButtonItems : nil;

    NSMutableArray<NSString *> *rightNames = [NSMutableArray array];
    for (UIBarButtonItem *item in right) {
        [rightNames addObject:[NSString stringWithFormat:@"%@%@",
                               NSStringFromClass([item class]),
                               item.image ? @"(img)" : @""]];
    }

    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"delegate %@ | navBarItem %@ | same as own: %@ | right %lu [%@] | left %lu",
                         NSStringFromClass([delegate class]),
                         navigationItem ? NSStringFromClass([navigationItem class]) : @"NIL",
                         navigationItem == own ? @"yes" : @"NO",
                         (unsigned long)right.count,
                         [rightNames componentsJoinedByString:@", "],
                         (unsigned long)left.count]
                 forKey:@"probe 1 nav item"];
}

#pragma mark - Questions 2 to 5

static void PSGCollectItemViews(UIView *root, NSInteger depth,
                                NSMutableArray<UIView *> *found) {
    if (root == nil || depth > 16) return;
    if ([NSStringFromClass([root class])
         rangeOfString:@"BarButtonItemView"].location != NSNotFound) {
        [found addObject:root];
        return;
    }
    for (UIView *child in root.subviews) {
        PSGCollectItemViews(child, depth + 1, found);
    }
}

static BOOL PSGOnScreen(UIView *view) {
    if (view.window == nil) return NO;
    for (UIView *node = view; node != nil; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) return NO;
    }
    return YES;
}

static void PSGReportRenderedItems(UIWindow *window) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    PSGCollectItemViews(window, 0, views);

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UIView *view in views) {
        if (!PSGOnScreen(view)) continue;
        CGRect frame = [view convertRect:view.bounds toView:window];

        id item = PSGSend(view, @selector(barButtonItem));
        UIImage *image = [item isKindOfClass:[UIBarButtonItem class]]
                       ? ((UIBarButtonItem *)item).image : nil;
        NSString *rendering = image
            ? (image.renderingMode == UIImageRenderingModeAlwaysTemplate
               ? @"template" : @"original")
            : @"noimage";

        id colourSet = PSGSend(view, @selector(colorSet));
        NSString *icon = @"-";
        if ([view respondsToSelector:@selector(icon)]) {
            unsigned long long value =
                ((unsigned long long (*)(id, SEL))objc_msgSend)(view, @selector(icon));
            icon = [NSString stringWithFormat:@"%llu", value];
        }

        [lines addObject:[NSString stringWithFormat:
                          @"%@ x%.0f y%.0f %.0fx%.0f icon:%@ set:%@ img:%@",
                          NSStringFromClass([view class]),
                          CGRectGetMinX(frame), CGRectGetMinY(frame),
                          frame.size.width, frame.size.height,
                          icon,
                          colourSet ? NSStringFromClass([colourSet class]) : @"nil",
                          rendering]];
    }

    [PRMDebug setStatus:lines.count ? [lines componentsJoinedByString:@" || "]
                                    : @"no rendered bar item views"
                 forKey:@"probe 2 rendered"];
}

#pragma mark - Question 3

// The colour a neighbour actually shows, read off its own image view.
static void PSGReportColours(UIWindow *window) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    PSGCollectItemViews(window, 0, views);

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UIView *view in views) {
        if (!PSGOnScreen(view)) continue;
        UIColor *tint = view.tintColor;
        UIColor *imageTint = nil;
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:[UIImageView class]]) {
                imageTint = child.tintColor;
                break;
            }
        }
        CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
        [tint getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
        [imageTint getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
        [lines addObject:[NSString stringWithFormat:@"%@ view %.2f/%.2f/%.2f img %.2f/%.2f/%.2f",
                          NSStringFromClass([view class]), r1, g1, b1, r2, g2, b2]];
    }
    [PRMDebug setStatus:lines.count ? [lines componentsJoinedByString:@" || "] : @"none"
                 forKey:@"probe 3 colours"];
}

#pragma mark - Question 6

// Names the class that draws the call buttons. They are not
// *BarButtonItemView, so the bar region is dumped whole.
static void PSGDumpBarRegion(UIView *root, UIView *window, NSInteger depth,
                             NSMutableArray<NSString *> *lines) {
    if (root == nil || depth > 14 || lines.count > 40) return;

    CGRect frame = [root convertRect:root.bounds toView:window];
    BOOL inBar = CGRectGetMinY(frame) >= 30.0 && CGRectGetMaxY(frame) <= 130.0;
    BOOL buttonSized = frame.size.width > 20.0 && frame.size.width < 90.0
                    && frame.size.height > 20.0 && frame.size.height < 70.0;

    if (inBar && buttonSized && PSGOnScreen(root)) {
        [lines addObject:[NSString stringWithFormat:@"%@ x%.0f y%.0f %.0fx%.0f d%ld%@",
                          NSStringFromClass([root class]),
                          CGRectGetMinX(frame), CGRectGetMinY(frame),
                          frame.size.width, frame.size.height, (long)depth,
                          root.accessibilityLabel.length
                              ? [@" " stringByAppendingString:root.accessibilityLabel]
                              : @""]];
    }
    for (UIView *child in root.subviews) {
        PSGDumpBarRegion(child, window, depth + 1, lines);
    }
}

static void PSGReportBarRegion(UIWindow *window) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    PSGDumpBarRegion(window, window, 0, lines);
    [PRMDebug setStatus:lines.count ? [lines componentsJoinedByString:@" || "]
                                    : @"nothing button-sized in the bar region"
                 forKey:@"probe 4 bar region"];
}

#pragma mark - Question 7

// The host exposes a hook-shaped factory for extra bar buttons. What it
// receives and returns decides whether the eye can join their array.

#pragma mark - Question 8

// The thread bar is plugin driven: navBarRendererKeysByViewModelProviderKey
// maps each view model provider to the renderer that draws its buttons. The
// call buttons come from one of those pairs, and the classes involved are
// Swift, so the mapping can only be read at runtime.
static void PSGReportBarRegistry(id controller) {
    id registry = PSGSend(controller, @selector(navBarRendererKeysByViewModelProviderKey));
    if (![registry isKindOfClass:[NSDictionary class]]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"registry is %@",
                             registry ? NSStringFromClass([registry class]) : @"nil"]
                     forKey:@"probe 8 registry"];
        return;
    }

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (id key in (NSDictionary *)registry) {
        id value = ((NSDictionary *)registry)[key];
        [lines addObject:[NSString stringWithFormat:@"%@ -> %@", key, value]];
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"%lu pairs: %@",
                         (unsigned long)[(NSDictionary *)registry count],
                         [lines componentsJoinedByString:@" || "]]
                 forKey:@"probe 8 registry"];

    // The controller that owns the bar, and the item the manager targets.
    id barController = PSGSend(controller, @selector(navBarViewController));
    [PRMDebug setStatus:[NSString stringWithFormat:@"navBarViewController %@ | liquidGlass %@",
                         barController ? NSStringFromClass([barController class]) : @"nil",
                         [controller respondsToSelector:@selector(navBarIsLiquidGlassEnabled)]
                          && ((BOOL (*)(id, SEL))objc_msgSend)(
                                controller, @selector(navBarIsLiquidGlassEnabled))
                             ? @"yes" : @"no"]
                 forKey:@"probe 9 bar owner"];
}

#pragma mark - Hook

// Marks which delivery is running while control stays pinned during
// development. Bumped every time this file is sent.
static NSString *const kPSGProbeBuild = @"probe-4";

%hook MSGThreadViewNavBarManager

// Hooked here rather than on updateRightBarButtonItems: PSGThreadBar.x
// already takes that method, and two hooks on one method in the same group
// cannot both be installed. This one receives the bar model, so it runs
// whenever the bar is built.
- (void)setNavigationBarProps:(id)props {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyDebugEnabled]) return;

    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ | props %@",
                         kPSGProbeBuild,
                         props ? NSStringFromClass([props class]) : @"nil"]
                 forKey:@"probe build"];
    PSGReportNavigationItem(self);
    PSGReportBarRegistry(PSGSend(self, @selector(delegate)));

    // Read after the bar has laid out, so frames and wrappers are final.
    id delegate = PSGSend(self, @selector(delegate));
    UIViewController *controller = [delegate isKindOfClass:[UIViewController class]]
                                 ? (UIViewController *)delegate : nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = controller.viewIfLoaded.window;
        if (window == nil) return;
        PSGReportRenderedItems(window);
        PSGReportColours(window);
        PSGReportBarRegion(window);
    });
}

%end
