import AppKit

// No storyboard and no main.nib: this is a menu-bar-only agent, so the app
// is assembled by hand and LSUIElement keeps it out of the Dock.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
