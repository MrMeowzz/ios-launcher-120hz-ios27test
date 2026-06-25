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
static void forceDisplayLink120Silent(id link);

// ---- original funcs ----

static void (*orig_CDL_setFrameInterval)(id, SEL, NSInteger);
static void (*orig_CDL_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_setPreferredFramesPerSecond)(id, SEL, NSInteger);
static id   (*orig_CDL_displayLinkWithTarget)(id, SEL, id, SEL);
static void (*orig_CDL_addToRunLoop)(id, SEL, NSRunLoop*, NSRunLoopMode);

static void (*orig_CDFRS_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);

static void (*orig_CCDirectorCaller_doCaller)(id, SEL, id);

// ---- tick counter ----

static CFTimeInterval lastCallerLogTime = 0;
static int callerTickCount = 0;

// ---- exported test ----

__attribute__((visibility("default")))
void CAHighFPS_TestLog(void) {
    logLine(@"[CAHighFPS] CAHighFPS_TestLog called from main.m");
}

// ---- helpers ----

static void forceDisplayLink120Silent(id link) {
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

static void forceDisplayLink120(id link, const char* reason) {
    if (!link) return;

    logLine([NSString stringWithFormat:@"[CAHighFPS] forceDisplayLink120: %s %@", reason, link]);
    forceDisplayLink120Silent(link);
}

// ---- CADynamicFrameRateSource ----

static void swiz_CDFRS_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    logLine(@"[CAHighFPS] CADynamicFrameRateSource setPreferredFrameRateRange forced to 120");

    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;

    if (orig_CDFRS_setPreferredFrameRateRange) {
        orig_CDFRS_setPreferredFrameRateRange(self, _cmd, range);
    }
}

// ---- CCDirectorCaller ----
// This is the real Cocos object your log showed:
// target=<CCDirectorCaller ...> selector=doCaller:

static void swiz_CCDirectorCaller_doCaller(id self, SEL _cmd, id sender) {
    callerTickCount++;

    CFTimeInterval now = CACurrentMediaTime();

    if (lastCallerLogTime == 0) {
        lastCallerLogTime = now;
    }

    if (now - lastCallerLogTime >= 1.0) {
        logLine([NSString stringWithFormat:@"[CAHighFPS] CCDirectorCaller doCaller ticks/sec = %d", callerTickCount]);
        callerTickCount = 0;
        lastCallerLogTime = now;
    }

    // sender should be the CADisplayLink. Keep it forced, but do not spam logs every frame.
    forceDisplayLink120Silent(sender);

    if (orig_CCDirectorCaller_doCaller) {
        orig_CCDirectorCaller_doCaller(self, _cmd, sender);
    }
}

// ---- CADisplayLink setters ----

static void swiz_CDL_setFrameInterval(id self, SEL _cmd, NSInteger interval) {
    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink setFrameInterval forced from %ld to 1", (long)interval]);

    if (orig_CDL_setFrameInterval) {
        orig_CDL_setFrameInterval(self, _cmd, 1);
    }

    forceDisplayLink120(self, "setFrameInterval");
}

static void swiz_CDL_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    logLine(@"[CAHighFPS] CADisplayLink setPreferredFrameRateRange forced to 120");

    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;

    if (orig_CDL_setPreferredFrameRateRange) {
        orig_CDL_setPreferredFrameRateRange(self, _cmd, range);
    }
}

static void swiz_CDL_setPreferredFramesPerSecond(id self, SEL _cmd, NSInteger fps) {
    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink setPreferredFramesPerSecond forced from %ld to 120", (long)fps]);

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

    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink created target=%@ selector=%s link=%@", target, sel_getName(selector), link]);

    forceDisplayLink120(link, "displayLinkWithTarget");

    return link;
}

static void swiz_CDL_addToRunLoop(id self, SEL _cmd, NSRunLoop* runLoop, NSRunLoopMode mode) {
    logLine([NSString stringWithFormat:@"[CAHighFPS] CADisplayLink addToRunLoop mode=%@", mode]);

    forceDisplayLink120(self, "before addToRunLoop");

    if (orig_CDL_addToRunLoop) {
        orig_CDL_addToRunLoop(self, _cmd, runLoop, mode);
    }

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

    Class ccDirectorCaller = objc_getClass("CCDirectorCaller");

    if (ccDirectorCaller) {
        logLine(@"[CAHighFPS] CCDirectorCaller found");

        swizzleInstance(
            ccDirectorCaller,
            @selector(doCaller:),
            (IMP)swiz_CCDirectorCaller_doCaller,
            (IMP*)&orig_CCDirectorCaller_doCaller
        );
    } else {
        logLine(@"[CAHighFPS] CCDirectorCaller not found");
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