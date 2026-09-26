// Preference storage for PrimeSenger. Flags default to off.

#import <Foundation/Foundation.h>

extern NSString *const PRMKeyReadAnonymously;
extern NSString *const PRMKeyReadReceiptsManual;
extern NSString *const PRMKeyStoriesAnonymously;
extern NSString *const PRMKeyHideTypingIndicator;
extern NSString *const PRMKeyUnlockMedia;
extern NSString *const PRMKeyLoopVideos;
extern NSString *const PRMKeyRevealCensored;
extern NSString *const PRMKeyViewOnce;
extern NSString *const PRMKeyHideQuickReaction;
extern NSString *const PRMKeyUploadHD;
extern NSString *const PRMKeySaveButton;
extern NSString *const PRMKeyReadOnReply;
extern NSString *const PRMKeyBlockViewOnceSend;
extern NSString *const PRMKeySoundOnOpen;
extern NSString *const PRMKeyStorySound;
extern NSString *const PRMKeySpeed;
extern NSString *const PRMKeySpeed2;
extern NSString *const PRMKeyHideMetaAIMedia;
extern NSString *const PRMKeySilencedChats;
extern NSString *const PRMKeyHideStoryReplyBar;
extern NSString *const PRMKeyHidePeopleYouMayKnow;
extern NSString *const PRMKeyCallConfirmation;
extern NSString *const PRMKeyHideMetaAI;
extern NSString *const PRMKeyHideMetaAIButton;
extern NSString *const PRMKeyHideStoriesTray;
extern NSString *const PRMKeyBlockScreenshotNotice;
extern NSString *const PRMKeyHidePymkInNotifications;
extern NSString *const PRMKeyHideTabChats;
extern NSString *const PRMKeyHideTabStories;
extern NSString *const PRMKeyHideTabNotifications;
extern NSString *const PRMKeyHideTabMenu;
extern NSString *const PRMKeyGlassTabBar;
extern NSString *const PRMKeyDebugEnabled;
extern NSString *const PRMKeyFlexEnabled;
extern NSString *const PRMKeyFloatingButton;
extern NSString *const PRMKeyNoAutoKeyboard;

@interface PRMPrefs : NSObject

+ (BOOL)isEnabled:(NSString *)key;
+ (void)setEnabled:(BOOL)enabled forKey:(NSString *)key;

@end
