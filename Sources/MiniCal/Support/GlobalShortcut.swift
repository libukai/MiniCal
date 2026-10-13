import Carbon
import Foundation
import os

/// Carbon hot keys are system-registered shortcuts and do not require an
/// Accessibility permission or a global keyboard-monitoring entitlement.
@MainActor final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private let signature: OSType = 0x4D43414C // MCAL, private to MiniCal.

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == 0x4D43414C, identity.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            Logger(subsystem: "com.libukai.MiniCal", category: "Shortcut").notice("Registered shortcut activated")
            Task { @MainActor in shortcut.action?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> String? {
        unregister()
        guard handler != nil else { return "无法建立系统快捷键处理器。" }
        let identity = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, identity, GetEventDispatcherTarget(), 0, &hotKey)
        guard status == noErr else {
            return status == eventHotKeyExistsErr
                ? "这个快捷键已被其他应用占用，请重新选择。"
                : "无法注册快捷键（系统代码 \(status)）。"
        }
        self.action = action
        return nil
    }

    static func keyEquivalent(for code: UInt32) -> String? {
        let keys: [UInt32:String] = [0:"a",1:"s",2:"d",3:"f",4:"h",5:"g",6:"z",7:"x",8:"c",9:"v",11:"b",12:"q",13:"w",14:"e",15:"r",16:"y",17:"t",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"o",32:"u",33:"[",34:"i",35:"p",37:"l",38:"j",39:"'",40:"k",41:";",42:"\\",43:",",44:"/",45:"n",46:"m",47:".",49:" ",50:"`"]
        return keys[code]
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        action = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
