// Manual read receipt control.
//
// While Read receipts are hidden and manual mode is on, an eye is added to
// the thread's navigation bar. Tapping it opens the one-shot gate and
// invokes the receipt on the live message list.
//
// The host's bar is driven by real UIBarButtonItem objects: each one is
// wrapped in an MSGIconBarButtonItemView, which applies the thread's
// colorSet and lays it out with the others. A customView bypasses that
// wrapper and is placed by UIKit instead, unthemed. A plain image item takes
// the same path as the call buttons.
//
// The array is written by MSGThreadViewNavBarManager, so the item is
// appended from inside its own update: no pass exists where the bar is
// drawn without it.
//
// Signatures taken from the binary:
//   -[MSGThreadViewNavBarManager updateRightBarButtonItems]  v16@0:8
//   -[MSGThreadViewNavBarManager delegate]                   @16@0:8
//   -[MSGThreadViewController navBarNavigationItem]          @16@0:8
//   -[MSGIconBarButtonItemView setColorSet:]                 v24@0:8@16
//   -[MSGMessageListViewController _notifyObserversDidSetAsRead:] v20@0:8B16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kPSGEyeItem = &kPSGEyeItem;
static const void *kPSGEyeTarget = &kPSGEyeTarget;

#pragma mark - Lookups

// The message list lives as a descendant of the thread controller.
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

// The item the manager writes to, which is not necessarily the controller's
// own navigationItem.
static UINavigationItem *PSGTargetNavigationItem(id delegate) {
    if (delegate == nil) return nil;
    if ([delegate respondsToSelector:@selector(navBarNavigationItem)]) {
        id item = ((id (*)(id, SEL))objc_msgSend)(delegate,
                                                  @selector(navBarNavigationItem));
        if ([item isKindOfClass:[UINavigationItem class]]) return item;
    }
    if ([delegate isKindOfClass:[UIViewController class]]) {
        return ((UIViewController *)delegate).navigationItem;
    }
    return nil;
}

#pragma mark - Target

@interface PSGReceiptEye : NSObject
@property (nonatomic, weak) UIViewController *host;
@end

@implementation PSGReceiptEye

- (void)tapped:(UIBarButtonItem *)item {
    UIViewController *list = PSGMessageListIn(self.host, 0);
    BOOL sent = [PSGReadReceipts sendReceiptOn:list];

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:sent ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleRigid];
    [haptic impactOccurred];
    [PRMDebug noteAction:@"manual receipt"];
}

@end

#pragma mark - Item

static BOOL PSGEyeWanted(void) {
    return ![PRMPrefs isEnabled:PRMKeyMasterDisable]
        && [PRMPrefs isEnabled:PRMKeyReadAnonymously]
        && [PRMPrefs isEnabled:PRMKeyReadReceiptsManual];
}

// A plain image item, so the host's renderer wraps and tints it as it does
// the call buttons. No customView, no explicit tintColor.
static UIBarButtonItem *PSGMakeEyeItem(PSGReceiptEye *eye) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:@"eye.fill" withConfiguration:configuration];

    UIBarButtonItem *item;
    if (glyph != nil) {
        item = [[UIBarButtonItem alloc]
                initWithImage:[glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                        style:UIBarButtonItemStylePlain
                       target:eye
                       action:@selector(tapped:)];
    } else {
        [PRMDebug log:@"eye.fill unavailable, falling back to text"];
        item = [[UIBarButtonItem alloc] initWithTitle:@"Seen"
                                                style:UIBarButtonItemStylePlain
                                               target:eye
                                               action:@selector(tapped:)];
    }
    item.accessibilityLabel = @"Mark as seen";
    return item;
}

static void PSGSyncEyeItem(id manager) {
    if (![manager respondsToSelector:@selector(delegate)]) return;
    id delegate = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(delegate));
    UINavigationItem *navigationItem = PSGTargetNavigationItem(delegate);
    if (navigationItem == nil) {
        [PRMDebug setStatus:@"no navigation item from the manager delegate"
                     forKey:@"thread bar"];
        return;
    }

    NSMutableArray<UIBarButtonItem *> *items =
        [NSMutableArray arrayWithArray:navigationItem.rightBarButtonItems ?: @[]];
    UIBarButtonItem *existing = objc_getAssociatedObject(navigationItem, kPSGEyeItem);

    if (!PSGEyeWanted()) {
        if (existing == nil) return;
        [items removeObject:existing];
        navigationItem.rightBarButtonItems = items;
        objc_setAssociatedObject(navigationItem, kPSGEyeItem, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (existing != nil && [items containsObject:existing]) return;

    UIViewController *host = [delegate isKindOfClass:[UIViewController class]]
                           ? (UIViewController *)delegate : nil;

    UIBarButtonItem *item = existing;
    if (item == nil) {
        PSGReceiptEye *eye = [[PSGReceiptEye alloc] init];
        eye.host = host;
        item = PSGMakeEyeItem(eye);
        // Held alongside the item: it only keeps a weak target.
        objc_setAssociatedObject(item, kPSGEyeTarget, eye,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [items addObject:item];
    navigationItem.rightBarButtonItems = items;
    objc_setAssociatedObject(navigationItem, kPSGEyeItem, item,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [PRMDebug noteHook:@"manual receipt"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ on %@, %lu items, held %@",
                         existing ? @"re-added" : @"added",
                         NSStringFromClass([delegate class]),
                         (unsigned long)navigationItem.rightBarButtonItems.count,
                         [navigationItem.rightBarButtonItems containsObject:item]
                             ? @"yes" : @"NO"]
                 forKey:@"thread bar"];
}

#pragma mark - Hook

%hook MSGThreadViewNavBarManager

// Appended from inside the host's own update, so the bar is never laid out
// without the item and there is nothing to re-assert afterwards.
- (void)updateRightBarButtonItems {
    %orig;
    PSGSyncEyeItem(self);
}

%end
