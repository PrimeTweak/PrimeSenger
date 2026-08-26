// Tab bar. A real UITabBar is placed inside the host's custom bar and the
// host's own drawing is hidden behind it.
//
// Measured: a standalone UITabBar, outside any UITabBarController, still
// receives the full iOS 26 treatment — its tree contains _UILiquidLensView,
// _UITabBarPlatterView and _UITabBarVisualProvider_Floating. The host's
// items already inherit UITabBarItem, so they are handed over unchanged.
//
// Selection is routed back through -didTapButton:, the host's own handler,
// so Messenger navigates exactly as it does on a native tap.
//
// Signatures taken from the binary and the runtime scan:
//   -[MDSModernTabBar layoutSubviews]     v16@0:8
//   -[MDSModernTabBar items]              @16@0:8
//   -[MDSModernTabBar selectedItem]       @16@0:8
//   -[MDSModernTabBar viewForItem:]       @24@0:8@16
//   -[MDSModernTabBar didTapButton:]      v24@0:8@16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Constants

static const NSInteger kPSGNativeBarTag = 0x504D4701;

// Marks host subviews hidden by this tweak, so anything the host hid on its
// own is never revealed.
static const void *kPSGHiddenByTweak = &kPSGHiddenByTweak;
static const void *kPSGBarDelegate = &kPSGBarDelegate;

#pragma mark - Tab names

static NSString *PSGKeyForTabName(NSString *name) {
    if (name.length == 0) return nil;
    NSDictionary *rules = @{
        @"Chats"         : PRMKeyHideTabChats,
        @"Stories"       : PRMKeyHideTabStories,
        @"Notifications" : PRMKeyHideTabNotifications,
        @"Menu"          : PRMKeyHideTabMenu,
    };
    for (NSString *label in rules) {
        if ([name compare:label options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return rules[label];
        }
    }
    return nil;
}

static BOOL PSGTabIsHidden(NSString *name) {
    if ([PRMPrefs isEnabled:PRMKeyMasterDisable]) return NO;
    NSString *key = PSGKeyForTabName(name);
    if (key == nil) return NO;
    return [PRMPrefs isEnabled:key];
}

static NSString *PSGNameForItem(UITabBarItem *item) {
    if (item.title.length > 0) return item.title;
    return item.accessibilityLabel ?: @"";
}

#pragma mark - Selection routing

@interface PSGTabBarBridge : NSObject <UITabBarDelegate>
@property (nonatomic, weak) UIView *host;
@end

@implementation PSGTabBarBridge

// The host's own handler is called so its delegate chain runs unchanged.
- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    UIView *host = self.host;
    if (host == nil) return;
    if (![host respondsToSelector:@selector(viewForItem:)]) return;

    id button = ((id (*)(id, SEL, id))objc_msgSend)(host, @selector(viewForItem:), item);
    if (![button isKindOfClass:[UIView class]]) return;
    if (![host respondsToSelector:@selector(didTapButton:)]) return;

    ((void (*)(id, SEL, id))objc_msgSend)(host, @selector(didTapButton:), button);
}

@end

#pragma mark - Host chrome

static void PSGSetHostChromeHidden(UIView *host, UIView *ours, BOOL hidden) {
    for (UIView *child in host.subviews) {
        if (child == ours) continue;
        BOOL ownedBefore = [objc_getAssociatedObject(child, kPSGHiddenByTweak) boolValue];
        if (hidden) {
            if (child.hidden) continue;
            child.hidden = YES;
            objc_setAssociatedObject(child, kPSGHiddenByTweak, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (ownedBefore) {
            child.hidden = NO;
            objc_setAssociatedObject(child, kPSGHiddenByTweak, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

#pragma mark - Native bar

static NSArray<UITabBarItem *> *PSGVisibleItems(UIView *host) {
    if (![host respondsToSelector:@selector(items)]) return nil;
    NSArray *items = ((id (*)(id, SEL))objc_msgSend)(host, @selector(items));

    NSMutableArray<UITabBarItem *> *kept = [NSMutableArray array];
    for (id entry in items) {
        if (![entry isKindOfClass:[UITabBarItem class]]) continue;
        if (PSGTabIsHidden(PSGNameForItem(entry))) continue;
        [kept addObject:entry];
    }
    return kept;
}

static UITabBarItem *PSGHostSelection(UIView *host) {
    if (![host respondsToSelector:@selector(selectedItem)]) return nil;
    id item = ((id (*)(id, SEL))objc_msgSend)(host, @selector(selectedItem));
    return [item isKindOfClass:[UITabBarItem class]] ? item : nil;
}

static void PSGApplyNativeBar(UIView *host) {
    UITabBar *native = (UITabBar *)[host viewWithTag:kPSGNativeBarTag];
    BOOL wanted = ![PRMPrefs isEnabled:PRMKeyMasterDisable]
               && [PRMPrefs isEnabled:PRMKeyGlassTabBar];

    if (!wanted) {
        PSGSetHostChromeHidden(host, native, NO);
        if (native == nil) return;
        [native removeFromSuperview];
        objc_setAssociatedObject(host, kPSGBarDelegate, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [PRMDebug setStatus:@"off, host bar restored" forKey:@"native tab bar"];
        return;
    }

    NSArray<UITabBarItem *> *items = PSGVisibleItems(host);
    if (items.count == 0) {
        [PRMDebug setStatus:@"no usable items" forKey:@"native tab bar"];
        return;
    }

    if (native == nil) {
        PSGTabBarBridge *bridge = [[PSGTabBarBridge alloc] init];
        bridge.host = host;

        native = [[UITabBar alloc] initWithFrame:host.bounds];
        native.tag = kPSGNativeBarTag;
        native.delegate = bridge;
        native.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                  UIViewAutoresizingFlexibleHeight;
        [host addSubview:native];

        objc_setAssociatedObject(host, kPSGBarDelegate, bridge,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [PRMDebug noteAction:@"native tab bar"];
    }

    native.frame = host.bounds;
    if (![native.items isEqualToArray:items]) native.items = items;

    UITabBarItem *selected = PSGHostSelection(host);
    if (selected != nil && [items containsObject:selected]) {
        native.selectedItem = selected;
    }

    PSGSetHostChromeHidden(host, native, YES);
    host.backgroundColor = [UIColor clearColor];
    [host bringSubviewToFront:native];

    [PRMDebug setStatus:[NSString stringWithFormat:@"on, %lu items, %.0fx%.0f",
                         (unsigned long)items.count,
                         native.bounds.size.width, native.bounds.size.height]
                 forKey:@"native tab bar"];
}

#pragma mark - Hook

%hook _TtC15MDSModernTabBar15MDSModernTabBar

- (void)layoutSubviews {
    %orig;
    [PRMDebug noteHook:@"tab bar layout"];
    [PRMDebug setStatus:@"reached, PSGTabBar 1.0.1" forKey:@"tab bar hook"];

    UIView *host = (UIView *)self;
    PSGApplyNativeBar(host);

    // With the native bar off, the host's own buttons are filtered directly.
    if ([host viewWithTag:kPSGNativeBarTag] != nil) return;

    NSMutableArray<UIView *> *mine = [NSMutableArray array];
    NSMutableArray<UIView *> *shown = [NSMutableArray array];
    for (UIView *child in host.subviews) {
        if ([NSStringFromClass([child class]) rangeOfString:@"TabBarButton"].location
            == NSNotFound) {
            continue;
        }
        NSString *name = child.accessibilityLabel ?: @"";
        BOOL ownedBefore = [objc_getAssociatedObject(child, kPSGHiddenByTweak) boolValue];

        if (PSGTabIsHidden(name)) { [mine addObject:child]; continue; }
        if (ownedBefore) {
            child.hidden = NO;
            objc_setAssociatedObject(child, kPSGHiddenByTweak, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!child.hidden) [shown addObject:child];
    }

    for (UIView *button in mine) {
        button.hidden = YES;
        objc_setAssociatedObject(button, kPSGHiddenByTweak, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    host.hidden = (shown.count == 0);
    if (mine.count == 0 || shown.count == 0) return;

    CGFloat width = host.bounds.size.width / (CGFloat)shown.count;
    NSUInteger index = 0;
    for (UIView *button in shown) {
        CGRect frame = button.frame;
        frame.origin.x = width * (CGFloat)index + (width - frame.size.width) / 2.0;
        button.frame = frame;
        index++;
    }
    [PRMDebug noteAction:@"tab bar layout"];
}

// Selection changes without a layout pass, so the native bar is told.
- (void)didTapButton:(id)button {
    %orig;
    UIView *host = (UIView *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITabBar *native = (UITabBar *)[host viewWithTag:kPSGNativeBarTag];
        UITabBarItem *selected = PSGHostSelection(host);
        if (native != nil && selected != nil) native.selectedItem = selected;
    });
}

%end
