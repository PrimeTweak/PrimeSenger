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
// Stored under its original name so an existing setting is not lost.
NSString *const PRMKeySaveButton            = @"psg_hold_to_save";
NSString *const PRMKeyReadOnReply           = @"psg_read_on_reply";
NSString *const PRMKeyBlockViewOnceSend     = @"psg_block_view_once_send";
NSString *const PRMKeySoundOnOpen           = @"psg_sound_on_open";
NSString *const PRMKeyStorySound            = @"psg_story_sound";
NSString *const PRMKeySpeed                 = @"psg_speed";
NSString *const PRMKeySpeed2                = @"psg_speed_2";
NSString *const PRMKeyHideMetaAIMedia       = @"psg_hide_meta_ai_media";
NSString *const PRMKeySilencedChats         = @"psg_silenced_chats";
NSString *const PRMKeyHideStoryReplyBar     = @"psg_hide_story_reply_bar";
NSString *const PRMKeyHidePeopleYouMayKnow  = @"psg_hide_people_you_may_know";
NSString *const PRMKeyCallConfirmation      = @"psg_call_confirmation";
NSString *const PRMKeyHideMetaAI           = @"psg_hide_meta_ai";
NSString *const PRMKeyHideMetaAIButton     = @"psg_hide_meta_ai_button";
NSString *const PRMKeyHideStoriesTray      = @"psg_hide_stories_tray";
NSString *const PRMKeyBlockScreenshotNotice = @"psg_block_screenshot_notice";
NSString *const PRMKeyHidePymkInNotifications = @"psg_hide_pymk_in_notifications";
NSString *const PRMKeyHideTabChats         = @"psg_hide_tab_chats";
NSString *const PRMKeyHideTabStories       = @"psg_hide_tab_stories";
NSString *const PRMKeyHideTabNotifications = @"psg_hide_tab_notifications";
NSString *const PRMKeyHideTabMenu          = @"psg_hide_tab_menu";
NSString *const PRMKeyGlassTabBar          = @"psg_glass_tab_bar";
NSString *const PRMKeyDebugEnabled          = @"psg_debug_enabled";
NSString *const PRMKeyFlexEnabled          = @"psg_flex_enabled";
NSString *const PRMKeyFloatingButton       = @"psg_floating_button";
NSString *const PRMKeyNoAutoKeyboard       = @"psg_no_auto_keyboard";

@implementation PRMPrefs

+ (BOOL)isEnabled:(NSString *)key {
    if (key.length == 0) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

+ (void)setEnabled:(BOOL)enabled forKey:(NSString *)key {
    if (key.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:key];
    [defaults synchronize];
}

@end
