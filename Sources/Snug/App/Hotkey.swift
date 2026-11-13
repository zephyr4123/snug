// 全局快捷键 ⌃⌥⌘9：立即恢复屏幕。Carbon 热键，不需要任何权限
import Carbon.HIToolbox
import SnugCore

@MainActor
final class Hotkey {
    /// 'SNUG'
    static let signature: OSType = 0x534E_5547

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) { self.action = action }

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            guard let ctx else { return noErr }
            // 应用事件目标上的热键事件在主线程派发
            let hotkey = Unmanaged<Hotkey>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)
        guard installed == noErr else {
            Log.error("快捷键 ⌃⌥⌘9 的事件处理没装上（\(installed)）")
            return
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let err = RegisterEventHotKey(UInt32(kVK_ANSI_9), UInt32(cmdKey | optionKey | controlKey), id,
                                      GetApplicationEventTarget(), 0, &hotKeyRef)
        if err == noErr {
            Log.info("已注册快捷键 ⌃⌥⌘9")
        } else {
            Log.error("快捷键 ⌃⌥⌘9 注册失败（\(err)），可能被别的 App 占用")
        }
    }
}
