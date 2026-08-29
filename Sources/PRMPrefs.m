#import "PRMPrefs.h"

NSString *const PRMKeyReadAnonymously       = @"psg_read_anonymously";
NSString *const PRMKeyReadReceiptsManual  = @"psg_read_receipts_manual";
NSString *const PRMKeyStoriesAnonymously    = @"psg_stories_anonymously";
NSString *const PRMKeyHideTypingIndicator   = @"psg_hide_typing_indicator";
NSString *const PRMKeyUnlockMedia           = @"psg_unlock_media";
NSString *const PRMKeyLoopVideos            = @"psg_loop_videos";
NSString *const PRMKeyRevealCensored        = @"psg_reveal_censored";
NSString *const PRMKeyViewOnce              = @"psg_view_once";
NSString *const PRMKeyHideQuickReaction     = @"psg_hide_quick_reaction";
NSString *const PRMKeyUploadHD              = @"psg_upload_hd";
NSString *const PRMKeyHoldToSave            = @"psg_hold_to_save";
NSString *const PRMKeyReadOnReply           = @"psg_read_on_reply";
NSString *const PRMKeyDebugActions          = @"psg_debug_actions";
NSString *const PRMKeyHideStoryReplyBar     = @"psg_hide_story_reply_bar";
NSString *const PRMKeyHidePeopleYouMayKnow  = @"psg_hide_people_you_may_know";
NSString *const PRMKeyCallConfirmation      = @"psg_call_confirmation";
NSString *const PRMKeyHideMetaAI           = @"psg_hide_meta_ai";
NSString *const PRMKeyHideMetaAIButton     = @"psg_hide_meta_ai_button";
NSString *const PRMKeyHideStoriesTray      = @"psg_hide_stories_tray";
NSString *const PRMKeyBlockScreenshotNotice = @"psg_block_screenshot_notice";
NSString *const PRMKeyMasterDisable        = @"psg_master_disable";
NSString *const PRMKeyHidePymkInNotifications = @"psg_hide_pymk_in_notifications";
NSString *const PRMKeyHideTabChats         = @"psg_hide_tab_chats";
NSString *const PRMKeyHideTabStories       = @"psg_hide_tab_stories";
NSString *const PRMKeyHideTabNotifications = @"psg_hide_tab_notifications";
NSString *const PRMKeyHideTabMenu          = @"psg_hide_tab_menu";
NSString *const PRMKeyGlassTabBar          = @"psg_glass_tab_bar";
NSString *const PRMKeyFloatingButton       = @"psg_floating_button";
NSString *const PRMKeyDebugEnabled          = @"psg_debug_enabled";
NSString *const PRMKeyFlexEnabled          = @"psg_flex_enabled";
NSString *const PRMKeyNoAutoKeyboard       = @"psg_no_auto_keyboard";

@implementation PRMPrefs

+ (NSArray<NSString *> *)allKeys {
    return @[
        PRMKeyReadAnonymously,
        PRMKeyReadReceiptsManual,
        PRMKeyStoriesAnonymously,
        PRMKeyHideTypingIndicator,
        PRMKeyUnlockMedia,
        PRMKeyLoopVideos,
        PRMKeyRevealCensored,
        PRMKeyViewOnce,
        PRMKeyHideQuickReaction,
        PRMKeyUploadHD,
        PRMKeyHoldToSave,
        PRMKeyReadOnReply,
        PRMKeyDebugActions,
        PRMKeyHideStoryReplyBar,
        PRMKeyHidePeopleYouMayKnow,
        PRMKeyCallConfirmation,
        PRMKeyHideMetaAI,
        PRMKeyHideMetaAIButton,
        PRMKeyHideStoriesTray,
        PRMKeyBlockScreenshotNotice,
        PRMKeyMasterDisable,
        PRMKeyHidePymkInNotifications,
        PRMKeyHideTabChats,
        PRMKeyHideTabStories,
        PRMKeyHideTabNotifications,
        PRMKeyHideTabMenu,
        PRMKeyGlassTabBar,
        PRMKeyFloatingButton,
        PRMKeyDebugEnabled,
        PRMKeyFlexEnabled,
        PRMKeyNoAutoKeyboard
    ];
}

// Keys carried the pmg_ prefix before the rename. Values written under the
// old names are copied across once, so no setting is lost.
+ (void)migrateLegacyKeys {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    static NSString *const done = @"psg_key_migration_done";
    if ([store boolForKey:done]) return;

    NSUInteger moved = 0;
    for (NSString *key in [self allKeys]) {
        if (![key hasPrefix:@"psg_"]) continue;
        if ([store objectForKey:key] != nil) continue;

        NSString *legacy = [@"pmg_" stringByAppendingString:
                            [key substringFromIndex:4]];
        id value = [store objectForKey:legacy];
        if (value == nil) continue;

        [store setObject:value forKey:key];
        moved++;
    }
    [store setBool:YES forKey:done];
    if (moved > 0) NSLog(@"[PrimeSenger] migrated %lu settings", (unsigned long)moved);
}

+ (void)initialize {
    if (self != [PRMPrefs class]) return;
    [self migrateLegacyKeys];
    // Logging defaults on.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{PRMKeyDebugEnabled: @YES}];
}

+ (BOOL)isEnabled:(NSString *)key {
    if (key.length == 0) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

+ (void)setEnabled:(BOOL)enabled forKey:(NSString *)key {
    if (key.length == 0) {
        NSLog(@"[PrimeSenger] refused to write an empty preference key");
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:key];
    [defaults synchronize];
}

@end
