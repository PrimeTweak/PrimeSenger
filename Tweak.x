// PrimeSenger entry point.

#import "PRMDebug.h"

%ctor {
    @autoreleasepool {
        [PRMDebug arm];
    }
}
