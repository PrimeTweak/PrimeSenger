#import "PSGReadReceipts.h"
#import "PRMDebug.h"
#import <objc/message.h>

static BOOL gGateOpen = NO;

@implementation PSGReadReceipts

+ (BOOL)consumeGate {
    if (!gGateOpen) return NO;
    gGateOpen = NO;
    [PRMDebug log:@"read receipt gate consumed"];
    return YES;
}

+ (BOOL)sendReceiptOn:(id)messageList {
    SEL selector = @selector(_notifyObserversDidSetAsRead:);
    if (messageList == nil || ![messageList respondsToSelector:selector]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"target %@ does not respond",
                             messageList ? NSStringFromClass([messageList class]) : @"nil"]
                     forKey:@"manual receipt"];
        return NO;
    }

    gGateOpen = YES;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(messageList, selector, YES);

    // The hook clears the gate when it lets a call through. A gate still
    // open means the call never reached it.
    BOOL delivered = !gGateOpen;
    gGateOpen = NO;

    [PRMDebug setStatus:[NSString stringWithFormat:@"called on %@, hook %@",
                         NSStringFromClass([messageList class]),
                         delivered ? @"passed it through" : @"NEVER SAW IT"]
                 forKey:@"manual receipt"];
    return delivered;
}

@end
