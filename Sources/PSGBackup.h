// Backup & reset: settings export and import, the cache, and a full reset.

#import <UIKit/UIKit.h>

@interface PSGBackupViewController : UITableViewController
@end

@interface PSGCache : NSObject
// What Clear cache removes: temporary files and the network cache.
+ (unsigned long long)clearableBytes;
+ (void)clear;
// Clears at launch when the chosen interval has passed.
+ (void)clearIfDue;
// Top-level items of Library/Caches with their sizes, for the report.
+ (NSArray<NSString *> *)inventory;
@end
