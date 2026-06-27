export THEOS=./theos

ARCHS = arm64
TARGET = iphone:clang:latest:11.0
FINALPACKAGE = 1
FOR_RELEASE = 1
IGNORE_WARNING = 0
MOBILE_THEOS = 1

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = ANGLEGLKit

ANGLEGLKit_FILES = MGLContext.mm MGLDisplay.mm MGLKView.mm MGLKViewController.mm MGLLayer.mm MGLKit.m

ANGLEGLKit_PUBLIC_HEADERS = include/

ANGLEGLKit_CFLAGS = \
	-fobjc-arc \
	-fno-modules \
	-Iinclude \
	-DGL_GLEXT_PROTOTYPES \
	-DGLES_SILENCE_DEPRECATION

ANGLEGLKit_CCFLAGS = \
	-std=c++11 \
	-fno-modules

ANGLEGLKit_OBJCCFLAGS = \
	-std=c++11 \
	-fno-modules

ANGLEGLKit_FRAMEWORKS = \
	Foundation \
	UIKit \
	QuartzCore \
	CoreGraphics

ANGLEGLKit_LDFLAGS = \
	-FFrameworks \
	-framework libEGL \
	-Wl,-reexport_framework,libGLESv2 \
	-rpath @executable_path/Frameworks \
	-rpath @loader_path/../

include $(THEOS_MAKE_PATH)/framework.mk
