// Manual read receipt control.
//
// While Read receipts are hidden and manual mode is on, an eye is added to
// the thread's navigation bar. Tapping it opens the one-shot gate and
// invokes the receipt on the live message list.
//
// The item goes through -customOtherSendBarButtons:, the host's own factory
// for extra bar buttons. Measured: it receives the thread theme and returns
// an empty array, so the slot is unused and the host tints whatever it is
// given. Adding to navigationItem instead placed the item alone in a UIKit
// array, which is why it landed at the trailing edge, untinted.
//
// Signatures taken from the binary:
//   -[MSGThreadViewController customOtherSendBarButtons:]          @24@0:8@16
//   -[MSGThreadViewController customLeftBarButton:]                @24@0:8@16
//   -[MSGMessageListViewController _notifyObserversDidSetAsRead:]  v20@0:8B16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"
#import <objc/runtime.h>
#import <objc/message.h>

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

#pragma mark - Hook

%hook MSGThreadViewController

// The host asks for extra trailing buttons here and expects an array. The
// eye is appended to whatever it already returns, so a future build that
// fills this slot keeps its own buttons.
- (id)customOtherSendBarButtons:(id)theme {
    id result = %orig;

    if (!PSGEyeWanted()) return result;

    NSMutableArray *buttons = [NSMutableArray array];
    if ([result isKindOfClass:[NSArray class]]) {
        [buttons addObjectsFromArray:(NSArray *)result];
    }

    PSGReceiptEye *eye = objc_getAssociatedObject(self, kPSGEyeTarget);
    if (eye == nil) {
        eye = [[PSGReceiptEye alloc] init];
        eye.host = (UIViewController *)self;
        // Held by the controller: the item keeps only a weak target.
        objc_setAssociatedObject(self, kPSGEyeTarget, eye,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [buttons addObject:PSGMakeEyeItem(eye)];

    [PRMDebug noteHook:@"manual receipt"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%lu host + 1 eye, theme %@",
                         (unsigned long)([result isKindOfClass:[NSArray class]]
                                         ? [(NSArray *)result count] : 0),
                         theme ? NSStringFromClass([theme class]) : @"nil"]
                 forKey:@"thread bar"];
    return buttons;
}

%end
