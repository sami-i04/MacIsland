import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

enum ActivityKind { case download, charging }

struct Activity: Equatable {
    var kind: ActivityKind
    var progress: Double
    var completed = false
}

final class ActivityCenter: ObservableObject {
    @Published private(set) var right: Activity?
    @Published private(set) var left: Activity?
    @Published private(set) var rightShown = false
    @Published private(set) var leftShown = false
    @Published private(set) var hovered: Bool?

    func setHovered(_ h: Bool?) {
        guard hovered != h else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { hovered = h }
    }

    private let downloads = DownloadMonitor()

    private let appear = Animation.spring(response: 0.5, dampingFraction: 0.66)
    private let melt = Animation.spring(response: 0.42, dampingFraction: 0.85)

    func start(battery: BatteryModel) {
        battery.onChange = { [weak self, weak battery] in
            guard let self, let battery else { return }
            self.batteryChanged(battery)
        }
        batteryChanged(battery)
        downloads.onProgress = { [weak self] in self?.update(.download, progress: $0) }
        downloads.onFinished = { [weak self] ok in self?.finish(.download, success: ok) }
        downloads.start()
    }

    private var notChargingSince: Date?

    private func batteryChanged(_ b: BatteryModel) {
        if b.onAC && b.percent < 100 {
            if b.charging { notChargingSince = nil } else if notChargingSince == nil { notChargingSince = Date() }
            if let since = notChargingSince, Date().timeIntervalSince(since) > 45, contains(.charging) {
                finish(.charging, success: true)
                return
            }
            if notChargingSince == nil || contains(.charging) || Date().timeIntervalSince(notChargingSince!) < 45 {
                update(.charging, progress: Double(b.percent) / 100)
            }
        } else {
            notChargingSince = nil
            if contains(.charging) {
                finish(.charging, success: b.onAC)
            }
        }
    }

    private func contains(_ k: ActivityKind) -> Bool { right?.kind == k || left?.kind == k }

    func update(_ kind: ActivityKind, progress: Double) {
        let p = min(1, max(0, progress))
        if right?.kind == kind, right?.completed == false { if right!.progress != p { right!.progress = p }; return }
        if left?.kind == kind, left?.completed == false { if left!.progress != p { left!.progress = p }; return }
        if right?.kind == kind || left?.kind == kind { return }
        let a = Activity(kind: kind, progress: p)
        if right == nil {
            right = a
            DispatchQueue.main.async { withAnimation(self.appear) { self.rightShown = true } }
        } else if left == nil {
            left = a
            DispatchQueue.main.async { withAnimation(self.appear) { self.leftShown = true } }
        }
    }

    func finish(_ kind: ActivityKind, success: Bool) {
        let isRight = right?.kind == kind
        guard isRight || left?.kind == kind else { return }
        if success {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
                if isRight { right?.completed = true; right?.progress = 1 } else { left?.completed = true; left?.progress = 1 }
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            NSSound(named: "Tink")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.hide(right: isRight) }
        } else {
            hide(right: isRight)
        }
    }

    private func hide(right isRight: Bool) {
        withAnimation(melt) { if isRight { rightShown = false } else { leftShown = false } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if isRight, !self.rightShown { self.right = nil }
            if !isRight, !self.leftShown { self.left = nil }
        }
    }

    func open(_ kind: ActivityKind) {
        switch kind {
        case .charging:
            if let u = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                NSWorkspace.shared.open(u)
            }
        case .download:
            Self.openBrowserDownloads()
        }
    }

    static func openBrowserDownloads() {
        guard let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!),
              let id = Bundle(url: browser)?.bundleIdentifier?.lowercased() else {
            return openDownloadsFolder()
        }
        if id.contains("safari") {
            let script = """
            tell application "Safari" to activate
            delay 0.25
            tell application "System Events" to keystroke "l" using {command down, option down}
            """
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                if let err { log.error("Safari-Downloads: \(err.description)") }
            }
            return
        }
        let page: String?
        if id.contains("firefox") { page = "about:downloads" }
        else if id.contains("chrome") || id.contains("brave") || id.contains("edge") || id.contains("vivaldi")
                    || id.contains("arc") || id.contains("opera") { page = "chrome://downloads" }
        else { page = nil }
        if let page, let u = URL(string: page) {
            NSWorkspace.shared.open([u], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        } else {
            openDownloadsFolder()
        }
    }

    private static func openDownloadsFolder() {
        if let d = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(d)
        }
    }
}

final class DownloadMonitor {
    var onProgress: ((Double) -> Void)?
    var onFinished: ((Bool) -> Void)?

    private var token: Any?
    private var items: [ObjectIdentifier: (Progress, NSKeyValueObservation)] = [:]
    private var anySucceeded = false

    func start() {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        token = Progress.addSubscriber(forFileURL: dir) { [weak self] p in
            DispatchQueue.main.async { self?.add(p) }
            return { DispatchQueue.main.async { self?.remove(p) } }
        }
    }

    private func add(_ p: Progress) {
        let obs = p.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.report() }
        }
        items[ObjectIdentifier(p)] = (p, obs)
        report()
    }

    private func remove(_ p: Progress) {
        guard items.removeValue(forKey: ObjectIdentifier(p)) != nil else { return }
        let done = !p.isCancelled && (p.isFinished || p.fractionCompleted >= 0.99
            || (p.totalUnitCount > 0 && p.completedUnitCount >= p.totalUnitCount))
        if done { anySucceeded = true }
        if items.isEmpty {
            onFinished?(anySucceeded)
            anySucceeded = false
        } else {
            report()
        }
    }

    private func report() {
        guard !items.isEmpty else { return }
        let ps = items.values.map(\.0)
        let total = ps.reduce(0.0) { $0 + max(Double($1.totalUnitCount), 1) }
        let done = ps.reduce(0.0) { $0 + $1.fractionCompleted * max(Double($1.totalUnitCount), 1) }
        onProgress?(total > 0 ? done / total : 0)
    }
}
