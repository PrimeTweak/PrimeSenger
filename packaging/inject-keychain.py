"""Links the sideload keychain fix into the app as a strong dependency.

cyan links injected dylibs weakly and strips their signature; on Messenger 584
dyld drops such a dylib before its SecItem swizzle runs, so keychain queries
scoped to the original team identifier fail at launch. Copying the dylib in
unmodified and linking it strongly keeps it loaded. Run on the app bundle
after cyan."""

import os
import shutil
import sys

import lief


def main(app, dylib):
    name = os.path.basename(dylib)
    frameworks = os.path.join(app, "Frameworks")
    os.makedirs(frameworks, exist_ok=True)
    shutil.copy2(dylib, os.path.join(frameworks, name))

    executable = os.path.join(app, os.path.splitext(os.path.basename(app))[0])
    binary = lief.parse(executable)
    binary.add_library("@rpath/" + name)
    binary.write(executable)
    print(f"linked {name} as a strong dependency")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: inject-keychain.py <App.app> <dylib>")
    main(sys.argv[1], sys.argv[2])
