import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct TopStrip: View {
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var battery: BatteryModel
    let notchWidth: CGFloat
    let height: CGFloat
    let musicActive: Bool
    let inMusic: Bool
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if musicActive {
                    SwitchArrow(inMusic: inMusic, onSwitch: onSwitch)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                } else {
                    EventPill(calendar: calendar)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: musicActive)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth + 16)
            BatteryLabel(battery: battery)
                .opacity(musicActive && !inMusic ? 0 : 1)
                .blur(radius: musicActive && !inMusic ? 4 : 0)
                .scaleEffect(musicActive && !inMusic ? 0.85 : 1, anchor: .trailing)
                .animation(musicActive && !inMusic ? .easeOut(duration: 0.15)
                                                    : .easeOut(duration: 0.25).delay(0.15),
                           value: musicActive && !inMusic)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: height)
    }
}

struct SwitchArrow: View {
    let inMusic: Bool
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
            Image(systemName: inMusic ? "square.grid.2x2.fill" : "music.note")
                .font(.system(size: 10, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 22)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .contentShape(Capsule())
        .onHover { if $0 { onSwitch() } }
        .help(inMusic ? String(localized: "Zu Apps & Quick Note") : String(localized: "Zur Musiksteuerung"))
    }
}

struct EventPill: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            if let e = calendar.next {
                let c = Color(nsColor: e.color)
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .bold))
                        Text(e.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(c)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(c.opacity(0.22)))
                    .layoutPriority(0)

                    Text(CalendarModel.when(e, now: ctx.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
                .help(e.title)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 9, weight: .bold))
                    Text(calendar.authorized ? String(localized: "Keine Termine") : String(localized: "Kalender erlauben"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
        }
    }
}

struct BatteryLabel: View {
    @ObservedObject var battery: BatteryModel

    var body: some View {
        HStack(spacing: 5) {
            Text(battery.label)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            Image(systemName: battery.symbol)
                .font(.system(size: 13, weight: .regular))
        }
        .foregroundStyle(battery.tint)
        .help("Akku \(battery.percent) %")
    }
}
