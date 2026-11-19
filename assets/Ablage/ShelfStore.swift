import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    @Published var selection: Set<URL> = []
    var focused = false

    func selectAll() { selection = Set(items) }
    func deselectAll() { if !selection.isEmpty { selection.removeAll() } }

    func click(_ url: URL, toggle: Bool) {
        if toggle {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
        } else if !selection.contains(url) {
            selection = [url]
        }
    }

    func dragItems(for url: URL) -> [URL] {
        selection.contains(url) ? items.filter { selection.contains($0) } : [url]
    }

    func removeSelected() {
        items.removeAll { selection.contains($0) }
        selection.removeAll()
        persist()
    }
    private let key = "shelfItems"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
        persist()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        selection.remove(url)
        persist()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}

enum AirDrop {
    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            log.error("AirDrop kann diese Objekte nicht senden")
        }
    }
}

func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let group = DispatchGroup()
    let lock = NSLock()
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}
