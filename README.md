About
=====

CocoaGame simplifies the creation of OpenGL games on the Mac. Although written in Objective C, CocoaGame is accessed entirely through C, making it easier to integrate in to an existing game.

CocoaGame provides the following services:

- Video mode switching (including Valve style fullscreen, where you can switch applications, and Lion fullscreen support).

- OpenGL configuration (including MSAA support).

- An abstracted input event framework provides support for mouse and keyboard input without having to parse NSEvents.

- Mouse locking, for first person shooters or other games where mouse movements do not move the mouse cursor.

- OpenGL pbuffer support (in case you're supporting really old Macs with flakey framebuffer objects).

CocoaGame plays nice with Cocoa, allowing you to set up menus and utility windows and integrate third-party Cocoa components, such as Sparkle.

CocoaGame has shipped in commercial games and is licensed under a liberal zlib like license.

Sample Project(s)
-----------------

The Test folder contains a simple demonstration project:

- Press Tab to toggle the mouse cursor on or off.
- Press Shift+Tab to toggle mouse delta mode (mouse lock) on or off.
- Press W to toggle fullscreen and window.
- Press Esc to exit with an alert panel.
- Press Alt+Esc or F5 to exit without an alert panel.

There's also a PbufferTest folder containing an example that uses pbuffers.

How to use CocoaGame
--------------------

### Option 1

- Create a non-document-based Cocoa project in Xcode.

- Add CocoaGame.m/.h to the project.

- Add OpenGL.framework to the project.

- Create a new NSObject-derived Objective-C class called AppDelegate (or copy AppDelegate.m/.h from Test).

- Open MainMenu.xib and create a plain NSObject, then change its class to AppDelegate.

- Still in MainMenu.xib, Ctrl+Drag from the Application object to your instantiated AppDelegate and set the AppDelegate as the Application's delegate outlet.

- Put your game loop in the applicationDidFinishLaunching method of your AppDelegate class.

### Option 2 ###

Duplicate the Test folder!

