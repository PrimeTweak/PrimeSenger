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

// Measured on the previous pass:
//
//   menu height   227 -> 271 | row 44 | rows 1     the container grew by
//                                                  exactly one row height
//   menu shape    2 sections, last has 1 rows
//   menu cell     MSGContextMenuTableViewCell | UITableViewLabel(Reply) UIImageView
//
// So the container is sized from the table and the added row is not clipped.
// What never happened is the table asking for it: neither the cell nor the
// tap counter ever fired. That question was not instrumented, which is why
// this pass records the whole surface at once rather than one hypothesis.
//
// Everything that can keep a row from being asked for is covered here: which
// index paths are requested and in what order, the counts returned against
// the counts asked, the table's own frame and content size against the
// container's, the paging that splits items between the first page and the
// More page, the grouped and more-action flags, and a forced reload to see
// whether the row appears when the table is told to ask again.

static NSMutableDictionary<NSNumber *, NSNumber *> *gRows = nil;
static NSMutableArray<NSString *> *gAsks = nil;
static __weak UITableView *gTable = nil;
static NSInteger gSections = 0;
static NSInteger gLastSection = -1;
static NSInteger gMaxVisible = -1;
static CGFloat gRowHeight = 0;
static BOOL gReloadDone = NO;

static void PSGNoteAsk(NSString *what, NSIndexPath *path) {
    if (gAsks == nil) gAsks = [NSMutableArray array];
    [gAsks addObject:[NSString stringWithFormat:@"%@%ld.%ld",
                      what, (long)path.section, (long)path.row]];
    while (gAsks.count > 26) [gAsks removeObjectAtIndex:0];
    [PRMDebug setStatus:[gAsks componentsJoinedByString:@" "] forKey:@"menu asks"];
}

static BOOL PSGIsAddedRow(NSIndexPath *path) {
    if (gLastSection < 0 || path.section != gLastSection) return NO;
    NSNumber *count = gRows[@(gLastSection)];
    return count != nil && path.row == count.integerValue;
}

%hook MSGContextMenu

#pragma mark Construction

- (id)initWithMenuItems:(id)items
    maxNumberOfVisibleItems:(NSInteger)maxItems
            moreActionBlock:(id)block
           presentationStyle:(NSUInteger)style {
    id result = %orig;
    gMaxVisible = maxItems;
    [PRMDebug setStatus:[NSString stringWithFormat:@"plain | %lu items | max %ld | style %lu",
                         (unsigned long)([items isKindOfClass:[NSArray class]]
                                         ? [(NSArray *)items count] : 0),
                         (long)maxItems, (unsigned long)style]
                 forKey:@"menu init"];
    return result;
}

- (id)initWithGroupedMenuItems:(id)items
               moreActionBlock:(id)block
             presentationStyle:(NSUInteger)style {
    id result = %orig;
    [PRMDebug setStatus:[NSString stringWithFormat:@"grouped | %lu groups | style %lu",
                         (unsigned long)([items isKindOfClass:[NSArray class]]
                                         ? [(NSArray *)items count] : 0),
                         (unsigned long)style]
                 forKey:@"menu init"];
    return result;
}

- (id)initWithInfoView:(id)infoView
             menuItems:(id)items
    maxNumberOfVisibleItems:(NSInteger)maxItems
            moreActionBlock:(id)block
          presentationStyle:(NSUInteger)style {
    id result = %orig;
    gMaxVisible = maxItems;
    [PRMDebug setStatus:[NSString stringWithFormat:@"infoView | %lu items | max %ld | style %lu",
                         (unsigned long)([items isKindOfClass:[NSArray class]]
                                         ? [(NSArray *)items count] : 0),
                         (long)maxItems, (unsigned long)style]
                 forKey:@"menu init"];
    return result;
}

// A fresh presentation: the trace starts clean and the forced reload is armed
// again.
- (void)_setUpMenuView {
    [gAsks removeAllObjects];
    gReloadDone = NO;
    %orig;
    [PRMDebug noteHook:@"menu setup"];
}

#pragma mark Paging

// The main suspicion: items are split between the first page and the page
// behind the More action, and a row past the split is simply never asked for.
- (id)createPrimaryAndSecondaryPagesWithMenuItems:(id)items {
    id pages = %orig;
    NSString *shape = @"not an array";
    if ([pages isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *sizes = [NSMutableArray array];
        for (id page in (NSArray *)pages) {
            [sizes addObject:[page isKindOfClass:[NSArray class]]
                             ? [NSString stringWithFormat:@"%lu", (unsigned long)[(NSArray *)page count]]
                             : NSStringFromClass([page class])];
        }
        shape = [NSString stringWithFormat:@"in %lu -> pages [%@]",
                 (unsigned long)([items isKindOfClass:[NSArray class]]
                                 ? [(NSArray *)items count] : 0),
                 [sizes componentsJoinedByString:@","]];
    }
    [PRMDebug setStatus:shape forKey:@"menu pages"];
    return pages;
}

- (id)_createSecondaryRangesForMenuWithMenuItems:(id)items
                                      maxOptions:(int)maxOptions
                                  setsOfActions:(id)sets {
    id ranges = %orig;
    [PRMDebug setStatus:[NSString stringWithFormat:@"max %d | in %lu | out %@",
                         maxOptions,
                         (unsigned long)([items isKindOfClass:[NSArray class]]
                                         ? [(NSArray *)items count] : 0),
                         [ranges isKindOfClass:[NSArray class]]
                             ? [NSString stringWithFormat:@"%lu", (unsigned long)[(NSArray *)ranges count]]
                             : @"-"]
                 forKey:@"menu ranges"];
    return ranges;
}

- (BOOL)_menuContainsGroupedItems {
    BOOL grouped = %orig;
    [PRMDebug setStatus:grouped ? @"grouped" : @"flat" forKey:@"menu grouped"];
    return grouped;
}

- (BOOL)_isMoreActionSection:(NSInteger)section {
    BOOL more = %orig;
    if (more) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"section %ld is the More section",
                             (long)section]
                     forKey:@"menu more"];
    }
    return more;
}

#pragma mark Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger count = %orig;
    gTable = tableView;
    gSections = count;
    gLastSection = count - 1;
    if (gRows == nil) gRows = [NSMutableDictionary dictionary];
    [PRMDebug noteHook:@"menu probe"];
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = %orig;
    gTable = tableView;
    if (gRows == nil) gRows = [NSMutableDictionary dictionary];
    gRows[@(section)] = @(count);

    if (![PRMPrefs isEnabled:PRMKeySaveButton]) return count;
    if (section != gLastSection) return count;

    [PRMDebug noteAction:@"menu probe"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%ld sections | rows %@ | returning %ld for %ld",
                         (long)gSections, gRows, (long)(count + 1), (long)section]
                 forKey:@"menu shape"];
    return count + 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    PSGNoteAsk(@"h", path);
    if (PSGIsAddedRow(path)) {
        [PRMDebug noteHook:@"menu row height"];
        return gRowHeight > 0 ? gRowHeight : 44.0;
    }
    CGFloat height = %orig;
    if (height > 0) gRowHeight = height;
    return height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    PSGNoteAsk(@"c", path);

    if (!PSGIsAddedRow(path)) {
        UITableViewCell *cell = %orig;
        // The host's own cell, described once with frames and constraint
        // count, so the added row can be built from the real thing rather
        // than approximated.
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
                [parts addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f%@",
                                  NSStringFromClass([node class]),
                                  node.frame.origin.x, node.frame.origin.y,
                                  node.frame.size.width, node.frame.size.height,
                                  text.length ? [NSString stringWithFormat:@"(%@)", text] : @""]];
            }
            [PRMDebug setStatus:[NSString stringWithFormat:@"%@ h%.0f cons%lu | %@",
                                 NSStringFromClass([cell class]),
                                 cell.frame.size.height,
                                 (unsigned long)cell.contentView.constraints.count,
                                 [parts componentsJoinedByString:@" , "]]
                         forKey:@"menu cell"];
        }
        return cell;
    }

    [PRMDebug noteHook:@"menu row"];
    // The host's own cell class, so the row inherits its styling instead of
    // imitating it. Measured: MSGContextMenuTableViewCell, height 44, a
    // UITableViewLabel and a UIImageView, no constraints of its own.
    Class native = objc_getClass("MSGContextMenuTableViewCell");
    UITableViewCell *row = native
        ? [[native alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]
        : [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
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
    if (PSGIsAddedRow(path)) {
        [PRMDebug noteHook:@"menu row shown"];
        return;
    }
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

#pragma mark Geometry and forced reload

- (void)_updateMenuHeight {
    // The class is forward declared here, so self is held as id and the
    // selector is sent through a cast rather than messaged as its own type.
    id menu = self;
    id container = [menu respondsToSelector:@selector(getMenuView)]
                 ? ((id (*)(id, SEL))objc_msgSend)(menu, @selector(getMenuView))
                 : nil;
    CGRect before = [container isKindOfClass:[UIView class]]
                  ? ((UIView *)container).frame : CGRectZero;
    %orig;
    CGRect after = [container isKindOfClass:[UIView class]]
                 ? ((UIView *)container).frame : CGRectZero;

    UITableView *table = gTable;

    // Measured: the added row is counted and its height is asked for, but its
    // cell is never built. The table reports content 271 inside a frame of
    // 227, five rows worth, so the sixth falls below the fold and a table
    // never builds a cell it cannot show. Both the table and the container
    // are grown by one row here, after the host has set them.
    if ([PRMPrefs isEnabled:PRMKeySaveButton] && gRowHeight > 0 && table != nil) {
        CGFloat wanted = table.contentSize.height;
        if (wanted > table.frame.size.height) {
            CGFloat grow = wanted - table.frame.size.height;
            CGRect box = table.frame;
            box.size.height = wanted;
            table.frame = box;
            if ([container isKindOfClass:[UIView class]]) {
                CGRect outer = ((UIView *)container).frame;
                outer.size.height += grow;
                ((UIView *)container).frame = outer;
            }
            [PRMDebug noteAction:@"menu grown"];
            [PRMDebug setStatus:[NSString stringWithFormat:@"grew by %.0f to %.0f",
                                 grow, wanted]
                         forKey:@"menu grown"];
        }
    }

    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"container %.0f -> %.0f | table %.0fx%.0f content %.0f "
                          "inset %.0f/%.0f | row %.0f | max %ld",
                         before.size.height, after.size.height,
                         table.frame.size.width, table.frame.size.height,
                         table.contentSize.height,
                         table.contentInset.top, table.contentInset.bottom,
                         gRowHeight, (long)gMaxVisible]
                 forKey:@"menu height"];

    if (!gReloadDone && table != nil && [PRMPrefs isEnabled:PRMKeySaveButton]) {
        gReloadDone = YES;
        // Told to ask again once, on the next turn of the runloop, so the
        // trace shows whether the row is reachable at all or only skipped on
        // the first pass.
        dispatch_async(dispatch_get_main_queue(), ^{
            UITableView *again = gTable;
            if (again == nil) return;
            NSInteger rowsBefore = [again numberOfRowsInSection:MAX(gLastSection, 0)];
            [again reloadData];
            NSInteger rowsAfter = [again numberOfRowsInSection:MAX(gLastSection, 0)];
            [PRMDebug setStatus:[NSString stringWithFormat:
                                 @"rows %ld -> %ld | content %.0f | frame %.0f",
                                 (long)rowsBefore, (long)rowsAfter,
                                 again.contentSize.height, again.frame.size.height]
                         forKey:@"menu reload"];
        });
    }
}

%end
