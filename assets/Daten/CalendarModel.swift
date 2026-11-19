import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct NextEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let color: NSColor
}

final class CalendarModel: ObservableObject {
    @Published private(set) var next: NextEvent?
    @Published private(set) var authorized = false
    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                if granted { self?.refresh() } else { log.info("Kalenderzugriff nicht erlaubt") }
            }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard authorized else { return }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 86_400), calendars: nil)
        let ev = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
        let n = ev.map { NextEvent(title: $0.title ?? String(localized: "Termin"), start: $0.startDate, end: $0.endDate,
                                   color: $0.calendar?.color ?? .systemBlue) }
        if n != next { next = n }
    }

    static func when(_ e: NextEvent, now: Date = Date()) -> String {
        if e.start <= now { return String(localized: "Jetzt") }
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = .current
        time.setLocalizedDateFormatFromTemplate("jmm")
        let t = time.string(from: e.start)
        if cal.isDateInToday(e.start) {
            let mins = Int(e.start.timeIntervalSince(now) / 60)
            return mins < 60 ? String(localized: "in \(max(mins, 1)) Min") : t
        }
        if cal.isDateInTomorrow(e.start) { return String(localized: "Morgen \(t)") }
        let day = DateFormatter()
        day.locale = .current
        day.dateFormat = "EE"
        return "\(day.string(from: e.start).replacingOccurrences(of: ".", with: "")) \(t)"
    }
}
