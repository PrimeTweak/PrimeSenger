// Complete measurement of the thread navigation bar, in one pass.
//
// Everything needed to place an item among the host's own call buttons is
// dumped from a single hook: the plugin registry that feeds the bar, every
// view it renders, the real element type each factory expects, and the
// colour source. Nothing here changes behaviour.
//
// Hooked on updateRightBarButtonItems, measured to fire. Nothing else in
// this tweak hooks it.
//
// Signatures taken from the binary:
//   -[MSGThreadViewNavBarManager updateRightBarButtonItems]        v16@0:8
//   -[MSGThreadViewNavBarManager delegate]                         @16@0:8
//   -[MSGThreadViewNavBarManager barButtonItemsRenderer]           @16@0:8
//   -[MSGThreadViewController navBarRendererKeysByViewModelProviderKey] @16@0:8
//   -[MSGThreadViewController navBarViewController]                @16@0:8
//   -[MSGThreadViewController navBarNavigationItem]                @16@0:8
//   -[MSGThreadViewController customOtherSendBarButtons:]          @24@0:8@16
//   -[MSGThreadViewController customLeftBarButton:]                @24@0:8@16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kPSGProbeBuild = @"probe-full";

#pragma mark - Helpers

static id PSGSend(id target, SEL selector) {
    if (target == nil || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static NSString *PSGClass(id object) {
    return object ? NSStringFromClass([object class]) : @"nil";
}

static BOOL PSGOnScreen(UIView *view) {
    if (view.window == nil) return NO;
    for (UIView *node = view; node != nil; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) return NO;
    }
    return YES;
}

static NSString *PSGColour(UIColor *colour) {
    if (colour == nil) return @"nil";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [colour getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%.2f/%.2f/%.2f", r, g, b];
}

// Every property and selector an object answers, so a Swift class that the
// static parser cannot read is still described.
static NSString *PSGDescribeObject(id object, NSUInteger limit) {
    if (object == nil) return @"nil";
    unsigned int count = 0;
    Method *methods = class_copyMethodList([object class], &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count && names.count < limit; i++) {
        [names addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);
    return [NSString stringWithFormat:@"%@[%u]{%@}", PSGClass(object), count,
            [names componentsJoinedByString:@","]];
}

#pragma mark - 1. Plugin registry

static void PSGDumpRegistry(id controller) {
    id registry = PSGSend(controller, @selector(navBarRendererKeysByViewModelProviderKey));
    if (![registry isKindOfClass:[NSDictionary class]]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"not a dictionary: %@",
                             PSGClass(registry)]
                     forKey:@"A registry"];
        return;
    }

    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (id key in (NSDictionary *)registry) {
        [pairs addObject:[NSString stringWithFormat:@"%@=>%@",
                          key, ((NSDictionary *)registry)[key]]];
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"%lu pairs | %@",
                         (unsigned long)[(NSDictionary *)registry count],
                         [pairs componentsJoinedByString:@" "]]
                 forKey:@"A registry"];
}

#pragma mark - 2. The renderer and the owners

static void PSGDumpOwners(id manager, id controller) {
    id renderer = PSGSend(manager, @selector(barButtonItemsRenderer));
    id barController = PSGSend(controller, @selector(navBarViewController));
    id navigationItem = PSGSend(controller, @selector(navBarNavigationItem));

    [PRMDebug setStatus:[NSString stringWithFormat:@"renderer %@ | barVC %@ | navItem %@",
                         PSGDescribeObject(renderer, 14),
                         PSGClass(barController), PSGClass(navigationItem)]
                 forKey:@"B renderer"];
}

#pragma mark - 3. What the factories expect

static void PSGDumpFactories(id controller) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    for (NSString *name in @[@"customOtherSendBarButtons:", @"customLeftBarButton:"]) {
        SEL selector = NSSelectorFromString(name);
        if (![controller respondsToSelector:selector]) {
            [lines addObject:[NSString stringWithFormat:@"%@ absent", name]];
            continue;
        }
        id result = ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, nil);
        NSString *element = @"-";
        if ([result isKindOfClass:[NSArray class]] && [(NSArray *)result count] > 0) {
            element = PSGDescribeObject([(NSArray *)result firstObject], 10);
        }
        [lines addObject:[NSString stringWithFormat:@"%@ -> %@ count %@ first %@",
                          name, PSGClass(result),
                          [result respondsToSelector:@selector(count)]
                              ? [NSString stringWithFormat:@"%lu", (unsigned long)[result count]]
                              : @"-",
                          element]];
    }
    [PRMDebug setStatus:[lines componentsJoinedByString:@" || "] forKey:@"C factories"];
}

#pragma mark - 4. Every view the bar draws

static void PSGWalkBar(UIView *root, UIView *window, NSInteger depth,
                       NSMutableArray<NSString *> *lines) {
    if (root == nil || depth > 16 || lines.count > 34) return;

    CGRect frame = [root convertRect:root.bounds toView:window];
    BOOL inBar = CGRectGetMinY(frame) >= 20.0 && CGRectGetMaxY(frame) <= 140.0;

    if (inBar && PSGOnScreen(root) && frame.size.width > 12.0) {
        UIColor *imageTint = nil;
        for (UIView *child in root.subviews) {
            if ([child isKindOfClass:[UIImageView class]]) {
                imageTint = child.tintColor;
                break;
            }
        }
        [lines addObject:[NSString stringWithFormat:@"d%ld %@ x%.0f y%.0f %.0fx%.0f t%@ i%@%@",
                          (long)depth, PSGClass(root),
                          CGRectGetMinX(frame), CGRectGetMinY(frame),
                          frame.size.width, frame.size.height,
                          PSGColour(root.tintColor), PSGColour(imageTint),
                          root.accessibilityLabel.length
                              ? [@" " stringByAppendingString:root.accessibilityLabel] : @""]];
    }
    for (UIView *child in root.subviews) {
        PSGWalkBar(child, window, depth + 1, lines);
    }
}

static void PSGDumpBarViews(UIWindow *window) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    PSGWalkBar(window, window, 0, lines);
    [PRMDebug setStatus:lines.count ? [lines componentsJoinedByString:@" || "] : @"nothing"
                 forKey:@"D bar views"];
}

#pragma mark - 5. The call buttons in detail

static void PSGDumpCallButtons(UIView *root, UIView *window, NSInteger depth,
                               NSMutableArray<NSString *> *lines) {
    if (root == nil || depth > 16 || lines.count > 10) return;

    NSString *name = PSGClass(root);
    BOOL candidate = [name rangeOfString:@"CallButton"].location != NSNotFound
                  || [name rangeOfString:@"BarButtonItemView"].location != NSNotFound
                  || [name rangeOfString:@"IconButton"].location != NSNotFound;

    if (candidate && PSGOnScreen(root)) {
        CGRect frame = [root convertRect:root.bounds toView:window];
        id item = PSGSend(root, @selector(barButtonItem));
        id colourSet = PSGSend(root, @selector(colorSet));
        [lines addObject:[NSString stringWithFormat:@"%@ x%.0f %.0fx%.0f item %@ set %@ super %@",
                          name, CGRectGetMinX(frame),
                          frame.size.width, frame.size.height,
                          PSGClass(item), PSGDescribeObject(colourSet, 8),
                          PSGClass(root.superview)]];
    }
    for (UIView *child in root.subviews) {
        PSGDumpCallButtons(child, window, depth + 1, lines);
    }
}

static void PSGDumpButtons(UIWindow *window) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    PSGDumpCallButtons(window, window, 0, lines);
    [PRMDebug setStatus:lines.count ? [lines componentsJoinedByString:@" || "] : @"none found"
                 forKey:@"E call buttons"];
}

#pragma mark - Hook

%hook MSGThreadViewNavBarManager

- (void)updateRightBarButtonItems {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyDebugEnabled]) return;

    id controller = PSGSend(self, @selector(delegate));
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ | delegate %@",
                         kPSGProbeBuild, PSGClass(controller)]
                 forKey:@"@ build"];

    PSGDumpRegistry(controller);
    PSGDumpOwners(self, controller);
    PSGDumpFactories(controller);

    // Views are read once the bar has laid out.
    UIViewController *host = [controller isKindOfClass:[UIViewController class]]
                           ? (UIViewController *)controller : nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = host.viewIfLoaded.window;
        if (window == nil) return;
        PSGDumpBarViews(window);
        PSGDumpButtons(window);
    });
}

%end
