"""Sets UIDesignRequiresCompatibility to false in an app's Info.plist.

Messenger ships the key set to true, which makes UIKit fall back to the
legacy material even when UIGlassEffect is requested explicitly. The key is
read once at launch, before any tweak code runs, so it can only be changed
while the bundle is being packaged.

Only that one key is touched: the plist is read, the value replaced, and the
file written back, so nothing else in it can be lost.
"""

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
