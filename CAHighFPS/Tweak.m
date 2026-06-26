#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "../src/components/LogUtils.h"

#define TARGET_FPS 120

static NSTimeInterval targetAnimationInterval(void) {
    return 1.0 / (double)TARGET_FPS;
}

static CAFrameRateRange targetFrameRateRange(void) {
    return CAFrameRateRangeMake(TARGET_FPS, TARGET_FPS, TARGET_FPS);
}

__attribute__((visibility("default")))
void CAHighFPS_TestLog(void) {
}

// ---- CADynamicFrameRateSource originals ----

static void (*orig_CDFRS_setPaused)(id, SEL, BOOL);
static BOOL (*orig_CDFRS_isPaused)(id, SEL);
static void (*orig_CDFRS_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void (*orig_CDFRS_setHighFrameRateReasons)(id, SEL, const unsigned*, unsigned long long);

// ---- CADisplayLink originals ----

static void (*orig_CDL_setPaused)(id, SEL, BOOL);
static BOOL (*orig_CDL_isPaused)(id, SEL);
static void (*orig_CDL_setFrameInterval)(id, SEL, NSInteger);
static void (*orig_CDL_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_setPreferredFramesPerSecond)(id, SEL, NSInteger);
static void (*orig_CDL_setHighFrameRateReasons)(id, SEL, const unsigned*, unsigned long long);
static id   (*orig_CDL_displayLinkWithTarget)(id, SEL, id, SEL);
static void (*orig_CDL_addToRunLoop)(id, SEL, NSRunLoop*, NSRunLoopMode);

// ---- Cocos / GD loop originals ----

static void (*orig_CCDirectorCaller_setAnimationInterval)(id, SEL, NSTimeInterval);
static NSTimeInterval (*orig_CCDirectorCaller_animationInterval)(id, SEL);
static void (*orig_CCDirectorCaller_startMainLoop)(id, SEL);

static void (*orig_CCDirector_setAnimationInterval)(id, SEL, NSTimeInterval);
static NSTimeInterval (*orig_CCDirector_animationInterval)(id, SEL);
static id (*orig_CCDirector_sharedDirector)(id, SEL);

// ---- helpers ----

static void callHighFrameRateReasonsIfAvailable(id object) {
    if (!object) return;

    SEL selector = @selector(setHighFrameRateReasons:count:);
    if (![object respondsToSelector:selector]) return;

    static const unsigned reasons[] = { 1, 2, 3 };
    ((void (*)(id, SEL, const unsigned*, unsigned long long))objc_msgSend)(object, selector, reasons, 3);
}

static void forceDisplayLink120(id link) {
    if (!link) return;

    if ([link respondsToSelector:@selector(setPaused:)] && orig_CDL_setPaused) {
        orig_CDL_setPaused(link, @selector(setPaused:), NO);
    }

    if ([link respondsToSelector:@selector(setFrameInterval:)] && orig_CDL_setFrameInterval) {
        orig_CDL_setFrameInterval(link, @selector(setFrameInterval:), 1);
    }

    if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)] && orig_CDL_setPreferredFramesPerSecond) {
        orig_CDL_setPreferredFramesPerSecond(link, @selector(setPreferredFramesPerSecond:), TARGET_FPS);
    }

    if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)] && orig_CDL_setPreferredFrameRateRange) {
        orig_CDL_setPreferredFrameRateRange(link, @selector(setPreferredFrameRateRange:), targetFrameRateRange());
    }

    callHighFrameRateReasonsIfAvailable(link);
}

static void forceDirector120(id director) {
    if (!director) return;

    if ([director respondsToSelector:@selector(setAnimationInterval:)]) {
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(director, @selector(setAnimationInterval:), targetAnimationInterval());
    }
}

static void forceSharedDirector120(void) {
    Class directorClass = objc_getClass("CCDirector");
    if (!directorClass) return;

    SEL selector = @selector(sharedDirector);
    if (![directorClass respondsToSelector:selector]) return;

    id director = ((id (*)(id, SEL))objc_msgSend)(directorClass, selector);
    forceDirector120(director);
}

// ---- CADynamicFrameRateSource hooks ----

static void swiz_CDFRS_setPaused(id self, SEL _cmd, BOOL paused) {
    if (orig_CDFRS_setPaused) {
        orig_CDFRS_setPaused(self, _cmd, NO);
    }
}

static BOOL swiz_CDFRS_isPaused(id self, SEL _cmd) {
    return NO;
}

static void swiz_CDFRS_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    if (orig_CDFRS_setPreferredFrameRateRange) {
        orig_CDFRS_setPreferredFrameRateRange(self, _cmd, targetFrameRateRange());
    }
}

static void swiz_CDFRS_setHighFrameRateReasons(id self, SEL _cmd, const unsigned* reasons, unsigned long long count) {
    if (orig_CDFRS_setHighFrameRateReasons) {
        static const unsigned forcedReasons[] = { 1, 2, 3 };
        orig_CDFRS_setHighFrameRateReasons(self, _cmd, forcedReasons, 3);
    }
}

// ---- CADisplayLink hooks ----

static void swiz_CDL_setPaused(id self, SEL _cmd, BOOL paused) {
    if (orig_CDL_setPaused) {
        orig_CDL_setPaused(self, _cmd, NO);
    }
}

static BOOL swiz_CDL_isPaused(id self, SEL _cmd) {
    return NO;
}

static void swiz_CDL_setFrameInterval(id self, SEL _cmd, NSInteger interval) {
    if (orig_CDL_setFrameInterval) {
        orig_CDL_setFrameInterval(self, _cmd, 1);
    }

    forceDisplayLink120(self);
}

static void swiz_CDL_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    if (orig_CDL_setPreferredFrameRateRange) {
        orig_CDL_setPreferredFrameRateRange(self, _cmd, targetFrameRateRange());
    }
}

static void swiz_CDL_setPreferredFramesPerSecond(id self, SEL _cmd, NSInteger fps) {
    if (orig_CDL_setPreferredFramesPerSecond) {
        orig_CDL_setPreferredFramesPerSecond(self, _cmd, TARGET_FPS);
    }
}

static void swiz_CDL_setHighFrameRateReasons(id self, SEL _cmd, const unsigned* reasons, unsigned long long count) {
    if (orig_CDL_setHighFrameRateReasons) {
        static const unsigned forcedReasons[] = { 1, 2, 3 };
        orig_CDL_setHighFrameRateReasons(self, _cmd, forcedReasons, 3);
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

// ---- Cocos / GD loop hooks ----

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
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(self, @selector(setAnimationInterval:), targetAnimationInterval());
    }

    forceSharedDirector120();
}

static void swiz_CCDirector_setAnimationInterval(id self, SEL _cmd, NSTimeInterval interval) {
    if (orig_CCDirector_setAnimationInterval) {
        orig_CCDirector_setAnimationInterval(self, _cmd, targetAnimationInterval());
    }
}

static NSTimeInterval swiz_CCDirector_animationInterval(id self, SEL _cmd) {
    return targetAnimationInterval();
}

static id swiz_CCDirector_sharedDirector(id self, SEL _cmd) {
    id director = nil;

    if (orig_CCDirector_sharedDirector) {
        director = orig_CCDirector_sharedDirector(self, _cmd);
    }

    forceDirector120(director);
    return director;
}

// ---- swizzle helpers ----

static void swizzleInstance(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    if (!cls || !sel || !newImp || !oldImp) return;

    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;

    IMP currentImp = method_getImplementation(method);
    if (currentImp == newImp) return;

    *oldImp = currentImp;
    method_setImplementation(method, newImp);
}

static void swizzleClass(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    if (!cls || !sel || !newImp || !oldImp) return;

    Class meta = object_getClass(cls);
    Method method = class_getClassMethod(cls, sel);
    if (!meta || !method) return;

    IMP currentImp = method_getImplementation(method);
    if (currentImp == newImp) return;

    *oldImp = currentImp;
    method_setImplementation(method, newImp);
}

// ---- apply hooks ----

static void applyDynamicFrameRateSourceHooks(void) {
    Class cdfrs = objc_getClass("CADynamicFrameRateSource");
    if (!cdfrs) return;

    swizzleInstance(cdfrs, @selector(setPaused:), (IMP)swiz_CDFRS_setPaused, (IMP*)&orig_CDFRS_setPaused);
    swizzleInstance(cdfrs, @selector(isPaused), (IMP)swiz_CDFRS_isPaused, (IMP*)&orig_CDFRS_isPaused);
    swizzleInstance(cdfrs, @selector(setPreferredFrameRateRange:), (IMP)swiz_CDFRS_setPreferredFrameRateRange, (IMP*)&orig_CDFRS_setPreferredFrameRateRange);
    swizzleInstance(cdfrs, @selector(setHighFrameRateReasons:count:), (IMP)swiz_CDFRS_setHighFrameRateReasons, (IMP*)&orig_CDFRS_setHighFrameRateReasons);
}

static void applyDisplayLinkHooks(void) {
    Class cdl = objc_getClass("CADisplayLink");
    if (!cdl) return;

    swizzleInstance(cdl, @selector(setPaused:), (IMP)swiz_CDL_setPaused, (IMP*)&orig_CDL_setPaused);
    swizzleInstance(cdl, @selector(isPaused), (IMP)swiz_CDL_isPaused, (IMP*)&orig_CDL_isPaused);
    swizzleInstance(cdl, @selector(setFrameInterval:), (IMP)swiz_CDL_setFrameInterval, (IMP*)&orig_CDL_setFrameInterval);
    swizzleInstance(cdl, @selector(setPreferredFrameRateRange:), (IMP)swiz_CDL_setPreferredFrameRateRange, (IMP*)&orig_CDL_setPreferredFrameRateRange);
    swizzleInstance(cdl, @selector(setPreferredFramesPerSecond:), (IMP)swiz_CDL_setPreferredFramesPerSecond, (IMP*)&orig_CDL_setPreferredFramesPerSecond);
    swizzleInstance(cdl, @selector(setHighFrameRateReasons:count:), (IMP)swiz_CDL_setHighFrameRateReasons, (IMP*)&orig_CDL_setHighFrameRateReasons);
    swizzleInstance(cdl, @selector(addToRunLoop:forMode:), (IMP)swiz_CDL_addToRunLoop, (IMP*)&orig_CDL_addToRunLoop);
    swizzleClass(cdl, @selector(displayLinkWithTarget:selector:), (IMP)swiz_CDL_displayLinkWithTarget, (IMP*)&orig_CDL_displayLinkWithTarget);
}

static void applyDirectorCallerHooks(void) {
    Class caller = objc_getClass("CCDirectorCaller");
    if (!caller) return;

    swizzleInstance(caller, @selector(setAnimationInterval:), (IMP)swiz_CCDirectorCaller_setAnimationInterval, (IMP*)&orig_CCDirectorCaller_setAnimationInterval);
    swizzleInstance(caller, @selector(animationInterval), (IMP)swiz_CCDirectorCaller_animationInterval, (IMP*)&orig_CCDirectorCaller_animationInterval);
    swizzleInstance(caller, @selector(startMainLoop), (IMP)swiz_CCDirectorCaller_startMainLoop, (IMP*)&orig_CCDirectorCaller_startMainLoop);
}

static void applyDirectorHooks(void) {
    Class director = objc_getClass("CCDirector");
    if (!director) return;

    swizzleInstance(director, @selector(setAnimationInterval:), (IMP)swiz_CCDirector_setAnimationInterval, (IMP*)&orig_CCDirector_setAnimationInterval);
    swizzleInstance(director, @selector(animationInterval), (IMP)swiz_CCDirector_animationInterval, (IMP*)&orig_CCDirector_animationInterval);
    swizzleClass(director, @selector(sharedDirector), (IMP)swiz_CCDirector_sharedDirector, (IMP*)&orig_CCDirector_sharedDirector);

    forceSharedDirector120();
}

static void applyAllHooks(void) {
    applyDynamicFrameRateSourceHooks();
    applyDisplayLinkHooks();
    applyDirectorHooks();
    applyDirectorCallerHooks();
    forceSharedDirector120();
}

__attribute__((constructor))
static void init() {
    applyAllHooks();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ applyAllHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ applyAllHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ applyAllHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ applyAllHooks(); });
}