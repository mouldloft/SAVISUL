import AppKit
import SwiftUI

struct IslandHome: View {
    let suite: Suite

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if suite.settings.islandMusic {
                MediaCard(suite: suite)
                    .frame(width: 340)
            }
            VStack(spacing: 8) {
                if suite.settings.islandCalls, let call = suite.calls.current {
                    CallBlock(suite: suite, call: call)
                        .transition(.blurReplace)
                } else if suite.settings.islandCalendar {
                    CalendarBlock(feed: suite.calendar)
                }
                if suite.settings.islandTimers { TimerBlock(timers: suite.timers) }
                if suite.settings.islandDownloads, let active = suite.downloads.active.first { DownloadBlock(item: active) }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

// MARK: Media

private struct MediaCard: View {
    let suite: Suite
    @State private var scrub: Double?

    var body: some View {
        let player = suite.nowPlaying
        if let item = player.item {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Artwork(image: player.artwork, size: 104, radius: 18)
                        .shadow(color: player.tint.opacity(0.45), radius: 18, y: 6)
                        .onTapGesture { player.openPlayer() }
                    if let path = player.appPath {
                        AppIconView(path: path, size: 24)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .offset(x: 6, y: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(item.artist.isEmpty ? (player.appName ?? "") : item.artist)
                                .font(.system(size: 12.5)).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if suite.settings.islandEqualizer {
                            EqualizerBars(playing: item.playing, tint: player.tint, levels: suite.spectrumLevels, count: 5, height: 16)
                                .padding(.top, 3)
                        }
                    }
                    LyricLine(suite: suite, item: item)
                        .frame(height: 30, alignment: .leading)
                        .padding(.top, 4)
                    Scrubber(item: item, tint: player.tint, scrub: $scrub) { player.seek(to: $0) }
                        .padding(.top, 2)
                    HStack(spacing: 22) {
                        Spacer()
                        MediaButton(symbol: "backward.fill", size: 15) { player.previous() }
                        MediaButton(symbol: item.playing ? "pause.fill" : "play.fill", size: 21) { player.toggle() }
                        MediaButton(symbol: "forward.fill", size: 15) { player.next() }
                        Spacer()
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.top, 4)
        } else {
            IdleMedia(available: player.available)
        }
    }
}

private struct LyricLine: View {
    let suite: Suite
    let item: NowPlayingItem

    var body: some View {
        let lyrics = suite.lyrics
        if suite.settings.islandLyrics, lyrics.state == .synced {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let lines = lyrics.lines(at: item.position(at: context.date))
                VStack(alignment: .leading, spacing: 1) {
                    Text(lines.current ?? "♪")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(suite.nowPlaying.tint)
                        .lineLimit(1)
                        .id(lines.current ?? "")
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity.combined(with: .offset(y: -6))))
                    if let next = lines.next {
                        Text(next).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
                    }
                }
                .animation(.islandQuick, value: lines.current)
            }
        } else if suite.settings.islandLyrics, lyrics.state == .loading {
            Text(Phrase("Finding lyrics…", ru: "Ищу текст…", uk: "Шукаю текст…", fr: "Recherche des paroles…").text)
                .font(.system(size: 11.5)).foregroundStyle(Palette.tertiary)
        } else if !item.album.isEmpty {
            Text(item.album).font(.system(size: 11.5)).foregroundStyle(Palette.tertiary).lineLimit(1)
        }
    }
}

private struct Scrubber: View {
    let item: NowPlayingItem
    let tint: Color
    @Binding var scrub: Double?
    let seek: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = item.duration > 0 ? item.position(at: context.date) / item.duration : 0
            let value = scrub ?? live
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(tint).frame(width: max(4, proxy.size.width * value))
                    }
                    .frame(height: scrub == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { scrub = min(max($0.location.x / proxy.size.width, 0), 1) }
                        .onEnded { _ in
                            if let scrub { seek(scrub) }
                            scrub = nil
                        })
                }
                .frame(height: 10)
                HStack {
                    Text(Say.clock(value * item.duration))
                    Spacer()
                    Text("-" + Say.clock(max(item.duration - value * item.duration, 0)))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.tertiary)
                .opacity(item.duration > 0 ? 1 : 0)
            }
            .animation(.islandQuick, value: scrub == nil)
        }
    }
}

private struct MediaButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 16, height: size + 12)
                .background(Circle().fill(Color.white.opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

private struct IdleMedia: View {
    let available: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06))
                Image(systemName: "music.note").font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.tertiary)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(Phrase("Nothing playing", ru: "Ничего не играет", uk: "Нічого не грає", fr: "Aucune lecture").text)
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(available
                     ? Phrase("Music, Spotify, YouTube and podcasts show up here with lyrics.",
                              ru: "Музыка, Spotify, YouTube и подкасты появятся здесь — с текстом песни.",
                              uk: "Музика, Spotify, YouTube і подкасти зʼявляться тут — з текстом пісні.",
                              fr: "Musique, Spotify, YouTube et podcasts s’affichent ici avec les paroles.").text
                     : Phrase("Now Playing is unavailable on this Mac.", ru: "«Сейчас играет» недоступно на этом Mac.",
                              uk: "«Зараз грає» недоступне на цьому Mac.", fr: "« À l’écoute » n’est pas disponible sur ce Mac.").text)
                    .font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    LaunchChip(path: "/System/Applications/Music.app")
                    LaunchChip(path: "/Applications/Spotify.app")
                    LaunchChip(path: "/System/Applications/Podcasts.app")
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct LaunchChip: View {
    let path: String

    var body: some View {
        if FileManager.default.fileExists(atPath: path) {
            Button {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            } label: {
                AppIconView(path: path, size: 22)
            }
            .buttonStyle(PressableStyle())
            .help(FileManager.default.displayName(atPath: path))
        }
    }
}

// MARK: Calendar

private struct CalendarBlock: View {
    let feed: CalendarFeed

    var body: some View {
        IslandTile {
            switch feed.access {
            case .granted:
                if let next = feed.next {
                    VStack(alignment: .leading, spacing: 6) {
                        EventRow(event: next, feed: feed, prominent: true)
                        if let second = feed.events.dropFirst().first(where: { $0.id != next.id }) {
                            EventRow(event: second, feed: feed, prominent: false)
                        }
                    }
                } else {
                    TileLabel(symbol: "calendar", tint: Palette.accent,
                              title: Phrase("No events ahead", ru: "Событий нет", uk: "Подій немає", fr: "Aucun événement").text,
                              detail: Phrase("The next 36 hours are free", ru: "Ближайшие 36 часов свободны", uk: "Найближчі 36 годин вільні", fr: "Les 36 prochaines heures sont libres").text)
                }
            case .unknown, .denied:
                HStack {
                    TileLabel(symbol: "calendar", tint: Palette.accent, title: Phrase("Calendar", ru: "Календарь", uk: "Календар", fr: "Calendrier").text,
                              detail: Phrase("See the next meeting here", ru: "Ближайшая встреча — прямо здесь", uk: "Найближча зустріч — просто тут", fr: "La prochaine réunion, ici").text)
                    Spacer(minLength: 6)
                    SmallAction(title: feed.access == .denied ? Phrases.openSettings.text : Phrases.allow.text) { feed.requestAccess() }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarFeed.Event
    let feed: CalendarFeed
    let prominent: Bool

    var body: some View {
        HStack(spacing: 9) {
            Capsule().fill(event.color).frame(width: 3, height: prominent ? 30 : 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: prominent ? 12.5 : 11.5, weight: prominent ? .semibold : .medium))
                    .foregroundStyle(prominent ? Palette.ink : Palette.secondary).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(when).font(.system(size: 10.5)).foregroundStyle(event.isNow ? Palette.positive : Palette.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if prominent, event.meeting != nil {
                SmallAction(title: Phrases.join.text, symbol: "video.fill") { feed.open(event) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { feed.open(event) }
    }

    private var when: String {
        if event.allDay { return Phrase("All day", ru: "Весь день", uk: "Весь день", fr: "Toute la journée").text }
        let range = "\(Say.time(event.start))–\(Say.time(event.end))"
        if event.isNow { return Phrase("Now", ru: "Идёт сейчас", uk: "Триває зараз", fr: "En cours").text + " · " + range }
        let lead = event.start.timeIntervalSinceNow
        if lead < 3600 * 6 { return Say.relative(lead) + " · " + range }
        let day = Calendar.current.isDateInTomorrow(event.start) ? Phrases.tomorrow.text : Phrases.today.text
        return day + " · " + range
    }
}

// MARK: Timers

private struct TimerBlock: View {
    let timers: TimerCenter

    var body: some View {
        IslandTile {
            if timers.timers.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 18)
                    ForEach([1.0, 5, 10, 25, 45], id: \.self) { minutes in
                        PresetChip(minutes: minutes) { timers.add(minutes: minutes) }
                    }
                    Text(Phrase("min", ru: "мин", uk: "хв", fr: "min").text)
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.tertiary)
                        .fixedSize()
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(TimerCenter.presets, id: \.self) { minutes in
                            Button(TimerCenter.label(for: minutes * 60)) { timers.add(minutes: minutes) }
                        }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(timers.timers.prefix(2)) { timer in
                        TimerRow(timer: timer, timers: timers)
                    }
                }
            }
        }
    }
}

private struct PresetChip: View {
    let minutes: Double
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text("\(Int(minutes))")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(hover ? Palette.onLight : Palette.ink)
                .frame(minWidth: 26).frame(height: 22)
                .background(Capsule().fill(hover ? Palette.accent : Color.white.opacity(0.08)))
        }
        .help(TimerCenter.label(for: minutes * 60))
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

private struct TimerRow: View {
    let timer: IslandTimer
    let timers: TimerCenter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 9) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                    Circle().trim(from: 0, to: 1 - timer.progress(at: context.date))
                        .stroke(timer.ringing ? Palette.danger : Palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.ringing ? Phrases.timerDone.text : Say.clock(timer.remaining(at: context.date).rounded(.up)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.ringing ? Palette.danger : Palette.ink)
                    Text(timer.label).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary)
                }
                Spacer(minLength: 4)
                RoundIcon(symbol: "plus", help: Phrases.plusMinute.text) { timers.extend(timer.id) }
                if !timer.ringing {
                    RoundIcon(symbol: timer.running ? "pause.fill" : "play.fill", help: "") { timers.toggle(timer.id) }
                }
                RoundIcon(symbol: "xmark", help: Phrases.cancel.text) { timers.cancel(timer.id) }
            }
        }
    }
}

// MARK: Downloads

private struct DownloadBlock: View {
    let item: DownloadWatcher.Active

    var body: some View {
        IslandTile {
            HStack(spacing: 9) {
                DownloadRing(progress: item.progress, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.system(size: 10.5, design: .rounded).monospacedDigit()).foregroundStyle(Palette.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var detail: String {
        var parts = [Say.bytes(item.bytes) + (item.total.map { " / " + Say.bytes($0) } ?? "")]
        if item.speed > 1 { parts.append(Say.bytes(Int64(item.speed)) + "/s") }
        if let remaining = item.remaining, remaining > 1 { parts.append(Say.duration(remaining)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Building blocks

/// The call in progress: which app, how long, whether the camera is on, and one button for every microphone.
private struct CallBlock: View {
    let suite: Suite
    let call: CallMonitor.Call

    var body: some View {
        IslandTile {
            HStack(spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    if let path = call.appPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "phone.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.positive).frame(width: 24, height: 24)
                    }
                    Circle().fill(Palette.positive).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .modifier(Breathing())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(call.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 5) {
                            Text("\(Phrases.onCallNow.text) · \(Say.clock(context.date.timeIntervalSince(call.since)))")
                                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Palette.positive).lineLimit(1)
                            if call.camera {
                                Image(systemName: "video.fill").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Palette.secondary)
                                    .help(Phrases.camera.text)
                            }
                        }
                    }
                }
                Spacer(minLength: 6)
                MicButton(muted: suite.callMicOff) { suite.toggleCallMic() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.islandQuick) { suite.island.tab = .call } }
    }
}

private struct MicButton: View {
    let muted: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(muted ? Color.white : Palette.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(muted ? Palette.danger : Color.white.opacity(hover ? 0.18 : 0.1)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(muted ? Phrases.unmute.text : Phrases.mute.text)
        .animation(.islandQuick, value: muted)
    }
}

struct IslandTile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6))
    }
}

struct TileLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary).lineLimit(1) }
            }
        }
    }
}

struct SmallAction: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)) }
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Palette.onLight)
            .padding(.horizontal, 10).frame(height: 22)
            .background(Capsule().fill(hover ? Palette.ink : Palette.accent))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

struct RoundIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(hover ? Palette.ink : Palette.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hover ? 0.14 : 0.07)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(help)
    }
}
