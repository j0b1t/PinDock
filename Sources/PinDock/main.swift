import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Policy is applied in applicationWillFinishLaunching from Appearance preference
// (menu bar → accessory, window/both → regular Dock icon).
app.run()
