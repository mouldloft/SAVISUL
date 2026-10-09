import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandFiles: View {
    let suite: Suite
    let model: IslandModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if suite.settings.islandShelf {
                ShelfZone(shelf: suite.shelf, targeted: model.dropTargeted || model.dragNearby)
                    .frame(maxWidth: .infinity)
            }
            if suite.settings.islandDownloads {
                DownloadsColumn(downloads: suite.downloads)
                    .frame(width: suite.settings.islandShelf ? 236 : nil)
                    .frame(maxWidth: suite.settings.islandShelf ? nil : .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

struct ShelfZone: View {
    let shelf: ShelfStore
    let targeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(Phrase("Shelf", ru: "Полка", uk: "Полиця", fr: "Étagère").text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                if !shelf.items.isEmpty {
                    Text("\(shelf.items.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Palette.onLight)
                        .padding(.horizontal, 6).frame(height: 16).background(Capsule().fill(Palette.accent))
                }
                Spacer()
                if !shelf.items.isEmpty {
                    RoundIcon(symbol: "dot.radiowaves.left.and.right", help: "AirDrop") { shelf.airDrop() }
                    RoundIcon(symbol: "folder", help: Phrases.reveal.text) { shelf.reveal() }
                    RoundIcon(symbol: "trash", help: Phrases.clear.text) { withAnimation(.islandQuick) { shelf.clear() } }
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(targeted ? Palette.accent.opacity(0.14) : Color.white.opacity(0.05))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(targeted ? Palette.accent : Color.white.opacity(0.14), style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [5, 4]))
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(targeted ? Palette.accent : Palette.tertiary)
                            .symbolEffect(.bounce, value: targeted)
                        Text(Phrase("Drop files here to keep them handy", ru: "Бросьте файлы сюда — пусть полежат под рукой",
                                    uk: "Киньте файли сюди — хай будуть під рукою", fr: "Déposez des fichiers ici pour les garder sous la main").text)
                            .font(.system(size: 11.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                        Text(Phrase("Or shake the pointer while dragging", ru: "Или встряхните курсор во время перетаскивания",
                                    uk: "Або струсніть курсор під час перетягування", fr: "Ou secouez le pointeur en glissant").text)
                            .font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(.horizontal, 12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item, shelf: shelf)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let shelf: ShelfStore
    @State private var hover = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    switch item.kind {
                    case .file:
                        FileThumb(path: item.path ?? "", size: 50)
                    case .link:
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.blue.opacity(0.18))
                            Image(systemName: "link").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.blue)
                        }
                        .frame(width: 50, height: 50)
                    case .text:
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.1))
                            Text(item.text ?? "").font(.system(size: 6.5)).foregroundStyle(Palette.secondary).lineLimit(6).padding(5)
                        }
                        .frame(width: 50, height: 50)
                    }
                }
                if hover {
                    Button { withAnimation(.islandQuick) { shelf.remove(item) } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).symbolRenderingMode(.palette)
                            .foregroundStyle(Palette.onLight, Palette.ink)
                    }
                    .buttonStyle(PressableStyle())
                    .offset(x: 6, y: -6)
                }
            }
            Text(item.title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Palette.secondary)
                .lineLimit(1).truncationMode(.middle).frame(width: 64)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { shelf.provider(for: item) }
        .contextMenu {
            Button(Phrases.open.text) { shelf.open(item) }
            Button(Phrases.copy.text) { shelf.copy(item) }
            if item.kind == .file { Button(Phrases.reveal.text) { shelf.reveal([item]) } }
            Button("AirDrop") { shelf.airDrop([item]) }
            Button(ContextPanelPhrases.actions.text) { Suite.shared.contextActions.open(with: ActionContext(shelf: item)) }
            Divider()
            Button(Phrases.remove.text) { shelf.remove(item) }
        }
        .help(item.title)
    }
}

/// Quick Look thumbnail with the Finder icon as a fallback.
struct FileThumb: View {
    let path: String
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: path) { image = await Thumbnails.shared.thumbnail(path: path, size: size) }
    }
}

private struct DownloadsColumn: View {
    let downloads: DownloadWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Phrase("Downloads", ru: "Загрузки", uk: "Завантаження", fr: "Téléchargements").text)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                RoundIcon(symbol: "arrow.up.forward.app", help: Phrases.open.text) { downloads.openFolder() }
            }
            VStack(spacing: 4) {
                ForEach(downloads.active.prefix(2)) { item in
                    HStack(spacing: 8) {
                        DownloadRing(progress: item.progress, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                            Text(item.progress.map { Say.percent($0 * 100) } ?? Say.bytes(item.bytes))
                                .font(.system(size: 9.5, design: .rounded).monospacedDigit()).foregroundStyle(Palette.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6).frame(height: 32)
                }
                ForEach(downloads.finished.prefix(max(0, 4 - min(downloads.active.count, 2)))) { item in
                    FinishedRow(item: item, downloads: downloads)
                }
                if downloads.active.isEmpty && downloads.finished.isEmpty {
                    Text(Phrase("Nothing new today", ru: "Сегодня ничего нового", uk: "Сьогодні нічого нового", fr: "Rien de neuf aujourd’hui").text)
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary).frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct FinishedRow: View {
    let item: DownloadWatcher.Finished
    let downloads: DownloadWatcher
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            FileThumb(path: item.url.path, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                Text([Say.bytes(item.size), Say.time(item.date)].joined(separator: " · "))
                    .font(.system(size: 9.5)).foregroundStyle(Palette.tertiary)
            }
            Spacer(minLength: 0)
            if hover {
                RoundIcon(symbol: "magnifyingglass", help: Phrases.reveal.text) { downloads.reveal(item) }
            }
        }
        .padding(.horizontal, 6).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { downloads.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }
}
