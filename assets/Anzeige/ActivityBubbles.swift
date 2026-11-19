import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct ActivityBubbles: View {
    @ObservedObject var activities: ActivityCenter
    let islandWidth: CGFloat
    let diameter: CGFloat
    let offsetX: CGFloat

    var body: some View {
        let half = islandWidth / 2
        let out = half + Layout.bubbleGap + diameter / 2
        let inside = max(0, half - diameter / 2 - 2)
        ZStack(alignment: .top) {
            if let a = activities.left {
                ActivityBubble(activity: a, diameter: diameter)
                    .scaleEffect(activities.leftShown ? (activities.hovered == false ? Layout.bubbleHoverScale : 1) : 0.55)
                    .offset(x: offsetX - (activities.leftShown ? out : inside))
                    .onTapGesture { activities.open(a.kind) }
            }
            if let a = activities.right {
                ActivityBubble(activity: a, diameter: diameter)
                    .scaleEffect(activities.rightShown ? (activities.hovered == true ? Layout.bubbleHoverScale : 1) : 0.55)
                    .offset(x: offsetX + (activities.rightShown ? out : inside))
                    .onTapGesture { activities.open(a.kind) }
            }
        }
        .padding(.top, Layout.bubbleInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct ActivityBubble: View {
    let activity: Activity
    let diameter: CGFloat

    private var color: Color {
        Color(nsColor: .systemGreen)
    }
    private var symbol: String {
        if activity.completed { return "checkmark" }
        switch activity.kind {
        case .download: return "arrow.down"
        case .charging: return "bolt.fill"
        }
    }

    var body: some View {
        let ring: CGFloat = 2.8
        let inset: CGFloat = ring / 2
        ZStack {
            Circle().fill(Color.black)
            Circle()
                .stroke(color.opacity(0.25), lineWidth: ring)
                .padding(inset)
            Circle()
                .trim(from: 0, to: CGFloat(activity.progress))
                .stroke(color, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(inset)
                .animation(.linear(duration: 0.9), value: activity.progress)
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.32, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(activity.completed ? 1.18 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: activity.completed)
        .contentShape(Circle())
        .help(activity.kind == .download ? String(localized: "Downloads") : String(localized: "Batterie"))
    }
}
