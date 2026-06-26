#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "../src/components/LogUtils.h"

#define TARGET_FPS 120

static NSTimeInterval targetAnimationInterval(void) {
    return 1.0 / (double)TARGET_FPS;
}

// Keep this symbol because main.m calls it with dlsym.
// No debug spam.
__attribute__((visibility("default")))
void CAHighFPS_TestLog(void) {
}

// ---- CADisplayLink originals ----

static void (*orig_CDL_setFrameInterval)(id, SEL, NSInteger);
static void (*orig_CDL_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_setPreferredFramesPerSecond)(id, SEL, NSInteger);
static id   (*orig_CDL_displayLinkWithTarget)(id, SEL, id, SEL);
static void (*orig_CDL_addToRunLoop)(id, SEL, NSRunLoop*, NSRunLoopMode);

// ---- CCDirectorCaller originals ----

static void (*orig_CCDirectorCaller_setAnimationInterval)(id, SEL, NSTimeInterval);
static NSTimeInterval (*orig_CCDirectorCaller_animationInterval)(id, SEL);
static void (*orig_CCDirectorCaller_startMainLoop)(id, SEL);

// ---- helpers ----

static void forceDisplayLink120(id link) {
    if (!link) {
        return;
    }

    if ([link respondsToSelector:@selector(setFrameInterval:)] && orig_CDL_setFrameInterval) {
        orig_CDL_setFrameInterval(link, @selector(setFrameInterval:), 1);
    }

    if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)] && orig_CDL_setPreferredFramesPerSecond) {
        orig_CDL_setPreferredFramesPerSecond(link, @selector(setPreferredFramesPerSecond:), TARGET_FPS);
    }

    if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)] && orig_CDL_setPreferredFrameRateRange) {
        CAFrameRateRange range = CAFrameRateRangeMake(TARGET_FPS, TARGET_FPS, TARGET_FPS);
        orig_CDL_setPreferredFrameRateRange(link, @selector(setPreferredFrameRateRange:), range);
    }
}

// ---- CADisplayLink hooks ----

static void swiz_CDL_setFrameInterval(id self, SEL _cmd, NSInteger interval) {
    if (orig_CDL_setFrameInterval) {
        orig_CDL_setFrameInterval(self, _cmd, 1);
    }
}

static void swiz_CDL_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;

    if (orig_CDL_setPreferredFrameRateRange) {
        orig_CDL_setPreferredFrameRateRange(self, _cmd, range);
    }
}

static void swiz_CDL_setPreferredFramesPerSecond(id self, SEL _cmd, NSInteger fps) {
    if (orig_CDL_setPreferredFramesPerSecond) {
        orig_CDL_setPreferredFramesPerSecond(self, _cmd, TARGET_FPS);
    }
}

static id swiz_CDL_displayLinkWithTarget(id self, SEL _cmd, id target, SEL selector) {
    id link = nil;

    if (orig_CDL_displayLinkWithTarget) {
        link = orig_CDL_displayLinkWithTarget(self, _cmd, target, selector);
    }

    forceDisplayLink120(link);

    return link;
}

static void swiz_CDL_addToRunLoop(id self, SEL _cmd, NSRunLoop* runLoop, NSRunLoopMode mode) {
    forceDisplayLink120(self);

    if (orig_CDL_addToRunLoop) {
        orig_CDL_addToRunLoop(self, _cmd, runLoop, mode);
    }

    forceDisplayLink120(self);
}

// ---- CCDirectorCaller game-side interval hooks ----

static void swiz_CCDirectorCaller_setAnimationInterval(id self, SEL _cmd, NSTimeInterval interval) {
    if (orig_CCDirectorCaller_setAnimationInterval) {
        orig_CCDirectorCaller_setAnimationInterval(self, _cmd, targetAnimationInterval());
    }
}

static NSTimeInterval swiz_CCDirectorCaller_animationInterval(id self, SEL _cmd) {
    return targetAnimationInterval();
}

static void swiz_CCDirectorCaller_startMainLoop(id self, SEL _cmd) {
    if (orig_CCDirectorCaller_startMainLoop) {
        orig_CCDirectorCaller_startMainLoop(self, _cmd);
    }

    if ([self respondsToSelector:@selector(setAnimationInterval:)]) {
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(
            self,
            @selector(setAnimationInterval:),
            targetAnimationInterval()
        );
    }
}

// ---- swizzle helpers ----

static void swizzleInstance(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    if (!cls || !sel || !newImp || !oldImp) {
        return;
    }

    Method method = class_getInstanceMethod(cls, sel);

    if (!method) {
        return;
    }

    IMP currentImp = method_getImplementation(method);

    if (currentImp == newImp) {
        return;
    }

    *oldImp = currentImp;
    method_setImplementation(method, newImp);
}

static void swizzleClass(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    if (!cls || !sel || !newImp || !oldImp) {
        return;
    }

    Method method = class_getClassMethod(cls, sel);

    if (!method) {
        return;
    }

    IMP currentImp = method_getImplementation(method);

    if (currentImp == newImp) {
        return;
    }

    *oldImp = currentImp;
    method_setImplementation(method, newImp);
}

// ---- apply hooks ----

static void applyDisplayLinkHooks(void) {
    Class cdl = objc_getClass("CADisplayLink");

    if (!cdl) {
        return;
    }

    swizzleInstance(
        cdl,
        @selector(setFrameInterval:),
        (IMP)swiz_CDL_setFrameInterval,
        (IMP*)&orig_CDL_setFrameInterval
    );

    swizzleInstance(
        cdl,
        @selector(setPreferredFrameRateRange:),
        (IMP)swiz_CDL_setPreferredFrameRateRange,
        (IMP*)&orig_CDL_setPreferredFrameRateRange
    );

    swizzleInstance(
        cdl,
        @selector(setPreferredFramesPerSecond:),
        (IMP)swiz_CDL_setPreferredFramesPerSecond,
        (IMP*)&orig_CDL_setPreferredFramesPerSecond
    );

    swizzleInstance(
        cdl,
        @selector(addToRunLoop:forMode:),
        (IMP)swiz_CDL_addToRunLoop,
        (IMP*)&orig_CDL_addToRunLoop
    );

    swizzleClass(
        cdl,
        @selector(displayLinkWithTarget:selector:),
        (IMP)swiz_CDL_displayLinkWithTarget,
        (IMP*)&orig_CDL_displayLinkWithTarget
    );
}

static void applyDirectorCallerHooks(void) {
    Class caller = objc_getClass("CCDirectorCaller");

    if (!caller) {
        return;
    }

    swizzleInstance(
        caller,
        @selector(setAnimationInterval:),
        (IMP)swiz_CCDirectorCaller_setAnimationInterval,
        (IMP*)&orig_CCDirectorCaller_setAnimationInterval
    );

    swizzleInstance(
        caller,
        @selector(animationInterval),
        (IMP)swiz_CCDirectorCaller_animationInterval,
        (IMP*)&orig_CCDirectorCaller_animationInterval
    );

    swizzleInstance(
        caller,
        @selector(startMainLoop),
        (IMP)swiz_CCDirectorCaller_startMainLoop,
        (IMP*)&orig_CCDirectorCaller_startMainLoop
    );
}

static void applyAllHooks(void) {
    applyDisplayLinkHooks();
    applyDirectorCallerHooks();
}

__attribute__((constructor))
static void init() {
    applyAllHooks();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applyAllHooks();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applyAllHooks();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applyAllHooks();
    });
}