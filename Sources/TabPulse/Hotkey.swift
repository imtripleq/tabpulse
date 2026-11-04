import Carbon.HIToolbox
import Foundation

/// Control-Option-Command-J from any app. A Carbon hot key needs no Accessibility permission, unlike a key event
/// monitor, and macOS hands TabPulse only this one key combination.
final class Hotkey {
    var onPress: () -> Void = {}
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var loggedFailure = false

    func register() {
        guard ref == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // A C callback can't capture anything, so `self` travels as the user data pointer.
            InstallEventHandler(GetApplicationEventTarget(), { _, _, me in
                guard let me else { return OSStatus(eventNotHandledErr) }
                Unmanaged<Hotkey>.fromOpaque(me).takeUnretainedValue().onPress()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5450_4C53), id: 1)   // "TPLS"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status != noErr else { return }
        ref = nil
        if !loggedFailure {   // another app already took it
            NSLog("TabPulse: couldn't register Control-Option-Command-J (\(status))")
            loggedFailure = true
        }
    }

    func unregister() {
        guard let ref else { return }
        UnregisterEventHotKey(ref)
        self.ref = nil
    }
}
