import SwiftUI
import MapKit

/// Somebody in the family walking a route, watched live: the route, where
/// they have been, where they are, and how far along. Refreshed every 15 s
/// while it is on screen — the rate their phone sends at.
struct LiveRouteScreen: View {
    let ref: LiveWalkRef
    @StateObject private var store = LiveWalkStore()
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if let walk = store.walk {
                content(walk)
            } else {
                ScrollView {
                    TrailStateView(state: store.state, noun: "walk", retry: { Task { await store.load(ref.id) } })
                        .padding(.top, 40)
                }
            }
        }
        .srPaper()
        .navigationTitle(ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load(ref.id)
            while !Task.isCancelled, store.walk?.endedAt == nil {
                try? await Task.sleep(for: .seconds(LiveShare.interval))
                guard !Task.isCancelled else { break }
                await store.load(ref.id)
            }
        }
    }

    private func content(_ walk: LiveWalk) -> some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                MapPolyline(coordinates: walk.route.map(\.coordinate))
                    .stroke(SR.accent.opacity(0.85), lineWidth: 5)
                if walk.trail.count > 1 {
                    MapPolyline(coordinates: walk.trail.map(\.coordinate))
                        .stroke(SR.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                if let here = walk.trail.last {
                    Annotation(walk.name, coordinate: here.coordinate, anchor: .center) {
                        Circle().fill(SR.accent).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(SR.paper, lineWidth: 3))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .accessibilityIdentifier("live-walk-map")

            VStack(alignment: .leading, spacing: 10) {
                Text(walk.line)
                    .font(SR.Text.mono(16))
                    .foregroundStyle(walk.progress?.offRoute == true ? SR.accent : SR.ink)
                ProgressView(value: walk.fraction).tint(SR.accent)
                Text(seen(walk))
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            .padding(16)
            .srGlassCard()
            .padding(12)
        }
    }

    private func seen(_ walk: LiveWalk) -> String {
        guard let iso = walk.lastFixAt, let at = ISO8601DateFormatter.srFractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return "Waiting for the first position."
        }
        let mins = Int(Date().timeIntervalSince(at) / 60)
        return mins < 1 ? "Position just now." : "Position \(mins) min ago."
    }
}

extension ISO8601DateFormatter {
    static let srFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// "Out on a route" on the Family tab: each live walk this phone may follow.
struct LiveWalksCard: View {
    @ObservedObject var store: LiveWalksStore

    var body: some View {
        if !store.walks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SRSectionLabel(text: "Out on a route", trailing: "\(store.walks.count)")
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(store.walks) { w in
                        NavigationLink(value: LiveWalkRef(id: w.id, title: "\(w.name) · \(w.routeName)")) {
                            HStack(spacing: 12) {
                                Image(systemName: Sport.icon(w.sport))
                                    .foregroundStyle(SR.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(w.name) · \(w.routeName)").font(SR.Text.title()).foregroundStyle(SR.ink)
                                    Text(w.line).font(SR.Text.mono(13)).foregroundStyle(SR.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(SR.inkMuted)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("live-walk-\(w.id)")
                    }
                }
                .srGlassCard(.paper)
            }
        }
    }
}
