// Inbox list. People You May Know is switched off through the flags the
// data source already consults. The row list itself is only measured here:
// the shape of an advert row is not yet known, so nothing is filtered.
// Signatures taken from the binary:
//   -[MSGThreadListDataSource shouldShowThreadlistEndPYMK]  B16@0:8
//   -[MSGThreadListDataSource isPYMKHiddenByUser]           B16@0:8
//   -[MSGThreadListDataSource threadlistEndPYMKDisplayCount] q16@0:8
//   -[MSGThreadListDataSource inboxRows]                    @16@0:8

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

// Observation only. The dump names the class of every row so the advert
// and stories entries can be identified before any filter is written.
// Describes one instance of each distinct row class, once per launch, so
// the class of an advert or stories row can be identified before any
// filter is written. Nothing is removed here.
static NSMutableSet *seenRowClasses = nil;

// Returns the class name of the controller a unit row owns, which is what
// distinguishes the search bar from the stories tray from the folder
// filters. MSGInboxRowUnit exposes -controller; nothing else identifies it.
static NSString *PSGUnitControllerName(id row) {
    if (![row respondsToSelector:@selector(controller)]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(row, @selector(controller));
    if (controller == nil) return nil;
    return NSStringFromClass([controller class]);
}

- (id)inboxRows {
    id rows = %orig;
    [PRMDebug noteHook:@"inboxRows"];
    [PRMDebug dumpCollection:rows label:@"inboxRows"];
    if (![rows isKindOfClass:[NSArray class]]) return rows;

    if (seenRowClasses == nil) seenRowClasses = [NSMutableSet set];
    for (id row in (NSArray *)rows) {
        NSString *kind = NSStringFromClass([row class]);
        NSString *owner = PSGUnitControllerName(row);
        NSString *key = owner ? [kind stringByAppendingString:owner] : kind;
        if ([seenRowClasses containsObject:key]) continue;
        [seenRowClasses addObject:key];
        [PRMDebug log:@"unit %@ owns %@", kind, owner ?: @"(no controller)"];
    }

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
