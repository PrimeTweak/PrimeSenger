#import "PSGCompatibility.h"

#if PRIMESENGER_DEBUG

#ifndef PRIMESENGER_VERSION
#define PRIMESENGER_VERSION "?"
#endif

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGHelp.h"
#import "PSGSettings.h"
#import "PSGBackup.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, PSGCompatVerdict) {
    PSGCompatVerdictOff,
    PSGCompatVerdictNotSeen,
    PSGCompatVerdictWorking,
    PSGCompatVerdictBroken,
};

@interface PSGCompatResult : NSObject
@property (nonatomic, copy) NSString *section;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic) PSGCompatVerdict verdict;
@end

@implementation PSGCompatResult
@end

#pragma mark - Options

// A requirement is {class, member, kind}: m instance method, c class method,
// e either, i ivar, k class only. Counters are the actions an option records.
static NSDictionary *PSGOption(NSString *section, NSString *title, NSString *key,
                               NSArray<NSString *> *counters, NSString *done,
                               NSString *hint, NSArray<NSArray<NSString *> *> *needs) {
    return @{@"section": section, @"title": title, @"key": key, @"counters": counters,
             @"done": done, @"hint": hint, @"needs": needs};
}

static NSArray<NSDictionary *> *PSGOptions(void) {
    static NSArray *options = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *tabBar = @"_TtC15MDSModernTabBar15MDSModernTabBar";
        NSArray *tabNeeds = @[@[tabBar, @"didTapButton:", @"m"]];
        options = @[
            PSGOption(@"Privacy", @"Read receipts", PRMKeyReadAnonymously,
                @[@"read receipt", @"send mark read", @"mpe read receipts",
                  @"read on reply", @"read on reaction"],
                @"Held back %lu read receipts", @"Open a chat with unread messages",
                @[@[@"MSGMessageListViewController", @"_notifyObserversDidSetAsRead:", @"m"],
                  @[@"MSGSendMessageTextOptionalInputBuilder", @"withMarkRead:", @"m"],
                  @[@"MPESettings", @"_isReadReceiptsDisabledFromPersistentStorage", @"m"]]),
            PSGOption(@"Privacy", @"Typing indicator", PRMKeyHideTypingIndicator,
                @[@"typing publish class", @"typing publish instance", @"mpe typing"],
                @"Kept the typing dots from being sent %lu times",
                @"Type in a chat without sending",
                @[@[@"MCMTypingIndicatorPublishEventMutationBuilder",
                    @"builderWithIsTyping:threadId:", @"e"],
                  @[@"MPESettings", @"_isTypingIndicatorsDisabledFromPersistentStorage", @"m"]]),
            PSGOption(@"Privacy", @"Story views", PRMKeyStoriesAnonymously,
                @[@"story seen", @"stories badge"],
                @"Watched %lu stories unseen", @"Watch a story to the end",
                @[@[@"MSGStoryBucketsDataManager",
                    @"markStoriesAsSeen:bucketID:isStoryPeekView:completion:", @"m"]]),
            PSGOption(@"Privacy", @"Screenshot alerts", PRMKeyBlockScreenshotNotice,
                @[@"screenshot notice", @"screenshot chat", @"screenshot photo",
                  @"screenshot viewer", @"screen capture state"],
                @"Blocked %lu screenshot alerts", @"Screenshot a disappearing photo",
                @[@[@"MSGEphemeralMediaViewController", @"_didCaptureContent", @"m"],
                  @[@"MSGMessageListViewController", @"_handleUserDidTakeScreenshot:", @"m"]]),

            PSGOption(@"Chats", @"Quick reaction", PRMKeyHideQuickReaction,
                @[@"quick reaction", @"quick reaction layout"],
                @"Swapped the emoji for a send button %lu times",
                @"Open a chat and tap the message field",
                @[@[@"LSComposerActionView", @"setAction:animated:", @"m"]]),
            PSGOption(@"Chats", @"Keep keyboard closed", PRMKeyNoAutoKeyboard,
                @[@"auto keyboard"], @"Kept the keyboard down %lu times", @"Open a chat",
                @[@[@"LSComposerViewController",
                    @"_scheduleAutoOpenKeyboardAfterOpenComposerView", @"m"]]),
            PSGOption(@"Chats", @"Confirm before calling", PRMKeyCallConfirmation,
                @[@"call button"], @"Asked before %lu calls", @"Tap a call button in a chat",
                @[@[@"LSRTCCallButton", @"handleButtonTap", @"m"]]),
            PSGOption(@"Chats", @"Upload in HD", PRMKeyUploadHD,
                @[@"hd uploads"], @"Turned HD on %lu times", @"Open the photo picker in a chat",
                @[@[@"LSMediaPickerViewController", @"_hdToggleButton", @"i"]]),
            PSGOption(@"Chats", @"View once toggle", PRMKeyBlockViewOnceSend,
                @[@"view once send"], @"Blocked View once %lu times",
                @"Tap View once in the photo picker",
                @[@[@"LSMediaPickerViewController", @"_didTapViewOnceToggle", @"m"]]),
            PSGOption(@"Chats", @"Mute bell", PRMKeySilencedChats,
                @[@"silence", @"silence bell"], @"Silenced %lu notifications",
                @"Tap the bell in a chat, then get a message there",
                @[@[@"MSGThreadListViewController",
                    @"notificationPresentationOptionsWithThreadKey:recipientID:"
                     "pushLogMessageType:pushPayloadType:", @"m"]]),

            PSGOption(@"Chat list", @"Stories tray", PRMKeyHideStoriesTray,
                @[[@"suppressed " stringByAppendingString:PRMKeyHideStoriesTray], @"inboxRows"],
                @"Removed the stories tray %lu times", @"Open the chat list",
                @[@[@"MSGThreadListDataSource", @"inboxRows", @"m"]]),
            PSGOption(@"Chat list", @"People you may know", PRMKeyHidePeopleYouMayKnow,
                @[@"pymk hidden", @"pymk count"], @"Removed %lu suggestions",
                @"Scroll to the bottom of the chat list",
                @[@[@"MSGThreadListDataSource", @"shouldShowThreadlistEndPYMK", @"m"]]),
            PSGOption(@"Chat list", @"Friend suggestions", PRMKeyHidePymkInNotifications,
                @[@"notif pymk count", @"notif pymk jewels", @"notif pymk convert"],
                @"Removed %lu suggestions", @"Open the Notifications tab",
                @[@[@"MSGJewelNotificationDataManager", @"peopleYouMayKnowSuggestionJewels", @"m"]]),

            PSGOption(@"Stories", @"Reply bar", PRMKeyHideStoryReplyBar,
                @[@"story reply bar", @"configure reply bar"],
                @"Removed the reply bar %lu times", @"Open a story",
                @[@[@"LSStoryBucketViewController", @"_addReplyBarViewController", @"m"]]),
            PSGOption(@"Stories", @"Start stories with sound", PRMKeyStorySound,
                @[@"story sound"], @"Unmuted %lu stories", @"Open a video story",
                @[@[@"LSStoryBucketViewController", @"shouldDefaultVideoToMute", @"m"]]),

            PSGOption(@"Media", @"Unlock media actions", PRMKeyUnlockMedia,
                @[@"canSaveMedia", @"canShareMedia", @"canForwardMedia", @"canCopyMedia",
                  @"canEditMedia", @"canReplyMedia", @"canGetInfo", @"canLiveText",
                  @"canAddToStory", @"canAddToAlbum", @"canShareSheet", @"canViewInThread",
                  @"video canSave", @"video canShare", @"video canForward", @"video canCopy",
                  @"video canEdit", @"video canReply", @"video canGetInfo", @"video canLiveText",
                  @"video canAddToStory", @"video canAddToAlbum", @"video canShareSheet"],
                @"Opened %lu greyed-out actions", @"Open a photo and tap Share",
                @[@[@"LSMediaViewController", @"canSaveMedia", @"m"]]),
            PSGOption(@"Media", @"Save button", PRMKeySaveButton,
                @[@"save media", @"save photo", @"save profile"],
                @"Saved or placed the save button %lu times",
                @"Open a profile picture or a story photo",
                @[@[@"LSMediaPhotoViewController", @"_networkImageView", @"i"]]),
            PSGOption(@"Media", @"Content warnings", PRMKeyRevealCensored,
                @[@"censored", @"video censored"], @"Revealed %lu hidden photos",
                @"Open a photo covered by a warning",
                @[@[@"LSMediaViewController", @"isContentCensored", @"m"]]),
            PSGOption(@"Media", @"Replay view once", PRMKeyViewOnce,
                @[@"view once"], @"Kept %lu View once photos", @"Open a View once photo",
                @[@[@"LSMediaViewController", @"markViewOnceMessageAsOpened:", @"m"]]),
            PSGOption(@"Media", @"Loop videos", PRMKeyLoopVideos,
                @[@"video playDidEnd", @"video appeared"], @"Looped %lu videos",
                @"Let a video play to the end",
                @[@[@"LSMediaVideoViewController", @"playDidEnd", @"m"]]),
            PSGOption(@"Media", @"Start videos with sound", PRMKeySoundOnOpen,
                @[@"sound on open"], @"Unmuted %lu videos", @"Open a video full screen",
                @[@[@"LSThreadMediaViewerContentController", @"isAudioMuted", @"m"]]),
            PSGOption(@"Media", @"Speed up videos", PRMKeySpeed,
                @[@"speed"], @"Sped up %lu videos", @"Play a video",
                @[@[@"LSVideoPlayerView", @"setRate:callsite:", @"m"]]),

            PSGOption(@"Meta AI", @"Meta AI in search", PRMKeyHideMetaAI,
                @[@"search bar setter"], @"Replaced the search text %lu times",
                @"Open the chat list",
                @[@[@"MSGUniversalUISearchBar", @"", @"k"]]),
            PSGOption(@"Meta AI", @"Meta AI button", PRMKeyHideMetaAIButton,
                @[[@"suppressed " stringByAppendingString:PRMKeyHideMetaAIButton]],
                @"Removed the Meta AI button %lu times", @"Open the chat list",
                @[@[@"MSGMetaAIFAB.MSGMetaAIFABViewController", @"", @"k"]]),
            PSGOption(@"Meta AI", @"Meta AI in media menu", PRMKeyHideMetaAIMedia,
                @[@"meta ai media"], @"Removed Ask Meta AI %lu times",
                @"Open the menu on a photo",
                @[@[@"LSThreadMediaViewerBucketViewController", @"canOpenMetaAIChat", @"m"]]),

            PSGOption(@"Tab bar", @"Liquid Glass", PRMKeyGlassTabBar,
                @[@"native tab bar"], @"Swapped in the glass tab bar",
                @"Relaunch Messenger", @[@[tabBar, @"", @"k"]]),
            PSGOption(@"Tab bar", @"Chats", PRMKeyHideTabChats,
                @[@"tab bar layout"], @"Removed the tab", @"Relaunch Messenger", tabNeeds),
            PSGOption(@"Tab bar", @"Stories", PRMKeyHideTabStories,
                @[@"tab bar layout"], @"Removed the tab", @"Relaunch Messenger", tabNeeds),
            PSGOption(@"Tab bar", @"Notifications", PRMKeyHideTabNotifications,
                @[@"tab bar layout"], @"Removed the tab", @"Relaunch Messenger", tabNeeds),
            PSGOption(@"Tab bar", @"Menu", PRMKeyHideTabMenu,
                @[@"tab bar layout"], @"Removed the tab", @"Relaunch Messenger", tabNeeds),
        ];
    });
    return options;
}

#pragma mark - Verdicts

static NSString *PSGMessengerVersion(void) {
    return [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"?";
}

// The first requirement missing from this Messenger build, or nil if none.
static NSString *PSGMissingRequirement(NSArray<NSArray<NSString *> *> *needs) {
    for (NSArray<NSString *> *need in needs) {
        Class cls = NSClassFromString(need[0]);
        if (cls == Nil) return need[0];
        NSString *member = need[1];
        NSString *kind = need[2];
        SEL selector = NSSelectorFromString(member);
        BOOL present = YES;
        if ([kind isEqualToString:@"m"]) present = [cls instancesRespondToSelector:selector];
        else if ([kind isEqualToString:@"c"]) present = [cls respondsToSelector:selector];
        else if ([kind isEqualToString:@"e"])
            present = [cls respondsToSelector:selector] || [cls instancesRespondToSelector:selector];
        else if ([kind isEqualToString:@"i"])
            present = class_getInstanceVariable(cls, member.UTF8String) != NULL;
        if (!present) return [NSString stringWithFormat:@"%@ %@", need[0], member];
    }
    return nil;
}

static NSArray<PSGCompatResult *> *PSGCompatResults(void) {
    NSDictionary<NSString *, NSNumber *> *counts = [PRMDebug actionCounts];
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *option in PSGOptions()) {
        PSGCompatResult *result = [[PSGCompatResult alloc] init];
        result.section = option[@"section"];
        result.title = option[@"title"];

        NSUInteger acted = 0;
        for (NSString *counter in option[@"counters"]) acted += counts[counter].unsignedIntegerValue;

        NSString *missing = PSGMissingRequirement(option[@"needs"]);
        if (missing != nil) {
            result.verdict = PSGCompatVerdictBroken;
            result.detail = [NSString stringWithFormat:@"%@ is missing in Messenger %@",
                             missing, PSGMessengerVersion()];
        } else if (![PRMPrefs isEnabled:option[@"key"]]) {
            result.verdict = PSGCompatVerdictOff;
        } else if (acted > 0) {
            result.verdict = PSGCompatVerdictWorking;
            NSString *done = option[@"done"];
            result.detail = [done containsString:@"%lu"]
                ? [NSString stringWithFormat:done, (unsigned long)acted] : done;
        } else {
            result.verdict = PSGCompatVerdictNotSeen;
            result.detail = option[@"hint"];
        }
        [results addObject:result];
    }
    return results;
}

static NSInteger PSGCount(NSArray<PSGCompatResult *> *results, PSGCompatVerdict verdict) {
    NSInteger count = 0;
    for (PSGCompatResult *result in results) if (result.verdict == verdict) count++;
    return count;
}

NSString *PSGCompatStatusText(void) {
    NSInteger broken = PSGCount(PSGCompatResults(), PSGCompatVerdictBroken);
    if (broken > 0) return [NSString stringWithFormat:@"%ld broken", (long)broken];
    return [PRMDebug recording] ? @"Compatible" : @"Not recording";
}

UIColor *PSGCompatStatusColor(void) {
    NSInteger broken = PSGCount(PSGCompatResults(), PSGCompatVerdictBroken);
    if (broken > 0) return [UIColor systemRedColor];
    return [PRMDebug recording] ? [UIColor systemGreenColor] : [UIColor secondaryLabelColor];
}

static NSString *PSGVerdictSymbol(PSGCompatVerdict verdict) {
    switch (verdict) {
        case PSGCompatVerdictWorking: return @"checkmark.circle";
        case PSGCompatVerdictBroken: return @"xmark.circle";
        case PSGCompatVerdictNotSeen: return @"circle.dashed";
        default: return @"minus.circle";
    }
}

static UIColor *PSGVerdictColor(PSGCompatVerdict verdict) {
    switch (verdict) {
        case PSGCompatVerdictWorking: return [UIColor systemGreenColor];
        case PSGCompatVerdictBroken: return [UIColor systemRedColor];
        default: return [UIColor tertiaryLabelColor];
    }
}

static NSString *PSGVerdictTag(PSGCompatVerdict verdict) {
    switch (verdict) {
        case PSGCompatVerdictWorking: return @"[OK]";
        case PSGCompatVerdictBroken: return @"[XX]";
        case PSGCompatVerdictNotSeen: return @"[..]";
        default: return @"[--]";
    }
}

// Section names in first-seen order, which is the settings order.
static NSArray<NSString *> *PSGSections(NSArray<PSGCompatResult *> *results) {
    NSMutableArray *sections = [NSMutableArray array];
    for (PSGCompatResult *result in results) {
        if (![sections containsObject:result.section]) [sections addObject:result.section];
    }
    return sections;
}

static NSString *PSGReportText(void) {
    NSArray<PSGCompatResult *> *results = PSGCompatResults();
    NSString *tweak = @PRIMESENGER_VERSION;
    NSMutableString *text = [NSMutableString stringWithFormat:
        @"PrimeSenger %@ \u00b7 Messenger %@ \u00b7 iOS %@\n%ld working \u00b7 %ld not seen \u00b7 %ld off \u00b7 %ld broken\n",
        tweak, PSGMessengerVersion(), [UIDevice currentDevice].systemVersion,
        (long)PSGCount(results, PSGCompatVerdictWorking),
        (long)PSGCount(results, PSGCompatVerdictNotSeen),
        (long)PSGCount(results, PSGCompatVerdictOff),
        (long)PSGCount(results, PSGCompatVerdictBroken)];
    for (NSString *section in PSGSections(results)) {
        [text appendFormat:@"\n%@\n", section];
        for (PSGCompatResult *result in results) {
            if (![result.section isEqualToString:section]) continue;
            [text appendFormat:@"%@ %@%@\n", PSGVerdictTag(result.verdict), result.title,
                               result.detail.length ? [@" - " stringByAppendingString:result.detail] : @""];
        }
    }
    [text appendString:@"\n--- cache ---\n"];
    for (NSString *line in [PSGCache inventory]) [text appendFormat:@"%@\n", line];
    NSDictionary *status = [PRMDebug statusLines];
    if (status.count > 0) {
        [text appendString:@"\n--- status ---\n"];
        for (NSString *key in [status.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [text appendFormat:@"%@  %@\n", key, status[key]];
        }
    }
    [text appendFormat:@"\n--- log ---\n%@\n", [PRMDebug logText]];
    return text;
}

#pragma mark - Report screen

static UIView *PSGSummaryView(NSArray<PSGCompatResult *> *results, CGFloat width) {
    NSInteger broken = PSGCount(results, PSGCompatVerdictBroken);
    UIColor *tone = broken ? [UIColor systemRedColor] : [UIColor systemGreenColor];
    UIView *summary = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 212.0)];

    UIView *disc = [[UIView alloc] initWithFrame:CGRectMake((width - 60.0) / 2.0, 16.0, 60.0, 60.0)];
    disc.backgroundColor = [tone colorWithAlphaComponent:0.14];
    disc.layer.cornerRadius = 30.0;
    UIImageSymbolConfiguration *markSize =
        [UIImageSymbolConfiguration configurationWithPointSize:26.0 weight:UIImageSymbolWeightBold];
    UIImageView *mark = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:(broken ? @"xmark" : @"checkmark") withConfiguration:markSize]];
    mark.tintColor = tone;
    mark.center = CGPointMake(30.0, 30.0);
    [disc addSubview:mark];
    [summary addSubview:disc];

    UILabel *headline = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 88.0, width - 32.0, 22.0)];
    headline.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    headline.textAlignment = NSTextAlignmentCenter;
    headline.text = broken
        ? [NSString stringWithFormat:@"%ld problem%@ with Messenger %@", (long)broken,
                                     broken == 1 ? @"" : @"s", PSGMessengerVersion()]
        : [NSString stringWithFormat:@"Compatible with Messenger %@", PSGMessengerVersion()];
    [summary addSubview:headline];

    UILabel *subline = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 112.0, width - 32.0, 16.0)];
    subline.font = [UIFont systemFontOfSize:12.0];
    subline.textColor = [UIColor secondaryLabelColor];
    subline.textAlignment = NSTextAlignmentCenter;
    subline.text = [NSString stringWithFormat:@"iOS %@ \u00b7 %lu options",
                    [UIDevice currentDevice].systemVersion, (unsigned long)results.count];
    [summary addSubview:subline];

    NSArray *tiles = @[
        @[@(broken), @"Broken", broken ? [UIColor systemRedColor] : [UIColor secondaryLabelColor]],
        @[@(PSGCount(results, PSGCompatVerdictWorking)), @"Working", [UIColor systemGreenColor]],
        @[@(PSGCount(results, PSGCompatVerdictNotSeen)), @"Not seen", [UIColor labelColor]],
        @[@(PSGCount(results, PSGCompatVerdictOff)), @"Off", [UIColor tertiaryLabelColor]],
    ];
    CGFloat gap = 8.0, inset = 16.0;
    CGFloat tileWidth = (width - inset * 2.0 - gap * 3.0) / 4.0;
    for (NSUInteger i = 0; i < tiles.count; i++) {
        UIView *tile = [[UIView alloc] initWithFrame:
            CGRectMake(inset + i * (tileWidth + gap), 142.0, tileWidth, 58.0)];
        tile.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        tile.layer.cornerRadius = 10.0;
        UILabel *number = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 8.0, tileWidth, 24.0)];
        number.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
        number.textAlignment = NSTextAlignmentCenter;
        number.textColor = tiles[i][2];
        number.text = [tiles[i][0] stringValue];
        UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 34.0, tileWidth, 14.0)];
        caption.font = [UIFont systemFontOfSize:11.0];
        caption.textColor = [UIColor secondaryLabelColor];
        caption.textAlignment = NSTextAlignmentCenter;
        caption.text = tiles[i][1];
        [tile addSubview:number];
        [tile addSubview:caption];
        [summary addSubview:tile];
    }
    return summary;
}

@implementation PSGCompatibilityReportViewController {
    NSArray<PSGCompatResult *> *_results;
    NSArray<NSString *> *_sections;
    NSArray<NSString *> *_cache;
    CGFloat _headerWidth;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Report";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(copyReport)];
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = PSGCloseItem(self, @selector(done));
    }
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 62.0, 0.0, 0.0);
    [self reload];
}

- (void)reload {
    _results = PSGCompatResults();
    _sections = PSGSections(_results);
    _cache = [PSGCache inventory];
    _headerWidth = 0.0;
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width == _headerWidth) return;
    _headerWidth = width;
    self.tableView.tableHeaderView = PSGSummaryView(_results, width);
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyReport {
    [UIPasteboard generalPasteboard].string = PSGReportText();
    UIBarButtonItem *button = self.navigationItem.rightBarButtonItem;
    button.title = @"Copied";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        button.title = @"Copy";
    });
}

// Option sections, then the cache inventory, then Start over.
- (NSInteger)cacheSection { return (NSInteger)_sections.count; }
- (NSInteger)resetSection { return (NSInteger)_sections.count + 1; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_sections.count + 2;
}

- (NSArray<PSGCompatResult *> *)resultsInSection:(NSInteger)section {
    NSString *name = _sections[(NSUInteger)section];
    return [_results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"section == %@", name]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == [self resetSection]) return 1;
    if (section == [self cacheSection]) return (NSInteger)_cache.count;
    return (NSInteger)[self resultsInSection:section].count;
}

- (NSString *)titleForSection:(NSInteger)section {
    if (section == [self resetSection]) return @"";
    if (section == [self cacheSection]) return @"Cache";
    return _sections[(NSUInteger)section];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self titleForSection:section];
    return title.length ? PSGHeader(title, nil, NULL, section) : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PSGHeaderHeight(section, [self titleForSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIImageSymbolConfiguration *size =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightSemibold];

    if (indexPath.section == [self resetSection]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                       reuseIdentifier:nil];
        cell.textLabel.text = @"Start over";
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:size];
        cell.imageView.tintColor = [UIColor systemRedColor];
        return cell;
    }

    if (indexPath.section == [self cacheSection]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                       reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = _cache[(NSUInteger)indexPath.row];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }

    PSGCompatResult *result = [self resultsInSection:indexPath.section][(NSUInteger)indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.imageView.image = [UIImage systemImageNamed:PSGVerdictSymbol(result.verdict) withConfiguration:size];
    cell.imageView.tintColor = PSGVerdictColor(result.verdict);
    cell.textLabel.text = result.title;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    cell.textLabel.textColor = result.verdict == PSGCompatVerdictOff
        ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    cell.detailTextLabel.text = result.detail;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.detailTextLabel.textColor = result.verdict == PSGCompatVerdictBroken
        ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGApplyCard(tableView, cell, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != [self resetSection]) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Start over"
                         message:@"Clears what this session recorded. Your settings are kept."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Start over"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [PRMDebug resetCounts];
        [self reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Compatibility screen

@implementation PSGCompatibilityViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Compatibility";
    PSGStyleTable(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return PSGHeader(@"Session", self, @selector(showHelp), section);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PSGHeaderHeight(section, @"Session");
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (void)showHelp {
    [PSGHelpSheet presentFrom:self title:@"Session" items:@[
        @[@"Record activity",
          @"Watches what every option does while you use Messenger. The stethoscope opens the report anytime.",
          @"stethoscope"],
        @[@"Report",
          @"Every option and the classes it relies on, marked Broken, Working, Not seen or Off.",
          @"list.bullet.rectangle.fill"],
    ]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:PSGSettingsCellIdentifier
                                                            forIndexPath:indexPath];
    if (indexPath.row == 0) {
        [cell prepareWithTitle:@"Record activity" symbol:@"stethoscope"];
        cell.accessoryView = cell.toggle;
        cell.toggle.on = [PRMDebug recording];
        [cell.toggle addTarget:self action:@selector(recordingChanged:)
              forControlEvents:UIControlEventValueChanged];
        return cell;
    }
    [cell prepareWithTitle:@"Report" symbol:@"list.bullet.rectangle.fill"];
    cell.value.text = PSGCompatStatusText();
    cell.value.textColor = PSGCompatStatusColor();
    cell.value.hidden = NO;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGApplyCard(tableView, cell, indexPath);
}

- (void)recordingChanged:(UISwitch *)toggle {
    [PRMPrefs setEnabled:toggle.on forKey:PRMKeyDebugEnabled];
    [PRMDebug refreshFloatingButton];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row != 1) return;
    [self.navigationController pushViewController:
        [[PSGCompatibilityReportViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
                                         animated:YES];
}

@end

#pragma mark - Floating stethoscope

@implementation PRMDebug (PSGCompatibility)

+ (void)openCompatibilityReport {
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window != nil) break;
    }
    UIViewController *host = window.rootViewController;
    while (host.presentedViewController != nil) host = host.presentedViewController;
    if (host == nil) return;
    PSGCompatibilityReportViewController *report =
        [[PSGCompatibilityReportViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:report];
    [host presentViewController:navigation animated:YES completion:nil];
}

@end

#endif
