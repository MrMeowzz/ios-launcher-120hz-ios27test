#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
#include <GLES2/gl2.h>

const NSString* kEAGLDrawablePropertyColorFormat = @"EAGLDrawablePropertyColorFormat";
const NSString* kEAGLDrawablePropertyRetainedBacking = @"EAGLDrawablePropertyRetainedBacking";
const NSString* kEAGLColorFormatRGB565 = @"EAGLColorFormatRGB565";
const NSString* kEAGLColorFormatRGBA8 = @"EAGLColorFormatRGBA8";
const NSString* kEAGLColorFormatSRGBA8 = @"EAGLColorFormatSRGBA8";

@interface MGLContext : NSObject
@end

@interface EAGLContext : MGLContext
@end

@implementation EAGLContext
@end

@interface MGLSharegroup : NSObject
@end

@interface EAGLSharegroup : MGLSharegroup
@end

@implementation EAGLSharegroup
@end

@interface MGLLayer : NSObject
@end

@interface CAEAGLLayer : MGLLayer
@end

@interface MGLKView : NSObject
@end

@interface GLKView : MGLKView
@end

@implementation GLKView
@end

@interface MGLKViewController : NSObject
@end

@interface GLKViewController : MGLKViewController
@end

@implementation GLKViewController
@end

@implementation CAEAGLLayer(hook)

+ (Class)class
{
    return MGLLayer.class;
}

@end

typedef void (*GLGenFramebuffersProc)(GLsizei n, GLuint *framebuffers);
typedef void (*GLGenRenderbuffersProc)(GLsizei n, GLuint *renderbuffers);

static GLGenFramebuffersProc orig_glGenFramebuffers = NULL;
static GLGenRenderbuffersProc orig_glGenRenderbuffers = NULL;

static BOOL returnedDefaultFramebuffer = NO;
static BOOL returnedDefaultRenderbuffer = NO;

static void* cachedLibGLESv2Handle = NULL;

static void* openMetalANGLEGLES(void)
{
    if (cachedLibGLESv2Handle)
    {
        return cachedLibGLESv2Handle;
    }

    const char* candidates[] = {
        "@loader_path/../libGLESv2.framework/libGLESv2",
        "@rpath/libGLESv2.framework/libGLESv2",
        "@executable_path/Frameworks/libGLESv2.framework/libGLESv2",
        "libGLESv2.framework/libGLESv2",
        NULL
    };

    for (int i = 0; candidates[i] != NULL; i++)
    {
        cachedLibGLESv2Handle = dlopen(candidates[i], RTLD_NOW | RTLD_GLOBAL);

        if (cachedLibGLESv2Handle)
        {
            NSLog(@"[ANGLEGLKit] Opened libGLESv2 using %s", candidates[i]);
            return cachedLibGLESv2Handle;
        }
    }

    NSLog(@"[ANGLEGLKit] Failed to dlopen libGLESv2. Last dlerror: %s", dlerror());
    return NULL;
}

static void* resolveRealGLESSymbol(const char* name, const void* selfSymbol)
{
    void* symbol = dlsym(RTLD_NEXT, name);

    if (symbol && symbol != selfSymbol)
    {
        return symbol;
    }

    void* handle = openMetalANGLEGLES();

    if (handle)
    {
        symbol = dlsym(handle, name);

        if (symbol && symbol != selfSymbol)
        {
            return symbol;
        }
    }

    symbol = dlsym(RTLD_DEFAULT, name);

    if (symbol && symbol != selfSymbol)
    {
        return symbol;
    }

    NSLog(@"[ANGLEGLKit] Could not resolve real GLES symbol: %s", name);
    return NULL;
}

void glGenFramebuffers(GLsizei n, GLuint *framebuffers)
{
    if (!framebuffers || n <= 0)
    {
        return;
    }

    if (!returnedDefaultFramebuffer)
    {
        returnedDefaultFramebuffer = YES;

        for (GLsizei i = 0; i < n; i++)
        {
            framebuffers[i] = 0;
        }

        NSLog(@"[ANGLEGLKit] Returned default framebuffer 0 for first glGenFramebuffers call.");
        return;
    }

    if (!orig_glGenFramebuffers)
    {
        orig_glGenFramebuffers =
            (GLGenFramebuffersProc)resolveRealGLESSymbol("glGenFramebuffers", (const void*)&glGenFramebuffers);
    }

    if (orig_glGenFramebuffers)
    {
        orig_glGenFramebuffers(n, framebuffers);
        return;
    }

    for (GLsizei i = 0; i < n; i++)
    {
        framebuffers[i] = 0;
    }

    NSLog(@"[ANGLEGLKit] WARNING: glGenFramebuffers real function missing; returned 0 to avoid NULL crash.");
}

void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers)
{
    if (!renderbuffers || n <= 0)
    {
        return;
    }

    if (!returnedDefaultRenderbuffer)
    {
        returnedDefaultRenderbuffer = YES;

        for (GLsizei i = 0; i < n; i++)
        {
            renderbuffers[i] = 0;
        }

        NSLog(@"[ANGLEGLKit] Returned default renderbuffer 0 for first glGenRenderbuffers call.");
        return;
    }

    if (!orig_glGenRenderbuffers)
    {
        orig_glGenRenderbuffers =
            (GLGenRenderbuffersProc)resolveRealGLESSymbol("glGenRenderbuffers", (const void*)&glGenRenderbuffers);
    }

    if (orig_glGenRenderbuffers)
    {
        orig_glGenRenderbuffers(n, renderbuffers);
        return;
    }

    for (GLsizei i = 0; i < n; i++)
    {
        renderbuffers[i] = 0;
    }

    NSLog(@"[ANGLEGLKit] WARNING: glGenRenderbuffers real function missing; returned 0 to avoid NULL crash.");
}