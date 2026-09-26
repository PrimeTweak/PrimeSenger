// Backup & reset: settings export and import, the cache, and a full reset.

#import <UIKit/UIKit.h>

@interface PSGBackupViewController : UITableViewController
@end

@interface PSGCache : NSObject
// What Clear cache removes: logs, crash reports, network and web caches,
// and temporary files. Anything else in the cache folder is left alone.
+ (unsigned long long)clearableBytes;
+ (void)clear;
// Clears at launch when the chosen interval has passed.
+ (void)clearIfDue;
@end
