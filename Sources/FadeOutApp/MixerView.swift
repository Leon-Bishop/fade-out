import AppKit
import FadeOutAudio
import SwiftUI

private enum MixerStackKind: String, Hashable {
    case music
    case browsers
    case communication

    init?(priority: AppSortPriority) {
        switch priority {
        case .music: self = .music
        case .browser: self = .browsers
        case .communication: self = .communication
        case .other: return nil
        }
    }

    var title: String {
        switch self {
        case .music: return "Music & streaming"
        case .browsers: return "Browsers"
        case .communication: return "Comms"
        }
    }

    var compactTitle: String {
        switch self {
        case .music: return "music"
        case .browsers: return "browsers"
        case .communication: return "comms"
        }
    }
}

private struct MixerStackGroup: Identifiable {
    let kind: MixerStackKind
    let rows: [AppRow]
    var id: String { "stack.\(kind.rawValue)" }
}

private enum MixerItem: Identifiable {
    case app(AppRow)
    case stack(MixerStackGroup)

    var id: String {
        switch self {
        case .app(let row): return row.id
        case .stack(let group): return group.id
        }
    }
}

struct MixerView: View {
    @ObservedObject var model: MixerModel
    @State private var showingAbout = false
    @State private var showingStacksHelp = false
    @State private var showingLayoutHelp = false
    @State private var hoveredAppID: String?
    @State private var compactScrollID: Int? = 0
    @State private var expandedStacks: Set<MixerStackKind> = []
    @AppStorage("layoutStyle") private var layoutStyle = "vertical"
    @AppStorage("stacksEnabled") private var stacksEnabled = false

    private let ink = Color(red: 0.07, green: 0.14, blue: 0.105)
    private let mutedInk = Color(red: 0.34, green: 0.40, blue: 0.35)
    private let violet = Color(red: 0.105, green: 0.29, blue: 0.195)
    private let cyan = Color(red: 0.52, green: 0.61, blue: 0.43)

    private var isHorizontal: Bool { layoutStyle == "horizontal" }

    private var compactChannelWidth: CGFloat {
        let channelCount = max(1, mixerItems.count + 1) // Apps/stacks plus master.
        let usableWidth: CGFloat = 328 // Fixed 354-point window minus outer and scroll padding.
        return max(54, usableWidth / CGFloat(channelCount))
    }

    private var hasGroupableApps: Bool {
        let stackablePriorities: [AppSortPriority] = [.music, .browser, .communication]
        return stackablePriorities.contains { priority in
            model.rows.lazy.filter { $0.sortPriority == priority }.prefix(2).count > 1
        }
    }

    private var mixerItems: [MixerItem] {
        guard stacksEnabled else { return model.rows.map(MixerItem.app) }
        var emitted = Set<MixerStackKind>()
        return model.rows.compactMap { row in
            guard let kind = MixerStackKind(priority: row.sortPriority) else { return .app(row) }
            let members = model.rows.filter { $0.sortPriority == row.sortPriority }
            guard members.count > 1 else { return .app(row) }
            guard emitted.insert(kind).inserted else { return nil }
            return .stack(MixerStackGroup(kind: kind, rows: members))
        }
    }

    var body: some View {
        ZStack {
            background
            if isHorizontal { horizontalMixer } else { verticalMixer }
        }
        .overlay(alignment: .topTrailing) {
            if showingLayoutHelp {
                layoutHelpCard
                    .padding(.top, isHorizontal ? 34 : 39)
                    .padding(.trailing, isHorizontal ? 8 : 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                    .zIndex(101)
            } else if showingStacksHelp {
                stacksHelpCard
                    .padding(.top, isHorizontal ? 34 : 39)
                    .padding(.trailing, isHorizontal ? 44 : 49)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                    .zIndex(100)
            }
        }
        .frame(width: 354)
        .frame(height: isHorizontal ? 190 : nil)
        .frame(minHeight: isHorizontal ? nil : 455)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .environment(\.controlActiveState, .active)
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
            stacksButton
            layoutButton
        }
        .padding(.horizontal, 2)
    }

    private var stacksButton: some View {
        Button {
            guard stacksEnabled || hasGroupableApps else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                stacksEnabled.toggle()
                if !stacksEnabled { expandedStacks.removeAll() }
                compactScrollID = 0
            }
        } label: {
            Image(systemName: stacksEnabled ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stacksEnabled ? Color.white : violet)
                .frame(width: 28, height: 24)
                .background(stacksEnabled ? violet : .white.opacity(0.24),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(violet.opacity(stacksEnabled ? 0 : 0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { showingStacksHelp = hovering }
        }
        .zIndex(showingStacksHelp ? 20 : 1)
        .accessibilityLabel("App stacks")
        .accessibilityValue(stacksEnabled ? "On" : "Off. Keep your mixer tidy by grouping browsers, music and calls.")
    }

    private var stacksHelpCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(violet)
                .frame(width: 20, height: 20)
                .background(violet.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("Keep your mixer tidy by grouping browsers, music and calls.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 218, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.968, blue: 0.91),
                    Color(red: 0.90, green: 0.93, blue: 0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(violet.opacity(0.20), lineWidth: 0.8))
        .shadow(color: ink.opacity(0.14), radius: 12, y: 5)
        .allowsHitTesting(false)
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { showingLayoutHelp = hovering }
        }
        .zIndex(showingLayoutHelp ? 21 : 1)
        .accessibilityLabel(isHorizontal ? "Show full mixer" : "Show compact desk")
    }

    private var layoutHelpCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isHorizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(violet)
                .frame(width: 20, height: 20)
                .background(violet.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(isHorizontal
                 ? "Return to the full mixer."
                 : "Switch to a compact horizontal mixer with studio-style faders.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 218, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.968, blue: 0.91),
                    Color(red: 0.90, green: 0.93, blue: 0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(violet.opacity(0.20), lineWidth: 0.8))
        .shadow(color: ink.opacity(0.14), radius: 12, y: 5)
        .allowsHitTesting(false)
    }

    private var horizontalMixer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("f a d e o u t")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded)).tracking(1.2)
                Spacer()
                stacksButton
                layoutButton
            }
            .padding(.horizontal, 2)
            if model.rows.isEmpty {
                Text("open an app to add it to the mixer")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            compactMasterStrip.id(0)
                            ForEach(Array(mixerItems.enumerated()), id: \.element.id) { index, item in
                                compactMixerItem(item).id(index + 1)
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
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func compactFunctionalScroller(proxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let count = mixerItems.count + 1
            let contentWidth = CGFloat(count) * compactChannelWidth + 2
            let trackWidth = geometry.size.width - 8
            let thumbWidth = max(36, min(trackWidth, trackWidth * geometry.size.width / contentWidth))
            let travel = max(0, trackWidth - thumbWidth)
            let maxIndex = max(1, count - 1)
            let progress = CGFloat(min(max(compactScrollID ?? 0, 0), maxIndex)) / CGFloat(maxIndex)

            if contentWidth > geometry.size.width + 0.5 {
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
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private func compactMixerItem(_ item: MixerItem) -> some View {
        switch item {
        case .app(let row):
            compactChannelStrip(row)
        case .stack(let group):
            compactStackStrip(group)
        }
    }

    private func compactStackStrip(_ group: MixerStackGroup) -> some View {
        let rows = liveRows(in: group)
        let volume = groupVolume(rows)
        return VStack(spacing: 4) {
            Button { model.toggleMute(rows) } label: {
                stackedIcons(rows, size: 17)
                    .opacity(volume == 0 ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .help(volume == 0 ? "Unmute \(group.kind.title)" : "Mute \(group.kind.title)")

            verticalFader(
                value: Binding(get: { groupVolume(liveRows(in: group)) },
                               set: { model.setVolume($0, for: liveRows(in: group)) }),
                label: "\(group.kind.title) volume"
            )
            Text("\(Int(volume * 100))")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(violet)
            Text(group.kind.compactTitle)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .lineLimit(1).foregroundStyle(ink).padding(.horizontal, 2)
        }
        .frame(width: compactChannelWidth, height: 140)
        .background(hoveredAppID == group.id ? .white.opacity(0.34) : .clear)
        .overlay(alignment: .trailing) { Rectangle().fill(violet.opacity(0.08)).frame(width: 1) }
        .animation(.easeOut(duration: 0.12), value: hoveredAppID)
        .onHover { hovering in hoveredAppID = hovering ? group.id : nil }
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
        .frame(width: compactChannelWidth, height: 140)
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
        .frame(width: compactChannelWidth, height: 140)
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
                        ForEach(mixerItems) { item in mixerItem(item) }
                    }
                    .padding(.vertical, 2)
                    .background(NativeScrollerStyler(axis: .vertical))
                }
                .frame(minHeight: 300, maxHeight: 420)
                .animation(.easeInOut(duration: 0.2), value: mixerItems.map(\.id))
            }
        }
        .padding(10)
        .glassCard()
        .layoutPriority(1)
    }

    @ViewBuilder
    private func mixerItem(_ item: MixerItem) -> some View {
        switch item {
        case .app(let row):
            appRow(row)
        case .stack(let group):
            stackSection(group)
        }
    }

    private func stackSection(_ group: MixerStackGroup) -> some View {
        let isExpanded = expandedStacks.contains(group.kind)
        return VStack(spacing: 0) {
            stackRow(group, isExpanded: isExpanded)
            if isExpanded {
                ForEach(liveRows(in: group)) { row in
                    appRow(row)
                        .padding(.leading, 18)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(violet.opacity(isExpanded ? 0.035 : 0),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func stackRow(_ group: MixerStackGroup, isExpanded: Bool) -> some View {
        let rows = liveRows(in: group)
        let volume = groupVolume(rows)
        return HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isExpanded { expandedStacks.remove(group.kind) }
                    else { expandedStacks.insert(group.kind) }
                }
            } label: {
                stackedIcons(rows, size: 24)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(group.kind.title)" : "Show apps in \(group.kind.title)")

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            if isExpanded { expandedStacks.remove(group.kind) }
                            else { expandedStacks.insert(group.kind) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(group.kind.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("\(rows.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(violet)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(violet.opacity(0.10), in: Capsule())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .foregroundStyle(mutedInk)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(volume < 0.999 ? violet : mutedInk)
                }
                Slider(value: Binding(get: { groupVolume(liveRows(in: group)) },
                                      set: { model.setVolume($0, for: liveRows(in: group)) }), in: 0...1)
                    .tint(violet).controlSize(.small).faderTrackFrame(color: violet)
                    .accessibilityLabel("\(group.kind.title) volume")
            }
            Button { model.toggleMute(rows) } label: {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(volume == 0 ? .white : violet)
                    .frame(width: 25, height: 25)
                    .background(volume == 0 ? AnyShapeStyle(violet) : AnyShapeStyle(.white.opacity(0.26)), in: Circle())
                    .overlay(Circle().stroke(violet.opacity(volume == 0 ? 0 : 0.13), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(volume == 0 ? "Unmute \(group.kind.title)" : "Mute \(group.kind.title)")
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(hoveredAppID == group.id ? .white.opacity(0.30) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(violet.opacity(0.08)).frame(height: 1) }
        .onHover { hovering in hoveredAppID = hovering ? group.id : nil }
    }

    private func liveRows(in group: MixerStackGroup) -> [AppRow] {
        group.rows.compactMap { groupedRow in
            model.rows.first(where: { $0.bundleID == groupedRow.bundleID })
        }
    }

    private func groupVolume(_ rows: [AppRow]) -> Double {
        guard !rows.isEmpty else { return 1 }
        return rows.map(\.volume).reduce(0, +) / Double(rows.count)
    }

    private func stackedIcons(_ rows: [AppRow], size: CGFloat) -> some View {
        let visible = Array(rows.prefix(3))
        let step = size * 0.38
        return ZStack(alignment: .leading) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                Image(nsImage: row.icon).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(.white.opacity(0.85), lineWidth: 1))
                    .offset(x: CGFloat(index) * step)
                    .zIndex(Double(visible.count - index))
            }
        }
        .frame(width: size + CGFloat(max(0, visible.count - 1)) * step, height: size,
               alignment: .leading)
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
    override var isOpaque: Bool { false }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        6
    }

    override func draw(_ dirtyRect: NSRect) {
        // AppKit normally redraws inactive overlay scrollers using the system tint. Own the
        // complete drawing pass so the forest treatment is identical in and out of focus.
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        drawKnobSlot(in: rect(for: .knobSlot), highlight: false)
        if knobProportion < 0.999 { drawKnob() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        needsDisplay = true
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
