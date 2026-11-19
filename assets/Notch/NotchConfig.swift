import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct NotchConfig: Codable {
    var width: Double = 185
    var height: Double = 32
    var topRadius: Double = 5.5
    var bottomRadius: Double = 10
    var offsetX: Double = 0
    var closedHeight: Double? = nil

    static func forScreen(_ s: NSScreen, builtIn: NotchConfig) -> NotchConfig {
        let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        if CGDisplayIsBuiltin(id) != 0, s.safeAreaInsets.top > 0 { return builtIn }
        var menuBar = s.frame.maxY - s.visibleFrame.maxY
        if menuBar < 20 || menuBar > 40 { menuBar = 24 }
        var c = builtIn
        c.height = Double(menuBar)
        c.offsetX = 0
        c.bottomRadius = min(builtIn.bottomRadius, Double(menuBar) * 0.42)
        c.closedHeight = max(4, (Double(menuBar) * 0.255).rounded())
        return c
    }

    static func load() -> NotchConfig {
        guard let url = Bundle.main.url(forResource: "notch_config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(NotchConfig.self, from: data) else {
            log.info("notch_config.json nicht gefunden – nutze eingebaute Standardwerte")
            return NotchConfig()
        }
        return c
    }
}

enum Layout {
    static let openWidth: CGFloat = 560
    static let openHeight: CGFloat = 137
    static let openBottomRadius: CGFloat = 26
    static let openTopRadius: CGFloat = 14
    static let contentInset: CGFloat = 16
    static let elementRadius: CGFloat = openBottomRadius - contentInset
    static let compactSide: CGFloat = 36
    static let compactArtwork: CGFloat = 22
    static let bubbleGap: CGFloat = 6
    static let bubbleInset: CGFloat = 4
    static let bubbleHoverScale: CGFloat = 1.15
    static let musicArtwork: CGFloat = 80
    static let musicVisualizer = CGSize(width: 38, height: 28)
    static let musicGap: CGFloat = 20
    static let musicOpenWidth: CGFloat = 497
    static let musicControlsWidth: CGFloat = musicOpenWidth - (contentInset + musicArtwork + musicGap)
        - (musicGap + musicVisualizer.width + contentInset + 4)
    static let hoverMargin: CGFloat = 8
    static let dragMargin: CGFloat = 60
    static let closeDelay: TimeInterval = 0.25
    static let openingPhase: TimeInterval = 0.35
}
