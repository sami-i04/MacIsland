import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class BatteryModel: ObservableObject {
    @Published private(set) var percent = 100
    @Published private(set) var onAC = true
    @Published private(set) var charging = false
    @Published private(set) var remaining: Double?
    private var timer: Timer?

    var onChange: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        refresh()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryModel>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = src
        }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let p = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : 0
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let ch = d[kIOPSIsChargingKey] as? Bool ?? false
            if percent != p { percent = p }
            if onAC != ac { onAC = ac }
            if charging != ch { charging = ch }
        }
        let est = IOPSGetTimeRemainingEstimate()
        let rem: Double? = est > 0 ? est : nil
        if remaining != rem { remaining = rem }
        onChange?()
    }

    var label: String {
        if onAC { return charging ? String(localized: "Lädt · \(percent) %") : "\(percent) %" }
        guard let r = remaining else { return "Max: –" }
        let h = Int((r / 3600).rounded())
        return h >= 1 ? String(localized: "Max: \(h)H") : String(localized: "Max: \(max(1, Int(r / 60)))M")
    }

    var symbol: String {
        if onAC { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var tint: Color {
        if onAC { return Color(nsColor: .systemGreen) }
        return percent <= 20 ? Color(nsColor: .systemRed) : .white
    }
}
