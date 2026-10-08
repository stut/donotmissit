import AppKit
import EventKit

let leadTime: TimeInterval = 60   // overlay appears this long before start
let pollInterval: TimeInterval = 10
let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                    "webex.com", "whereby.com", "chime.aws", "gotomeeting.com", "meet.goto.com", "around.co"]

func meetingURL(in text: String) -> URL? {
    // Google notes arrive as HTML; NSDataDetector would glue "<br>" onto the URL.
    let text = text.replacingOccurrences(of: "[<>]", with: " ", options: .regularExpression)
    let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        .compactMap(\.url)
        .first { url in meetingHosts.contains { url.host?.hasSuffix($0) == true } }
}

func meetingURL(for e: EKEvent) -> URL? {
    meetingURL(in: [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: "\n"))
}

func declined(_ e: EKEvent) -> Bool {
    e.attendees?.first { $0.isCurrentUser }?.participantStatus == .declined
}

// Borderless windows refuse key status by default; we need it for Return/Esc.
// Non-activating panel: takes keys without needing app activation, which macOS won't grant to a timer.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = EKEventStore()
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var events: [EKEvent] = []
    var alerted = Set<String>()
    var overlays: [NSWindow] = []
    var overlayURL: URL?
    var overlayKey = ""

    func applicationDidFinishLaunching(_ note: Notification) {
        status.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "DoNotMissIt")
        status.button?.imagePosition = .imageLeading
        status.menu = NSMenu()
        status.menu?.delegate = self
        Timer.scheduledTimer(timeInterval: pollInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        Task {
            _ = try? await store.requestFullAccessToEvents()
            tick()
        }
    }

    @objc func tick() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            status.button?.title = " No calendar access"
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300), end: now.addingTimeInterval(86400), calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !declined($0) && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        if let next = events.first(where: { $0.startDate > now }) {
            let left = Duration.seconds(ceil(next.startDate.timeIntervalSince(now) / 60) * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
            status.button?.title = " \((next.title ?? "").prefix(25)) · \(left)"
        } else {
            status.button?.title = ""
        }

        // Window opens 5 min in the past so a meeting that started while asleep still alerts on wake.
        guard overlays.isEmpty, let due = events.first(where: {
            let dt = $0.startDate.timeIntervalSince(now)
            return dt <= leadTime && dt > -300 && !alerted.contains(key($0))
        }) else { return }
        alerted.insert(key(due))
        showOverlay(due)
    }

    // Title, not identifier: the same meeting in two calendars has two identifiers but should alert once.
    func key(_ e: EKEvent) -> String { "\(e.title ?? "")@\(e.startDate.timeIntervalSince1970)" }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if events.isEmpty { menu.addItem(withTitle: "No meetings in the next 24h", action: nil, keyEquivalent: "") }
        for e in events.prefix(15) {
            let time = e.startDate.formatted(date: .omitted, time: .shortened)
            let item = menu.addItem(withTitle: "\(time)  \(e.title ?? "Untitled")", action: #selector(preview), keyEquivalent: "")
            item.target = self
            item.representedObject = e
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")
    }

    @objc func preview(_ item: NSMenuItem) {
        if let e = item.representedObject as? EKEvent { showOverlay(e) }
    }

    func showOverlay(_ e: EKEvent) {
        dismiss()
        overlayURL = meetingURL(for: e)
        overlayKey = key(e)
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            w.isOpaque = false
            w.contentView = content(e, width: screen.frame.width * 0.8)
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            overlays.append(w)
        }
        overlays.first?.makeKey()
    }

    func content(_ e: EKEvent, width: CGFloat) -> NSView {
        let title = NSTextField(wrappingLabelWithString: e.title ?? "Untitled")
        title.font = .systemFont(ofSize: 56, weight: .bold)
        title.alignment = .center
        title.preferredMaxLayoutWidth = width
        let time = NSTextField(labelWithString: [e.startDate, e.endDate]
            .map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: " – "))
        time.font = .systemFont(ofSize: 28)

        var buttons: [NSButton] = []
        if overlayURL != nil {
            let joinButton = NSButton(title: "Join", target: self, action: #selector(join))
            joinButton.keyEquivalent = "\r"
            buttons.append(joinButton)
        }
        let dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismiss))
        dismissButton.keyEquivalent = "\u{1b}"
        buttons.append(dismissButton)
        buttons.forEach { $0.controlSize = .large }

        let stack = NSStackView(views: [title, time, NSStackView(views: buttons)])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    @objc func join() {
        alerted.insert(overlayKey)   // joined early from the menu: don't alert again at start time
        if let url = overlayURL { NSWorkspace.shared.open(url) }
        dismiss()
    }

    @objc func dismiss() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }
}

if CommandLine.arguments.contains("--selftest") {
    precondition(meetingURL(in: "Join: https://us02web.zoom.us/j/123?pwd=x")?.host == "us02web.zoom.us")
    precondition(meetingURL(in: "Room 4\n<https://meet.google.com/abc-defg-hij>")?.host == "meet.google.com")
    precondition(meetingURL(in: "Join<br>https://meet.google.com/abc-defg-hij<br>x")?.path == "/abc-defg-hij")
    precondition(meetingURL(in: "https://calendar.google.com/event?eid=1 https://example.com") == nil)
    print("ok")
    exit(0)
}

let app = App()
NSApplication.shared.delegate = app
NSApplication.shared.run()
