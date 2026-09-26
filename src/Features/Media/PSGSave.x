// A save button on pictures Messenger gives no way to keep. Story and
// disappearing photos share one viewer; profile pictures have their own.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSInteger kPSGSaveButtonTag = 0x50534753;
static const char kPSGCarrierKey;

// The picture the button belongs to, held weakly. An unretained association
// would leave a dangling pointer if the host replaced its image view while
// the button stayed, and the next tap would crash on it.
@interface PSGWeakBox : NSObject
@property (nonatomic, weak) UIView *view;
@end

@implementation PSGWeakBox
@end

#pragma mark - Finding the picture

// Any view answering -image with a UIImage, largest first, so the picture
// wins over an avatar sharing the screen. A carrier covering most of the
// screen is a background, never the subject, and is refused.
static UIView *PSGImageBearingView(UIView *root, UIImage **out) {
    UIView *best = nil;
    UIImage *bestImage = nil;
    CGFloat bestArea = 0;
    CGFloat rootArea = root.bounds.size.width * root.bounds.size.height;

    NSMutableArray<UIView *> *queue = [@[root] mutableCopy];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:node.subviews];

        if (![node respondsToSelector:@selector(image)]) continue;
        id found = ((id (*)(id, SEL))objc_msgSend)(node, @selector(image));
        if (![found isKindOfClass:[UIImage class]]) continue;

        CGSize size = node.bounds.size;
        if (size.width < 80 || size.height < 80) continue;
        if (rootArea > 0 && size.width * size.height > rootArea * 0.8) continue;
        if (node.isHidden || node.alpha < 0.05) continue;

        CGFloat area = size.width * size.height;
        if (area > bestArea) { bestArea = area; best = node; bestImage = found; }
    }
    if (out != NULL) *out = bestImage;
    return best;
}

#pragma mark - Writing

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

- (void)write:(id)image from:(NSString *)route {
    if (![image isKindOfClass:[UIImage class]]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"%@: no image", route]
                     forKey:@"save media"];
        return;
    }
    UIImage *picture = image;
    [PRMDebug noteAction:@"save media"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@: writing %.0fx%.0f",
                         route, picture.size.width, picture.size.height]
                 forKey:@"save media"];
    UIImageWriteToSavedPhotosAlbum(
        picture, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image
    didFinishSavingWithError:(NSError *)error
                 contextInfo:(void *)contextInfo {
    [PRMDebug setStatus:(error == nil) ? @"saved" : error.localizedDescription
                 forKey:@"save media"];
}

// Bound at creation to the view it was placed on, rather than searching the
// screen again at tap time.
- (void)saveTapped:(UIButton *)sender {
    PSGWeakBox *box = objc_getAssociatedObject(sender, &kPSGCarrierKey);
    UIView *carrier = box.view;
    if (carrier == nil || ![carrier respondsToSelector:@selector(image)]) {
        [PRMDebug setStatus:@"button lost its view" forKey:@"save media"];
        return;
    }
    [self write:((id (*)(id, SEL))objc_msgSend)(carrier, @selector(image))
           from:NSStringFromClass([carrier class])];
}

@end

#pragma mark - The button

// Pinned to the top right of the picture itself rather than the screen, so it
// lands correctly without knowing either layout, and bound to that picture so
// the tap never has to search for it again.
static void PSGAddSaveButton(UIView *root, UIView *carrier, NSString *key) {
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
    PSGWeakBox *box = [[PSGWeakBox alloc] init];
    box.view = carrier;
    objc_setAssociatedObject(save, &kPSGCarrierKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [save addTarget:[PSGMediaSaver shared]
             action:@selector(saveTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:save];

    [PRMDebug noteAction:key];
    [PRMDebug setStatus:[NSString stringWithFormat:@"on %@ at %.0f,%.0f",
                         NSStringFromClass([carrier class]),
                         save.frame.origin.x, save.frame.origin.y]
                 forKey:key];
}

#pragma mark - The profile picture viewer

// The profile picture viewer, a Swift class matched by its runtime name and
// resolved once, so each layout pass only compares pointers.
static Class PSGProfileViewerClass(void) {
    static Class resolved = Nil;
    static BOOL tried = NO;
    if (!tried) {
        tried = YES;
        resolved = objc_getClass("LSThreadProfilePictureViewerSwift.LSProfilePictureViewController");
    }
    return resolved;
}

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeySaveButton]) return;

    Class wanted = PSGProfileViewerClass();
    if (wanted != Nil) {
        if (![self isKindOfClass:wanted]) return;
    } else {
        // Falls back to a one-time name match if the lookup fails.
        static Class matched = Nil;
        if (matched == Nil
            && [NSStringFromClass([self class]) containsString:@"LSProfilePictureViewController"]) {
            matched = [self class];
        }
        if (matched == Nil || ![self isKindOfClass:matched]) return;
    }

    [PRMDebug noteHook:@"save profile"];

    UIView *root = self.viewIfLoaded;
    if (root == nil) return;
    if ([root viewWithTag:kPSGSaveButtonTag] != nil) return;

    UIImage *image = nil;
    UIView *carrier = PSGImageBearingView(root, &image);
    if (carrier == nil) {
        [PRMDebug setStatus:@"no image yet" forKey:@"save profile"];
        return;
    }

    PSGAddSaveButton(root, carrier, @"save profile");
}

%end

#pragma mark - The shared photo viewer

// Stories, disappearing photos and ordinary fullscreen photos all arrive
// here. The class is forward declared, so self is held as id and its ivar is
// read through the runtime rather than messaged.
%hook LSMediaPhotoViewController

// Screenshot notice from the photo viewer. Kept here because Logos allows
// one block per class per file.
- (void)_handleUserDidTakeScreenshot:(id)note {
    [PRMDebug noteHook:@"screenshot photo"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screenshot photo"];
        [PRMDebug setStatus:@"photo notice swallowed" forKey:@"screenshot photo"];
        return;
    }
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeySaveButton]) return;
    [PRMDebug noteHook:@"save photo"];

    id controller = self;
    UIView *root = [controller respondsToSelector:@selector(viewIfLoaded)]
                 ? ((id (*)(id, SEL))objc_msgSend)(controller, @selector(viewIfLoaded))
                 : nil;
    if (![root isKindOfClass:[UIView class]]) return;
    if ([root viewWithTag:kPSGSaveButtonTag] != nil) return;

    Ivar slot = class_getInstanceVariable(object_getClass(controller), "_networkImageView");
    UIView *carrier = slot ? object_getIvar(controller, slot) : nil;
    if (![carrier isKindOfClass:[UIView class]] ||
        ![carrier respondsToSelector:@selector(image)]) {
        [PRMDebug setStatus:@"no network image view" forKey:@"save photo"];
        return;
    }

    id image = ((id (*)(id, SEL))objc_msgSend)(carrier, @selector(image));
    if (![image isKindOfClass:[UIImage class]]) {
        [PRMDebug setStatus:@"image not loaded yet" forKey:@"save photo"];
        return;
    }

    PSGAddSaveButton(root, carrier, @"save photo");
}

%end
