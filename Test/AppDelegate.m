/*
	Press Tab to toggle the mouse cursor on or off.
	Press Shift+Tab to toggle mouse delta mode on or off (the mode you'd use for an FPS).
	Press W to toggle fullscreen and window.
	Press Esc to exit with an alert panel.
	Press Alt+Esc or F5 to exit without an alert panel.
*/

#import "AppDelegate.h"
#import "CocoaGame.h"
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>

// You can use a reduced size FBO to provide support for lower resolution rendering without changing the video mode.
static const int fboWidth = 256;
static const int fboHeight = 256;

static GLuint fbo;
static GLuint fboTexture;

static double gameTime = 0;

static void InitCocoaGame(void)
{
	// Some example customisations...
	#ifdef NDEBUG
		CocoaGame_SetTraceEnabled(FALSE);
	#endif
	// CocoaGame_SetFadeTime(0.1f);
	
	if (! CocoaGame_Init()) 
		exit(EXIT_FAILURE);
		
	CocoaGame_SetMouseDeltaMode(FALSE);
	CocoaGame_SetMouseCursorVisible(FALSE);
	
	CocoaGame_VideoConfig videoConfig = COCOAGAME_VIDEOCONFIG_DEFAULTS;
	videoConfig.disposition = COCOAGAME_VIDEO_WINDOW;
	//videoConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW;
	videoConfig.mode.width = 800;
	videoConfig.mode.height = 600;
	videoConfig.mode.bits = 32;
	//videoConfig.useLionFullScreenSupport = FALSE;
	videoConfig.title = "CocoaGame Test";
	
	if (! CocoaGame_InitVideo(&videoConfig)) {
		CocoaGame_Shutdown();
		exit(EXIT_FAILURE);
	}
	
	CocoaGame_GLConfig glConfig = COCOAGAME_GLCONFIG_DEFAULTS;
	glConfig.colourBits = 24;
	glConfig.alphaBits = 8;
	glConfig.depthBits = 0;
	glConfig.stencilBits = 0;
	glConfig.msaa = 0;
	glConfig.swapInterval = 1;
	
	if (! CocoaGame_InitGL(&glConfig)) {
		CocoaGame_Shutdown();
		exit(EXIT_FAILURE);
	}
}

static void Draw(void *);
static void InitDraw(void)
{
	glGenFramebuffersEXT(1, &fbo);
	
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
	
	GLuint fboDepthBuffer;
	glGenRenderbuffersEXT(1, &fboDepthBuffer);
	glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, fboDepthBuffer);
	glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT, fboWidth, fboHeight);
	
	glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, fboDepthBuffer);
	
	glGenTextures(1, &fboTexture);
	glBindTexture(GL_TEXTURE_2D, fboTexture);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, fboWidth, fboHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	
	glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, fboTexture, 0);
	
	GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
	if (status != GL_FRAMEBUFFER_COMPLETE_EXT) {
		CocoaGame_Shutdown();
		exit(EXIT_FAILURE);
	}

	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);

	CocoaGame_SetDrawCallback(&Draw, NULL);
}

static void Draw(void *context)
{
	(void) context;
	
	const CocoaGame_VideoConfig *currentVideoConfig = CocoaGame_GetVideoConfig();

	glViewport(0, 0, currentVideoConfig->mode.width, currentVideoConfig->mode.height);
	
	glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
	glDisable(GL_SCISSOR_TEST);
	glClear(GL_COLOR_BUFFER_BIT);

	#if 1
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
		glViewport(0, 0, fboWidth, fboHeight);
	
		float r = cosf((float) (fmod(gameTime, 1.0)) * (float) M_PI * 2.0f) * 0.5f + 0.5f;

		glClearColor(r, 0.5f, 0.0f, 1.0f);
		glDisable(GL_SCISSOR_TEST);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
	
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();
		// gluPerspective(90.0f, (float) fboWidth / (float) fboHeight, 0.1f, 5000.0f);
		gluPerspective(90.0f, CocoaGame_GetAspectRatio(), 0.1f, 5000.0f);
	
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
	
		glTranslatef(0.0f, 0.0f, -12.0f);
		glRotatef((float) fmod(gameTime, 10.0) * 360.0f * 0.1f, 0.0f, 0.0f, 1.0f);
		
		glEnable(GL_DEPTH_TEST);
		glDepthFunc(GL_LEQUAL);
	
		glBegin(GL_TRIANGLES);
			glColor3f(1.0f, 0.0f, 0.0f);
			glVertex3f(0.0f, 10.0f, 0.0f);
			glColor3f(0.0f, 1.0f, 0.0f);
			glVertex3f(10.0f, 0.0f, 0.0f);
			glColor3f(0.0f, 0.0f, 1.0f);
			glVertex3f(-10.0f, -10.0f, 0.0f);
		glEnd();

		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
	
		glTranslatef(0.0f, 0.0f, -12.0f);
		glRotatef((float) fmod(gameTime, 10.0) * 360.0f * 0.1f, 0.0f, 1.0f, 0.0f);
	
		glBegin(GL_TRIANGLES);
			glColor3f(1.0f, 0.0f, 0.0f);
			glVertex3f(0.0f, 10.0f, 0.0f);
			glColor3f(0.0f, 1.0f, 0.0f);
			glVertex3f(10.0f, 0.0f, 0.0f);
			glColor3f(0.0f, 0.0f, 1.0f);
			glVertex3f(-10.0f, -10.0f, 0.0f);
		glEnd();
	
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
	#endif

	glViewport(0, 0, currentVideoConfig->mode.width, currentVideoConfig->mode.height);
	
	int mouseX, mouseY;
	CocoaGame_GetMousePosition(&mouseX, &mouseY);
	
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0.0, 1.0, 0.0, 1.0, -1.0, 1.0);
	
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	
	glEnable(GL_TEXTURE_2D);
	glBindTexture(GL_TEXTURE_2D, fboTexture);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
	
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
	
	glBegin(GL_QUADS);
		glTexCoord2f(0.0f, 0.0f);
		glVertex3f(0.0f, 1.0f, 0.0f);

		glTexCoord2f(1.0f, 0.0f);
		glVertex3f(1.0f, 1.0f, 0.0f);

		glTexCoord2f(1.0f, 1.0f);
		glVertex3f(1.0f, 0.0f, 0.0f);

		glTexCoord2f(0.0f, 1.0f);
		glVertex3f(0.0f, 0.0f, 0.0f);
	glEnd();

	glDisable(GL_TEXTURE_2D);

	glEnable(GL_SCISSOR_TEST);
	glScissor(mouseX - 16, mouseY - 16, 32, 32);
	glClearColor(1.0f, 1.0f, 1.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glDisable(GL_SCISSOR_TEST);
}

static void ProcessEvents(void)
{
	CocoaGame_Poll();
	
	CocoaGame_Event event;
	while (CocoaGame_DequeueEvent(&event)) {
		//CocoaGame_TraceEvent(&event);
		
		// Tab key to toggle the cursor visibility
		if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == '\t') 
			CocoaGame_SetMouseCursorVisible(! CocoaGame_IsMouseCursorVisible());

		// Shift+Tab to switch to delta moude
		if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == '\x19') 
			CocoaGame_SetMouseDeltaMode(! CocoaGame_IsMouseInDeltaMode());
		
		if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == 'M') {
			int x, y;
			CocoaGame_GetMousePosition(&x, &y);
			CocoaGame_SetMousePosition(x, y);
		}

		if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == COCOAGAME_KEY_ESCAPE) 
			CocoaGame_AbortWithMessage("You pressed Escape!", "This is what it looks like when CocoaGame_AbortWithMessage is called!");
		
		if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == COCOAGAME_KEY_F5)
			CocoaGame_SetQuitRequested(TRUE);
		
		if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == 'W')
			CocoaGame_ToggleFullScreenWindow();
	}
}

static void Update(void)
{
	gameTime = [[NSDate date] timeIntervalSince1970];
}

@implementation AppDelegate

// The game loop goes here.
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{
	(void) aNotification;
	
	// The first pool frees any autoreleased objects created during initialisation...
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	InitCocoaGame();
	InitDraw();
	
	while (! CocoaGame_WasQuitRequested()) {
		// ...free the initial pool and create a new one for this loop.
		[pool release];
		pool = [[NSAutoreleasePool alloc] init];
		
		ProcessEvents();
		Update();
		
		if (! CocoaGame_BeginRender()) {
			// If the application is not visible, and sleep for a bit to cut CPU usage. Note that CocoaGame_Sleep 
			// will interrupt the sleep if an event turns up.
			CocoaGame_Sleep(1);
		} else {
			// Draw may occasionally be called for us.
			Draw(NULL);

			CocoaGame_EndRender();

			// If the application is inactive but still rendering (i.e., it's running in a window), sleep some.
			if (! CocoaGame_IsAppActive())
				CocoaGame_Sleep(1.0 / 16.0);
		}
	}

	CocoaGame_Shutdown();
	[pool release];
	exit(EXIT_SUCCESS);
}

- (void)applicationWillTerminate:(NSNotification *)aNotification 
{
	(void) aNotification;

	CocoaGame_Shutdown();
}

@end
