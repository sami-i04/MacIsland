import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class ActivityScreenChooser {
    private var sameHeight = false

    func choose() -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let builtIn = screens.first { CGDisplayIsBuiltin(IslandController.displayID($0)) != 0 }
        let top = screens.max { $0.frame.maxY < $1.frame.maxY }!
        guard let b = builtIn, screens.count > 1 else { return IslandController.displayID(builtIn ?? top) }

        let ratio = screens.filter { $0 != b }.map { s -> CGFloat in
            let overlap = max(0, min(s.frame.maxY, b.frame.maxY) - max(s.frame.minY, b.frame.minY))
            return overlap / min(s.frame.height, b.frame.height)
        }.max() ?? 0

        if sameHeight { if ratio < 0.5 { sameHeight = false } }
        else if ratio >= 0.6 { sameHeight = true }

        return IslandController.displayID(sameHeight ? b : top)
    }
}
