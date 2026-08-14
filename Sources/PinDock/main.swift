import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory = no Dock icon; settings window still works when opened from menu bar.
app.setActivationPolicy(.accessory)
app.run()
