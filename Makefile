ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TapLock
TapLock_FILES = Shared/Preferences.swift Sources/PrivateAPI.swift Sources/LockAction.swift Sources/HomeDoubleTap.swift Sources/Tweak.x.swift
TapLock_FRAMEWORKS = Foundation UIKit
TapLock_SWIFT_VERSION = 5

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
