ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TapLockPrefs
TapLockPrefs_FILES = ../Shared/Preferences.swift ../Shared/Applications.swift ../Sources/PrivateAPI.swift SettingsController.swift
TapLockPrefs_FRAMEWORKS = Foundation UIKit
TapLockPrefs_PRIVATE_FRAMEWORKS = Preferences
TapLockPrefs_SWIFT_VERSION = 5
TapLockPrefs_SWIFTFLAGS = -I../Interfaces
TapLockPrefs_INSTALL_PATH = /Library/PreferenceBundles
TapLockPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
