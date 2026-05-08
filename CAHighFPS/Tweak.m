#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static void (*orig_setPreferredFrameRateRange)(id self, SEL _cmd, CAFrameRateRange range);

static void swizzled_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    CAFrameRateRange newRange = CAFrameRateRangeMake(60, 120, 120);
    orig_setPreferredFrameRateRange(self, _cmd, newRange);
}

__attribute__((constructor))
static void init() {
    Class cls = objc_getClass("CADisplayLink");
    SEL sel = @selector(setPreferredFrameRateRange:);
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        orig_setPreferredFrameRateRange = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swizzled_setPreferredFrameRateRange);
    }
}
