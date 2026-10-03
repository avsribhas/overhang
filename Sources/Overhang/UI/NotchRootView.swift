import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var activity = ActivityCenter.shared
    @State private var dropTargeted = false

    var body: some View {
        let size = vm.bodySize(activity: activity.current)
        let shoulders = vm.topCornerRadius * 2

        ZStack(alignment: .top) {
            NotchShape(topRadius: vm.topCornerRadius, bottomRadius: vm.bottomCornerRadius)
                .fill(Color.black)
                .frame(width: size.width + shoulders, height: size.height)
                .shadow(color: .black.opacity(vm.state == .open ? 0.55 : 0), radius: 14, y: 4)

            Group {
                if vm.state == .open {
                    OpenNotchView(vm: vm)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else if let current = activity.current {
                    ClosedActivityView(activity: current, notchWidth: vm.notchSize.width,
                                       sideWidth: vm.activitySideWidth, height: vm.notchSize.height)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                }
            }
            .clipShape(NotchShape(topRadius: 0, bottomRadius: vm.bottomCornerRadius))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(vm.animation, value: vm.state)
        .animation(vm.animation, value: activity.current)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard vm.state == .open else { return false }
            if vm.enabledTools.contains(.shelf) { vm.selectedTool = .shelf }
            ShelfService.shared.add(providers: providers)
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            vm.showingDropHint = targeted
        }
    }
}

struct OpenNotchView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 8) {
            header
            ToolStrip(vm: vm)
            ToolContentView(tool: vm.selectedTool)
                .id(vm.selectedTool)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if vm.showingDropHint {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.08)))
                            .overlay(Label("Drop to add to Shelf", systemImage: "tray.and.arrow.down")
                                .font(.system(size: 13, weight: .semibold)))
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    /// The header row shares its height with the notch; nothing is drawn behind the camera.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.selectedTool.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(vm.selectedTool.title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: vm.notchSize.width + 20)
            IconButton(symbol: vm.pinned ? "pin.fill" : "pin", size: 22, help: "Keep open",
                       tint: vm.pinned ? Theme.accent : .white) { vm.pinned.toggle() }
            IconButton(symbol: "gearshape", size: 22, help: "Settings") {
                SettingsWindowController.shared.show()
            }
        }
        .frame(height: max(vm.notchSize.height, 28))
    }
}

struct ToolStrip: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(vm.enabledTools) { tool in
                    ToolStripButton(tool: tool, selected: tool == vm.selectedTool) {
                        withAnimation(.easeOut(duration: 0.15)) { vm.selectedTool = tool }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 30)
    }
}

private struct ToolStripButton: View {
    let tool: Tool
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(hovering ? 1 : 0.75))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.accent : Color.white.opacity(hovering ? 0.12 : 0.05)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .onHover { hovering = $0 }
    }
}
