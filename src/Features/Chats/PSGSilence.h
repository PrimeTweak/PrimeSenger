// Local silence for a chat. The list lives on the phone only: Messenger is
// never told, so a silenced chat never shows as muted anywhere.

#import <Foundation/Foundation.h>

@interface PSGSilence : NSObject

// A stable string for a thread key: its 64-bit key when it has one, its
// description otherwise.
+ (NSString *)identifierForThreadKey:(id)threadKey;

+ (BOOL)isSilenced:(NSString *)identifier;
+ (void)setSilenced:(BOOL)silenced identifier:(NSString *)identifier;
+ (NSUInteger)count;

@end
