// Manual read receipt control.
//
// While Read receipts are hidden and manual mode is on, an eye is added to
// the thread's navigation bar. Tapping it opens the one-shot gate and
// invokes the receipt on the live message list.
//
// The item is added to the controller's navigationItem. It renders at the
// trailing edge, outside the host's own call buttons, because those are not
// UIKit bar items: measured, rightBarButtonItems holds one entry, ours.
//
// customOtherSendBarButtons: is not the route. Despite returning an empty
// array it feeds the send bar, not the navigation bar, and putting a
// UIBarButtonItem in it crashes the thread on open.
//
// Signatures taken from the binary:
//   -[MSGThreadViewController viewDidLoad]                         v16@0:8
//   -[MSGThreadViewController viewDidLayoutSubviews]               v16@0:8
//   -[MSGMessageListViewController _notifyObserversDidSetAsRead:]  v20@0:8B16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kPSGEyeTarget = &kPSGEyeTarget;
static const void *kPSGEyeItem = &kPSGEyeItem;

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

#pragma mark - Target

@interface PSGReceiptEye : NSObject
@property (nonatomic, weak) UIViewController *host;
@end

@implementation PSGReceiptEye

- (void)tapped:(id)sender {
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

// A plain image item with no customView and no tintColor: the host wraps
// and tints the buttons it receives from this factory.
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

static void PSGSyncEye(UIViewController *host, NSString *pass) {
    NSMutableArray<UIBarButtonItem *> *items =
        [NSMutableArray arrayWithArray:host.navigationItem.rightBarButtonItems ?: @[]];
    UIBarButtonItem *existing = objc_getAssociatedObject(host, kPSGEyeItem);

    if (!PSGEyeWanted()) {
        if (existing == nil) return;
        [items removeObject:existing];
        host.navigationItem.rightBarButtonItems = items;
        objc_setAssociatedObject(host, kPSGEyeItem, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, kPSGEyeTarget, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (existing != nil && [items containsObject:existing]) return;

    UIBarButtonItem *item = existing;
    if (item == nil) {
        PSGReceiptEye *eye = [[PSGReceiptEye alloc] init];
        eye.host = host;
        item = PSGMakeEyeItem(eye);
        // Held by the controller: the item keeps only a weak target.
        objc_setAssociatedObject(host, kPSGEyeTarget, eye,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [items addObject:item];
    host.navigationItem.rightBarButtonItems = items;
    objc_setAssociatedObject(host, kPSGEyeItem, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [PRMDebug noteHook:@"manual receipt"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ at %@, %lu items",
                         existing ? @"re-added" : @"added", pass,
                         (unsigned long)host.navigationItem.rightBarButtonItems.count]
                 forKey:@"thread bar"];
}

#pragma mark - Hook

%hook MSGThreadViewController

- (void)viewDidLoad {
    %orig;
    PSGSyncEye((UIViewController *)self, @"viewDidLoad");
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *host = (UIViewController *)self;
    if (host.viewIfLoaded.window == nil) return;
    PSGSyncEye(host, @"layout");
}

%end
