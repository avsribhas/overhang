import IOKit.pwr_mgt
import OverhangCore
import SwiftUI

/// Holds an IOKit power assertion, the same mechanism `caffeinate` uses.
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var isActive = false
    @Published private(set) var until: Date?
    @Published private(set) var keepDisplayOn = true

    private var assertionID: IOPMAssertionID = 0
    private var expiry: Timer?

    func start(duration: TimeInterval?, keepDisplayOn: Bool) {
        stop()
        let type = keepDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Overhang Keep Awake" as CFString, &assertionID)
        guard result == kIOReturnSuccess else { return }
        isActive = true
        self.keepDisplayOn = keepDisplayOn
        if let duration {
            until = Date().addingTimeInterval(duration)
            expiry = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        expiry?.invalidate()
        expiry = nil
        if isActive { IOPMAssertionRelease(assertionID) }
        assertionID = 0
        isActive = false
        until = nil
    }
}

struct KeepAwakeView: View {
    @ObservedObject private var service = KeepAwakeService.shared
    @State private var keepDisplayOn = true

    private struct Option: Hashable {
        let title: String
        let duration: TimeInterval?
    }

    private let options: [Option] = [
        Option(title: "15 min", duration: 900), Option(title: "30 min", duration: 1800),
        Option(title: "1 hour", duration: 3600), Option(title: "2 hours", duration: 7200),
        Option(title: "5 hours", duration: 18000), Option(title: "Indefinitely", duration: nil),
    ]

    var body: some View {
        HStack(spacing: 22) {
            Button {
                service.isActive ? service.stop() : service.start(duration: nil, keepDisplayOn: keepDisplayOn)
            } label: {
                ZStack {
                    Circle().fill(service.isActive ? Color.orange : Theme.card).frame(width: 130, height: 130)
                    Image(systemName: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 44))
                        .foregroundStyle(service.isActive ? Color.black : Color.white)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                Text(service.isActive ? "Your Mac is staying awake" : "Sleep as usual")
                    .font(.system(size: 16, weight: .semibold))
                Group {
                    if let until = service.until {
                        Text("Until \(until.formatted(date: .omitted, time: .shortened)) · ") + Text(until, style: .relative) + Text(" left")
                    } else if service.isActive {
                        Text("Until you turn it off")
                    } else {
                        Text("Pick a duration")
                    }
                }
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        PillButton(title: option.title) { service.start(duration: option.duration, keepDisplayOn: keepDisplayOn) }
                    }
                }
                Toggle("Keep display on too", isOn: $keepDisplayOn)
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .onAppear { keepDisplayOn = service.isActive ? service.keepDisplayOn : true }
    }
}
