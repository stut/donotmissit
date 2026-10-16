import AppKit
import EventKit
import ServiceManagement
import SwiftUI

let lookAheads: KeyValuePairs = [4: "4 hours", 8: "8 hours", 12: "12 hours", 24: "24 hours", 48: "2 days", 72: "3 days",
                                 168: "1 week", 336: "2 weeks", 720: "1 month"]
// integer(forKey:) is 0 until the picker is first used, and defaults can be hand-edited.
var leadTime: TimeInterval { TimeInterval(min(max(UserDefaults.standard.integer(forKey: "leadMinutes"), 1), 10) * 60) }   // overlay appears this long before start
var lookAheadHours: Int { let h = UserDefaults.standard.integer(forKey: "lookAheadHours"); return lookAheads.contains { $0.key == h } ? h : 24 }
let pollInterval: TimeInterval = 10
let meetingHosts = ["zoom.us": "Zoom", "meet.google.com": "Google Meet", "teams.microsoft.com": "Teams", "teams.live.com": "Teams",
                    "webex.com": "Webex", "whereby.com": "Whereby", "chime.aws": "Chime", "gotomeeting.com": "GoTo",
                    "meet.goto.com": "GoTo", "around.co": "Around"]

func provider(_ url: URL) -> String? { meetingHosts.first { url.host?.hasSuffix($0.key) == true }?.value }
// h:mm:ss past an hour: menu previews can open the overlay up to a month ahead.
func countdown(_ s: Int) -> String { Duration.seconds(s).formatted(.time(pattern: s < 3600 ? .minuteSecond : .hourMinuteSecond)) }
// Up to 84pt and ~0.71 of the ring's inner diameter (d - 20). Measured, as digit widths vary by locale; the slack under 3/4 covers SF's looser small-size tracking.
func clockFont(_ text: String, _ d: CGFloat) -> NSFont { .monospacedDigitSystemFont(ofSize: min(84, 60 * (d - 20) / text.size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 84, weight: .light)]).width), weight: .light) }

func meetingURL(in text: String) -> URL? {
    // Google notes arrive as HTML; NSDataDetector would glue "<br>" onto the URL.
    let text = text.replacingOccurrences(of: "[<>]", with: " ", options: .regularExpression)
    let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        .compactMap(\.url)
        .first { provider($0) != nil }
}

func meetingURL(for e: EKEvent) -> URL? {
    meetingURL(in: [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: "\n"))
}

func declined(_ e: EKEvent) -> Bool {
    e.attendees?.first { $0.isCurrentUser }?.participantStatus == .declined
}

// Title, not identifier: the same meeting in two calendars has two identifiers but should alert once.
func key(_ e: EKEvent) -> String { "\(e.title ?? "")@\(e.startDate.timeIntervalSince1970)" }

// e and everything starting with it, e first, for one shared overlay. e leads even if a poll has since dropped it from events.
func together(_ e: EKEvent, in events: [EKEvent]) -> [EKEvent] {
    var seen = Set<String>()
    return ([e] + events).filter { $0.startDate == e.startDate && seen.insert(key($0)).inserted }
}

// The app icon's stopwatch as a template, on the icon's 1024pt canvas: case ring, calendar header with binder slots, crown, pusher.
func menuBarIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 17, height: 18), flipped: true) { r in
        let t = NSAffineTransform()
        t.scale(by: r.height / 770)
        t.translateX(by: -165, yBy: -120)
        t.concat()
        let face = NSBezierPath(ovalIn: NSRect(x: 240, y: 292, width: 536, height: 536))
        let ring = NSBezierPath(ovalIn: NSRect(x: 182, y: 234, width: 652, height: 652))
        ring.append(face)
        ring.windingRule = .evenOdd
        ring.fill()
        NSBezierPath(roundedRect: NSRect(x: 416, y: 126, width: 184, height: 62), xRadius: 22, yRadius: 22).fill()
        NSBezierPath.fill(NSRect(x: 470, y: 176, width: 76, height: 80))
        NSGraphicsContext.saveGraphicsState()
        let pusher = NSAffineTransform()
        pusher.translateX(by: 508, yBy: 560)
        pusher.rotate(byDegrees: 45)
        pusher.translateX(by: -508, yBy: -560)
        pusher.concat()
        NSBezierPath.fill(NSRect(x: 480, y: 190, width: 56, height: 64))
        NSBezierPath(roundedRect: NSRect(x: 450, y: 146, width: 116, height: 54), xRadius: 20, yRadius: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSBezierPath.clip(NSRect(x: 0, y: 0, width: 1024, height: 462))   // header: the face above the chord
        face.fill()
        NSGraphicsContext.current?.compositingOperation = .clear   // binder slots, then the rings inside them
        for x in [369.0, 605] { NSBezierPath(roundedRect: NSRect(x: x - 14, y: 266, width: 70, height: 132), xRadius: 35, yRadius: 35).fill() }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        for x in [369.0, 605] { NSBezierPath(roundedRect: NSRect(x: x + 6, y: 286, width: 30, height: 92), xRadius: 15, yRadius: 15).fill() }
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "DoNotMissIt"
    return img
}

struct SettingsView: View {
    @AppStorage("leadMinutes") private var leadMinutes = 1
    @AppStorage("lookAheadHours") private var lookAheadHours = 24
    @State private var login = SMAppService.mainApp.status == .enabled

    func info(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }

    var body: some View {
        Form {
            Section {
                Picker("Remind me", selection: $leadMinutes) {
                    ForEach(1...10, id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s") before") }
                }
                Picker("Look ahead", selection: $lookAheadHours) {
                    ForEach(lookAheads, id: \.key) { Text($0.value) }
                }
                Toggle("Start at login", isOn: Binding(get: { login }, set: {
                    try? $0 ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    // Previously switched off in System Settings: only the user can re-enable it there.
                    if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                    login = SMAppService.mainApp.status == .enabled
                }))
            }
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info("CFBundleName")).font(.title3.weight(.semibold))
                        Group {
                            Text("Version \(info("CFBundleShortVersionString")) Build \(info("CFBundleVersion"))")
                            Text(info("NSHumanReadableCopyright"))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        // The login item can be flipped in System Settings while this window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login = SMAppService.mainApp.status == .enabled
        }
    }
}

// No main menu (LSUIElement), so nothing else turns ⌘W into Close.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "w" else { return super.performKeyEquivalent(with: e) }
        performClose(nil)
        return true
    }
}

func makeSettingsWindow() -> NSWindow {
    let w = SettingsWindow(contentViewController: NSHostingController(rootView: SettingsView()))
    w.styleMask = [.titled, .closable]
    w.titlebarAppearsTransparent = true   // one seamless surface like System Settings, not a hairline under the title
    w.title = "DoNotMissIt Settings"
    w.isReleasedWhenClosed = false
    w.collectionBehavior = .moveToActiveSpace   // else it reopens on the Space it was first shown on, which may since have been closed
    w.setContentSize(w.contentView!.fittingSize)   // SwiftUI sizes the window lazily, which would throw off center()
    w.center()
    return w
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
    var overlayEvents: [EKEvent] = []
    var timers: [Timer] = []
    lazy var settings = makeSettingsWindow()

    func applicationDidFinishLaunching(_ note: Notification) {
        status.button?.image = menuBarIcon()
        status.button?.imagePosition = .imageLeading
        status.menu = NSMenu()
        status.menu?.delegate = self
        Timer.scheduledTimer(timeInterval: pollInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        // Settings apply now, not on the next poll. Async: defaults change on any thread, and AppKit writes some mid-layout inside showOverlay.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in DispatchQueue.main.async { self?.tick() } }
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
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300), end: now.addingTimeInterval(TimeInterval(lookAheadHours) * 3600), calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !declined($0) && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        if let next = events.first(where: { $0.startDate > now }) {
            let left = Duration.seconds(ceil(next.startDate.timeIntervalSince(now) / 60) * 60)
                .formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2, fractionalPart: .hide(rounded: .down)))
            status.button?.title = " \(next.title.isEmpty ? "Untitled" : next.title.prefix(25)) · \(left)"
        } else {
            status.button?.title = ""
        }

        // Window opens 5 min in the past so a meeting that started while asleep still alerts on wake.
        guard overlays.isEmpty, let due = events.first(where: {
            let dt = $0.startDate.timeIntervalSince(now)
            return dt <= leadTime && dt > -300 && !alerted.contains(key($0))
        }) else { return }
        let group = together(due, in: events).filter { !alerted.contains(key($0)) }
        group.forEach { alerted.insert(key($0)) }
        showOverlay(group)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if events.isEmpty {
            let span = lookAheads.first { $0.key == lookAheadHours }!.value
            menu.addItem(withTitle: "Nothing scheduled in the next \(span.hasPrefix("1 ") ? String(span.dropFirst(2)) : span)", action: nil, keyEquivalent: "")
        }
        for e in events.prefix(10) {
            let time = Calendar.current.isDateInToday(e.startDate) ? e.startDate.formatted(date: .omitted, time: .shortened)
                : e.startDate.formatted(.dateTime.weekday().day().month().hour().minute())
            let item = menu.addItem(withTitle: "\(time)  \(e.title.isEmpty ? "Untitled" : e.title!)", action: #selector(preview), keyEquivalent: "")
            item.target = self
            item.representedObject = e
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")
    }

    @objc func openSettings() {
        NSApp.activate()
        settings.orderFrontRegardless()   // activation can be refused (e.g. when run from Xcode), which would leave it behind the frontmost app
        settings.makeKey()
    }

    @objc func preview(_ item: NSMenuItem) {
        if let e = item.representedObject as? EKEvent { showOverlay(together(e, in: events)) }
    }

    func showOverlay(_ es: [EKEvent]) {
        dismiss()
        overlayEvents = es
        for screen in NSScreen.screens {
            let w = makeOverlay(es, frame: screen.frame)
            w.orderFrontRegardless()
            overlays.append(w)
        }
        overlays.first?.makeKey()
    }

    func makeOverlay(_ es: [EKEvent], frame: NSRect) -> NSWindow {
        let w = OverlayWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = .clear
        w.isOpaque = false
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.state = .active
        w.contentView = blur
        let root = content(es, width: min(frame.width * 0.8, 1000), scale: w.backingScaleFactor)
        root.frame = blur.bounds
        root.autoresizingMask = [.width, .height]
        blur.addSubview(root)
        w.setFrame(frame, display: true)
        return w
    }

    func content(_ es: [EKEvent], width: CGFloat, scale: CGFloat) -> NSView {
        let e = es[0]
        var tint = e.calendar?.color ?? .controlAccentColor
        // Dark calendar colours (Blueberry, Grape, Graphite) sink into the card; lift them toward white.
        if tint.usingColorSpace(.genericGamma22Gray)?.whiteComponent ?? 1 < 0.45 { tint = tint.blended(withFraction: 0.4, of: .white)! }
        let d = min(300, width * 0.35), textWidth = max(360, width - d - 48 * 2 - 56)   // card insets and gap; 360 fits Join Google Meet + Dismiss
        func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .secondaryLabelColor, lines: Int = 1) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: s)
            l.font = .systemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.isSelectable = false   // a clicked selectable label takes first responder and swallows Return/Esc
            l.preferredMaxLayoutWidth = textWidth
            l.maximumNumberOfLines = lines
            l.cell?.truncatesLastVisibleLine = true
            l.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true   // one-line labels report their untruncated width
            return l
        }
        let clock = NSTextField(labelWithString: "")
        let caption = label("", 17, .medium)
        let face = NSStackView(views: [clock, caption])
        face.orientation = .vertical
        face.spacing = 0

        let dial = NSView()
        dial.wantsLayer = true
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(x: 0, y: 0, width: d, height: d)
        // Starts at 12 o'clock and runs clockwise, so strokeEnd drains it like a clock hand.
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: d / 2, y: d / 2), radius: d / 2 - 6, startAngle: .pi / 2, endAngle: -1.5 * .pi, clockwise: true)
        let track = CAShapeLayer(), arc = CAShapeLayer()
        for l in [track, arc] {
            l.path = path
            l.fillColor = nil
            l.lineWidth = 8
            l.lineCap = .round
        }
        [glow, track, arc].forEach(dial.layer!.addSublayer)
        [glow, track, arc].forEach { $0.contentsScale = scale }   // hand-added sublayers don't inherit it and render soft
        track.strokeColor = NSColor.white.withAlphaComponent(0.1).cgColor
        arc.shadowOffset = .zero
        arc.shadowRadius = 14
        arc.shadowOpacity = 1
        dial.addSubview(face)
        face.translatesAutoresizingMaskIntoConstraints = false

        func when(_ e: EKEvent) -> String { [e.startDate, e.endDate].map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: " – ") }
        func place(_ e: EKEvent) -> String { let loc = e.location ?? ""; return URL(string: loc)?.host == nil ? loc : "" }
        var returnTaken = false   // Return joins the first event with a link
        func joinPill(_ i: Int, small: Bool = false) -> NSButton? {
            guard let name = meetingURL(for: es[i]).flatMap(provider) else { return nil }
            defer { returnTaken = true }
            let b = pill("Join \(name)", #selector(join), returnTaken ? "" : "\r", primary: true, small: small)
            b.tag = i
            return b
        }
        let dismissPill = pill("Dismiss", #selector(dismiss), "\u{1b}", primary: false)
        let column = NSStackView()
        if es.count == 1 {
            let title = label(e.title.isEmpty ? "Untitled" : e.title!, 44, .bold, .labelColor, lines: 3)
            let info = [label(e.calendar?.title ?? "", 18, .semibold, tint), title, label(when(e), 22), label(place(e), 22)]
            info.forEach { $0.isHidden = $0.stringValue.isEmpty }   // the stack detaches hidden views, so no blank rows
            let footer = NSStackView(views: [joinPill(0), dismissPill].compactMap { $0 })
            footer.spacing = 12
            footer.setHuggingPriority(.defaultHigh, for: .horizontal)   // else it ties with the column's hugging and its width is ambiguous
            column.setViews(info + [footer], in: .top)
            column.setCustomSpacing(14, after: title)
            column.setCustomSpacing(32, after: info.last { !$0.isHidden }!)
        } else {
            // One line per event, its Join pinned right; dividers between.
            var rows: [NSView] = [label("\(es.count) events at \(e.startDate.formatted(date: .omitted, time: .shortened))", 18, .semibold, tint)]
            for (i, e) in es.enumerated() {
                if i > 0 {
                    let rule = NSView()
                    rule.wantsLayer = true
                    rule.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
                    rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
                    rows.append(rule)
                }
                let text = NSStackView(views: [label(e.title.isEmpty ? "Untitled" : e.title!, 26, .bold, .labelColor),
                                               label([e.calendar?.title ?? "", when(e), place(e)].filter { !$0.isEmpty }.joined(separator: " · "), 17)])
                text.orientation = .vertical
                text.alignment = .leading
                text.spacing = 4
                text.setContentHuggingPriority(.defaultLow, for: .horizontal)
                let row = NSStackView()
                row.setViews([text], in: .leading)
                row.setViews([joinPill(i, small: true)].compactMap { $0 }, in: .trailing)
                row.spacing = 16
                rows.append(row)
            }
            rows.dropFirst().forEach { $0.widthAnchor.constraint(equalToConstant: textWidth).isActive = true }
            column.setViews(rows + [dismissPill], in: .top)
            column.spacing = 18
            column.setCustomSpacing(22, after: rows[0])
            column.setCustomSpacing(32, after: rows.last!)
        }
        column.orientation = .vertical
        column.alignment = .leading

        let card = NSStackView(views: [column, dial])
        card.spacing = 56
        card.edgeInsets = NSEdgeInsets(top: 44, left: 48, bottom: 44, right: 48)
        card.setHuggingPriority(.defaultLow - 1, for: .vertical)   // else its insets tie with the column and footer hugging (all 250) and stretch them
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.94).cgColor
        card.layer?.cornerRadius = 32
        card.layer?.borderWidth = 1
        let shadow = NSShadow()   // AppKit overwrites shadow properties set on the view's layer
        shadow.shadowColor = .black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        card.shadow = shadow
        card.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        root.addSubview(card)
        NSLayoutConstraint.activate([
            dial.widthAnchor.constraint(equalToConstant: d), dial.heightAnchor.constraint(equalToConstant: d),
            face.centerXAnchor.constraint(equalTo: dial.centerXAnchor), face.centerYAnchor.constraint(equalTo: dial.centerYAnchor),
            // The card's top/bottom insets are only as strong as its hugging, so hold them here.
            card.heightAnchor.constraint(greaterThanOrEqualTo: column.heightAnchor, constant: 88), card.heightAnchor.constraint(greaterThanOrEqualToConstant: d + 88),
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        timers.append(Timer(timeInterval: 0.25, repeats: true) { [weak clock, weak caption, weak glow, weak arc, weak card, tint, start = e.startDate!] _ in
            let dt = start.timeIntervalSinceNow, late = dt <= 0, c = late ? NSColor.systemRed : tint
            let text = (late ? "+" : "") + countdown(abs(Int(dt.rounded(.up))))
            clock?.stringValue = text
            clock?.font = clockFont(text, d)
            clock?.textColor = late ? c : .labelColor
            caption?.stringValue = late ? "since start" : "until start"
            glow?.colors = [late ? 0.45 : 0.3, 0.08, 0].map { c.withAlphaComponent($0).cgColor }
            arc?.strokeColor = c.cgColor
            arc?.shadowColor = c.cgColor
            arc?.strokeEnd = late ? 1 : min(1, dt / leadTime)
            card?.layer?.borderColor = (late ? c.withAlphaComponent(0.4) : NSColor(white: 1, alpha: 0.1)).cgColor
        })
        RunLoop.main.add(timers.last!, forMode: .common)   // .default mode pauses while a pill is held down
        timers.last!.fire()
        return root
    }

    // Drawn by hand: system bezels go grey on the overlays that aren't key (every screen but one).
    func pill(_ title: String, _ action: Selector, _ key: String, primary: Bool, small: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.keyEquivalent = key
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = small ? 20 : 26
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(primary ? 1 : 0.12).cgColor
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: small ? 16 : 19, weight: .semibold), .foregroundColor: primary ? NSColor.black : .white])
        NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: b.intrinsicContentSize.width + (small ? 40 : 56)),
                                     b.heightAnchor.constraint(equalToConstant: small ? 40 : 52)])
        return b
    }

    @objc func join(_ b: NSButton) {
        let e = overlayEvents[b.tag]
        alerted.insert(key(e))   // joined early from the menu: don't alert again at start time
        if let url = meetingURL(for: e) { NSWorkspace.shared.open(url) }
        dismiss()
    }

    @objc func dismiss() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }
}

if CommandLine.arguments.contains("--selftest") {
    precondition(meetingURL(in: "Join: https://us02web.zoom.us/j/123?pwd=x")?.host == "us02web.zoom.us")
    precondition(meetingURL(in: "Room 4\n<https://meet.google.com/abc-defg-hij>")?.host == "meet.google.com")
    precondition(meetingURL(in: "Join<br>https://meet.google.com/abc-defg-hij<br>x")?.path == "/abc-defg-hij")
    precondition(meetingURL(in: "https://calendar.google.com/event?eid=1 https://example.com") == nil)
    precondition(provider(URL(string: "https://us02web.zoom.us/j/1")!) == "Zoom")
    for t in [43, 3599, 86399].map(countdown) + ["+" + countdown(3599), "+" + countdown(360002)] { precondition(t.size(withAttributes: [.font: clockFont(t, 224)]).width <= 0.75 * 204, t) }
    let s = EKEventStore(), t = Date()
    let evs = [("A", t), ("B", t), ("A", t), ("C", t + 60)].map { let e = EKEvent(eventStore: s); (e.title, e.startDate) = $0; return e }
    precondition(together(evs[1], in: evs).map(\.title) == ["B", "A"])
    print("ok")
    exit(0)
}

let app = App()
NSApplication.shared.delegate = app
NSApplication.shared.run()
