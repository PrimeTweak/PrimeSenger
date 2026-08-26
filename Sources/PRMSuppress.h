// Suppression by controller identity.
//
// Two approaches were measured to work where method-level hooks did not:
// matching a controller by class name and hiding its view, and filtering a
// row list by asking each row which controller it owns. Both need the same
// lookup, so it lives here and is shared across the Prime line.

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
