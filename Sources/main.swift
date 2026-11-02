// BatteryGuard — tiny menu bar app that blocks attention at low battery
// until the charger is connected.

import Cocoa
import IOKit.ps

// MARK: - Config

let lowThreshold = 20          // show alert at or below this %
let criticalThreshold = 10     // alert turns red + extra sound

// MARK: - Battery reading

struct BatteryState {
    var percent: Int
    var onAC: Bool
    var isCharging: Bool
    var hasBattery: Bool
}

func readBattery() -> BatteryState {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return BatteryState(percent: 100, onAC: true, isCharging: false, hasBattery: false) }

    let sourceType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    let onAC = sourceType == kIOPMACPowerKey

    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
              (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        else { continue }
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
        let charging = d[kIOPSIsChargingKey] as? Bool ?? false
        return BatteryState(percent: pct, onAC: onAC, isCharging: charging, hasBattery: true)
    }
    return BatteryState(percent: 100, onAC: true, isCharging: false, hasBattery: false)
}

// MARK: - Alert window

final class AlertCard: NSView {
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let percentLabel = NSTextField(labelWithString: "")
    let waiting = NSTextField(labelWithString: "Waiting for charger…")
    let closeButton = NSButton(title: "Close preview", target: nil, action: nil)
    let bar = NSProgressIndicator()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        icon.symbolConfiguration = .init(pointSize: 64, weight: .regular)
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.alignment = .center
        message.font = .systemFont(ofSize: 14)
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.stringValue = "Please plug in your charger now.\nIf the battery runs out your Mac will shut down, you may lose unsaved work, and it can take a while before it starts again."
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .heavy)
        percentLabel.alignment = .center
        waiting.font = .systemFont(ofSize: 12, weight: .medium)
        waiting.textColor = .tertiaryLabelColor
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        closeButton.bezelStyle = .rounded
        closeButton.isHidden = true

        let stack = NSStackView(views: [icon, title, percentLabel, bar, message, waiting, closeButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(4, after: title)
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 36, bottom: 28, right: 36)
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 260),
            message.widthAnchor.constraint(equalToConstant: 380),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(percent: Int) {
        let critical = percent <= criticalThreshold
        let color: NSColor = critical ? .systemRed : .systemOrange
        let symbol = percent <= 10 ? "battery.0percent" : "battery.25percent"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Low battery")
        icon.contentTintColor = color
        title.stringValue = critical ? "Battery Critically Low" : "Battery Low — Please Charge"
        percentLabel.stringValue = "\(percent)%"
        percentLabel.textColor = color
        bar.doubleValue = Double(percent)
    }
}

final class AlertController {
    private var backdrop: NSWindow?
    private var panel: NSPanel?
    private let card = AlertCard(frame: .zero)
    private var pulseTimer: Timer?
    private(set) var isShowing = false
    private(set) var isPreview = false
    var onClosePreview: (() -> Void)?

    init() {
        card.closeButton.target = self
        card.closeButton.action = #selector(closePreview)
    }

    func show(percent: Int, preview: Bool) {
        card.update(percent: percent)
        card.closeButton.isHidden = !preview
        isPreview = preview
        if isShowing { return }
        isShowing = true

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Dim backdrop (click-through, so you can still save work)
        let bd = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        bd.isOpaque = false
        bd.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        bd.ignoresMouseEvents = true
        bd.level = level
        bd.collectionBehavior = behavior
        bd.isReleasedWhenClosed = false
        bd.alphaValue = 0
        bd.orderFrontRegardless()
        backdrop = bd

        // Centered card — no close button
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: level.rawValue + 1)
        p.collectionBehavior = behavior
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.contentView = card
        p.setContentSize(card.fittingSize)
        let f = p.frame
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - f.width / 2, y: screen.frame.midY - f.height / 2))
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            bd.animator().alphaValue = 1
            p.animator().alphaValue = 1
        }

        // Gentle pulse on the "waiting" label
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            guard let l = self?.card.waiting else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.8; l.animator().alphaValue = l.alphaValue > 0.6 ? 0.3 : 1 }
        }

        // Keep it on top even if other apps try to cover it
        NotificationCenter.default.addObserver(self, selector: #selector(reassert),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reassert),
                                               name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc private func reassert() {
        guard isShowing, let p = panel, let bd = backdrop else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        bd.setFrame(screen.frame, display: true)
        let f = p.frame
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - f.width / 2, y: screen.frame.midY - f.height / 2))
        bd.orderFrontRegardless()
        p.orderFrontRegardless()
    }

    @objc private func closePreview() {
        hide()
        onClosePreview?()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        isPreview = false
        pulseTimer?.invalidate(); pulseTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        let bd = backdrop, p = panel
        backdrop = nil; panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            bd?.animator().alphaValue = 0
            p?.animator().alphaValue = 0
        }, completionHandler: {
            bd?.orderOut(nil)
            p?.orderOut(nil)
        })
    }
}

// MARK: - Launch at login (LaunchAgent)

enum LoginItem {
    static let label = "com.local.batteryguard"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func set(_ on: Bool) {
        if on {
            guard let exe = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": ["SuccessfulExit": false],
                "ProcessType": "Interactive",
            ]
            try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: plistURL, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let alert = AlertController()
    private var lastState = readBattery()
    private var lastSoundPercent = Int.max
    private var runLoopSource: CFRunLoopSource?
    private var fallbackTimer: Timer?

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginToggle = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preview Alert", action: #selector(previewAlert), keyEquivalent: "p").target = self
        loginToggle.target = self
        menu.addItem(loginToggle)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BatteryGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // First run: enable launch at login automatically
        let firstRunKey = "didFirstRun"
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            LoginItem.set(true)
            UserDefaults.standard.set(true, forKey: firstRunKey)
        }

        alert.onClosePreview = { [weak self] in self?.evaluate() }

        // Event-driven power notifications (no polling cost)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.evaluate() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = src
        }
        // Safety net in case a notification is missed (e.g. after sleep)
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.evaluate() }
        fallbackTimer?.tolerance = 15
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(evaluate),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        evaluate()
        if CommandLine.arguments.contains("--preview") { previewAlert() }
    }

    @objc func evaluate() {
        let s = readBattery()
        lastState = s
        updateStatusItem(s)

        guard s.hasBattery else { return }
        let low = !s.onAC && s.percent <= lowThreshold

        if low {
            alert.show(percent: s.percent, preview: false)
            // Sound when alert first appears, then at every 5% drop
            if s.percent <= lastSoundPercent - 5 || lastSoundPercent == Int.max {
                NSSound(named: s.percent <= criticalThreshold ? "Sosumi" : "Funk")?.play()
                lastSoundPercent = s.percent
            }
        } else {
            lastSoundPercent = Int.max
            if alert.isShowing && !alert.isPreview {
                alert.hide()
                if s.onAC { NSSound(named: "Glass")?.play() }
            }
        }
    }

    private func updateStatusItem(_ s: BatteryState) {
        guard let b = statusItem.button else { return }
        let symbol: String
        switch (s.onAC, s.percent) {
        case (true, _): symbol = "battery.100percent.bolt"
        case (_, ...lowThreshold): symbol = "battery.25percent"
        case (_, ...50): symbol = "battery.50percent"
        case (_, ...80): symbol = "battery.75percent"
        default: symbol = "battery.100percent"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Battery")
        img?.isTemplate = true
        b.image = img
        b.title = " \(s.percent)%"
        b.contentTintColor = (!s.onAC && s.percent <= lowThreshold) ? .systemRed : nil

        let src = s.onAC ? (s.isCharging ? "Charging" : "On power") : "On battery"
        statusLine.title = s.hasBattery ? "\(s.percent)% — \(src)" : "No battery found"
        loginToggle.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func previewAlert() {
        alert.show(percent: min(lastState.percent, lowThreshold), preview: true)
        NSSound(named: "Funk")?.play()
    }

    @objc private func toggleLogin() {
        LoginItem.set(!LoginItem.isEnabled)
        loginToggle.state = LoginItem.isEnabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
