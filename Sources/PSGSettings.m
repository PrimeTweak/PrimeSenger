#import "PSGSettings.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGHelp.h"
#import "PSGCompatibility.h"

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

#pragma mark - Row

typedef NS_ENUM(NSInteger, PSGRowKind) {
    PSGRowKindSwitch,
    PSGRowKindLink,
};

@interface PSGSettingsRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) BOOL inverted;
@property (nonatomic, assign) PSGRowKind kind;
@property (nonatomic, copy) NSString *help;
@property (nonatomic, copy) NSString *auxKey;
@property (nonatomic, copy) NSString *auxOnTitle;
@property (nonatomic, copy) NSString *auxOffTitle;
@property (nonatomic, copy) NSString *thirdKey;
@property (nonatomic, copy) NSString *thirdTitle;
@end

@implementation PSGSettingsRow

// A noun title shows the thing, so its switch is on while the thing is
// visible; for a key that stores "hide this", that is the stored value inverted.
+ (instancetype)row:(NSString *)title symbol:(NSString *)symbol key:(NSString *)key
           inverted:(BOOL)inverted help:(NSString *)help {
    PSGSettingsRow *row = [[PSGSettingsRow alloc] init];
    row.title = title;
    row.symbol = symbol;
    row.key = key;
    row.inverted = inverted;
    row.help = help;
    row.kind = PSGRowKindSwitch;
    return row;
}

+ (instancetype)link:(NSString *)title symbol:(NSString *)symbol {
    PSGSettingsRow *row = [[PSGSettingsRow alloc] init];
    row.title = title;
    row.symbol = symbol;
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
@property (nonatomic, strong) UIButton *info;
@property (nonatomic, strong) UILabel *value;
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
    _toggle.onTintColor = [UIColor colorWithRed:0.031 green:0.400 blue:1.0 alpha:1.0];

    _pill = [UIButton buttonWithType:UIButtonTypeSystem];
    _pill.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    _pill.backgroundColor = [UIColor tertiarySystemFillColor];
    _pill.layer.cornerRadius = 12.0;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 11.0);
    _pill.hidden = YES;
    [self.contentView addSubview:_pill];

    _info = [UIButton buttonWithType:UIButtonTypeSystem];
    _info.tintColor = [UIColor secondaryLabelColor];
    _info.accessibilityLabel = @"About this option";
    UIImageSymbolConfiguration *infoSize =
        [UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *infoGlyph = [UIImage systemImageNamed:@"info.circle" withConfiguration:infoSize];
    if (infoGlyph != nil) {
        [_info setImage:infoGlyph forState:UIControlStateNormal];
    } else {
        [_info setTitle:@"i" forState:UIControlStateNormal];
    }
    _info.hidden = YES;
    [self.contentView addSubview:_info];

    _value = [[UILabel alloc] initWithFrame:CGRectZero];
    _value.font = [UIFont systemFontOfSize:15.0];
    _value.textAlignment = NSTextAlignmentRight;
    _value.hidden = YES;
    [self.contentView addSubview:_value];
    return self;
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

    CGFloat available = width - kTextLeading - right;
    if (!self.info.hidden) {
        // The info button follows the title's last letter.
        CGFloat textWidth = ceil([self.label sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)].width);
        CGFloat labelWidth = MIN(textWidth, available - kInfoSize - 4.0);
        self.label.frame = CGRectMake(kTextLeading, 0.0, labelWidth, height);
        self.info.frame = CGRectMake(kTextLeading + labelWidth + 2.0, (height - kInfoSize) / 2.0,
                                     kInfoSize, kInfoSize);
        return;
    }
    self.label.frame = CGRectMake(kTextLeading, 0.0, available, height);
}

@end

#pragma mark - Header

@interface PSGSettingsHeader : UIView
@property (nonatomic, strong) UILabel *label;
@end

@implementation PSGSettingsHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;
    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.font = [UIFont systemFontOfSize:kHeaderSize weight:UIFontWeightSemibold];
    _label.textColor = [UIColor colorWithRed:0.396 green:0.404 blue:0.420 alpha:1.0];
    [self addSubview:_label];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = ceil(self.label.font.lineHeight);
    CGFloat top = self.bounds.size.height - height - kHeaderBaseline;
    self.label.frame = CGRectMake(kHeaderLeading, top,
                                  self.bounds.size.width - kHeaderLeading * 2.0, height);
}

@end

#pragma mark - Controller

@interface PSGSettingsViewController ()
@property (nonatomic, strong) NSArray<NSArray<PSGSettingsRow *> *> *sections;
@property (nonatomic, strong) NSArray<NSString *> *titles;
@end

@implementation PSGSettingsViewController

+ (UIViewController *)presentable {
    PSGSettingsViewController *settings =
        [[PSGSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    return [[UINavigationController alloc] initWithRootViewController:settings];
}

// A missing symbol falls back to a plain circle rather than showing nothing.
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

    // A custom view rather than the system Done item, whose iOS 26 style
    // ignores tintColor and draws white on a light sheet.
    UIImageSymbolConfiguration *check =
        [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    closeButton.tintColor = [UIColor labelColor];
    closeButton.accessibilityLabel = @"Done";
    [closeButton addTarget:self action:@selector(close)
          forControlEvents:UIControlEventTouchUpInside];
    UIImage *glyph = [UIImage systemImageNamed:@"checkmark" withConfiguration:check];
    if (glyph != nil) {
        [closeButton setImage:glyph forState:UIControlStateNormal];
    } else {
        [closeButton setTitle:@"Done" forState:UIControlStateNormal];
        [closeButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:closeButton];

    self.tableView.rowHeight = kRowHeight;
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, kTextLeading, 0.0, 0.0);
    [self.tableView registerClass:[PSGSettingsCell class] forCellReuseIdentifier:@"row"];
    [self buildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)buildSections {
    NSMutableArray<NSString *> *titles = [@[@"Privacy", @"Chats", @"Chat list", @"Stories",
                                            @"Media", @"Meta AI", @"Tab bar"] mutableCopy];
    NSMutableArray *sections = [@[
        @[[[[PSGSettingsRow row:@"Read receipts" symbol:@"eye.fill" key:PRMKeyReadAnonymously
                       inverted:YES
                           help:@"Turn off so nobody sees you read. The pill sets when a receipt "
                                 "still goes out: never, when you tap the eye, or when you reply."]
             pill:PRMKeyReadReceiptsManual on:@"Manual" off:@"Never"]
             third:PRMKeyReadOnReply title:@"On reply"],
          [PSGSettingsRow row:@"Typing indicator" symbol:@"ellipsis.bubble.fill"
                          key:PRMKeyHideTypingIndicator inverted:YES
                         help:@"Turn off to stop sending the three dots while you type. "
                               "You still see theirs."],
          [PSGSettingsRow row:@"Story views" symbol:@"eye.circle.fill"
                          key:PRMKeyStoriesAnonymously inverted:YES
                         help:@"Turn off to watch stories without appearing in the viewer list."],
          [PSGSettingsRow row:@"Screenshot alerts" symbol:@"camera.fill"
                          key:PRMKeyBlockScreenshotNotice inverted:YES
                         help:@"Turn off so nobody is told when you screenshot a disappearing "
                               "photo or an encrypted chat."]],

        @[[PSGSettingsRow row:@"Quick reaction" symbol:@"face.smiling.fill"
                          key:PRMKeyHideQuickReaction inverted:YES
                         help:@"Turn off to replace the emoji next to the message field with "
                               "a send button."],
          [PSGSettingsRow row:@"Keep keyboard closed" symbol:@"keyboard.chevron.compact.down"
                          key:PRMKeyNoAutoKeyboard inverted:NO help:nil],
          [PSGSettingsRow row:@"Confirm before calling" symbol:@"phone.fill"
                          key:PRMKeyCallConfirmation inverted:NO help:nil],
          [PSGSettingsRow row:@"Upload in HD" symbol:@"arrow.up.circle.fill"
                          key:PRMKeyUploadHD inverted:NO
                         help:@"Photos you pick in Messenger go out in full quality. The iOS "
                               "photo picker is not affected."],
          [PSGSettingsRow row:@"View once toggle" symbol:@"1.circle"
                          key:PRMKeyBlockViewOnceSend inverted:YES
                         help:@"Turn off so the View once option can't be switched on by mistake."],
          [PSGSettingsRow row:@"Mute bell" symbol:@"bell.slash.fill"
                          key:PRMKeySilencedChats inverted:NO
                         help:@"Adds a bell to each chat. Tap it to mute that chat on this phone "
                               "only; nobody is told."]],

        @[[PSGSettingsRow row:@"Stories tray" symbol:@"person.3.fill"
                          key:PRMKeyHideStoriesTray inverted:YES help:nil],
          [PSGSettingsRow row:@"People you may know" symbol:@"person.2.fill"
                          key:PRMKeyHidePeopleYouMayKnow inverted:YES help:nil],
          [PSGSettingsRow row:@"Friend suggestions" symbol:@"person.badge.plus"
                          key:PRMKeyHidePymkInNotifications inverted:YES
                         help:@"The suggested people shown in the notifications tab."]],

        @[[PSGSettingsRow row:@"Reply bar" symbol:@"arrowshape.turn.up.left.fill"
                          key:PRMKeyHideStoryReplyBar inverted:YES help:nil],
          [PSGSettingsRow row:@"Start stories with sound" symbol:@"speaker.wave.2.fill"
                          key:PRMKeyStorySound inverted:NO help:nil]],

        @[[PSGSettingsRow row:@"Unlock media actions" symbol:@"lock.open.fill"
                          key:PRMKeyUnlockMedia inverted:NO
                         help:@"Turns back on the options Messenger greys out on photos and "
                               "videos: save, share, forward, copy."],
          [PSGSettingsRow row:@"Save button" symbol:@"square.and.arrow.down.fill"
                          key:PRMKeySaveButton inverted:NO
                         help:@"Adds a save button to story photos, disappearing photos and "
                               "profile pictures."],
          [PSGSettingsRow row:@"Content warnings" symbol:@"exclamationmark.triangle.fill"
                          key:PRMKeyRevealCensored inverted:YES
                         help:@"Turn off to show photos hidden behind a warning without the "
                               "extra tap."],
          [PSGSettingsRow row:@"Replay view once" symbol:@"arrow.counterclockwise.circle.fill"
                          key:PRMKeyViewOnce inverted:NO
                         help:@"View once photos can be opened again instead of vanishing after "
                               "one look."],
          [PSGSettingsRow row:@"Loop videos" symbol:@"repeat"
                          key:PRMKeyLoopVideos inverted:NO help:nil],
          [PSGSettingsRow row:@"Start videos with sound" symbol:@"speaker.wave.3.fill"
                          key:PRMKeySoundOnOpen inverted:NO help:nil],
          [[PSGSettingsRow row:@"Speed up videos" symbol:@"speedometer"
                           key:PRMKeySpeed inverted:NO help:nil]
             pill:PRMKeySpeed2 on:@"2x" off:@"1.5x"]],

        @[[PSGSettingsRow row:@"Meta AI in search" symbol:@"magnifyingglass"
                          key:PRMKeyHideMetaAI inverted:YES help:nil],
          [PSGSettingsRow row:@"Meta AI button" symbol:@"sparkles"
                          key:PRMKeyHideMetaAIButton inverted:YES help:nil],
          [PSGSettingsRow row:@"Meta AI in media menu" symbol:@"photo.fill"
                          key:PRMKeyHideMetaAIMedia inverted:YES help:nil]],

        @[[PSGSettingsRow row:@"Liquid Glass" symbol:@"drop.fill"
                          key:PRMKeyGlassTabBar inverted:NO
                         help:@"Uses the iOS glass tab bar instead of Messenger's own."],
          [PSGSettingsRow row:@"Chats" symbol:@"bubble.left.fill"
                          key:PRMKeyHideTabChats inverted:YES help:nil],
          [PSGSettingsRow row:@"Stories" symbol:@"play.rectangle.fill"
                          key:PRMKeyHideTabStories inverted:YES help:nil],
          [PSGSettingsRow row:@"Notifications" symbol:@"bell.badge.fill"
                          key:PRMKeyHideTabNotifications inverted:YES help:nil],
          [PSGSettingsRow row:@"Menu" symbol:@"line.3.horizontal"
                          key:PRMKeyHideTabMenu inverted:YES help:nil]],
    ] mutableCopy];

    // The last card carries no title: Compatibility in debug builds, FLEX, Pause.
    NSMutableArray<PSGSettingsRow *> *last = [NSMutableArray array];
#if PRIMESENGER_DEBUG
    [last addObject:[PSGSettingsRow link:@"Compatibility" symbol:@"checkmark.seal.fill"]];
#endif
    [last addObject:[PSGSettingsRow row:@"FLEX explorer" symbol:@"scope"
                                    key:PRMKeyFlexEnabled inverted:NO
                                   help:@"A developer tool that inspects what is on screen."]];
    [last addObject:[PSGSettingsRow row:@"Pause PrimeSenger" symbol:@"pause.circle.fill"
                                    key:PRMKeyMasterDisable inverted:NO
                                   help:@"Turns everything off at once without changing your "
                                         "switches."]];
    [titles addObject:@""];
    [sections addObject:last];

    self.titles = titles;
    self.sections = sections;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = self.titles[(NSUInteger)section];
    if (title.length == 0) return nil;
    PSGSettingsHeader *header = [[PSGSettingsHeader alloc] initWithFrame:CGRectZero];
    header.label.text = title;
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.titles[(NSUInteger)section].length == 0) return kHeaderFirst;
    return section == 0 ? kHeaderFirst + kHeaderBaseline : kHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGSettingsRow *row = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"
                                                            forIndexPath:indexPath];
    NSInteger tag = indexPath.section * 100 + indexPath.row;
    cell.label.text = row.title;
    cell.glyph.image = [self glyphNamed:row.symbol];
    cell.pill.hidden = YES;
    cell.value.hidden = YES;

    cell.info.hidden = row.help.length == 0;
    cell.info.tag = tag;
    [cell.info removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.info addTarget:self action:@selector(infoTapped:)
        forControlEvents:UIControlEventTouchUpInside];

    if (row.kind == PSGRowKindLink) {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
#if PRIMESENGER_DEBUG
        cell.value.text = PSGCompatStatusText();
        cell.value.textColor = PSGCompatStatusColor();
        cell.value.hidden = NO;
#endif
        [cell setNeedsLayout];
        return cell;
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = cell.toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.toggle.on = [row displayedState];
    cell.toggle.tag = tag;
    [cell.toggle removeTarget:self action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.toggle addTarget:self action:@selector(toggleChanged:)
          forControlEvents:UIControlEventValueChanged];

    // The pill belongs to the feature, so it shows while the feature is active.
    if (row.auxKey != nil && [PRMPrefs isEnabled:row.key]) {
        BOOL auxOn = [PRMPrefs isEnabled:row.auxKey];
        BOOL thirdOn = row.thirdKey != nil && [PRMPrefs isEnabled:row.thirdKey];
        NSString *label = thirdOn ? row.thirdTitle : (auxOn ? row.auxOnTitle : row.auxOffTitle);
        [cell.pill setTitle:label forState:UIControlStateNormal];
        [cell.pill setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        cell.pill.hidden = NO;
        cell.pill.tag = tag;
        [cell.pill removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.pill addTarget:self action:@selector(pillTapped:)
            forControlEvents:UIControlEventTouchUpInside];
    }
    [cell setNeedsLayout];
    return cell;
}

// Each cell carries its own card, rounded only on the edges of its group,
// so the grouped background can never fall out of step with the content.
- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger count = [tableView numberOfRowsInSection:indexPath.section];
    CACornerMask corners = 0;
    if (indexPath.row == 0) corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (indexPath.row == count - 1) corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;

    UIView *card = [[UIView alloc] initWithFrame:cell.bounds];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.layer.cornerRadius = 14.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.maskedCorners = corners;
    cell.backgroundView = card;
    cell.backgroundColor = [UIColor clearColor];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
#if PRIMESENGER_DEBUG
    PSGSettingsRow *row = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    if (row.kind != PSGRowKindLink) return;
    PSGCompatibilityViewController *compatibility =
        [[PSGCompatibilityViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:compatibility animated:YES];
#endif
}

- (PSGSettingsRow *)rowForTag:(NSInteger)tag {
    NSInteger section = tag / 100;
    NSInteger index = tag % 100;
    if (section < 0 || section >= (NSInteger)self.sections.count) return nil;
    NSArray<PSGSettingsRow *> *rows = self.sections[(NSUInteger)section];
    if (index < 0 || index >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)index];
}

- (void)infoTapped:(UIButton *)button {
    PSGSettingsRow *row = [self rowForTag:button.tag];
    if (row.help.length == 0) return;
    [PSGHelpSheet presentFrom:self title:row.title items:@[@[row.title, row.help]]];
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
    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch *)toggle {
    PSGSettingsRow *row = [self rowForTag:toggle.tag];
    if (row == nil) return;
    [row applyDisplayedState:toggle.isOn];
    [self noteRestartIfTabRow:row];
    [PRMDebug refreshFloatingButton];
    [PRMDebug returnButtonToSlot];
    if (row.auxKey != nil) [self.tableView reloadData];
    if ([row.key isEqualToString:PRMKeyFlexEnabled]) {
        [PRMDebug applyFlexState];
        if (toggle.isOn) [self close];
    }
}

// Tab changes settle only after a relaunch, which is said once per launch.
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
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
