import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class IslandState: ObservableObject {
    @Published var isOpen = false
    @Published var isDragging = false
    @Published var shelfTargeted = false
    @Published var airDropTargeted = false
    @Published var hoveredItem: URL?
    @Published var config: NotchConfig
    let builtInConfig: NotchConfig
    let shelf: ShelfStore
    let music: NowPlaying
    let calendar: CalendarModel
    let battery: BatteryModel
    let apps: AppSlots
    let note: QuickNote
    let activities: ActivityCenter
    var requestKey: (() -> Void)?

    func focusShelf() {
        shelf.focused = true
        requestKey?()
    }

    func handleKey(_ e: NSEvent) -> Bool {
        guard shelf.focused, isOpen else { return false }
        let cmd = e.modifierFlags.contains(.command)
        if cmd, e.charactersIgnoringModifiers?.lowercased() == "a" { shelf.selectAll(); return true }
        if e.keyCode == 53 { shelf.deselectAll(); return true }
        if (e.keyCode == 51 || e.keyCode == 117), !shelf.selection.isEmpty {
            shelf.removeSelected(); return true
        }
        return false
    }
    private var musicSub: Any?

    var islandWidth: CGFloat {
        isOpen ? openWidth : CGFloat(config.width) + (compactMusic ? 2 * Layout.compactSide : 0)
    }

    var musicMode: Bool { isOpen && music.showCompact && !isDragging && !showHomeWhileMusic }
    @Published var showsActivities = true
    var closedHeight: CGFloat {
        if compactMusic || !thinNotch { return CGFloat(config.height) }
        return CGFloat(config.closedHeight ?? config.height)
    }
    var thinNotch = false
    var closedBottomRadius: CGFloat { min(CGFloat(config.bottomRadius), closedHeight / 2) }

    var compactMusic: Bool { music.showCompact && showsActivities }
    @Published var showHomeWhileMusic = false
    private var lastSwitch = Date.distantPast
    static let switchSpring = Animation.spring(response: 0.378, dampingFraction: 0.612)
    var musicHomeMode: Bool { isOpen && music.showCompact && !isDragging && showHomeWhileMusic }

    func toggleMusicHome() {
        guard Date().timeIntervalSince(lastSwitch) > 0.45 else { return }
        lastSwitch = Date()
        withAnimation(Self.switchSpring) { showHomeWhileMusic.toggle() }
    }
    var openWidth: CGFloat { musicMode ? Layout.musicOpenWidth : Layout.openWidth }

    init(config: NotchConfig, builtIn: NotchConfig, models m: SharedModels) {
        self.config = config
        self.builtInConfig = builtIn
        shelf = m.shelf; music = m.music; calendar = m.calendar; battery = m.battery
        apps = m.apps; note = m.note; activities = m.activities
        musicSub = music.$showCompact.dropFirst().removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
}
