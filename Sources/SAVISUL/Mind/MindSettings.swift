#if MOULD_ENGINE
import AppKit
import Carbon.HIToolbox
import MouldEngine
import SwiftUI

/// The assistant's switches in the Features tab.
enum MindFeatures {
    @MainActor static let group = FeatureGroup(
        id: "assistant", symbol: "sparkles", title: MindPhrases.group, detail: MindPhrases.groupDetail,
        main: FeatureItem(id: "assistant", key: \.assistant, title: MindPhrases.enable, detail: MindPhrases.enableDetail),
        options: [FeatureItem(id: "assistantHotkey", key: \.assistantHotkey, title: MindPhrases.hotkey, keys: ["⌃", "⌥", "H"])])
}

extension Suite {
    /// ⌃⌥H opens the assistant. The engine itself starts the first time it's needed, not with the app.
    func applyAssistant(_ settings: SuiteSettings) {
        if settings.assistant && settings.assistantHotkey {
            if !HotKeyCenter.shared.isRegistered("mind.panel") {
                HotKeyCenter.shared.register("mind.panel", .control(kVK_ANSI_H), press: { MindPanel.shared.toggle() })
            }
        } else {
            HotKeyCenter.shared.unregister("mind.panel")
        }
        if !settings.assistant {
            MindPanel.shared.close()
            MindHost.shared.stop()
        }
    }
}

/// Settings → Assistant: where it thinks, what it may send, the local model, its folders and its memory.
struct MindCard: View {
    let suite: Suite

    var body: some View {
        let host = MindHost.shared
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(symbol: "sparkles", tint: Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MindPhrases.group.text).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(MindPhrases.enableDetail.text).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                GlassSwitch(isOn: suite.settings.assistant) { suite.settings.assistant.toggle() }
                    .accessibilityLabel(MindPhrases.enable.text)
            }
            if suite.settings.assistant {
                field(MindPhrases.mode.text) {
                    Menu {
                        ForEach(RouterPolicy.Mode.allCases, id: \.self) { mode in
                            Button(MindPhrases.modeTitle(mode).text) { host.mode = mode }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(MindPhrases.modeTitle(host.mode).text).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
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
                ToggleRow(symbol: "lock.shield", tint: Palette.positive, title: MindPhrases.personalToCloud.text, detail: MindPhrases.personalDetail.text,
                          isOn: host.personalToCloud) { host.personalToCloud.toggle() }
                Hairline()
                models(host)
                Hairline()
                folders(host)
                Hairline()
                PhotoSettings(search: PhotoSearch.shared)
                Hairline()
                HStack(spacing: 8) {
                    Text(MindPhrases.memories(host.memories)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    Spacer()
                    PillButton(title: MindPhrases.journal.text, symbol: "list.bullet.rectangle") {
                        NSWorkspace.shared.activateFileViewerSelecting([MindHost.storage.appendingPathComponent("journal")])
                    }
                    PillButton(title: MindPhrases.forget.text, tint: Palette.danger) { host.clearMemory() }
                        .disabled(host.memories == 0)
                }
            }
        }
        .card()
        .onAppear {
            guard suite.settings.assistant else { return }
            if host.engine == nil { host.start() } else { host.syncLocalModels() }
        }
    }

    @ViewBuilder private func models(_ host: MindHost) -> some View {
        let local = host.models.filter { $0.locality == .local && $0.backend == "local" }
        field(MindPhrases.localModel.text) {
            ForEach(local, id: \.id) { profile in
                HStack(spacing: 6) {
                    Image(systemName: "cpu").foregroundStyle(Palette.positive)
                    Text(profile.title).foregroundStyle(Palette.ink)
                    if host.loadedModels.contains(profile.id) {
                        Text("· " + MindPhrases.loaded.text).foregroundStyle(Palette.tertiary)
                    }
                }
                .font(.system(size: 12.5, weight: .medium))
            }
            if local.contains(where: { $0.id == "local:" + LocalModels.recommendedID }) {
                EmptyView()
            } else if let fraction = host.downloading {
                HStack(spacing: 10) {
                    ProgressView(value: fraction).tint(Palette.accent)
                    Text(Say.percent(fraction * 100)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.secondary).monospacedDigit()
                    Button { host.cancelDownload() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.tertiary)
                }
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(LocalModels.recommended.title) · \(Say.bytes(LocalModels.recommended.bytes))")
                            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink)
                        if !local.isEmpty {
                            Text(MindPhrases.betterModel.text).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    PillButton(title: MindPhrases.download.text, symbol: "arrow.down.circle.fill", prominent: true) { host.downloadRecommended() }
                }
            }
            if let problem = host.downloadProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(Palette.warning).fixedSize(horizontal: false, vertical: true)
            }
            if !LocalModels.serverInstalled {
                Text(MindPhrases.installLlama.text).font(.system(size: 11)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        field(MindPhrases.cloudModel.text) {
            let cloud = host.models.first { $0.locality == .cloud || $0.backend != "local" }
            Text(cloud.map { "\($0.title) · \(AIService.shared.provider.title)" } ?? "\(MindPhrases.none.text) · \(MindPhrases.cloudFromAI.text)")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(cloud == nil ? Palette.tertiary : Palette.ink)
            if cloud != nil && host.mode != .localOnly {
                Text(MindPhrases.ownModel.text).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func folders(_ host: MindHost) -> some View {
        field(MindPhrases.folders.text) {
            ForEach(host.folders, id: \.self) { folder in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().frame(width: 16, height: 16)
                    Text(folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(size: 12.5)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { host.removeFolder(folder) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.tertiary)
                }
            }
            PillButton(title: MindPhrases.addFolder.text, symbol: "plus") { pickFolder(host) }
            Footnote(MindPhrases.foldersDetail.text)
        }
    }

    private func pickFolder(_ host: MindHost) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { host.addFolder(url) }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
            content()
        }
    }
}
#endif
