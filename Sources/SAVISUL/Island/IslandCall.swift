import AppKit
import SwiftUI

/// The call in progress, with its controls: every microphone, the app's camera, the speakers, the output, the app itself, and hang up.
struct IslandCall: View {
    let suite: Suite
    let call: CallMonitor.Call
    @State private var busy: CallControls.Action?

    var body: some View {
        let output = suite.app?.audio.currentOutput
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CallAppIcon(call: call, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(call.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 6) {
                            Text("\(Phrases.onCallNow.text) · \(Say.clock(context.date.timeIntervalSince(call.since)))")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.positive)
                            if call.camera {
                                Label(Phrases.camera.text, systemImage: "video.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Palette.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            HStack(alignment: .top, spacing: 8) {
                CallButton(symbol: suite.callMicOff ? "mic.slash.fill" : "mic.fill",
                           title: suite.callMicOff ? Phrases.unmute.text : Phrases.mute.text, engaged: suite.callMicOff) {
                    suite.toggleCallMic()
                }
                CallButton(symbol: call.camera ? "video.fill" : "video.slash.fill", title: Phrases.cameraButton.text,
                           engaged: !call.camera, busy: busy == .camera) {
                    run(.camera)
                }
                CallButton(symbol: suite.callSoundOff ? "speaker.slash.fill" : "speaker.wave.2.fill", title: Phrases.soundButton.text,
                           engaged: suite.callSoundOff) {
                    suite.toggleCallSound()
                }
                CallButton(symbol: output?.symbol ?? "speaker.wave.2", title: output?.name ?? Phrases.outputButton.text, engaged: false) {
                    suite.sound.cycleOutput()
                }
                CallButton(symbol: "arrow.up.forward.app", title: Phrases.open.text, engaged: false) {
                    suite.openCallApp()
                }
                Spacer(minLength: 0)
                HangUpButton(busy: busy == .hangUp) { run(.hangUp) }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func run(_ action: CallControls.Action) {
        guard busy == nil else { return }
        busy = action
        suite.callAction(action) { busy = nil }
    }
}

/// The app's icon with a live dot, or the phone glyph when the app has no icon to show.
struct CallAppIcon: View {
    let call: CallMonitor.Call
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let path = call.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
            } else {
                ZStack {
                    Circle().fill(Palette.positive.opacity(0.18))
                    Image(systemName: "phone.fill").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Palette.positive)
                }
                .frame(width: size, height: size)
            }
            Circle().fill(Palette.positive).frame(width: size * 0.26, height: size * 0.26)
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                .modifier(Breathing())
        }
    }
}

/// A round control with its name under it; engaged controls turn white, the way a muted microphone does on iPhone.
private struct CallButton: View {
    let symbol: String
    let title: String
    let engaged: Bool
    var busy = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(engaged ? Palette.ink : Color.white.opacity(hover ? 0.18 : 0.11))
                    if busy {
                        Spinner(size: 15, color: engaged ? Palette.onLight : Palette.ink)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(engaged ? Palette.onLight : Palette.ink)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 44, height: 44)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 64)
            }
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.islandQuick, value: engaged)
    }
}

private struct HangUpButton: View {
    let busy: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Palette.danger.opacity(hover ? 1 : 0.92))
                    if busy {
                        Spinner(size: 15, color: .white)
                    } else {
                        Image(systemName: "phone.down.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .shadow(color: Palette.danger.opacity(hover ? 0.55 : 0.3), radius: hover ? 10 : 6)
                Text(Phrases.hangUp.text)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.danger)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.islandQuick, value: hover)
    }
}
