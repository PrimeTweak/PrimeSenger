# PrimeSenger

A Messenger enhancer. Part of the Prime line, alongside PrimeFreeBird and PrimeGram.

## Naming

| Prefix | Scope |
| --- | --- |
| `PRM` | Shared core reused across the Prime line |
| `PSG` | Messenger-specific hooks and settings |

## Language

English only. Identifiers, comments, UI strings, and repository content.
A single `Base.lproj` — no other locale.

## Target

Messenger `com.facebook.Messenger` 575.0.0, iOS 15.1 and later, arm64.
Built against the iOS 16.5 SDK. The host app and its frameworks are arm64
only, so no second slice is produced.

## Build

Run the **Build PrimeSenger** workflow from the Actions tab with a URL to a
decrypted Messenger IPA. It produces the dylib, then a patched IPA with the
dylib and the sideload keychain fix injected and Meta's entitlements
preserved.

## Sideload requirements

Both files under `Resources/` are required, and were established by
measurement rather than assumption:

- `Messenger.entitlements` — Meta's own entitlements, preserved through
  repackaging. Without them auth storage aborts before `main`.
- `SideloadKeychainFix.dylib` — rebinds the `SecItem` functions so keychain
  queries scoped to the original team identifier resolve. Thin arm64: the
  universal wrapper it originally shipped in placed the signed slice one
  page off, and the second code page failed to validate.

## Features

Every switch defaults to off. Nothing changes behaviour until it is enabled
in the settings screen.

| Switch | Hook |
| --- | --- |
| Read anonymously | `MSGMessageListViewController _notifyObserversDidSetAsRead:` |
| Hide typing indicator | `MSGTypingIndicatorView shouldHideTypingIndicator:` |
| Remove People You May Know | `MSGThreadListDataSource` PYMK flags |
| Plain search placeholder | `MSGSearchBarPlaceholderProvider` |
| Watch stories anonymously | `MSGStoryBucketsDataManager markStoriesAsSeen:...` |
| Hide story reply bar | `LSStoryBucketViewController _addReplyBarViewController` |
| Unlock media | `LSMediaViewController canSaveMedia` and siblings |
| Confirm before calling | `LSRTCCallButton handleButtonTap` |
| Remove suggestions from Notifications | `MSGJewelNotificationDataManager peopleYouMayKnowSuggestionJewels` |
| Hide individual tabs | `MDSModernTabBar layoutSubviews`, matched on the button accessibility label |
| Liquid Glass tab bar | The bar's own `UIVisualEffectView` re-effected with `UIGlassEffect` |

## Settings screen

Built to the metrics measured off Messenger's own settings: no section
titles, 52pt single-line rows, a 24pt filled glyph at the leading edge, text
and separators at 62pt, 26pt between groups.

Labels name the thing rather than the action, as every native row does, so a
switch reads as "this is present". Preferences that store "hide this" are
therefore displayed inverted — the stored keys are unchanged, only their
reading flips, in `PSGSettingsRow`.

Opened from a filled bolt in the top right of Messenger's settings.

## Debugging

A floating `PM` button appears on every screen. Tap it for the report, long
press to capture the current screen's view tree and copy everything to the
clipboard.

The settings screen offers a full scan, which dumps the selectors, type
encodings and ivars of every class the tweak targets, plus a sweep of loaded
classes against name patterns. Screens are recorded automatically as they
appear.

## Not implemented

- Screenshot detection blocking: `MSGApplication` exposes no handler in 575.
- Advert filtering: `inboxRows` is observed only. No advert row has been seen
  yet, and no filter is written on an unmeasured class name.

## License

Proprietary. All rights reserved. See LICENSE.
