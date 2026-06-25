export ARCHS := arm64
PACKAGE_FORMAT = ipa
TARGET := iphone:clang:latest:14.0:13.5
#TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = Geode

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Geode

ifeq ($(TROLLSTORE),1)
Geode_CODESIGN_FLAGS = -Sts-entitlements.xml
THEOS_PACKAGE_NAME=trollstore
else
Geode_CODESIGN_FLAGS = -Sentitlements.xml
endif

Geode_FILES = $(wildcard src/*.m) $(wildcard src/*.mm) $(wildcard src/views/*.m) $(wildcard src/components/*.m) $(wildcard src/LCUtils/*.m) fishhook/fishhook.c $(wildcard MSColorPicker/MSColorPicker/*.m) $(wildcard GCDWebServer/GCDWebServer/*/*.m)
Geode_FRAMEWORKS = UIKit CoreGraphics Security
#Geode_CFLAGS = -fobjc-arc -IGCDWebServer/GCDWebServer/Core -IGCDWebServer/GCDWebServer/Requests -IGCDWebServer/GCDWebServer/Responses -Wno-deprecated-declarations
Geode_CFLAGS = -fobjc-arc -IGCDWebServer/GCDWebServer/Core -IGCDWebServer/GCDWebServer/Requests -IGCDWebServer/GCDWebServer/Responses
#Geode_CCFLAGS = -std=c++20 -I./include
#Geode_CXXFLAGS = -std=c++20 -I./include 
#Geode_CCFLAGS = -std=c++17 -I./include
Geode_CXXFLAGS = -std=c++17 -I./include 
Geode_LIBRARIES = archive # thats dumb
$(APPLICATION_NAME)_LDFLAGS = -e _GeodeMain -rpath @loader_path/Frameworks
#$(APPLICATION_NAME)_LDFLAGS = -e _GeodeMain -rpath @loader_path/Frameworks -L./libs -lLIEF -lstdc++

include $(THEOS_MAKE_PATH)/application.mk
SUBPROJECTS += ZSign TweakLoader WebServerLib PlatformConsole TestJITLess EnterpriseLoader CAHighFPS
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	@echo "Copying ANGLE frameworks into launcher Frameworks folder..."
	@mkdir -p "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks"
	@rm -rf "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks/ANGLEGLKit.framework"
	@rm -rf "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks/libEGL.framework"
	@rm -rf "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks/libGLESv2.framework"
	@cp -R "Resources/GDFrameworks/ANGLEGLKit.framework" "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks/"
	@cp -R "Resources/GDFrameworks/libEGL.framework" "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks/"
	@cp -R "Resources/GDFrameworks/libGLESv2.framework" "$(THEOS_STAGING_DIR)/Applications/Geode.app/Frameworks/"

after-package::
ifeq ($(TROLLSTORE),1)
	@mv "$(THEOS_PACKAGE_DIR)/trollstore_$(THEOS_PACKAGE_BASE_VERSION).ipa" "$(THEOS_PACKAGE_DIR)/com.geode.launcher_$(THEOS_PACKAGE_BASE_VERSION).tipa"
endif

before-all::
	@sh ./download_openssl.sh

# make package FINALPACKAGE=1 STRIP=0 TROLLSTORE=1
