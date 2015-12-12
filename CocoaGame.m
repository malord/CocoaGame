//
// CocoaGame2
// Copyright (c) 2007-2012 Mark H. P. Lord. All rights reserved.
//
// Ideas:
// - use the field editor to fully support UNICODE character input (e.g., Alt+E to accent the next character)
// - multi-screen support
// - prevent click-through
//

#include "CocoaGame.h"
#import <Cocoa/Cocoa.h>
#include <sys/time.h>

//
// Compile-time options
//

// If you get "queue full" in your Console, increase this. Or your frame rate.
#define COCOAGAME_MAX_QUEUED_EVENTS 64

//
// Compatibility
//

#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	typedef int CocoaGame_Int;
	typedef unsigned int CocoaGame_UInt;
	typedef float CocoaGame_Float;
#else
	typedef NSInteger CocoaGame_Int;
	typedef NSUInteger CocoaGame_UInt;
	typedef CGFloat CocoaGame_Float;
#endif

//
// Interfaces
//

@interface NSWindow (CocoaGameAdditions)

- (BOOL)cocoaGame_IsFullScreen;

@end

@interface CocoaGame_Window : NSWindow
@end

#if defined(MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
@interface CocoaGame_Delegate : NSObject <NSWindowDelegate>
#else
@interface CocoaGame_Delegate : NSObject
#endif

- (BOOL)windowShouldClose:(id)sender;

- (void)applicationDidBecomeActive:(NSNotification *)aNotification;
- (void)applicationWillResignActive:(NSNotification *)aNotification;
- (void)applicationDidResignActive:(NSNotification *)aNotification;
- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification;

@end

@interface CocoaGame_View : NSView {
	NSCursor *invisibleCursor;
}

- (void)globalFrameDidChange:(NSNotification *)aNotification;

@end

//
// Globals
//

const CocoaGame_VideoConfig COCOAGAME_VIDEOCONFIG_DEFAULTS = { 
	.disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW, 
	.mode = {
		.width = 800, 
		.height = 600, 
		.bits = 32
	},
	.title = NULL, 
	.acceptClosestMode = FALSE, 
	.captureDisplay = TRUE,
	.enableWindowResizing = TRUE,
	.fullScreenWindowLevel = COCOAGAME_WINDOWLEVEL_DEFAULT,
	.useLionFullScreenSupport = TRUE,
};
	
const CocoaGame_GLConfig COCOAGAME_GLCONFIG_DEFAULTS = { 
	.colourBits = 24, 
	.depthBits = 24, 
	.alphaBits = 8, 
	.stencilBits = 8, 
	.msaa = 4, 
	.swapInterval = 1 
};

//
// Private functions
//

#define countof(arr) (sizeof(arr) / sizeof((arr)[0]))

static void CocoaGame_DefaultTraceHandler(const char *format, va_list argptr);
static void CocoaGame_FormatAndAppendNewline(char *buf, size_t bufsize, const char *format, va_list argptr);

static void CocoaGame_DefaultAbortWithMessageHandler(const char *title, const char *format, va_list argptr);

static void CocoaGame_GetVideoModeFromDictionary(NSDictionary *dict, CocoaGame_VideoMode *mode);

static CocoaGame_Bool CocoaGame_CreateDelegate(void);
static void CocoaGame_DestroyDelegate(void);

/// You should call CocoaGame_FadeFromBlack() after calling this, as it will fade out if in a non-windowed mode.
static void CocoaGame_ShutdownVideo(void);

static CocoaGame_Bool CocoaGame_InitVideoFullScreenSetMode(const CocoaGame_VideoConfig *config, CocoaGame_Bool setMode);
static CocoaGame_Bool CocoaGame_InitVideoWindow(const CocoaGame_VideoConfig *config, CocoaGame_View *reuseView);
static CocoaGame_Bool CocoaGame_InitVideoFullScreenWindow(const CocoaGame_VideoConfig *config, CocoaGame_View *reuseView);

static CocoaGame_Bool CocoaGame_CreateFullScreenWindow(CocoaGame_Int level, CocoaGame_Bool hidesOnDeactivate, CocoaGame_View *reuseView);
static void CocoaGame_DestroyWindow(void);
static CocoaGame_Int CocoaGame_WindowLevelToNSWindowLevel(CocoaGame_WindowLevel level);

static void CocoaGame_ReadViewDimensions(int *width, int *height);
static CGRect CocoaGame_GetDisplayBoundsInNSWindowCoordinateSpace(void);

static NSOpenGLContext *CocoaGame_CreateOpenGLContext(const CocoaGame_GLConfig *config, CocoaGame_GLConfig *actualConfig);
static CocoaGame_Bool CocoaGame_ReadGLConfig(NSOpenGLContext *context, NSOpenGLPixelFormat *pixelFormat, CocoaGame_GLConfig *config);
static BOOL CocoaGame_UpdateOpenGLContext(void);

static CocoaGame_Bool CocoaGame_PollOne(void);
static void CocoaGame_UpdateModifiers(unsigned long cocoaModifierFlags);

static BOOL CocoaGame_UpdateMousePosition(NSEvent *event);
static void CocoaGame_QueueMouseMoveEvent(NSEvent *event);
static CocoaGame_Bool CocoaGame_MouseMoveHasDelta(NSEvent *event);
static void CocoaGame_UpdateMousePositionOutsideOfEventStream(void);
static void CocoaGame_InternalSetMouseDeltaMode(CocoaGame_Bool deltaMode);
static void CocoaGame_InternalSetMouseCursorVisible(CocoaGame_Bool cursorVisible);
static void CocoaGame_WarpMouseCursorToCentreOfView(void);
static void CocoaGame_ImplementDefaultMouseMode(void);
static void CocoaGame_ImplementAppMouseMode(void);

static void CocoaGame_SetupModifiersEvent(CocoaGame_ModifiersEvent *event);
static void CocoaGame_SetupMousePositionEvent(CocoaGame_MousePositionEvent *mousePositionEvent);
static void CocoaGame_SetupMouseMoveEvent(NSEvent *event, CocoaGame_MouseMoveEvent *mouseMove);
static void CocoaGame_NSEventToMouseButtonEvent(NSEvent *event, CocoaGame_MouseButtonEvent *buttonEvent);
static void CocoaGame_QueueKeyAndCharacterEvents(NSEvent *event);
static void CocoaGame_QueueKeyEvent(NSEvent *event);
static void CocoaGame_QueueCharEvent(NSEvent *event);
static CocoaGame_Bool CocoaGame_IsFunctionKey(unsigned long unicode);

// Returns TRUE if the key should not be passed to the application.
static CocoaGame_Bool CocoaGame_CheckForSpecialKeys(NSEvent *event);

#ifdef COCOAGAME_ENABLE_PBUFFERS
static NSOpenGLPixelFormat *CocoaGame_CreatePixelFormatForPixelBuffer(const CocoaGame_GLConfig *config);
#endif

//
// Private data
//

static CocoaGame_Bool traceEnabled = TRUE;
static CocoaGame_TraceHandler traceHandler = &CocoaGame_DefaultTraceHandler;
static CocoaGame_AbortWithMessageHandler abortWithMessageHandler = &CocoaGame_DefaultAbortWithMessageHandler;

static CocoaGame_Bool isInitialised = FALSE;

static CGDirectDisplayID whichDisplay;
static NSDictionary *originalMode;

static int videoModeCount;
static CocoaGame_VideoMode *videoModes;

static CocoaGame_Delegate *delegate;

static CocoaGame_Event queue[COCOAGAME_MAX_QUEUED_EVENTS];
static int queueRead = 0;
static int queueWrite = 0;

static CocoaGame_Bool enableAltEsc = TRUE;
static CocoaGame_Bool shouldQuit;
static unsigned int modifiers;

static NSPoint mousePosition;
static BOOL mouseIsInView;

static CGDisplayFadeReservationToken fadeToken = kCGDisplayFadeReservationInvalidToken;
static float fadeTime = 1.0f / 3.0f;

static CocoaGame_VideoConfig videoConfig = { 
	.disposition = COCOAGAME_VIDEO_NONE, 
	.mode = {
		.width = 0, 
		.height = 0, 
		.bits = 0
	},
	.title = NULL, 
	.acceptClosestMode = FALSE, 
	.captureDisplay = FALSE,
	.enableWindowResizing = FALSE
};

typedef struct CocoaGame_VideoDispositionTraits {
	CocoaGame_Bool shouldFade;
	CocoaGame_Bool acquiresDisplays;
	CocoaGame_Bool hidesMenuBar;
	CocoaGame_Bool rendersToView;
	CocoaGame_Bool hideGlobalCursor;
} CocoaGame_VideoDispositionTraits;

static const CocoaGame_VideoDispositionTraits videoTraits[COCOAGAME_VIDEO__MAX_DISPOSITION] = {
	// None
	{
		.shouldFade = FALSE,
		.acquiresDisplays = FALSE,
		.hidesMenuBar = FALSE,
		.rendersToView = FALSE,
		.hideGlobalCursor = FALSE,
	},
	
	// Window
	{
		.shouldFade = FALSE,
		.acquiresDisplays = FALSE,
		.hidesMenuBar = FALSE,
		.rendersToView = TRUE,
		.hideGlobalCursor = FALSE,
	},
	
	// Fullscreen
	{
		.shouldFade = TRUE,
		.acquiresDisplays = TRUE,
		.hidesMenuBar = TRUE,
		.rendersToView = FALSE,
		.hideGlobalCursor = TRUE,
	},
	
	// Fullscreen set-mode
	{
		.shouldFade = TRUE,
		.acquiresDisplays = TRUE,
		.hidesMenuBar = TRUE,
		.rendersToView = FALSE,
		.hideGlobalCursor = TRUE,
	},
	
	// Fullscreen window
	{
		.shouldFade = FALSE,
		.acquiresDisplays = FALSE,
		.hidesMenuBar = TRUE,
		.rendersToView = TRUE,
		.hideGlobalCursor = TRUE, // 10.4 needs this to be TRUE.
	},
};

#define CocoaGame_GetVideoTraits() (&videoTraits[videoConfig.disposition])

static int windowWidth, windowHeight;

static CocoaGame_Window *window;
static CocoaGame_View *view;

static volatile CocoaGame_Bool windowIsTogglingFullScreen;

static NSOpenGLContext *openGLContext;
static CocoaGame_Bool openGLUpdateRequired;

static CocoaGame_GLConfig glConfig;

static CocoaGame_Bool wantKeyRepeats = TRUE;

static CocoaGame_Bool wantMouseDeltaMode = FALSE;
static CocoaGame_Bool wantMouseCursorVisible = TRUE;

static CocoaGame_Bool viewCursorHidden = FALSE;
static CocoaGame_Bool nsCursorHidden = FALSE;

static void (*drawCallback)(void *);
static void *drawCallbackContext;

static CocoaGame_Bool discardedRender = FALSE;

//
// Implementation
//

static void CocoaGame_DefaultTraceHandler(const char *format, va_list argptr)
{
	char buf[1024];
	CocoaGame_FormatAndAppendNewline(buf, sizeof(buf), format, argptr);

	fputs(buf, stderr);
}

void CocoaGame_Trace(const char *format, ...)
{
	va_list argptr;
	va_start(argptr, format);

	if (traceEnabled)
		traceHandler(format, argptr);
	
	va_end(argptr);
}

void CocoaGame_SetTraceEnabled(CocoaGame_Bool newTraceEnabled)
{
	traceEnabled = newTraceEnabled;
}

void CocoaGame_SetTraceHandler(CocoaGame_TraceHandler handler)
{
	traceHandler = handler ? handler : &CocoaGame_DefaultTraceHandler;
}

CocoaGame_TraceHandler CocoaGame_GetTraceHandler(void)
{
	return traceHandler;
}

static void CocoaGame_FormatAndAppendNewline(char *buf, size_t bufsize, const char *format, va_list argptr)
{
	vsnprintf(buf, bufsize - 1, format, argptr);

	if (buf[0] && buf[strlen(buf) - 1] != '\n')
		strcat(buf, "\n");
}

void CocoaGame_CreateAutoreleasePool(void **pool)
{
	*pool = [[NSAutoreleasePool alloc] init];
}

void CocoaGame_FreeAutoreleasePool(void *pool)
{
	[(NSAutoreleasePool *) pool drain];
}

void CocoaGame_SetAltEscEnabled(CocoaGame_Bool newEnableAltEsc)
{
	enableAltEsc = newEnableAltEsc;
}

CocoaGame_GLInfo *CocoaGame_GetGLInfo2(const CocoaGame_GLConfig *fakeConfig)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	CocoaGame_GLInfo *info;
	NSOpenGLContext *tempContext = nil;
	
	if (! openGLContext) {
		NSOpenGLPixelFormatAttribute attribs[40];
		unsigned int attribCount = 0;

		attribs[attribCount++] = NSOpenGLPFAAccelerated;
		attribs[attribCount++] = NSOpenGLPFADoubleBuffer;
		attribs[attribCount++] = NSOpenGLPFANoRecovery;

		attribs[attribCount++] = NSOpenGLPFAFullScreen;
		attribs[attribCount++] = NSOpenGLPFAScreenMask;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) CGDisplayIDToOpenGLDisplayMask(whichDisplay);

		attribs[attribCount++] = NSOpenGLPFAColorSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) fakeConfig->colourBits;
		attribs[attribCount++] = NSOpenGLPFAAlphaSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) fakeConfig->alphaBits;
		attribs[attribCount++] = NSOpenGLPFADepthSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) fakeConfig->depthBits;
		attribs[attribCount++] = NSOpenGLPFAStencilSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) fakeConfig->stencilBits;

		// Terminate the attributes.
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) 0;
		
		NSCAssert(attribCount <= countof(attribs), @"Overflowed attribs array");

		NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];

		if (! pixelFormat) {
			[pool drain];
			return NULL;
		}

		tempContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
		[pixelFormat release];
		
		if (! tempContext) {
			[pool drain];
			return NULL;
		}
		
		[tempContext makeCurrentContext];
		[tempContext setFullScreen];
	}
	
	info = calloc(1, sizeof(CocoaGame_GLInfo));
	info->version = strdup((const char *) glGetString(GL_VERSION));
	info->extensions = strdup((const char *) glGetString(GL_EXTENSIONS));
	info->renderer = strdup((const char *) glGetString(GL_RENDERER));
	info->vendor = strdup((const char *) glGetString(GL_VENDOR));
	
	if (tempContext) {
		if ([NSOpenGLContext currentContext] == tempContext) 
			[NSOpenGLContext clearCurrentContext];
			
		[tempContext clearDrawable];
		[tempContext release];
	}
	
	[pool drain];
	return info;
}

CocoaGame_GLInfo *CocoaGame_GetGLInfo(void)
{
	return CocoaGame_GetGLInfo2(&COCOAGAME_GLCONFIG_DEFAULTS);
}

void CocoaGame_FreeGLInfo(CocoaGame_GLInfo *info)
{
	free(info->version);
	free(info->extensions);
	free(info->vendor);
	free(info->renderer);
	free(info);
}

CocoaGame_Bool CocoaGame_Init(void)
{
	NSCAssert(! isInitialised, @"CocoaGame already initialised.");
	
	whichDisplay = kCGDirectMainDisplay;
	
	originalMode = [(NSDictionary *) CGDisplayCurrentMode(whichDisplay) copy];
	NSCAssert(originalMode, @"Couldn't get original display mode.");
	if (! originalMode)
		return FALSE;
	
	if (! CocoaGame_BuildModeList())
		return FALSE;
	
	isInitialised = TRUE;
	shouldQuit = FALSE;
	queueRead = queueWrite = 0;
	modifiers = 0; // force an event for any modifiers
	videoConfig.disposition = COCOAGAME_VIDEO_NONE;
	
	window = nil;
	view = nil;
	delegate = nil;
	openGLContext = nil;
	openGLUpdateRequired = FALSE;

	if (! CocoaGame_CreateDelegate())
		return FALSE;

	CocoaGame_Trace("%s: initialisation complete.\n", __FUNCTION__);
	return TRUE;
}

static int CocoaGame_VideoModeCompare(const void *va, const void *vb)
{
	const CocoaGame_VideoMode *a = (const CocoaGame_VideoMode *) va;
	const CocoaGame_VideoMode *b = (const CocoaGame_VideoMode *) vb;
	
	if (a->bits > b->bits)
		return -1;
		
	if (a->bits < b->bits)
		return 1;
	
	if (a->width > b->width)
		return -1;
		
	if (a->width < b->width)
		return 1;
		
	if (a->height > b->height)
		return -1;
		
	if (a->height < b->height)
		return 1;
		
	return 0;
}

CocoaGame_Bool CocoaGame_BuildModeList(void)
{
	// Owned by the system - don't release.
	NSArray *modeList = (NSArray *) CGDisplayAvailableModes(whichDisplay);
	
	videoModes = realloc(videoModes, [modeList count] * sizeof(CocoaGame_VideoMode));
	videoModeCount = (int) [modeList count];
	
	int i;
	for (i = 0; i != videoModeCount; ++i) {
		// Owned by the system - don't release.
		NSDictionary *mode = (NSDictionary *) [modeList objectAtIndex:i];
		
		CocoaGame_GetVideoModeFromDictionary(mode, &videoModes[i]);
	}
	
	qsort(videoModes, videoModeCount, sizeof(*videoModes), &CocoaGame_VideoModeCompare);
	
	CocoaGame_VideoMode *out = videoModes;
	const CocoaGame_VideoMode *in = videoModes;
	const CocoaGame_VideoMode *inEnd = videoModes + videoModeCount;
	
	*out++ = *in++;
	
	for (; in != inEnd; ++in) {
		if (! CocoaGame_VideoModesEqual(in - 1, in))
			*out++ = *in;
	}
	
	int newVideoModeCount = (int) (out - videoModes);
	
	CocoaGame_Trace("%s: %d video modes (%d duplicates removed).\n", __FUNCTION__, newVideoModeCount, videoModeCount - newVideoModeCount);
	videoModeCount = newVideoModeCount;
	
	videoModes = realloc(videoModes, videoModeCount * sizeof(CocoaGame_VideoMode));
	
	return TRUE;
}

static void CocoaGame_GetVideoModeFromDictionary(NSDictionary *dict, CocoaGame_VideoMode *mode)
{
	mode->width = [[dict objectForKey:(id) kCGDisplayWidth] intValue];
	mode->height = [[dict objectForKey:(id) kCGDisplayHeight] intValue];
	mode->bits = [[dict objectForKey:(id) kCGDisplayBitsPerPixel] intValue];
}

CocoaGame_Bool CocoaGame_VideoModesEqual(const CocoaGame_VideoMode *a, const CocoaGame_VideoMode *b)
{
	return a->width == b->width && a->height == b->height && a->bits == b->bits;
}

BOOL CocoaGame_ParseVideoMode(const char *str, CocoaGame_VideoMode *videoMode)
{
	videoMode->bits = 32;
	if (sscanf(str, "%dx%dx%d", &videoMode->width, &videoMode->height, &videoMode->bits) < 2)
		return NO;
		
	if (videoMode->width < 1 || videoMode->height < 1)
		return NO;
		
	if (videoMode->bits < 16)
		return NO;
		
	return YES;
}

int CocoaGame_GetVideoModeCount(void)
{
	return videoModeCount;
}

const CocoaGame_VideoMode *CocoaGame_GetVideoMode(int modeNumber)
{
	NSCAssert(modeNumber >= 0 && modeNumber < videoModeCount, @"Invalid mode number");
	
	return &videoModes[modeNumber];	   
}

void CocoaGame_Shutdown(void)
{
	if (! isInitialised)
		return;
	
	CocoaGame_ShutdownVideo();
	CocoaGame_FadeFromBlack();
	
	free(videoModes);
	videoModes = NULL;
	videoModeCount = 0;

	CocoaGame_DestroyDelegate();
	
	isInitialised = FALSE;

	CocoaGame_Trace("%s: shutdown complete.\n", __FUNCTION__);
}

void CocoaGame_AbortWithMessage(const char *title, const char *format, ...)
{
	va_list argptr;
	va_start(argptr, format);
	CocoaGame_AbortWithMessageVA(title, format, argptr);
	va_end(argptr);
}

void CocoaGame_AbortWithMessageVA(const char *title, const char *format, va_list argptr)
{
	(*abortWithMessageHandler)(title, format, argptr);
}

static void CocoaGame_DefaultAbortWithMessageHandler(const char *title, const char *format, va_list argptr)
{
	char buf[1024];
	vsnprintf(buf, sizeof(buf), format, argptr);
	buf[sizeof(buf) - 1] = 0;
	
	CocoaGame_Shutdown();
	NSRunAlertPanel([NSString stringWithUTF8String:title], @"%@", NSLocalizedString(@"Quit", @""), nil, nil, [NSString stringWithUTF8String:buf]);
	
	exit(1);
}

void CocoaGame_SetAbortWithMessageHandler(CocoaGame_AbortWithMessageHandler handler)
{
	abortWithMessageHandler = handler;
}

static void CocoaGame_ShutdownVideo(void)
{
	// CocoaGame_Shutdown should have checked this
	NSCAssert(isInitialised, @"");

	// Destroying a window while it's in the process of toggling fullscreen is bad.
	while (windowIsTogglingFullScreen) 
		CocoaGame_Poll();

	if (CocoaGame_GetVideoTraits()->shouldFade)
		CocoaGame_FadeToBlack();
		
	CocoaGame_ImplementDefaultMouseMode();

	if (openGLContext) {
		CocoaGame_Trace("%s: shutting down OpenGL...\n", __FUNCTION__);

		if ([NSOpenGLContext currentContext] == openGLContext) 
			[NSOpenGLContext clearCurrentContext];
			
		[openGLContext clearDrawable];
		[openGLContext release];
		openGLContext = nil;
	}
	
	if (CocoaGame_GetVideoTraits()->acquiresDisplays) {
		CocoaGame_Trace("%s: releasing displays...\n", __FUNCTION__);
		CGReleaseAllDisplays();
		CGRestorePermanentDisplayConfiguration();
	}
	
	if (CocoaGame_GetVideoTraits()->hidesMenuBar) {
		CocoaGame_Trace("%s: restoring menu bar...\n", __FUNCTION__);
		[NSMenu setMenuBarVisible:YES];
	}
	
	if (window) {
		CocoaGame_Trace("%s: destroying window...\n", __FUNCTION__);
		CocoaGame_DestroyWindow();
	}
	
	videoConfig.disposition = COCOAGAME_VIDEO_NONE;
}

static CocoaGame_Bool CocoaGame_CreateWindowAndView(CocoaGame_Float width, CocoaGame_Float height, CocoaGame_UInt styleMask, CocoaGame_Bool useLionFullScreenSupport, CocoaGame_View *reuseView)
{
	CocoaGame_DestroyWindow();
		
	CocoaGame_Trace("%s: creating window...\n", __FUNCTION__);
	window = [[CocoaGame_Window alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
												styleMask:styleMask
												  backing:NSBackingStoreBuffered
													defer:NO];
													
	if (! window) {
		NSLog(@"%s: unable to create window.", __FUNCTION__);
		return FALSE;
	}

	if (useLionFullScreenSupport && [window respondsToSelector:@selector(toggleFullScreen:)])
		[window setCollectionBehavior:[window collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];

	#ifdef MAC_OS_X_VERSION_10_6
		[window setDelegate:(id <NSWindowDelegate>) delegate];
	#else
		[window setDelegate:delegate];
	#endif
	// NSCAssert([delegate retainCount] == 1, @""); // The window doesn't retain its delegate.
	
	if (! reuseView) {
		view = [[CocoaGame_View alloc] initWithFrame:[window contentRectForFrameRect:[window frame]]];
		if (! view) {
			NSLog(@"%s: unable to create view.", __FUNCTION__);
			CocoaGame_DestroyWindow();
			return FALSE;
		}
	} else {
		view = [reuseView retain];
		[view setFrame:[window contentRectForFrameRect:[window frame]]];
	}
		
	[window setContentView:view];
	[view release];

	[window setBackgroundColor:[NSColor blackColor]];
	[window setAcceptsMouseMovedEvents:YES];
	[window setReleasedWhenClosed:NO];
	
	return TRUE;
}

static CocoaGame_Bool CocoaGame_CreateDelegate(void)
{
	if (! delegate) {
		delegate = [[CocoaGame_Delegate alloc] init];
		if (! delegate) {
			NSLog(@"%s: unable to create delegate.", __FUNCTION__);
			return FALSE;
		}
	}
	
	return TRUE;
}

static void CocoaGame_DestroyWindow(void)
{
	[window close];
	[window release];
	window = nil;
	view = nil;
}

static void CocoaGame_DestroyDelegate(void)
{
	[window setDelegate:nil];
	[delegate release];
	delegate = nil;
}

void CocoaGame_GetStartupVideoMode(CocoaGame_VideoMode *mode)
{
	CocoaGame_GetVideoModeFromDictionary(originalMode, mode);
}

float CocoaGame_GetStartupAspectRatio(void)
{
	CocoaGame_VideoMode mode;
	CocoaGame_GetStartupVideoMode(&mode);
	
	return (float) mode.width / (float) mode.height;
}

CocoaGame_Bool CocoaGame_InitVideo(const CocoaGame_VideoConfig *config)
{
	NSCAssert(isInitialised, @"");
	NSCAssert((int) config->disposition > COCOAGAME_VIDEO_NONE && (int) config->disposition < (int) COCOAGAME_VIDEO__MAX_DISPOSITION, @"Invalid video disposition.");
	
	if (videoConfig.disposition != COCOAGAME_VIDEO_NONE) {
		// This may or may not fade the screen.
		CocoaGame_ShutdownVideo();
	}
	
	// This is particularly important when using the Lion fullscreen support. If you need to disable it for some
	// reason, disable it only if config->useLionFullScreenSupport is FALSE.
	[NSApp activateIgnoringOtherApps:YES];
	
	videoConfig = *config;

	// Remember these values for CocoaGame_ToggleFullScreenWindow().
	windowWidth = config->mode.width;
	windowHeight = config->mode.height;

	// The InitVideo function must set these.
	videoConfig.disposition = COCOAGAME_VIDEO_NONE; 
	videoConfig.mode.width = 0;
	videoConfig.mode.height = 0;
	videoConfig.mode.bits = 0;
	videoConfig.captureDisplay = FALSE;
	
	CocoaGame_Bool result;
	
	if (videoTraits[config->disposition].shouldFade)
		CocoaGame_FadeToBlack();

	switch (config->disposition) {
		case COCOAGAME_VIDEO_FULLSCREEN:
			result = CocoaGame_InitVideoFullScreenSetMode(config, FALSE);
			break;
			
		case COCOAGAME_VIDEO_FULLSCREEN_SET_MODE:
			result = CocoaGame_InitVideoFullScreenSetMode(config, TRUE);
			break;
			
		case COCOAGAME_VIDEO_FULLSCREEN_WINDOW:
			result = CocoaGame_InitVideoFullScreenWindow(config, nil);
			break;
			
		case COCOAGAME_VIDEO_WINDOW:
			result = CocoaGame_InitVideoWindow(config, nil);
			break;
			
		default:
			result = FALSE;
			break;
	}
	
	if ([NSApp isActive]) 
		CocoaGame_ImplementAppMouseMode();

	CocoaGame_UpdateMousePositionOutsideOfEventStream();
	
	CocoaGame_FadeFromBlack();
	
	return result;
}

void CocoaGame_FadeToBlack(void)
{
	if (fadeToken == kCGDisplayFadeReservationInvalidToken) {
		if (CGAcquireDisplayFadeReservation(5, &fadeToken) == kCGErrorSuccess)
			CGDisplayFade(fadeToken, fadeTime, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, TRUE);
		else
			fadeToken = kCGDisplayFadeReservationInvalidToken;
	}
}

void CocoaGame_FadeFromBlack(void)
{
	if (fadeToken != kCGDisplayFadeReservationInvalidToken) {
		CGDisplayFade(fadeToken, fadeTime, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, FALSE);
		CGReleaseDisplayFadeReservation(fadeToken);

		fadeToken = kCGDisplayFadeReservationInvalidToken;
	}
}

void CocoaGame_SetFadeTime(float newFadeTime)
{
	fadeTime = newFadeTime;
}

const CocoaGame_VideoConfig *CocoaGame_GetVideoConfig(void)
{
	return &videoConfig;
}

float CocoaGame_GetAspectRatio(void)
{
	return (float) CocoaGame_GetVideoConfig()->mode.width / (float) CocoaGame_GetVideoConfig()->mode.height;
}

static CocoaGame_Bool CocoaGame_InitVideoFullScreenSetMode(const CocoaGame_VideoConfig *config, CocoaGame_Bool setMode)
{
	// Capture all video
	videoConfig.captureDisplay = config->captureDisplay;
	CocoaGame_Trace("%s: capturing displays...\n", __FUNCTION__);
	if (config->captureDisplay && CGCaptureAllDisplays() != kCGErrorSuccess) {
		NSLog(@"%s: unable to capture display.", __FUNCTION__);
		videoConfig.captureDisplay = FALSE;
		return FALSE;
	}
	
	if (setMode) {
		// Find the matching video mode
		CocoaGame_Trace("%s: finding best match for mode %dx%dx%d...\n", __FUNCTION__, config->mode.width, config->mode.height, config->mode.bits);
		boolean_t exactMatch = 0;
		NSDictionary *bestMode = (NSDictionary *) CGDisplayBestModeForParameters(whichDisplay, config->mode.bits, config->mode.width, config->mode.height, &exactMatch);
		if (! bestMode || (! config->acceptClosestMode && ! exactMatch)) {
			NSLog(@"%s: unable to find match for mode.\n", __FUNCTION__);
			CGReleaseAllDisplays();
			return FALSE;
		}
	
		CocoaGame_VideoMode mode;
		CocoaGame_GetVideoModeFromDictionary(bestMode, &mode);
	
		CocoaGame_Trace("%s: setting mode %dx%dx%d...\n", __FUNCTION__, mode.width, mode.height, mode.bits);
		if (CGDisplaySwitchToMode(whichDisplay, (CFDictionaryRef) bestMode) != CGDisplayNoErr) {
			NSLog(@"%s: unable to set video mode %dx%dx%d.\n", __FUNCTION__, mode.width, mode.height, mode.bits);
			CGReleaseAllDisplays();
			return FALSE;
		}
	}
	
	CocoaGame_GetVideoModeFromDictionary((NSDictionary *) CGDisplayCurrentMode(whichDisplay), &videoConfig.mode);

	// We don't render to the window, but it's useful for other things (e.g., setting the cursor)
	if (! CocoaGame_CreateFullScreenWindow(CGShieldingWindowLevel(), FALSE, nil))
		return FALSE;
		
	int actualWindowWidth, actualWindowHeight;
	CocoaGame_ReadViewDimensions(&actualWindowWidth, &actualWindowHeight);
	NSCAssert(actualWindowWidth == videoConfig.mode.width && actualWindowHeight == videoConfig.mode.height,
		@"CocoaGame_InitVideoFullScreen: window bounds don't match screen!");

	videoConfig.disposition = setMode ? COCOAGAME_VIDEO_FULLSCREEN_SET_MODE : COCOAGAME_VIDEO_FULLSCREEN;

	CocoaGame_Trace("%s: full-screen video initialised.\n", __FUNCTION__);
	return TRUE;
}

static CocoaGame_Bool CocoaGame_CreateFullScreenWindow(CocoaGame_Int level, CocoaGame_Bool hidesOnDeactivate, CocoaGame_View *reuseView)
{
	// Set the size of the window using the display bounds returned by CGDisplayBounds (which we have to convert
	// in to Cocoa's coordinate system). i.e., this code works even if the mode hasn't been changed.
	CGRect auxScreenRect = CocoaGame_GetDisplayBoundsInNSWindowCoordinateSpace();
	
	// Create a window.
	if (! CocoaGame_CreateWindowAndView(auxScreenRect.size.width, auxScreenRect.size.height, NSBorderlessWindowMask, FALSE, reuseView))
		return FALSE;

	// Necessary if we're launched from the Console, or after a Mac security warning box.
	[NSApp activateIgnoringOtherApps:YES];
		
	// [window setContentSize:NSMakeSize(auxScreenRect.size.width, auxScreenRect.size.height)];
	[window setFrameOrigin:NSMakePoint(auxScreenRect.origin.x, auxScreenRect.origin.y)];
	[window setLevel:level];
	[window makeKeyAndOrderFront:nil];
	[window setHidesOnDeactivate:hidesOnDeactivate ? YES : NO];

	[NSMenu setMenuBarVisible:NO];
	
	return TRUE;
}

void CocoaGame_ToggleFullScreenWindow(void)
{
	NSCAssert(isInitialised, @"");
	NSCAssert(videoConfig.disposition == COCOAGAME_VIDEO_FULLSCREEN_WINDOW || videoConfig.disposition == COCOAGAME_VIDEO_WINDOW, 
		@"CocoaGame_ToggleFullScreenWindow only available in window or full-screen-window video setup.");
		
	if (videoConfig.useLionFullScreenSupport && [window respondsToSelector:@selector(toggleFullScreen:)]) {
		[window toggleFullScreen:nil];
		return;
	}
	
	CocoaGame_ImplementDefaultMouseMode();
	
	CocoaGame_View *reuseView = view;
	[reuseView retain];
	
	[window setContentView:nil];
	view = nil;

	CocoaGame_Trace("%s: destroying window...\n", __FUNCTION__);
	CocoaGame_DestroyWindow();
	
	CocoaGame_Bool result;
	
	if (videoConfig.disposition == COCOAGAME_VIDEO_FULLSCREEN_WINDOW) {
		// Go windowed
		CocoaGame_VideoConfig newConfig = videoConfig;
		newConfig.disposition = COCOAGAME_VIDEO_WINDOW;
		newConfig.mode.width = windowWidth;
		newConfig.mode.height = windowHeight;
		result = CocoaGame_InitVideoWindow(&newConfig, reuseView);
		[NSMenu setMenuBarVisible:YES];
	} else {
		// Go full screen
		CocoaGame_VideoConfig newConfig = videoConfig;
		newConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW;
		result = CocoaGame_InitVideoFullScreenWindow(&newConfig, reuseView);
		// The menu bar will have been hidden by CocoaGame_InitVideoFullScreenWindow.
	}
	
	NSCAssert(result, @"Failed to toggle full-screen/window.");
	
	[reuseView release];

	CocoaGame_ImplementAppMouseMode();
	
	CocoaGame_UpdateMousePositionOutsideOfEventStream();
	
	CocoaGame_FadeFromBlack();
}

void CocoaGame_GetWindowDimensions(int *width, int *height)
{
	NSCAssert(videoConfig.disposition == COCOAGAME_VIDEO_FULLSCREEN_WINDOW || videoConfig.disposition == COCOAGAME_VIDEO_WINDOW, 
		@"CocoaGame_GetWindowDimensions only available in window or full-screen-window video setup.");

	*width = windowWidth;
	*height = windowHeight;
}

void CocoaGame_SetDrawCallback(void (*callback)(void *), void *context)
{
	drawCallback = callback;
	drawCallbackContext = context;
}

static CGRect CocoaGame_GetDisplayBoundsInNSWindowCoordinateSpace(void)
{
	CGRect auxScreenRect = CGDisplayBounds(whichDisplay);
	CGRect mainScreenRect = CGDisplayBounds(CGMainDisplayID());
	
	auxScreenRect.origin.y = -(auxScreenRect.origin.y + auxScreenRect.size.height - mainScreenRect.size.height);
	
	return auxScreenRect;
}

static CocoaGame_Bool CocoaGame_InitVideoWindow(const CocoaGame_VideoConfig *config, CocoaGame_View *reuseView)
{
	CocoaGame_UInt styleMask = NSTitledWindowMask | NSMiniaturizableWindowMask | NSClosableWindowMask;
	
	if (config->enableWindowResizing)
		styleMask |= NSResizableWindowMask;
		
	if (! CocoaGame_CreateWindowAndView(config->mode.width, config->mode.height, styleMask, config->useLionFullScreenSupport, reuseView))
		return FALSE;

	if (config->title)
		[window setTitle:[NSString stringWithUTF8String:config->title]];
		
	[window center];
	[window makeKeyAndOrderFront:nil];
	
	videoConfig.disposition = COCOAGAME_VIDEO_WINDOW;
	CocoaGame_GetVideoModeFromDictionary((NSDictionary *) CGDisplayCurrentMode(whichDisplay), &videoConfig.mode);
	CocoaGame_ReadViewDimensions(&videoConfig.mode.width, &videoConfig.mode.height);

	CocoaGame_Trace("%s: windowed video initialised.\n", __FUNCTION__);
	return TRUE;
}

static void CocoaGame_ReadViewDimensions(int *width, int *height)
{
	NSRect bounds = [view bounds];
	
	*width = (int) bounds.size.width;
	*height = (int) bounds.size.height;
}

static CocoaGame_Bool CocoaGame_InitVideoFullScreenWindow(const CocoaGame_VideoConfig *config, CocoaGame_View *reuseView)
{
	if (config->useLionFullScreenSupport && [NSWindow instancesRespondToSelector:@selector(toggleFullScreen:)]) {
		// Use Lion's fullscreen support.
		if (! CocoaGame_InitVideoWindow(config, reuseView))
			return FALSE;
			
		windowIsTogglingFullScreen = TRUE;

		// This is the secret to ensuring the game goes fullscreen with a nice animation, but for some reason
		// it only works when the game is launched from the Dock. I think it's something to do with how the
		// application gets activated.
		CocoaGame_Poll();
		
		[window toggleFullScreen:window];
	
		// If you want to wait for the fullscreen toggle animation to run before continuing game startup, uncomment.
		while (windowIsTogglingFullScreen)
			CocoaGame_Poll();

		videoConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW;

		return TRUE;
	}
	
	if (! CocoaGame_CreateFullScreenWindow(CocoaGame_WindowLevelToNSWindowLevel(config->fullScreenWindowLevel), TRUE, reuseView))
		return FALSE;

	videoConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW;
	CocoaGame_GetVideoModeFromDictionary((NSDictionary *) CGDisplayCurrentMode(whichDisplay), &videoConfig.mode);
	CocoaGame_ReadViewDimensions(&videoConfig.mode.width, &videoConfig.mode.height);

	CocoaGame_Trace("%s: full-screen-window video initialised.\n", __FUNCTION__);
	return TRUE;
}

static CocoaGame_Int CocoaGame_WindowLevelToNSWindowLevel(CocoaGame_WindowLevel level)
{
	switch (level) {
		default:
			NSCAssert(0, @"Invalid CocoaGame_WindowLevel");
			
		case COCOAGAME_WINDOWLEVEL_DEFAULT:
			return NSNormalWindowLevel;
			
		case COCOAGAME_WINDOWLEVEL_PANEL:
			return NSFloatingWindowLevel;
			
		case COCOAGAME_WINDOWLEVEL_VERY_HIGH:
			return NSScreenSaverWindowLevel;
	}
}

CocoaGame_Bool CocoaGame_InitGL(const CocoaGame_GLConfig *config)
{
	NSCAssert(isInitialised && videoConfig.disposition != COCOAGAME_VIDEO_NONE, 
		@"Attempt to initialise GL without initialising video first.");
	
	CocoaGame_Trace("%s: initialising OpenGL...\n", __FUNCTION__);
	openGLContext = CocoaGame_CreateOpenGLContext(config, &glConfig);
	if (! openGLContext)
		return FALSE;
		
	if (! CocoaGame_UpdateOpenGLContext()) {
		openGLContext = nil;
		return FALSE;
	}
	
	[openGLContext retain];		   
	
	openGLUpdateRequired = FALSE;

	[openGLContext makeCurrentContext];

	// Make sure we don't display any garbage to the user.
	glDisable(GL_SCISSOR_TEST);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	
	[openGLContext flushBuffer];

	CocoaGame_Trace("%s: OpenGL initialised.\n", __FUNCTION__);

	return TRUE;
}

static NSOpenGLContext *CocoaGame_CreateOpenGLContext(const CocoaGame_GLConfig *config, CocoaGame_GLConfig *actualConfig)
{
	int msaa = config->msaa;
	if (msaa < 1)
		msaa = 1;

	for (; msaa; --msaa) {
		NSOpenGLPixelFormatAttribute attribs[40];
		unsigned int attribCount = 0;

		attribs[attribCount++] = NSOpenGLPFAAccelerated;
		attribs[attribCount++] = NSOpenGLPFADoubleBuffer;
		attribs[attribCount++] = NSOpenGLPFANoRecovery;

		if (CocoaGame_GetVideoTraits()->acquiresDisplays) {
			attribs[attribCount++] = NSOpenGLPFAFullScreen;
			attribs[attribCount++] = NSOpenGLPFAScreenMask;
			attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) CGDisplayIDToOpenGLDisplayMask(whichDisplay);
		}

		attribs[attribCount++] = NSOpenGLPFAColorSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->colourBits;
		attribs[attribCount++] = NSOpenGLPFAAlphaSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->alphaBits;
		attribs[attribCount++] = NSOpenGLPFADepthSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->depthBits;
		attribs[attribCount++] = NSOpenGLPFAStencilSize;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->stencilBits;

		if (msaa > 1) {
			attribs[attribCount++] = NSOpenGLPFAMultisample;
			attribs[attribCount++] = NSOpenGLPFASampleBuffers;
			attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) 1;
			attribs[attribCount++] = NSOpenGLPFASamples;
			attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) msaa;
		}

		// Terminate the attributes.
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) 0;
		
		NSCAssert(attribCount <= countof(attribs), @"Overflowed attribs buffer");

		NSOpenGLPixelFormat *pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attribs] autorelease];

		if (! pixelFormat) 
			continue;

		NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
		
		if (! context) 
			continue;
		
		GLint swapInterval = config->swapInterval;
		[context setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];

		CocoaGame_ReadGLConfig(context, pixelFormat, actualConfig);
		return [context autorelease];
	}

	NSLog(@"%s: unable to create GL pixel format/context.", __FUNCTION__);
	return nil;
}

static CocoaGame_Bool CocoaGame_ReadGLConfig(NSOpenGLContext *context, NSOpenGLPixelFormat *pixelFormat, CocoaGame_GLConfig *config)
{
	GLint gotMSAA = 0;
	[pixelFormat getValues:&gotMSAA forAttribute:NSOpenGLPFASamples forVirtualScreen:0];
	config->msaa = (int) gotMSAA;

	GLint gotColour;
	[pixelFormat getValues:&gotColour forAttribute:NSOpenGLPFAColorSize forVirtualScreen:0];
	config->colourBits = (int) gotColour;

	GLint gotAlpha;
	[pixelFormat getValues:&gotAlpha forAttribute:NSOpenGLPFAAlphaSize forVirtualScreen:0];
	config->alphaBits = (int) gotAlpha;

	GLint gotDepth;
	[pixelFormat getValues:&gotDepth forAttribute:NSOpenGLPFADepthSize forVirtualScreen:0];
	config->depthBits = (int) gotDepth;

	GLint gotStencil;
	[pixelFormat getValues:&gotStencil forAttribute:NSOpenGLPFAStencilSize forVirtualScreen:0];
	config->stencilBits = (int) gotStencil;
	
	GLint gotSwapInterval;
	[context getValues:&gotSwapInterval forParameter:NSOpenGLCPSwapInterval];
	config->swapInterval = (int) gotSwapInterval;
	
	CocoaGame_Trace("%s: colourBits=%d alphaBits=%d depthBits=%d stencilBits=%d msaa=%d swapInterval=%d\n", 
		__FUNCTION__, config->colourBits, config->alphaBits, config->depthBits, config->stencilBits, config->msaa, config->swapInterval);
	
	return TRUE;
}

const CocoaGame_GLConfig *CocoaGame_GetGLConfig(void)
{
	return &glConfig;
}

CocoaGame_Bool CocoaGame_BeginRender(void)
{
	NSCAssert(isInitialised && openGLContext, @"Attempt to begin rendering when GL not initialised.");

	CocoaGame_Bool shouldRender;
	
	if (CocoaGame_GetVideoTraits()->rendersToView) {
		shouldRender = [window isVisible];

		CocoaGame_ReadViewDimensions(&videoConfig.mode.width, &videoConfig.mode.height);

		NSCAssert([openGLContext view] == view, @"openGLContext has been reassigned somehow.");
	} else {
		shouldRender = [NSApp isActive];
			
		CGRect bounds = CGDisplayBounds(whichDisplay);
		if ((int) bounds.size.width != videoConfig.mode.width || (int) bounds.size.height != videoConfig.mode.height) {
			NSLog(@"%s: video mode changed externally!\n", __FUNCTION__);
			CocoaGame_GetVideoModeFromDictionary((NSDictionary *) CGDisplayCurrentMode(whichDisplay), &videoConfig.mode);
			openGLUpdateRequired = TRUE;
		}
	}

	if (openGLUpdateRequired)  {
		CocoaGame_UpdateOpenGLContext();
		openGLUpdateRequired = FALSE;
	}

	[openGLContext makeCurrentContext];
	
	discardedRender = FALSE;

	return shouldRender;
}

static BOOL CocoaGame_UpdateOpenGLContext(void)
{
	if (CocoaGame_GetVideoTraits()->rendersToView) {
		CocoaGame_Trace("%s: updating OpenGL context (windowed).\n", __FUNCTION__);
		[openGLContext setView:view];
		[openGLContext update];
		CocoaGame_Trace("%s: OpenGL context updated.\n", __FUNCTION__);
	} else {
		CocoaGame_Trace("%s: updating OpenGL context (full screen).\n", __FUNCTION__);
		
		#if 0
			if (CGLSetFullScreen([openGLContext CGLContextObj]) != kCGLNoError)
				return FALSE;
		#else
			// Less deprecated!, but doesn't return an error code.
			[openGLContext setFullScreen];
		#endif

		CocoaGame_Trace("%s: OpenGL context updated.\n", __FUNCTION__);
	}

	return TRUE;
}

void CocoaGame_EndRender(void)
{
	// Shut down during render?
	if (! isInitialised || ! openGLContext)
		return;

	NSCAssert([NSOpenGLContext currentContext] == openGLContext, @"Did you forget to CocoaGame_SetTargetPixelBuffer(NULL)?");
	NSCAssert(! CocoaGame_GetVideoTraits()->rendersToView || [openGLContext view] == view, @"openGLContext view reassigned somehow.");
	
	if (! discardedRender)
		[openGLContext flushBuffer];
	
	discardedRender = TRUE;
}

void CocoaGame_DiscardRender(void)
{
	discardedRender = TRUE;
}
	

typedef struct CocoaGame_SidedModifierTest {
	CocoaGame_UInt cocoaFlag;
	CocoaGame_UInt cocoaLeftDeviceFlag;
	CocoaGame_UInt cocoaRightDeviceFlag;
	enum CocoaGame_Modifiers leftFlag;
	enum CocoaGame_Modifiers rightFlag;
} CocoaGame_SidedModifierTest;

static CocoaGame_SidedModifierTest SIDED_MODIFIER_TESTS[] = {
	{ NSShiftKeyMask, NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK, COCOAGAME_MODIFIER_LEFT_SHIFT, COCOAGAME_MODIFIER_RIGHT_SHIFT },
	{ NSControlKeyMask, NX_DEVICELCTLKEYMASK, NX_DEVICERCTLKEYMASK, COCOAGAME_MODIFIER_LEFT_CTRL, COCOAGAME_MODIFIER_RIGHT_CTRL },
	{ NSAlternateKeyMask, NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK, COCOAGAME_MODIFIER_LEFT_ALT, COCOAGAME_MODIFIER_RIGHT_ALT },
	{ NSCommandKeyMask, NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK, COCOAGAME_MODIFIER_LEFT_COMMAND, COCOAGAME_MODIFIER_RIGHT_COMMAND }
};

static unsigned int CocoaGame_TestSidedModifiers(const CocoaGame_SidedModifierTest *test, CocoaGame_UInt cocoaModifierFlags)
{
	if (! (cocoaModifierFlags & test->cocoaFlag)) 
		return 0;
		
	unsigned int flags = 0;
		
	if (cocoaModifierFlags & test->cocoaLeftDeviceFlag)
		flags |= test->leftFlag;
		
	if (cocoaModifierFlags & test->cocoaRightDeviceFlag)
		flags |= test->rightFlag;
		
	// If neither of the device flags are set, just assume left
	if (! flags)
		return test->leftFlag;
		
	return flags;
}

void CocoaGame_UpdateModifiers(unsigned long cocoaModifierFlags)
{
	NSCAssert(isInitialised, @"");
	
	unsigned int i;

	unsigned int newModifiers = 0;	  
	for (i = 0; i != countof(SIDED_MODIFIER_TESTS); ++i) 
		newModifiers |= CocoaGame_TestSidedModifiers(&SIDED_MODIFIER_TESTS[i], (CocoaGame_UInt) cocoaModifierFlags);
		
	if (cocoaModifierFlags & NSAlphaShiftKeyMask)
		newModifiers |= COCOAGAME_MODIFIER_CAPS_LOCK;
		
	if (modifiers == newModifiers)
		return;
		
	CocoaGame_Event ourEvent;
	ourEvent.type = COCOAGAME_EVENT_MODIFIERS_CHANGED;
	ourEvent.modifiers.modifiers = newModifiers;
	ourEvent.modifiersChanged.previousModifiers = modifiers;
	CocoaGame_QueueEvent(&ourEvent);
		
	modifiers = newModifiers;
}

unsigned int CocoaGame_GetModifiers(void)
{
	NSCAssert(isInitialised, @"");

	return modifiers;
}

void CocoaGame_Sleep(double seconds)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// CocoaGame_Trace("%s...\n", __FUNCTION__);
	
	[NSApp nextEventMatchingMask:NSAnyEventMask 
					   untilDate:[NSDate dateWithTimeIntervalSinceNow:seconds] 
						  inMode:NSDefaultRunLoopMode 
						 dequeue:NO];
	
	[pool drain];
}

void CocoaGame_QueueEvent(const CocoaGame_Event *event)
{
	int nextQueueWrite = (queueWrite + 1) % COCOAGAME_MAX_QUEUED_EVENTS;
	
	if (nextQueueWrite == queueRead) {
		NSLog(@"%s: queue full.", __FUNCTION__);
	} else {	
		queue[queueWrite] = *event;
		queueWrite = nextQueueWrite;
	}
}

CocoaGame_Bool CocoaGame_DequeueEvent(CocoaGame_Event *event)
{
	if (queueRead == queueWrite) 
		return FALSE;

	// Leaving this here as a reminder. Standard Cocoa application's don't process any input during a fullscreen
	// toggle. I've found this to be an issue only when quitting while a window is in the process of animating 
	// between fullscreen and a window, so I've put some code to protect from that in CocoaGame_ShutdownVideo
	// instead. If there's some other issue then this code may need to be restored.
	// if (windowIsTogglingFullScreen) {
	// 	CocoaGame_Poll();
	// 	return FALSE;
	// }
	
	*event = queue[queueRead];
	queueRead = (queueRead + 1) % COCOAGAME_MAX_QUEUED_EVENTS;
	return TRUE;
}	

void CocoaGame_TraceEvent(const CocoaGame_Event *event)
{
	switch (event->type) {
		case COCOAGAME_EVENT_NONE:
			break;
			
		case COCOAGAME_EVENT_APP_ACTIVATE:
			fprintf(stderr, "App activate\n");
			break;
			
		case COCOAGAME_EVENT_APP_DEACTIVATE:
			fprintf(stderr, "App deactivate\n");
			break;
			
		case COCOAGAME_EVENT_MODIFIERS_CHANGED:
			fprintf(stderr, "Modifiers	 : modifiers now 0x%02x were 0x%02x\n", 
				event->modifiers.modifiers, event->modifiersChanged.previousModifiers);
			break;
			
		case COCOAGAME_EVENT_KEY_DOWN:
			fprintf(stderr, "Key down	 : key 0x%04x modifiers 0x%02x keyCode 0x%02x\n", 
				(unsigned int) event->key.key, event->modifiers.modifiers, event->key.keyCode);
			break;

		case COCOAGAME_EVENT_KEY_UP:
			fprintf(stderr, "Key up		 : key 0x%04x modifiers 0x%02x keyCode 0x%02x\n", 
				(unsigned int) event->key.key, event->modifiers.modifiers, event->key.keyCode);
			break;

		case COCOAGAME_EVENT_CHAR:
			if (event->character.unicode >= ' ' && event->character.unicode < 127) {
				fprintf(stderr, "Character	 : '%c' modifiers 0x%02x\n", 
					(char) event->character.unicode, event->modifiers.modifiers);
			} else {
				fprintf(stderr, "Character	 : UNICODE 0x%04x modifiers 0x%02x\n", 
					(unsigned int) event->character.unicode, event->modifiers.modifiers);
			}
			break;
			
		case COCOAGAME_EVENT_MOUSE_MOVE:
			fprintf(stderr, "Mouse move	 :			@ %4d, %4d delta % 3.4f, % 3.4f modifiers 0x%02x\n", 
				event->mousePosition.x, event->mousePosition.y, 
				event->mouseMove.deltaX, event->mouseMove.deltaY, event->modifiers.modifiers);
			break;

		case COCOAGAME_EVENT_MOUSE_DOWN:
			fprintf(stderr, "Mouse down	 : button %d @ %4d, %4d modifiers 0x%02x\n", 
				(int) event->mouseButton.button, event->mousePosition.x, event->mousePosition.y, 
				event->modifiers.modifiers);
			break;
			
		case COCOAGAME_EVENT_MOUSE_UP:
			fprintf(stderr, "Mouse up	 : button %d @ %4d, %4d modifiers 0x%02x\n", 
				(int) event->mouseButton.button, event->mousePosition.x, event->mousePosition.y, 
				event->modifiers.modifiers);
			break;

		case COCOAGAME_EVENT_MOUSE_SCROLL:
			fprintf(stderr, "Mouse scroll:			@ %4d, %4d scroll % 3.4f, % 3.4f modifiers 0x%02x\n", 
				event->mouseScroll.cursorX, event->mouseScroll.cursorY, 
				event->mouseScroll.scrollX, event->mouseScroll.scrollY, event->modifiers.modifiers);
			break;
	}
}

static CocoaGame_Bool CocoaGame_PollOne(void)
{
	NSCAssert(isInitialised, @"");

	NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask 
										untilDate:nil // i.e., return immediately/don't wait for an event
										   inMode:NSDefaultRunLoopMode
										  dequeue:YES];
	
	if (! event)
		return FALSE;
										  
	if (! CocoaGame_ProcessEvent(event))
		[NSApp sendEvent:event];
		
	return TRUE;
}

void CocoaGame_Poll(void)
{
	while (CocoaGame_PollOne())
		{}
}

CocoaGame_Bool CocoaGame_ProcessEvent(void *voidEvent)
{
	NSEvent *event = (NSEvent *) voidEvent;
	
	CocoaGame_UpdateModifiers([event modifierFlags]);
	
	CocoaGame_Bool consumed = FALSE;
		
	switch ([event type]) {
		// handle an NSSystemDefined event with subtype 7, and you can get 32-button-mouse support!
		
		case NSLeftMouseDown:
		case NSRightMouseDown:
		case NSOtherMouseDown: {
			if (CocoaGame_UpdateMousePosition(event))
				CocoaGame_QueueMouseMoveEvent(event);

			if (([event window] == window && mouseIsInView) || CocoaGame_GetVideoTraits()->acquiresDisplays) {
				CocoaGame_Event ourEvent;
				CocoaGame_NSEventToMouseButtonEvent(event, &ourEvent.mouseButton);
				ourEvent.type = COCOAGAME_EVENT_MOUSE_DOWN;
				CocoaGame_QueueEvent(&ourEvent);
			}

			consumed = CocoaGame_GetVideoTraits()->acquiresDisplays;
			break;
		}

		case NSLeftMouseUp:
		case NSRightMouseUp:
		case NSOtherMouseUp:
			if (CocoaGame_UpdateMousePosition(event))
				CocoaGame_QueueMouseMoveEvent(event);
			
			if ([event window] == window || CocoaGame_GetVideoTraits()->acquiresDisplays) {
				CocoaGame_Event ourEvent;
				CocoaGame_NSEventToMouseButtonEvent(event, &ourEvent.mouseButton);
				ourEvent.type = COCOAGAME_EVENT_MOUSE_UP;
				CocoaGame_QueueEvent(&ourEvent);
			}
			break;
			
		case NSLeftMouseDragged:
		case NSRightMouseDragged:
		case NSOtherMouseDragged:
		case NSMouseMoved:
			if (CocoaGame_UpdateMousePosition(event))
				CocoaGame_QueueMouseMoveEvent(event);
			break;
			
		case NSScrollWheel:
			// Don't queue a COCOAGAME_EVENT_MOUSE_MOVE since the deltaX and deltaY properties of the event
			// are hijacked for NSScrollWheel to contain scroll deltas.
			CocoaGame_UpdateMousePosition(event);

			if ([event window] == window || CocoaGame_GetVideoTraits()->acquiresDisplays) {
				consumed = TRUE;

				CocoaGame_Event ourEvent;
				CocoaGame_SetupModifiersEvent(&ourEvent.modifiers);
				ourEvent.mouseScroll.cursorX = (int) mousePosition.x;
				ourEvent.mouseScroll.cursorY = (int) mousePosition.y;
				ourEvent.mouseScroll.scrollX = (float) [event deltaX];
				ourEvent.mouseScroll.scrollY = (float) [event deltaY];
				ourEvent.modifiers.type = COCOAGAME_EVENT_MOUSE_SCROLL;
				CocoaGame_QueueEvent(&ourEvent);
			}
			break;
			
		case NSKeyUp:
			if ([event window] == window || CocoaGame_GetVideoTraits()->acquiresDisplays) 
				CocoaGame_QueueKeyAndCharacterEvents(event);
			break;
			
		case NSKeyDown:
			if ([event window] == window || CocoaGame_GetVideoTraits()->acquiresDisplays) {
				consumed = TRUE;
				
				if (! CocoaGame_CheckForSpecialKeys(event)) {
					 if (wantKeyRepeats || ! [event isARepeat]) {
						CocoaGame_QueueKeyAndCharacterEvents(event);
					}					 
				}
			}
			break;
			
		default:
			break;
	}

	return consumed;
}

static BOOL CocoaGame_UpdateMousePosition(NSEvent *event)
{
	// We want the mouse position at the time of the event, in our window coordinates.
	
	NSPoint mousePositionWas = mousePosition;

	NSPoint positionInWindow;
	
	if ([event window] == window)
		positionInWindow = [event locationInWindow];
	else {
		NSPoint positionInScreen;
	
		if ([event window]) 
			positionInScreen = [[event window] convertBaseToScreen:[event locationInWindow]];
		else 
			positionInScreen = [event locationInWindow];

		positionInWindow = [window convertScreenToBase:positionInScreen];
	}
	
	if (view && CocoaGame_GetVideoTraits()->rendersToView) {
		NSRect viewBounds = [view bounds];
		mousePosition = [view convertPoint:positionInWindow fromView:nil];
		mouseIsInView = NSPointInRect(mousePosition, viewBounds);
	} else {
		mousePosition = positionInWindow;
		mouseIsInView = YES;
	}

	CocoaGame_Bool positionChanged = (int) mousePosition.x != (int) mousePositionWas.x || (int) mousePosition.y != (int) mousePositionWas.y;
	
	return positionChanged || CocoaGame_MouseMoveHasDelta(event);
}

static void CocoaGame_QueueMouseMoveEvent(NSEvent *event)
{
	CocoaGame_Event ourEvent;
	CocoaGame_SetupMouseMoveEvent(event, &ourEvent.mouseMove);
	ourEvent.type = COCOAGAME_EVENT_MOUSE_MOVE;
	CocoaGame_QueueEvent(&ourEvent);
}

static CocoaGame_Bool CocoaGame_MouseMoveHasDelta(NSEvent *event)
{
	return fabsf((float) [event deltaX]) > 0.01f || fabsf((float) [event deltaY]) > 0.01f;
}

static void CocoaGame_SetupModifiersEvent(CocoaGame_ModifiersEvent *event)
{
	event->modifiers = modifiers;
}

static void CocoaGame_SetupMousePositionEvent(CocoaGame_MousePositionEvent *mousePositionEvent)
{
	CocoaGame_SetupModifiersEvent(&mousePositionEvent->base);
	mousePositionEvent->x = (int) mousePosition.x;
	mousePositionEvent->y = (int) mousePosition.y;				  
}

static void CocoaGame_SetupMouseMoveEvent(NSEvent *event, CocoaGame_MouseMoveEvent *mouseMove)
{
	CocoaGame_SetupMousePositionEvent(&mouseMove->base);
	mouseMove->deltaX = (float) [event deltaX];
	mouseMove->deltaY = (float) [event deltaY];
}

static void CocoaGame_NSEventToMouseButtonEvent(NSEvent *event, CocoaGame_MouseButtonEvent *buttonEvent)
{
	CocoaGame_SetupMousePositionEvent(&buttonEvent->base);
	buttonEvent->button = (CocoaGame_MouseButton) [event buttonNumber];
	buttonEvent->clickCount = (int) [event clickCount];
}

static void CocoaGame_QueueKeyAndCharacterEvents(NSEvent *event)
{
	if ([event type] == NSKeyDown)
		CocoaGame_QueueCharEvent(event);

	CocoaGame_QueueKeyEvent(event);
}

static void CocoaGame_QueueKeyEvent(NSEvent *event)
{
	NSString *characters = [event charactersIgnoringModifiers];
	CocoaGame_UInt length = [characters length];

	if (length) {
		CocoaGame_Event ourEvent;
		CocoaGame_SetupModifiersEvent(&ourEvent.modifiers);
		ourEvent.key.key = [characters characterAtIndex:0];
		ourEvent.key.keyCode = [event keyCode];
		ourEvent.type = [event type] == NSKeyDown ? COCOAGAME_EVENT_KEY_DOWN : COCOAGAME_EVENT_KEY_UP;

		// Normalise to upper case
		if (ourEvent.key.key >= 'a' && ourEvent.key.key <= 'z')
			ourEvent.key.key += 'A' - 'a';
			
		CocoaGame_QueueEvent(&ourEvent);
	}
}

static void CocoaGame_QueueCharEvent(NSEvent *event)
{
	NSString *characters = [event characters];
	CocoaGame_UInt length = [characters length];
	unsigned long unicode = length ? [characters characterAtIndex:0] : 0;

	if (length && ! CocoaGame_IsFunctionKey(unicode)) {
		CocoaGame_Event ourEvent;
		CocoaGame_SetupModifiersEvent(&ourEvent.modifiers);
		ourEvent.character.unicode = unicode;
		ourEvent.type = COCOAGAME_EVENT_CHAR;

		if (length > 1)
			CocoaGame_Trace("%s: multi-character input extra characters ignored.\n", __FUNCTION__);

		CocoaGame_QueueEvent(&ourEvent);
	}
}

static CocoaGame_Bool CocoaGame_IsFunctionKey(unsigned long unicode)
{
	// Omit the range reserved by OpenStep for special keys, the delete key and any control codes.
	return (unicode >= 0xF700 && unicode <= 0xF8FF) || unicode == 127 || unicode < 32;
}

static void CocoaGame_UpdateMousePositionOutsideOfEventStream(void)
{
	if (window) 
		mousePosition = [window mouseLocationOutsideOfEventStream];
}

static CocoaGame_Bool CocoaGame_CheckForSpecialKeys(NSEvent *event)
{
	NSString *characters = [event charactersIgnoringModifiers];
	
	(void) characters;

	if (enableAltEsc) {
		// Alt+Esc, Alt+Shift+Esc, Alt+Ctrl+Esc will all trigger this
		if ([characters length] && [characters characterAtIndex:0] == 0x1b && (CocoaGame_GetModifiers() & COCOAGAME_MODIFIER_BOTH_ALTS)) {
			shouldQuit = TRUE;
			return TRUE;
		}
	}
	
	// if ([characters length] && [characters characterAtIndex:0] == '\t' && (CocoaGame_GetModifiers() & COCOAGAME_MODIFIER_BOTH_COMMANDS))
	//	   CocoaGame_Trace("Command+Tab!");
	
	return FALSE;
}

CocoaGame_Bool CocoaGame_WasQuitRequested(void)
{
	NSCAssert(isInitialised, @"");

	return shouldQuit;
}

void CocoaGame_SetQuitRequested(CocoaGame_Bool newValue)
{
	shouldQuit = newValue;
}

void CocoaGame_GetMousePosition(int *x, int *y)
{
	*x = (int) mousePosition.x;
	*y = (int) mousePosition.y;
}

CocoaGame_Bool CocoaGame_IsAppActive(void)
{
	return [NSApp isActive] ? TRUE : FALSE;
}

void CocoaGame_SetKeyRepeat(CocoaGame_Bool keyRepeatEnabled)
{
	wantKeyRepeats = keyRepeatEnabled;
}

void CocoaGame_SetMouseDeltaMode(CocoaGame_Bool deltaMode)
{
	wantMouseDeltaMode = deltaMode;
	
	if (CocoaGame_AppOwnsMouse())
		CocoaGame_InternalSetMouseDeltaMode(deltaMode);
}

static void CocoaGame_InternalSetMouseDeltaMode(CocoaGame_Bool deltaMode)	 
{
	if (deltaMode) {
		CGAssociateMouseAndMouseCursorPosition(0);
		CocoaGame_WarpMouseCursorToCentreOfView();
	} else
		CGAssociateMouseAndMouseCursorPosition(1);

	CocoaGame_UpdateMousePositionOutsideOfEventStream();
}

CocoaGame_Bool CocoaGame_IsMouseInDeltaMode(void)
{
	return wantMouseDeltaMode;
}

void CocoaGame_SetMouseCursorVisible(CocoaGame_Bool cursorVisible)
{
	wantMouseCursorVisible = cursorVisible;
	
	if (CocoaGame_AppOwnsMouse())
		CocoaGame_InternalSetMouseCursorVisible(cursorVisible);
}

static void CocoaGame_InternalSetMouseCursorVisible(CocoaGame_Bool cursorVisible)	 
{
	// This hack is needed to simultaneously support 10.4 and Lion
	BOOL isLionFullScreenWindow = videoConfig.disposition == COCOAGAME_VIDEO_FULLSCREEN_WINDOW && videoConfig.useLionFullScreenSupport && [window respondsToSelector:@selector(toggleFullScreen:)];

	if (CocoaGame_GetVideoTraits()->hideGlobalCursor && ! isLionFullScreenWindow) {
		if (cursorVisible) {
			if (nsCursorHidden) {
				[NSCursor unhide];
				nsCursorHidden = FALSE;
			}
		} else {
			if (! nsCursorHidden) {
				[NSCursor hide];
				nsCursorHidden = TRUE;
			}
		}
	} else {
		if (nsCursorHidden) {
			[NSCursor unhide];
			nsCursorHidden = FALSE;
		}
	}

	viewCursorHidden = ! cursorVisible;
	[window invalidateCursorRectsForView:view];
}

CocoaGame_Bool CocoaGame_IsMouseCursorVisible(void)
{
	return wantMouseCursorVisible;
}

CocoaGame_Bool CocoaGame_AppOwnsMouse(void)
{
	if (! [NSApp isActive] || videoConfig.disposition == COCOAGAME_VIDEO_NONE)
		return NO;
		
	// If rendering to a view, then mouse cursor visibility is handled for us by the cursor rects.
	if (! CocoaGame_GetVideoTraits()->rendersToView) 
		return YES;
	
	return [NSApp keyWindow] == window;
}

static void CocoaGame_WarpMouseCursorToCentreOfView(void)
{
	NSRect frame = [window contentRectForFrameRect:[window frame]];

	CGRect mainScreenRect = CGDisplayBounds(CGMainDisplayID());

	frame.origin.y = -(frame.origin.y + frame.size.height - mainScreenRect.size.height);

	CGWarpMouseCursorPosition(CGPointMake((NSMaxX(frame) + NSMinX(frame)) / 2.0f, (NSMaxY(frame) + NSMinY(frame)) / 2.0f));
}

void CocoaGame_SetMousePosition(int x, int y)
{
	// I don't trust NSScreen when combined with CGDisplaySwitchToMode...
	
	NSRect frame = [window contentRectForFrameRect:[window frame]];
	
	CGRect mainScreenRect = CGDisplayBounds(CGMainDisplayID());
	
	CGPoint point;
	point.x = frame.origin.x + x;
	point.y = frame.origin.y + y;
	
	point.y = mainScreenRect.size.height - point.y;

	CGWarpMouseCursorPosition(point);
}

static void CocoaGame_ImplementDefaultMouseMode(void)
{
	CocoaGame_InternalSetMouseDeltaMode(FALSE);
	CocoaGame_InternalSetMouseCursorVisible(TRUE);
}

static void CocoaGame_ImplementAppMouseMode(void)
{
	CocoaGame_InternalSetMouseDeltaMode(wantMouseDeltaMode);
	CocoaGame_InternalSetMouseCursorVisible(wantMouseCursorVisible);
}

#ifdef COCOAGAME_ENABLE_PBUFFERS

//
// Pixel buffers
//

struct CocoaGame_PixelBuffer {
	NSOpenGLPixelBuffer *pixelBuffer;
	NSOpenGLContext *context;
};

CocoaGame_PixelBuffer *CocoaGame_CreatePixelBuffer(GLenum textureTarget, GLint internalFormat, GLsizei width, GLsizei height, const CocoaGame_GLConfig *config)
{
	CocoaGame_PixelBuffer *pb;
	NSOpenGLPixelFormat *pixelFormat;
	NSAutoreleasePool *pool;
	
	NSCAssert(openGLContext, @"Must initialise GL before creating a pixel buffer.");
	
	pool = [[NSAutoreleasePool alloc] init];
	
	pixelFormat = CocoaGame_CreatePixelFormatForPixelBuffer(config);
	if (! pixelFormat) {
		[pool drain];
		return NULL;
	}
	
	pb = calloc(1, sizeof(*pb));
	
	pb->pixelBuffer = [[NSOpenGLPixelBuffer alloc] initWithTextureTarget:textureTarget 
												   textureInternalFormat:internalFormat 
												   textureMaxMipMapLevel:0 
															  pixelsWide:width 
															  pixelsHigh:height];
															
	if (! pb->pixelBuffer) {
		free(pb);
		[pool drain];
		return NULL;
	}
	
	pb->context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:openGLContext];
	
	if (! pb->context) {
		[pb->pixelBuffer release];
		free(pb);
		[pool drain];
		return NULL;
	}
	
	// [pb->context setPixelBuffer:pb->pixelBuffer cubeMapFace:0 mipMapLevel:0 currentVirtualScreen:[openGLContext currentVirtualScreen]];
	
	[pool drain];
	return pb;
}

static NSOpenGLPixelFormat *CocoaGame_CreatePixelFormatForPixelBuffer(const CocoaGame_GLConfig *config)
{
	NSOpenGLPixelFormatAttribute attribs[40];
	unsigned int attribCount = 0;

	attribs[attribCount++] = NSOpenGLPFAAccelerated;
	// attribs[attribCount++] = NSOpenGLPFADoubleBuffer; // Don't need double buffering for the pbuffer
	attribs[attribCount++] = NSOpenGLPFANoRecovery;

	if (CocoaGame_GetVideoTraits()->acquiresDisplays) {
		attribs[attribCount++] = NSOpenGLPFAFullScreen;
		attribs[attribCount++] = NSOpenGLPFAScreenMask;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) CGDisplayIDToOpenGLDisplayMask(whichDisplay);
	}

	// Shoudn't need to specify these for the pbuffer
	// attribs[attribCount++] = NSOpenGLPFAColorSize;
	// attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->colourBits;
	// attribs[attribCount++] = NSOpenGLPFAAlphaSize;
	// attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->alphaBits;

	// But do need to specify these to enable depth/stencil.
	attribs[attribCount++] = NSOpenGLPFADepthSize;
	attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->depthBits;
	attribs[attribCount++] = NSOpenGLPFAStencilSize;
	attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) config->stencilBits;

	// Use the same MSAA as the front buffer. I'm not sure what happens if I don't do this.
	if (glConfig.msaa > 1) {
		attribs[attribCount++] = NSOpenGLPFAMultisample;
		attribs[attribCount++] = NSOpenGLPFASampleBuffers;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) 1;
		attribs[attribCount++] = NSOpenGLPFASamples;
		attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) glConfig.msaa;
	}

	// Terminate the attributes.
	attribs[attribCount++] = (NSOpenGLPixelFormatAttribute) 0;
	
	NSCAssert(attribCount <= countof(attribs), @"Overflowed attribs array,");

	return [[[NSOpenGLPixelFormat alloc] initWithAttributes:attribs] autorelease];
}

void CocoaGame_SetTargetPixelBuffer(CocoaGame_PixelBuffer *pbuffer)
{
	if (pbuffer) {
		[pbuffer->context setPixelBuffer:pbuffer->pixelBuffer cubeMapFace:0 mipMapLevel:0 currentVirtualScreen:[openGLContext currentVirtualScreen]];
		[pbuffer->context makeCurrentContext];
	} else 
		[openGLContext makeCurrentContext];
}

void CocoaGame_SetTextureImageToPixelBuffer(CocoaGame_PixelBuffer *targetPbuffer, CocoaGame_PixelBuffer *pbuffer, GLenum colourBuffer)
{
	NSOpenGLContext *targetContext = targetPbuffer ? targetPbuffer->context : openGLContext;
	
	[targetContext setTextureImageToPixelBuffer:pbuffer->pixelBuffer colorBuffer:colourBuffer];
}

void CocoaGame_DestroyPixelBuffer(CocoaGame_PixelBuffer *pbuffer)
{
	if ([NSOpenGLContext currentContext] == pbuffer->context) 
		[NSOpenGLContext clearCurrentContext];
		
	[pbuffer->context clearDrawable];
	[pbuffer->context release];

	[pbuffer->pixelBuffer release];
	
	free(pbuffer);
	
	[openGLContext makeCurrentContext];
}

#endif // COCOAGAME_ENABLE_PBUFFERS

//
// Timers
//

double CocoaGame_GetTimer(void)
{
	struct timeval tv;
	gettimeofday(&tv, 0);

	return (double) tv.tv_sec + (double) tv.tv_usec / 1e6;
}

uint32_t CocoaGame_GetMillisecondTimer(void)
{
	struct timeval tv;
	gettimeofday(&tv, 0);

	uintmax_t bigTime;
	bigTime = (uintmax_t) tv.tv_sec * 1000 + (uintmax_t) tv.tv_usec / 1000;

	return (uint32_t) bigTime;
}

//
// NSWindow (CocoaGameAdditions)
//

@implementation NSWindow (CocoaGameAdditions)

- (BOOL)cocoaGame_IsFullScreen
{
	return ([self styleMask] & NSFullScreenWindowMask) != 0;
}

@end

//
// CocoaGame_Window
//

@implementation CocoaGame_Window

- (id)initWithContentRect:(NSRect)contentRect styleMask:(CocoaGame_UInt)windowStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)deferCreation 
{
	if (self = [super initWithContentRect:contentRect styleMask:windowStyle backing:bufferingType defer:deferCreation], self) {
	}
	
	CocoaGame_Trace("%s\n", __FUNCTION__);
	return self;
}

- (void)dealloc 
{
	CocoaGame_Trace("%s\n", __FUNCTION__);
	[super dealloc];
}

- (BOOL)canBecomeKeyWindow 
{
	return YES;
}

@end

//
// CocoaGame_Delegate
//

@implementation CocoaGame_Delegate

- (id)init 
{
	CocoaGame_Trace("%s\n", __FUNCTION__);

	if (self = [super init], self) {
		[[NSNotificationCenter defaultCenter] addObserver:self 
												selector:@selector(applicationDidBecomeActive:)
													name:NSApplicationDidBecomeActiveNotification
												  object:nil];

		[[NSNotificationCenter defaultCenter] addObserver:self 
												selector:@selector(applicationWillResignActive:)
													name:NSApplicationWillResignActiveNotification
												  object:nil];

		[[NSNotificationCenter defaultCenter] addObserver:self 
												selector:@selector(applicationDidResignActive:)
													name:NSApplicationDidResignActiveNotification
												  object:nil];

		[[NSNotificationCenter defaultCenter] addObserver:self 
												selector:@selector(applicationDidChangeScreenParameters:)
													name:NSApplicationDidChangeScreenParametersNotification
												  object:nil];
	}
	
	return self;
}

- (void)dealloc 
{
	CocoaGame_Trace("%s\n", __FUNCTION__);

	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSApplicationDidBecomeActiveNotification
												  object:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSApplicationWillResignActiveNotification
												  object:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSApplicationDidResignActiveNotification
												  object:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSApplicationDidChangeScreenParametersNotification
												  object:nil];

	[super dealloc];
}

- (BOOL)windowShouldClose:(id)sender 
{
	(void) sender;
	
	shouldQuit = TRUE;
	return NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification;
{
	(void) aNotification;
	// CocoaGame_Trace("app did activate\n");

	[window makeKeyAndOrderFront:self];
		
	if (CocoaGame_AppOwnsMouse()) 
		CocoaGame_ImplementAppMouseMode();
		
	CocoaGame_Event ourEvent;
	ourEvent.type = COCOAGAME_EVENT_APP_ACTIVATE;
	CocoaGame_QueueEvent(&ourEvent);
	
	openGLUpdateRequired = TRUE;
}

- (void)applicationWillResignActive:(NSNotification *)aNotification;
{
	(void) aNotification;
	// CocoaGame_Trace("app will deactivate\n");

	CocoaGame_Event ourEvent;
	ourEvent.type = COCOAGAME_EVENT_APP_DEACTIVATE;
	CocoaGame_QueueEvent(&ourEvent);
}

- (void)applicationDidResignActive:(NSNotification *)aNotification;
{
	(void) aNotification;
	// CocoaGame_Trace("app did deactivate\n");
	
	CocoaGame_ImplementDefaultMouseMode();
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification;
{
	(void) aNotification;
	openGLUpdateRequired = TRUE;
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	(void) notification;

	CocoaGame_Trace("%s\n", __FUNCTION__);

	CocoaGame_ImplementDefaultMouseMode();
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	(void) notification;

	CocoaGame_Trace("%s\n", __FUNCTION__);

	CocoaGame_ImplementAppMouseMode();
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
	(void) notification;

	windowIsTogglingFullScreen = TRUE;
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
	(void) notification;

	windowIsTogglingFullScreen = FALSE;
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
	(void) notification;
	
	windowIsTogglingFullScreen = TRUE;
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
	(void) notification;

	windowIsTogglingFullScreen = FALSE;
}

@end

//
// CocoaGame_View
//

@implementation CocoaGame_View

- (id)initWithFrame:(NSRect)frame 
{
	CocoaGame_Trace("%s\n", __FUNCTION__);
	
	if (self = [super initWithFrame:frame], self) {
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(globalFrameDidChange:) 
													 name:NSViewGlobalFrameDidChangeNotification
												   object:self];		
	}
	
	return self;
}

- (void)dealloc 
{
	CocoaGame_Trace("%s\n", __FUNCTION__);
	
	[invisibleCursor release];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSViewGlobalFrameDidChangeNotification
												  object:self];
								 
	[super dealloc];
}

- (void)drawRect:(NSRect)rect 
{
	// Use the callback if we can.
	if (openGLContext && drawCallback) {
		if (CocoaGame_BeginRender()) {
			(*drawCallback)(drawCallbackContext);
			CocoaGame_EndRender();
			return;
		}
	}

	[[NSColor blackColor] set];
	NSRectFill(rect);
}

- (void)globalFrameDidChange:(NSNotification *)aNotification 
{
	(void) aNotification;

	openGLUpdateRequired = TRUE;
	
	if (videoConfig.disposition == COCOAGAME_VIDEO_WINDOW && ! [[self window] cocoaGame_IsFullScreen]) {
		windowWidth = [self bounds].size.width;
		windowHeight = [self bounds].size.height;
	}

	if (videoConfig.disposition == COCOAGAME_VIDEO_FULLSCREEN_WINDOW || videoConfig.disposition == COCOAGAME_VIDEO_WINDOW) {
		CocoaGame_VideoDisposition disposition;
		// I thought this might be safer than overriding -[NSWindow toggleFullScreen:]
		if ([[self window] cocoaGame_IsFullScreen])
			disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW;
		else
			disposition = COCOAGAME_VIDEO_WINDOW;

		if (videoConfig.disposition != disposition) {
			// We've switched fullscreen/window.
			CocoaGame_ImplementDefaultMouseMode();
			videoConfig.disposition = disposition;
			CocoaGame_ImplementAppMouseMode();
			CocoaGame_UpdateMousePositionOutsideOfEventStream();
		}
	}
}

- (void)resetCursorRects
{
	if (! invisibleCursor) {
		NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
		invisibleCursor = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(0, 0)];
		[image release];
	}
	
	if (viewCursorHidden)
		[self addCursorRect:[self bounds] cursor:invisibleCursor];
	else {
		// Although not adding a cursor rect gives you the arrow cursor, if you don't add a cursor rect then 
		// -[NSWindow invalidateCursorRectsForView:] ignores you.
		[self addCursorRect:[self bounds] cursor:[NSCursor arrowCursor]];
	}
}	 

@end

