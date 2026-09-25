// Shared media gate helpers, used by both media controllers.

#import <Foundation/Foundation.h>

// Turns a refusal into an allowance while the media switch is on.
BOOL PSGUnlockGate(BOOL original, NSString *name);

// Clears the censor flag while the reveal switch is on.
BOOL PSGCensorGate(BOOL original, NSString *name);
