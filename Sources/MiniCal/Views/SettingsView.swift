import AppKit
import SwiftUI
import MiniCalData

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var data: CalendarDataStore
    var onLoginToggle: (Bool) -> Void
    var onNotificationsToggle: (Bool) -> Void
    var onSubscription: (String) -> Void
    var onImportICS: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @UIState private var selectedTab = "general"
    @UIState private var newCalendarName = ""
    @UIState private var confirmCreate = false
    @UIState private var pendingDelete: CalendarList?
    @UIState private var subscriptionSheet = false
    @UIState private var subscriptionURL = ""
    @UIState private var recordingShortcut = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                general.tabItem { Label("通用", systemImage: "gearshape") }.tag("general")
                events.tabItem { Label("事件", systemImage: "calendar.badge.clock") }.tag("events")
                appearance.tabItem { Label("样式", systemImage: "paintpalette") }.tag("appearance")
                status.tabItem { Label("状态栏", systemImage: "menubar.rectangle") }.tag("status")
            }
            Divider()
            HStack {
                Text(data.useFixtures ? "演示模式 · 使用虚拟日历数据" : "MiniCal · 偏好设置")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("还原本页设置") { settings.reset(section: selectedTab) }
            }.padding(14)
        }
        .frame(width: 600, height: 650)
        .onChange(of: settings.config.launchAtLogin) { _, enabled in onLoginToggle(enabled) }
        .onChange(of: settings.config.notifyHolidays) { _, enabled in onNotificationsToggle(enabled) }
        .sheet(isPresented: $subscriptionSheet) { subscriptionForm }
        .confirmationDialog("新建日历“\(trimmedCalendarName)”？", isPresented: $confirmCreate, titleVisibility: .visible) {
            Button("新建日历") {
                let title = trimmedCalendarName
                Task { do { try await data.createCalendar(title: title); newCalendarName = "" } catch { data.errorMessage = error.localizedDescription } }
            }
            Button("取消", role: .cancel) {}
        } message: { Text(data.useFixtures ? "将创建演示日历。" : "将写入系统日历账户。") }
        .confirmationDialog("删除日历“\(pendingDelete?.title ?? "")”？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            if let calendar = pendingDelete {
                Button("删除日历及其中全部事件", role: .destructive) {
                    Task { do { try await data.deleteCalendar(id: calendar.id) } catch { data.errorMessage = error.localizedDescription } }
                    pendingDelete = nil
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { Text("删除会影响此日历内的所有事件，无法在应用中撤销。") }
    }

    private var general: some View {
        Form {
            Section("启动与交互") {
                Toggle("登录时启动", isOn: $settings.config.launchAtLogin)
                if let error = settings.loginError { errorText(error) }
                Toggle("鼠标悬停状态栏时打开月历", isOn: $settings.config.hoverOpen)
                Toggle("开关面板动画", isOn: $settings.config.animate)
            }
            Section("月历内容") {
                Toggle("隐藏农历", isOn: $settings.config.hideLunar)
                Toggle("隐藏底部日期详情", isOn: $settings.config.hideFooter)
                Toggle("显示事件圆点", isOn: $settings.config.showEventDots)
                Toggle("显示法定休假及补班角标", isOn: $settings.config.showHolidayBadges)
                Text("已更新至 2026 年官方放假与调休数据；未收录的年份不显示休班角标。").font(.caption).foregroundStyle(.secondary)
                Toggle("显示周数列", isOn: $settings.config.showWeekNumbers)
                Toggle("使用 ISO 周数", isOn: $settings.config.useISOWeekNumbers)
                Picker("一周开始于", selection: $settings.config.firstWeekday) {
                    ForEach(Array(["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"].enumerated()), id: \.offset) { index, day in Text(day).tag(index + 1) }
                }
            }
            Section("节假日通知") {
                Toggle("推送已收录年份的节假日通知", isOn: $settings.config.notifyHolidays)
                if let error = settings.notificationError { errorText(error) }
            }
            Section("全局快捷键") {
                Toggle("启用打开 / 关闭月历快捷键", isOn: $settings.config.shortcutEnabled)
                HStack {
                    Text("快捷键")
                    Spacer()
                    Button(recordingShortcut ? "请按组合键…" : shortcutTitle) {
                        settings.shortcutError = nil
                        recordingShortcut.toggle()
                    }
                    .overlay {
                        if recordingShortcut {
                            ShortcutCaptureView { keyCode, modifiers in
                                settings.config.shortcutKeyCode = keyCode
                                settings.config.shortcutModifiers = modifiers
                                settings.config.shortcutEnabled = true
                                recordingShortcut = false
                            } onCancel: { recordingShortcut = false }
                            onInvalid: { settings.shortcutError = "请同时按住 ⌘、⌥ 或 ⌃ 中至少一个修饰键。" }
                            .frame(width: 1, height: 1)
                        }
                    }
                    Button(recordingShortcut ? "取消" : "清除") {
                        recordingShortcut = false
                        settings.config.shortcutEnabled = false
                        settings.shortcutError = nil
                    }
                }
                if let error = settings.shortcutError { errorText(error) }
                Text("点击录制后输入组合键；Esc 取消。系统快捷键冲突会在注册时提示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var events: some View {
        Form {
            Section("访问权限") {
                HStack { Text("系统日历：\(data.eventAccess.labelString)"); Spacer(); Button("授权日历") { Task { await data.requestEventAccess() } }.disabled(data.eventAccess == .authorized) }
                HStack { Text("提醒事项：\(data.reminderAccess.labelString)"); Spacer(); Button("授权提醒事项") { Task { await data.requestReminderAccess() } }.disabled(data.reminderAccess == .authorized) }
                Toggle("在日期详情中显示提醒事项", isOn: $settings.config.showReminders)
                if let error = data.errorMessage { errorText(error) }
            }
            Section("显示的日历") {
                if data.calendars.isEmpty { Text(data.eventAccess == .authorized ? "没有可显示的日历，请刷新月历。" : "授权后可以选择日历。") .foregroundStyle(.secondary) }
                ForEach(data.calendars) { calendar in
                    HStack {
                        Circle().fill(Color(hex: calendar.colorHex)).frame(width: 8, height: 8)
                        Toggle(calendar.title, isOn: calendarVisibility(calendar.id))
                        Button { pendingDelete = calendar } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).disabled(!calendar.allowsModifications)
                            .help("删除此日历及其中所有事件")
                    }
                }
            }
            if settings.config.showReminders, !data.reminderLists.isEmpty {
                Section("显示的提醒事项列表") {
                    ForEach(data.reminderLists) { calendar in
                        HStack {
                            Circle().fill(Color(hex: calendar.colorHex)).frame(width: 8, height: 8)
                            Toggle(calendar.title, isOn: calendarVisibility(calendar.id))
                        }
                    }
                }
            }
            Section("新建与导入") {
                HStack {
                    TextField("新日历名称", text: $newCalendarName)
                    Button("新建…") { confirmCreate = true }
                        .disabled(trimmedCalendarName.isEmpty || data.eventAccess != .authorized)
                }
                HStack {
                    Button("订阅日历…") { subscriptionSheet = true }
                    Button("导入 ICS 文件…", action: onImportICS)
                }
            }
        }.formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("主题") {
                Picker("外观", selection: $settings.config.theme) { ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            Section("尺寸") {
                scaleSlider("面板宽度", value: $settings.config.widthScale, detail: "\(Int(settings.panelWidth)) pt")
                scaleSlider("面板高度", value: $settings.config.heightScale, detail: "\(Int(settings.panelHeight)) pt")
                scaleSlider("字体大小", value: $settings.config.fontScale, detail: String(format: "%.0f%%", settings.fontMultiplier * 100))
            }
            Section("\(editingDarkPalette ? "深色" : "浅色")主题颜色") {
                ForEach(paletteLabels, id: \.0) { key, title in
                    ColorPicker(title, selection: paletteBinding(key), supportsOpacity: true)
                }
            }
        }.formStyle(.grouped)
    }

    private var status: some View {
        Form {
            Section("显示模块 · 拖拽或使用箭头调整顺序") {
                List {
                    ForEach($settings.config.statusModules) { $module in
                        HStack(spacing: 8) {
                            Toggle(module.title, isOn: $module.enabled).frame(width: 105, alignment: .leading)
                            if module.id != "icon" && module.id != "custom" {
                                Picker("格式", selection: $module.format) {
                                    ForEach(Array(formatLabels(module.id).enumerated()), id: \.offset) { index, title in Text(title).tag(index) }
                                }.labelsHidden().frame(maxWidth: .infinity)
                            } else { Spacer() }
                            Button { moveModule(module.id, direction: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless).disabled(settings.config.statusModules.first?.id == module.id)
                            Button { moveModule(module.id, direction: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless).disabled(settings.config.statusModules.last?.id == module.id)
                        }
                    }.onMove { source, destination in settings.config.statusModules.move(fromOffsets: source, toOffset: destination) }
                }.frame(height: 220)
                if !settings.config.statusModules.contains(where: \.enabled) { Text("至少开启一个模块才能显示状态栏内容。将保留日历图标入口。") .font(.caption).foregroundStyle(.secondary) }
            }
            Section("时间与自定义格式") {
                Toggle("显示秒", isOn: $settings.config.showSeconds)
                TextField("自定义日期格式", text: $settings.config.customFormat)
                Text("例如 yyyy-MM-dd、MM月dd日 HH:mm。大写 MM 为月份，小写 mm 为分钟。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Text("预览"); Spacer(); Text(customPreview).monospacedDigit().textSelection(.enabled) }
            }
            Section("菜单栏位置") {
                Text("按住 ⌘ 拖动菜单栏图标调整位置。")
                    .foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var subscriptionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("订阅日历").font(.headline)
            TextField("webcal:// 或 https:// 日历地址", text: $subscriptionURL).textFieldStyle(.roundedBorder)
            Text("地址将交给系统日历处理订阅。应用不会在此窗口下载或导入远程内容。")
                .font(.caption).foregroundStyle(.secondary)
            if !subscriptionURL.isEmpty && !validSubscription { errorText("请输入包含服务器地址的 webcal、http 或 https URL。") }
            HStack { Spacer(); Button("取消") { subscriptionSheet = false }; Button("继续") { let address = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines); subscriptionSheet = false; onSubscription(address) }.disabled(!validSubscription).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 460)
    }

    private var validSubscription: Bool {
        guard let url = URL(string: subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["webcal", "http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }
    private var trimmedCalendarName: String { newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var editingDarkPalette: Bool { settings.config.theme == .dark || (settings.config.theme == .system && colorScheme == .dark) }
    private let paletteLabels = [("window", "背景"), ("title", "标题"), ("date", "日期"), ("weekend", "周末"), ("festival", "节日 / 节气"), ("today", "今天"), ("holiday", "休假"), ("workday", "补班"), ("event", "事件圆点")]
    private func paletteBinding(_ key: String) -> Binding<Color> {
        Binding(get: { Color(hex: settings.colorHex(for: key, dark: editingDarkPalette)) }, set: { color in settings.config.palette[(editingDarkPalette ? "dark." : "") + key] = color.hexRepresentation })
    }
    private func calendarVisibility(_ id: String) -> Binding<Bool> {
        Binding(get: { !settings.config.hiddenCalendarIDs.contains(id) }, set: { visible in settings.config.hiddenCalendarIDs.removeAll { $0 == id }; if !visible { settings.config.hiddenCalendarIDs.append(id) } })
    }
    private func errorText(_ message: String) -> some View { Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
    private func scaleSlider(_ title: String, value: Binding<Double>, detail: String) -> some View {
        HStack { Text(title).frame(width: 70, alignment: .leading); Slider(value: value, in: 0.2...1); Text(detail).font(.caption).monospacedDigit().frame(width: 60, alignment: .trailing) }
    }
    private func formatLabels(_ id: String) -> [String] {
        switch id {
        case "solar": return ["11月29日", "11.29", "11/29", "29"]
        case "lunar": return ["初五", "冬月初五"]
        case "week": return ["星期一", "周一", "Mon"]
        case "time": return ["24 小时", "12 小时", "上下午"]
        default: return []
        }
    }
    private func moveModule(_ id: String, direction: Int) {
        guard let index = settings.config.statusModules.firstIndex(where: { $0.id == id }), settings.config.statusModules.indices.contains(index + direction) else { return }
        settings.config.statusModules.swapAt(index, index + direction)
    }
    private var customPreview: String {
        let formatter = DateFormatter(); formatter.locale = .current; formatter.dateFormat = settings.config.customFormat
        return formatter.string(from: Date())
    }
    private var shortcutTitle: String {
        let modifiers = settings.config.shortcutModifiers
        let prefix = ((modifiers & 4096) != 0 ? "⌃" : "") + ((modifiers & 2048) != 0 ? "⌥" : "") + ((modifiers & 512) != 0 ? "⇧" : "") + ((modifiers & 256) != 0 ? "⌘" : "")
        let labels: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",53:"Esc",123:"←",124:"→",125:"↓",126:"↑"]
        return prefix + (labels[settings.config.shortcutKeyCode] ?? "键 \(settings.config.shortcutKeyCode)")
    }
}

/// Local first-responder capture only; no global event monitor or input access.
private struct ShortcutCaptureView: NSViewRepresentable {
    var onCapture: (UInt32, UInt32) -> Void
    var onCancel: () -> Void
    var onInvalid: () -> Void
    func makeNSView(context: Context) -> CaptureView { let view = CaptureView(); configure(view); return view }
    func updateNSView(_ view: CaptureView, context: Context) { configure(view) }
    private func configure(_ view: CaptureView) { view.onCapture = onCapture; view.onCancel = onCancel; view.onInvalid = onInvalid }
    final class CaptureView: NSView {
        var onCapture: ((UInt32, UInt32) -> Void)?
        var onCancel: (() -> Void)?
        var onInvalid: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self, let window = self.window else { return }; window.makeFirstResponder(self) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { guard window?.firstResponder === self else { return false }; capture(event); return true }
        override func keyDown(with event: NSEvent) { capture(event) }
        private func capture(_ event: NSEvent) {
            if event.keyCode == 53 { onCancel?(); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else { onInvalid?(); return }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= 256 }
            if flags.contains(.shift) { modifiers |= 512 }
            if flags.contains(.option) { modifiers |= 2048 }
            if flags.contains(.control) { modifiers |= 4096 }
            onCapture?(UInt32(event.keyCode), modifiers)
        }
    }
}
