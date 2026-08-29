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

+ (id)liveController {
    return gLiveController;
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

// The receipt is sent by the host's own read path, gated on the flag. No
// exported C entry point could be reached: the symbol named in the binary
// strings is not in the symbol table. Instead the flag is lowered and the
// host is asked to rerun the path it already runs on appearance and on
// return to the foreground.
//
// Measured on MSGMessageListViewController:
//   -viewDidAppear:                     v20@0:8B16
//   -_handleApplicationDidBecomeActive: v24@0:8@16
//   -_notifyObserversDidSetAsRead:      v20@0:8B16

+ (BOOL)sendReceiptOn:(id)messageList {
    id target = messageList ?: gLiveController;
    if (target == nil) {
        [PRMDebug setStatus:@"no live thread" forKey:@"manual receipt"];
        return NO;
    }

    // Lowered first: the send path checks it. The gate lets one suppressed
    // notification through so the interface follows.
    BOOL lowered = [self setFlag:NO on:target];
    gGateOpen = YES;

    NSMutableArray<NSString *> *ran = [NSMutableArray array];

    // Rerun the paths the host itself uses. Each is measured to exist; any
    // that does not respond is skipped and reported.
    SEL becameActive = @selector(_handleApplicationDidBecomeActive:);
    if ([target respondsToSelector:becameActive]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, becameActive, nil);
        [ran addObject:@"didBecomeActive"];
    }

    SEL appeared = @selector(viewDidAppear:);
    if ([target respondsToSelector:appeared]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, appeared, NO);
        [ran addObject:@"viewDidAppear"];
    }

    SEL notify = @selector(_notifyObserversDidSetAsRead:);
    if ([target respondsToSelector:notify]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, notify, YES);
        [ran addObject:@"observers"];
    }

    __weak id weakTarget = target;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self setFlag:YES on:weakTarget];
        gGateOpen = NO;
    });

    [PRMDebug setStatus:[NSString stringWithFormat:@"flag %@ | ran %@",
                         lowered ? @"lowered" : @"UNREACHABLE",
                         ran.count ? [ran componentsJoinedByString:@", "] : @"nothing"]
                 forKey:@"manual receipt"];
    return lowered && ran.count > 0;
}

@end
