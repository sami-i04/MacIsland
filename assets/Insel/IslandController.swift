import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class IslandController {
    private let state: IslandState
    private let panel: IslandPanel
    private var screen: NSScreen
    private var timer: Timer?
    private var closeWorkItem: DispatchWorkItem?

    private var lastDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var mouseWasDown = false

    let displayID: CGDirectDisplayID

    enum SpaceRole { case all, desktop, fullscreen }
    let role: SpaceRole
    private(set) var active = true

    init(state: IslandState, screen: NSScreen, role: SpaceRole = .all) {
        self.state = state
        self.screen = screen
        self.displayID = Self.displayID(screen)
        self.role = role
        state.thinNotch = role == .fullscreen
        self.panel = IslandPanel(contentRect: .zero)
        switch role {
        case .desktop:
            panel.collectionBehavior = [.stationary, .ignoresCycle]
        case .fullscreen:
            panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        case .all:
            break
        }
        let host = FirstMouseHostingView(rootView: IslandView(state: state))
        panel.contentView = host
        panel.keyHandler = { [weak state] e in state?.handleKey(e) ?? false }
        panel.onMouseDown = { [weak self] inText in
            guard let self else { return }
            self.state.shelf.focused = false
            if !inText {
                DispatchQueue.main.async {
                    if !self.state.shelf.focused { self.releaseKeyboard() }
                }
            }
        }
        panel.requestKeyboard = { [weak self] in self?.takeKeyboard() }
        state.requestKey = { [weak self] in self?.takeKeyboard() }
        move(to: screen)
        panel.orderFrontRegardless()
        startTracking()
        startFullscreenWatch()
        startEdgeGuard()
    }

    private var edgeMonitors: [Any] = []
    private var lastEdgeMouse = NSPoint.zero

    private func startEdgeGuard() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.guardEdge() }) {
            edgeMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.guardEdge(); return e }) {
            edgeMonitors.append(l)
        }
    }

    private func guardEdge() {
        guard active, let main = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let f = screen.frame
        let prev = lastEdgeMouse
        lastEdgeMouse = m
        let r = islandRect(open: state.isOpen, margin: 0)
        guard f.contains(prev), m.y >= f.maxY - 1, m.x >= r.minX, m.x <= r.maxX else { return }
        CGWarpMouseCursorPosition(CGPoint(x: m.x, y: main.frame.maxY - f.maxY + 2))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private var spaceTimer: Timer?

    private func startFullscreenWatch() {
        guard role != .all else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.assignSpaces()
            self?.updateActive()
            self?.keepWarm()
        }
        RunLoop.main.add(t, forMode: .common)
        spaceTimer = t
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.assignSpaces()
            self?.updateActive()
            self?.panel.displayIfNeeded()
            self?.keepWarm()
        }
        assignSpaces()
        updateActive()
    }

    private func keepWarm() {
        guard !active, let v = panel.contentView else { return }
        v.needsLayout = true
        v.needsDisplay = true
        v.layer?.setNeedsDisplay()
        v.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.invalidateShadow()
    }

    private func assignSpaces() {
        let all = SpaceInfo.spaces(displayID: displayID)
        guard !all.isEmpty else { return }
        let wanted = all.filter { role == .fullscreen ? $0.fullscreen : !$0.fullscreen }.map(\.id)
        SpaceInfo.assign(window: panel.windowNumber, to: wanted, allOnDisplay: all.map(\.id))
    }

    private func updateActive() {
        let fs = SpaceInfo.isFullscreen(displayID: displayID)
        let a = role == .fullscreen ? fs : !fs
        guard a != active else { return }
        active = a
        if !a {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            if state.isOpen { setOpen(false) }
            panel.ignoresMouseEvents = true
        }
    }

    func shutdown() {
        spaceTimer?.invalidate()
        timer?.invalidate()
        edgeMonitors.forEach(NSEvent.removeMonitor)
        edgeMonitors.removeAll()
        timer = nil
        closeWorkItem?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    static let externalToggled = Notification.Name("MacIslandExternalToggled")
    static var externalEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "showOnExternal") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showOnExternal") }
    }

    static func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first { Self.displayID($0) == displayID }
    }

    private func move(to s: NSScreen) {
        screen = s
        let c = NotchConfig.forScreen(s, builtIn: state.builtInConfig)
        if c.height != state.config.height || c.bottomRadius != state.config.bottomRadius || c.offsetX != state.config.offsetX {
            state.config = c
        }
        layout()
    }

    static func builtInScreen() -> NSScreen {
        NSScreen.screens.first {
            let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func screensChanged() {
        if let s = currentScreen() { move(to: s) }
    }

    func ensureVisible() {
        if !panel.isVisible, role != .desktop || active { panel.orderFrontRegardless() }
        guard let s = currentScreen() else { return }
        if !s.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.maxY - 1)) { move(to: s) }
    }

    func recover() {
        if let s = currentScreen() { move(to: s) }
        panel.ignoresMouseEvents = !state.isOpen || !active
        if role != .desktop || active { panel.orderFrontRegardless() }
        if timer == nil || timer?.isValid == false { startTracking() }
    }

    private func layout() {
        let tr = max(Layout.openTopRadius, CGFloat(state.config.topRadius))
        let w = Layout.openWidth + 2 * tr + 120
        let h = Layout.openHeight + 60
        let f = screen.frame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
        panel.setFrame(rect, display: true)
    }

    func setShowsActivities(_ v: Bool) {
        guard state.showsActivities != v else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { state.showsActivities = v }
    }

    private func islandRect(open: Bool, margin: CGFloat) -> NSRect {
        let c = state.config
        let w = open ? state.openWidth
                     : CGFloat(c.width) + (state.compactMusic ? 2 * Layout.compactSide : 0)
        let h = open ? Layout.openHeight : CGFloat(c.height)
        let f = screen.frame
        let x = f.midX + CGFloat(c.offsetX) - w / 2
        return NSRect(x: x, y: f.maxY - h, width: w, height: h + 1).insetBy(dx: -margin, dy: -margin)
    }

    private var previousApp: NSRunningApplication?

    func takeKeyboard() {
        if !NSApp.isActive {
            let front = NSWorkspace.shared.frontmostApplication
            if front != NSRunningApplication.current { previousApp = front }
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.allowKey = true
        if !panel.isKeyWindow { panel.makeKey() }
    }

    func releaseKeyboard() {
        guard NSApp.isActive || panel.isKeyWindow else { return }
        guard !NSApp.windows.contains(where: { !($0 is IslandPanel) && $0.isVisible && $0.canBecomeKey }) else { return }
        panel.makeFirstResponder(nil)
        panel.allowKey = false
        state.shelf.focused = false
        if let prev = previousApp, !prev.isTerminated {
            prev.activate()
        } else {
            NSApp.hide(nil)
            panel.orderFrontRegardless()
        }
        previousApp = nil
    }

    private func bubbleRects() -> [NSRect] { bubbleHits().map(\.rect) }

    private func bubbleHits() -> [(rect: NSRect, right: Bool)] {
        guard state.showsActivities else { return [] }
        let a = state.activities
        let d = CGFloat(state.config.height) - 2 * Layout.bubbleInset
        let half = state.islandWidth / 2
        let cx = screen.frame.midX + CGFloat(state.config.offsetX)
        let y = screen.frame.maxY - Layout.bubbleInset - d
        var rects: [(rect: NSRect, right: Bool)] = []
        if a.right != nil, a.rightShown {
            rects.append((NSRect(x: cx + half + Layout.bubbleGap, y: y, width: d, height: d), true))
        }
        if a.left != nil, a.leftShown {
            rects.append((NSRect(x: cx - half - Layout.bubbleGap - d, y: y, width: d, height: d), false))
        }
        return rects
    }

    private func startTracking() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var idleSkip = 0

    private func tick() {
        guard active else { return }
        let mouse = NSEvent.mouseLocation
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        if !state.isOpen, !mouseDown, closeWorkItem == nil,
           !islandRect(open: true, margin: 140).contains(mouse) {
            idleSkip += 1
            if idleSkip < 6 { return }
        }
        idleSkip = 0

        let dragCount = NSPasteboard(name: .drag).changeCount
        if !mouseDown {
            lastDragChangeCount = dragCount
            if state.isDragging { withAnimation(IslandState.switchSpring) { state.isDragging = false } }
        } else if dragCount != lastDragChangeCount, !state.isDragging {
            withAnimation(IslandState.switchSpring) { state.isDragging = true }
        }
        mouseWasDown = mouseDown

        let hit = bubbleHits().first { $0.rect.insetBy(dx: -2, dy: -2).contains(mouse) }
        state.activities.setHovered(hit?.right)
        if hit != nil {
            panel.ignoresMouseEvents = false
            closeWorkItem?.cancel()
            closeWorkItem = nil
            return
        } else if !state.isOpen {
            let over = islandRect(open: false, margin: 0).contains(mouse)
            if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        }

        let shouldOpen: Bool
        let sinceOpen = Date().timeIntervalSince(openedAt)
        if state.isOpen, !state.isDragging, sinceOpen < Layout.openingPhase {
            let p = CGFloat(sinceOpen / Layout.openingPhase)
            let a = islandRect(open: false, margin: Layout.hoverMargin)
            let b = islandRect(open: true, margin: 4)
            let grow = NSRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
                              width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
            shouldOpen = grow.contains(mouse)
        } else if state.isOpen {
            shouldOpen = islandRect(open: true, margin: state.isDragging ? Layout.dragMargin : 4).contains(mouse)
        } else if state.isDragging {
            shouldOpen = islandRect(open: false, margin: Layout.dragMargin).contains(mouse)
        } else {
            shouldOpen = !mouseDown && islandRect(open: false, margin: Layout.hoverMargin).contains(mouse)
        }

        if shouldOpen {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            if !state.isOpen { setOpen(true) }
            if state.isDragging, !state.shelfSession { state.shelfSession = true }
        } else if state.isOpen, sinceOpen < Layout.openingPhase, !state.isDragging {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            setOpen(false)
        } else if state.isOpen, closeWorkItem == nil {
            let item = DispatchWorkItem { [weak self] in
                self?.closeWorkItem = nil
                self?.setOpen(false)
            }
            closeWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.closeDelay, execute: item)
        }
    }

    private var openedAt = Date.distantPast

    private func setOpen(_ open: Bool) {
        if open { openedAt = Date() }
        state.isOpen = open
        if !open { state.showHomeWhileMusic = false; state.shelfSession = false }
        panel.ignoresMouseEvents = !open
        if !open, panel.isKeyWindow || NSApp.isActive {
            panel.makeFirstResponder(nil)
            state.shelf.focused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, !self.state.isOpen else { return }
                self.releaseKeyboard()
            }
        }
        if open {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
