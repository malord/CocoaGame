//
// CocoaGame2
// Copyright (c) 2007-2012 Mark H. P. Lord. All rights reserved.
//

#ifndef COCOAGAME_H
#define COCOAGAME_H

#include <OpenGL/gl.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int CocoaGame_Bool;

#ifndef TRUE
#define TRUE 1
#endif

#ifndef FALSE
#define FALSE 0
#endif

//
// Logging
// These functions don't require CocoaGame_Init() to have been called.
//

/// Write a diagnostic message to stderr, unless disabled with CocoaGame_SetTraceEnabled().
void CocoaGame_Trace(const char *format, ...);

/// Disable CocoaGame_Trace() (which disables all of CocoaGame's output to stderr).
void CocoaGame_SetTraceEnabled(CocoaGame_Bool traceEnabled);

typedef void (*CocoaGame_TraceHandler)(const char *format, va_list argptr);

/// Redirect CocoaGame_Trace() output to the specified function. The function will only be called if tracing is 
/// enabled (controlled by CocoaGame_SetTraceEnabled()).
void CocoaGame_SetTraceHandler(CocoaGame_TraceHandler handler);

CocoaGame_TraceHandler CocoaGame_GetTraceHandler(void);

//
// Autorelease pool management
//

/// Allows you to create NSAutoreleasePools without having to make a module Objective-C. Use 
/// CocoaGame_FreeAutoreleasePool() to free the pool and release its contents.
void CocoaGame_CreateAutoreleasePool(void **pool);

/// Free an NSAutoreleasePool created by CocoaGame_CreateAutoreleasePool().
void CocoaGame_FreeAutoreleasePool(void *pool);

//
// Initialisation and shutdown
//

/// Enable or disable Alt+Esc to quit. Enabled by default.
void CocoaGame_SetAltEscEnabled(CocoaGame_Bool enableAltEsc);

/// Initialise the CocoaGame framework. Returns TRUE on success, FALSE on failure.
CocoaGame_Bool CocoaGame_Init(void);

/// Shut down the CocoaGame framework. You should call this if any of the Init functions other than CocoaGame_Init()
/// fail (e.g., CocoaGame_InitVideo() or CocoaGame_InitGL()) and it can be called at any time.
void CocoaGame_Shutdown(void);

/// Abort the application with a modal alert panel. Shuts down CocoaGame if necessary.
void CocoaGame_AbortWithMessage(const char *title, const char *format, ...);

/// va_list version of CocoaGame_AbortWithMessage().
void CocoaGame_AbortWithMessageVA(const char *title, const char *format, va_list argptr);

typedef void (*CocoaGame_AbortWithMessageHandler)(const char *title, const char *format, va_list argptr);

/// Redirect CocoaGame_AbortWithMessage() output to the specified function. This can be used to customise the alert
/// box, for example.
void CocoaGame_SetAbortWithMessageHandler(CocoaGame_AbortWithMessageHandler handler);

//
// Video modes
//

typedef struct CocoaGame_VideoMode {
	/// Width, in pixels.
	int width;
	
	/// Height, in pixels.
	int height;
	
	/// Total bits, e.g., 32 for R, G, B, A with 8 bits per component.
	int bits;
} CocoaGame_VideoMode;

/// Parses a string, e,.g. "1680x1050" and fills in a CocoaGame_VideoMode's width, height and optionally bits members.
BOOL CocoaGame_ParseVideoMode(const char *str, CocoaGame_VideoMode *videoMode);

/// Returns the number of video modes.
int CocoaGame_GetVideoModeCount(void);

/// Returns information on an individual video mode. Duplicate modes will have been removed, and the modes are
/// guaranteed to be sorted in descendening order of area.
const CocoaGame_VideoMode *CocoaGame_GetVideoMode(int modeNumber);

/// Build the video mode list. This is normally called in CocoaGame_Init but you can call it yourself to rebuild the
/// list at any time.
CocoaGame_Bool CocoaGame_BuildModeList(void);

CocoaGame_Bool CocoaGame_VideoModesEqual(const CocoaGame_VideoMode *a, const CocoaGame_VideoMode *b);

typedef enum CocoaGame_WindowLevel {
	/// Standard window level for an application. System alerts and panels will present above the window. This is
	/// the only window level that allows you to access Xcode while debugging.
	COCOAGAME_WINDOWLEVEL_DEFAULT,
	
	/// Window level of an application's floating panels. Use this if the application has panels you need to be
	/// behind the game window.
	COCOAGAME_WINDOWLEVEL_PANEL,
	
	/// Maximum non-crazy window level. This covers system panels (including the Command+Tab UI). Not recommended.
	COCOAGAME_WINDOWLEVEL_VERY_HIGH,
} CocoaGame_WindowLevel;

/// Specifies how the video hardware is to be used.
typedef enum CocoaGame_VideoDisposition {
	/// The video hardware is not to be used. You can't pass this to CocoaGame_InitVideo().
	COCOAGAME_VIDEO_NONE,
	
	/// Set up video in a window. The width and height members of the CocoaGame_VideoConfig's mode member are used.
	COCOAGAME_VIDEO_WINDOW,
	
	/// Go full-screen, in the user's current video mode. To support different resolutions the game must up-scale
	/// its back buffer.
	COCOAGAME_VIDEO_FULLSCREEN,
	
	/// Go full-screen and set the video mode. The width, height and bits members of the CocoaGame_VideoConfig's
	/// mode member are all used. 
	COCOAGAME_VIDEO_FULLSCREEN_SET_MODE,
	
	/// Create a full-screen window, without changing the video mode. To support different resolutions the game
	/// must up-scale its back buffer. This is the most user-friendly video disposition, and allows you to debug in
    /// Xcode.
	COCOAGAME_VIDEO_FULLSCREEN_WINDOW,
	
	COCOAGAME_VIDEO__MAX_DISPOSITION
} CocoaGame_VideoDisposition;

/// Specifies how the video hardware is to be configured.
typedef struct CocoaGame_VideoConfig {
	/// One of the CocoaGame_VideoDisposition enumerants.
	CocoaGame_VideoDisposition disposition;
	
	/// Used by COCOAGAME_VIDEO_FULLSCREEN_SET_MODE, COCOAGAME_VIDEO_WINDOW and COCOAGAME_VIDEO_FULLSCREEN_WINDOW.
	/// In COCOAGAME_VIDEO_FULLSCREEN_WINDOW, the width and height are recorded for use by
	/// CocoaGame_ToggleFullScreenWindow().
	CocoaGame_VideoMode mode;
	
	/// Title for the window, in UTF-8.
	const char *title; 
	
	/// If TRUE, don't require an exact match for the video mode but accept the closest match.
	CocoaGame_Bool acceptClosestMode; 
	
	/// This should only really be FALSE in developer builds, where it may help to escape full-screen hell. It is
	/// igored in windowed and fullscreen-windowed modes.
	CocoaGame_Bool captureDisplay;

	/// The OpenGL context happily survives the resize, so the default is TRUE. However, your game needs to be able
	/// to deal with the dynamic resolution change. This has to be TRUE to use Lion's fullscreen support.
	CocoaGame_Bool enableWindowResizing;

	/// Specifies the window level when using COCOAGAME_VIDEO_FULLSCREEN_WINDOW. Ignore in all other dispositions.
	CocoaGame_WindowLevel fullScreenWindowLevel;
	
	/// Use Lion's fullscreen support, if available (only applies to FULLSCREEN_WINDOW and WINDOW dispositions).
	CocoaGame_Bool useLionFullScreenSupport;
} CocoaGame_VideoConfig;

/// A CocoaGame_VideoConfig containing default values for each member. You should assign this to your own
/// CocoaGame_VideoConfig before customising it (in case new memebers are added in the future).
extern const CocoaGame_VideoConfig COCOAGAME_VIDEOCONFIG_DEFAULTS;

/// Retrieves the system's video mode when CocoaGame_Init() was called (i.e., before we changed the mode).
void CocoaGame_GetStartupVideoMode(CocoaGame_VideoMode *mode);

/// Returns width / height of the user's desktop at startup, which probably tells you the aspect ratio of the screen.
float CocoaGame_GetStartupAspectRatio(void);

/// Returns TRUE on success, FALSE on failure.
CocoaGame_Bool CocoaGame_InitVideo(const CocoaGame_VideoConfig *config);

/// Returns the current video configuration. If CocoaGame_InitVideo() was unable to find an exact match for the video
/// mode, or if the window was resized, the returned configuration will not match the requested configuration (i.e.,
/// mode.width and mode.height will always contain the correct, current values).
const CocoaGame_VideoConfig *CocoaGame_GetVideoConfig(void);

/// Returns the current width / height.
float CocoaGame_GetAspectRatio(void);

/// Toggle between fullscreen-window and window mode without recreating the OpenGL context.
void CocoaGame_ToggleFullScreenWindow(void);

/// Retrieves the last known window size. Use this when using CocoaGame_ToggleFullScreenWindow() to find out what
/// the window size was the last time the game was in windowed mode.
void CocoaGame_GetWindowDimensions(int *width, int *height);

/// Set a function to call which will draw the game outside your usual game loop. This allows the contents to be
/// correctly redrawn when resizing the window or animating to/from fullscreen.
void CocoaGame_SetDrawCallback(void (*callback)(void *), void *context);

//
// Fades
// Fades are normally done for you.
//

/// Does nothing if already faded out.
void CocoaGame_FadeToBlack(void);

/// Does nothing if not currently faded out.
void CocoaGame_FadeFromBlack(void);

// Old function names.
#define CocoaGame_FadeOut CocoaGame_FadeToBlack
#define CocoaGame_FadeIn CocoaGame_FadeFromBlack

/// Set the fade time, in seconds. Call this before CocoaGame_InitVideo.
void CocoaGame_SetFadeTime(float fadeTime);

//
// OpenGL initialisation
//

/// Specifies how OpenGL is to be configured.
typedef struct CocoaGame_GLConfig {
	/// Minimum required colour bits per pixel (default is 24).
	int colourBits;
	
	/// Minimum required depth bits per pixel (default is 24).
	int depthBits;
	
	/// Minimum required alpha bits per pixel (default is 8).
	int alphaBits;
	
	/// Minimum required stencil bits per pixel (default is 8).
	int stencilBits;
	
	/// MSAA mode (<= 1 to disable, default is 4).
	int msaa;
	
	/// Swap interval (0 to not v-sync, 1 to v-sync, 2 to v-sync at half refresh rate).
	int swapInterval;
} CocoaGame_GLConfig;

/// A CocoaGame_GLConfig containing default values for each member. You should assign this to your own
/// CocoaGame_GLConfig before customising it (in case new members are added in the future).
extern const CocoaGame_GLConfig COCOAGAME_GLCONFIG_DEFAULTS;

/// Initialise OpenGL. Returns TRUE on success, FALSE on failure.
CocoaGame_Bool CocoaGame_InitGL(const CocoaGame_GLConfig *config);

/// Returns the actual OpenGL configuration that CocoaGame_InitGL() found.
const CocoaGame_GLConfig *CocoaGame_GetGLConfig(void);

typedef struct CocoaGame_GLInfo {
	char *version;
	char *extensions;
	char *vendor;
	char *renderer;
} CocoaGame_GLInfo;

/// Obtains information on the OpenGL driver. If OpenGL is not yet initialised, creates a full-screen context to
/// acquire the information. You must free the returned structure with CocoaGame_FreeGLInfo().
CocoaGame_GLInfo *CocoaGame_GetGLInfo(void);

/// Like CocoaGame_GetGLInfo(), but allows you to specify the OpenGL configuration if a context has to be created.
CocoaGame_GLInfo *CocoaGame_GetGLInfo2(const CocoaGame_GLConfig *fakeConfig);

/// Frees memory allocated by CocoaGame_GetGLInfo2().
void CocoaGame_FreeGLInfo(CocoaGame_GLInfo *info);

//
// Render loop
//

/// Returns TRUE if the application should render a frame, FALSE otherwise.
CocoaGame_Bool CocoaGame_BeginRender(void);

/// Must only be called for a corresponding successful call to CocoaGame_BeginRender(). Don't call if CocoaGame_BeginRender failed.
void CocoaGame_EndRender(void);

/// If CocoaGame_BeginRender() was called successfully but you don't want to display this frame, call this. You 
/// must still call CocoaGame_EndRender().
void CocoaGame_DiscardRender(void);

//
// OpenGL pbuffer support
//

typedef struct CocoaGame_PixelBuffer CocoaGame_PixelBuffer;

/// Create a pixel buffer with the specified texture target type (e.g., TEXTURE_2D), internalFormat (e.g., GL_RGBA)
/// and dimensions. The pixel format is determined from the CocoaGame_GLConfig, but the colourBits and alphaBits
/// fields are ignored. You should assume all other fields in the CocoaGame_GLConfig are read (even if they're not
/// currently).
CocoaGame_PixelBuffer *CocoaGame_CreatePixelBuffer(GLenum textureTarget, GLint internalFormat, GLsizei width, GLsizei height, const CocoaGame_GLConfig *config);

/// Set the pixel buffer to render in to, or NULL to render to the screen.
void CocoaGame_SetTargetPixelBuffer(CocoaGame_PixelBuffer *pbuffer);

/// Set the currently bound texture of the targetPbuffer pixel buffer (which can be NULL, to set a texture of the 
/// global OpenGL context) to the current output of the pbuffer pixel buffer (which must not be NULL). colourBuffer
/// should be either GL_FRONT or GL_BACK.
void CocoaGame_SetTextureImageToPixelBuffer(CocoaGame_PixelBuffer *targetPbuffer, CocoaGame_PixelBuffer *pbuffer, GLenum colourBuffer);

/// Destroy a pixel buffer.
void CocoaGame_DestroyPixelBuffer(CocoaGame_PixelBuffer *pbuffer);

//
// Input constants
//

/// Mouse buttons. The values correspond to those returned by -[NSEvent buttonNumber].
typedef enum CocoaGame_MouseButton {
	COCOAGAME_MOUSEBUTTON_LEFT =  0,
	COCOAGAME_MOUSEBUTTON_RIGHT = 1,
	COCOAGAME_MOUSEBUTTON_MIDDLE = 2
} CocoaGame_MouseButton;

/// Non alphanumeric key codes (the "key" member of CocoaGame_KeyEvent). These map directly to their Cocoa 
/// equivalents (e.g., COCOAGAME_KEY_F1 == NSF1FunctionKey) and are here so you don't need to include Cocoa.h.
enum CocoaGame_Keys {
	COCOAGAME_KEY_ESCAPE = 27,
	COCOAGAME_KEY_UP = 0xf700,
	COCOAGAME_KEY_DOWN = 0xf701,
	COCOAGAME_KEY_LEFT = 0xf702,
	COCOAGAME_KEY_RIGHT = 0xf703,
	COCOAGAME_KEY_F1 = 0xf704,
	COCOAGAME_KEY_F2 = 0xf705,
	COCOAGAME_KEY_F3 = 0xf706,
	COCOAGAME_KEY_F4 = 0xf707,
	COCOAGAME_KEY_F5 = 0xf708,
	COCOAGAME_KEY_F6 = 0xf709,
	COCOAGAME_KEY_F7 = 0xf70a,
	COCOAGAME_KEY_F8 = 0xf70b,
	COCOAGAME_KEY_F9 = 0xf70c,
	COCOAGAME_KEY_F10 = 0xf70d,
	COCOAGAME_KEY_F11 = 0xf70e,
	COCOAGAME_KEY_F12 = 0xf70f,
	COCOAGAME_KEY_F13 = 0xf710,
	COCOAGAME_KEY_F14 = 0xf711,
	COCOAGAME_KEY_F15 = 0xf712,
	COCOAGAME_KEY_F16 = 0xf713,
	COCOAGAME_KEY_F17 = 0xf714,
	COCOAGAME_KEY_F18 = 0xf715,
	COCOAGAME_KEY_F19 = 0xf716,
	COCOAGAME_KEY_F20 = 0xf717,
	COCOAGAME_KEY_F21 = 0xf718,
	COCOAGAME_KEY_F22 = 0xf719,
	COCOAGAME_KEY_F23 = 0xf71a,
	COCOAGAME_KEY_F24 = 0xf71b,
	COCOAGAME_KEY_F25 = 0xf71c,
	COCOAGAME_KEY_F26 = 0xf71d,
	COCOAGAME_KEY_F27 = 0xf71e,
	COCOAGAME_KEY_F28 = 0xf71f,
	COCOAGAME_KEY_F29 = 0xf720,
	COCOAGAME_KEY_F30 = 0xf721,
	COCOAGAME_KEY_F31 = 0xf722,
	COCOAGAME_KEY_F32 = 0xf723,
	COCOAGAME_KEY_F33 = 0xf724,
	COCOAGAME_KEY_F34 = 0xf725,
	COCOAGAME_KEY_F35 = 0xf726,
	COCOAGAME_KEY_INSERT = 0xf727,
	COCOAGAME_KEY_DELETE = 0xf728,
	COCOAGAME_KEY_HOME = 0xf729,
	COCOAGAME_KEY_BEGIN = 0xf72a,
	COCOAGAME_KEY_END = 0xf72b,
	COCOAGAME_KEY_PAGEUP = 0xf72c,
	COCOAGAME_KEY_PAGEDOWN = 0xf72d,
	COCOAGAME_KEY_PRINTSCREEN = 0xf72e,
	COCOAGAME_KEY_SCROLLLOCK = 0xf72f,
	COCOAGAME_KEY_PAUSE = 0xf730,
	COCOAGAME_KEY_SYSREQ = 0xf731,
	COCOAGAME_KEY_BREAK = 0xf732,
	COCOAGAME_KEY_RESET = 0xf733,
	COCOAGAME_KEY_STOP = 0xf734,
	COCOAGAME_KEY_MENU = 0xf735,
	COCOAGAME_KEY_USER = 0xf736,
	COCOAGAME_KEY_SYSTEM = 0xf737,
	COCOAGAME_KEY_PRINT = 0xf738,
	COCOAGAME_KEY_CLEARLINE = 0xf739,
	COCOAGAME_KEY_CLEARDISPLAY = 0xf73a,
	COCOAGAME_KEY_INSERTLINE = 0xf73b,
	COCOAGAME_KEY_DELETELINE = 0xf73c,
	COCOAGAME_KEY_INSERTCHAR = 0xf73d,
	COCOAGAME_KEY_DELETECHAR = 0xf73e,
	COCOAGAME_KEY_PREV = 0xf73f,
	COCOAGAME_KEY_NEXT = 0xf740,
	COCOAGAME_KEY_SELECT = 0xf741,
	COCOAGAME_KEY_EXECUTE = 0xf742,
	COCOAGAME_KEY_UNDO = 0xf743,
	COCOAGAME_KEY_REDO = 0xf744,
	COCOAGAME_KEY_FIND = 0xf745,
	COCOAGAME_KEY_HELP = 0xf746,
	COCOAGAME_KEY_MODESWITCH = 0xf747
};

/// Modifier keys (Shift, Ctrl, etc.)
typedef enum CocoaGame_Modifiers {
	COCOAGAME_MODIFIER_LEFT_SHIFT = 1u<<0,
	COCOAGAME_MODIFIER_RIGHT_SHIFT = 1u<<1,
	COCOAGAME_MODIFIER_LEFT_CTRL = 1u<<2,
	COCOAGAME_MODIFIER_RIGHT_CTRL = 1u<<3,
	COCOAGAME_MODIFIER_LEFT_ALT = 1u<<4,
	COCOAGAME_MODIFIER_RIGHT_ALT = 1u<<5,
	COCOAGAME_MODIFIER_LEFT_COMMAND = 1u<<6,
	COCOAGAME_MODIFIER_RIGHT_COMMAND = 1u<<7,
	
	COCOAGAME_MODIFIER_CAPS_LOCK = 1u<<8,
	
	/// Bit mask to use to test for either left or right shift key
	COCOAGAME_MODIFIER_BOTH_SHIFTS = (COCOAGAME_MODIFIER_LEFT_SHIFT | COCOAGAME_MODIFIER_RIGHT_SHIFT),

	/// Bit mask to use to test for either left or right ctrl key
	COCOAGAME_MODIFIER_BOTH_CTRLS = (COCOAGAME_MODIFIER_LEFT_CTRL | COCOAGAME_MODIFIER_RIGHT_CTRL),

	/// Bit mask to use to test for either left or right alt key
	COCOAGAME_MODIFIER_BOTH_ALTS = (COCOAGAME_MODIFIER_LEFT_ALT | COCOAGAME_MODIFIER_RIGHT_ALT),

	/// Bit mask to use to test for either left or right command key
	COCOAGAME_MODIFIER_BOTH_COMMANDS = (COCOAGAME_MODIFIER_LEFT_COMMAND | COCOAGAME_MODIFIER_RIGHT_COMMAND),
} CocoaGame_Modifiers;

//
// Input events
//

typedef enum CocoaGame_EventType {
	COCOAGAME_EVENT_NONE,
	COCOAGAME_EVENT_MODIFIERS_CHANGED,
	COCOAGAME_EVENT_KEY_DOWN,
	COCOAGAME_EVENT_KEY_UP,
	COCOAGAME_EVENT_CHAR,
	COCOAGAME_EVENT_MOUSE_MOVE,
	COCOAGAME_EVENT_MOUSE_DOWN,
	COCOAGAME_EVENT_MOUSE_UP,
	COCOAGAME_EVENT_MOUSE_SCROLL,
	COCOAGAME_EVENT_APP_DEACTIVATE,
	COCOAGAME_EVENT_APP_ACTIVATE,
} CocoaGame_EventType;

typedef struct CocoaGame_ModifiersEvent {
	CocoaGame_EventType type;
	unsigned int modifiers;
} CocoaGame_ModifiersEvent;

typedef struct CocoaGame_ModifiersChangedEvent {
	CocoaGame_ModifiersEvent base;
	
	unsigned int previousModifiers;
} CocoaGame_ModifiersChangedEvent;

typedef struct CocoaGame_KeyEvent {
	CocoaGame_ModifiersEvent base;
	
	/// This is a character, or one of the special key codes (e.g., NSUpArrowFunctionKey).
	unsigned long key;
	
	/// This is the Carbon key code.
	unsigned short keyCode;
} CocoaGame_KeyEvent;

typedef struct CocoaGame_CharEvent {
	CocoaGame_ModifiersEvent base;
	
	/// The UNICODE character that was generated.
	unsigned long unicode;
} CocoaGame_CharEvent;

typedef struct CocoaGame_MousePositionEvent {
	CocoaGame_ModifiersEvent base;

	int x;

	/// Y coordinate in Cocoa space (1 at the bottom of the window).
	int y;
} CocoaGame_MousePositionEvent;

typedef struct CocoaGame_MouseMoveEvent {
	CocoaGame_MousePositionEvent base;
	
	float deltaX;
	float deltaY;
} CocoaGame_MouseMoveEvent;

typedef struct CocoaGame_MouseButtonEvent {
	CocoaGame_MousePositionEvent base;
	
	CocoaGame_MouseButton button;	 
	int clickCount;
} CocoaGame_MouseButtonEvent;

typedef struct CocoaGame_MouseScrollEvent {
	CocoaGame_ModifiersEvent base;
	
	float scrollX;
	float scrollY;
	
	int cursorX;
	int cursorY;
} CocoaGame_MouseScrollEvent;

typedef union CocoaGame_Event {
	CocoaGame_EventType type;
	CocoaGame_ModifiersEvent modifiers;
	CocoaGame_ModifiersChangedEvent modifiersChanged;
	CocoaGame_KeyEvent key;
	CocoaGame_CharEvent character;
	CocoaGame_MousePositionEvent mousePosition;
	CocoaGame_MouseMoveEvent mouseMove;
	CocoaGame_MouseButtonEvent mouseButton;
	CocoaGame_MouseScrollEvent mouseScroll;
} CocoaGame_Event;

//
// Input handling/event loop
//

/// Returns TRUE if the user has attempted to terminate the application (e.g., they clicked to close the window).
CocoaGame_Bool CocoaGame_WasQuitRequested(void);

/// Allows you to clear or manually set the value returned by CocoaGame_WasQuitRequested().
void CocoaGame_SetQuitRequested(CocoaGame_Bool newValue);

// CocoaGame_ReadEvent() has been removed. Instead, call CocoaGame_Poll() then call CocoaGame_DequeueEvent() in a 
// loop until it returns FALSE.

/// Run the application's run loop, consuming certain events (CocoaGame_ProcessEvent()) and passing all other events
/// to [NSApp sendEvent:] for normal processing.
void CocoaGame_Poll(void);

/// Read the next event from the event queue, which is filled by CocoaGame_Poll() or your own calls to 
/// CocoaGame_QueueEvent(). Returns FALSE if the queue is empty.
CocoaGame_Bool CocoaGame_DequeueEvent(CocoaGame_Event *event);

/// Process an NSEvent. You only need to use this if you wish to override CocoaGame's NSEvent handling. Returns TRUE 
/// if the event has been consumed (in which case a CocoaGame_Event may have been queued), FALSE if the NSEvent 
/// should be processed as normal (e.g., by -[NSApp sendEvent:]). You could place a call to this method in an 
/// overridden -[NSApp sendEvent:] if you're not running your own event loop.
CocoaGame_Bool CocoaGame_ProcessEvent(void *event);

/// Manually queue a CocoaGame_Event to be read by CocoaGame_DequeueEvent().
void CocoaGame_QueueEvent(const CocoaGame_Event *event);

/// Print the contents of a CocoaGame_Event to stderr (even if CocoaGame_Trace() has been disabled).
void CocoaGame_TraceEvent(const CocoaGame_Event *event);

/// Sleep the application for the specified number of seconds, or until an event occurs. You can specify fractions of
/// seconds.
void CocoaGame_Sleep(double seconds);

/// Returns TRUE if the application is active, FALSE if not. This does not tell you whether or not the window is
/// visible and rendering will occur.
CocoaGame_Bool CocoaGame_IsAppActive(void);

/// Specify whether or not repeated keys should generate events. Default is TRUE.
void CocoaGame_SetKeyRepeat(CocoaGame_Bool keyRepeatEnabled);

/// Enable or disable mouse delta mode. This locks the cursor to the centre of the window and only reports deltas.
void CocoaGame_SetMouseDeltaMode(CocoaGame_Bool deltaMode);

CocoaGame_Bool CocoaGame_IsMouseInDeltaMode(void);

/// Show or hide the mouse cursor. This can be called freely (i.e., you don't need to balance hides with shows).
void CocoaGame_SetMouseCursorVisible(CocoaGame_Bool cursorVisible);

/// Returns the last value passed to CocoaGame_SetMouseCursorVisible(). The cursor may actually be visible due to
/// the application being inactive.
CocoaGame_Bool CocoaGame_IsMouseCursorVisible(void);

CocoaGame_Bool CocoaGame_AppOwnsMouse(void);

/// Returns a combination of CocoaGame_Modifiers enumerants indicating the state of the modifier keys after the
/// last event that was processed by CocoaGame_ProcessEvent() (which is usually called for you by CocoaGame_Poll()).
unsigned int CocoaGame_GetModifiers(void);

/// Returns the current position of the mouse cursor, in pixels relative to the bottom-left of the window. Note that
/// the bottom-left of the window is X 0, Y 1.
void CocoaGame_GetMousePosition(int *x, int *y);

/// Move the mouse. Coordinates are in Cocoa coordinates (X 0, Y 1 is the bottom-left of the window).
void CocoaGame_SetMousePosition(int x, int y);

//
// Timers
//

/// Returns the number of seconds since some point in the past, as a double.
double CocoaGame_GetTimer(void);

/// Returns the current value of a looping millisecond timer.
uint32_t CocoaGame_GetMillisecondTimer(void);

#ifdef __cplusplus
}
#endif

#endif
