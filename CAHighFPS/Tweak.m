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

static void forceDisplayLink120(id link, const char* reason);

// ---- original funcs ----

static void (*orig_CDL_setFrameInterval)(id, SEL, NSInteger);
static void (*orig_CDL_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_setPreferredFramesPerSecond)(id, SEL, NSInteger);
static id   (*orig_CDL_displayLinkWithTarget)(id, SEL, id, SEL);
static void (*orig_CDL_addToRunLoop)(id, SEL, NSRunLoop*, NSRunLoopMode);

static void (*orig_CDFRS_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);

static void (*orig_CCDirector_setAnimationInterval)(id, SEL, double);
static double (*orig_CCDirector_getAnimationInterval)(id, SEL);
static double (*orig_CCDirector_animationInterval)(id, SEL);

// ---- exported test ----

__attribute__((visibility("default")))
void CAHighFPS_TestLog(void) {
    logLine(@"[CAHighFPS] CAHighFPS_TestLog called from main.m");
}

// ---- helpers ----

static void forceDisplayLink120(id link, const char* reason) {
    if (!link) return;

    logLine([NSString stringWithFormat:@"[CAHighFPS] forceDisplayLink120: %s %@", reason, link]);

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

// ---- CADynamicFrameRateSource ----

static void swiz_CDFRS_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    logLine(@"[CAHighFPS] CADynamicFrameRateSource setPreferredFrameRateRange forced to 120");

    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;

    orig_CDFRS_setPreferredFrameRateRange(self, _cmd, range);
}

// ---- Cocos2d / GD frame interval ----

static void swiz_CCDirector_setAnimationInterval(id self, SEL _cmd, double interval) {
    double forced = 1.0 / TARGET_FPS;

    logLine([NSString stringWithFormat:@"[CAHighFPS] CCDirector setAnimationInterval forced from %f to %f", interval, forced]);

    if (orig_CCDirector_setAnimationInterval) {
        orig_CCDirector_setAnimationInterval(self, _cmd, forced);
    }
}

static double swiz_CCDirector_getAnimationInterval(id self, SEL _cmd) {
    logLine(@"[CAHighFPS] CCDirector getAnimationInterval forced to 1/120");
    return 1.0 / TARGET_FPS;
}

static double swiz_CCDirector_animationInterval(id self, SEL _cmd) {
    logLine(@"[CAHighFPS] CCDirector animationInterval forced to 1/120");
    return 1.0 / TARGET_FPS;
}

// ---- CADisplayLink setters ----

static void swiz_CDL_setFrameInterval(id self, SEL _cmd, NSInteger interval) {
    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink setFrameInterval forced from %ld to 1", (long)interval]);

    orig_CDL_setFrameInterval(self, _cmd, 1);
    forceDisplayLink120(self, "setFrameInterval");
}

static void swiz_CDL_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    logLine(@"[CAHighFPS] CADisplayLink setPreferredFrameRateRange forced to 120");

    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;

    orig_CDL_setPreferredFrameRateRange(self, _cmd, range);
}

static void swiz_CDL_setPreferredFramesPerSecond(id self, SEL _cmd, NSInteger fps) {
    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink setPreferredFramesPerSecond forced from %ld to 120", (long)fps]);

    orig_CDL_setPreferredFramesPerSecond(self, _cmd, TARGET_FPS);
}

// ---- CADisplayLink creation / runloop ----

static id swiz_CDL_displayLinkWithTarget(id self, SEL _cmd, id target, SEL selector) {
    id link = orig_CDL_displayLinkWithTarget(self, _cmd, target, selector);

    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink created target=%@ selector=%s link=%@", target, sel_getName(selector), link]);

    forceDisplayLink120(link, "displayLinkWithTarget");

    return link;
}

static void swiz_CDL_addToRunLoop(id self, SEL _cmd, NSRunLoop* runLoop, NSRunLoopMode mode) {
    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink addToRunLoop mode=%@", mode]);

    forceDisplayLink120(self, "before addToRunLoop");

    orig_CDL_addToRunLoop(self, _cmd, runLoop, mode);

    forceDisplayLink120(self, "after addToRunLoop");
}

// ---- swizzle helpers ----

static void swizzleInstance(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    Method m = class_getInstanceMethod(cls, sel);

    if (!m) {
        logLine([NSString stringWithFormat:@"[CAHighFPS] instance method not found: %s", sel_getName(sel)]);
        return;
    }

    IMP currentImp = method_getImplementation(m);

    if (currentImp == newImp) {
        return;
    }

    *oldImp = currentImp;
    method_setImplementation(m, newImp);

    logLine([NSString stringWithFormat:@"[CAHighFPS] swizzled instance method: %s", sel_getName(sel)]);
}

static void swizzleClass(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    Class meta = object_getClass(cls);
    Method m = class_getClassMethod(cls, sel);

    if (!m) {
        logLine([NSString stringWithFormat:@"[CAHighFPS] class method not found: %s", sel_getName(sel)]);
        return;
    }

    IMP currentImp = method_getImplementation(m);

    if (currentImp == newImp) {
        return;
    }

    *oldImp = currentImp;
    method_setImplementation(m, newImp);

    logLine([NSString stringWithFormat:@"[CAHighFPS] swizzled class method: %s on %@", sel_getName(sel), meta]);
}

static void applySwizzles(void) {
    Class cdfrs = objc_getClass("CADynamicFrameRateSource");

    if (cdfrs) {
        swizzleInstance(
            cdfrs,
            @selector(setPreferredFrameRateRange:),
            (IMP)swiz_CDFRS_setPreferredFrameRateRange,
            (IMP*)&orig_CDFRS_setPreferredFrameRateRange
        );
    } else {
        logLine(@"[CAHighFPS] CADynamicFrameRateSource not found");
    }

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
    } else {
        logLine(@"[CAHighFPS] CADisplayLink not found");
    }

    Class ccDirector = objc_getClass("CCDirector");

    if (ccDirector) {
        logLine(@"[CAHighFPS] CCDirector found");

        swizzleInstance(
            ccDirector,
            @selector(setAnimationInterval:),
            (IMP)swiz_CCDirector_setAnimationInterval,
            (IMP*)&orig_CCDirector_setAnimationInterval
        );

        swizzleInstance(
            ccDirector,
            @selector(getAnimationInterval),
            (IMP)swiz_CCDirector_getAnimationInterval,
            (IMP*)&orig_CCDirector_getAnimationInterval
        );

        swizzleInstance(
            ccDirector,
            @selector(animationInterval),
            (IMP)swiz_CCDirector_animationInterval,
            (IMP*)&orig_CCDirector_animationInterval
        );
    } else {
        logLine(@"[CAHighFPS] CCDirector not found");
    }
}

__attribute__((constructor))
static void init() {
    logLine(@"[CAHighFPS] loaded");

    applySwizzles();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        logLine(@"[CAHighFPS] reapplying swizzles after 2s");
        applySwizzles();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        logLine(@"[CAHighFPS] reapplying swizzles after 5s");
        applySwizzles();
    });
}
