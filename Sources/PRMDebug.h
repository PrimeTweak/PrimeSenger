// On-device debugging for a sideloaded build, where no console exists: a
// rolling log, per-hook counters and status lines, recorded only while
// Record activity is on.

#import <UIKit/UIKit.h>

@interface PRMDebug : NSObject

// Installs the floating button once the application becomes active.
+ (void)arm;

// Appends one line to the rolling log. Cheap when debug is switched off.
+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

// Records that a hook body ran. Counted regardless of the logging switch.
+ (void)noteHook:(NSString *)name;

// Records that a hook changed behaviour rather than merely observing.
+ (void)noteAction:(NSString *)name;

// Logs the class of every element of a collection.
+ (void)dumpCollection:(id)collection label:(NSString *)label;

// Records that a screen appeared, and captures its view tree the first
// time that screen class is seen.
+ (void)noteScreen:(NSString *)className view:(UIView *)view;

// One line of state per subsystem, included in the copied report.
+ (void)setStatus:(NSString *)value forKey:(NSString *)name;
// YES while Record activity is on; always NO in a release build.
+ (BOOL)recording;
+ (NSDictionary<NSString *, NSNumber *> *)actionCounts;
+ (NSDictionary<NSString *, NSString *> *)statusLines;
+ (NSString *)logText;
+ (void)resetCounts;



// Re-places the floating button after the keyboard has moved.
+ (void)keyboardFrameChanged:(NSNotification *)note;

// Glides the floating button back to its slot after a manual move.
+ (void)returnButtonToSlot;


// Places or removes the floating button according to the current switches.
+ (void)installButton;


@end

// FLEX, resolved at runtime so a build without it still loads.
@interface PRMDebug (PSGFlex)

// Brings the explorer in line with the stored preference.
+ (void)applyFlexState;

@end

@interface PRMDebug (PRMLauncher)

// Opens the tweak's settings. The floating button's tap goes here, so the
// tweak stays reachable when the Menu tab is hidden.
+ (void)openSettings;

// Re-evaluates whether the floating button should be on screen.
+ (void)refreshFloatingButton;

@end

#if PRIMESENGER_DEBUG
@interface PRMDebug (PSGCompatibility)
+ (void)openCompatibilityReport;
@end
#endif
