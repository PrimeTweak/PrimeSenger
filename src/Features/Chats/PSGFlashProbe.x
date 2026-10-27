// Debug probe for the flash seen when a thread opens with the keyboard kept
// closed. For four seconds after the thread appears it records every change
// to the message list's content size and offset, each reload or batch update
// it receives with the caller, the keyboard frames, and the composer calls the
// option suppresses, so the reload that replaces the list can be attributed.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>

#if PRIMESENGER_DEBUG

static const NSTimeInterval kPSGFlashWindow = 4.0;

static NSTimeInterval gOpenAt = 0.0;
static __weak UICollectionView *gList = nil;

static NSTimeInterval PSGFlashElapsed(void) {
    return gOpenAt == 0.0 ? -1.0 : [NSDate timeIntervalSinceReferenceDate] - gOpenAt;
}

static BOOL PSGFlashOpen(void) {
    if (![PRMDebug recording]) return NO;
    NSTimeInterval dt = PSGFlashElapsed();
    return dt >= 0.0 && dt <= kPSGFlashWindow;
}

static void PSGFlashLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void PSGFlashLog(NSString *format, ...) {
    if (!PSGFlashOpen()) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [PRMDebug log:@"flash +%4.0fms %@", PSGFlashElapsed() * 1000.0, line];
}

// The frames of the host's own code, as image and offset, since its symbols
// are stripped; UIKit and the probe itself are left out.
static NSString *PSGFlashCaller(void) {
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *frame in [NSThread callStackSymbols]) {
        if (kept.count == 4) break;
        if ([frame containsString:@"UIKitCore"] || [frame containsString:@"PrimeSenger"]) continue;
        NSArray<NSString *> *parts = [frame componentsSeparatedByCharactersInSet:
                                      [NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray<NSString *> *words = [NSMutableArray array];
        for (NSString *part in parts) if (part.length) [words addObject:part];
        if (words.count < 2) continue;
        [kept addObject:[NSString stringWithFormat:@"%@%@", words[1],
                         words.count > 5 ? [@" +" stringByAppendingString:words.lastObject] : @""]];
    }
    return kept.count ? [kept componentsJoinedByString:@" < "] : @"-";
}

// Reads stored geometry only: asking the list for its counts can make it run
// a pending reload, which re-enters the hooks below.
static void PSGFlashSnap(NSString *tag) {
    UICollectionView *list = gList;
    if (list == nil) { PSGFlashLog(@"%@: no list", tag); return; }
    PSGFlashLog(@"%@: offset.y=%.1f inset.bottom=%.1f contentH=%.1f boundsH=%.1f",
                tag, list.contentOffset.y, list.adjustedContentInset.bottom,
                list.contentSize.height, list.bounds.size.height);
}

#pragma mark - Watcher

// Observes the list's offset and content size for the window, then lets go.
@interface PSGFlashWatcher : NSObject
@property (nonatomic, weak) UICollectionView *list;
@property (nonatomic, assign) CGPoint lastOffset;
@property (nonatomic, assign) CGSize lastSize;
@end

@implementation PSGFlashWatcher

- (void)attachTo:(UICollectionView *)list {
    self.list = list;
    self.lastOffset = list.contentOffset;
    self.lastSize = list.contentSize;
    [list addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:NULL];
    [list addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)detach {
    UICollectionView *list = self.list;
    if (list == nil) return;
    [list removeObserver:self forKeyPath:@"contentOffset"];
    [list removeObserver:self forKeyPath:@"contentSize"];
    self.list = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentSize"]) {
        CGSize size = [change[NSKeyValueChangeNewKey] CGSizeValue];
        if (fabs(size.height - self.lastSize.height) < 0.5) return;
        PSGFlashLog(@"contentSize %.1f -> %.1f  via %@", self.lastSize.height, size.height, PSGFlashCaller());
        self.lastSize = size;
    } else {
        CGPoint offset = [change[NSKeyValueChangeNewKey] CGPointValue];
        if (fabs(offset.y - self.lastOffset.y) < 0.5) return;
        PSGFlashLog(@"offset.y %.1f -> %.1f", self.lastOffset.y, offset.y);
        self.lastOffset = offset;
    }
}

@end

static PSGFlashWatcher *gWatcher = nil;

static UICollectionView *PSGFlashFindList(UIView *view, NSInteger depth) {
    if (view == nil || depth > 10) return nil;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UICollectionView class]] &&
            [NSStringFromClass([sub class]) containsString:@"MessageList"]) {
            return (UICollectionView *)sub;
        }
    }
    for (UIView *sub in view.subviews) {
        UICollectionView *found = PSGFlashFindList(sub, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

static void PSGFlashArmKeyboardLog(void) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSArray<NSString *> *names = @[UIKeyboardWillShowNotification, UIKeyboardDidShowNotification,
                                       UIKeyboardWillChangeFrameNotification, UIKeyboardWillHideNotification];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *note) {
                CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
                PSGFlashLog(@"keyboard %@: endY=%.0f h=%.0f",
                            [name stringByReplacingOccurrencesOfString:@"UIKeyboard" withString:@""],
                            end.origin.y, end.size.height);
            }];
        }
    });
}

#pragma mark - Thread open

%hook MSGMessageListViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![PRMDebug recording]) return;

    PSGFlashArmKeyboardLog();
    [gWatcher detach];
    gOpenAt = [NSDate timeIntervalSinceReferenceDate];
    gList = PSGFlashFindList(((UIViewController *)self).viewIfLoaded, 0);

    [PRMDebug log:@"flash === thread opened, keep-keyboard-closed=%@, list=%@ ===",
              [PRMPrefs isEnabled:PRMKeyNoAutoKeyboard] ? @"ON" : @"OFF",
              gList ? NSStringFromClass([gList class]) : @"NOT FOUND"];

    if (gList != nil) {
        gWatcher = [[PSGFlashWatcher alloc] init];
        [gWatcher attachTo:gList];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPSGFlashWindow * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [gWatcher detach]; });
    }

    PSGFlashSnap(@"t+0");
    for (NSNumber *mark in @[@0.3, @0.8, @1.6, @2.5, @3.9]) {
        NSString *tag = [NSString stringWithFormat:@"t+%.0fms", mark.doubleValue * 1000.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mark.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ PSGFlashSnap(tag); });
    }
}

%end

#pragma mark - List mutations

%hook MSGMessageListCollectionView

- (void)reloadData {
    if ((UICollectionView *)self == gList) {
        PSGFlashLog(@"reloadData  via %@", PSGFlashCaller());
    }
    %orig;
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    if ((UICollectionView *)self == gList) {
        PSGFlashLog(@"batchUpdates  via %@", PSGFlashCaller());
    }
    %orig;
}

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if ((UICollectionView *)self == gList) {
        PSGFlashLog(@"setContentOffset y=%.1f animated=%d  via %@", offset.y, animated, PSGFlashCaller());
    }
    %orig;
}

- (void)scrollToItemAtIndexPath:(NSIndexPath *)path
               atScrollPosition:(UICollectionViewScrollPosition)position
                       animated:(BOOL)animated {
    if ((UICollectionView *)self == gList) {
        PSGFlashLog(@"scrollToItem %ld/%ld position=%lu animated=%d",
                    (long)path.section, (long)path.item, (unsigned long)position, animated);
    }
    %orig;
}

- (void)setContentInset:(UIEdgeInsets)inset {
    if ((UICollectionView *)self == gList) {
        PSGFlashLog(@"setContentInset top=%.0f bottom=%.0f", inset.top, inset.bottom);
    }
    %orig;
}

%end

#pragma mark - Composer calls the option suppresses

%hook LSComposerViewController

- (void)_scheduleAutoOpenKeyboardAfterOpenComposerView {
    PSGFlashLog(@"composer schedule auto keyboard (option %@)",
                [PRMPrefs isEnabled:PRMKeyNoAutoKeyboard] ? @"ON: suppressed" : @"OFF: runs");
    %orig;
}

- (void)_autoOpenKeyboardAfterOpenComposerView {
    PSGFlashLog(@"composer auto keyboard (option %@)",
                [PRMPrefs isEnabled:PRMKeyNoAutoKeyboard] ? @"ON: suppressed" : @"OFF: runs");
    %orig;
}

%end

#endif
