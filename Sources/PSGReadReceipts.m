#import "PSGReadReceipts.h"
#import "PRMDebug.h"
#import <objc/runtime.h>
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

+ (BOOL *)flagSlotFor:(id)controller {
    if (controller == nil) return NULL;
    Ivar flag = class_getInstanceVariable([controller class], "_disableReadReceipts");
    if (flag == NULL) return NULL;
    return (BOOL *)((__bridge void *)controller + ivar_getOffset(flag));
}

+ (BOOL)sendReceiptOn:(id)messageList {
    id target = messageList ?: gLiveController;
    BOOL *slot = [self flagSlotFor:target];

    if (slot == NULL) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"flag unreachable on %@",
                             target ? NSStringFromClass([target class]) : @"nil"]
                     forKey:@"manual receipt"];
        return NO;
    }

    // Lowered, so the host may send. The gate lets one suppressed
    // notification through as well, which keeps the interface in step.
    *slot = NO;
    gGateOpen = YES;

    SEL notify = @selector(_notifyObserversDidSetAsRead:);
    if ([target respondsToSelector:notify]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, notify, YES);
    }

    __weak id weakTarget = target;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id strongTarget = weakTarget;
        BOOL *later = [self flagSlotFor:strongTarget];
        if (later != NULL) *later = YES;
        gGateOpen = NO;
    });

    [PRMDebug setStatus:[NSString stringWithFormat:@"flag lowered on %@ for %.0fs",
                         NSStringFromClass([target class]), kWindow]
                 forKey:@"manual receipt"];
    return YES;
}

@end
