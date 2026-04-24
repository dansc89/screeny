import Carbon.HIToolbox

@MainActor
final class HotKeyManager {
    private struct RegisteredHotKey {
        let identifier: UInt32
        let reference: EventHotKeyRef
    }

    private static let signature: OSType = 0x534D4B59 // SMKY
    private nonisolated(unsafe) static var eventHandler: EventHandlerRef?
    private nonisolated(unsafe) static weak var callbackOwner: HotKeyManager?

    private var nextIdentifier: UInt32 = 1
    private var hotKeys: [UInt32: RegisteredHotKey] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    init() {
        Self.callbackOwner = self
        installEventHandlerIfNeeded()
    }

    func registerDefaultHotKeys(fullScreenHandler: @escaping () -> Void, interactiveHandler: @escaping () -> Void) {
        _ = register(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey), action: fullScreenHandler)
        _ = register(keyCode: 21, modifiers: UInt32(cmdKey | shiftKey), action: interactiveHandler)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let identifier = nextIdentifier
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return false
        }

        hotKeys[identifier] = RegisteredHotKey(identifier: identifier, reference: hotKeyRef)
        actions[identifier] = action
        nextIdentifier += 1
        return true
    }

    private func unregisterAll() {
        for entry in hotKeys.values {
            UnregisterEventHotKey(entry.reference)
        }
        hotKeys.removeAll()
        actions.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard Self.eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &Self.eventHandler
        )

        if status != noErr {
            assertionFailure("Failed to install hot key event handler: \(status)")
        }
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
        guard let event else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard parameterStatus == noErr else {
            return parameterStatus
        }

        Task { @MainActor in
            callbackOwner?.actions[hotKeyID.id]?()
        }
        return noErr
    }
}
