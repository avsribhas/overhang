import AppKit
import EventKit
import SwiftUI

final class CalendarModel: ObservableObject {
    static let shared = CalendarModel()

    struct DayGroup: Identifiable {
        let id: Date
        let events: [EKEvent]
    }

    private let store = EKEventStore()
    @Published private(set) var groups: [DayGroup] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)

    var hasAccess: Bool { status == .fullAccess }

    func load() {
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            store.requestFullAccessToEvents { [weak self] _, _ in
                DispatchQueue.main.async { self?.load() }
            }
            return
        }
        guard hasAccess else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 4, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > Date() || $0.isAllDay && calendar.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
        let byDay = Dictionary(grouping: events) { calendar.startOfDay(for: max($0.startDate, start)) }
        groups = byDay.keys.sorted().map { DayGroup(id: $0, events: byDay[$0] ?? []) }
    }
}

struct CalendarToolView: View {
    @ObservedObject private var model = CalendarModel.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide))).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.negative)
                Text(Date().formatted(.dateTime.day())).font(.system(size: 52, weight: .semibold, design: .rounded))
                Text(Date().formatted(.dateTime.month(.wide).year())).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                PillButton(title: "Open Calendar", symbol: "arrow.up.forward.app") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
            .frame(width: 150)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))

            content
        }
        .onAppear { model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .denied, .restricted, .writeOnly:
            VStack(spacing: 8) {
                EmptyState(symbol: "calendar.badge.exclamationmark", title: "No calendar access",
                           message: "Allow Overhang under System Settings → Privacy & Security → Calendars.")
                PillButton(title: "Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        default:
            if model.groups.isEmpty {
                EmptyState(symbol: "calendar", title: "No upcoming events", message: "Nothing in the next few days.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dayTitle(group.id)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                                ForEach(group.events, id: \.self) { event in
                                    EventRow(event: event)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInTomorrow(date) { return "TOMORROW" }
        return date.formatted(.dateTime.weekday(.wide).month().day()).uppercased()
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendar?.color ?? .systemBlue))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(timeText).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            if let location = event.location, !location.isEmpty {
                Text(location).font(.system(size: 10)).foregroundStyle(Theme.tertiary).lineLimit(1).frame(maxWidth: 160, alignment: .trailing)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
