// Saving media the app offers no button for.
//
// The long press route is gone. Reproduced from MSGPlusX's binary to the
// letter, without the duplicate check, the userInteractionEnabled write or
// the delegate an earlier attempt here added, it installed 204 recognisers
// in one session and fired zero times: the "hold gesture" key writes on
// every state transition, a failure included, and it never appeared. The
// touch does not reach those views on this build, so their feature cannot
// work here either. It also cost one recogniser per layout pass, none of
// them released.
//
// What replaced it is the route that measured working on the first try: a
// button placed on the screen that already shows the image.
//
//   profile save   ran 2  acted 2   button added
//   save media     saved
//
// Both screens are found by name rather than hooked directly, the way
// PSGScreens.x matches the Meta AI controller, since one of them is a Swift
// class whose mangled runtime name would have to be reconstructed by hand.
//
//   LSProfilePictureViewController          the profile picture viewer
//   MSGMessageLongPressOverlayViewController  the preview behind the menu
//
// The image is looked up rather than assumed: any view answering -image
// with a UIImage counts, which covers both the plain UIImageView of the
// profile viewer and the LSNetworkImageView measured inside the overlay.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static const NSInteger kPSGSaveButtonTag = 0x50534753;

// Any view answering -image with a UIImage, largest first, so the picture
// wins over an avatar or an icon sharing the same screen.
static UIView *PSGImageBearingView(UIView *root, UIImage **out) {
    UIView *best = nil;
    UIImage *bestImage = nil;
    CGFloat bestArea = 0;
    NSMutableArray<UIView *> *queue = [@[root] mutableCopy];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:node.subviews];
        if (![node respondsToSelector:@selector(image)]) continue;
        id found = ((id (*)(id, SEL))objc_msgSend)(node, @selector(image));
        if (![found isKindOfClass:[UIImage class]]) continue;
        CGSize size = node.bounds.size;
        // Small squares are avatars and glyphs, not the subject of the screen.
        if (size.width < 80 || size.height < 80) continue;
        CGFloat area = size.width * size.height;
        if (area > bestArea) { bestArea = area; best = node; bestImage = found; }
    }
    if (out != NULL) *out = bestImage;
    return best;
}

@interface PSGMediaSaver : NSObject
+ (instancetype)shared;
@end

@implementation PSGMediaSaver

+ (instancetype)shared {
    static PSGMediaSaver *saver = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ saver = [[PSGMediaSaver alloc] init]; });
    return saver;
}

- (void)write:(UIImage *)image from:(NSString *)route {
    if (![image isKindOfClass:[UIImage class]]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"%@: no image", route]
                     forKey:@"save media"];
        return;
    }
    [PRMDebug noteAction:@"save media"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@: writing %.0fx%.0f",
                         route, image.size.width, image.size.height]
                 forKey:@"save media"];
    UIImageWriteToSavedPhotosAlbum(
        image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image
    didFinishSavingWithError:(NSError *)error
                 contextInfo:(void *)contextInfo {
    [PRMDebug setStatus:(error == nil) ? @"saved" : error.localizedDescription
                 forKey:@"save media"];
}

- (void)saveTapped:(UIButton *)sender {
    UIView *root = sender.superview;
    UIImage *image = nil;
    PSGImageBearingView(root, &image);
    [self write:image from:@"button"];
}

@end

#pragma mark - Save button

// The two screens that show an image with no way to keep it. Matched by
// name, and each gets the button only once.
static BOOL PSGScreenWantsSaveButton(NSString *name) {
    return [name containsString:@"LSProfilePictureViewController"]
        || [name containsString:@"MSGMessageLongPressOverlayViewController"];
}

%hook UIViewController

// viewDidLayoutSubviews rather than viewDidAppear:, which PSGScreens.x
// already owns on this class.
- (void)viewDidLayoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHoldToSave]) return;

    NSString *name = NSStringFromClass([self class]);
    if (!PSGScreenWantsSaveButton(name)) return;

    // Counted at the door, before any guard. The previous build counted
    // after the image lookup, so a screen that appeared without a match was
    // indistinguishable from a screen that never appeared at all.
    BOOL overlay = [name containsString:@"LongPress"];
    [PRMDebug noteHook:overlay ? @"save overlay" : @"save profile"];

    UIView *root = self.viewIfLoaded;
    if (root == nil) return;
    if ([root viewWithTag:kPSGSaveButtonTag] != nil) return;

    UIImage *image = nil;
    UIView *carrier = PSGImageBearingView(root, &image);

    if (carrier == nil) {
        // What the screen does hold, largest first, so the next pass aims at
        // something measured instead of another guess about the hierarchy.
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        NSMutableArray<UIView *> *queue = [@[root] mutableCopy];
        while (queue.count > 0 && seen.count < 40) {
            UIView *node = queue.firstObject;
            [queue removeObjectAtIndex:0];
            [queue addObjectsFromArray:node.subviews];
            CGSize size = node.bounds.size;
            if (size.width < 80 || size.height < 80) continue;
            [seen addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f%@",
                             NSStringFromClass([node class]), size.width, size.height,
                             [node respondsToSelector:@selector(image)] ? @" HASIMAGE" : @""]];
        }
        [PRMDebug setStatus:[NSString stringWithFormat:@"%@ no match | %@",
                             name, [seen componentsJoinedByString:@" , "]]
                     forKey:overlay ? @"save overlay" : @"save profile"];
        return;
    }

    // Pinned to the top right of the picture itself rather than the screen,
    // so it sits on the image on both screens without knowing either layout.
    CGRect frame = [carrier convertRect:carrier.bounds toView:root];
    CGFloat x = MIN(CGRectGetMaxX(frame) - 52, root.bounds.size.width - 52);
    CGFloat y = MAX(CGRectGetMinY(frame) + 8, 60);

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.tag = kPSGSaveButtonTag;
    save.frame = CGRectMake(MAX(x, 8), y, 44, 44);
    save.tintColor = [UIColor whiteColor];
    save.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    save.layer.cornerRadius = 22;
    [save setImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
          forState:UIControlStateNormal];
    [save addTarget:[PSGMediaSaver shared]
             action:@selector(saveTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:save];

    [PRMDebug noteAction:overlay ? @"save overlay" : @"save profile"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"on %@ %.0fx%.0f at %.0f,%.0f",
                         NSStringFromClass([carrier class]),
                         image.size.width, image.size.height, save.frame.origin.x, save.frame.origin.y]
                 forKey:overlay ? @"save overlay" : @"save profile"];
}

%end

