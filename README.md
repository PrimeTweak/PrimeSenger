# PrimeSenger

A Messenger tweak for privacy, media and a cleaner interface.

## Requirements

Messenger 584.0.0 on iOS 15.1 or later, sideloaded.

## Features

Settings open from the sparkles at the top of Messenger's settings, or from the
floating button, which shows on its own when the Menu tab is hidden and anytime
with the Floating button option. Each switch names a change to Messenger; on
applies it.

**Privacy** — read anonymously (always, with a manual eye, or until you reply),
hide the typing indicator, watch stories anonymously, block screenshot alerts.

**Chats** — hide the quick reaction, keep the keyboard closed, confirm before
calling, upload in HD, block View once, a mute bell that silences a chat on this
phone only.

**Chat list** — hide the stories tray, People you may know and friend suggestions.

**Stories** — hide the reply bar, start stories with sound.

**Media** — unlock grayed-out media actions, a save button for story,
disappearing and profile pictures, reveal covered photos, replay View once
photos, loop videos, start videos with sound, speed up videos.

**Meta AI** — hide it in search, the chat list button and the media menu.

**Tab bar** — Liquid Glass, and hidden tabs: any of the five.

**Tools** — Backup & reset (export and import your settings, clear the cache,
reset to defaults), and FLEX explorer, which inspects what is on screen.

## Compatibility

Debug builds add a Compatibility page. Turn on Record activity after a
Messenger update and use the app: the report marks every option Working,
Not seen, Off or Broken, and names any class the update removed.

## Build

Actions → **Build PrimeSenger** → Run workflow with the link to a decrypted Messenger IPA.
**Liquid Glass** builds the glass variant.

- **Debug**: IPA with the Compatibility tools, in the `debug` draft release
- **Release** (default branch only): IPA and debs, in a draft release to publish

The version is `Version:` in `control`. Release notes are its section in `CHANGELOG.md`.

## Sideload requirements

Both files under `packaging/` are required: `Messenger.entitlements` keeps
Meta's entitlements through repackaging, and `SideloadKeychainFix.dylib`
lets keychain queries scoped to the original team identifier resolve.

## License

Proprietary. All rights reserved. See LICENSE.
