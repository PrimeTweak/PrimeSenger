// PrimeSenger entry point.

#import "PRMDebug.h"
#import "PSGBackup.h"
#import <UIKit/UIKit.h>

%ctor {
    @autoreleasepool {
        [PRMDebug arm];

        // Cache clearing is kept off the launch path: deleting the URL cache
        // while the app opens and purges it at startup can corrupt it. It runs
        // once, a few seconds after the app first becomes active.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ [PSGCache clearIfDue]; });
            });
        }];
    }
}
