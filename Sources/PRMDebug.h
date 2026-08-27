// On-device debugger. No console is available on a sideloaded build, so
// everything is reported on screen: a rolling log, per-hook fire counts,
// class and method inspection, and object dumps for structures whose
// shape is not yet known.

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

// Walks the key window and logs every view class with its frame, so an
// on-screen element can be identified by looking at it.
+ (void)dumpViewHierarchy;

// Records that a screen appeared, and captures its view tree the first
// time that screen class is seen.
+ (void)noteScreen:(NSString *)className view:(UIView *)view;

// Dumps every loaded class whose name matches one of the built-in family
// patterns, with its selectors. One call replaces a round of builds spent
// asking what a class exposes.
+ (void)runFullScan;

// Places the entire report on the pasteboard. Returns its length so the
// caller can confirm something was copied.
+ (NSUInteger)copyReportToPasteboard;

// Reports whether the bundle opts out of the current design system.
+ (void)reportDesignMode;

// One-line state per subsystem, shown at the top of the report.
+ (void)setStatus:(NSString *)value forKey:(NSString *)name;

// Reports whether a view and all of its ancestors are visible.
+ (BOOL)viewIsOnScreen:(UIView *)view;

// Re-places the floating button after the keyboard has moved.
+ (void)keyboardFrameChanged:(NSNotification *)note;

// Records whether fleXD is linked in, for the report.
+ (void)reportFlexPresence;

// Re-places the floating button when the host's own has moved.
+ (void)hostDidMove;

// Places or removes the floating button according to the current switches.
+ (void)installButton;


// Opens the report.
+ (void)present;

@end

// Implemented in PRMLauncher.m, which is where the Messenger-specific
// settings screen is known. Declared on a category so the main
// implementation is not held responsible for defining them.
// fleXD, resolved at runtime so a missing clone cannot break the build.
@interface PRMDebug (PSGFlex)

+ (BOOL)flexAvailable;
+ (void)toggleFlex;

@end

@interface PRMDebug (PRMLauncher)

// Opens the tweak's settings. The floating button's tap goes here, so the
// tweak stays reachable when the Menu tab is hidden.
+ (void)openSettings;

// Re-evaluates whether the floating button should be on screen.
+ (void)refreshFloatingButton;

@end
