import SwiftUI

/// The career: the season under way (its next round, calendar and table),
/// the ladder of four championships, and a lifetime's record.
struct CarProCareerView: View {
    @ObservedObject var game: CarProGame
    @State private var starting: CarProTier?
    @State private var confirmAbandon = false

    var body: some View {
        CarProPage {
            header
            if let season = game.career.season {
                if season.complete {
                    seasonOver(season)
                } else {
                    nextRound(season)
                }
                calendar(season)
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Standings", trailing: season.tier.name)
                    CarProStandingsTable(table: season.table)
                }
                if !season.complete {
                    Button(role: .destructive) {
                        confirmAbandon = true
                    } label: {
                        SRButtonLabel(title: "Give up this season", icon: "xmark", fill: true)
                            .frame(minHeight: 48)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("car-pro-abandon")
                }
            }
            ladder
            record
        }
        .sheet(item: $starting) { tier in
            CarProSeasonStartSheet(game: game, tier: tier)
        }
        .confirmationDialog("Give up the season?", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Give up the season", role: .destructive) { game.abandonSeason() }
            Button("Keep racing", role: .cancel) {}
        } message: {
            Text("The points so far are lost. Prize money you have won is yours to keep.")
        }
        .accessibilityIdentifier("car-pro-career-page")
    }

    private var header: some View {
        let career = game.career
        let titles = career.titles.count
        return SRPageHeader(kicker: "Career", title: CarProFormat.money(career.money),
                            strap: "\(titles) title\(titles == 1 ? "" : "s") · \(career.stats.wins) wins · "
                                + "\(career.stats.podiums) podiums. Win prize money; spend it in the garage.")
    }

    // MARK: - The season

    private func nextRound(_ season: CarProSeason) -> some View {
        let trackId = season.tier.calendar[season.round]
        let track = CarProCircuits.track(trackId) ?? CarProCircuits.all[0]
        let car = game.career.car(season.playerCarId)
        let pi = car?.setup.stats.pi ?? 0
        let inProgress = game.weekend.map { $0.weekend.round == season.round && $0.weekend.tier == season.tier } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Round \(season.round + 1) of \(season.tier.calendar.count)", trailing: season.tier.name)
            VStack(alignment: .leading, spacing: 12) {
                CarProTrackMap(track: track)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                    Text("\(season.tier.laps(on: track)) laps · \(CarProFormat.length(track.length)) · \(track.location)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    Text("Running \(CarProFormat.ordinal(season.playerPosition)) in the table"
                         + (car.map { " in the \($0.model.name)." } ?? "."))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
                if pi > season.tier.piLimit {
                    Label("PI \(pi) is over the \(season.tier.name) limit of \(season.tier.piLimit). Ease the tuning back in the garage.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    SRHaptic.tap()
                    game.openWeekend()
                } label: {
                    SRButtonLabel(title: inProgress ? "Back to the weekend" : "To the weekend", icon: "flag.checkered", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-next-round")
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
    }

    private func seasonOver(_ season: CarProSeason) -> some View {
        let place = season.playerPosition
        let won = place == 1
        return VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Season over", trailing: season.tier.name)
            HStack(spacing: 14) {
                Image(systemName: won ? "trophy.fill" : (place <= 3 ? "medal.fill" : "flag.checkered"))
                    .font(SR.Text.hero(30))
                    .foregroundStyle(Color.white)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(won ? Color(red: 0.95, green: 0.68, blue: 0.12) : SR.accentDeep))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(won ? "Champion" : "You finished \(CarProFormat.ordinal(place))")
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                    Text(Self.seasonOverLine(place: place, tier: season.tier))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
    }

    static func seasonOverLine(place: Int, tier: CarProTier) -> String {
        guard place <= 3 else { return "Finish in the top three to move up. Start another season below." }
        guard let next = tier.next else { return "You have beaten the best." }
        return "The \(next.name) is open to you."
    }

    private func calendar(_ season: CarProSeason) -> some View {
        let places = CarProPresent.playerPlaces(season)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Calendar", trailing: "\(season.tier.calendar.count) rounds")
            VStack(spacing: 0) {
                ForEach(Array(season.tier.calendar.enumerated()), id: \.offset) { round, trackId in
                    if round > 0 { Divider().overlay(SR.divider) }
                    calendarRow(round: round, trackId: trackId, place: places[round], next: round == season.round,
                                tier: season.tier)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }

    private func calendarRow(round: Int, trackId: String, place: Int?, next: Bool, tier: CarProTier) -> some View {
        let track = CarProCircuits.track(trackId) ?? CarProCircuits.all[0]
        return HStack(spacing: 12) {
            CarProTrackMap(track: track)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(round + 1). \(track.name)")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(tier.laps(on: track)) laps · \(CarProFormat.length(track.length))")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 6)
            if let place {
                Text("P\(place)")
                    .font(SR.Text.display(17))
                    .foregroundStyle(place <= 3 ? SR.good : SR.ink)
                    .accessibilityLabel("Finished \(CarProFormat.ordinal(place))")
            } else if next {
                Text("NEXT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(SR.accentDeep))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The ladder

    private var ladder: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Championships", trailing: "4 tiers")
            ForEach(CarProTier.allCases) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: CarProTier) -> some View {
        let state = CarProPresent.state(of: tier, in: game.career)
        let free = game.career.season?.complete ?? true
        let icon: String
        let tint: Color
        switch state {
        case .locked: icon = "lock.fill"; tint = SR.inkMuted
        case .open: icon = "flag.fill"; tint = SR.accentDeep
        case .current: icon = "flag.checkered"; tint = SR.good
        case .champion: icon = "trophy.fill"; tint = Color(red: 0.95, green: 0.68, blue: 0.12)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(SR.Text.title(18))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.name)
                        .font(SR.Text.title())
                        .foregroundStyle(state == .locked ? SR.inkMuted : SR.ink)
                    Text(tier.line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("PI up to \(tier.piLimit) · \(tier.calendar.count) rounds · up to \(CarProFormat.money(CarProPresent.seasonPurse(tier)))")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if state == .locked {
                        Text(CarProPresent.unlockHint(tier))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if state != .locked && state != .current && free {
                Button {
                    SRHaptic.tap()
                    starting = tier
                } label: {
                    SRButtonLabel(title: state == .champion ? "Defend the title" : "Start a season", icon: "play.fill", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(tier == highestOpen ? .prominent : .regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-start-\(tier.rawValue)")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .opacity(state == .locked ? 0.75 : 1)
        .accessibilityElement(children: .contain)
    }

    private var highestOpen: CarProTier? {
        CarProTier.allCases.last { game.career.isUnlocked($0) }
    }

    private var record: some View {
        let stats = game.career.stats
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your record")
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    CarProFact(label: "Races", value: "\(stats.races)")
                    CarProFact(label: "Wins", value: "\(stats.wins)")
                    CarProFact(label: "Podiums", value: "\(stats.podiums)")
                }
                HStack(spacing: 10) {
                    CarProFact(label: "Poles", value: "\(stats.poles)")
                    CarProFact(label: "Titles", value: "\(game.career.titles.count)")
                    CarProFact(label: "Earned", value: CarProFormat.money(stats.earnings))
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
    }
}

/// Choosing the car for a new season: every car in the garage, the ones
/// under the tier's PI limit ready to enter.
struct CarProSeasonStartSheet: View {
    @ObservedObject var game: CarProGame
    let tier: CarProTier
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "New season", title: tier.name,
                                 strap: "\(tier.calendar.count) rounds against seven drivers. Cars up to PI \(tier.piLimit).")
                    VStack(spacing: SR.cardGap) {
                        ForEach(game.career.garage) { car in
                            row(car)
                        }
                    }
                    Text("Too quick for this tier? Buy a slower car in the garage, or move up a tier.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 32)
            }
            .srGround(.warm)
            .navigationTitle("Choose a car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ car: CarProOwnedCar) -> some View {
        let pi = car.setup.stats.pi
        let eligible = pi <= tier.piLimit
        return HStack(spacing: 12) {
            CarProCarPortrait(look: CarProCarLook(setup: car.setup))
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SR.ink.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(car.model.name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                CarProPIBadge(pi: pi)
                if !eligible {
                    Text("Over the limit by \(pi - tier.piLimit)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.error)
                }
            }
            Spacer(minLength: 6)
            Button {
                game.startSeason(tier, carId: car.id)
                dismiss()
            } label: {
                SRButtonLabel(title: "Enter", icon: "flag.fill")
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(!eligible)
            .accessibilityIdentifier("car-pro-enter-\(car.id)")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
    }
}

/// A championship round: the briefing, the grid from qualifying, the result.
struct CarProWeekendView: View {
    @ObservedObject var game: CarProGame

    var body: some View {
        CarProPage {
            if let current = game.weekend {
                switch current.stage {
                case .briefing:
                    briefing(current.weekend)
                case let .grid(rows, playerLap):
                    grid(current.weekend, rows: rows, playerLap: playerLap)
                case let .result(results, reward):
                    result(current.weekend, results: results, reward: reward)
                }
            } else {
                SRPageHeader(kicker: "Career", title: "No round to race", strap: "Start a season from the career page.")
                Button {
                    game.open(.career)
                } label: {
                    SRButtonLabel(title: "To the career", icon: "trophy.fill", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
            }
        }
        .accessibilityIdentifier("car-pro-weekend")
    }

    // MARK: - Briefing

    @ViewBuilder
    private func briefing(_ w: CarProWeekend) -> some View {
        let track = w.track
        SRPageHeader(kicker: "Round \(w.round + 1) of \(w.tier.calendar.count) · \(w.tier.name)", title: track.name,
                     strap: track.line)
        VStack(alignment: .leading, spacing: 12) {
            CarProTrackMap(track: track)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
            HStack(spacing: 10) {
                CarProFact(label: "Laps", value: "\(w.laps)")
                CarProFact(label: "Length", value: CarProFormat.length(track.length))
                CarProFact(label: "Corners", value: "\(track.corners.count)")
            }
            Text("Corners: " + track.corners.map(\.name).joined(separator: ", ") + ".")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The field", trailing: "\(w.field.count + 1) cars")
            VStack(spacing: 0) {
                fieldRow(w.player, you: true)
                ForEach(w.field) { entrant in
                    Divider().overlay(SR.divider)
                    fieldRow(entrant, you: false)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
        VStack(spacing: 10) {
            Button {
                SRHaptic.tap()
                game.qualify()
            } label: {
                SRButtonLabel(title: "Qualify: two timed laps", icon: "stopwatch.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-qualify")
            Button {
                SRHaptic.tap()
                game.skipQualifying()
            } label: {
                SRButtonLabel(title: "Skip qualifying, start last", icon: "forward.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-skip-qualifying")
        }
    }

    private func fieldRow(_ entrant: CarProEntrant, you: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(CarProCarArt.livery(entrant.hue))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(you ? "\(entrant.name) (you)" : entrant.name)
                    .font(SR.Text.title(15))
                    .foregroundStyle(you ? SR.accent : SR.ink)
                    .lineLimit(1)
                Text(entrant.setup.model.name + (entrant.driver.map { " · " + Self.temperament($0) } ?? ""))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            CarProPIBadge(pi: entrant.setup.stats.pi)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// A driver in two words: how quick, how bold.
    static func temperament(_ driver: CarProDriverProfile) -> String {
        let pace = driver.skill > 0.8 ? "Quick" : (driver.skill > 0.5 ? "Steady" : "Learning")
        let style = driver.aggression > 0.6 ? "bold" : (driver.aggression < 0.35 ? "careful" : "fair")
        return "\(pace), \(style)"
    }

    // MARK: - Grid

    @ViewBuilder
    private func grid(_ w: CarProWeekend, rows: [CarProQualifyingRow], playerLap: Double?) -> some View {
        let slot = (rows.firstIndex { $0.entrant.isPlayer } ?? rows.count - 1) + 1
        let pole = rows.first?.time
        SRPageHeader(kicker: "Qualifying · \(w.track.name)", title: Self.gridTitle(slot: slot, playerLap: playerLap),
                     strap: Self.gridStrap(playerLap))
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(SR.Text.display(17))
                        .foregroundStyle(index == 0 ? SR.accent : SR.inkGhost)
                        .frame(width: 26, alignment: .leading)
                    Circle()
                        .fill(CarProCarArt.livery(row.entrant.hue))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.entrant.name)
                            .font(SR.Text.title(15))
                            .foregroundStyle(row.entrant.isPlayer ? SR.accent : SR.ink)
                            .lineLimit(1)
                        Text(row.entrant.setup.model.name)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 6)
                    Text(gridTime(row.time, pole: pole, first: index == 0))
                        .font(SR.Text.title(15))
                        .monospacedDigit()
                        .foregroundStyle(SR.ink)
                }
                .padding(.vertical, 8)
                .background(row.entrant.isPlayer ? SR.accent.opacity(0.07) : Color.clear)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityIdentifier("car-pro-grid")
        VStack(spacing: 10) {
            Button {
                SRHaptic.tap()
                game.startRace()
            } label: {
                SRButtonLabel(title: "To the grid: \(w.laps) laps", icon: "flag.checkered", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-race-start")
            Button {
                game.back()
            } label: {
                SRButtonLabel(title: "Back to the career", icon: "chevron.backward", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
        }
    }

    static func gridTitle(slot: Int, playerLap: Double?) -> String {
        guard playerLap != nil else { return "You start last" }
        return slot == 1 ? "Pole position!" : "You start \(CarProFormat.ordinal(slot))"
    }

    static func gridStrap(_ playerLap: Double?) -> String {
        guard let playerLap else { return "No timed lap: from the back of the grid." }
        return "Your best lap: \(CarProFormat.time(playerLap))."
    }

    static func resultTitle(_ mine: CarProResult?) -> String {
        guard let mine, mine.time != nil else { return "You retired" }
        return mine.position == 1 ? "You won!" : "You finished \(CarProFormat.ordinal(mine.position))"
    }

    static func resultStrap(_ reward: CarProRaceReward?, tier: CarProTier) -> String? {
        guard let reward else { return nil }
        return "Now \(CarProFormat.ordinal(reward.championshipPosition)) in the \(tier.name)."
    }

    private func gridTime(_ time: Double?, pole: Double?, first: Bool) -> String {
        guard let time else { return "No time" }
        if first { return CarProFormat.time(time) }
        guard let pole else { return CarProFormat.time(time) }
        return "+" + CarProFormat.time(time - pole)
    }

    // MARK: - Result

    @ViewBuilder
    private func result(_ w: CarProWeekend, results: [CarProResult], reward: CarProRaceReward?) -> some View {
        let mine = results.first { $0.isPlayer }
        SRPageHeader(kicker: "Round \(w.round + 1) · \(w.track.name)", title: Self.resultTitle(mine),
                     strap: Self.resultStrap(reward, tier: w.tier))
        if let reward {
            CarProRewardStrip(reward: reward)
            if reward.seasonComplete {
                CarProSeasonEndCard(reward: reward, tier: w.tier)
            }
        }
        CarProResultsTable(results: results, showPoints: true)
        if results.contains(where: { $0.estimated }) {
            Text("Cars still running when you took the flag are timed from their pace.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button {
            SRHaptic.tap()
            game.closeWeekend()
        } label: {
            SRButtonLabel(title: "Continue", icon: "arrow.right", fill: true)
                .frame(minHeight: 48)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("car-pro-weekend-done")
    }
}

/// What a race paid: points, prize money, the fastest lap.
struct CarProRewardStrip: View {
    let reward: CarProRaceReward

    var body: some View {
        HStack(spacing: 10) {
            chip("+\(reward.points)", "points", SR.accentDeep)
            chip(CarProFormat.money(reward.prize), "prize", SR.good)
            if reward.fastestLap {
                chip("+1", "fastest lap", Color(red: 0.55, green: 0.32, blue: 0.88))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chip(_ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SR.Text.display(20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
    }
}

/// The end of a season: the bonus, a title, the tier it opened.
struct CarProSeasonEndCard: View {
    let reward: CarProRaceReward
    let tier: CarProTier
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: reward.title ? "trophy.fill" : "flag.checkered")
                    .font(SR.Text.hero(28))
                    .foregroundStyle(reward.title ? Color(red: 0.95, green: 0.68, blue: 0.12) : SR.accent)
                    .scaleEffect(shown ? 1 : 0.4)
                    .accessibilityHidden(true)
                Text(reward.title ? "\(tier.name) champion!" : "Season over: \(CarProFormat.ordinal(reward.championshipPosition))")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if reward.seasonBonus > 0 {
                Text("Season bonus: \(CarProFormat.money(reward.seasonBonus)).")
                    .font(SR.Text.body())
                    .foregroundStyle(SR.inkSecondary)
            }
            if let unlocked = reward.unlocked {
                Label("The \(unlocked.name) is open.", systemImage: "lock.open.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true }
            SRHaptic.ok()
        }
        .accessibilityElement(children: .combine)
    }
}
