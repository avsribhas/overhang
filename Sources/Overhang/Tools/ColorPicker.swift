import AppKit
import SwiftUI

struct PickedColor: Codable, Identifiable, Equatable {
    var id = UUID()
    let red: Double
    let green: Double
    let blue: Double

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        red = Double(rgb.redComponent)
        green = Double(rgb.greenComponent)
        blue = Double(rgb.blueComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    var rgbString: String { "rgb(\(Int((red * 255).rounded())), \(Int((green * 255).rounded())), \(Int((blue * 255).rounded())))" }

    var hslString: String {
        let maxV = max(red, green, blue), minV = min(red, green, blue)
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        let d = maxV - minV
        if d > 0 {
            s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            switch maxV {
            case red: h = (green - blue) / d + (green < blue ? 6 : 0)
            case green: h = (blue - red) / d + 2
            default: h = (red - green) / d + 4
            }
            h /= 6
        }
        return "hsl(\(Int((h * 360).rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }
}

struct ColorPickerView: View {
    @State private var colors: [PickedColor] = JSONStore.load([PickedColor].self, from: "colors.json") ?? []
    @State private var toast: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                Button(action: sample) {
                    ZStack {
                        Circle().fill(colors.first?.color ?? Theme.card).frame(width: 110, height: 110)
                        Image(systemName: "eyedropper.halffull").font(.system(size: 30)).foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                }
                .buttonStyle(.plain)
                Text("Click to pick from screen").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .frame(width: 160)

            VStack(alignment: .leading, spacing: 8) {
                if let current = colors.first {
                    ForEach([current.hex, current.rgbString, current.hslString], id: \.self) { value in
                        HStack {
                            Text(value).font(.system(size: 14, weight: .medium, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            IconButton(symbol: "doc.on.doc", size: 24) { copy(value) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
                    }
                } else {
                    EmptyState(symbol: "eyedropper", title: "No colors yet", message: "Pick any pixel on any screen.")
                }
                if colors.count > 1 {
                    Text("HISTORY").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    HStack(spacing: 6) {
                        ForEach(colors.dropFirst().prefix(12)) { picked in
                            Circle().fill(picked.color).frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.white.opacity(0.2)))
                                .help(picked.hex)
                                .onTapGesture { copy(picked.hex) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .toast($toast)
    }

    private func sample() {
        NotchController.current?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSColorSampler().show { color in
                DispatchQueue.main.async {
                    if let color {
                        let picked = PickedColor(color)
                        colors.insert(picked, at: 0)
                        colors = Array(colors.prefix(30))
                        JSONStore.save(colors, to: "colors.json")
                        Clipboard.copy(picked.hex)
                    }
                    NotchController.current?.open(tool: .colorPicker)
                }
            }
        }
    }

    private func copy(_ value: String) {
        Clipboard.copy(value)
        withAnimation { toast = "Copied \(value)" }
    }
}
