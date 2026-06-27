//
// Copyright 2019 Le Hoang Quyen. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//

#import "MGLDisplay.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglext_angle.h>
#include <EGL/eglplatform.h>

#ifndef EGL_PLATFORM_ANGLE_ANGLE
#define EGL_PLATFORM_ANGLE_ANGLE 0x3202
#endif

#ifndef EGL_PLATFORM_ANGLE_TYPE_ANGLE
#define EGL_PLATFORM_ANGLE_TYPE_ANGLE 0x3203
#endif

#ifndef EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE
#define EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE 0x3489
#endif

#ifndef EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE
#define EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE 0x3209
#endif

#ifndef EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE
#define EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE 0x320A
#endif

namespace
{
void Throw(NSString *msg)
{
    [NSException raise:@"MGLSurfaceException" format:@"%@", msg];
}

static void LogEGLError(NSString *prefix)
{
    EGLint error = eglGetError();
    NSLog(@"[ANGLEGLKit] %@ EGL error: 0x%04x", prefix, error);
}

static EGLDisplay CreateMetalANGLEDisplay()
{
    EGLDisplay display = EGL_NO_DISPLAY;

    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplayEXT =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");

    const EGLint extAttribs[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,
        EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
        EGL_NONE
    };

    if (getPlatformDisplayEXT)
    {
        display = getPlatformDisplayEXT(
            EGL_PLATFORM_ANGLE_ANGLE,
            (void *)0,
            extAttribs
        );

        if (display != EGL_NO_DISPLAY)
        {
            NSLog(@"[ANGLEGLKit] Created EGL display using eglGetPlatformDisplayEXT + MetalANGLE.");
            return display;
        }

        LogEGLError(@"eglGetPlatformDisplayEXT failed");
    }
    else
    {
        NSLog(@"[ANGLEGLKit] eglGetPlatformDisplayEXT is missing.");
    }

#if EGL_VERSION_1_5
    const EGLAttrib attribs15[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,
        EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
        EGL_NONE
    };

    display = eglGetPlatformDisplay(
        EGL_PLATFORM_ANGLE_ANGLE,
        (void *)0,
        attribs15
    );

    if (display != EGL_NO_DISPLAY)
    {
        NSLog(@"[ANGLEGLKit] Created EGL display using eglGetPlatformDisplay + MetalANGLE.");
        return display;
    }

    LogEGLError(@"eglGetPlatformDisplay failed");
#endif

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);

    if (display != EGL_NO_DISPLAY)
    {
        NSLog(@"[ANGLEGLKit] Created EGL display using fallback eglGetDisplay.");
        return display;
    }

    LogEGLError(@"eglGetDisplay failed");
    return EGL_NO_DISPLAY;
}
}

@interface EGLDisplayHolder : NSObject
@property(nonatomic, assign) EGLDisplay eglDisplay;
@end

@implementation EGLDisplayHolder

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _eglDisplay = CreateMetalANGLEDisplay();

        if (_eglDisplay == EGL_NO_DISPLAY)
        {
            Throw(@"Failed to create EGL display");
        }

        EGLint major = 0;
        EGLint minor = 0;

        if (!eglInitialize(_eglDisplay, &major, &minor))
        {
            LogEGLError(@"eglInitialize failed");
            Throw(@"Failed to call eglInitialize()");
        }

        NSLog(@"[ANGLEGLKit] EGL initialized successfully: %d.%d", major, minor);
    }

    return self;
}

- (void)dealloc
{
    if (_eglDisplay != EGL_NO_DISPLAY)
    {
        eglTerminate(_eglDisplay);
        _eglDisplay = EGL_NO_DISPLAY;
    }
}

@end

static EGLDisplayHolder *gGlobalDisplayHolder = nil;
static MGLDisplay *gDefaultDisplay = nil;

@interface MGLDisplay ()
@end

@implementation MGLDisplay

+ (MGLDisplay *)defaultDisplay
{
    @synchronized(self)
    {
        if (!gDefaultDisplay)
        {
            gDefaultDisplay = [[MGLDisplay alloc] init];
        }

        return gDefaultDisplay;
    }
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        @synchronized([MGLDisplay class])
        {
            if (!gGlobalDisplayHolder)
            {
                gGlobalDisplayHolder = [[EGLDisplayHolder alloc] init];
            }

            _eglDisplay = gGlobalDisplayHolder.eglDisplay;
        }

        if (_eglDisplay == EGL_NO_DISPLAY)
        {
            Throw(@"MGLDisplay received EGL_NO_DISPLAY");
        }
    }

    return self;
}

@end
