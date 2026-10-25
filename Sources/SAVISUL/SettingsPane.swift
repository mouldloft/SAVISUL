import AppKit
import SwiftUI

struct SettingsPane: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            LanguageCard(model: model)
            #if SAVISUL_CLOUD
            CloudCard(model: model)
            #endif
            GeneralCard(model: model)
            WallpaperCard(model: model)
            UpdateCard()
            AICard()
            #if MOULD_ENGINE
            MindCard(suite: Suite.shared)
            #endif
            PermissionsCard(model: model)
            AboutFooter(model: model)
        }
    }
}

/// Each language says hello in its own words; the glow slides to the one chosen, and the panda waves every switch.
private struct LanguageCard: View {
    var model: AppModel
    @Namespace private var glow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                CardTitle(model.text(.language))
                Spacer(minLength: 8)
                // Waves at every switch, unless the person turned the panda off.
                if Suite.shared.settings.islandPanda {
                    PandaView(mood: .hello, size: 40)
                        .id(model.language)
                        .frame(width: 40, height: 30)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Language.allCases) { language in
                    LanguageTile(language: language, selected: model.language == language, glow: glow) {
                        if model.language != language { PandaVoice.speak(.hello) }
                        model.setLanguage(language)
                    }
                }
            }
        }
        .card()
        .animation(.panelSpring, value: model.language)
    }
}

private struct LanguageTile: View {
    let language: Language
    let selected: Bool
    let glow: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.greeting)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(selected ? 1 : 0.8))
                Text(language.nativeName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selected ? Palette.accent : Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hover ? 0.075 : 0.04))
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.accent.opacity(0.3), Palette.accent.opacity(0.07)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.accent.opacity(0.75), lineWidth: 1.2))
                            .shadow(color: Palette.accent.opacity(0.35), radius: 10)
                            .matchedGeometryEffect(id: "language", in: glow)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Palette.onLight, Palette.accent)
                        .padding(8)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .scaleEffect(hover && !selected ? 1.025 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.quickSpring, value: hover)
        .accessibilityLabel(language.nativeName)
    }
}

private struct GeneralCard: View {
    var model: AppModel

    var body: some View {
        let permissions = model.permissions
        VStack(spacing: 0) {
            CardTitle(model.text(.general))
                .padding(.bottom, 6)
            ToggleRow(symbol: "power", tint: Palette.accent, title: model.text(.openAtLogin),
                      detail: permissions.login == .requiresApproval ? model.text(.stApproval) : nil,
                      isOn: permissions.login != .denied) {
                model.permissions.setLogin(model.permissions.login == .denied)
            }
            if let error = permissions.loginError {
                InlineNotice(symbol: "exclamationmark.triangle.fill", text: model.format(.loginFailed, error))
                    .padding(.bottom, 6)
            }
            Hairline(inset: 42)
            ToggleRow(symbol: "dock.rectangle", title: model.text(.showInDock),
                      detail: model.statusVisible ? nil : model.text(.dockForced),
                      isOn: model.showInDock || !model.statusVisible) {
                model.setShowInDock(!model.showInDock)
            }
            Hairline(inset: 42)
            ToggleRow(symbol: "pin", title: model.text(.keepOpen), detail: model.text(.keepOpenDetail), isOn: model.pinned) {
                model.togglePinned()
            }
            Hairline(inset: 42)
            HStack(spacing: 12) {
                RowIcon(symbol: "command")
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.text(.shortcut))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(model.text(model.hotKeyReady ? .shortcutDetail : .shortcutBusy))
                        .font(.system(size: 11.5))
                        .foregroundStyle(model.hotKeyReady ? Palette.secondary : Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                HStack(spacing: 4) {
                    ForEach(["⌃", "⌥", "S"], id: \.self) { key in
                        Text(key)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24, height: 24)
                            .floatingGlass(RoundedRectangle(cornerRadius: 7, style: .continuous), shadow: false)
                    }
                }
                .opacity(model.hotKeyReady ? 1 : 0.45)
            }
            .padding(.vertical, 7)
            if !model.statusVisible {
                InlineNotice(symbol: "menubar.rectangle", text: model.text(.menuBarHidden))
                    .padding(.top, 8)
            }
        }
        .card()
    }
}

/// The person's own AI key for Context Actions. Nothing is sent anywhere without it.
private struct WallpaperCard: View {
    var model: AppModel

    var body: some View {
        let wallpaper = LiveWallpaper.shared
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(model.text(.wallpaper))
                .padding(.bottom, 4)
            Text(model.text(.wallpaperDetail))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            caption(model.text(.wpScene))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(WallpaperLandscape.allCases.filter { $0 != .custom || !wallpaper.customPath.isEmpty }) { scene in
                    WallpaperTile(title: model.text(scene.copy),
                                  image: SakuraArt.thumbnail(scene == .custom ? wallpaper.customPath : scene.art(for: .desktop).resource),
                                  selected: wallpaper.landscape == scene) { wallpaper.setLandscape(scene) }
                }
                WallpaperAddTile(title: model.text(.wpAdd)) { wallpaper.chooseCustomImage() }
            }
            .padding(.bottom, 14)
            caption(model.text(.wpWhere))
            GlassSegmented(items: WallpaperTarget.allCases.map { SegmentItem(value: $0, title: model.text($0.copy)) },
                           selection: wallpaper.target) { wallpaper.setTarget($0) }
                .padding(.bottom, 8)
            Hairline(inset: 42)
            ToggleRow(symbol: "cursorarrow.rays", tint: Palette.accent, title: model.text(.wallpaperGlow),
                      detail: model.text(.wallpaperGlowDetail), isOn: wallpaper.glow) {
                wallpaper.setGlow(!wallpaper.glow)
            }
        }
        .card()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.tertiary)
            .padding(.bottom, 6)
    }
}

/// One wallpaper in the gallery: its preview, its name, and a check when it is the one playing.
private struct WallpaperTile: View {
    let title: String
    let image: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.06)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Palette.onLight, Palette.accent)
                            .padding(6)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Color.white.opacity(hover ? 0.28 : 0.1), lineWidth: selected ? 2 : 1))
                .scaleEffect(hover && !selected ? 1.025 : 1)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.quickSpring, value: hover)
        .animation(.quickSpring, value: selected)
    }
}

/// The last tile: a dashed frame with a plus that opens a picture of the person's own.
private struct WallpaperAddTile: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(hover ? 0.42 : 0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0.03)))
                    .frame(height: 88)
                    .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.accent))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.quickSpring, value: hover)
    }
}

private struct UpdateCard: View {
    var body: some View {
        let updater = Updater.shared
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(UpdatePhrases.title.text)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(UpdatePhrases.version.text) \(updater.current)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(status(updater.state))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                PillButton(title: WhatsNewPhrases.open.text, symbol: "gift") { WhatsNew.shared.show() }
                if case .available = updater.state {
                    PillButton(title: UpdatePhrases.update.text, prominent: true) { updater.install() }
                } else if !updater.busy {
                    PillButton(title: UpdatePhrases.check.text, prominent: false) { updater.check() }
                }
            }
        }
        .card()
    }

    private func status(_ state: Updater.State) -> String {
        switch state {
        case .idle: UpdatePhrases.detail.text
        case .checking: UpdatePhrases.checking.text
        case .upToDate: UpdatePhrases.upToDate.text
        case .failed: UpdatePhrases.failed.text
        case let .available(version): UpdatePhrases.available.text + " " + version
        case let .downloading(version): UpdatePhrases.downloading.text + " " + version + "…"
        case .installing: UpdatePhrases.installing.text
        }
    }
}

private struct AICard: View {
    @State private var key = ""
    @State private var testing = false
    @State private var status: (ok: Bool, text: String)?

    var body: some View {
        let ai = AIService.shared
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(symbol: "sparkles", tint: AgentKind.claude.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AIPhrases.title.text).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(AIPhrases.detail.text).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            field(AIPhrases.service.text) {
                Menu {
                    ForEach(AIService.Provider.allCases) { provider in
                        Button(provider.title) {
                            ai.select(provider)
                            status = nil
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(ai.provider.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.28)))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            field(AIPhrases.key.text) {
                if ai.hasKey {
                    HStack(spacing: 8) {
                        Label(AIPhrases.keySaved.text, systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.positive)
                        Spacer()
                        Button(AIPhrases.remove.text) { ai.removeKey(); status = nil }
                            .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.danger)
                    }
                    .frame(height: 34)
                } else {
                    HStack(spacing: 8) {
                        SecureField(AIPhrases.keyPlaceholder.text, text: $key)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.28)))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                            .onSubmit(saveKey)
                        PillButton(title: AIPhrases.save.text, prominent: !key.isEmpty, action: saveKey)
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            field(AIPhrases.model.text) {
                GlassField(prompt: ai.provider.defaultModel.isEmpty ? AIPhrases.modelPlaceholder.text : ai.provider.defaultModel,
                           text: Binding(get: { ai.model }, set: { ai.model = $0 }), monospaced: true)
            }
            field(AIPhrases.address.text) {
                GlassField(prompt: ai.provider.defaultBase.isEmpty ? "https://" : ai.provider.defaultBase,
                           text: Binding(get: { ai.baseURL }, set: { ai.baseURL = $0 }), monospaced: true)
                Text(AIPhrases.addressHint.text).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if testing {
                    Spinner(size: 12, color: Palette.accent)
                } else if let status {
                    Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(status.ok ? Palette.positive : Palette.warning)
                        .lineLimit(2)
                }
                Spacer()
                PillButton(title: AIPhrases.test.text, symbol: "bolt.fill", action: test)
                    .disabled(!ai.ready || testing)
                    .opacity(ai.ready ? 1 : 0.5)
            }
        }
        .card()
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
            content()
        }
    }

    private func saveKey() {
        AIService.shared.setKey(key)
        key = ""
        status = nil
    }

    private func test() {
        testing = true
        status = nil
        Task { @MainActor in
            do {
                let reply = try await AIService.shared.ask(system: "Reply with the single word OK.", prompt: "Test")
                status = (true, AIPhrases.works.text + (reply.isEmpty ? "" : " · " + String(reply.prefix(24))))
            } catch {
                status = (false, error.localizedDescription)
            }
            testing = false
        }
    }
}

private struct PermissionsCard: View {
    var model: AppModel

    var body: some View {
        let permissions = model.permissions
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(model.text(.permissions))
                .padding(.bottom, 6)
            PermissionRow(model: model, symbol: "keyboard", title: model.text(.permAccessibility),
                          use: model.text(.permAccessibilityUse), state: permissions.accessibility) {
                model.requestTyping()
            }
            Hairline(inset: 42)
            PermissionRow(model: model, symbol: "rectangle.dashed.badge.record", title: model.text(.permScreen),
                          use: model.text(.permScreenUse), state: permissions.screen) {
                model.permissions.requestScreenRecording()
            }
            Hairline(inset: 42)
            PermissionRow(model: model, symbol: "bell.badge", title: model.text(.permNotifications),
                          use: model.text(.permNotificationsUse), state: permissions.notifications) {
                model.permissions.requestNotifications { _ in }
            }
            Hairline(inset: 42)
            PermissionRow(model: model, symbol: "lock.shield", title: model.text(.permAdmin),
                          use: model.text(.permAdminUse), state: nil, action: nil)
            Footnote(model.text(.permissionsNote))
                .padding(.top, 10)
        }
        .card()
    }
}

private struct PermissionRow: View {
    var model: AppModel
    let symbol: String
    let title: String
    let use: String
    let state: PermissionState?
    let action: (() -> Void)?

    var body: some View {
        let needsAction = action != nil && state != .granted
        HStack(alignment: .center, spacing: 12) {
            RowIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(use)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if needsAction {
                    HStack(spacing: 5) {
                        Circle().fill(tint).frame(width: 5, height: 5)
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if let action, needsAction {
                PillButton(title: model.text(state == .notDetermined ? .allow : .openSettings), prominent: true, action: action)
            } else {
                StatusBadge(text: badge, tint: tint)
            }
        }
        .padding(.vertical, 8)
        .animation(.panelSpring, value: state)
    }

    private var tint: Color {
        switch state {
        case .granted: Palette.positive
        case .denied: Palette.warning
        case .requiresApproval: Palette.warning
        case .notDetermined: Palette.secondary
        case nil: Palette.accent
        }
    }

    private var badge: String {
        switch state {
        case .granted: model.text(.stAllowed)
        case .denied: model.text(.stOff)
        case .requiresApproval: model.text(.stApproval)
        case .notDetermined: model.text(.stNotAsked)
        case nil: model.text(.stAskEachTime)
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
        .contentTransition(.opacity)
    }
}

private struct AboutFooter: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            StoneMark(color: Palette.secondary)
                .frame(width: 18, height: 15)
            Text("SAVISUL \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1")")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Spacer()
            PillButton(title: model.text(.menuQuit), symbol: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}
