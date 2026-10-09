import Carbon.HIToolbox
import CoreAudio
import SwiftUI

/// App volumes in the Sound tab.
struct MixerCard: View {
    var model: AppModel
    let suite: Suite

    var body: some View {
        let mixer = suite.mixer
        let on = suite.settings.mixer
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MixerPhrases.title.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(MixerPhrases.subtitle.text).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                GlassSwitch(isOn: on) { suite.settings.mixer.toggle() }
            }
            if on {
                if mixer.permission == .denied {
                    InlinePermission(text: MixerPhrases.needsAccess.text, button: Phrases.openSettings.text) { mixer.requestPermission() }
                } else if mixer.permission == .unknown {
                    InlinePermission(text: MixerPhrases.needsAccess.text, button: Phrases.allow.text) { mixer.requestPermission() }
                }
                if mixer.apps.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.zzz").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
                        Text(MixerPhrases.silent.text).font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(mixer.apps) { app in
                            MixerRow(app: app, mixer: mixer, outputs: model.audio.outputs)
                        }
                    }
                }
            } else {
                PlayingStrip(model: model)
            }
        }
        .card()
        .animation(.panelSpring, value: on)
        .onAppear { mixer.metering = true }
        .onDisappear { mixer.metering = false }
    }
}

private struct PlayingStrip: View {
    var model: AppModel

    var body: some View {
        let playing = model.audio.playing
        if playing.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "speaker.zzz").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
                Text(model.text(.silence)).font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                ForEach(playing) { app in
                    VStack(spacing: 6) {
                        AppIconView(path: app.appPath, size: 34, fallback: "waveform")
                        Text(app.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.secondary).lineLimit(1).frame(width: 58)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MixerRow: View {
    let app: Mixer.App
    let mixer: Mixer
    let outputs: [AudioEndpoint]

    var body: some View {
        let rule = mixer.rule(app)
        let peak = Double(mixer.peaks[app.id] ?? 0)
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AppIconView(path: app.path, size: 28, fallback: "waveform")
                    if app.playing {
                        Circle().fill(Palette.positive).frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                            .offset(x: 2, y: 2)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    OutputMenu(app: app, mixer: mixer, outputs: outputs, rule: rule)
                }
                Spacer(minLength: 6)
                Text(rule.muted ? MixerPhrases.off.text : Say.percent(rule.volume * 100))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(rule.volume > 1.005 ? Palette.warning : (rule.muted ? Palette.tertiary : Palette.secondary))
                    .frame(width: 46, alignment: .trailing)
                    .contentTransition(.numericText())
                Button { mixer.toggleMute(app) } label: {
                    Image(systemName: rule.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rule.muted ? Palette.onLight : Palette.ink)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(rule.muted ? Palette.ink : Color.white.opacity(0.07)))
                }
                .buttonStyle(PressableStyle())
                .help(rule.muted ? MixerPhrases.unmute.text : MixerPhrases.mute.text)
            }
            ZStack(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.positive.opacity(0.5), Palette.warning.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * min(peak, 1)), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .animation(.linear(duration: 0.06), value: peak)
                }
                FineSlider(value: rule.volume, range: 0...2, detent: 1,
                           tint: rule.volume > 1.005 ? Palette.warning : Palette.accent) { mixer.setVolume($0, for: app) }
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
        .contextMenu {
            Button(MixerPhrases.reset.text) { mixer.reset(app) }
        }
    }
}

private struct OutputMenu: View {
    let app: Mixer.App
    let mixer: Mixer
    let outputs: [AudioEndpoint]
    let rule: Mixer.Rule

    var body: some View {
        Menu {
            Button {
                mixer.setOutput(nil, for: app)
            } label: {
                Label(MixerPhrases.systemOutput.text, systemImage: rule.output == nil ? "checkmark" : "speaker.wave.2")
            }
            Divider()
            ForEach(outputs) { device in
                let uid = CA.uid(device.id)
                Button {
                    mixer.setOutput(uid, for: app)
                } label: {
                    Label(device.name, systemImage: rule.output == uid && uid != nil ? "checkmark" : device.symbol)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: currentSymbol).font(.system(size: 9, weight: .semibold))
                Text(currentName).font(.system(size: 10.5)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(rule.output == nil ? Palette.tertiary : Palette.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var current: AudioEndpoint? {
        guard let uid = rule.output else { return nil }
        return outputs.first { CA.uid($0.id) == uid }
    }

    private var currentName: String { current?.name ?? MixerPhrases.systemOutput.text }
    private var currentSymbol: String { current?.symbol ?? "speaker.wave.2" }
}

struct InlinePermission: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.warning)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            PillButton(title: button, prominent: true, action: action)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.warning.opacity(0.08)))
    }
}

/// Output cycling, all-mics mute and the headphone guard, right under the device cards.
struct SoundTricksCard: View {
    var model: AppModel
    let suite: Suite

    var body: some View {
        let settings = suite.settings
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TrickButton(symbol: suite.micMuted ? "mic.slash.fill" : "mic.fill", title: suite.micMuted ? SoundPhrases.micsOff.text : MixerPhrases.muteMics.text,
                            keys: KeyCombo.control(kVK_ANSI_M).glyphs, active: suite.micMuted, tint: Palette.danger) { suite.sound.toggleMics() }
                TrickButton(symbol: "arrow.triangle.swap", title: MixerPhrases.nextOutput.text,
                            keys: KeyCombo.control(kVK_ANSI_O).glyphs, active: false, tint: Palette.accent) { suite.sound.cycleOutput() }
            }
            Hairline()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MixerPhrases.guardTitle.text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(MixerPhrases.guardDetail(Int((settings.headphoneLevel * 100).rounded()))).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 6)
                GlassSwitch(isOn: settings.headphoneGuard) { settings.headphoneGuard.toggle() }
            }
            if settings.headphoneGuard {
                FineSlider(value: settings.headphoneLevel, range: 0...1, tint: Palette.accent) { settings.headphoneLevel = (($0 * 100).rounded()) / 100 }
            }
            Hairline()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MixerPhrases.pinTitle.text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(MixerPhrases.pinDetail.text).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Menu {
                    Button(MixerPhrases.pinNone.text) { settings.pinnedInput = "" }
                    Divider()
                    ForEach(model.audio.inputs) { device in
                        if let uid = CA.uid(device.id) {
                            Button(device.name) {
                                settings.pinnedInput = uid
                                model.audio.select(device.id, scope: .input)
                            }
                        }
                    }
                } label: {
                    Text(pinnedName).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(settings.pinnedInput.isEmpty ? Palette.secondary : Palette.accent)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .card()
        .animation(.panelSpring, value: settings.headphoneGuard)
    }

    private var pinnedName: String {
        let uid = suite.settings.pinnedInput
        guard !uid.isEmpty else { return MixerPhrases.pinNone.text }
        return model.audio.inputs.first { CA.uid($0.id) == uid }?.name ?? MixerPhrases.pinNone.text
    }
}

private struct TrickButton: View {
    let symbol: String
    let title: String
    let keys: [String]
    let active: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(active ? Palette.onLight : tint)
                        .contentTransition(.symbolEffect(.replace))
                    Spacer()
                    KeyCaps(keys: keys, size: 18).opacity(active ? 0.7 : 1)
                }
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(active ? Palette.onLight : Palette.ink).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(active ? tint : Color.white.opacity(hover ? 0.09 : 0.055)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

enum MixerPhrases {
    static let title = Phrase("App volume", ru: "Громкость приложений", uk: "Гучність застосунків", fr: "Volume par app")
    static let subtitle = Phrase("Each app its own level, up to 200 %, and its own output.",
                                 ru: "Своя громкость для каждого — до 200 % — и свой выход.",
                                 uk: "Своя гучність для кожного — до 200 % — і свій вихід.",
                                 fr: "Un niveau par app, jusqu’à 200 %, et sa propre sortie.")
    static let needsAccess = Phrase("macOS asks once before SAVISUL can route other apps' sound.",
                                    ru: "macOS один раз спросит разрешение, чтобы SAVISUL мог вести звук приложений.",
                                    uk: "macOS один раз спитає дозвіл, щоб SAVISUL міг вести звук застосунків.",
                                    fr: "macOS demande une fois avant que SAVISUL puisse router le son des apps.")
    static let silent = Phrase("No app is making sound right now", ru: "Сейчас ни одно приложение не звучит", uk: "Зараз жоден застосунок не звучить", fr: "Aucune app ne joue de son")
    static let off = Phrase("Off", ru: "Выкл", uk: "Вимк", fr: "Coupé")
    static let mute = Phrase("Mute", ru: "Выключить звук", uk: "Вимкнути звук", fr: "Couper")
    static let unmute = Phrase("Unmute", ru: "Включить звук", uk: "Увімкнути звук", fr: "Réactiver")
    static let reset = Phrase("Reset to 100 %", ru: "Сбросить на 100 %", uk: "Скинути на 100 %", fr: "Revenir à 100 %")
    static let systemOutput = Phrase("System output", ru: "Как в системе", uk: "Як у системі", fr: "Sortie système")
    static let muteMics = Phrase("Mute all mics", ru: "Заглушить микрофоны", uk: "Заглушити мікрофони", fr: "Couper les micros")
    static let nextOutput = Phrase("Next output", ru: "Следующий выход", uk: "Наступний вихід", fr: "Sortie suivante")
    static let guardTitle = Phrase("Headphones unplugged", ru: "Наушники отключились", uk: "Навушники відключилися", fr: "Écouteurs débranchés")
    static let pinTitle = Phrase("Keep microphone", ru: "Держать микрофон", uk: "Тримати мікрофон", fr: "Garder le micro")
    static let pinDetail = Phrase("AirPods won't take over input and drop music quality.",
                                  ru: "AirPods не перехватят вход и не испортят качество музыки.",
                                  uk: "AirPods не перехоплять вхід і не зіпсують якість музики.",
                                  fr: "Les AirPods ne prennent plus l’entrée et la musique reste nette.")
    static let pinNone = Phrase("Any", ru: "Любой", uk: "Будь-який", fr: "Aucun")
    @MainActor static func guardDetail(_ percent: Int) -> String {
        Phrase("Speakers drop to %d%% instead of blasting", ru: "Динамики стихнут до %d%%, а не заорут", uk: "Динаміки стихнуть до %d%%, а не заволають", fr: "Les haut-parleurs baissent à %d %%")(percent)
    }
}
