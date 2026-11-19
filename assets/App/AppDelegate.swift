import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let models = SharedModels()
    private var builtInConfig = NotchConfig()
    private var islands: [CGDirectDisplayID: [IslandController]] = [:]
    private var allIslands: [IslandController] { islands.values.flatMap { $0 } }
    private var watchdogTimer: Timer?
    private let chooser = ActivityScreenChooser()

    private func updateActivityScreen() {
        let target = chooser.choose()
        let available = islands.keys.contains { $0 == target }
        for (id, cs) in islands {
            let show = available ? id == target : islands.count == 1 || CGDisplayIsBuiltin(id) != 0
            cs.forEach { $0.setShowsActivities(show) }
        }
    }

    private func syncIslands() {
        let screens = NSScreen.screens.filter { s in
            IslandController.externalEnabled || CGDisplayIsBuiltin(IslandController.displayID(s)) != 0
        }
        let wanted = screens.isEmpty ? [IslandController.builtInScreen()] : screens
        let ids = Set(wanted.map(IslandController.displayID))

        for (id, cs) in islands where !ids.contains(id) {
            cs.forEach { $0.shutdown() }
            islands[id] = nil
        }
        for s in wanted {
            let id = IslandController.displayID(s)
            if let cs = islands[id] {
                cs.forEach { $0.screensChanged() }
                continue
            }
            let cfg = NotchConfig.forScreen(s, builtIn: builtInConfig)
            func make(_ role: IslandController.SpaceRole) -> IslandController {
                IslandController(state: IslandState(config: cfg, builtIn: builtInConfig, models: models),
                                 screen: s, role: role)
            }
            if cfg.closedHeight == nil {
                islands[id] = [make(.all)]
            } else {
                islands[id] = [make(.fullscreen), make(.desktop)]
            }
        }
        updateActivityScreen()
    }

    private func recoverAfterSleep() {
        log.info("Aufgewacht – stelle wieder her")
        syncIslands()
        allIslands.forEach { $0.recover() }
        models.music.ensureRunning()
        models.music.spectrum.restart()
        models.battery.refresh()
        models.calendar.refresh()
    }

    private func watchdog() {
        if islands.count != NSScreen.screens.filter({ IslandController.externalEnabled
            || CGDisplayIsBuiltin(IslandController.displayID($0)) != 0 }).count { syncIslands() }
        allIslands.forEach { $0.ensureVisible() }
        updateActivityScreen()
        models.music.ensureRunning()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        builtInConfig = NotchConfig.load()
        models.start()
        syncIslands()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.syncIslands() }
        NotificationCenter.default.addObserver(
            forName: IslandController.externalToggled, object: nil, queue: .main
        ) { [weak self] _ in self?.syncIslands() }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.recoverAfterSleep() }
            }
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.models.music.spectrum.stop()
        }

        let w = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.watchdog() }
        RunLoop.main.add(w, forMode: .common)
        watchdogTimer = w

        log.info("MacIsland gestartet")
    }

    func applicationWillTerminate(_ notification: Notification) {
        models.music.stop()
    }
}
