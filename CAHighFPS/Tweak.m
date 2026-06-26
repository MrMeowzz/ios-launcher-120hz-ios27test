#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "../src/components/LogUtils.h"

#define TARGET_FPS 120

static void logLine(NSString* line) {
    AppLog(@"%@", line);
    NSLog(@"%@", line);
    fprintf(stderr, "%s\n", line.UTF8String);
}

static NSTimeInterval targetAnimationInterval(void) {
    return 1.0 / (double)TARGET_FPS;
}

static void forceDisplayLink120(id link);
static void applyGameFPSBypass(void);

// ---- original funcs ----

static void (*orig_CDL_setFrameInterval)(id, SEL, NSInteger);
static void (*orig_CDL_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_setPreferredFramesPerSecond)(id, SEL, NSInteger);
static id   (*orig_CDL_displayLinkWithTarget)(id, SEL, id, SEL);
static void (*orig_CDL_addToRunLoop)(id, SEL, NSRunLoop*, NSRunLoopMode);

static void (*orig_CCDirector_setAnimationInterval)(id, SEL, NSTimeInterval);
static NSTimeInterval (*orig_CCDirector_animationInterval)(id, SEL);

// ---- exported test ----

__attribute__((visibility("default")))
void CAHighFPS_TestLog(void) {
    logLine(@"[CAHighFPS] CAHighFPS_TestLog called from main.m");
}

// ---- helpers ----

static void forceDisplayLink120(id link) {
    if (!link) return;

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

// ---- CADisplayLink setters ----

static void swiz_CDL_setFrameInterval(id self, SEL _cmd, NSInteger interval) {
    if (orig_CDL_setFrameInterval) {
        orig_CDL_setFrameInterval(self, _cmd, 1);
    }

    forceDisplayLink120(self);
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

// ---- CADisplayLink creation / runloop ----

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

// ---- CCDirector game-side FPS bypass ----

static void forceDirectorAnimationInterval(void) {
    Class directorClass = objc_getClass("CCDirector");

    if (!directorClass) {
        return;
    }

    id director = nil;

    if ([directorClass respondsToSelector:@selector(sharedDirector)]) {
        director = ((id (*)(id, SEL))objc_msgSend)(directorClass, @selector(sharedDirector));
    }

    if (!director) {
        return;
    }

    if ([director respondsToSelector:@selector(setAnimationInterval:)]) {
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(
            director,
            @selector(setAnimationInterval:),
            targetAnimationInterval()
        );
    }
}

static void swiz_CCDirector_setAnimationInterval(id self, SEL _cmd, NSTimeInterval interval) {
    if (orig_CCDirector_setAnimationInterval) {
        orig_CCDirector_setAnimationInterval(self, _cmd, targetAnimationInterval());
    }
}

static NSTimeInterval swiz_CCDirector_animationInterval(id self, SEL _cmd) {
    return targetAnimationInterval();
}

static void applyGameFPSBypass(void) {
    Class directorClass = objc_getClass("CCDirector");

    if (!directorClass) {
        return;
    }

    Method setIntervalMethod = class_getInstanceMethod(directorClass, @selector(setAnimationInterval:));

    if (setIntervalMethod) {
        IMP currentImp = method_getImplementation(setIntervalMethod);

        if (currentImp != (IMP)swiz_CCDirector_setAnimationInterval) {
            orig_CCDirector_setAnimationInterval = (void (*)(id, SEL, NSTimeInterval))currentImp;
            method_setImplementation(setIntervalMethod, (IMP)swiz_CCDirector_setAnimationInterval);
        }
    }

    Method getIntervalMethod = class_getInstanceMethod(directorClass, @selector(animationInterval));

    if (getIntervalMethod) {
        IMP currentImp = method_getImplementation(getIntervalMethod);

        if (currentImp != (IMP)swiz_CCDirector_animationInterval) {
            orig_CCDirector_animationInterval = (NSTimeInterval (*)(id, SEL))currentImp;
            method_setImplementation(getIntervalMethod, (IMP)swiz_CCDirector_animationInterval);
        }
    }

    forceDirectorAnimationInterval();
}

// ---- swizzle helpers ----

static void swizzleInstance(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    Method m = class_getInstanceMethod(cls, sel);

    if (!m) {
        return;
    }

    IMP currentImp = method_getImplementation(m);

    if (currentImp == newImp) {
        return;
    }

    *oldImp = currentImp;
    method_setImplementation(m, newImp);
}

static void swizzleClass(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    Method m = class_getClassMethod(cls, sel);

    if (!m) {
        return;
    }

    IMP currentImp = method_getImplementation(m);

    if (currentImp == newImp) {
        return;
    }

    *oldImp = currentImp;
    method_setImplementation(m, newImp);
}

static void applySwizzles(void) {
    Class cdl = objc_getClass("CADisplayLink");

    if (cdl) {
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

    applyGameFPSBypass();
}

__attribute__((constructor))
static void init() {
    applySwizzles();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applySwizzles();
        applyGameFPSBypass();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applySwizzles();
        applyGameFPSBypass();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applySwizzles();
        applyGameFPSBypass();
    });
}