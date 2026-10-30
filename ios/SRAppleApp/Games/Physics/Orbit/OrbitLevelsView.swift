import SwiftUI

/// The level list: how to play, the stars so far and a button for the next
/// level, then the three systems with ten levels each. A level opens when
/// the one before it is done.
struct OrbitLevelsView: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                ForEach(OrbitSystem.allCases) { system in
                    OrbitSystemSection(game: game, system: system)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(OrbitLevelsBackdrop().ignoresSafeArea())
        .accessibilityIdentifier("orbit-level-list")
    }

    private var next: Int { game.progress.nextLevel(of: OrbitLevels.count) }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ORBIT")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Let gravity swing you home.")
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            OrbitHowToPlay()
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(OrbitPaint.goldDeep)
                Text("\(game.progress.totalStars) of \(OrbitLevels.count * 3) stars")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                Spacer(minLength: 8)
                Text("\(game.progress.finishedLevels) of \(OrbitLevels.count) levels")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            .accessibilityElement(children: .combine)
            OrbitCardButton(title: playTitle, icon: "paperplane.fill") { game.open(next) }
                .accessibilityIdentifier("orbit-play")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var playTitle: String {
        if game.progress.finishedLevels == 0 { return "Play level 1" }
        if game.progress.finishedLevels >= OrbitLevels.count { return "Play level \(next) again" }
        return "Play level \(next)"
    }
}

/// One system: its name, a line about it, its stars, and its ten levels.
struct OrbitSystemSection: View {
    @ObservedObject var game: OrbitGame
    let system: OrbitSystem

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("SYSTEM \(system.rawValue + 1)")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                Spacer(minLength: 8)
                Text("\(starsHere) of 30 stars")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
            }
            Text(system.title)
                .font(SR.Text.display(20))
                .foregroundStyle(SR.ink)
            Text(system.line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(system.levels), id: \.self) { number in
                    OrbitLevelTile(game: game, number: number)
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var starsHere: Int {
        system.levels.reduce(0) { $0 + game.progress.stars($1) }
    }
}

/// A level's button: its number and stars, a lock until it opens, and a
/// ring round the next one to play.
struct OrbitLevelTile: View {
    @ObservedObject var game: OrbitGame
    let number: Int

    var body: some View {
        let open = game.progress.isOpen(number)
        let stars = game.progress.stars(number)
        let next = game.progress.nextLevel(of: OrbitLevels.count) == number && game.progress.best(number) == nil
        Button {
            SRHaptic.tap()
            game.open(number)
        } label: {
            face(open: open, stars: stars, next: next)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!open)
        .accessibilityLabel(label(open: open, stars: stars))
        .accessibilityIdentifier("orbit-level-\(number)")
    }

    private func face(open: Bool, stars: Int, next: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(spacing: 3) {
            if open {
                Text("\(number)")
                    .font(SR.Text.figure(20))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < stars ? "star.fill" : "star")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(i < stars ? OrbitPaint.gold : Color.white.opacity(0.45))
                    }
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(shape.fill(OrbitLevelTile.fill(system: OrbitSystem.of(level: number), open: open)))
        .overlay(shape.stroke(next ? OrbitPaint.gold : Color.white.opacity(0.12), lineWidth: next ? 2.5 : 1))
        .shadow(color: next ? OrbitPaint.gold.opacity(0.45) : Color.clear, radius: 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    static func fill(system: OrbitSystem, open: Bool) -> LinearGradient {
        let colours: [Color]
        if !open {
            colours = [OrbitPaint.rgb(0.30, 0.31, 0.38), OrbitPaint.rgb(0.18, 0.19, 0.25)]
        } else {
            switch system {
            case .inner: colours = [OrbitPaint.rgb(0.96, 0.52, 0.28), OrbitPaint.rgb(0.78, 0.24, 0.36)]
            case .giants: colours = [OrbitPaint.rgb(0.16, 0.68, 0.70), OrbitPaint.rgb(0.14, 0.34, 0.66)]
            case .deep: colours = [OrbitPaint.rgb(0.56, 0.32, 0.92), OrbitPaint.rgb(0.22, 0.12, 0.48)]
            }
        }
        return LinearGradient(colors: colours, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func label(open: Bool, stars: Int) -> String {
        let lv = OrbitLevels.level(number)
        guard open else { return "Level \(number), \(lv.name), locked" }
        if game.progress.best(number) == nil { return "Level \(number), \(lv.name), not done yet" }
        return "Level \(number), \(lv.name), \(stars) of 3 stars"
    }
}

/// Still space behind the level list: drawn once, no animation.
struct OrbitLevelsBackdrop: View {
    /// Made once for the app's life, not each time the list redraws.
    private static let sky = OrbitSkyLayout(level: nil, seed: 11)

    var body: some View {
        let sky = Self.sky
        return Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: [OrbitPaint.spaceHigh, OrbitPaint.spaceDeep]),
                                                           startPoint: CGPoint(x: 0, y: 0),
                                                           endPoint: CGPoint(x: size.width, y: size.height)))
            let w = Double(size.width), h = Double(size.height)
            for layer in sky.layers {
                for star in layer {
                    let s = star.size
                    let x = star.x * w, y = star.y * h
                    context.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2)),
                                 with: .color(OrbitPaint.starWhite.opacity(star.brightness * 0.8)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
