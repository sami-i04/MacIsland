import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        canHide = false
        ignoresMouseEvents = true
        autorecalculatesKeyViewLoop = false
        initialFirstResponder = nil
    }

    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
    var keyHandler: ((NSEvent) -> Bool)?
    var onMouseDown: ((Bool) -> Void)?
    var requestKeyboard: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            let hit = contentView?.hitTest(contentView!.convert(event.locationInWindow, from: nil))
            var v: NSView? = hit
            var inText = false
            while let cur = v { if cur is NSTextView { inText = true; break }; v = cur.superview }
            allowKey = inText
            onMouseDown?(inText)
            if inText { requestKeyboard?() }
        }
        super.sendEvent(event)
    }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(nil)
    }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
