import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class SharedModels {
    let shelf = ShelfStore()
    let music = NowPlaying()
    let calendar = CalendarModel()
    let battery = BatteryModel()
    let apps = AppSlots()
    let note = QuickNote()
    let activities = ActivityCenter()

    func start() {
        music.start()
        calendar.start()
        battery.start()
        activities.start(battery: battery)
    }
}
