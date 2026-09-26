// The chat list: People you may know through the flags the data source
// consults, and rows owned by a hidden controller dropped from the list.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PRMSuppress.h"
#import <objc/message.h>

%hook MSGThreadListDataSource

- (BOOL)shouldShowThreadlistEndPYMK {
    [PRMDebug noteHook:@"pymk show"];
    if ([PRMPrefs isEnabled:PRMKeyHidePeopleYouMayKnow]) {
        [PRMDebug noteAction:@"pymk show"];
        return NO;
    }
    return %orig;
}

- (BOOL)isPYMKHiddenByUser {
    [PRMDebug noteHook:@"pymk hidden"];
    if ([PRMPrefs isEnabled:PRMKeyHidePeopleYouMayKnow]) {
        [PRMDebug noteAction:@"pymk hidden"];
        return YES;
    }
    return %orig;
}

- (long long)threadlistEndPYMKDisplayCount {
    [PRMDebug noteHook:@"pymk count"];
    if ([PRMPrefs isEnabled:PRMKeyHidePeopleYouMayKnow]) {
        [PRMDebug noteAction:@"pymk count"];
        return 0;
    }
    return %orig;
}

// Returns the class name of the controller a unit row owns, which tells the
// search bar, the stories tray and the folder filters apart. Rows are
// recognized by answering -controller.
static NSString *PSGUnitControllerName(id row) {
    if (![row respondsToSelector:@selector(controller)]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(row, @selector(controller));
    if (controller == nil) return nil;
    return NSStringFromClass([controller class]);
}

- (id)inboxRows {
    id rows = %orig;
    [PRMDebug noteHook:@"inboxRows"];
    if (![rows isKindOfClass:[NSArray class]]) return rows;

    NSMutableArray *kept = [NSMutableArray array];
    BOOL removed = NO;
    for (id row in (NSArray *)rows) {
        NSString *owner = PSGUnitControllerName(row);
        if (owner != nil && [PRMSuppress shouldSuppressControllerName:owner]) {
            [PRMDebug log:@"dropped row owned by %@", owner];
            removed = YES;
            continue;
        }
        [kept addObject:row];
    }
    if (!removed) return rows;
    [PRMDebug noteAction:@"inboxRows"];
    return kept;
}

%end
