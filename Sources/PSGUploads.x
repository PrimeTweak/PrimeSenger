// Two additions that reach media the permission gates cannot.
//
// HD uploads: the picker carries its own toggle and its own tap handler. The
// toggle is read before it is pressed, so an already enabled state is left
// alone rather than flipped back off.
//
//   -[LSMediaPickerViewController viewDidAppear:]     v20@0:8B16
//   -[LSMediaPickerViewController _didTapHDToggle:]   v24@0:8@16
//   ivar _hdToggleButton : UIButton
//   ivar _shouldPersistHdToggleState : B
//
// Hold to save: LSNetworkImageView is the image view of the whole app, so a
// long press on it reaches thumbnails, avatars and story frames, none of
// which offer a save button. The write goes through the system, not through
// Messenger, and the app already declares NSPhotoLibraryAddUsageDescription.
//
//   -[LSNetworkImageView layoutSubviews]  v16@0:8
//   -[LSNetworkImageView image]           @16@0:8

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Hold to save

// A subclass rather than a tag, so an already installed recogniser is
// recognised by its own type and never counted twice.
@interface PSGHoldRecognizer : UILongPressGestureRecognizer
@end

@implementation PSGHoldRecognizer
@end

@interface PSGImageSaver : NSObject
+ (instancetype)shared;
@end

@implementation PSGImageSaver

+ (instancetype)shared {
    static PSGImageSaver *saver = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ saver = [[PSGImageSaver alloc] init]; });
    return saver;
}

- (void)handleHold:(UIGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;

    id view = recognizer.view;
    if (![view respondsToSelector:@selector(image)]) {
        [PRMDebug setStatus:@"view carries no image" forKey:@"hold to save"];
        return;
    }

    UIImage *image = ((id (*)(id, SEL))objc_msgSend)(view, @selector(image));
    if (![image isKindOfClass:[UIImage class]]) {
        [PRMDebug setStatus:@"image is nil" forKey:@"hold to save"];
        return;
    }

    [PRMDebug noteAction:@"hold to save"];
    UIImageWriteToSavedPhotosAlbum(
        image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

// The system calls this back once the write has finished.
- (void)image:(UIImage *)image
    didFinishSavingWithError:(NSError *)error
                 contextInfo:(void *)contextInfo {
    [PRMDebug setStatus:(error == nil) ? @"saved" : error.localizedDescription
                 forKey:@"hold to save"];
}

@end

%hook LSNetworkImageView

- (void)layoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHoldToSave]) return;

    // The class is forward declared here, so self is used as a view through a
    // cast rather than messaged as its own type.
    UIView *view = (UIView *)self;
    for (UIGestureRecognizer *installed in view.gestureRecognizers) {
        if ([installed isKindOfClass:[PSGHoldRecognizer class]]) return;
    }

    [PRMDebug noteHook:@"hold to save"];
    PSGHoldRecognizer *hold =
        [[PSGHoldRecognizer alloc] initWithTarget:[PSGImageSaver shared]
                                           action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.6;
    // Other recognisers keep working, so a tap that opens the media viewer is
    // not swallowed by the hold.
    hold.cancelsTouchesInView = NO;

    view.userInteractionEnabled = YES;
    [view addGestureRecognizer:hold];
    [PRMDebug noteAction:@"hold to save"];
}

%end

#pragma mark - HD uploads

%hook LSMediaPickerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"hd upload"];
    if (![PRMPrefs isEnabled:PRMKeyUploadHD]) return;

    id picker = self;
    Ivar slot = class_getInstanceVariable(object_getClass(picker), "_hdToggleButton");
    if (slot == NULL) {
        [PRMDebug setStatus:@"hd toggle ivar missing" forKey:@"hd upload"];
        return;
    }

    id toggle = object_getIvar(picker, slot);
    if (![toggle isKindOfClass:[UIButton class]]) {
        [PRMDebug setStatus:@"hd toggle not a button" forKey:@"hd upload"];
        return;
    }

    // The selected state is read before and after, so the report says whether
    // it is the right reading of the toggle rather than assuming it.
    BOOL before = ((UIButton *)toggle).selected;
    if (before) {
        [PRMDebug setStatus:@"already on" forKey:@"hd upload"];
        return;
    }

    if (![picker respondsToSelector:@selector(_didTapHDToggle:)]) {
        [PRMDebug setStatus:@"tap handler missing" forKey:@"hd upload"];
        return;
    }

    [PRMDebug noteAction:@"hd upload"];
    ((void (*)(id, SEL, id))objc_msgSend)(picker, @selector(_didTapHDToggle:), toggle);

    [PRMDebug setStatus:[NSString stringWithFormat:@"selected %d -> %d",
                         before, ((UIButton *)toggle).selected]
                 forKey:@"hd upload"];
}

%end
