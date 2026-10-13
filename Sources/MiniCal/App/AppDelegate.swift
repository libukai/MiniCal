import AppKit
import Combine
import ServiceManagement
import OSLog
import SwiftUI
import MiniCalCore
import MiniCalData
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let settings: SettingsStore
    private let model: CalendarModel
    private let data: CalendarDataStore
    private let fixtures: Bool
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var calendarWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var shortcut: GlobalShortcut?
    private var timer: Timer?
    private var localKeys: Any?
    private var cancellables = Set<AnyCancellable>()
    private var hoverRevision = 0
    private var registeredShortcut: String?
    private var calendarMenuItem: NSMenuItem?
    private let lifecycleLog = Logger(subsystem: "com.libukai.MiniCal", category: "Windowing")

    init(settings: SettingsStore, model: CalendarModel, data: CalendarDataStore, fixtures: Bool) {
        self.settings = settings; self.model = model; self.data = data; self.fixtures = fixtures
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleLog.info("Application launched")
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        shortcut = GlobalShortcut()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel(fixtures ? "MiniCal，虚拟数据" : "MiniCal")
            let tracker = StatusHoverView(frame: button.bounds)
            tracker.autoresizingMask = [.width, .height]
            tracker.onEnter = { [weak self] in self?.hoverEntered() }
            tracker.onExit = { [weak self] in self?.hoverRevision += 1 }
            button.addSubview(tracker)
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: calendarView())
        settings.$config.receive(on: RunLoop.main).sink { [weak self] _ in
            // @Published fires before assignment, so use a queued run-loop turn.
            Task { @MainActor [weak self] in self?.applyPreferences() }
        }.store(in: &cancellables)
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self.map { $0.handleKey(event) == nil } ?? false }
            return consumed ? nil : event
        }
        applyPreferences()
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if CommandLine.arguments.contains("--calendar-window") { showCalendarWindow() }
    }

    func popoverDidClose(_ notification: Notification) { lifecycleLog.info("Calendar popover did close") }

    func applicationDidResignActive(_ notification: Notification) {
        if popover.contentViewController?.view.window?.attachedSheet == nil { closePopover() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        lifecycleLog.info("Application terminating")
        timer?.invalidate()
        shortcut?.unregister()
        if let localKeys { NSEvent.removeMonitor(localKeys) }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "minical" {
            guard url.host?.lowercased() == "show", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            if let value = components.queryItems?.first(where: { $0.name == "date" })?.value,
               let seconds = Double(value), seconds.isFinite,
               (-62_135_596_800...253_402_300_799).contains(seconds) {
                model.go(to: Date(timeIntervalSince1970: seconds))
            }
            openPopover()
        }
    }

    func openPopover() {
        guard let button = statusItem?.button else { return }
        if calendarWindow?.isVisible == true { calendarWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        NSApp.activate(ignoringOtherApps: true)
        popover.animates = settings.config.animate
        resizeCalendarContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        lifecycleLog.info("Calendar popover opened")
        popover.contentViewController?.view.window?.makeKey()
    }
    func closePopover() {
        hoverRevision += 1
        if popover.isShown { lifecycleLog.info("Calendar popover closed"); popover.performClose(nil) }
    }
    func pinCalendarWindow() {
        if calendarWindow?.isVisible == true { calendarWindow?.close(); model.pinned = false; return }
        closePopover()
        showCalendarWindow()
    }
    func showCalendarWindow() {
        if calendarWindow == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: settings.panelWidth, height: calendarHeight),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = fixtures ? "MiniCal · 虚拟数据" : "MiniCal"
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: calendarView())
            window.center()
            calendarWindow = window
        }
        model.pinned = true
        resizeCalendarContent()
        calendarWindow?.makeKeyAndOrderFront(nil)
        lifecycleLog.info("Calendar window opened")
        NSApp.activate(ignoringOtherApps: true)
    }
    func openSettings() {
        closePopover()
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, data: data,
                onLoginToggle: { [weak self] in self?.setLaunchAtLogin($0) },
                onNotificationsToggle: { [weak self] in self?.setHolidayNotifications($0) },
                onSubscription: { [weak self] in self?.subscribe($0) },
                onImportICS: { [weak self] in self?.importICS() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = fixtures ? "MiniCal 设置 · 虚拟数据" : "MiniCal 设置"
            window.contentViewController = NSHostingController(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        lifecycleLog.info("Settings opened")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === calendarWindow { model.pinned = false }
    }

    private func calendarView() -> CalendarView {
        CalendarView(model: model, settings: settings, data: data,
                     openSettings: { [weak self] in self?.openSettings() },
                     close: { [weak self] in
                         if self?.calendarWindow?.isVisible == true { self?.calendarWindow?.close() }
                         else { self?.closePopover() }
                     }, pin: { [weak self] in self?.pinCalendarWindow() })
    }
    private var calendarHeight: Double {
        78 + 6 * max(27, settings.panelHeight / 8.4) + (settings.config.hideFooter ? 0 : 36)
    }
    private func resizeCalendarContent() {
        let size = NSSize(width: settings.panelWidth, height: calendarHeight)
        popover.contentSize = size
        calendarWindow?.setContentSize(size)
        let appearance: NSAppearance? = settings.config.theme == .system ? nil : NSAppearance(named: settings.config.theme == .dark ? .darkAqua : .aqua)
        popover.appearance = appearance
        calendarWindow?.appearance = appearance
        settingsWindow?.appearance = appearance
    }
    private func applyPreferences() {
        updateStatus()
        if settings.config.shortcutEnabled, let key = GlobalShortcut.keyEquivalent(for: settings.config.shortcutKeyCode) {
            calendarMenuItem?.keyEquivalent = key
            var mask: NSEvent.ModifierFlags = []
            if settings.config.shortcutModifiers & 256 != 0 { mask.insert(.command) }
            if settings.config.shortcutModifiers & 512 != 0 { mask.insert(.shift) }
            if settings.config.shortcutModifiers & 2048 != 0 { mask.insert(.option) }
            if settings.config.shortcutModifiers & 4096 != 0 { mask.insert(.control) }
            calendarMenuItem?.keyEquivalentModifierMask = mask
        } else { calendarMenuItem?.keyEquivalent = "l"; calendarMenuItem?.keyEquivalentModifierMask = .command }
        resizeCalendarContent()
        let registration = settings.config.shortcutEnabled ? "\(settings.config.shortcutKeyCode):\(settings.config.shortcutModifiers)" : "disabled"
        if registration != registeredShortcut {
            registeredShortcut = registration
            if settings.config.shortcutEnabled {
                settings.shortcutError = shortcut?.register(keyCode: settings.config.shortcutKeyCode,
                    modifiers: settings.config.shortcutModifiers, action: { [weak self] in self?.togglePopover() })
            } else { shortcut?.unregister(); settings.shortcutError = nil }
        }
        timer?.invalidate()
        let seconds = settings.config.showSeconds ? 1.0 : 15.0
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let now = Date(), engine = model.engine, day = engine.info(for: now)
        let title = NSMutableAttributedString(string: "")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        for module in settings.config.statusModules where module.enabled {
            var text: String?
            if module.id == "icon" {
                if title.length > 0 { title.append(NSAttributedString(string: " ", attributes: attributes)) }
                let attachment = NSTextAttachment()
                attachment.image = calendarIcon(day: day.dayNumber)
                attachment.bounds = NSRect(x: 0, y: -3, width: 19, height: 19)
                title.append(NSAttributedString(attachment: attachment))
                continue
            }
            switch module.id {
            case "solar": text = now.formatted(["M月d日", "M.d", "M/d", "d"][min(3, max(0, module.format))])
            case "lunar": text = module.format == 0 ? day.lunarShort : engine.lunarInfo(for: now).monthName + engine.lunarInfo(for: now).dayName
            case "week":
                let weekday = Calendar.current.component(.weekday, from: now) - 1
                let chinese = ["日", "一", "二", "三", "四", "五", "六"][weekday]
                text = module.format == 0 ? "星期" + chinese : module.format == 1 ? "周" + chinese : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday]
            case "time":
                let format = ["HH:mm", "hh:mm", "ahh:mm"][min(2, max(0, module.format))] + (settings.config.showSeconds ? ":ss" : "")
                text = now.formatted(format)
            case "custom": if !settings.config.customFormat.isEmpty { text = now.formatted(settings.config.customFormat) }
            default: break
            }
            if let text, !text.isEmpty {
                if title.length > 0 { title.append(NSAttributedString(string: " ", attributes: attributes)) }
                title.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        if title.length == 0 { title.append(NSAttributedString(string: "历", attributes: attributes)) }
        button.image = nil
        button.attributedTitle = title
        button.toolTip = "\(engine.monthTitle(now))\(day.dayNumber)日\n\(day.lunarLong)\n按 ⌘ 拖动可调整菜单栏位置"
    }
    private func calendarIcon(day: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 19), flipped: false) { rect in
            NSColor.labelColor.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 16, height: 15), xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.2; outline.stroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 2, y: 12.5)); line.line(to: NSPoint(x: 17, y: 12.5))
            line.lineWidth = 1; line.stroke()
            let digits = NSAttributedString(string: String(day), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor.labelColor])
            let size = digits.size()
            digits.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: 2.2))
            return true
        }
        image.isTemplate = true
        return image
    }
    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            addItem("回到今天", action: #selector(goToday), to: menu)
            addItem("固定日历窗口", action: #selector(pinFromMenu), to: menu)
            menu.addItem(.separator())
            addItem("偏好设置…", action: #selector(settingsFromMenu), to: menu, key: ",")
            menu.addItem(.separator())
            addItem("退出MiniCal", action: #selector(quit), to: menu, key: "q")
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else { togglePopover() }
    }
    private func togglePopover() { popover.isShown ? closePopover() : openPopover() }
    private func hoverEntered() {
        hoverRevision += 1
        let revision = hoverRevision
        guard settings.config.hoverOpen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.hoverRevision == revision, self.settings.config.hoverOpen, !self.popover.isShown else { return }
            self.openPopover()
        }
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if settings.config.shortcutEnabled && UInt32(event.keyCode) == settings.config.shortcutKeyCode {
            var mask: UInt32 = 0
            if event.modifierFlags.contains(.command) { mask |= 256 }
            if event.modifierFlags.contains(.shift) { mask |= 512 }
            if event.modifierFlags.contains(.option) { mask |= 2048 }
            if event.modifierFlags.contains(.control) { mask |= 4096 }
            if mask == settings.config.shortcutModifiers { if !event.isARepeat { togglePopover() }; return nil }
        }
        let calendarHost = calendarWindow?.isKeyWindow == true || popover.contentViewController?.view.window?.isKeyWindow == true
        guard calendarHost, event.window?.attachedSheet == nil, !model.jumpPresented,
              !(event.window?.firstResponder is NSTextView), !model.showDetails else { return event }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { openSettings(); return nil }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
        switch event.keyCode {
        case 123: model.moveMonth(-1)
        case 124: model.moveMonth(1)
        case 126: model.moveMonth(-12)
        case 125: model.moveMonth(12)
        case 49: model.today()
        case 36, 76: model.showDetails = true
        case 53: if calendarWindow?.isKeyWindow == true { calendarWindow?.close() } else { closePopover() }
        default: return event
        }
        return nil
    }
    private func installMenu() {
        let menu = NSMenu(), root = NSMenuItem(), appMenu = NSMenu()
        let calendarItem = NSMenuItem(title: "显示日历", action: #selector(calendarFromMenu), keyEquivalent: "l")
        calendarItem.target = self; appMenu.addItem(calendarItem); calendarMenuItem = calendarItem
        addItem("偏好设置…", action: #selector(settingsFromMenu), to: appMenu, key: ",")
        appMenu.addItem(.separator())
        addItem("退出MiniCal", action: #selector(quit), to: appMenu, key: "q")
        root.submenu = appMenu; menu.addItem(root)
        let edit = NSMenu(title: "编辑"), editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editRoot.submenu = edit; menu.addItem(editRoot)
        NSApp.mainMenu = menu
    }
    private func addItem(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item)
    }
    @objc private func calendarFromMenu() { statusItem?.button?.performClick(nil) }
    @objc private func goToday() { model.today(); openPopover() }
    @objc private func pinFromMenu() { pinCalendarWindow() }
    @objc private func settingsFromMenu() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard !fixtures else { settings.loginError = nil; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            settings.loginError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许MiniCal。" : nil
        } catch { settings.loginError = error.localizedDescription }
    }
    private func setHolidayNotifications(_ enabled: Bool) {
        guard !fixtures else { settings.notificationError = nil; return }
        Task {
            do { try await HolidayNotifications.setEnabled(enabled); settings.notificationError = nil }
            catch { settings.notificationError = error.localizedDescription }
        }
    }
    private func subscribe(_ input: String) {
        guard var components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["webcal", "http", "https"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil else {
            data.errorMessage = "请输入有效的 webcal、http 或 https 日历订阅地址。"; return
        }
        guard !fixtures else { data.errorMessage = "虚拟模式已验证订阅地址；不会打开系统日历。"; return }
        components.scheme = "webcal"
        if let url = components.url, NSWorkspace.shared.open(url) { data.errorMessage = nil }
        else { data.errorMessage = "系统未能打开日历订阅地址。" }
    }
    private func importICS() {
        let panel = NSOpenPanel()
        panel.title = "选择日历文件"
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let bytes = try Data(contentsOf: url)
                let drafts = try await data.importICS(data: bytes, previewOnly: true)
                let alert = NSAlert()
                alert.messageText = "导入 \(drafts.count) 个事件？"
                alert.informativeText = drafts.prefix(8).map(\.title).joined(separator: "\n") + "\n\n" + (fixtures ? "仅写入本次虚拟数据。" : "确认后将添加到系统默认日历。")
                alert.addButton(withTitle: "导入"); alert.addButton(withTitle: "取消")
                guard !drafts.isEmpty, alert.runModal() == .alertFirstButtonReturn else { return }
                _ = try await data.importICS(data: bytes, previewOnly: false)
            } catch { data.errorMessage = error.localizedDescription }
        }
    }
}

@MainActor private final class StatusHoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next); area = next
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
