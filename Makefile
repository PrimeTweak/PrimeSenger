TARGET := iphone:clang:16.5:15.1
# The host app and its frameworks are arm64 only. Shipping an extra
# slice leaves on-device signers with a slice they may not cover.
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Messenger

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrimeSenger

# fleXD is fetched here rather than by the workflow: .github is hidden in
# Finder and has been left behind before, which would silently produce a
# build with no explorer in it. Pinned by tag so a build that worked keeps
# working.
FLEX_TAG = 6.1.0
FLEX_ROOT = vendor/FLEX/Classes
FLEX_FETCH := $(shell test -d $(FLEX_ROOT) || git clone --quiet --depth 1 \
                --branch $(FLEX_TAG) https://github.com/TimOliver/fleXD.git \
                vendor/FLEX 2>&1)
FLEX_DIRS = $(shell find $(FLEX_ROOT) -type d -not -path '*/Headers*' 2>/dev/null)
FLEX_SOURCES = $(shell find $(FLEX_ROOT) \( -name '*.m' -o -name '*.mm' \) \
                 -not -path '*/Headers/*' 2>/dev/null)
FLEX_COUNT = $(words $(FLEX_SOURCES))

PrimeSenger_FILES = Tweak.x $(wildcard Sources/*.x) $(wildcard Sources/*.m) \
                    $(FLEX_SOURCES)
PrimeSenger_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations \
                     $(addprefix -I,$(FLEX_DIRS)) \
                     -Wno-unsupported-availability-guard -Wno-strict-prototypes \
                     -Wno-unused-function -Wno-nullability-completeness \
                     -Wno-unused-property-ivar \
                     -DPSG_FLEX_SOURCES=$(FLEX_COUNT)

# fleXD builds cleanly under its own settings, which do not use -Werror.
# Theos does, so any warning in its 182 sources stops the build, and they
# would surface one at a time. Warnings still appear in the log; they just
# no longer abort. This applies to this project's own sources too, so the
# build log is worth reading rather than only its exit code.
PrimeSenger_CFLAGS += -Wno-error
PrimeSenger_CXXFLAGS = -std=gnu++11 -Wno-error
PrimeSenger_FRAMEWORKS = UIKit Foundation CoreGraphics ImageIO QuartzCore \
                         WebKit Security SceneKit QuickLook
PrimeSenger_LIBRARIES = z sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

# Lets the workflow print what this file actually sees, rather than what it
# is assumed to see: make print-FLEX_SOURCES
print-%: ; @echo '$*=$($*)'
