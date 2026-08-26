TARGET := iphone:clang:16.5:15.1
# The host app and its frameworks are arm64 only. Shipping an extra
# slice leaves on-device signers with a slice they may not cover.
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Messenger

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrimeSenger

PrimeSenger_FILES = Tweak.x $(wildcard Sources/*.x) $(wildcard Sources/*.m)
PrimeSenger_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations
PrimeSenger_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
