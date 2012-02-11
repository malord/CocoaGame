#import "PbufferTestAppDelegate.h"
#import "CocoaGame.h"
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>

@implementation PbufferTestAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{
	(void) aNotification;
	
	// The first pool frees any autoreleased objects created during initialisaiton...
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	// Some example customisations...
	#ifdef NDEBUG
		CocoaGame_SetTraceEnabled(FALSE);
	#endif
	// CocoaGame_SetFadeTime(0.1f);
	
	if (! CocoaGame_Init()) 
		exit(EXIT_FAILURE);
		
	CocoaGame_SetMouseDeltaMode(FALSE);
	CocoaGame_SetMouseCursorVisible(TRUE);
	
	CocoaGame_VideoConfig videoConfig = COCOAGAME_VIDEOCONFIG_DEFAULTS;
	// videoConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN_SET_MODE;
	// videoConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN;
	// videoConfig.disposition = COCOAGAME_VIDEO_FULLSCREEN_WINDOW;
	videoConfig.disposition = COCOAGAME_VIDEO_WINDOW;
	videoConfig.mode.width = 800;
	videoConfig.mode.height = 600;
	videoConfig.mode.bits = 32;
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
	glConfig.msaa = 8;
	glConfig.swapInterval = 1;
	
	if (! CocoaGame_InitGL(&glConfig)) {
		CocoaGame_Shutdown();
		exit(EXIT_FAILURE);
	}
	
	// Create a texure before creating the pixel buffer, so we can confirm the pixel buffer can access it.

	GLuint texture;
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);

	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
	glPixelStorei(GL_PACK_ALIGNMENT, 1);

	static const unsigned char pixels[4][4] = {
		{ 255, 0, 0, 255 }, { 0, 255, 0, 255 },
		{ 0, 0, 255, 255 }, { 255, 255, 0, 255 }
	};
	
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
	
	const int renderTargetWidth = 256;
	const int renderTargetHeight = 256;

	CocoaGame_GLConfig pixelBufferConfig = *CocoaGame_GetGLConfig();
	pixelBufferConfig.depthBits = 24;
	
	CocoaGame_PixelBuffer *pbuffer = CocoaGame_CreatePixelBuffer(GL_TEXTURE_2D, GL_RGBA, renderTargetWidth, renderTargetHeight, &pixelBufferConfig);
	
	if (! pbuffer)
		CocoaGame_AbortWithMessage("Unable to create puffer.", "");
	
	GLuint renderTargetTexture;
	glGenTextures(1, &renderTargetTexture);
	glBindTexture(GL_TEXTURE_2D, renderTargetTexture);
	
	glBindTexture(GL_TEXTURE_2D, 0);

	while (! CocoaGame_WasQuitRequested()) {
		// ...free the initial pool and create a new one for this loop
		[pool release];
		pool = [[NSAutoreleasePool alloc] init];
		
		CocoaGame_Poll();
		
		CocoaGame_Event event;
		
		while (CocoaGame_DequeueEvent(&event)) {
			//CocoaGame_TraceEvent(&event);
			
			if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == COCOAGAME_KEY_ESCAPE) 
				CocoaGame_SetQuitRequested(TRUE);

			if (event.type == COCOAGAME_EVENT_KEY_DOWN && event.key.key == 'W')
				CocoaGame_ToggleFullScreenWindow();
		}
		
		if (! CocoaGame_BeginRender()) {
			// If the application is not visible, and sleep for a bit to cut CPU usage. Note that CocoaGame_Sleep 
			// will interrupt the sleep if an event turns up.
			CocoaGame_Sleep(1);
		} else {
			const CocoaGame_VideoConfig *actualVideoConfig = CocoaGame_GetVideoConfig();

			glViewport(0, 0, actualVideoConfig->mode.width, actualVideoConfig->mode.height);
			
			glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
			glDisable(GL_SCISSOR_TEST);
			glClear(GL_COLOR_BUFFER_BIT);

			#if 1
				glFlush();
				CocoaGame_SetTargetPixelBuffer(pbuffer);

				glViewport(0, 0, renderTargetWidth, renderTargetHeight);
			
				float r = cosf((float) (fmod([[NSDate date] timeIntervalSince1970], 1.0)) * (float) M_PI * 2.0f) * 0.5f + 0.5f;

				glClearColor(r, 0.5f, 0.0f, 1.0f);
				glDisable(GL_SCISSOR_TEST);
				glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
			
				glMatrixMode(GL_PROJECTION);
				glLoadIdentity();
				// gluPerspective(90.0f, (float) renderTargetWidth / (float) renderTargetHeight, 0.1f, 5000.0f);
				gluPerspective(90.0f, CocoaGame_GetAspectRatio(), 0.1f, 5000.0f);
			
				glMatrixMode(GL_MODELVIEW);
				glLoadIdentity();
			
				glTranslatef(0.0f, 0.0f, -12.0f);
				glRotatef((float) fmod([[NSDate date] timeIntervalSince1970], 10.0) * 360.0f * 0.1f, 0.0f, 0.0f, 1.0f);
				
				glEnable(GL_DEPTH_TEST);
				glDepthFunc(GL_LEQUAL);

				glBindTexture(GL_TEXTURE_2D, texture);
				glEnable(GL_TEXTURE_2D);
			
				glBegin(GL_TRIANGLES);
					glTexCoord2f(0.5f, 0.0f);
					// glColor3f(1.0f, 0.0f, 0.0f);
					glVertex3f(0.0f, 10.0f, 0.0f);

					glTexCoord2f(1.0f, 1.0f);
					// glColor3f(0.0f, 1.0f, 0.0f);
					glVertex3f(10.0f, 0.0f, 0.0f);

					glTexCoord2f(0.0f, 1.0f);
					// glColor3f(0.0f, 0.0f, 1.0f);
					glVertex3f(-10.0f, -10.0f, 0.0f);
				glEnd();

				glMatrixMode(GL_MODELVIEW);
				glLoadIdentity();
			
				glTranslatef(0.0f, 0.0f, -12.0f);
				glRotatef((float) fmod([[NSDate date] timeIntervalSince1970], 10.0) * 360.0f * 0.1f, 0.0f, 1.0f, 0.0f);
			
				glBegin(GL_TRIANGLES);
					glTexCoord2f(0.5f, 0.0f);
					// glColor3f(1.0f, 0.0f, 0.0f);
					glVertex3f(0.0f, 10.0f, 0.0f);

					glTexCoord2f(1.0f, 1.0f);
					// glColor3f(0.0f, 1.0f, 0.0f);
					glVertex3f(10.0f, 0.0f, 0.0f);

					glTexCoord2f(0.0f, 1.0f);
					// glColor3f(0.0f, 0.0f, 1.0f);
					glVertex3f(-10.0f, -10.0f, 0.0f);
				glEnd();

				glFlush();
				CocoaGame_SetTargetPixelBuffer(NULL);
			#endif
			
			glBindTexture(GL_TEXTURE_2D, renderTargetTexture);
			CocoaGame_SetTextureImageToPixelBuffer(NULL, pbuffer, GL_FRONT);

			glViewport(0, 0, actualVideoConfig->mode.width, actualVideoConfig->mode.height);
			
			int mouseX, mouseY;
			CocoaGame_GetMousePosition(&mouseX, &mouseY);
			
			glMatrixMode(GL_PROJECTION);
			glLoadIdentity();
			glOrtho(0.0, 1.0, 0.0, 1.0, -1.0, 1.0);
			
			glMatrixMode(GL_MODELVIEW);
			glLoadIdentity();
			
			glEnable(GL_TEXTURE_2D);
			glBindTexture(GL_TEXTURE_2D, renderTargetTexture);
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

			CocoaGame_EndRender();

			// If the application is inactive but still rendering (i.e., it's running in a window), sleep some.
			if (! CocoaGame_IsAppActive())
				CocoaGame_Sleep(1.0 / 16.0); // frame rate will be lower due to swap interval
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
