import AppKit
import EventKit
import Observation
import SwiftUI

/// Upcoming events from every calendar the Mac syncs, with meeting links pulled out of them.
@MainActor
@Observable
final class CalendarFeed {
    enum Access: Equatable { case unknown, granted, denied }

    struct Event: Identifiable, Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
        var color: Color
        var calendar: String
        var location: String?
        var meeting: URL?

        var isNow: Bool { start <= Date() && end > Date() }
    }

    private(set) var access: Access = .unknown
    private(set) var events: [Event] = []
    @ObservationIgnored var onSoon: ((Event) -> Void)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var warned: Set<String> = []

    func start() {
        readAccess()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        ticker?.invalidate()
        ticker = nil
    }

    /// Panel renders (--dump-panels): shows these events as if access were granted, without reading the calendar.
    func preview(_ sample: [Event]) {
        access = .granted
        events = sample
    }

    private func readAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func requestAccess() {
        if access == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.readAccess()
                    self?.store.reset()
                    self?.refresh()
                }
            }
        }
    }

    func refresh() {
        readAccess()
        guard access == .granted else {
            events = []
            return
        }
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .hour, value: 36, to: now) ?? now.addingTimeInterval(129_600)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600 * 4), end: horizon, calendars: nil)
        let found = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .filter { event in
                event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .prefix(8)
            .map { event in
                Event(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                      title: event.title?.isEmpty == false ? event.title! : Phrase("Event", ru: "Событие", uk: "Подія", fr: "Événement").text,
                      start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                      color: Color(nsColor: event.calendar.color ?? .systemBlue),
                      calendar: event.calendar.title,
                      location: event.location?.isEmpty == false ? event.location : nil,
                      meeting: Self.meetingLink(event))
            }
        let list = Array(found)
        if list != events { events = list }
        for event in list where !event.allDay && !warned.contains(event.id) {
            let lead = event.start.timeIntervalSince(now)
            if lead > 0, lead <= 5 * 60 {
                warned.insert(event.id)
                onSoon?(event)
            }
        }
    }

    var next: Event? { events.first { !$0.allDay } ?? events.first }

    func open(_ event: Event) {
        if let meeting = event.meeting {
            NSWorkspace.shared.open(meeting)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"https?://(?:[\w-]+\.)?(?:zoom\.us/(?:j|my|w)/[^\s<>"]+|meet\.google\.com/[a-z\-]+|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|teams\.live\.com/meet/[^\s<>"]+|[\w-]+\.webex\.com/[^\s<>"]+|telemost\.yandex\.ru/j/[^\s<>"]+|meet\.jit\.si/[^\s<>"]+|discord\.gg/[^\s<>"]+|facetime\.apple\.com/join[^\s<>"]+|app\.slack\.com/huddle/[^\s<>"]+|whereby\.com/[^\s<>"]+)"#,
        options: [.caseInsensitive])

    private static func meetingLink(_ event: EKEvent) -> URL? {
        if let url = event.url, matches(url.absoluteString) { return url }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingPattern.firstMatch(in: text, range: range), let found = Range(match.range, in: text) {
                return URL(string: String(text[found]))
            }
        }
        return nil
    }

    private static func matches(_ text: String) -> Bool {
        meetingPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
