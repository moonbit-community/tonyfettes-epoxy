// Demo-only: open a real window with a current GL context and pump its event
// loop. This is the window-system layer's job (a toolkit's, normally) — NOT
// epoxy's — so it lives in the demo. It is the sole reason the demo links
// Cocoa and OpenGL; epoxy itself only dlopen()s.
//
// NSOpenGLView et al. are deprecated (Apple wants Metal) but still work fine
// for a legacy 2.1 context, which is exactly what this demo draws with.

#ifdef __APPLE__

#define GL_SILENCE_DEPRECATION 1
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import <Cocoa/Cocoa.h>

static NSWindow *g_window;
static NSOpenGLContext *g_context;
static volatile int g_closed;

@interface DemoWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation DemoWindowDelegate
- (void)windowWillClose:(NSNotification *)notification {
  g_closed = 1;
}
@end

int demo_window_open(int width, int height) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSRect rect = NSMakeRect(0, 0, width, height);
    g_window = [[NSWindow alloc]
        initWithContentRect:rect
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [g_window setTitle:@"epoxy triangle"];
    [g_window setDelegate:[DemoWindowDelegate new]];
    [g_window center];

    NSOpenGLPixelFormatAttribute attrs[] = {
      NSOpenGLPFADoubleBuffer,
      NSOpenGLPFAColorSize, 24,
      0,
    };
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if (!pf) return 0;
    NSOpenGLView *view = [[NSOpenGLView alloc] initWithFrame:rect pixelFormat:pf];
    if (!view) return 0;
    [g_window setContentView:view];
    [g_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp finishLaunching];

    g_context = [view openGLContext];
    [g_context makeCurrentContext];
    return 1;
  }
}

// Present the frame the caller just drew, then pump pending events (throttled
// to ~60 fps by the wait in nextEventMatchingMask). Returns 0 once the user
// closes the window.
int demo_window_frame(void) {
  @autoreleasepool {
    [g_context flushBuffer];
    NSEvent *event;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0];
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:deadline
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES])) {
      [NSApp sendEvent:event];
      deadline = [NSDate distantPast];
    }
    return g_closed ? 0 : 1;
  }
}

#else

int demo_window_open(int width, int height) { return 0; }
int demo_window_frame(void) { return 0; }

#endif
