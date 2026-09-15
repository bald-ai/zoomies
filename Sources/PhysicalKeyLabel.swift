import AppKit
import Carbon

/// Names physical keys using the unmodified active layout, independent of shortcut modifiers.
enum PhysicalKeyLabel {
    static let layoutChanged = Notification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String)

    static func name(for keyCode: UInt16, fallback: String) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        let data = unsafeBitCast(property, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return fallback }
        return translatedName(for: keyCode,
                              layout: UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self),
                              fallback: fallback)
    }

    static func translatedName(for keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>, fallback: String) -> String {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 16)
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return fallback }
        let value = String(utf16CodeUnits: characters, count: length)
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return value.uppercased()
    }
}

/// Distributed input-source notifications arrive while Settings/editor windows remain open.
final class KeyboardLayoutObservation {
    private var token: NSObjectProtocol?

    init(onChange: @escaping () -> Void) {
        token = DistributedNotificationCenter.default().addObserver(
            forName: PhysicalKeyLabel.layoutChanged, object: nil, queue: .main
        ) { _ in onChange() }
    }

    deinit {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
    }
}
