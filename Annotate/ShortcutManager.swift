import Foundation

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}

enum ShortcutKey: String, CaseIterable {
    case pen = "p"
    case arrow = "a"
    case line = "l"
    case highlighter = "h"
    case rectangle = "r"
    case circle = "o"
    case counter = "n"
    case text = "t"
    case select = "v"
    case eraser = "e"
    case colorPicker = "c"
    case lineWidthPicker = "w"
    case toggleBoard = "b"

    var defaultKey: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: return L10n.text("Pen")
        case .arrow: return L10n.text("Arrow")
        case .line: return L10n.text("Line")
        case .highlighter: return L10n.text("Highlighter")
        case .rectangle: return L10n.text("Rectangle")
        case .circle: return L10n.text("Circle")
        case .counter: return L10n.text("Counter")
        case .text: return L10n.text("Text")
        case .select: return L10n.text("Select")
        case .eraser: return L10n.text("Eraser")
        case .colorPicker: return L10n.text("Color Picker")
        case .lineWidthPicker: return L10n.text("Line Width")
        case .toggleBoard: return L10n.text("Toggle Board")
        }
    }
}

@MainActor
class ShortcutManager: @unchecked Sendable {
    static var shared = ShortcutManager()

    private let defaults: UserDefaults
    private let shortcutPrefix = "shortcut."

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    func getShortcut(for tool: ShortcutKey) -> String {
        defaults.string(forKey: shortcutPrefix + tool.rawValue) ?? tool.defaultKey
    }

    func setShortcut(_ key: String, for tool: ShortcutKey) {
        if isShortcutTaken(key, excluding: tool) {
            print("Shortcut '\(key)' is already in use.")
            return
        }
        defaults.set(key, forKey: shortcutPrefix + tool.rawValue)
        defaults.synchronize()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func resetToDefault(tool: ShortcutKey) {
        defaults.removeObject(forKey: shortcutPrefix + tool.rawValue)
        defaults.synchronize()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func resetAllToDefault() {
        ShortcutKey.allCases.forEach { tool in
            defaults.removeObject(forKey: shortcutPrefix + tool.rawValue)
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func isShortcutTaken(_ key: String, excluding tool: ShortcutKey) -> Bool {
        for otherTool in ShortcutKey.allCases where otherTool != tool {
            if getShortcut(for: otherTool) == key {
                return true
            }
        }
        return false
    }
}

extension ShortcutManager {
    var allShortcuts: [ShortcutKey: String] {
        Dictionary(uniqueKeysWithValues: ShortcutKey.allCases.map { ($0, getShortcut(for: $0)) })
    }
}
