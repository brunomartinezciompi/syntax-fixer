import AppKit
import SwiftUI

/// Logs to ~/Library/Logs/SyntaxFixer.log to diagnose unexpected shutdowns.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SyntaxFixer.log")

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = Data("[\(stamp)] \(message)\n".utf8)
        FileHandle.standardError.write(line)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(line)
        try? handle.close()
    }
}

/// Floating panel that can take keyboard focus without being a main window.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escape in an NSPanel fires `cancelOperation:`, which closes the window.
    /// Here that would quit the whole app, so we neutralize it.
    override func cancelOperation(_ sender: Any?) {
        Log.write("escape ignored (cancelOperation)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no switcher entry: just the floating panel.
        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: PanelLayout.baseHeight),
            styleMask: [.titled, .fullSizeContentView, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "syntax"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Always on top, on every desktop, and never hides when it loses focus.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 320, height: 150)
        panel.maxSize = NSSize(width: 900, height: PanelLayout.baseHeight + PanelLayout.maxResultHeight + 40)
        panel.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 1)

        panel.contentView = NSHostingView(rootView: ContentView(
            onResultHeightChange: { [weak self] height in
                self?.fitToResult(height: height)
            }
        ))

        // Remembers where you left it; first run goes top-right.
        panel.setFrameAutosaveName("SyntaxFixerPanel")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.maxY - panel.frame.height - 24
            ))
        }

        // The autosave also stores the height it had with the previous response
        // on screen: we keep only the position and return to the base height.
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = PanelLayout.baseHeight
        frame.size.width = max(430, frame.size.width)
        frame.origin.y = top - frame.size.height
        panel.setFrame(frame, display: false)

        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        Log.write("app ready, panel visible at \(panel.frame)")
    }

    /// We only quit via the × or ⌘Q, never because a window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The panel never closes: that would leave the app alive but invisible.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Log.write("windowShouldClose intercepted — not closing")
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.write("terminating. stack:\n" + Thread.callStackSymbols.prefix(12).joined(separator: "\n"))
    }

    /// Clicking the Dock icon while the app runs: brings the panel to the front.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    /// Fits the panel height to the response, growing downward so the top
    /// edge stays put.
    private func fitToResult(height: CGFloat) {
        guard let panel else { return }

        let extra = height > 0 ? min(height, PanelLayout.maxResultHeight) + 1 : 0
        var target = PanelLayout.baseHeight + extra
        if let screen = panel.screen ?? NSScreen.main {
            target = min(target, screen.visibleFrame.height - 40)
        }

        var frame = panel.frame
        guard abs(frame.height - target) > 1 else { return }
        frame.origin.y += frame.height - target
        frame.size.height = target
        panel.setFrame(frame, display: true, animate: true)
    }

    private func showPanel() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Minimal menu so ⌘Q, ⌘C, ⌘V and ⌘A work inside the panel.
    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit syntax", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
