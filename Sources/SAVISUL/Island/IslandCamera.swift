import AVFoundation
import SwiftUI

struct IslandCamera: View {
    let suite: Suite

    var body: some View {
        let camera = suite.camera
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05))
                switch camera.access {
                case .authorized:
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if camera.running {
                                HStack(spacing: 5) {
                                    Circle().fill(Palette.positive).frame(width: 6, height: 6)
                                    Text(Phrase("Only you see this", ru: "Видите только вы", uk: "Бачите лише ви", fr: "Vous seul le voyez").text)
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).frame(height: 20)
                                .background(Capsule().fill(.black.opacity(0.45)))
                                .padding(10)
                            }
                        }
                case .notDetermined:
                    CameraAsk(title: Phrase("Check yourself before a call", ru: "Проверьте себя перед звонком", uk: "Перевірте себе перед дзвінком", fr: "Vérifiez-vous avant un appel").text,
                              button: Phrases.allow.text) { camera.start() }
                default:
                    CameraAsk(title: Phrase("Camera access is off for SAVISUL", ru: "Доступ SAVISUL к камере выключен", uk: "Доступ SAVISUL до камери вимкнено", fr: "L’accès à la caméra est désactivé").text,
                              button: Phrases.openSettings.text) { camera.openSettings() }
                }
            }
            .frame(width: 300)
            VStack(alignment: .leading, spacing: 10) {
                Text(Phrase("Mirror", ru: "Зеркало", uk: "Дзеркало", fr: "Miroir").text)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(Phrase("Light, hair, background — the camera stops as soon as the island closes.",
                            ru: "Свет, причёска, фон. Камера выключается, как только остров закроется.",
                            uk: "Світло, зачіска, фон. Камера вимикається, щойно острів закриється.",
                            fr: "Lumière, coiffure, arrière-plan : la caméra s’arrête dès que l’île se ferme.").text)
                    .font(.system(size: 11.5)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                if camera.cameras.count > 1 {
                    Picker("", selection: Binding(get: { camera.selected ?? "" }, set: { camera.selected = $0 })) {
                        ForEach(camera.cameras, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }
                if let next = suite.calendar.next, next.meeting != nil, next.start.timeIntervalSinceNow < 3600 {
                    HStack(spacing: 8) {
                        Capsule().fill(next.color).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(Say.time(next.start)).font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                        }
                        Spacer(minLength: 4)
                        SmallAction(title: Phrases.join.text, symbol: "video.fill") { suite.calendar.open(next) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .onAppear { if camera.access == .authorized { camera.start() } }
        .onDisappear { camera.stop() }
    }
}

private struct CameraAsk: View {
    let title: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "web.camera").font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.tertiary)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            SmallAction(title: button, action: action)
        }
        .padding(16)
    }
}
