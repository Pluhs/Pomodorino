import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

struct StoredColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        self.init(nsColor: NSColor(color))
    }

    init(nsColor: NSColor) {
        let nsColor = nsColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let accentDefault = StoredColor(red: 0.039, green: 0.518, blue: 1)
    static let workDefault = StoredColor(red: 1, green: 0.231, blue: 0.188)
    static let breakDefault = StoredColor(red: 0.204, green: 0.78, blue: 0.349)
    static let pausedDefault = StoredColor(red: 0.56, green: 0.56, blue: 0.58)
}

class AppSettings: ObservableObject {
    @Published var workDuration: Int {
        didSet { UserDefaults.standard.set(workDuration, forKey: "workDuration") }
    }
    @Published var shortBreakDuration: Int {
        didSet { UserDefaults.standard.set(shortBreakDuration, forKey: "shortBreakDuration") }
    }
    @Published var longBreakDuration: Int {
        didSet { UserDefaults.standard.set(longBreakDuration, forKey: "longBreakDuration") }
    }
    @Published var pomodorosBeforeLongBreak: Int {
        didSet { UserDefaults.standard.set(pomodorosBeforeLongBreak, forKey: "pomodorosBeforeLongBreak") }
    }
    @Published var autoStartNextSession: Bool {
        didSet { UserDefaults.standard.set(autoStartNextSession, forKey: "autoStartNextSession") }
    }
    @Published var audioEnabled: Bool {
        didSet { UserDefaults.standard.set(audioEnabled, forKey: "audioEnabled") }
    }
    @Published var tickerEnabled: Bool {
        didSet { UserDefaults.standard.set(tickerEnabled, forKey: "tickerEnabled") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }
    @Published var shortcutKeyCode: Int {
        didSet { UserDefaults.standard.set(shortcutKeyCode, forKey: "shortcutKeyCode") }
    }
    @Published var shortcutModifiers: Int {
        didSet { UserDefaults.standard.set(shortcutModifiers, forKey: "shortcutModifiers") }
    }
    @Published var accentColor: StoredColor {
        didSet { saveColor(accentColor, forKey: "accentColor") }
    }
    @Published var workTimerColor: StoredColor {
        didSet { saveColor(workTimerColor, forKey: "workTimerColor") }
    }
    @Published var breakTimerColor: StoredColor {
        didSet { saveColor(breakTimerColor, forKey: "breakTimerColor") }
    }
    @Published var pausedTimerColor: StoredColor {
        didSet { saveColor(pausedTimerColor, forKey: "pausedTimerColor") }
    }
    @Published var menuBarPillEnabled: Bool {
        didSet { UserDefaults.standard.set(menuBarPillEnabled, forKey: "menuBarPillEnabled") }
    }

    init() {
        let defaults = UserDefaults.standard

        defaults.register(defaults: [
            "workDuration": 25,
            "shortBreakDuration": 5,
            "longBreakDuration": 15,
            "pomodorosBeforeLongBreak": 4,
            "autoStartNextSession": false,
            "audioEnabled": true,
            "tickerEnabled": true,
            "launchAtLogin": false,
            "shortcutKeyCode": 35,
            "shortcutModifiers": 6144,
            "menuBarPillEnabled": true,
        ])

        self.workDuration = defaults.integer(forKey: "workDuration")
        self.shortBreakDuration = defaults.integer(forKey: "shortBreakDuration")
        self.longBreakDuration = defaults.integer(forKey: "longBreakDuration")
        self.pomodorosBeforeLongBreak = defaults.integer(forKey: "pomodorosBeforeLongBreak")
        self.autoStartNextSession = defaults.bool(forKey: "autoStartNextSession")
        self.audioEnabled = defaults.bool(forKey: "audioEnabled")
        self.tickerEnabled = defaults.bool(forKey: "tickerEnabled")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.shortcutKeyCode = defaults.integer(forKey: "shortcutKeyCode")
        self.shortcutModifiers = defaults.integer(forKey: "shortcutModifiers")
        self.accentColor = Self.loadColor(forKey: "accentColor", default: .accentDefault)
        self.workTimerColor = Self.loadColor(forKey: "workTimerColor", default: .workDefault)
        self.breakTimerColor = Self.loadColor(forKey: "breakTimerColor", default: .breakDefault)
        self.pausedTimerColor = Self.loadColor(forKey: "pausedTimerColor", default: .pausedDefault)
        self.menuBarPillEnabled = defaults.bool(forKey: "menuBarPillEnabled")
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }

    func resetColors() {
        accentColor = .accentDefault
        workTimerColor = .workDefault
        breakTimerColor = .breakDefault
        pausedTimerColor = .pausedDefault
    }

    private static func loadColor(forKey key: String, default defaultColor: StoredColor) -> StoredColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? JSONDecoder().decode(StoredColor.self, from: data)
        else {
            return defaultColor
        }
        return color
    }

    private func saveColor(_ color: StoredColor, forKey key: String) {
        guard let data = try? JSONEncoder().encode(color) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
