// Saving media the app offers no button for.
//
// History, all measured on this build:
//
//   The long press on LSNetworkImageView, copied from MSGPlusX to the letter,
//   installed 204 recognisers in one session and fired zero times. Removed.
//
//   A button placed on the screen that already shows the image works:
//     save button   ran 4  acted 4   on UIImageView 480x313
//   but it was bound to nothing. The tap searched the screen again from the
//   root and took the largest image it could find, which on a thread is the
//   conversation background rather than the photo. That is why the button
//   appeared over text messages and why tapping it did nothing useful.
//
// Two things follow. The button carries the exact view it was built for, and
// a carrier covering most of the screen is refused outright.
//
// The third part is a probe, not a feature. Putting the row in Messenger's
// own long press menu is where Save belongs, and every question that route
// raises is answered in one pass:
//
//   -[MSGContextMenu tableView:numberOfRowsInSection:]    q32@0:8@16q24
//   -[MSGContextMenu tableView:cellForRowAtIndexPath:]    @32@0:8@16@24
//   -[MSGContextMenu tableView:heightForRowAtIndexPath:]  d32@0:8@16@24
//   -[MSGContextMenu tableView:didSelectRowAtIndexPath:]  v32@0:8@16@24
//   -[MSGContextMenu getMenuItems]                        @16@0:8
//   -[MSGContextMenu _updateMenuHeight]                   v16@0:8
//
// The open question is whether the container is sized from the table, which
// would include an added row, or from getMenuItems, which would clip it. If
// it is the model, the row has to be a real MSGContextMenuItem, whose
// constructors are exported C functions whose argument types are not known
// yet.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSInteger kPSGSaveButtonTag = 0x50534753;
static const char kPSGCarrierKey;

// The picture last shown by a screen this file put a button on. Held weakly
// so a dismissed screen leaves nothing behind.
static __weak UIView *gLastCarrier = nil;

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
    UIView *carrier = objc_getAssociatedObject(sender, &kPSGCarrierKey);
    if (carrier == nil) {
        [PRMDebug setStatus:@"button lost its view" forKey:@"save media"];
        return;
    }
    [self write:((id (*)(id, SEL))objc_msgSend)(carrier, @selector(image))
           from:NSStringFromClass([carrier class])];
}

// Called from the added menu row, which has no button to carry a view.
- (void)saveLastCarrier {
    UIView *carrier = gLastCarrier;
    if (carrier == nil) {
        [PRMDebug setStatus:@"no carrier recorded" forKey:@"save media"];
        return;
    }
    [self write:((id (*)(id, SEL))objc_msgSend)(carrier, @selector(image))
           from:@"menu row"];
}

@end

#pragma mark - Save button

static BOOL PSGScreenWantsSaveButton(NSString *name) {
    return [name containsString:@"LSProfilePictureViewController"]
        || [name containsString:@"MSGMessageLongPressOverlayViewController"];
}

%hook UIViewController

// viewDidLayoutSubviews rather than viewDidAppear:, which PSGScreens.x
// already owns on this class.
- (void)viewDidLayoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeySaveButton]) return;

    NSString *name = NSStringFromClass([self class]);
    if (!PSGScreenWantsSaveButton(name)) return;

    // Counted at the door, before any guard, so a screen that appears without
    // a match is never confused with a screen that never appeared.
    BOOL overlay = [name containsString:@"LongPress"];
    NSString *key = overlay ? @"save overlay" : @"save profile";
    [PRMDebug noteHook:key];

    UIView *root = self.viewIfLoaded;
    if (root == nil) return;
    if ([root viewWithTag:kPSGSaveButtonTag] != nil) return;

    UIImage *image = nil;
    UIView *carrier = PSGImageBearingView(root, &image);

    if (carrier == nil) {
        // What the screen does hold, so a later pass aims at something
        // measured rather than another guess about the hierarchy.
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        NSMutableArray<UIView *> *queue = [@[root] mutableCopy];
        while (queue.count > 0 && seen.count < 30) {
            UIView *node = queue.firstObject;
            [queue removeObjectAtIndex:0];
            [queue addObjectsFromArray:node.subviews];
            CGSize size = node.bounds.size;
            if (size.width < 80 || size.height < 80) continue;
            [seen addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f%@",
                             NSStringFromClass([node class]), size.width, size.height,
                             [node respondsToSelector:@selector(image)] ? @" HASIMAGE" : @""]];
        }
        [PRMDebug setStatus:[NSString stringWithFormat:@"no match | %@",
                             [seen componentsJoinedByString:@" , "]]
                     forKey:key];
        return;
    }

    gLastCarrier = carrier;

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
    // Bound here, so the tap knows which picture it belongs to.
    objc_setAssociatedObject(save, &kPSGCarrierKey, carrier, OBJC_ASSOCIATION_ASSIGN);
    [save addTarget:[PSGMediaSaver shared]
             action:@selector(saveTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:save];

    [PRMDebug noteAction:key];
    [PRMDebug setStatus:[NSString stringWithFormat:@"on %@ %.0fx%.0f at %.0f,%.0f",
                         NSStringFromClass([carrier class]),
                         image.size.width, image.size.height,
                         save.frame.origin.x, save.frame.origin.y]
                 forKey:key];
}

%end

#pragma mark - Native menu probe

static NSInteger gMenuSections = 0;
static NSInteger gMenuLastSection = -1;
static NSInteger gMenuRowsInLast = 0;
static CGFloat gMenuRowHeight = 0;

static BOOL PSGIsAddedRow(NSIndexPath *path) {
    return gMenuLastSection >= 0
        && path.section == gMenuLastSection
        && path.row == gMenuRowsInLast;
}

%hook MSGContextMenu

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger count = %orig;
    gMenuSections = count;
    gMenuLastSection = count - 1;
    [PRMDebug noteHook:@"menu probe"];
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = %orig;
    if (![PRMPrefs isEnabled:PRMKeySaveButton]) return count;
    if (section != gMenuLastSection) return count;

    gMenuRowsInLast = count;
    [PRMDebug noteAction:@"menu probe"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%ld sections, last has %ld rows",
                         (long)gMenuSections, (long)count]
                 forKey:@"menu shape"];
    return count + 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    if (PSGIsAddedRow(path)) return gMenuRowHeight > 0 ? gMenuRowHeight : 44.0;
    CGFloat height = %orig;
    // The host's own height, reused for the added row so it never stands out.
    if (height > 0) gMenuRowHeight = height;
    return height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    if (!PSGIsAddedRow(path)) {
        UITableViewCell *cell = %orig;
        // The host's own cell, described once, so a later pass can match its
        // look instead of approximating it.
        static BOOL described = NO;
        if (!described && cell != nil) {
            described = YES;
            NSMutableArray<NSString *> *parts = [NSMutableArray array];
            NSMutableArray<UIView *> *queue = [cell.contentView.subviews mutableCopy];
            while (queue.count > 0 && parts.count < 12) {
                UIView *node = queue.firstObject;
                [queue removeObjectAtIndex:0];
                [queue addObjectsFromArray:node.subviews];
                NSString *text = [node isKindOfClass:[UILabel class]]
                               ? ([(UILabel *)node text] ?: @"") : @"";
                [parts addObject:[NSString stringWithFormat:@"%@%@",
                                  NSStringFromClass([node class]),
                                  text.length ? [NSString stringWithFormat:@"(%@)", text] : @""]];
            }
            [PRMDebug setStatus:[NSString stringWithFormat:@"%@ | %@",
                                 NSStringFromClass([cell class]),
                                 [parts componentsJoinedByString:@" "]]
                         forKey:@"menu cell"];
        }
        return cell;
    }

    [PRMDebug noteHook:@"menu row"];
    UITableViewCell *row = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                  reuseIdentifier:nil];
    row.backgroundColor = [UIColor clearColor];
    row.textLabel.text = @"Save";
    row.textLabel.font = [UIFont systemFontOfSize:16];
    row.textLabel.textColor = [UIColor labelColor];
    row.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
    row.imageView.tintColor = [UIColor labelColor];
    [PRMDebug noteAction:@"menu row"];
    return row;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    // The original is not called for the added row: the host's model has no
    // entry at this index.
    if (!PSGIsAddedRow(path)) {
        %orig;
        return;
    }
    [PRMDebug noteHook:@"menu tap"];
    [PRMDebug noteAction:@"menu tap"];
    [[PSGMediaSaver shared] saveLastCarrier];
}

- (void)tableView:(UITableView *)tableView
    willDisplayCell:(UITableViewCell *)cell
  forRowAtIndexPath:(NSIndexPath *)path {
    if (PSGIsAddedRow(path)) return;
    %orig;
}

- (id)getMenuItems {
    id items = %orig;
    NSString *shape = @"not an array";
    if ([items isKindOfClass:[NSArray class]]) {
        NSArray *list = items;
        shape = [NSString stringWithFormat:@"%lu items, first %@",
                 (unsigned long)list.count,
                 list.count ? NSStringFromClass([list.firstObject class]) : @"-"];
    }
    [PRMDebug setStatus:shape forKey:@"menu items"];
    return items;
}

// The question that decides the whole route: is the container sized from the
// table, which would include the added row, or from the model, which would
// clip it.
- (void)_updateMenuHeight {
    // The class is forward declared here, so self is held as id and the
    // selector is sent through a cast rather than messaged as its own type.
    id menu = self;
    id view = [menu respondsToSelector:@selector(getMenuView)]
            ? ((id (*)(id, SEL))objc_msgSend)(menu, @selector(getMenuView))
            : nil;
    CGRect before = [view isKindOfClass:[UIView class]] ? ((UIView *)view).frame : CGRectZero;
    %orig;
    CGRect after = [view isKindOfClass:[UIView class]] ? ((UIView *)view).frame : CGRectZero;
    [PRMDebug setStatus:[NSString stringWithFormat:@"%.0f -> %.0f | row %.0f | rows %ld",
                         before.size.height, after.size.height,
                         gMenuRowHeight, (long)gMenuRowsInLast]
                 forKey:@"menu height"];
}

%end
