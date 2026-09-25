"""Sets UIDesignRequiresCompatibility to false in an app's Info.plist.
Messenger ships it true, which keeps the legacy design; UIKit reads it once at
launch, so it can only change while the bundle is packaged. Nothing else moves."""

import plistlib
import sys

KEY = "UIDesignRequiresCompatibility"


def main(path):
    with open(path, "rb") as handle:
        info = plistlib.load(handle)

    before = info.get(KEY, "(absent)")
    info[KEY] = False

    with open(path, "wb") as handle:
        plistlib.dump(info, handle)

    print(f"{KEY}: {before} -> False")
    print(f"{len(info)} keys preserved")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: set-liquid-glass.py <Info.plist>")
    main(sys.argv[1])
