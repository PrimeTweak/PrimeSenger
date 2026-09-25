# fleXD 6.1.0 needs the iOS 26 SDK. Xcode carries it, but Theos only looks
# in its own sdks directory, so it is linked there from this file, which
# always travels with the sources.
SDK_LINK := $(shell \
    if command -v xcrun >/dev/null 2>&1; then \
        mkdir -p "$(THEOS)/sdks"; \
        ln -sfn "$$(xcrun --sdk iphoneos --show-sdk-path)" \
                "$(THEOS)/sdks/iPhoneOS$$(xcrun --sdk iphoneos --show-sdk-version).sdk"; \
    fi 2>&1)

# latest picks the newest SDK Theos can see. The deployment target stays
# 15.1, so the tweak still runs on older systems.
TARGET := iphone:clang:latest:15.1
$(info SDK link: $(if $(SDK_LINK),$(SDK_LINK),done))
# The host app and its frameworks are arm64 only. Shipping an extra
# slice leaves on-device signers with a slice they may not cover.
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Messenger

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrimeSenger

# fleXD is fetched here, next to the sources, and pinned by tag so a build
# that worked keeps working.
FLEX_TAG = 6.1.0
FLEX_ROOT = vendor/FLEX/Classes
FLEX_FETCH := $(shell test -d $(FLEX_ROOT) || git clone --quiet --depth 1 \
                --branch $(FLEX_TAG) https://github.com/TimOliver/fleXD.git \
                vendor/FLEX 2>&1)
FLEX_DIRS = $(shell find $(FLEX_ROOT) -type d -not -path '*/Headers*' 2>/dev/null)
FLEX_SOURCES = $(shell find $(FLEX_ROOT) \( -name '*.m' -o -name '*.mm' \) \
                 -not -path '*/Headers/*' 2>/dev/null)

# PRIME_DEBUG=1 builds Debug, with the Compatibility report; a plain make
# builds Release.
PRIME_DEBUG ?= 0
PRIMESENGER_VERSION := $(shell grep '^Version:' control | cut -d' ' -f2)

PrimeSenger_FILES = $(shell find src -name '*.x' -o -name '*.xm' -o -name '*.m' -o -name '*.mm' -o -name '*.c') \
                    $(FLEX_SOURCES)
PrimeSenger_CFLAGS = -fobjc-arc $(addprefix -I,$(wildcard include) $(shell find src -type d)) \
                     -Wno-deprecated-declarations \
                     $(addprefix -I,$(FLEX_DIRS)) \
                     -Wno-unsupported-availability-guard -Wno-strict-prototypes \
                     -Wno-unused-function -Wno-nullability-completeness \
                     -Wno-unused-property-ivar \
                     -DPRIMESENGER_DEBUG=$(PRIME_DEBUG) \
                     -DPRIMESENGER_VERSION=\"$(PRIMESENGER_VERSION)\"

# Theos builds with -Werror, which fleXD's 182 sources are not written for.
# Warnings stay in the log without stopping the build, for this project's
# sources too, so the log is worth reading.
PrimeSenger_CFLAGS += -Wno-error
PrimeSenger_CXXFLAGS = -std=gnu++11 -Wno-error
PrimeSenger_FRAMEWORKS = UIKit Foundation CoreGraphics ImageIO QuartzCore \
                         WebKit Security SceneKit QuickLook
PrimeSenger_LIBRARIES = z sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

# Lets the workflow print what this file actually sees, rather than what it
# is assumed to see: make print-FLEX_SOURCES
print-%: ; @echo '$*=$($*)'
