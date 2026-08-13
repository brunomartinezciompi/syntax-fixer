import AppKit
import SwiftUI

/// Log a ~/Library/Logs/SyntaxFixer.log para diagnosticar cierres inesperados.
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

/// Panel flotante que puede recibir foco de teclado sin ser una ventana principal.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escape en un NSPanel dispara `cancelOperation:`, que cierra la ventana.
    /// Acá eso equivaldría a cerrar la app entera, así que lo neutralizamos.
    override func cancelOperation(_ sender: Any?) {
        Log.write("escape ignorado (cancelOperation)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sin icono en el Dock ni en el switcher: sólo el panel flotante.
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

        // Siempre encima, en todos los escritorios, y no se esconde al perder foco.
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

        // Recuerda dónde lo dejaste; la primera vez, arriba a la derecha.
        panel.setFrameAutosaveName("SyntaxFixerPanel")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.maxY - panel.frame.height - 24
            ))
        }

        // El autosave también guarda el alto que tenía con la respuesta anterior
        // en pantalla: conservamos sólo la posición y volvemos al alto base.
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
        Log.write("app lista, panel visible en \(panel.frame)")
    }

    /// Sólo se sale por la × o por ⌘Q, nunca porque una ventana se cerró.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// El panel no se cierra: quedaría la app viva pero invisible.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Log.write("windowShouldClose interceptado — no se cierra")
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.write("terminando. stack:\n" + Thread.callStackSymbols.prefix(12).joined(separator: "\n"))
    }

    /// Click en el icono del Dock cuando la app ya corre: trae el panel al frente.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    /// Ajusta el alto del panel al de la respuesta, creciendo hacia abajo
    /// para que el borde superior no se mueva.
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

    /// Menú mínimo para que ⌘Q, ⌘C, ⌘V y ⌘A funcionen dentro del panel.
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
