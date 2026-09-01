// Local silence for a chat. The list lives on the phone only: Messenger is
// never told, so a silenced chat never shows as muted anywhere.

#import <Foundation/Foundation.h>

@interface PSGSilence : NSObject

// A stable string for a thread key, whatever object the host hands over: the
// 64-bit key when the object exposes one, its description otherwise. Both
// sides of the feature use this, so the same thread always produces the same
// string.
+ (NSString *)identifierForThreadKey:(id)threadKey;

+ (BOOL)isSilenced:(NSString *)identifier;
+ (void)setSilenced:(BOOL)silenced identifier:(NSString *)identifier;
+ (NSUInteger)count;

@end
