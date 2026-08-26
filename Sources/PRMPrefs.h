// Preference storage shared across the Prime line. Flags default to off.

#import <Foundation/Foundation.h>

extern NSString *const PRMKeyReadAnonymously;
extern NSString *const PRMKeyReadReceiptsManual;
extern NSString *const PRMKeyStoriesAnonymously;
extern NSString *const PRMKeyHideTypingIndicator;
extern NSString *const PRMKeyUnlockMedia;
extern NSString *const PRMKeyLoopVideos;
extern NSString *const PRMKeyHideStoryReplyBar;
extern NSString *const PRMKeyHidePeopleYouMayKnow;
extern NSString *const PRMKeyCallConfirmation;
extern NSString *const PRMKeyHideMetaAI;
extern NSString *const PRMKeyHideMetaAIButton;
extern NSString *const PRMKeyHideStoriesTray;
extern NSString *const PRMKeyBlockScreenshotNotice;
extern NSString *const PRMKeyMasterDisable;
extern NSString *const PRMKeyHidePymkInNotifications;
extern NSString *const PRMKeyHideTabChats;
extern NSString *const PRMKeyHideTabStories;
extern NSString *const PRMKeyHideTabNotifications;
extern NSString *const PRMKeyHideTabMenu;
extern NSString *const PRMKeyGlassTabBar;
extern NSString *const PRMKeyFloatingButton;
extern NSString *const PRMKeyDebugEnabled;

@interface PRMPrefs : NSObject

// Every key this tweak stores, in declaration order.
+ (NSArray<NSString *> *)allKeys;

+ (BOOL)isEnabled:(NSString *)key;
+ (void)setEnabled:(BOOL)enabled forKey:(NSString *)key;

@end
