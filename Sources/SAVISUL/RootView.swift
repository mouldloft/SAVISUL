import SwiftUI

struct RootView: View {
    var model: AppModel
    var backdrop = false

    var body: some View {
        ZStack {
            if backdrop { PreviewWallpaper() }
            PanelBackdrop()
            VStack(spacing: 0) {
                PanelHeader(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                ZStack {
                    PaneScroll(model: model)
                        .id(model.pane)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .animation(.panelSpring, value: model.pane)
            }
            VStack {
                Spacer()
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
                TabBar(model: model)
                    .padding(.bottom, 14)
            }
            if model.menuOpen {
                Color.black.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeMenu() }
                    .transition(.opacity)
                MoreMenu(model: model)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .frame(width: Metrics.panelWidth, height: Metrics.panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .circular))
        .environment(\.colorScheme, .dark)
        .animation(.panelSpring, value: model.menuOpen)
        .animation(.panelSpring, value: model.toast)
    }
}

private struct PaneScroll: View {
    var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    pane
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 2)
                .padding(.bottom, 112)
            }
            .onChange(of: model.scrollToEnd) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .scrollIndicators(.never)
        .mask {
            // Content dissolves before it reaches the floating tab bar instead of showing around it.
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 44)
                Color.clear.frame(height: 60)
            }
        }
    }

    @ViewBuilder private var pane: some View {
        switch model.pane {
        case .energy: EnergyPane(model: model)
        case .sound: SoundPane(model: model)
        case .system: SystemPane(model: model)
        case .work: WorkPane(model: model)
        case .tools: ToolsPane(model: model)
        case .features: FeaturesPane(model: model, suite: Suite.shared)
        case .settings: SettingsPane(model: model)
        case .automations: AutomationsPane(model: model, engine: Suite.shared.automations)
        }
    }
}

struct PanelBackdrop: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .circular)
        ZStack {
            shape.fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.6))
            shape.fill(RadialGradient(colors: [Color.white.opacity(0.09), .clear], center: UnitPoint(x: 0.18, y: 0),
                                      startRadius: 0, endRadius: 340))
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.06), Color.white.opacity(0.14)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Stands in for the blurred desktop in offscreen QA renders, where the window material can't be drawn.
private struct PreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.17, green: 0.19, blue: 0.24), Color(red: 0.09, green: 0.09, blue: 0.11)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.42, green: 0.33, blue: 0.24).opacity(0.5), .clear],
                           center: UnitPoint(x: 0.85, y: 0.15), startRadius: 0, endRadius: 300)
        }
    }
}

private struct PanelHeader: View {
    var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    StoneMark()
                        .frame(width: 21, height: 12)
                    Text(model.text(model.pane.title))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                Text(model.subtitle(for: model.pane))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            StatusChips(model: model)
            GlassIconButton(symbol: "ellipsis", size: 34, selected: model.menuOpen, help: model.text(.moreMenu)) {
                model.toggleMenu()
            }
        }
    }
}

private struct StatusChips: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            if model.capture.isRecording {
                Button { model.toggleRecording() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.danger).frame(width: 7, height: 7)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(at: context.date))
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .floatingGlass(Capsule(), shadow: false)
                }
                .buttonStyle(PressableStyle())
                .help(model.text(.capStop))
            }
            if model.power.lidAwake && model.pane != .energy {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill").font(.system(size: 9.5, weight: .bold))
                    Text(model.text(.chipAwake)).font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .floatingGlass(Capsule(), shadow: false)
                .transition(.opacity)
            }
        }
    }

    private func elapsed(at date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(model.capture.recordingStart ?? date))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TabBar: View {
    var model: AppModel
    @Namespace private var space

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Pane.main) { pane in
                    tab(pane)
                }
            }
            .padding(4)
            .floatingGlass(Capsule())
            settingsButton
        }
        .animation(.panelSpring, value: model.pane)
    }

    private func tab(_ pane: Pane) -> some View {
        let selected = model.pane == pane
        return Button { model.select(pane) } label: {
            Image(systemName: selected ? pane.selectedSymbol : pane.symbol)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                .frame(width: 48, height: 40)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.17))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6))
                            .matchedGeometryEffect(id: "tab", in: space)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(model.text(pane.title))
        .accessibilityLabel(model.text(pane.title))
    }

    private var settingsButton: some View {
        let selected = model.pane == .settings
        return Button { model.select(.settings) } label: {
            Image(systemName: selected ? Pane.settings.selectedSymbol : Pane.settings.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                .frame(width: 48, height: 48)
                .background {
                    if selected {
                        Circle()
                            .fill(Color.white.opacity(0.17))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6))
                            .padding(4)
                    }
                }
                .floatingGlass(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(model.text(.tabSettings))
        .accessibilityLabel(model.text(.tabSettings))
    }
}

private struct MoreMenu: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                quick(model.pinned ? "pin.fill" : "pin", model.text(.menuKeepOpen), active: model.pinned) {
                    model.togglePinned()
                }
                quick("moon.zzz", model.text(.menuDisplayOff)) {
                    model.closeMenu()
                    model.run(.displayOff)
                }
                quick("camera.viewfinder", model.text(.menuScreenshot)) {
                    model.shoot(.selection)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            Hairline().padding(.horizontal, 14)
            VStack(spacing: 0) {
                row(model.text(.menuSettings), "gearshape") { model.select(.settings) }
                row(model.text(.menuActivityMonitor), "waveform.path.ecg") {
                    model.closeMenu()
                    model.run(.activity)
                }
                row(model.text(.menuQuit), "power", tint: Palette.danger) { NSApp.terminate(nil) }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 248)
        .floatingGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), strength: 1.25)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 60)
        .padding(.trailing, 14)
    }

    private func quick(_ symbol: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? Palette.onLight : Palette.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(active ? Palette.ink : Color.white.opacity(0.06)))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func row(_ title: String, _ symbol: String, tint: Color = Palette.ink, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, symbol: symbol, tint: tint, action: action)
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    var tint: Color = Palette.ink
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.08 : 0)).padding(.horizontal, 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
