import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class QuickNote: ObservableObject {
    private let key = "quickNote"
    @Published var text: String {
        didSet { UserDefaults.standard.set(text, forKey: key) }
    }
    init() { text = UserDefaults.standard.string(forKey: "quickNote") ?? "" }
}
