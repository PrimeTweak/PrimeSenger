#import "PSGReadReceipts.h"
#import "PRMDebug.h"
#import <objc/message.h>

static BOOL gGateOpen = NO;
static __weak id gLiveController = nil;

// How long the host's flag stays lowered. Long enough for its own read path
// to run, short enough that nothing else slips through.
static const NSTimeInterval kWindow = 2.0;

@implementation PSGReadReceipts

+ (void)setLiveController:(id)controller {
    gLiveController = controller;
}

+ (BOOL)consumeGate {
    if (!gGateOpen) return NO;
    gGateOpen = NO;
    return YES;
}

// Written through key-value coding: the ivar is private and its layout is
// not exposed, but the key reaches it.
+ (BOOL)setFlag:(BOOL)value on:(id)controller {
    if (controller == nil) return NO;
    @try {
        [controller setValue:@(value) forKey:@"disableReadReceipts"];
        return YES;
    } @catch (NSException *problem) {
        return NO;
    }
}

+ (BOOL)sendReceiptOn:(id)messageList {
    id target = messageList ?: gLiveController;

    // Lowered, so the host may send. The gate lets one suppressed
    // notification through as well, which keeps the interface in step.
    if (![self setFlag:NO on:target]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"key unreachable on %@",
                             target ? NSStringFromClass([target class]) : @"nil"]
                     forKey:@"manual receipt"];
        return NO;
    }
    gGateOpen = YES;

    SEL notify = @selector(_notifyObserversDidSetAsRead:);
    if ([target respondsToSelector:notify]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, notify, YES);
    }

    __weak id weakTarget = target;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self setFlag:YES on:weakTarget];
        gGateOpen = NO;
    });

    [PRMDebug setStatus:[NSString stringWithFormat:@"flag lowered on %@ for %.0fs",
                         NSStringFromClass([target class]), kWindow]
                 forKey:@"manual receipt"];
    return YES;
}

@end
