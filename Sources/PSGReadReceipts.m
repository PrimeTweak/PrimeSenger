#import "PSGReadReceipts.h"
#import "PRMDebug.h"
#import <objc/message.h>
#import <dlfcn.h>

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

// Measured in the host binary: the mailbox SDK exposes a C entry point that
// marks a thread read, and posts MCAMailboxSDKDidMarkThreadAsReadNotification
// when it lands. Lowering the flag alone sends nothing, because nothing in
// the host asks again once the thread is already on screen.
typedef void (*PSGMarkReadFunction)(id, id);

+ (BOOL)sendReceiptOn:(id)messageList {
    id target = messageList ?: gLiveController;
    if (target == nil) {
        [PRMDebug setStatus:@"no live thread" forKey:@"manual receipt"];
        return NO;
    }

    // Lowered first: the send path checks it, and the gate lets one
    // suppressed notification through so the interface follows.
    BOOL lowered = [self setFlag:NO on:target];
    gGateOpen = YES;

    NSMutableArray<NSString *> *tried = [NSMutableArray array];
    BOOL sent = NO;

    // The host's own entry point, resolved by name so a rename is reported
    // rather than crashed on.
    PSGMarkReadFunction mark = (PSGMarkReadFunction)
        dlsym(RTLD_DEFAULT, "MCAMailboxSDKMarkAsReadThreadWithThreadIdentifier");
    id threadKey = nil;
    @try { threadKey = [target valueForKey:@"threadQueryKey"]; } @catch (NSException *ignored) {}

    if (mark != NULL && threadKey != nil) {
        mark(threadKey, nil);
        [tried addObject:@"mailbox SDK"];
        sent = YES;
    } else {
        [tried addObject:mark == NULL ? @"symbol absent" : @"no thread key"];
    }

    SEL notify = @selector(_notifyObserversDidSetAsRead:);
    if ([target respondsToSelector:notify]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, notify, YES);
        [tried addObject:@"observers"];
    }

    __weak id weakTarget = target;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self setFlag:YES on:weakTarget];
        gGateOpen = NO;
    });

    [PRMDebug setStatus:[NSString stringWithFormat:@"flag %@ | %@ | key %@",
                         lowered ? @"lowered" : @"UNREACHABLE",
                         [tried componentsJoinedByString:@", "],
                         threadKey ? NSStringFromClass([threadKey class]) : @"nil"]
                 forKey:@"manual receipt"];
    return sent;
}

@end
