import AppKit

@main
struct AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // weak reference: keep the delegate alive for the app's lifetime
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
