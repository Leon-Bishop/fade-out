import AppKit
import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel
    @State private var showingAbout = false
    @State private var hoveredAppID: String?
    @State private var compactScrollID: Int? = 0
    @AppStorage("layoutStyle") private var layoutStyle = "vertical"

    private let ink = Color(red: 0.07, green: 0.14, blue: 0.105)
    private let mutedInk = Color(red: 0.34, green: 0.40, blue: 0.35)
    private let violet = Color(red: 0.105, green: 0.29, blue: 0.195)
    private let cyan = Color(red: 0.52, green: 0.61, blue: 0.43)

    private var isHorizontal: Bool { layoutStyle == "horizontal" }

    var body: some View {
        ZStack {
            background
            if isHorizontal { horizontalMixer } else { verticalMixer }
        }
        .frame(width: isHorizontal ? 330 : 354)
        .frame(height: isHorizontal ? 190 : nil)
        .frame(minHeight: isHorizontal ? nil : 455)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.22), value: layoutStyle)
        .alert("About Fade Out", isPresented: $showingAbout) {
            Button("Done") {}
        } message: {
            Text("Fade out the noise.\n\nMade by Howl Dev")
        }
    }

    private var verticalMixer: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            masterCard
            appsCard
            if !model.captureAcknowledged && !model.rows.isEmpty { permissionCard }
            if let error = model.errorMessage { errorBanner(error) }
            footer
        }
        .padding(12)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.965, blue: 0.91),
                Color(red: 0.915, green: 0.94, blue: 0.875),
                Color(red: 0.865, green: 0.91, blue: 0.835)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Text("f a d e o u t")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(1.5)
            Spacer()
            layoutButton
        }
        .padding(.horizontal, 2)
    }

    private var layoutButton: some View {
        Button {
            layoutStyle = isHorizontal ? "vertical" : "horizontal"
        } label: {
            Image(systemName: isHorizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(violet)
                .frame(width: 28, height: 24)
                .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(violet.opacity(0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .help(isHorizontal ? "Show full mixer" : "Show compact desk")
        .accessibilityLabel(isHorizontal ? "Show full mixer" : "Show compact desk")
    }

    private var horizontalMixer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("f a d e o u t")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded)).tracking(1.2)
                Spacer()
                layoutButton
            }
            if model.rows.isEmpty {
                Text("open an app to add it to the mixer")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            compactMasterStrip.id(0)
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                                compactChannelStrip(row).id(index + 1)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 1)
                        .background(NativeScrollerSuppressor(axis: .horizontal))
                    }
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $compactScrollID, anchor: .center)
                    .overlay(alignment: .bottom) {
                        compactFunctionalScroller(proxy: scrollProxy)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    private func compactFunctionalScroller(proxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let count = model.rows.count + 1
            let contentWidth = CGFloat(count) * 54
            let trackWidth = geometry.size.width - 8
            let thumbWidth = max(36, min(trackWidth, trackWidth * geometry.size.width / contentWidth))
            let travel = max(0, trackWidth - thumbWidth)
            let maxIndex = max(1, count - 1)
            let progress = CGFloat(min(max(compactScrollID ?? 0, 0), maxIndex)) / CGFloat(maxIndex)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(violet.opacity(0.18))
                    .frame(width: trackWidth, height: 4)
                Capsule()
                    .fill(violet.opacity(0.78))
                    .frame(width: thumbWidth, height: 4)
                    .offset(x: travel * progress)
            }
            .frame(width: trackWidth, height: 14)
            .contentShape(Rectangle())
            .offset(x: 4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard travel > 0 else { return }
                        let rawProgress = (value.location.x - thumbWidth / 2) / travel
                        let bounded = min(1, max(0, rawProgress))
                        let target = Int((bounded * CGFloat(maxIndex)).rounded())
                        compactScrollID = target
                        withAnimation(.easeOut(duration: 0.10)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
            )
        }
        .frame(height: 14)
    }

    private var compactMasterStrip: some View {
        VStack(spacing: 4) {
            Text("M")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(violet)
                .frame(width: 20, height: 20)
                .background(violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            verticalFader(
                value: Binding(get: { model.masterVolume }, set: model.setMaster),
                label: "Master volume"
            )
            Text("\(Int(model.masterVolume * 100))")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(violet)
            Text("master")
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(mutedInk)
        }
        .frame(width: 54, height: 140)
        .overlay(alignment: .trailing) { Rectangle().fill(violet.opacity(0.12)).frame(width: 1) }
    }

    private func compactChannelStrip(_ row: AppRow) -> some View {
        VStack(spacing: 4) {
            Button { model.toggleMute(row) } label: {
                Image(nsImage: row.icon).resizable().interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .opacity(row.volume == 0 ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .help(row.volume == 0 ? "Unmute \(row.name)" : "Mute \(row.name)")

            verticalFader(
                value: Binding(
                    get: { model.rows.first(where: { $0.id == row.id })?.volume ?? row.volume },
                    set: { model.setVolume($0, for: row) }
                ),
                label: "\(row.name) volume"
            )
            Text("\(Int(row.volume * 100))")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(violet)
            Text(row.name)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(ink)
                .padding(.horizontal, 3)
        }
        .frame(width: 54, height: 140)
        .background(hoveredAppID == row.id ? .white.opacity(0.34) : .clear)
        .overlay(alignment: .trailing) { Rectangle().fill(violet.opacity(0.08)).frame(width: 1) }
        .animation(.easeOut(duration: 0.12), value: hoveredAppID)
        .onHover { hovering in hoveredAppID = hovering ? row.id : nil }
    }

    private func verticalFader(value: Binding<Double>, label: String) -> some View {
        Slider(value: value, in: 0...1)
            .tint(violet)
            .controlSize(.mini)
            .frame(width: 76)
            .faderTrackFrame(color: violet)
            .rotationEffect(.degrees(-90))
            .frame(width: 20, height: 76)
            .accessibilityLabel(label)
    }

    private var masterCard: some View {
        HStack(spacing: 9) {
            Text("master")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(mutedInk)
            Slider(value: Binding(get: { model.masterVolume }, set: model.setMaster), in: 0...1)
                .tint(violet)
                .controlSize(.small)
                .faderTrackFrame(color: violet)
                .accessibilityLabel("Master volume")
            Text("\(Int(model.masterVolume * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(violet)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.horizontal, 3).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(violet.opacity(0.12)).frame(height: 1) }
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("mixer").sectionLabel(color: mutedInk)
                Spacer()
                Text("\(model.rows.count) active")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(mutedInk)
            }
            if model.rows.isEmpty {
                VStack(spacing: 7) {
                    ZStack {
                        Circle().fill(violet.opacity(0.08)).frame(width: 48, height: 48)
                        Image(systemName: "speaker.slash")
                            .font(.system(size: 19, weight: .medium)).foregroundStyle(violet.opacity(0.62))
                    }
                    Text("Nothing to fade out").font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Open an app and it will appear here.")
                        .font(.system(size: 11)).foregroundStyle(mutedInk)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in appRow(row) }
                    }
                    .padding(.vertical, 2)
                    .background(NativeScrollerStyler(axis: .vertical))
                }
                .frame(minHeight: 300, maxHeight: 420)
                .animation(.easeInOut(duration: 0.2), value: model.rows.map(\.id))
            }
        }
        .padding(10)
        .glassCard()
        .layoutPriority(1)
    }

    private func appRow(_ row: AppRow) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: row.icon).resizable().interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: ink.opacity(0.07), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.name).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                    Spacer()
                    Text("\(Int(row.volume * 100))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(row.volume < 0.999 ? violet : mutedInk)
                }
                Slider(
                    value: Binding(
                        get: { model.rows.first(where: { $0.id == row.id })?.volume ?? row.volume },
                        set: { model.setVolume($0, for: row) }
                    ), in: 0...1
                )
                .tint(violet)
                .controlSize(.small)
                .faderTrackFrame(color: violet)
                .accessibilityLabel("\(row.name) volume")
            }
            Button { model.toggleMute(row) } label: {
                Image(systemName: row.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.volume == 0 ? .white : violet)
                    .frame(width: 25, height: 25)
                    .background(row.volume == 0 ? AnyShapeStyle(violet) : AnyShapeStyle(.white.opacity(0.26)), in: Circle())
                    .overlay(Circle().stroke(violet.opacity(row.volume == 0 ? 0 : 0.13), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.volume == 0 ? "Unmute \(row.name)" : "Mute \(row.name)")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(hoveredAppID == row.id ? .white.opacity(0.30) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(violet.opacity(0.08)).frame(height: 1) }
        .animation(.easeOut(duration: 0.14), value: hoveredAppID)
        .onHover { hovering in hoveredAppID = hovering ? row.id : nil }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.shield").foregroundStyle(violet)
                Text("Allow audio mixing").font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            Text("Fade Out needs System Audio Recording access to adjust sound. Audio stays on this Mac.")
                .font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
            Button("Continue") { model.acknowledgeCapture() }
                .buttonStyle(.borderedProminent).tint(violet).controlSize(.small)
        }
        .padding(13)
        .glassCard()
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(cyan.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Button { model.setLaunchAtLogin(!model.launchAtLogin) } label: {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(model.launchAtLogin ? violet : .white.opacity(0.42))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(model.launchAtLogin ? violet.opacity(0.72) : violet.opacity(0.28), lineWidth: 0.8)
                        if model.launchAtLogin {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 14, height: 14)
                    Text("Launch at login")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(mutedInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Launch at login")
            .accessibilityValue(model.launchAtLogin ? "On" : "Off")
            Spacer()
            Button { showingAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(mutedInk)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain).help("About Fade Out")
            Button { model.stop(); NSApplication.shared.terminate(nil) } label: {
                Label("quit", systemImage: "power")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(violet)
                    .padding(.leading, 5)
            }
            .buttonStyle(.plain).help("Quit Fade Out")
        }
        .padding(.horizontal, 2)
    }

}

private extension View {
    func faderTrackFrame(color: Color) -> some View {
        background {
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(height: 4)
                .overlay {
                    Capsule()
                        .stroke(color.opacity(0.16), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
        }
    }

    func glassCard() -> some View {
        background(.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(red: 0.10, green: 0.29, blue: 0.20).opacity(0.09), lineWidth: 0.7)
            )
            .shadow(color: Color(red: 0.07, green: 0.18, blue: 0.12).opacity(0.045), radius: 8, y: 3)
    }

    func sectionLabel(color: Color) -> some View {
        font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.1).foregroundStyle(color)
    }
}

struct MixerView_Previews: PreviewProvider {
    static var previews: some View { MixerView(model: .preview()) }
}

private enum NativeScrollAxis {
    case horizontal
    case vertical
}

private struct NativeScrollerSuppressor: NSViewRepresentable {
    let axis: NativeScrollAxis

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        suppress(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        suppress(from: nsView)
    }

    private func suppress(from view: NSView) {
        for delay in [0.0, 0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                var ancestor: NSView? = view
                while let current = ancestor {
                    if let scrollView = current as? NSScrollView {
                        switch axis {
                        case .horizontal:
                            scrollView.hasHorizontalScroller = false
                            scrollView.horizontalScroller = nil
                        case .vertical:
                            scrollView.hasVerticalScroller = false
                            scrollView.verticalScroller = nil
                        }
                        return
                    }
                    ancestor = current.superview
                }
            }
        }
    }
}

private struct NativeScrollerStyler: NSViewRepresentable {
    let axis: NativeScrollAxis

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        styleScroller(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        styleScroller(from: nsView)
    }

    private func styleScroller(from view: NSView) {
        for delay in [0.0, 0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                var ancestor: NSView? = view
                while let current = ancestor {
                    if let scrollView = current as? NSScrollView {
                        scrollView.scrollerStyle = .overlay
                        scrollView.autohidesScrollers = false
                        switch axis {
                        case .horizontal:
                            if !(scrollView.horizontalScroller is ForestScroller) {
                                scrollView.horizontalScroller = ForestScroller()
                            }
                            scrollView.hasHorizontalScroller = true
                        case .vertical:
                            if !(scrollView.verticalScroller is ForestScroller) {
                                scrollView.verticalScroller = ForestScroller()
                            }
                            scrollView.hasVerticalScroller = true
                        }
                        return
                    }
                    ancestor = current.superview
                }
            }
        }
    }
}

private final class ForestScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        6
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let horizontal = bounds.width > bounds.height
        var track = slotRect
        if horizontal {
            track.origin.y = slotRect.midY - 1.5
            track.size.height = 3
        } else {
            track.origin.x = slotRect.midX - 1.5
            track.size.width = 3
        }
        NSColor(calibratedRed: 0.14, green: 0.34, blue: 0.24, alpha: 0.14).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
    }

    override func drawKnob() {
        let horizontal = bounds.width > bounds.height
        var knob = rect(for: .knob)
        if horizontal {
            knob.origin.y = bounds.midY - 1.5
            knob.size.height = 3
        } else {
            knob.origin.x = bounds.midX - 1.5
            knob.size.width = 3
        }
        NSColor(calibratedRed: 0.14, green: 0.34, blue: 0.24, alpha: 0.68).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
