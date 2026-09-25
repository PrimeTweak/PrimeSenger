// Suppression by controller identity: a controller matched by class name
// has its view hidden, and a row it owns is dropped from lists.

#import <Foundation/Foundation.h>

@interface PRMSuppress : NSObject

// Returns the preference key governing a controller class name, or nil when
// no rule covers it. Matching is a case-insensitive substring test, because
// Swift classes report as "Module.Class" and carry module prefixes.
+ (NSString *)keyForControllerName:(NSString *)name;

// Convenience: whether a controller class name should be suppressed right
// now, given the current switch states.
+ (BOOL)shouldSuppressControllerName:(NSString *)name;

@end
