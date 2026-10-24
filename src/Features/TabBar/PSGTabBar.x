// A system UITabBar placed inside the host's own bar carries the Liquid
// Glass material; tabs are hidden by their accessibility identifier, or by
// their label where the host sets none.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Constants

static const NSInteger kPSGNativeBarTag = 0x50534703;

// Marks host subviews hidden by this tweak, so anything the host hid on its
// own is never revealed.
static const void *kPSGHiddenByTweak = &kPSGHiddenByTweak;
static const void *kPSGBarDelegate = &kPSGBarDelegate;

#pragma mark - Tab names

// The host's accessibility identifiers, stable across languages.
static NSDictionary<NSString *, NSString *> *PSGKeysByIdentifier(void) {
    return @{
        @"tabbar-chats"                   : PRMKeyHideTabChats,
        @"tabbar-meta-ai"                 : PRMKeyHideTabMetaAI,
        @"tabbar-jewel-notification-menu" : PRMKeyHideTabNotifications,
    };
}

// Option names, matched against the label when no identifier is known.
static NSDictionary<NSString *, NSString *> *PSGKeysByLabel(void) {
    return @{
        @"Chats"         : PRMKeyHideTabChats,
        @"Meta AI"       : PRMKeyHideTabMetaAI,
        @"Stories"       : PRMKeyHideTabStories,
        @"Notifications" : PRMKeyHideTabNotifications,
        @"Menu"          : PRMKeyHideTabMenu,
    };
}

static NSString *PSGKeyForTab(NSString *identifier, NSString *label) {
    NSString *key = identifier.length ? PSGKeysByIdentifier()[identifier] : nil;
    if (key != nil) return key;
    if (label.length == 0) return nil;
    NSDictionary *byLabel = PSGKeysByLabel();
    for (NSString *candidate in byLabel) {
        if ([label compare:candidate options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return byLabel[candidate];
        }
    }
    return nil;
}

// The key of a tab the user chose to hide, nil for any other tab.
static NSString *PSGHiddenKeyForTab(NSString *identifier, NSString *label) {
    NSString *key = PSGKeyForTab(identifier, label);
    if (key == nil) return nil;
    return [PRMPrefs isEnabled:key] ? key : nil;
}

// One counter per tab option, named after the option so the report counts a
// tab the same way whatever the device language.
static void PSGNoteTabHidden(NSString *key) {
    NSDictionary *byLabel = PSGKeysByLabel();
    NSString *name = key;
    for (NSString *label in byLabel) {
        if ([byLabel[label] isEqualToString:key]) { name = label; break; }
    }
    [PRMDebug noteAction:[@"tab hidden " stringByAppendingString:name]];
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
        UITabBarItem *item = entry;
        NSString *key = PSGHiddenKeyForTab(item.accessibilityIdentifier, PSGNameForItem(item));
        if (key != nil) {
            PSGNoteTabHidden(key);
            continue;
        }
        [kept addObject:item];
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
    BOOL wanted = [PRMPrefs isEnabled:PRMKeyGlassTabBar];

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
        NSString *key = PSGHiddenKeyForTab(child.accessibilityIdentifier, child.accessibilityLabel);
        BOOL ownedBefore = [objc_getAssociatedObject(child, kPSGHiddenByTweak) boolValue];

        if (key != nil) {
            [mine addObject:child];
            PSGNoteTabHidden(key);
            continue;
        }
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
