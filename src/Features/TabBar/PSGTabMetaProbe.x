// Debug probe for two Messenger 584 changes, measured in one recording: the
// class that now carries the chat notification-presentation method (Mute bell
// lost its old host) and the identity of the new Meta AI tab. Logs once while
// Record activity is on. Debug builds only.

#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#if PRIMESENGER_DEBUG

// Every class exposing a notification-presentation method, so Mute bell can be
// repointed to wherever 584 moved it and to its current selector.
static void PSGScanNotificationHosts(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (classes == NULL) return;

    NSUInteger hits = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(classes[i], &methodCount);
        if (methods == NULL) continue;
        for (unsigned int j = 0; j < methodCount; j++) {
            NSString *sel = NSStringFromSelector(method_getName(methods[j]));
            if ([sel rangeOfString:@"notificationPresentationOptions"
                           options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [PRMDebug log:@"mutebell host: %@ -%@",
                          NSStringFromClass(classes[i]), sel];
                hits++;
            }
        }
        free(methods);
    }
    free(classes);

    [PRMDebug log:@"mutebell scan: %lu host(s)", (unsigned long)hits];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%lu notif-presentation host(s)",
                         (unsigned long)hits]
                 forKey:@"mute bell probe"];
}

// Every ivar of the object whose name carries "identifier", with its value,
// so a stable, language-independent key can be matched instead of the label.
static NSString *PSGIdentifierIvars(id object) {
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (Class cls = [object class]; cls != Nil && cls != [NSObject class];
         cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        if (ivars == NULL) continue;
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = @(ivar_getName(ivars[i]) ?: "");
            if ([name rangeOfString:@"dentifier"].location == NSNotFound) continue;
            id value = nil;
            @try { value = [object valueForKey:name]; } @catch (NSException *problem) {}
            [found addObject:[NSString stringWithFormat:@"%@=%@", name, value ?: @"(nil)"]];
        }
        free(ivars);
    }
    return found.count ? [found componentsJoinedByString:@" "] : @"-";
}

// Each tab's name as the hide logic reads it, its stable identifiers, and
// every bar subview, so the Meta AI tab and a relabeled Menu tab can both be
// matched by something other than the displayed text.
static void PSGDumpTabs(UIView *host) {
    if ([host respondsToSelector:@selector(items)]) {
        NSArray *items = ((id (*)(id, SEL))objc_msgSend)(host, @selector(items));
        NSUInteger index = 0;
        for (id entry in items) {
            if (![entry isKindOfClass:[UITabBarItem class]]) continue;
            UITabBarItem *item = entry;
            [PRMDebug log:@"tab item %lu: title=%@ a11y=%@ a11yId=%@ tag=%ld class=%@ ivars[%@]",
                      (unsigned long)index++, item.title ?: @"(nil)",
                      item.accessibilityLabel ?: @"(nil)",
                      item.accessibilityIdentifier ?: @"(nil)", (long)item.tag,
                      NSStringFromClass([item class]), PSGIdentifierIvars(item)];
        }
    }
    for (UIView *child in host.subviews) {
        [PRMDebug log:@"tab subview: a11y=%@ a11yId=%@ tag=%ld class=%@ ivars[%@]",
                  child.accessibilityLabel ?: @"(nil)",
                  child.accessibilityIdentifier ?: @"(nil)", (long)child.tag,
                  NSStringFromClass([child class]), PSGIdentifierIvars(child)];
    }
}

%hook _TtC15MDSModernTabBar15MDSModernTabBar

- (void)layoutSubviews {
    %orig;
    if (![PRMDebug recording]) return;

    static dispatch_once_t scanToken;
    dispatch_once(&scanToken, ^{ PSGScanNotificationHosts(); });

    static BOOL dumped = NO;
    if (dumped) return;
    UIView *host = (UIView *)self;
    if (host.subviews.count == 0) return;
    [PRMDebug log:@"tab dump ==="];
    PSGDumpTabs(host);
    dumped = YES;
}

%end

#endif
