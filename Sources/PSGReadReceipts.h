// Read receipts.
//
// The host keeps its own flag, _disableReadReceipts, set from the thread's
// initialiser. PSGAnonymity writes it on viewDidLoad, which stops the
// receipt at the source rather than only silencing local observers.
//
// Manual mode lowers that flag for a short window so the host's own read
// path can run once, then raises it again.

#import <Foundation/Foundation.h>

@interface PSGReadReceipts : NSObject

// The thread currently on screen, or nil. Held weakly.
+ (void)setLiveController:(id)controller;

// YES while a receipt has been asked for by hand. Consumed by the first
// suppressed notification that checks it.
+ (BOOL)consumeGate;

// Lowers the host's flag for a moment and nudges its read path. Returns NO
// when the flag cannot be reached, so the caller can report it.
+ (BOOL)sendReceiptOn:(id)messageList;

@end
