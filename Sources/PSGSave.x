// Saving media the app offers no button for.
//
// Two separate routes, because one cannot reach what the other does.
//
// Route 1, the long press on LSNetworkImageView. Reproduced from MSGPlusX's
// own build, read out of their binary:
//
//   %orig
//   if (!boolForKey) return;
//   g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:...];
//   [g setNumberOfTouchesRequired:1];
//   [g setMinimumPressDuration:...];
//   [self addGestureRecognizer:g];
//
// Three things they do not do, and an earlier attempt here did: no check for
// an already installed recogniser, no write to userInteractionEnabled, no
// delegate. That attempt installed 11 times and never fired once, so their
// form is taken literally instead. The recogniser count is reported, since
// without a check the view accumulates one per layout pass.
//
// Route 2, the profile picture viewer. Measured in the view tree:
//
//   === screen appeared: LSProfilePictureViewController ===
//     UIVisualEffectView
//     UIImageView (70,328 300x300)
//     MDSIconButton (16,78 44x44)  a11y="Close"
//
// A plain UIImageView, not an LSNetworkImageView, so route 1 can never see
// it. MSGPlusX cannot save a profile picture either. The controller is a
// Swift class, matched by name the way PSGScreens.x matches the Meta AI
// button rather than hooked directly.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static const NSInteger kPSGSaveButtonTag = 0x50534753;

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

// Route 1 target.
- (void)handleHold:(UIGestureRecognizer *)recognizer {
    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) trace = [NSMutableArray array];
    static const char *const names[] = {"possible","began","changed","ended","cancelled","failed"};
    NSInteger state = recognizer.state;
    [trace addObject:(state >= 0 && state < 6) ? @(names[state]) : @"?"];
    while (trace.count > 8) [trace removeObjectAtIndex:0];
    [PRMDebug setStatus:[trace componentsJoinedByString:@" "] forKey:@"hold gesture"];

    if (state != UIGestureRecognizerStateBegan) return;
    [PRMDebug noteAction:@"hold fired"];

    id view = recognizer.view;
    if (![view respondsToSelector:@selector(image)]) return;
    [self write:((id (*)(id, SEL))objc_msgSend)(view, @selector(image)) from:@"hold"];
}

// Route 2 target. The button carries the image view it was built beside.
- (void)saveTapped:(UIButton *)sender {
    UIView *root = sender.superview;
    UIImageView *best = nil;
    CGFloat area = 0;
    NSMutableArray<UIView *> *queue = [@[root] mutableCopy];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:node.subviews];
        if (![node isKindOfClass:[UIImageView class]]) continue;
        UIImageView *candidate = (UIImageView *)node;
        CGFloat size = candidate.bounds.size.width * candidate.bounds.size.height;
        if (candidate.image != nil && size > area) { area = size; best = candidate; }
    }
    [self write:best.image from:@"profile"];
}

@end

#pragma mark - Route 1

%hook LSNetworkImageView

- (void)layoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHoldToSave]) return;

    // Deliberately without a duplicate check, matching the reference build.
    UIView *view = (UIView *)self;
    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc] initWithTarget:[PSGMediaSaver shared]
                                                      action:@selector(handleHold:)];
    hold.numberOfTouchesRequired = 1;
    hold.minimumPressDuration = 0.5;
    [view addGestureRecognizer:hold];

    [PRMDebug noteHook:@"hold install"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%.0fx%.0f uie=%d recognisers=%lu",
                         view.bounds.size.width, view.bounds.size.height,
                         view.userInteractionEnabled,
                         (unsigned long)view.gestureRecognizers.count]
                 forKey:@"hold install"];
}

%end

#pragma mark - Route 2

%hook UIViewController

// viewDidLayoutSubviews rather than viewDidAppear:, which PSGScreens.x
// already owns on this class.
- (void)viewDidLayoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHoldToSave]) return;
    if (![NSStringFromClass([self class]) containsString:@"LSProfilePictureViewController"]) return;

    UIView *root = self.viewIfLoaded;
    if (root == nil || [root viewWithTag:kPSGSaveButtonTag] != nil) return;

    [PRMDebug noteHook:@"profile save"];

    // Placed opposite the host's own Close button, at the same size and on
    // the same line, so it reads as part of the screen rather than added on.
    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.tag = kPSGSaveButtonTag;
    save.frame = CGRectMake(root.bounds.size.width - 60, 78, 44, 44);
    save.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    save.tintColor = [UIColor whiteColor];
    save.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    save.layer.cornerRadius = 22;
    [save setImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
          forState:UIControlStateNormal];
    [save addTarget:[PSGMediaSaver shared]
             action:@selector(saveTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:save];

    [PRMDebug noteAction:@"profile save"];
    [PRMDebug setStatus:@"button added" forKey:@"profile save"];
}

%end
