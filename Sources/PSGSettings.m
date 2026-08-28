#import "PSGSettings.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGHelp.h"

// Metrics read off the native settings screen.
static const CGFloat kRowHeight      = 52.0;
static const CGFloat kIconSize       = 24.0;
static const CGFloat kIconLeading    = 18.0;
static const CGFloat kTextLeading    = 62.0;

// Section headings, measured against Messenger's own: bold, sentence case,
// secondary grey, sitting on the card's leading edge. Nothing like the small
// grey capitals UIKit draws by default.
static const CGFloat kHeaderLeading  = 20.0;
static const CGFloat kHeaderSize     = 15.0;
static const CGFloat kHeaderHeight   = 42.0;
static const CGFloat kHeaderFirst    = 30.0;
static const CGFloat kHeaderBaseline = 8.0;

// The pill keeps one gap from the toggle. The offset used to include the
// accessory's own width, but contentView already stops before the accessory,
// so counting it again pushed the pill a full toggle clear of the switch.
static const CGFloat kPillHeight    = 24.0;
static const CGFloat kPillMinWidth  = 54.0;
static const CGFloat kPillTrailing  = 10.0;
static const CGFloat kPillLabelGap  = 10.0;

// The group's info button sits in the heading, at the trailing edge, so it
// mirrors the title across the card and costs no vertical space.
static const CGFloat kInfoSize      = 22.0;
static const CGFloat kInfoGlyphSize = 20.0;
static const CGFloat kInfoTitleGap  = 8.0;

#pragma mark - Row

typedef NS_ENUM(NSInteger, PSGRowKind) {
    PSGRowKindSwitch,
    PSGRowKindAction,
};

@interface PSGSettingsRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) BOOL inverted;
@property (nonatomic, assign) PSGRowKind kind;
@property (nonatomic, assign) SEL action;
// Auxiliary preference offered beside the switch, shown only while the main
// switch is on. Nil for an ordinary row.
@property (nonatomic, copy) NSString *auxKey;
@property (nonatomic, copy) NSString *auxOnTitle;
@property (nonatomic, copy) NSString *auxOffTitle;
@end

@implementation PSGSettingsRow

+ (instancetype)switchRow:(NSString *)title
                   symbol:(NSString *)symbol
                      key:(NSString *)key
                 inverted:(BOOL)inverted {
    PSGSettingsRow *row = [[PSGSettingsRow alloc] init];
    row.title = title;
    row.symbol = symbol;
    row.key = key;
    row.inverted = inverted;
    row.kind = PSGRowKindSwitch;
    return row;
}

+ (instancetype)switchRow:(NSString *)title
                   symbol:(NSString *)symbol
                      key:(NSString *)key
                   auxKey:(NSString *)auxKey
               auxOnTitle:(NSString *)auxOnTitle
              auxOffTitle:(NSString *)auxOffTitle {
    PSGSettingsRow *row = [self switchRow:title symbol:symbol key:key inverted:NO];
    row.auxKey = auxKey;
    row.auxOnTitle = auxOnTitle;
    row.auxOffTitle = auxOffTitle;
    return row;
}

+ (instancetype)actionRow:(NSString *)title action:(SEL)action {
    PSGSettingsRow *row = [[PSGSettingsRow alloc] init];
    row.title = title;
    row.action = action;
    row.kind = PSGRowKindAction;
    return row;
}

// A switch shows whether the thing is present. For a preference that stores
// "hide this", that is the opposite of what is stored.
- (BOOL)displayedState {
    BOOL stored = [PRMPrefs isEnabled:self.key];
    return self.inverted ? !stored : stored;
}

- (void)applyDisplayedState:(BOOL)on {
    [PRMPrefs setEnabled:(self.inverted ? !on : on) forKey:self.key];
}

@end

#pragma mark - Cell

@interface PSGSettingsCell : UITableViewCell
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UIButton *pill;
@end

@implementation PSGSettingsCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self == nil) return nil;

    _glyph = [[UIImageView alloc] initWithFrame:CGRectZero];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.tintColor = [UIColor labelColor];
    [self.contentView addSubview:_glyph];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.font = [UIFont systemFontOfSize:16.0];
    _label.textColor = [UIColor labelColor];
    [self.contentView addSubview:_label];

    _toggle = [[UISwitch alloc] init];
    // The host's blue rather than the system green.
    _toggle.onTintColor = [UIColor colorWithRed:0.031 green:0.400 blue:1.0 alpha:1.0];

    _pill = [UIButton buttonWithType:UIButtonTypeSystem];
    _pill.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    _pill.backgroundColor = [UIColor tertiarySystemFillColor];
    _pill.layer.cornerRadius = 12.0;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 11.0);
    _pill.hidden = YES;
    [self.contentView addSubview:_pill];
    self.accessoryView = _toggle;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.contentView.bounds.size.height;
    self.glyph.frame = CGRectMake(kIconLeading, (height - kIconSize) / 2.0,
                                  kIconSize, kIconSize);

    CGFloat right = self.accessoryView ? self.accessoryView.bounds.size.width + 12.0 : 16.0;

    if (!self.pill.hidden) {
        [self.pill sizeToFit];
        CGFloat pillWidth = MAX(self.pill.bounds.size.width, kPillMinWidth);
        self.pill.frame = CGRectMake(
            self.contentView.bounds.size.width - kPillTrailing - pillWidth,
            (height - kPillHeight) / 2.0, pillWidth, kPillHeight);
        // The label stops one gap short of the pill. Taken as the larger of
        // the two insets so a row without an accessory keeps its own margin.
        right = MAX(right, kPillTrailing + pillWidth + kPillLabelGap);
    }

    CGFloat left = self.glyph.hidden ? kIconLeading : kTextLeading;
    self.label.frame = CGRectMake(left, 0.0,
                                  self.contentView.bounds.size.width - left - right,
                                  height);
}

@end

#pragma mark - Header

@interface PSGSettingsHeader : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIButton *info;
@end

@implementation PSGSettingsHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;
    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.font = [UIFont systemFontOfSize:kHeaderSize weight:UIFontWeightSemibold];
    // The host uses a darker grey than the system secondary label.
    _label.textColor = [UIColor colorWithRed:0.396 green:0.404 blue:0.420 alpha:1.0];
    [self addSubview:_label];

    _info = [UIButton buttonWithType:UIButtonTypeSystem];
    _info.tintColor = _label.textColor;
    _info.accessibilityLabel = @"What these do";
    _info.hidden = YES;
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kInfoGlyphSize
                                                        weight:UIFontWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:@"info.circle" withConfiguration:configuration];
    if (glyph != nil) {
        [_info setImage:glyph forState:UIControlStateNormal];
    } else {
        [PRMDebug log:@"symbol info.circle not available"];
        _info.titleLabel.font = [UIFont systemFontOfSize:kHeaderSize weight:UIFontWeightBold];
        [_info setTitle:@"i" forState:UIControlStateNormal];
        [_info setTitleColor:_label.textColor forState:UIControlStateNormal];
    }
    [self addSubview:_info];
    return self;
}

// The text sits on the baseline just above the card rather than centred, so
// the gap below it matches the native spacing.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = ceil(self.label.font.lineHeight);
    CGFloat top = self.bounds.size.height - height - kHeaderBaseline;
    CGFloat reserved = self.info.hidden ? 0.0 : kInfoSize + kInfoTitleGap;

    self.label.frame = CGRectMake(kHeaderLeading, top,
                                  self.bounds.size.width - kHeaderLeading * 2.0 - reserved,
                                  height);

    // Centred on the title rather than on the view, so it holds its place
    // whatever height the heading is given.
    self.info.frame = CGRectMake(self.bounds.size.width - kHeaderLeading - kInfoSize,
                                 top + (height - kInfoSize) / 2.0,
                                 kInfoSize, kInfoSize);
}

@end

#pragma mark - Controller

@interface PSGSettingsViewController ()
@property (nonatomic, strong) NSArray<NSArray<PSGSettingsRow *> *> *sections;
// The verb lives here rather than at the start of every row. Repeating
// "Hide" eight times was pushing the longest labels into an ellipsis.
@property (nonatomic, strong) NSArray<NSString *> *titles;
// One entry per section, each a list of pairs: a control's own label, then
// a sentence describing it. Kept beside the rows so the two cannot drift.
@property (nonatomic, strong) NSArray<NSArray<NSArray<NSString *> *> *> *help;
@end

@implementation PSGSettingsViewController

+ (UIViewController *)presentable {
    PSGSettingsViewController *settings =
        [[PSGSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:settings];
    return navigation;
}

// Falls back to a plain circle when a symbol name is not present on this
// system, and says so in the log rather than showing nothing.
- (UIImage *)glyphNamed:(NSString *)name {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:configuration];
    if (image == nil) {
        [PRMDebug log:@"symbol %@ not available", name];
        image = [UIImage systemImageNamed:@"circle.fill" withConfiguration:configuration];
    }
    return image;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PrimeSenger";
    // A custom view rather than the system Done item: iOS 26 renders that
    // item in a prominent style whose glyph colour overrides tintColor,
    // leaving it white on a light sheet.
    UIImageSymbolConfiguration *check =
        [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    closeButton.tintColor = [UIColor labelColor];
    closeButton.accessibilityLabel = @"Done";
    [closeButton addTarget:self
                    action:@selector(close)
          forControlEvents:UIControlEventTouchUpInside];

    UIImage *glyph = [UIImage systemImageNamed:@"checkmark" withConfiguration:check];
    if (glyph != nil) {
        [closeButton setImage:glyph forState:UIControlStateNormal];
    } else {
        [closeButton setTitle:@"Done" forState:UIControlStateNormal];
        [closeButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithCustomView:closeButton];

    self.tableView.rowHeight = kRowHeight;
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, kTextLeading, 0.0, 0.0);
    [self.tableView registerClass:[PSGSettingsCell class] forCellReuseIdentifier:@"row"];

    // Grouped by the place the thing appears, not by whether the switch
    // adds or removes. Four rows used to sit under "Hide in chats" while
    // their hooks were on the thread list, the search bar and the inbox
    // rows; they are with the list they act on now.
    self.titles = @[@"Conversations", @"Chat list", @"Notifications", @"Stories",
                    @"Media", @"Tab bar", @"Diagnostics", @""];

    self.sections = @[
        @[[PSGSettingsRow switchRow:@"Read receipts" symbol:@"eye.fill"
                                key:PRMKeyReadAnonymously
                             auxKey:PRMKeyReadReceiptsManual
                         auxOnTitle:@"Manual" auxOffTitle:@"Off"],
          [PSGSettingsRow switchRow:@"Typing indicator" symbol:@"ellipsis.bubble.fill"
                                key:PRMKeyHideTypingIndicator inverted:NO],
          [PSGSettingsRow switchRow:@"Keep keyboard closed"
                             symbol:@"keyboard.chevron.compact.down"
                                key:PRMKeyNoAutoKeyboard inverted:NO],
          [PSGSettingsRow switchRow:@"Confirm before calling" symbol:@"phone.fill"
                                key:PRMKeyCallConfirmation inverted:NO],
          [PSGSettingsRow switchRow:@"Quick reaction" symbol:@"face.smiling.fill"
                                key:PRMKeyHideQuickReaction inverted:NO]],

        @[[PSGSettingsRow switchRow:@"Stories tray" symbol:@"person.3.fill"
                                key:PRMKeyHideStoriesTray inverted:NO],
          [PSGSettingsRow switchRow:@"People you may know" symbol:@"person.2.fill"
                                key:PRMKeyHidePeopleYouMayKnow inverted:NO],
          [PSGSettingsRow switchRow:@"Meta AI in search" symbol:@"magnifyingglass"
                                key:PRMKeyHideMetaAI inverted:NO],
          [PSGSettingsRow switchRow:@"Meta AI button" symbol:@"sparkles"
                                key:PRMKeyHideMetaAIButton inverted:NO]],

        @[[PSGSettingsRow switchRow:@"People you may know" symbol:@"bell.fill"
                                key:PRMKeyHidePymkInNotifications inverted:NO]],

        @[[PSGSettingsRow switchRow:@"Story views" symbol:@"eye.circle.fill"
                                key:PRMKeyStoriesAnonymously inverted:NO],
          [PSGSettingsRow switchRow:@"Reply bar" symbol:@"bubble.left.fill"
                                key:PRMKeyHideStoryReplyBar inverted:NO],
          [PSGSettingsRow switchRow:@"Screenshot alerts" symbol:@"camera.fill"
                                key:PRMKeyBlockScreenshotNotice inverted:NO]],

        @[[PSGSettingsRow switchRow:@"Saving & forwarding"
                             symbol:@"square.and.arrow.down.fill"
                                key:PRMKeyUnlockMedia inverted:NO],
          [PSGSettingsRow switchRow:@"Censored media"
                             symbol:@"exclamationmark.triangle.fill"
                                key:PRMKeyRevealCensored inverted:NO],
          [PSGSettingsRow switchRow:@"View once media" symbol:@"1.circle.fill"
                                key:PRMKeyViewOnce inverted:NO],
          [PSGSettingsRow switchRow:@"Loop videos" symbol:@"repeat"
                                key:PRMKeyLoopVideos inverted:NO],
          [PSGSettingsRow switchRow:@"HD uploads" symbol:@"arrow.up.circle.fill"
                                key:PRMKeyUploadHD inverted:NO],
          [PSGSettingsRow switchRow:@"Hold to save" symbol:@"hand.tap.fill"
                                key:PRMKeyHoldToSave inverted:NO]],

        @[[PSGSettingsRow switchRow:@"Liquid Glass" symbol:@"drop.fill"
                                key:PRMKeyGlassTabBar inverted:NO],
          [PSGSettingsRow switchRow:@"Chats" symbol:@"message.fill"
                                key:PRMKeyHideTabChats inverted:NO],
          [PSGSettingsRow switchRow:@"Stories" symbol:@"play.rectangle.fill"
                                key:PRMKeyHideTabStories inverted:NO],
          [PSGSettingsRow switchRow:@"Notifications" symbol:@"bell.badge.fill"
                                key:PRMKeyHideTabNotifications inverted:NO],
          [PSGSettingsRow switchRow:@"Menu" symbol:@"line.3.horizontal"
                                key:PRMKeyHideTabMenu inverted:NO]],

        @[[PSGSettingsRow switchRow:@"Logging" symbol:@"doc.text.fill"
                                key:PRMKeyDebugEnabled inverted:NO],
          [PSGSettingsRow switchRow:@"Floating access button"
                             symbol:@"circle.grid.cross.fill"
                                key:PRMKeyFloatingButton inverted:NO],
          [PSGSettingsRow switchRow:@"FLEX explorer" symbol:@"scope"
                                key:PRMKeyFlexEnabled inverted:NO],
          [PSGSettingsRow actionRow:@"Copy everything" action:@selector(copyReport)],
          [PSGSettingsRow actionRow:@"Run full scan" action:@selector(runScan)],
          [PSGSettingsRow actionRow:@"Capture in 8 seconds" action:@selector(captureLater)],
          [PSGSettingsRow actionRow:@"Open debug report" action:@selector(openReport)]],

        @[[PSGSettingsRow switchRow:@"Pause PrimeSenger" symbol:@"pause.circle.fill"
                                key:PRMKeyMasterDisable inverted:NO]],
    ];

    // Written from the hook each switch drives, not from its label. Kept in
    // the same order as the rows above.
    self.help = @[
        @[@[@"Read receipts",
            @"Nobody sees when you open a chat. With Manual on, an eye sits in the "
             "conversation header, and tapping it sends a single receipt by hand."],
          @[@"Typing indicator",
            @"Stops the three dots from being sent while you type. You still see theirs."],
          @[@"Keep keyboard closed",
            @"The keyboard no longer opens by itself when you enter a chat. Tapping "
             "the message field still opens it."],
          @[@"Confirm before calling",
            @"Asks first when you tap a call button, so a mis-tap in the header does "
             "not ring anyone."],
          @[@"Quick reaction",
            @"With the field empty, the composer shows an emoji that sends on a "
             "single tap. This keeps the send button there instead."]],

        @[@[@"Stories tray",
            @"Removes the row of story bubbles from the top of the conversation list."],
          @[@"People you may know",
            @"Removes the suggested contacts from the end of the conversation list."],
          @[@"Meta AI in search",
            @"The search field reads Search instead of offering Meta AI."],
          @[@"Meta AI button",
            @"Removes the floating Meta AI button from the conversation list."]],

        @[@[@"People you may know",
            @"Removes suggested contacts from the Notifications tab."]],

        @[@[@"Story views",
            @"Watch a story without appearing in its viewer list."],
          @[@"Reply bar",
            @"Removes the reply field from the bottom of a story."],
          @[@"Screenshot alerts",
            @"Messenger tells the other person when you capture their story or a "
             "disappearing photo. This stops that message from being sent."]],

        @[@[@"Saving & forwarding",
            @"Opens every action Messenger refuses on a photo or video: saving, "
             "copying, sharing, forwarding, replying, editing, Live Text, adding "
             "to a story or a shared album. Ordinary media already allows most of "
             "these, so the switch only shows on the ones it blocks."],
          @[@"Censored media",
            @"Shows media Messenger covers with a warning, without the tap to reveal."],
          @[@"View once media",
            @"A View once photo or video normally burns the first time you open it. "
             "This keeps it from being marked as opened, so it stays there."],
          @[@"Loop videos",
            @"A video restarts from the beginning instead of stopping at the end."],
          @[@"HD uploads",
            @"Turns the HD switch on in the photo picker every time it opens, so "
             "photos are sent at full quality without setting it by hand."],
          @[@"Hold to save",
            @"Hold any picture in the app to write it to your camera roll, "
             "including thumbnails and avatars that offer no save button."]],

        @[@[@"Liquid Glass",
            @"Places a real iOS tab bar inside Messenger's own, so the bar picks up "
             "the system's Liquid Glass. Taps are handed back to Messenger, so "
             "nothing about navigation changes."],
          @[@"Chats, Stories, Notifications, Menu",
            @"Each switch removes that tab from the bar. Hiding all four leaves the "
             "bar empty."]],

        @[@[@"Logging",
            @"Records what the tweak does into a 4000 line buffer while Messenger "
             "runs. Leave it off unless you are measuring something."],
          @[@"Floating access button",
            @"A round button over Messenger. Tap it to open these settings, hold it "
             "to open FLEX, drag it to move it."],
          @[@"FLEX explorer",
            @"Apple's view inspector. Opened by holding the floating button."],
          @[@"Copy everything",
            @"Puts the whole report on the clipboard."],
          @[@"Run full scan",
            @"Lists every class the tweak knows about, then copies the report."],
          @[@"Capture in 8 seconds",
            @"Closes settings, waits eight seconds, then records the screen you "
             "ended up on."],
          @[@"Open debug report",
            @"Closes settings and shows the report on screen."]],

        @[@[@"Pause PrimeSenger",
            @"Suspends every removal and every added control at once, without "
             "touching your switches. Turn it off and they all come back."]],
    ];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

// The header and footer views are left to the system: in an inset-grouped
// table they carry the rounded card background, and replacing them with
// empty views destroys it.
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = self.titles[(NSUInteger)section];
    BOOL explained = [self helpForSection:section] != nil;
    if (title.length == 0 && !explained) return nil;

    PSGSettingsHeader *header = [[PSGSettingsHeader alloc] initWithFrame:CGRectZero];
    header.label.text = title;
    header.info.hidden = !explained;
    if (explained) {
        header.info.tag = section;
        [header.info addTarget:self
                        action:@selector(infoTapped:)
              forControlEvents:UIControlEventTouchUpInside];
    }
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *title = self.titles[(NSUInteger)section];
    // A group with no heading still needs the full height once it carries an
    // info button, so the button is not cropped by the shorter spacer.
    if (title.length == 0) {
        return [self helpForSection:section] != nil ? kHeaderHeight : kHeaderFirst;
    }
    return section == 0 ? kHeaderFirst + kHeaderBaseline : kHeaderHeight;
}

- (NSArray<NSArray<NSString *> *> *)helpForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.help.count) return nil;
    NSArray<NSArray<NSString *> *> *items = self.help[(NSUInteger)section];
    return items.count > 0 ? items : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

// A group with no heading takes its title from its single entry.
- (void)infoTapped:(UIButton *)button {
    NSArray<NSArray<NSString *> *> *items = [self helpForSection:button.tag];
    if (items == nil) return;

    NSString *title = self.titles[(NSUInteger)button.tag];
    if (title.length == 0) title = items.firstObject.firstObject;

    [PSGHelpSheet presentFrom:self title:title items:items];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGSettingsRow *row = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"
                                                            forIndexPath:indexPath];

    cell.label.text = row.title;

    if (row.kind == PSGRowKindAction) {
        cell.glyph.hidden = YES;
        cell.label.textColor = self.view.tintColor;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    cell.glyph.hidden = NO;
    cell.glyph.image = [self glyphNamed:row.symbol];
    cell.label.textColor = [UIColor labelColor];
    cell.accessoryView = cell.toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    BOOL mainOn = [row displayedState];
    cell.toggle.on = mainOn;
    cell.toggle.tag = indexPath.section * 100 + indexPath.row;

    if (row.auxKey != nil && mainOn) {
        BOOL auxOn = [PRMPrefs isEnabled:row.auxKey];
        [cell.pill setTitle:(auxOn ? row.auxOnTitle : row.auxOffTitle)
                   forState:UIControlStateNormal];
        [cell.pill setTitleColor:(auxOn ? [UIColor labelColor]
                                        : [UIColor secondaryLabelColor])
                        forState:UIControlStateNormal];
        cell.pill.hidden = NO;
        cell.pill.tag = cell.toggle.tag;
        [cell.pill removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.pill addTarget:self
                      action:@selector(pillTapped:)
            forControlEvents:UIControlEventTouchUpInside];
    } else {
        cell.pill.hidden = YES;
    }
    [cell setNeedsLayout];
    [cell.toggle removeTarget:self action:NULL
             forControlEvents:UIControlEventValueChanged];
    [cell.toggle addTarget:self
                    action:@selector(toggleChanged:)
          forControlEvents:UIControlEventValueChanged];
    return cell;
}

// The grouped background the system draws was arriving out of step with the
// content, leaving some sections without a card while the rest scrolled over
// one. Each cell now carries its own, rounded only on the edges of its
// group, so there is nothing left to desynchronise.
- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger count = [tableView numberOfRowsInSection:indexPath.section];
    CACornerMask corners = 0;
    if (indexPath.row == 0) {
        corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (indexPath.row == count - 1) {
        corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }

    UIView *card = [[UIView alloc] initWithFrame:cell.bounds];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
    card.layer.cornerRadius = 14.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.maskedCorners = corners;

    cell.backgroundView = card;
    cell.backgroundColor = [UIColor clearColor];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSGSettingsRow *row = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    if (row.kind != PSGRowKindAction || row.action == NULL) return;

    IMP implementation = [self methodForSelector:row.action];
    void (*call)(id, SEL) = (void (*)(id, SEL))implementation;
    call(self, row.action);
}

- (PSGSettingsRow *)rowForTag:(NSInteger)tag {
    NSInteger section = tag / 100;
    NSInteger index = tag % 100;
    if (section < 0 || section >= (NSInteger)self.sections.count) return nil;
    NSArray<PSGSettingsRow *> *rows = self.sections[(NSUInteger)section];
    if (index < 0 || index >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)index];
}

- (void)pillTapped:(UIButton *)pill {
    PSGSettingsRow *row = [self rowForTag:pill.tag];
    if (row == nil || row.auxKey == nil) return;

    BOOL next = ![PRMPrefs isEnabled:row.auxKey];
    [PRMPrefs setEnabled:next forKey:row.auxKey];
    [PRMDebug log:@"%@ aux %@ (%@)", row.title, next ? @"on" : @"off", row.auxKey];

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
                                         initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch *)toggle {
    NSInteger section = toggle.tag / 100;
    NSInteger index = toggle.tag % 100;
    if (section < 0 || section >= (NSInteger)self.sections.count) return;
    NSArray<PSGSettingsRow *> *rows = self.sections[(NSUInteger)section];
    if (index < 0 || index >= (NSInteger)rows.count) return;

    PSGSettingsRow *row = rows[(NSUInteger)index];
    [row applyDisplayedState:toggle.isOn];
    [self noteRestartIfTabRow:row];
    [PRMDebug refreshFloatingButton];
    // A switch can change which slot applies, so a moved button returns.
    [PRMDebug returnButtonToSlot];
    if (row.auxKey != nil) [self.tableView reloadData];

    // The explorer lives in its own window above everything, so this sheet
    // is dismissed to leave it visible.
    if ([row.key isEqualToString:PRMKeyFlexEnabled]) {
        [PRMDebug toggleFlex];
        if (toggle.on) [self close];
    }

    BOOL storedNow = [PRMPrefs isEnabled:row.key];
    [PRMDebug log:@"%@ shown %@, stored %@ (%@)",
                  row.title,
                  toggle.isOn ? @"on" : @"off",
                  storedNow ? @"on" : @"off",
                  row.key];
}

// A hidden tab is removed as the bar lays out, but the tab's own controller
// stays loaded until the app starts again. Said once per run rather than on
// every switch.
- (void)noteRestartIfTabRow:(PSGSettingsRow *)row {
    static BOOL told = NO;
    NSArray *tabKeys = @[PRMKeyHideTabChats, PRMKeyHideTabStories,
                         PRMKeyHideTabNotifications, PRMKeyHideTabMenu];
    if (![tabKeys containsObject:row.key] || told) return;
    told = YES;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Restart Messenger"
                         message:@"Tab changes settle once the app is closed and opened again."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)presentCopied:(NSUInteger)length title:(NSString *)title {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:[NSString stringWithFormat:
                                  @"%lu characters on the clipboard.", (unsigned long)length]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyReport {
    [self presentCopied:[PRMDebug copyReportToPasteboard] title:@"Copied"];
}

- (void)runScan {
    [PRMDebug runFullScan];
    [self presentCopied:[PRMDebug copyReportToPasteboard] title:@"Scan complete"];
}

- (void)captureLater {
    [self dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [PRMDebug dumpViewHierarchy];
        });
    }];
}

- (void)openReport {
    [self dismissViewControllerAnimated:YES completion:^{
        [PRMDebug present];
    }];
}

@end
