// PrimeSenger entry point.

#import "PRMDebug.h"
#import "PSGBackup.h"

%ctor {
    @autoreleasepool {
        [PSGCache clearIfDue];
        [PRMDebug arm];
    }
}
