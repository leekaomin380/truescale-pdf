import SwiftUI

@main
struct TrueScalePDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showsOpenSourceComponents = false

    var body: some Scene {
        WindowGroup("Epub 转 PDF") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $showsOpenSourceComponents) {
                    OpenSourceComponentsView()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("开源组件…") {
                    showsOpenSourceComponents = true
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
