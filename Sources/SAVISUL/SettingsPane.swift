import AppKit
import SwiftUI

struct SettingsPane: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            LanguageCard(model: model)
            GeneralCard(model: model)
            AICard()
            PermissionsCard(model: model)
            AboutFooter(model: model)
        }
    }
}

private struct LanguageCard: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(model.text(.language))
            GlassSegmented(items: Language.allCases.map { SegmentItem(value: $0, title: $0.nativeName) },
                           selection: model.language) { model.setLanguage($0) }
        }
        .card()
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
