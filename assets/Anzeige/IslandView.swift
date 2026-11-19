import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct IslandView: View {
    @ObservedObject var state: IslandState

    private var tr: CGFloat { state.isOpen ? Layout.openTopRadius : CGFloat(state.config.topRadius) }
    private var size: CGSize {
        state.isOpen
            ? CGSize(width: state.openWidth, height: Layout.openHeight)
            : CGSize(width: state.config.width + (state.compactMusic ? 2 * Layout.compactSide : 0),
                     height: state.closedHeight)
    }

    private var shelfVisible: Bool { state.isOpen && state.isDragging }
    private var homeVisible: Bool { state.isOpen && !musicMode && !state.isDragging }
    private var musicMode: Bool { state.musicMode }

    private var compactSpring: Animation {
        state.compactMusic ? .spring(response: 0.42, dampingFraction: 0.66) : .spring(response: 0.34, dampingFraction: 0.88)
    }

    private var widthSpring: Animation {
        state.isOpen ? .spring(response: 0.378, dampingFraction: 0.612) : .spring(response: 0.306, dampingFraction: 0.86)
    }
    private var heightSpring: Animation {
        state.isOpen ? .spring(response: 0.45, dampingFraction: 0.678) : .spring(response: 0.27, dampingFraction: 0.90)
    }
    private var contentAnimation: Animation {
        state.isOpen ? .spring(response: 0.38, dampingFraction: 0.82).delay(0.06) : .easeOut(duration: 0.12)
    }

    var body: some View {
      ZStack(alignment: .top) {
        ActivityBubbles(activities: state.activities,
                        islandWidth: size.width,
                        diameter: CGFloat(state.config.height) - 2 * Layout.bubbleInset,
                        offsetX: CGFloat(state.config.offsetX))
            .opacity(state.showsActivities ? 1 : 0)
            .allowsHitTesting(state.showsActivities)
            .animation(.easeOut(duration: 0.25), value: state.showsActivities)
            .animation(widthSpring, value: state.isOpen)
            .animation(compactSpring, value: state.compactMusic)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.black
                    .contextMenu {
                        Button("Ablage leeren") { state.shelf.clear() }
                        Divider()
                        Button(IslandController.externalEnabled ? String(localized: "Nur auf dem MacBook-Display anzeigen")
                                                                : String(localized: "Auch auf externen Displays anzeigen")) {
                            IslandController.externalEnabled.toggle()
                            NotificationCenter.default.post(name: IslandController.externalToggled, object: nil)
                        }
                        Divider()
                        Button("MacIsland beenden") { NSApp.terminate(nil) }
                    }

                MusicLayer(music: state.music,
                           expanded: musicMode,
                           homeMode: state.musicHomeMode,
                           visible: musicMode || state.musicHomeMode || (state.compactMusic && !state.isOpen),
                           notchHeight: CGFloat(state.config.height),
                           closedBottomRadius: CGFloat(state.config.bottomRadius),
                           contentAnimation: contentAnimation)
                    .padding(.horizontal, tr)
                    .frame(width: size.width + 2 * tr, height: size.height, alignment: .top)

            }
            .overlay(alignment: .top) {
                TopStrip(calendar: state.calendar, battery: state.battery,
                         notchWidth: CGFloat(state.config.width), height: CGFloat(state.config.height),
                         musicActive: state.music.showCompact && !state.isDragging,
                         inMusic: musicMode,
                         onSwitch: { state.toggleMusicHome() })
                    .padding(.horizontal, Layout.openTopRadius + Layout.contentInset + 2)
                    .frame(width: state.openWidth + 2 * Layout.openTopRadius)
                    .offset(x: 0, y: 0)
                    .opacity(state.isOpen ? 1 : 0)
                    .blur(radius: state.isOpen ? 0 : 6)
                    .scaleEffect(state.isOpen ? 1 : 0.8, anchor: .top)
                    .animation(contentAnimation, value: state.isOpen)
                    .allowsHitTesting(state.isOpen)
            }
            .overlay(alignment: .top) {
                HomeContent(apps: state.apps, note: state.note, shelf: state.shelf, state: state)
                    .padding(.top, CGFloat(state.config.height) + 4)
                    .padding(.horizontal, Layout.openTopRadius + Layout.contentInset)
                    .padding(.bottom, Layout.contentInset)
                    .frame(width: Layout.openWidth + 2 * Layout.openTopRadius, height: Layout.openHeight, alignment: .top)
                    .scaleEffect(homeVisible ? 1 : 0.55, anchor: .top)
                    .blur(radius: homeVisible ? 0 : 8)
                    .opacity(homeVisible ? 1 : 0)
                    .allowsHitTesting(homeVisible)
                    .animation(contentAnimation, value: homeVisible)
            }
            .overlay(alignment: .top) {
                    OpenContent(state: state)
                        .padding(.top, CGFloat(state.config.height) + 4)
                        .padding(.horizontal, Layout.openTopRadius + Layout.contentInset)
                        .padding(.bottom, Layout.contentInset)
                        .frame(width: Layout.openWidth + 2 * Layout.openTopRadius, height: Layout.openHeight, alignment: .top)
                        .scaleEffect(shelfVisible ? 1 : 0.55, anchor: .top)
                        .blur(radius: shelfVisible ? 0 : 8)
                        .opacity(shelfVisible ? 1 : 0)
                        .allowsHitTesting(shelfVisible)
                        .animation(contentAnimation, value: shelfVisible)
            }
            .frame(width: size.width + 2 * tr)
            .animation(widthSpring, value: state.isOpen)
            .animation(widthSpring, value: state.musicMode)
            .animation(compactSpring, value: state.compactMusic)
            .frame(height: size.height, alignment: .top)
            .clipShape(NotchShape(topRadius: tr,
                                  bottomRadius: state.isOpen ? Layout.openBottomRadius : state.closedBottomRadius))
            .animation(heightSpring, value: state.isOpen)
            .animation(compactSpring, value: state.compactMusic)
            .offset(x: CGFloat(state.config.offsetX))
            Spacer(minLength: 0)
        }
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}
