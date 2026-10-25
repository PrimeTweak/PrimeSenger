#import "PSGSettings.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGHelp.h"
#import "PSGBackup.h"
#import "PSGHiddenTabs.h"
#import "PSGCompatibility.h"

#ifndef PRIMESENGER_VERSION
#define PRIMESENGER_VERSION "?"
#endif

NSString *const PSGSettingsCellIdentifier = @"row";

// Metrics read off Messenger's own settings screen.
static const CGFloat kRowHeight      = 52.0;
static const CGFloat kIconSize       = 24.0;
static const CGFloat kIconLeading    = 18.0;
static const CGFloat kTextLeading    = 62.0;

static const CGFloat kHeaderLeading  = 20.0;
static const CGFloat kHeaderSize     = 15.0;
static const CGFloat kHeaderHeight   = 42.0;
static const CGFloat kHeaderFirst    = 30.0;
static const CGFloat kHeaderBaseline = 8.0;

static const CGFloat kPillHeight     = 24.0;
static const CGFloat kPillMinWidth   = 54.0;
static const CGFloat kPillTrailing   = 10.0;
static const CGFloat kPillLabelGap   = 10.0;

static const CGFloat kInfoSize       = 22.0;
static const CGFloat kInfoGlyphSize  = 20.0;
static const CGFloat kLinkHeight     = 44.0;

#pragma mark - Shared pieces

static UIImage *PSGGlyph(NSString *name) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage *image = name ? [UIImage systemImageNamed:name withConfiguration:configuration] : nil;
    if (image == nil && name != nil) {
        [PRMDebug log:@"symbol %@ not available", name];
        image = [UIImage systemImageNamed:@"circle.fill" withConfiguration:configuration];
    }
    return image;
}

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
    [self.contentView addSubview:_label];

    _toggle = [[UISwitch alloc] init];
    _toggle.onTintColor = [UIColor colorWithRed:0.031 green:0.400 blue:1.0 alpha:1.0];

    _pill = [UIButton buttonWithType:UIButtonTypeSystem];
    _pill.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    _pill.backgroundColor = [UIColor tertiarySystemFillColor];
    _pill.layer.cornerRadius = 12.0;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 11.0);
    [self.contentView addSubview:_pill];

    _value = [[UILabel alloc] initWithFrame:CGRectZero];
    _value.font = [UIFont systemFontOfSize:15.0];
    _value.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_value];
    [self prepareWithTitle:nil symbol:nil];
    return self;
}

- (void)prepareWithTitle:(NSString *)title symbol:(NSString *)symbol {
    self.label.text = title;
    self.label.textColor = [UIColor labelColor];
    self.glyph.image = PSGGlyph(symbol);
    self.glyph.tintColor = [UIColor labelColor];
    self.pill.hidden = YES;
    self.value.hidden = YES;
    self.value.textColor = [UIColor secondaryLabelColor];
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    [self.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    [self.pill removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.contentView.bounds.size.height;
    CGFloat width = self.contentView.bounds.size.width;
    self.glyph.frame = CGRectMake(kIconLeading, (height - kIconSize) / 2.0, kIconSize, kIconSize);

    CGFloat right = 16.0;
    if (!self.pill.hidden) {
        [self.pill sizeToFit];
        CGFloat pillWidth = MAX(self.pill.bounds.size.width, kPillMinWidth);
        self.pill.frame = CGRectMake(width - kPillTrailing - pillWidth,
                                     (height - kPillHeight) / 2.0, pillWidth, kPillHeight);
        right = kPillTrailing + pillWidth + kPillLabelGap;
    }
    if (!self.value.hidden) {
        CGFloat valueWidth = ceil([self.value sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)].width);
        self.value.frame = CGRectMake(width - 8.0 - valueWidth, 0.0, valueWidth, height);
        right = 8.0 + valueWidth + kPillLabelGap;
    }
    // A row without an icon starts its text where the icon would have been.
    CGFloat left = self.glyph.image != nil ? kTextLeading : kIconLeading;
    self.label.frame = CGRectMake(left, 0.0, width - left - right, height);
}

@end

@implementation PSGSettingsHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;
    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.font = [UIFont systemFontOfSize:kHeaderSize weight:UIFontWeightSemibold];
    _label.textColor = [UIColor colorWithRed:0.396 green:0.404 blue:0.420 alpha:1.0];
    [self addSubview:_label];

    _info = [UIButton buttonWithType:UIButtonTypeSystem];
    _info.tintColor = _label.textColor;
    _info.accessibilityLabel = @"About these options";
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kInfoGlyphSize
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:@"info.circle" withConfiguration:configuration];
    [_info setImage:glyph forState:UIControlStateNormal];
    _info.hidden = YES;
    [self addSubview:_info];
    return self;
}

// The info button sits at the trailing edge, centered on the title.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = ceil(self.label.font.lineHeight);
    CGFloat top = self.bounds.size.height - height - kHeaderBaseline;
    self.label.frame = CGRectMake(kHeaderLeading, top,
                                  self.bounds.size.width - kHeaderLeading * 2.0 - kInfoSize, height);
    self.info.frame = CGRectMake(self.bounds.size.width - kHeaderLeading - kInfoSize,
                                 top + (height - kInfoSize) / 2.0, kInfoSize, kInfoSize);
}

@end

void PSGStyleTable(UITableView *table) {
    table.rowHeight = kRowHeight;
    table.separatorInset = UIEdgeInsetsMake(0.0, kTextLeading, 0.0, 0.0);
    [table registerClass:[PSGSettingsCell class] forCellReuseIdentifier:PSGSettingsCellIdentifier];
}

void PSGApplyCard(UITableView *table, UITableViewCell *cell, NSIndexPath *path) {
    NSInteger count = [table numberOfRowsInSection:path.section];
    CACornerMask corners = 0;
    if (path.row == 0) corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (path.row == count - 1) corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    UIView *card = [[UIView alloc] initWithFrame:cell.bounds];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.layer.cornerRadius = 14.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.maskedCorners = corners;
    cell.backgroundView = card;
    cell.backgroundColor = [UIColor clearColor];
}

PSGSettingsHeader *PSGHeader(NSString *title, id target, SEL infoAction, NSInteger tag) {
    PSGSettingsHeader *header = [[PSGSettingsHeader alloc] initWithFrame:CGRectZero];
    header.label.text = title;
    header.info.hidden = infoAction == NULL;
    if (infoAction != NULL) {
        header.info.tag = tag;
        [header.info addTarget:target action:infoAction forControlEvents:UIControlEventTouchUpInside];
    }
    return header;
}

CGFloat PSGHeaderHeight(NSInteger section, NSString *title) {
    if (title.length == 0) return kHeaderFirst;
    return section == 0 ? kHeaderFirst + kHeaderBaseline : kHeaderHeight;
}

// A custom view rather than the system Done item, whose iOS 26 style ignores
// tintColor and draws a washed-out checkmark on a light sheet.
UIBarButtonItem *PSGCloseItem(id target, SEL action) {
    UIImageSymbolConfiguration *check =
        [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    button.tintColor = [UIColor labelColor];
    button.accessibilityLabel = @"Done";
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    UIImage *glyph = [UIImage systemImageNamed:@"checkmark" withConfiguration:check];
    [button setImage:glyph forState:UIControlStateNormal];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

// The "How it works" link under the last section, in the footer's gray: as high as
// a section title, its icon and text in the row icon and title columns.
@interface PSGHowItWorksLink : UIControl
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@end

@implementation PSGHowItWorksLink

- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    UIColor *gray = [UIColor tertiaryLabelColor];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"How it works";
    title.font = [UIFont systemFontOfSize:kHeaderSize];
    title.textColor = gray;
    CGFloat height = ceil(title.font.lineHeight);
    CGFloat top = kHeaderHeight - height - kHeaderBaseline;
    CGSize fit = [title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    title.frame = CGRectMake(kTextLeading, top, ceil(fit.width), height);
    [self addSubview:title];

    UIImageSymbolConfiguration *size =
        [UIImageSymbolConfiguration configurationWithPointSize:kHeaderSize weight:UIImageSymbolWeightRegular];
    UIImageView *icon =
        [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:size]];
    icon.contentMode = UIViewContentModeCenter;
    icon.tintColor = gray;
    icon.frame = CGRectMake(kIconLeading, top + (height - kIconSize) / 2.0, kIconSize, kIconSize);
    [self addSubview:icon];

    self.isAccessibilityElement = YES;
    self.accessibilityLabel = title.text;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1.0;
}

@end

#pragma mark - Rows

typedef NS_ENUM(NSInteger, PSGRowKind) {
    PSGRowKindSwitch,
    PSGRowKindLink,
};

@interface PSGSettingsRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) PSGRowKind kind;
@property (nonatomic, assign) SEL action;
@property (nonatomic, copy) NSString *auxKey;
@property (nonatomic, copy) NSString *auxOnTitle;
@property (nonatomic, copy) NSString *auxOffTitle;
@property (nonatomic, copy) NSString *thirdKey;
@property (nonatomic, copy) NSString *thirdTitle;
@end

@implementation PSGSettingsRow

// A switch names a change to Messenger and is on while the change applies,
// which is the stored value as it is.
+ (instancetype)row:(NSString *)title symbol:(NSString *)symbol key:(NSString *)key {
    PSGSettingsRow *row = [[PSGSettingsRow alloc] init];
    row.title = title;
    row.symbol = symbol;
    row.key = key;
    row.kind = PSGRowKindSwitch;
    return row;
}

+ (instancetype)link:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    PSGSettingsRow *row = [[PSGSettingsRow alloc] init];
    row.title = title;
    row.symbol = symbol;
    row.action = action;
    row.kind = PSGRowKindLink;
    return row;
}

- (instancetype)pill:(NSString *)auxKey on:(NSString *)onTitle off:(NSString *)offTitle {
    self.auxKey = auxKey;
    self.auxOnTitle = onTitle;
    self.auxOffTitle = offTitle;
    return self;
}

- (instancetype)third:(NSString *)thirdKey title:(NSString *)thirdTitle {
    self.thirdKey = thirdKey;
    self.thirdTitle = thirdTitle;
    return self;
}

- (BOOL)displayedState {
    return [PRMPrefs isEnabled:self.key];
}

- (void)applyDisplayedState:(BOOL)on {
    [PRMPrefs setEnabled:on forKey:self.key];
}

@end

#pragma mark - Controller

@interface PSGSettingsViewController ()
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSArray<NSArray<PSGSettingsRow *> *> *sections;
@property (nonatomic, strong) NSArray<NSArray<NSArray<NSString *> *> *> *help;
@end

@implementation PSGSettingsViewController

+ (UIViewController *)presentable {
    PSGSettingsViewController *settings =
        [[PSGSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    return [[UINavigationController alloc] initWithRootViewController:settings];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PrimeSenger";
    self.navigationItem.rightBarButtonItem = PSGCloseItem(self, @selector(close));
    PSGStyleTable(self.tableView);
    [self buildSections];
    [self installFooter];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)installFooter {
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 72.0)];
    footer.text = @"PrimeSenger " PRIMESENGER_VERSION;
    footer.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    footer.textColor = [UIColor tertiaryLabelColor];
    footer.textAlignment = NSTextAlignmentCenter;
    self.tableView.tableFooterView = footer;
}

// Help lists only the options whose title leaves something out; a section
// whose titles say it all has no info button.
- (void)buildSections {
    NSMutableArray *titles = [@[@"Privacy", @"Chats", @"Chat list", @"Stories",
                                @"Media", @"Meta AI", @"Tab bar", @"Tools"] mutableCopy];

    NSMutableArray<PSGSettingsRow *> *tools = [NSMutableArray arrayWithObject:
        [PSGSettingsRow link:@"Backup & reset" symbol:@"lock.icloud.fill" action:@selector(openBackup)]];
#if PRIMESENGER_DEBUG
    [tools addObject:[PSGSettingsRow link:@"Compatibility" symbol:@"checkmark.seal.fill"
                                   action:@selector(openCompatibility)]];
#endif
    [tools addObject:[PSGSettingsRow row:@"Floating button" symbol:@"sparkles"
                                     key:PRMKeyFloatingButton]];
    [tools addObject:[PSGSettingsRow row:@"FLEX explorer" symbol:@"scope"
                                     key:PRMKeyFlexEnabled]];

    self.sections = @[
        @[[[[PSGSettingsRow row:@"Read anonymously" symbol:@"eye.fill" key:PRMKeyReadAnonymously]
             pill:PRMKeyReadReceiptsManual on:@"Manual" off:@"Always"]
             third:PRMKeyReadOnReply title:@"Until reply"],
          [PSGSettingsRow row:@"Hide typing indicator" symbol:@"ellipsis.bubble.fill"
                          key:PRMKeyHideTypingIndicator],
          [PSGSettingsRow row:@"Watch stories anonymously" symbol:@"eye.circle.fill"
                          key:PRMKeyStoriesAnonymously],
          [PSGSettingsRow row:@"Block screenshot alerts" symbol:@"camera.fill"
                          key:PRMKeyBlockScreenshotNotice]],
        @[[PSGSettingsRow row:@"Hide quick reaction" symbol:@"face.smiling.fill"
                          key:PRMKeyHideQuickReaction],
          [PSGSettingsRow row:@"Keep keyboard closed" symbol:@"keyboard.chevron.compact.down"
                          key:PRMKeyNoAutoKeyboard],
          [PSGSettingsRow row:@"Confirm before calling" symbol:@"phone.fill"
                          key:PRMKeyCallConfirmation],
          [PSGSettingsRow row:@"Upload in HD" symbol:@"arrow.up.circle.fill"
                          key:PRMKeyUploadHD],
          [PSGSettingsRow row:@"Block View once" symbol:@"1.circle"
                          key:PRMKeyBlockViewOnceSend],
          [PSGSettingsRow row:@"Mute bell" symbol:@"bell.slash.fill"
                          key:PRMKeySilencedChats]],
        @[[PSGSettingsRow row:@"Hide stories tray" symbol:@"person.3.fill"
                          key:PRMKeyHideStoriesTray],
          [PSGSettingsRow row:@"Hide People you may know" symbol:@"person.2.fill"
                          key:PRMKeyHidePeopleYouMayKnow],
          [PSGSettingsRow row:@"Hide friend suggestions" symbol:@"person.badge.plus"
                          key:PRMKeyHidePymkInNotifications]],
        @[[PSGSettingsRow row:@"Hide reply bar" symbol:@"arrowshape.turn.up.left.fill"
                          key:PRMKeyHideStoryReplyBar],
          [PSGSettingsRow row:@"Start stories with sound" symbol:@"speaker.wave.2.fill"
                          key:PRMKeyStorySound]],
        @[[PSGSettingsRow row:@"Unlock media actions" symbol:@"lock.open.fill"
                          key:PRMKeyUnlockMedia],
          [PSGSettingsRow row:@"Save button" symbol:@"square.and.arrow.down.fill"
                          key:PRMKeySaveButton],
          [PSGSettingsRow row:@"Reveal covered photos" symbol:@"exclamationmark.triangle.fill"
                          key:PRMKeyRevealCensored],
          [PSGSettingsRow row:@"Replay view once" symbol:@"arrow.counterclockwise.circle.fill"
                          key:PRMKeyViewOnce],
          [PSGSettingsRow row:@"Loop videos" symbol:@"repeat"
                          key:PRMKeyLoopVideos],
          [PSGSettingsRow row:@"Start videos with sound" symbol:@"speaker.wave.3.fill"
                          key:PRMKeySoundOnOpen],
          [[PSGSettingsRow row:@"Speed up videos" symbol:@"speedometer" key:PRMKeySpeed]
             pill:PRMKeySpeed2 on:@"2x" off:@"1.5x"]],
        @[[PSGSettingsRow row:@"Hide Meta AI in search" symbol:@"magnifyingglass"
                          key:PRMKeyHideMetaAI],
          [PSGSettingsRow row:@"Hide Meta AI button" symbol:@"circle"
                          key:PRMKeyHideMetaAIButton],
          [PSGSettingsRow row:@"Hide Meta AI in media menu" symbol:@"photo.fill"
                          key:PRMKeyHideMetaAIMedia]],
        @[[PSGSettingsRow row:@"Liquid Glass" symbol:@"drop.fill"
                          key:PRMKeyGlassTabBar],
          [PSGSettingsRow link:@"Hidden tabs" symbol:@"eye.slash.fill"
                       action:@selector(openHiddenTabs)]],
        tools,
    ];

    self.help = @[
        @[@[@"Read anonymously",
            @"Keeps your read receipts from being sent. Manual: tap the eye in a chat to send one. "
             "Until reply: one is sent when you answer.",
            @"eye.fill"],
          @[@"Watch stories anonymously", @"Stories you watch don't count you as a viewer.",
            @"eye.circle.fill"],
          @[@"Block screenshot alerts",
            @"Others aren't told when you screenshot a disappearing photo.",
            @"camera.fill"]],
        @[@[@"Hide quick reaction",
            @"Replaces the one-tap emoji next to the message field with a send button.",
            @"face.smiling.fill"],
          @[@"Upload in HD",
            @"Sends photos in full quality from Messenger's own picker.",
            @"arrow.up.circle.fill"],
          @[@"Block View once",
            @"Removes the option to send a photo that opens only once.",
            @"1.circle"],
          @[@"Mute bell",
            @"A bell in each chat that mutes it for this phone only.",
            @"bell.slash.fill"]],
        @[@[@"Hide friend suggestions", @"Removes the suggested people from the Notifications tab.",
            @"person.badge.plus"]],
        @[],
        @[@[@"Unlock media actions",
            @"Lets you save, share and copy media that Messenger locks.",
            @"lock.open.fill"],
          @[@"Save button",
            @"A save button for stories, disappearing photos and profile pictures.",
            @"square.and.arrow.down.fill"],
          @[@"Reveal covered photos", @"Skips the warning Messenger shows over sensitive photos.",
            @"exclamationmark.triangle.fill"],
          @[@"Replay view once",
            @"Lets you open View once photos again.",
            @"arrow.counterclockwise.circle.fill"]],
        @[],
        @[@[@"Liquid Glass", @"Uses the iOS glass tab bar instead of Messenger's own.",
            @"drop.fill"]],
        @[@[@"Floating button",
            @"A button over Messenger that opens these settings. "
             "It shows by itself when the Menu tab is hidden.",
            @"sparkles"],
          @[@"FLEX explorer",
            @"A developer tool that inspects the screen.",
            @"scope"]],
    ];
    self.titles = titles;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openBackup {
    [self.navigationController pushViewController:
        [[PSGBackupViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}

- (void)openHiddenTabs {
    [self.navigationController pushViewController:
        [[PSGHiddenTabsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}

#if PRIMESENGER_DEBUG
- (void)openCompatibility {
    [self.navigationController pushViewController:
        [[PSGCompatibilityViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
#endif

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    BOOL explained = self.help[(NSUInteger)section].count > 0;
    return PSGHeader(self.titles[(NSUInteger)section], self,
                     explained ? @selector(infoTapped:) : NULL, section);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PSGHeaderHeight(section, self.titles[(NSUInteger)section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == (NSInteger)self.sections.count - 1 ? kLinkHeight : CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != (NSInteger)self.sections.count - 1) return nil;
    return [[PSGHowItWorksLink alloc] initWithTarget:self action:@selector(showHowItWorks)];
}

- (void)infoTapped:(UIButton *)button {
    NSInteger section = button.tag;
    if (section < 0 || section >= (NSInteger)self.help.count) return;
    [PSGHelpSheet presentFrom:self title:self.titles[(NSUInteger)section]
                        items:self.help[(NSUInteger)section]];
}

// How the switches and pills read, for anyone who wonders.
- (void)showHowItWorks {
    [PSGHelpSheet presentFrom:self title:@"How it works" items:@[
        @[@"Switches",
          @"Each switch names a change to Messenger. On applies it, off leaves Messenger untouched.",
          @"switch.2"],
        @[@"Info buttons", @"The info button next to a section title explains each switch in that section.",
          @"info.circle"],
        @[@"Pills",
          @"Some switches have a small button next to them. Tap it to pick an option, "
          @"like 1.5x or 2x for Speed up videos.",
          @"slider.horizontal.3"],
    ]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGSettingsRow *row = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:PSGSettingsCellIdentifier
                                                            forIndexPath:indexPath];
    [cell prepareWithTitle:row.title symbol:row.symbol];
    NSInteger tag = indexPath.section * 100 + indexPath.row;

    if (row.kind == PSGRowKindLink) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (row.action == @selector(openHiddenTabs)) {
            cell.value.text = PSGHiddenTabsSummary();
            cell.value.hidden = NO;
        }
        return cell;
    }

    cell.accessoryView = cell.toggle;
    cell.toggle.on = [row displayedState];
    cell.toggle.tag = tag;
    [cell.toggle addTarget:self action:@selector(toggleChanged:)
          forControlEvents:UIControlEventValueChanged];

    // The pill belongs to the feature, so it shows while the feature is active.
    if (row.auxKey != nil && [PRMPrefs isEnabled:row.key]) {
        BOOL auxOn = [PRMPrefs isEnabled:row.auxKey];
        BOOL thirdOn = row.thirdKey != nil && [PRMPrefs isEnabled:row.thirdKey];
        [cell.pill setTitle:(thirdOn ? row.thirdTitle : (auxOn ? row.auxOnTitle : row.auxOffTitle))
                   forState:UIControlStateNormal];
        [cell.pill setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        cell.pill.hidden = NO;
        cell.pill.tag = tag;
        [cell.pill addTarget:self action:@selector(pillTapped:)
            forControlEvents:UIControlEventTouchUpInside];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGApplyCard(tableView, cell, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSGSettingsRow *row = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    if (row.kind != PSGRowKindLink || row.action == NULL) return;
    ((void (*)(id, SEL))[self methodForSelector:row.action])(self, row.action);
}

- (PSGSettingsRow *)rowForTag:(NSInteger)tag {
    NSInteger section = tag / 100;
    NSInteger index = tag % 100;
    if (section < 0 || section >= (NSInteger)self.sections.count) return nil;
    NSArray<PSGSettingsRow *> *rows = self.sections[(NSUInteger)section];
    if (index < 0 || index >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)index];
}

// Cycles the pill: off, aux, then third when there is one. The keys are
// written as a pair so a reader of either never sees both raised.
- (void)pillTapped:(UIButton *)pill {
    PSGSettingsRow *row = [self rowForTag:pill.tag];
    if (row == nil || row.auxKey == nil) return;
    if (row.thirdKey != nil) {
        BOOL auxOn = [PRMPrefs isEnabled:row.auxKey];
        BOOL thirdOn = [PRMPrefs isEnabled:row.thirdKey];
        [PRMPrefs setEnabled:(!auxOn && !thirdOn) forKey:row.auxKey];
        [PRMPrefs setEnabled:auxOn forKey:row.thirdKey];
    } else {
        [PRMPrefs setEnabled:![PRMPrefs isEnabled:row.auxKey] forKey:row.auxKey];
    }
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch *)toggle {
    PSGSettingsRow *row = [self rowForTag:toggle.tag];
    if (row == nil) return;
    [row applyDisplayedState:toggle.isOn];
    [PRMDebug refreshFloatingButton];
    [PRMDebug returnButtonToSlot];
    if (row.auxKey != nil) [self.tableView reloadData];
    if ([row.key isEqualToString:PRMKeyFlexEnabled]) {
        [PRMDebug applyFlexState];
        if (toggle.isOn) [self close];
    }
}

@end
