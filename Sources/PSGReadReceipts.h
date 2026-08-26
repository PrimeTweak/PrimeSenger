// One-shot gate for read receipts.
//
// The Read receipts switch suppresses -[MSGMessageListViewController
// _notifyObserversDidSetAsRead:]. Manual mode keeps that suppression and
// opens the gate for exactly one call, raised by the eye in the thread bar.

#import <Foundation/Foundation.h>

@interface PSGReadReceipts : NSObject

// YES while a receipt has been asked for by hand. Consumed by the first
// suppressed call that checks it.
+ (BOOL)consumeGate;

// Opens the gate and invokes the receipt on the given message list.
// Returns NO when the controller cannot take the call, so the caller can
// report it rather than fail silently.
+ (BOOL)sendReceiptOn:(id)messageList;

@end
