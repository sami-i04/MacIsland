import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct AirDropView: View {
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var state: IslandState
    private var isDragging: Bool { state.isDragging }
    private var targeted: Bool { state.airDropTargeted }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.elementRadius)
                .fill(targeted ? Color.blue.opacity(0.35) : Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: Layout.elementRadius)
                .strokeBorder(targeted ? Color.blue : Color.white.opacity(0.12), lineWidth: 1.5)
            VStack(spacing: 6) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 18))
                    .foregroundStyle(targeted ? .white : .blue)
                Text("AirDrop").font(.system(size: 12, weight: .medium))
                if !isDragging && !shelf.items.isEmpty {
                    Text("Ablage senden")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .contentShape(Rectangle())
        .onTapGesture { AirDrop.send(shelf.items) }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { state.airDropTargeted }, set: { state.airDropTargeted = $0 })) { providers in
            loadFileURLs(providers) { AirDrop.send($0) }
            return true
        }
    }
}
