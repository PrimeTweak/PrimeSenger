// Compatibility report: each option records what it does, and the report
// checks that Messenger still has the classes and methods it relies on.
// Compiled into debug builds only.

#import <UIKit/UIKit.h>

#if PRIMESENGER_DEBUG

@interface PSGCompatibilityViewController : UITableViewController
@end

@interface PSGCompatibilityReportViewController : UITableViewController
@end

// "Compatible", "2 broken" or "Not recording", and its color.
FOUNDATION_EXPORT NSString *PSGCompatStatusText(void);
FOUNDATION_EXPORT UIColor *PSGCompatStatusColor(void);

#endif
