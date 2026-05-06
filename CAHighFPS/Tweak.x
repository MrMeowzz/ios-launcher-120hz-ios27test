// Code by Nathan
// https://github.com/verygenericname

%config(generator = internal);
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
//#import <CydiaSubstrate/CydiaSubstrate.h>

%hook CADynamicFrameRateSource

-(void)setPaused:(BOOL)arg1 {
    //
}

-(BOOL)isPaused {
    return NO;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;
    %orig;
}

-(void)setHighFrameRateReasons:(const unsigned*)arg1 count:(unsigned long long)arg2 {
    //
}

/*- (double)commitDeadline { // are these really needed?
    double vsyncInterval = 1.0 / 120.0;
    double now = CACurrentMediaTime();
    double nextVsync = ceil(now / vsyncInterval) * vsyncInterval;
    
    return nextVsync;
}

- (double)commitDeadlineAfterTimestamp:(double)arg1 { // ^
    double vsyncInterval = 1.0 / 120.0;
    double now = CACurrentMediaTime();
    double nextVsync = ceil(now / vsyncInterval) * vsyncInterval;
    
    return nextVsync;
}*/

%end

%hook CADisplayLink
-(void)setPaused:(BOOL)arg1 {
    //
}

-(BOOL)isPaused {
    return NO;
}

- (void)setFrameInterval:(NSInteger)interval {
    %orig(1);
    if ([self respondsToSelector:@selector(setPreferredFramesPerSecond:)])
        self.preferredFramesPerSecond = 120;
}

- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode {
    if ([self respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        self.preferredFramesPerSecond = 120;
    } else if (@available(iOS 15.0, *)) {
        self.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120);
    }
    %orig();
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;
    %orig;
}

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    %orig(120);
}

-(void)setHighFrameRateReasons:(const unsigned*)arg1 count:(unsigned long long)arg2 {
    //
}

%end
