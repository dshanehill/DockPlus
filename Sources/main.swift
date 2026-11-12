// Dock+ — a Dock button that opens a Dock-style bubble of apps above it.
// The same app is copied for each folder; the folder's name, symbol and colours live in Info.plist,
// and its list of apps lives in its own preferences.
import AppKit
import SwiftUI
import ApplicationServices
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

// MARK: - Folder settings

let info = Bundle.main.infoDictionary ?? [:]
let folderName = info["CFBundleName"] as? String ?? "Folder"
let folderSymbol = info["FolderSymbol"] as? String ?? "square.grid.2x2.fill"
let folderColors = info["FolderColors"] as? [String] ?? ["#8A5CFF", "#2F9BFF"]
let defaultApps = info["DefaultApps"] as? [String] ?? []
let store = UserDefaults.standard
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Dock+.log")

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) [\(folderName)] \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

func hexColor(_ s: String) -> NSColor {
    var h = s.trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

// MARK: - App list

func loadApps() -> [URL] {
    if store.array(forKey: "apps") == nil {
        let urls = defaultApps.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        store.set(urls.map { $0.path }, forKey: "apps")
    }
    return (store.stringArray(forKey: "apps") ?? [])
        .map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
}
func saveApps(_ urls: [URL]) { store.set(urls.map { $0.path }, forKey: "apps") }
func addApps(_ new: [URL]) {
    var list = loadApps()
    for u in new where u.pathExtension == "app" && !list.contains(where: { $0.path == u.path }) && u.path != Bundle.main.bundlePath {
        list.append(u)
    }
    saveApps(list)
}
func appName(_ url: URL) -> String {
    let n = FileManager.default.displayName(atPath: url.path)
    return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
}

// MARK: - Dock-style button icon

func tileIcon(symbol: String, colors: [String]) -> NSImage {
    let s: CGFloat = 1024
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
    hexColor(colors.first ?? "#888888").setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    let cs = colors.map(hexColor)
    (NSGradient(colors: cs.count > 1 ? cs : [cs[0], cs[0]]) ?? NSGradient(starting: .gray, ending: .darkGray)!).draw(in: path, angle: -60)
    NSColor.white.withAlphaComponent(0.28).setStroke(); path.lineWidth = 5; path.stroke()
    let cfg = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = sym.size
        let scale = min(470 / sz.width, 470 / sz.height)
        let w = sz.width * scale, h = sz.height * scale
        sym.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    img.unlockFocus()
    return img
}

func writeICNS(_ image: NSImage, to url: URL) {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let iconset = temporary.appendingPathComponent("AppIcon.iconset")
    do {
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                    let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
                }
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["--convert", "icns", "--output", url.path, iconset.path]
        try process.run(); process.waitUntilExit()
    } catch { log("Could not write folder icon: \(error.localizedDescription)") }
}

// MARK: - Dock helpers

func runTool(_ path: String, _ args: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    try? p.run(); p.waitUntilExit()
}
func isInDock(_ bundle: URL) -> Bool {
    let dock = UserDefaults(suiteName: "com.apple.dock")
    let apps = dock?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
    let want = bundle.standardizedFileURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return apps.contains { item in
        let s = (((item["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])?["_CFURLString"] as? String) ?? ""
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == want
    }
}
/// Pins a folder button to the Dock. Returns true if the Dock had to restart.
@discardableResult
func pinToDock(_ bundle: URL) -> Bool {
    if isInDock(bundle) { return false }
    let entry = "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>\(bundle.standardizedFileURL.absoluteString)</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
    runTool("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array-add", entry])
    runTool("/usr/bin/killall", ["Dock"])
    log("pinned to Dock: \(bundle.path)")
    return true
}

// MARK: - Dock geometry

struct DockInfo {
    var edge: ArrowEdge
    var reach: CGFloat      // how far the Dock can ever stick out from the screen edge, magnified
    var tileHalf: CGFloat   // half the width of the largest the button can get
}

func readDock(screen: NSScreen) -> DockInfo {
    let d = UserDefaults(suiteName: "com.apple.dock")
    d?.synchronize()
    let orientation = d?.string(forKey: "orientation") ?? "bottom"
    let tile = CGFloat((d?.object(forKey: "tilesize") as? NSNumber)?.doubleValue ?? 48)
    let magnify = d?.bool(forKey: "magnification") ?? false
    let large = CGFloat((d?.object(forKey: "largesize") as? NSNumber)?.doubleValue ?? 128)
    let biggest = magnify ? max(tile, large) : tile
    let edge: ArrowEdge = orientation == "left" ? .left : (orientation == "right" ? .right : .bottom)
    // Dock padding under/around the icons plus breathing room, so the bubble always clears it.
    var reach = biggest + 22
    // The normal (unmagnified) Dock may already be taller than that, e.g. with indicators.
    let vf = screen.visibleFrame, sf = screen.frame
    switch edge {
    case .bottom: reach = max(reach, vf.minY - sf.minY + 4)
    case .left: reach = max(reach, vf.minX - sf.minX + 4)
    case .right: reach = max(reach, sf.maxX - vf.maxX + 4)
    case .none: break
    }
    let geometry = UserDefaults(suiteName: "org.dockplusGeometry")
    geometry?.synchronize()
    if Date().timeIntervalSince1970 - (geometry?.double(forKey: "time") ?? 0) < 0.5 {
        reach = max(reach, CGFloat(geometry?.double(forKey: "reach") ?? 0) + 4)
    }
    return DockInfo(edge: edge, reach: reach, tileHalf: biggest / 2 + 10)
}

// MARK: - Bubble shape

enum ArrowEdge { case bottom, left, right, none }
var hoverDockReach: CGFloat?
let arrowH: CGFloat = 13, arrowW: CGFloat = 28, cornerR: CGFloat = 20

func bubblePath(size: NSSize, edge: ArrowEdge, arrowAt a: CGFloat) -> NSBezierPath {
    var b = NSRect(origin: .zero, size: size)
    switch edge {
    case .bottom: b.origin.y += arrowH; b.size.height -= arrowH
    case .left: b.origin.x += arrowH; b.size.width -= arrowH
    case .right: b.size.width -= arrowH
    case .none: break
    }
    let r = cornerR, p = NSBezierPath()
    p.move(to: NSPoint(x: b.minX + r, y: b.minY))
    if edge == .bottom {
        p.line(to: NSPoint(x: a - arrowW / 2, y: b.minY))
        p.line(to: NSPoint(x: a, y: b.minY - arrowH))
        p.line(to: NSPoint(x: a + arrowW / 2, y: b.minY))
    }
    p.line(to: NSPoint(x: b.maxX - r, y: b.minY))
    p.appendArc(from: NSPoint(x: b.maxX, y: b.minY), to: NSPoint(x: b.maxX, y: b.minY + r), radius: r)
    if edge == .right {
        p.line(to: NSPoint(x: b.maxX, y: a - arrowW / 2))
        p.line(to: NSPoint(x: b.maxX + arrowH, y: a))
        p.line(to: NSPoint(x: b.maxX, y: a + arrowW / 2))
    }
    p.line(to: NSPoint(x: b.maxX, y: b.maxY - r))
    p.appendArc(from: NSPoint(x: b.maxX, y: b.maxY), to: NSPoint(x: b.maxX - r, y: b.maxY), radius: r)
    p.line(to: NSPoint(x: b.minX + r, y: b.maxY))
    p.appendArc(from: NSPoint(x: b.minX, y: b.maxY), to: NSPoint(x: b.minX, y: b.maxY - r), radius: r)
    if edge == .left {
        p.line(to: NSPoint(x: b.minX, y: a + arrowW / 2))
        p.line(to: NSPoint(x: b.minX - arrowH, y: a))
        p.line(to: NSPoint(x: b.minX, y: a - arrowW / 2))
    }
    p.line(to: NSPoint(x: b.minX, y: b.minY + r))
    p.appendArc(from: NSPoint(x: b.minX, y: b.minY), to: NSPoint(x: b.minX + r, y: b.minY), radius: r)
    p.close()
    return p
}

final class BorderView: NSView {
    var path = NSBezierPath()
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - App tile inside the bubble

let tileW: CGFloat = 104, tileH: CGFloat = 112, iconSize: CGFloat = 68

final class Tile: NSView {
    let url: URL?
    let onClick: () -> Void
    let onRemove: (() -> Void)?
    private var hover = false { didSet { needsDisplay = true } }

    init(url: URL?, icon: NSImage, title: String, onClick: @escaping () -> Void, onRemove: (() -> Void)?) {
        self.url = url; self.onClick = onClick; self.onRemove = onRemove
        super.init(frame: NSRect(x: 0, y: 0, width: tileW, height: tileH))
        let iv = NSImageView(frame: NSRect(x: (tileW - iconSize) / 2, y: tileH - iconSize - 8, width: iconSize, height: iconSize))
        iv.image = icon; iv.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iv)
        let label = NSTextField(wrappingLabelWithString: title)
        label.frame = NSRect(x: 4, y: 2, width: tileW - 8, height: tileH - iconSize - 14)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        if onRemove != nil {
            let m = NSMenu()
            let open = NSMenuItem(title: "Open \(title)", action: #selector(menuOpen), keyEquivalent: ""); open.target = self
            let rm = NSMenuItem(title: "Remove from \(folderName)", action: #selector(menuRemove), keyEquivalent: ""); rm.target = self
            m.addItem(open); m.addItem(.separator()); m.addItem(rm)
            menu = m
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick() } }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    @objc func menuOpen() { onClick() }
    @objc func menuRemove() { onRemove?() }

    override func draw(_ dirtyRect: NSRect) {
        guard hover else { return }
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 12, yRadius: 12).fill()
    }
}

// MARK: - Bubble window

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.closeBubble() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var stopRequested = false
    var managerWindow: NSWindow?
    var hoverCoordinator: HoverCoordinator?
    var panel: BubblePanel?
    var clickMonitor: Any?
    var hoverTimer: Timer?
    var lastAnchor: NSPoint?
    var launchedAt = Date()
    var lastClosed = Date.distantPast

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard info["DockPlusManager"] as? Bool == true, !stopRequested else { return .terminateNow }
        // Allow system-initiated logout and shutdown to finish.
        if NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: 0x7768793F) != nil { return .terminateNow }
        closeManagerWindow(nil)
        return .terminateCancel
    }

    @objc func closeManagerWindow(_ sender: Any?) {
        managerWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func stopSwitchingAndQuit(_ sender: Any?) {
        stopRequested = true
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === managerWindow { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        if info["DockPlusManager"] as? Bool == true { showManager(); return }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(hoverRequest(_:)), name: NSNotification.Name("org.dockplus.switch"), object: nil)
        buildMainMenu()
        let icon = tileIcon(symbol: folderSymbol, colors: folderColors)
        NSApp.applicationIconImage = icon
        let anchor = NSEvent.mouseLocation
        let restarted = pinToDock(Bundle.main.bundleURL)
        log("started")
        if CommandLine.arguments.contains("--hover-launch") { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (restarted ? 1.8 : 0.05)) {
            self.showBubble(anchor: anchor)
        }
    }

    @objc func hoverRequest(_ note: Notification) {
        guard let target = note.userInfo?["id"] as? String else { return }
        if target != Bundle.main.bundleIdentifier { closeBubble(animated: false); return }
        hoverDockReach = (note.userInfo?["reach"] as? NSNumber).map { CGFloat($0.doubleValue) }
        if panel?.isVisible == true { return }
        let anchor: NSPoint
        if let x = note.userInfo?["x"] as? Double, let y = note.userInfo?["y"] as? Double { anchor = NSPoint(x: x, y: y) }
        else { anchor = NSEvent.mouseLocation }
        showBubble(anchor: anchor)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if info["DockPlusManager"] as? Bool == true { showManager(); return false }
        // Clicking the Dock button while the bubble is open closes it (the click itself already closed it).
        if let p = panel, p.isVisible { closeBubble() }
        else if Date().timeIntervalSince(lastClosed) > 0.5 { showBubble(anchor: NSEvent.mouseLocation) }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Apps dropped on the Dock button get added.
        addApps(urls)
        log("added \(urls.map { $0.lastPathComponent })")
        if Date().timeIntervalSince(launchedAt) > 1 { showBubble(anchor: NSEvent.mouseLocation) }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        for u in loadApps() {
            let it = NSMenuItem(title: appName(u), action: #selector(openFromMenu(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = u
            let ic = NSWorkspace.shared.icon(forFile: u.path); ic.size = NSSize(width: 16, height: 16); it.image = ic
            m.addItem(it)
        }
        m.addItem(.separator())
        let add = NSMenuItem(title: "Add App to \(folderName)…", action: #selector(addAppsDialog), keyEquivalent: ""); add.target = self
        let nf = NSMenuItem(title: "New Folder…", action: #selector(newFolderDialog), keyEquivalent: ""); nf.target = self
        m.addItem(add); m.addItem(nf)
        return m
    }

    func buildMainMenu() {
        let main = NSMenu(); let item = NSMenuItem(); main.addItem(item)
        let sub = NSMenu()
        let add = NSMenuItem(title: "Add App to \(folderName)…", action: #selector(addAppsDialog), keyEquivalent: "o"); add.target = self
        let nf = NSMenuItem(title: "New Folder…", action: #selector(newFolderDialog), keyEquivalent: "n"); nf.target = self
        sub.addItem(add); sub.addItem(nf); sub.addItem(.separator())
        sub.addItem(NSMenuItem(title: "Quit \(folderName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = sub
        NSApp.mainMenu = main
    }

    func isOverDock(_ p: NSPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        return !NSMouseInRect(p, s.visibleFrame, false)
    }

    @objc func openFromMenu(_ sender: NSMenuItem) { if let u = sender.representedObject as? URL { launch(u) } }

    func launch(_ url: URL) {
        closeBubble()
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, err in
            if let err = err { log("could not open \(url.lastPathComponent): \(err.localizedDescription)") }
        }
    }

    // MARK: Bubble

    func showBubble(anchor: NSPoint?) {
        closeBubble(animated: false)
        lastClosed = .distantPast
        let apps = loadApps()
        let count = max(1, apps.count)
        let cols = max(1, min(5, count))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let pad: CGFloat = 14, header: CGFloat = 40
        let bodyW = CGFloat(cols) * tileW + pad * 2
        let bodyH = CGFloat(rows) * tileH + pad + header

        // Work out where the Dock is and where the bubble should point.
        let a = anchor ?? lastAnchor
        let screen = NSScreen.screens.first(where: { a != nil && NSMouseInRect(a!, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame, sf = screen.frame
        let dock = readDock(screen: screen)
        let edge = dock.edge
        let fromDock = a.map { isOverDock($0) || dockZone(dock, sf).contains($0) } ?? false
        let pt: NSPoint
        if let a = a, fromDock { pt = a }
        else {
            switch edge {
            case .left: pt = NSPoint(x: sf.minX, y: sf.midY)
            case .right: pt = NSPoint(x: sf.maxX, y: sf.midY)
            default: pt = NSPoint(x: sf.midX, y: sf.minY)
            }
        }
        lastAnchor = pt

        var size = NSSize(width: bodyW, height: bodyH)
        var origin = NSPoint.zero
        var arrowAt: CGFloat = 0
        switch edge {
        case .bottom, .none:
            size.height += arrowH
            origin.y = min(sf.minY + dock.reach, vf.maxY - size.height)
            origin.x = min(max(pt.x - size.width / 2, vf.minX + 8), vf.maxX - size.width - 8)
            arrowAt = min(max(pt.x - origin.x, cornerR + arrowW / 2), size.width - cornerR - arrowW / 2)
        case .left:
            size.width += arrowH
            origin.x = sf.minX + dock.reach
            origin.y = min(max(pt.y - size.height / 2, vf.minY + 8), vf.maxY - size.height - 8)
            arrowAt = min(max(pt.y - origin.y, cornerR + arrowW / 2), size.height - cornerR - arrowW / 2)
        case .right:
            size.width += arrowH
            origin.x = sf.maxX - dock.reach - size.width
            origin.y = min(max(pt.y - size.height / 2, vf.minY + 8), vf.maxY - size.height - 8)
            arrowAt = min(max(pt.y - origin.y, cornerR + arrowW / 2), size.height - cornerR - arrowW / 2)
        }

        let p = BubblePanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.setAccessibilityLabel(folderName)

        let shape = bubblePath(size: size, edge: edge, arrowAt: arrowAt)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let fx = NSVisualEffectView(frame: container.bounds)
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = NSImage(size: size, flipped: false) { _ in NSColor.black.setFill(); shape.fill(); return true }
        container.addSubview(fx)

        // Content area (the bubble body, without the pointer).
        var body = NSRect(origin: .zero, size: NSSize(width: bodyW, height: bodyH))
        if edge == .bottom || edge == .none { body.origin.y = arrowH }
        if edge == .left { body.origin.x = arrowH }

        let title = NSTextField(labelWithString: folderName)
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.frame = NSRect(x: body.minX, y: body.maxY - header + 8, width: bodyW, height: 24)
        container.addSubview(title)

        let tiles: [Tile] = apps.enumerated().map { (i, u) in
            let ic = NSWorkspace.shared.icon(forFile: u.path); ic.size = NSSize(width: 256, height: 256)
            return Tile(url: u, icon: ic, title: appName(u), onClick: { [weak self] in self?.launch(u) }, onRemove: { [weak self] in
                var list = loadApps(); list.removeAll { $0.path == u.path }; saveApps(list)
                log("removed \(u.lastPathComponent)")
                self?.showBubble(anchor: self?.lastAnchor)
                _ = i
            })
        }
        for (i, t) in tiles.enumerated() {
            let r = i / cols, c = i % cols
            t.setFrameOrigin(NSPoint(x: body.minX + pad + CGFloat(c) * tileW,
                                     y: body.maxY - header - CGFloat(r + 1) * tileH))
            container.addSubview(t)
        }
        if apps.isEmpty {
            let message = NSTextField(labelWithString: "No apps")
            message.textColor = .secondaryLabelColor
            message.alignment = .center
            message.frame = NSRect(x: body.minX + pad, y: body.minY + 45, width: bodyW - pad * 2, height: 24)
            container.addSubview(message)
        }

        let border = BorderView(frame: container.bounds)
        border.path = bubblePath(size: NSSize(width: size.width - 1, height: size.height - 1), edge: edge, arrowAt: arrowAt)
        border.path.transform(using: AffineTransform(translationByX: 0.5, byY: 0.5))
        container.addSubview(border)

        p.contentView = container
        panel = p

        // Fade and rise into place, like the Dock's own pop-ups.
        let final = p.frame
        let start = final
        // Keep the bubble anchored while fading in.
        p.alphaValue = 0
        p.setFrame(start, display: false)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.animator().setFrame(final, display: true)
        }

        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("org.dockplus.opened"), object: Bundle.main.bundleIdentifier, userInfo: nil, deliverImmediately: true)
        log("bubble shown, \(apps.count) apps, edge \(edge), at \(Int(final.minX)),\(Int(final.minY)) size \(Int(final.width))x\(Int(final.height))")
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeBubble()
        }

        // Hover zone = the bubble + the strip running from the bubble's pointer down to the Dock button.
        let bubbleZone = final.insetBy(dx: -6, dy: -6)
        var buttonZone = NSRect.zero
        if fromDock {
            switch edge {
            case .bottom, .none:
                buttonZone = NSRect(x: pt.x - dock.tileHalf, y: sf.minY, width: dock.tileHalf * 2, height: final.minY - sf.minY + 8)
            case .left:
                buttonZone = NSRect(x: sf.minX, y: pt.y - dock.tileHalf, width: final.minX - sf.minX + 8, height: dock.tileHalf * 2)
            case .right:
                buttonZone = NSRect(x: final.maxX - 8, y: pt.y - dock.tileHalf, width: sf.maxX - final.maxX + 8, height: dock.tileHalf * 2)
            }
        }
        var outsideSince: Date?
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, self.panel != nil else { return }
            if NSApp.modalWindow != nil || p.attachedSheet != nil { outsideSince = nil; return }
            let m = NSEvent.mouseLocation
            if bubbleZone.contains(m) || buttonZone.contains(m) { outsideSince = nil; return }
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) > 0.3 { self.closeBubble() }
        }
    }

    func dockZone(_ dock: DockInfo, _ sf: NSRect) -> NSRect {
        switch dock.edge {
        case .left: return NSRect(x: sf.minX, y: sf.minY, width: dock.reach, height: sf.height)
        case .right: return NSRect(x: sf.maxX - dock.reach, y: sf.minY, width: dock.reach, height: sf.height)
        default: return NSRect(x: sf.minX, y: sf.minY, width: sf.width, height: dock.reach)
        }
    }

    func closeBubble(animated: Bool = true, why: String = "") {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        hoverTimer?.invalidate(); hoverTimer = nil
        guard let p = panel else { return }
        panel = nil
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("org.dockplus.closed"), object: Bundle.main.bundleIdentifier, userInfo: nil, deliverImmediately: true)
        lastClosed = Date()
        if !animated { p.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { closeBubble() }
    }

    // MARK: Editing

    @objc func addAppsDialog() {
        closeBubble(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        let op = NSOpenPanel()
        op.title = "Add apps to \(folderName)"
        op.prompt = "Add"
        op.allowedContentTypes = [.application]
        op.allowsMultipleSelection = true
        op.canChooseDirectories = false
        op.directoryURL = URL(fileURLWithPath: "/Applications")
        if op.runModal() == .OK {
            addApps(op.urls)
            log("added \(op.urls.map { $0.lastPathComponent })")
        }
        showBubble(anchor: lastAnchor)
    }

    let symbolChoices: [(String, String, [String])] = [
        ("Sparkles (AI)", "sparkles", ["#8A5CFF", "#2F9BFF"]),
        ("Game Controller (Games)", "gamecontroller.fill", ["#FF4F6D", "#FF9A3C"]),
        ("Briefcase (Work)", "briefcase.fill", ["#3A7BD5", "#00D2FF"]),
        ("Chat Bubbles (Messaging)", "bubble.left.and.bubble.right.fill", ["#20C46B", "#7BE495"]),
        ("Film (Video)", "film.fill", ["#E0473C", "#F7797D"]),
        ("Music Note (Audio)", "music.note", ["#FC5C7D", "#6A82FB"]),
        ("Paintbrush (Creative)", "paintbrush.pointed.fill", ["#F7971E", "#FFD200"]),
        ("Globe (Web)", "globe", ["#1488CC", "#2B32B2"]),
        ("Hammer (Tools)", "hammer.fill", ["#606C88", "#3F4C6B"]),
        ("Dollar Sign (Money)", "dollarsign.circle.fill", ["#11998E", "#38EF7D"]),
        ("Star (Favorites)", "star.fill", ["#F2994A", "#F2C94C"]),
    ]

    @objc func newFolderDialog() {
        closeBubble(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Give the folder a name and pick a symbol. It will get its own button on your Dock."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 64))
        let name = NSTextField(frame: NSRect(x: 0, y: 36, width: 300, height: 26))
        name.placeholderString = "Folder name, for example Games"
        name.font = .systemFont(ofSize: 15)
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        for c in symbolChoices {
            pop.addItem(withTitle: c.0)
            pop.lastItem?.image = NSImage(systemSymbolName: c.1, accessibilityDescription: nil)
        }
        box.addSubview(name); box.addSubview(pop)
        alert.accessoryView = box
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let clean = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !clean.isEmpty else { return }
        let choice = symbolChoices[max(0, pop.indexOfSelectedItem)]
        createFolder(named: clean, symbol: choice.1, colors: choice.2)
    }

    func createFolder(named name: String, symbol: String, colors: [String]) {
        let fm = FileManager.default
        let src = info["DockPlusManager"] as? Bool == true
            ? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/FolderTemplate.app")
            : Bundle.main.bundleURL
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let dest = directory.appendingPathComponent("\(name).app")
        if fm.fileExists(atPath: dest.path) {
            let a = NSAlert(); a.messageText = "There is already an app called \(name)."; a.runModal(); return
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dest)
            try? fm.removeItem(at: dest.appendingPathComponent("Icon\r"))
            let plistURL = dest.appendingPathComponent("Contents/Info.plist")
            let data = try Data(contentsOf: plistURL)
            var d = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
            let slug = name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            d["CFBundleName"] = name
            d["CFBundleDisplayName"] = name
            d["CFBundleIdentifier"] = "org.dockplus.Folder.\(slug.isEmpty ? "Folder" : slug)\(UUID().uuidString)"
            d["FolderSymbol"] = symbol
            d["FolderColors"] = colors
            d["DefaultApps"] = [String]()
            let out = try PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
            try out.write(to: plistURL)
            let icon = tileIcon(symbol: symbol, colors: colors)
            writeICNS(icon, to: dest.appendingPathComponent("Contents/Resources/AppIcon.icns"))
            let signing = Process()
            signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            let identifier = d["CFBundleIdentifier"] as! String
            signing.arguments = ["--force", "--sign", "-", "--identifier", identifier,
                                 "-r=designated => identifier \"" + identifier + "\"", dest.path]
            try signing.run(); signing.waitUntilExit()
            guard signing.terminationStatus == 0 else { throw NSError(domain: "DockPlus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not sign the new folder app."]) }
            log("created folder \(name)")
            pinToDock(dest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSWorkspace.shared.openApplication(at: dest, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        } catch {
            log("could not create folder \(name): \(error.localizedDescription)")
            let a = NSAlert(); a.messageText = "Couldn't make that folder."; a.informativeText = error.localizedDescription; a.runModal()
        }
    }
}

struct ManagedFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let symbol: String
}
final class FolderLibrary: ObservableObject {
    @Published var folders: [ManagedFolder] = []
    @Published var selected: String?
    @Published var apps: [URL] = []
    var current: ManagedFolder? { folders.first { $0.id == selected } }
    func reload() {
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        folders = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).compactMap { url in
            guard url.pathExtension == "app", let b = Bundle(url: url),
                  let id = b.bundleIdentifier, id.hasPrefix("org.dockplus.Folder."),
                  let d = b.infoDictionary else { return nil }
            return ManagedFolder(id: id, name: d["CFBundleDisplayName"] as? String ?? url.deletingPathExtension().lastPathComponent,
                                 url: url, symbol: d["FolderSymbol"] as? String ?? "folder.fill")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !folders.contains(where: { $0.id == selected }) { selected = folders.first?.id }
        loadSelection()
    }
    func loadSelection() {
        guard let folder = current, let defaults = UserDefaults(suiteName: folder.id) else { apps = []; return }
        defaults.synchronize()
        if let paths = defaults.stringArray(forKey: "apps") { apps = paths.map { URL(fileURLWithPath: $0) } }
        else {
            let ids = Bundle(url: folder.url)?.infoDictionary?["DefaultApps"] as? [String] ?? []
            apps = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        }
    }
    func save() {
        guard let folder = current, let defaults = UserDefaults(suiteName: folder.id) else { return }
        defaults.set(apps.map(\.path), forKey: "apps"); defaults.synchronize()
    }
    func add() {
        guard let folder = current else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Apps to \(folder.name)"; panel.prompt = "Add Apps"
        panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !apps.contains(url) && url != folder.url { apps.append(url) }
        save()
    }
    func remove(_ url: URL) { apps.removeAll { $0 == url }; save() }
    func openFolder() { if let folder = current { NSWorkspace.shared.open(folder.url) } }
    func create() {
        (NSApp.delegate as? AppDelegate)?.newFolderDialog()
        let previous = Set(folders.map(\.id)); reload()
        if let new = folders.first(where: { !previous.contains($0.id) }) { selected = new.id; loadSelection() }
    }
}
struct ManagerView: View {
    @ObservedObject var library: FolderLibrary
    var body: some View {
        NavigationSplitView {
            List(selection: $library.selected) {
                Section("Dock Folders") {
                    ForEach(library.folders) { folder in
                        Label(folder.name, systemImage: folder.symbol).tag(folder.id)
                            .accessibilityLabel(folder.name + ", Dock folder")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .onChange(of: library.selected) { _ in library.loadSelection() }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: library.create) { Label("New Folder", systemImage: "plus") }
                        .buttonStyle(.borderless).help("Create a new Dock folder")
                    Spacer()
                }.padding(12)
            }
        } detail: {
            if let folder = library.current {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: folder.symbol).font(.system(size: 32)).foregroundStyle(.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(folder.name).font(.title2.bold())
                            Text("\(library.apps.count) apps in this Dock folder").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Folder", action: library.openFolder)
                            .help("Show this folder’s app launcher")
                    }.padding(24)
                    Divider()
                    if library.apps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "app.badge.checkmark").font(.system(size: 36)).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text("Add your first app").font(.headline)
                            Text("Choose the apps you want to launch from this folder.").foregroundStyle(.secondary)
                            Button("Add Apps…", action: library.add)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(library.apps, id: \.path) { url in
                                HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appName(url))
                                        if !FileManager.default.fileExists(atPath: url.path) { Text("App not found").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    Button { library.remove(url) } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove " + appName(url) + " from " + folder.name)
                                        .help("Remove from folder; the app stays installed")
                                }.padding(.vertical, 5)
                            }
                            .onMove { indices, destination in library.apps.move(fromOffsets: indices, toOffset: destination); library.save() }
                        }.listStyle(.inset)
                    }
                    Divider()
                    Text("Removing an app from a folder keeps it installed on your Mac.")
                        .font(.caption).foregroundStyle(.secondary).padding(14)
                }
            } else {
                VStack(spacing: 14) {
                    Text("Your Dock, organized").font(.title2)
                    Text("Create a folder to keep related apps together.").foregroundStyle(.secondary)
                    Button("New Folder…", action: library.create)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: library.create) { Label("New Folder", systemImage: "folder.badge.plus") }.help("New Folder (Command-N)")
                Button(action: library.add) { Label("Add Apps", systemImage: "plus") }.disabled(library.current == nil).help("Add Apps (Command-O)")
            }
        }
        .frame(minWidth: 720, minHeight: 440)
    }
}
extension AppDelegate {
    func showManager() {
        NSApp.setActivationPolicy(.regular)
        if let window = managerWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let library = FolderLibrary(); library.reload()
        hoverCoordinator = HoverCoordinator()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Dock+"; window.setFrameAutosaveName("DockPlusManager")
        window.toolbarStyle = .unified; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ManagerView(library: library))
        managerWindow = window
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dock+", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Dock+", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let close = NSMenuItem(title: "Close Dock+ Window", action: #selector(closeManagerWindow(_:)), keyEquivalent: "q")
        close.target = self; appMenu.addItem(close)
        appMenu.addItem(.separator())
        let stop = NSMenuItem(title: "Quit Dock+ and Stop Switching", action: #selector(stopSwitchingAndQuit(_:)), keyEquivalent: "")
        stop.target = self; appMenu.addItem(stop)
        appItem.submenu = appMenu; menu.addItem(appItem)
        let file = NSMenuItem(); file.title = "File"; let fileMenu = NSMenu(title: "File")
        let new = ActionMenuItem("New Folder…", key: "n", action: library.create)
        let add = ActionMenuItem("Add Apps…", key: "o", action: library.add)
        fileMenu.addItem(new); fileMenu.addItem(add); fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.submenu = fileMenu; menu.addItem(file)
        let edit = NSMenuItem(); edit.title = "Edit"; let edits = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edits.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = edits; menu.addItem(edit)
        let win = NSMenuItem(); win.title = "Window"; let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.submenu = windows; menu.addItem(win); NSApp.windowsMenu = windows; NSApp.mainMenu = menu
        NSApp.applicationIconImage = tileIcon(symbol: "folder.fill.badge.gearshape", colors: ["#2979E8", "#60BCFF"])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)

    }
}

final class HoverCoordinator: NSObject {
    var timer: Timer?
    var active: String?
    var lastOpen = Date.distantPast
    var candidate: String?
    var candidateSince = Date()
    var lastDiagnostic = ""
    var hoveredFolder: String?
    var pendingSwitch: UUID?
    override init() {
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(opened(_:)), name: NSNotification.Name("org.dockplus.opened"), object: nil)
        center.addObserver(self, selector: #selector(closed(_:)), name: NSNotification.Name("org.dockplus.closed"), object: nil)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in self?.poll() }
    }
    @objc func opened(_ n: Notification) { active = n.object as? String; lastOpen = Date() }
    @objc func closed(_ n: Notification) { if active == n.object as? String { active = nil; lastOpen = Date() } }
    func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }; return result
    }
    func diagnose(_ text: String) {
        if text != lastDiagnostic { lastDiagnostic = text; log(text) }
    }
    func poll() {
        let trusted = AXIsProcessTrusted()
        if !trusted { diagnose("hover: Accessibility access unavailable for " + Bundle.main.bundlePath); return }
        if lastDiagnostic.hasPrefix("hover: Accessibility access unavailable") || lastDiagnostic.isEmpty { diagnose("hover: Accessibility access confirmed") }
        let point = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(top - point.y), &hit)
        guard status == .success, let hitElement = hit else { diagnose("hover: hit test error " + String(status.rawValue)); return }
        var icon = hitElement
        for _ in 0..<4 {
            if value(icon, kAXRoleAttribute) as? String == "AXDockItem" { break }
            guard let parent = value(icon, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            icon = parent as! AXUIElement
        }
        guard value(icon, kAXRoleAttribute) as? String == "AXDockItem" else { candidate = nil; hoveredFolder = nil; pendingSwitch = nil; return }
        let element = icon
        diagnose("hover: Dock item " + (value(element, kAXTitleAttribute) as? String ?? "(no title)"))
        var reach: CGFloat = 0
        var anchor = point
        if let rawPosition = value(element, kAXPositionAttribute), let rawSize = value(element, kAXSizeAttribute),
           CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() {
            var position = CGPoint.zero; var size = CGSize.zero
            AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position)
            AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
            anchor = NSPoint(x: position.x + size.width / 2, y: top - position.y - size.height / 2)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main!
            let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
            if orientation == "left" { reach = position.x + size.width - screen.frame.minX }
            else if orientation == "right" { reach = screen.frame.maxX - position.x }
            else { reach = top - position.y - screen.frame.minY }
        }
        let geometry = UserDefaults(suiteName: "org.dockplusGeometry")!
        geometry.set(Double(reach), forKey: "reach")
        geometry.set(Date().timeIntervalSince1970, forKey: "time")
        geometry.synchronize()

        let title = value(element, kAXTitleAttribute) as? String ?? ""
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let folder = urls.first(where: { url in
            guard let bundle = Bundle(url: url), bundle.bundleIdentifier?.hasPrefix("org.dockplus.Folder.") == true else { return false }
            return (bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? url.deletingPathExtension().lastPathComponent) == title
        }), let id = Bundle(url: folder)?.bundleIdentifier else { candidate = nil; hoveredFolder = nil; pendingSwitch = nil; return }
        guard id != hoveredFolder else { return }
        guard id != active else { hoveredFolder = id; lastOpen = Date(); return }
        // A short grace period bridges the gap between neighboring Dock icons.

        if candidate != id { candidate = id; candidateSince = Date(); return }
        guard Date().timeIntervalSince(candidateSince) >= 0.12 else { return }
        log("hover switching to " + id)
        active = id; hoveredFolder = id; lastOpen = Date(); candidate = nil
        let token = UUID(); pendingSwitch = token
        let deliver = { [weak self] in
            guard let self = self, self.pendingSwitch == token else { return }
            self.pendingSwitch = nil
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("org.dockplus.switch"), object: nil,
                userInfo: ["id": id, "reach": Double(reach), "x": Double(anchor.x), "y": Double(anchor.y)], deliverImmediately: true)
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.arguments = ["--hover-launch"]
            NSWorkspace.shared.openApplication(at: folder, configuration: configuration) { _, error in
                DispatchQueue.main.async { if error == nil { deliver() } }
            }
        } else {
            deliver()
        }
    }
}
final class ActionMenuItem: NSMenuItem {
    let handler: () -> Void
    init(_ title: String, key: String, action: @escaping () -> Void) {
        handler = action; super.init(title: title, action: #selector(invoke), keyEquivalent: key); target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func invoke() { handler() }
}
let app = NSApplication.shared
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--write-icon" {
    writeICNS(tileIcon(symbol: "square.grid.2x2.fill", colors: ["#2979E8", "#60BCFF"]), to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
