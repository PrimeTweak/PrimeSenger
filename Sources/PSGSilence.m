#import "PSGSilence.h"
#import "PRMDebug.h"
#import <objc/message.h>

static NSString *const kPSGSilencedKeys = @"psg_silenced_thread_keys";

@implementation PSGSilence

+ (NSString *)identifierForThreadKey:(id)threadKey {
    if (threadKey == nil) return nil;
    // Measured: MSGThreadsTableThreadKey answers threadKey with a 64-bit
    // integer. Other carriers fall back to their description.
    if ([threadKey respondsToSelector:@selector(threadKey)]) {
        long long key = ((long long (*)(id, SEL))objc_msgSend)(threadKey, @selector(threadKey));
        if (key != 0) return [NSString stringWithFormat:@"%lld", key];
    }
    if ([threadKey isKindOfClass:[NSNumber class]]) return [threadKey stringValue];
    if ([threadKey isKindOfClass:[NSString class]]) return threadKey;
    return [threadKey description];
}

+ (NSArray<NSString *> *)stored {
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:kPSGSilencedKeys];
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

+ (BOOL)isSilenced:(NSString *)identifier {
    return identifier != nil && [[self stored] containsObject:identifier];
}

+ (void)setSilenced:(BOOL)silenced identifier:(NSString *)identifier {
    if (identifier == nil) return;
    NSMutableArray *list = [[self stored] mutableCopy];
    if (silenced && ![list containsObject:identifier]) [list addObject:identifier];
    if (!silenced) [list removeObject:identifier];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kPSGSilencedKeys];
    [PRMDebug log:@"silence %@ %@ (%lu total)", silenced ? @"on" : @"off",
                  identifier, (unsigned long)list.count];
}

+ (NSUInteger)count {
    return [self stored].count;
}

@end
