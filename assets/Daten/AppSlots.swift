import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class AppSlots: ObservableObject {
    static let count = 4
    @Published private(set) var apps: [URL?]
    @Published var hovered: Int?
    private let key = "appSlots"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        apps = (0..<Self.count).map { i in
            guard i < saved.count, !saved[i].isEmpty, FileManager.default.fileExists(atPath: saved[i]) else { return nil }
            return URL(fileURLWithPath: saved[i])
        }
    }

    func choose(_ i: Int) {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.title = String(localized: "App für Platz \(i + 1) wählen")
        p.prompt = String(localized: "Hinterlegen")
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = false
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url else { return }
            self?.set(i, url)
        }
    }

    func open(_ i: Int) {
        guard let url = apps[i] else { return choose(i) }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func set(_ i: Int, _ url: URL?) {
        apps[i] = url
        UserDefaults.standard.set(apps.map { $0?.path ?? "" }, forKey: key)
    }
}
