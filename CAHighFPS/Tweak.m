#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

// ---- CADynamicFrameRateSource ----

static void (*orig_CDFRS_setPaused)(id, SEL, BOOL);
static void swiz_CDFRS_setPaused(id self, SEL _cmd, BOOL arg1) {}

static BOOL (*orig_CDFRS_isPaused)(id, SEL);
static BOOL swiz_CDFRS_isPaused(id self, SEL _cmd) { return NO; }

static void (*orig_CDFRS_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void swiz_CDFRS_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;
    orig_CDFRS_setPreferredFrameRateRange(self, _cmd, range);
}

static void (*orig_CDFRS_setHighFrameRateReasons)(id, SEL, const unsigned*, unsigned long long);
static void swiz_CDFRS_setHighFrameRateReasons(id self, SEL _cmd, const unsigned* arg1, unsigned long long arg2) {}

// ---- CADisplayLink ----

static void (*orig_CDL_setPaused)(id, SEL, BOOL);
static void swiz_CDL_setPaused(id self, SEL _cmd, BOOL arg1) {}

static BOOL (*orig_CDL_isPaused)(id, SEL);
static BOOL swiz_CDL_isPaused(id self, SEL _cmd) { return NO; }

static void (*orig_CDL_setFrameInterval)(id, SEL, NSInteger);
static void swiz_CDL_setFrameInterval(id self, SEL _cmd, NSInteger interval) {
    orig_CDL_setFrameInterval(self, _cmd, 1);
    if ([self respondsToSelector:@selector(setPreferredFramesPerSecond:)])
        ((void(*)(id,SEL,NSInteger))objc_msgSend)(self, @selector(setPreferredFramesPerSecond:), 120);
}

static void (*orig_CDL_setPreferredFrameRateRange)(id, SEL, CAFrameRateRange);
static void swiz_CDL_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;
    orig_CDL_setPreferredFrameRateRange(self, _cmd, range);
}

static void (*orig_CDL_setPreferredFramesPerSecond)(id, SEL, NSInteger);
static void swiz_CDL_setPreferredFramesPerSecond(id self, SEL _cmd, NSInteger fps) {
    orig_CDL_setPreferredFramesPerSecond(self, _cmd, 120);
}

static void (*orig_CDL_setHighFrameRateReasons)(id, SEL, const unsigned*, unsigned long long);
static void swiz_CDL_setHighFrameRateReasons(id self, SEL _cmd, const unsigned* arg1, unsigned long long arg2) {}

// ---- CADisplayLink creation ----

static id (*orig_CDL_displayLinkWithTarget)(id, SEL, id, SEL);
static id swiz_CDL_displayLinkWithTarget(id self, SEL _cmd, id target, SEL selector) {
    id link = orig_CDL_displayLinkWithTarget(self, _cmd, target, selector);
    if (link) {
        CAFrameRateRange range = CAFrameRateRangeMake(120, 120, 120);
        ((void(*)(id,SEL,CAFrameRateRange))objc_msgSend)(link, @selector(setPreferredFrameRateRange:), range);
    }
    return link;
}

// ---- helpers ----

static void swizzle(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        fprintf(stderr, "[CAHighFPS] method not found: %s\n", sel_getName(sel));
        return;
    }
    *oldImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

static void applySwizzles(void) {
    Class cdfrs = objc_getClass("CADynamicFrameRateSource");
    if (cdfrs) {
        swizzle(cdfrs, @selector(setPaused:),                     (IMP)swiz_CDFRS_setPaused,                  (IMP*)&orig_CDFRS_setPaused);
        swizzle(cdfrs, @selector(isPaused),                       (IMP)swiz_CDFRS_isPaused,                   (IMP*)&orig_CDFRS_isPaused);
        swizzle(cdfrs, @selector(setPreferredFrameRateRange:),    (IMP)swiz_CDFRS_setPreferredFrameRateRange, (IMP*)&orig_CDFRS_setPreferredFrameRateRange);
        swizzle(cdfrs, @selector(setHighFrameRateReasons:count:), (IMP)swiz_CDFRS_setHighFrameRateReasons,    (IMP*)&orig_CDFRS_setHighFrameRateReasons);
    } else {
        fprintf(stderr, "[CAHighFPS] CADynamicFrameRateSource not found\n");
    }

    Class cdl = objc_getClass("CADisplayLink");
    if (cdl) {
        swizzle(cdl, @selector(setPaused:),                       (IMP)swiz_CDL_setPaused,                    (IMP*)&orig_CDL_setPaused);
        swizzle(cdl, @selector(isPaused),                         (IMP)swiz_CDL_isPaused,                     (IMP*)&orig_CDL_isPaused);
        swizzle(cdl, @selector(setFrameInterval:),                (IMP)swiz_CDL_setFrameInterval,             (IMP*)&orig_CDL_setFrameInterval);
        swizzle(cdl, @selector(setPreferredFrameRateRange:),      (IMP)swiz_CDL_setPreferredFrameRateRange,   (IMP*)&orig_CDL_setPreferredFrameRateRange);
        swizzle(cdl, @selector(setPreferredFramesPerSecond:),     (IMP)swiz_CDL_setPreferredFramesPerSecond,  (IMP*)&orig_CDL_setPreferredFramesPerSecond);
        swizzle(cdl, @selector(setHighFrameRateReasons:count:),   (IMP)swiz_CDL_setHighFrameRateReasons,      (IMP*)&orig_CDL_setHighFrameRateReasons);

        Class cdlMeta = object_getClass(cdl);
        swizzle(cdlMeta, @selector(displayLinkWithTarget:selector:), (IMP)swiz_CDL_displayLinkWithTarget, (IMP*)&orig_CDL_displayLinkWithTarget);
    } else {
        fprintf(stderr, "[CAHighFPS] CADisplayLink not found\n");
    }
}

__attribute__((constructor))
static void init() {
    fprintf(stderr, "[CAHighFPS] loaded\n");

    applySwizzles();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applySwizzles();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        applySwizzles();
    });
}
