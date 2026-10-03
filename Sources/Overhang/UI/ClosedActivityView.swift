import AppKit
import SwiftUI
import OverhangCore

/// Content on the two "wings" beside the camera while the notch is closed.
struct ClosedActivityView: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat

    @ObservedObject private var music = NowPlayingService.shared

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: sideWidth, height: height)
            Spacer(minLength: notchWidth)
            trailing
                .frame(width: sideWidth, height: height)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case let .hud(symbol, _):
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        case let .timer(_, progress, paused):
            ZStack {
                RingGauge(value: progress, color: paused ? Theme.secondary : Theme.accent, lineWidth: 2.5)
                    .frame(width: height * 0.5, height: height * 0.5)
            }
        case .timerDone:
            Image(systemName: "bell.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
        case .music:
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 11))
                }
            }
            .frame(width: height * 0.68, height: height * 0.68)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .keepAwake:
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 12)).foregroundStyle(Color.orange)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case let .hud(_, level):
            if let level {
                ProgressBar(value: level, color: .white, height: 4).frame(width: sideWidth - 18)
            }
        case let .timer(remaining, _, paused):
            Text(DurationFormatter.clock(remaining))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(paused ? Theme.secondary : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .timerDone:
            Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
        case let .music(isPlaying):
            AudioBars(animating: isPlaying)
                .frame(width: 20, height: height * 0.45)
        case .keepAwake:
            Text("On").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.orange)
        }
    }
}

/// Decorative equalizer bars (not driven by real audio levels).
struct AudioBars: View {
    let animating: Bool
    private let count = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.22)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .scaleEffect(y: animating ? barHeight(index, context.date) : 0.25, anchor: .center)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: context.date)
        }
    }

    private func barHeight(_ index: Int, _ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate * 4.5
        let value = (sin(t + Double(index) * 1.7) + sin(t * 1.9 + Double(index))) / 4 + 0.5
        return CGFloat(0.3 + value * 0.7)
    }
}
