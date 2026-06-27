//
// Copyright 2019 Le Hoang Quyen. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//

- (void)initImpl
{
}

- (void)deallocImpl
{
    [self pause];
}

- (void)viewDidMoveToWindow
{
}

- (void)viewDidLoad
{
    NSLog(@"MGLKViewController viewDidLoad");
    [super viewDidLoad];
}

- (NSInteger)effectivePreferredFramesPerSecond
{
    NSInteger preferred = _preferredFramesPerSecond;

#if TARGET_OS_IOS || TARGET_OS_TV
    NSInteger screenMax = UIScreen.mainScreen.maximumFramesPerSecond;

    if (screenMax <= 0)
    {
        screenMax = 60;
    }

    if (preferred <= 1)
    {
        preferred = screenMax;
    }

    if (preferred > screenMax)
    {
        preferred = screenMax;
    }

    if (preferred <= 0)
    {
        preferred = 60;
    }
#else
    if (preferred <= 1)
    {
        preferred = 60;
    }
#endif

    return preferred;
}

- (void)applyPreferredFrameRateToDisplayLink
{
    if (!_displayLink)
    {
        return;
    }

    NSInteger fps = [self effectivePreferredFramesPerSecond];

#if TARGET_OS_IOS || TARGET_OS_TV
    if (@available(iOS 15.0, tvOS 15.0, *))
    {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
        NSLog(@"MGLKViewController preferredFrameRateRange forced to %ld", (long)fps);
    }
#endif

    _displayLink.preferredFramesPerSecond = fps;
    NSLog(@"MGLKViewController preferredFramesPerSecond set to %ld", (long)fps);
}

- (void)setPreferredFramesPerSecond:(NSInteger)preferredFramesPerSecond
{
    _preferredFramesPerSecond = preferredFramesPerSecond;

    if (_displayLink)
    {
        [self applyPreferredFrameRateToDisplayLink];
    }

    [self pause];
    [self resume];
}

- (void)pause
{
    if (_paused)
    {
        return;
    }

    NSLog(@"MGLKViewController pause");

    if (_displayLink)
    {
        [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        _displayLink = nil;
    }

    _paused = YES;
}

- (void)resume
{
    if (!_paused)
    {
        return;
    }

    NSLog(@"MGLKViewController resume");

    if (!_glView)
    {
        return;
    }

    if (!_displayLink)
    {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameStep)];
        [self applyPreferredFrameRateToDisplayLink];
    }

    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    _paused = NO;
}