TARGET := iphone:clang:16.5:15.1
# The host app and its frameworks are arm64 only. Shipping an extra
# slice leaves on-device signers with a slice they may not cover.
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Messenger

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrimeSenger

# fleXD is cloned by the workflow into vendor/FLEX, so its 441 files never
# enter this repository. Classes/Headers is excluded, as its podspec does.
FLEX_ROOT = vendor/FLEX/Classes
FLEX_DIRS = $(shell find $(FLEX_ROOT) -type d -not -path '*/Headers*' 2>/dev/null)
FLEX_SOURCES = $(shell find $(FLEX_ROOT) \( -name '*.m' -o -name '*.mm' \) \
                 -not -path '*/Headers/*' 2>/dev/null)

PrimeSenger_FILES = Tweak.x $(wildcard Sources/*.x) $(wildcard Sources/*.m) \
                    $(FLEX_SOURCES)
PrimeSenger_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations \
                     $(addprefix -I,$(FLEX_DIRS)) \
                     -Wno-unsupported-availability-guard -Wno-strict-prototypes \
                     -Wno-unused-function -Wno-nullability-completeness
PrimeSenger_CXXFLAGS = -std=gnu++11
PrimeSenger_FRAMEWORKS = UIKit Foundation CoreGraphics ImageIO QuartzCore \
                         WebKit Security SceneKit QuickLook
PrimeSenger_LIBRARIES = z sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk
