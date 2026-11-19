import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = min(topRadius, rect.height / 2)
        let left = rect.minX + tr
        let right = rect.maxX - tr
        let br = min(bottomRadius, (right - left) / 2, rect.height - tr)
        let top = rect.minY, bottom = rect.maxY
        let k: CGFloat = 0.45

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addCurve(to: CGPoint(x: left, y: top + tr),
                   control1: CGPoint(x: left - tr * k, y: top),
                   control2: CGPoint(x: left, y: top + tr * k))
        p.addLine(to: CGPoint(x: left, y: bottom - br))
        p.addCurve(to: CGPoint(x: left + br, y: bottom),
                   control1: CGPoint(x: left, y: bottom - br * k),
                   control2: CGPoint(x: left + br * k, y: bottom))
        p.addLine(to: CGPoint(x: right - br, y: bottom))
        p.addCurve(to: CGPoint(x: right, y: bottom - br),
                   control1: CGPoint(x: right - br * k, y: bottom),
                   control2: CGPoint(x: right, y: bottom - br * k))
        p.addLine(to: CGPoint(x: right, y: top + tr))
        p.addCurve(to: CGPoint(x: rect.maxX, y: top),
                   control1: CGPoint(x: right, y: top + tr * k),
                   control2: CGPoint(x: right + tr * k, y: top))
        p.closeSubpath()
        return p
    }
}
