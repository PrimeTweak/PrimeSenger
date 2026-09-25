// Manual receipts: the host's _disableReadReceipts flag is lowered for a
// short window so its own read path sends a single receipt.

#import <Foundation/Foundation.h>

@interface PSGReadReceipts : NSObject

// The thread currently on screen, or nil. Held weakly.
+ (void)setLiveController:(id)controller;

// The thread currently on screen, or nil if it has gone away.
+ (id)liveController;

// YES while a receipt has been asked for by hand. Consumed by the first
// suppressed notification that checks it.
+ (BOOL)consumeGate;

// Lowers the host's flag for a moment and nudges its read path. Returns NO
// when the flag cannot be reached, so the caller can report it.
+ (BOOL)sendReceiptOn:(id)messageList;

@end
