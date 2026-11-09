import SwiftUI

/// Home's family block: one row per person — who, where, since when, the
/// shape of their day so far, and for anyone on the move where they are
/// heading and when they will get there. Replaced the Orbit (review
/// 2026-11-09): the rules are `FamilyBoard` (Foundation-only, Linux-tested);
/// this adapts the household view and the forecast into it and draws it.
struct HomeFamilyBoard: View {
    let view: HouseholdView
    let forecast: FamilyForecast?
    var openPerson: ((String) -> Void)? = nil
    @ObservedObject private var places = PlaceNamer.shared
    @ObservedObject private var photos = FamilyPhotos.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Rows that fit the large tile: five at ordinary text sizes, three from
    /// the accessibility sizes up; past that, "+N more".
    private var capacity: Int { typeSize.isAccessibilitySize ? 3 : 5 }

    var body: some View {
        // Redrawn once a minute: "for 12 min" and the strip's right edge move
        // with the clock, not only when the view does.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let input = Self.input(view: view, forecast: forecast, places: places, now: context.date)
            let rows = FamilyBoard.rows(input, clock: Self.clock)
            let colours = SR.PersonHue.assign(view.people.map(\.subject))
            let initials = view.initials
            let shown = rows.count > capacity ? Array(rows.prefix(capacity - 1)) : rows
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shown) { row in
                    rowView(row, colour: colours[row.subject] ?? SR.accent, initials: initials[row.subject] ?? HouseholdView.twoLetters(row.name))
                }
                if shown.count < rows.count {
                    Text("+\(rows.count - shown.count) more on Family")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .padding(.leading, 46)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-board")
    }

    // MARK: A row

    @ViewBuilder
    private func rowView(_ row: FamilyBoardRow, colour: Color, initials: String) -> some View {
        let content = HStack(alignment: .center, spacing: 10) {
            avatar(row, colour: colour, initials: initials)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.isSelf ? "You" : firstName(row.name))
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .layoutPriority(2)
                    Text(row.headline)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(row.sharing ? SR.inkSecondary : SR.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    trailing(row)
                }
                if let journey = row.journey {
                    journeyBar(journey, colour: colour)
                } else if !row.strip.isEmpty {
                    strip(row.strip, colour: colour)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
        .accessibilityIdentifier("family-board-\(row.subject)")

        if let openPerson, row.sharing {
            Button {
                SRHaptic.tap()
                openPerson(row.subject)
            } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens their page on Family")
        } else {
            content
        }
    }

    /// Their picture or initials, ringed by how recently they were heard from;
    /// a red dot for a low battery, a dashed ring for not sharing.
    private func avatar(_ row: FamilyBoardRow, colour: Color, initials: String) -> some View {
        let size: CGFloat = 36
        return ZStack {
            if let image = photos.image(id: nil, subject: row.subject), row.sharing {
                FamilyPhotoCircle(image: image, size: size - 4)
            } else {
                Text(initials)
                    .font(SR.Text.title(13))
                    .foregroundStyle(row.sharing ? .white : SR.inkMuted)
                    .frame(width: size - 4, height: size - 4)
                    .background(Circle().fill(row.sharing ? colour : SR.surface))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if row.sharing {
                Circle().strokeBorder(row.stale ? SR.warn : (row.moving ? colour : SR.paper), lineWidth: row.moving ? 2.5 : 2)
            } else {
                Circle().strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if row.lowBattery {
                Circle().fill(SR.error).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(SR.surface, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
    }

    /// "since 08:41" / "for 12 min" — and a low battery, which outranks it.
    @ViewBuilder
    private func trailing(_ row: FamilyBoardRow) -> some View {
        if row.lowBattery, let battery = row.battery {
            Label("\(battery)%", systemImage: BatteryReading.symbol(battery))
                .labelStyle(.titleAndIcon)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.error)
                .lineLimit(1)
                .fixedSize()
        } else if let since = row.since {
            Text(since)
                .font(SR.Text.mono(12))
                .foregroundStyle(row.stale ? SR.warn : SR.inkMuted)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The day so far: one slice per twenty-odd minutes since the morning,
    /// grey at home, their colour washed out away, solid while travelling.
    private func strip(_ bands: [FamilyBand], colour: Color) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fill(band, colour: colour))
                    .frame(height: band == .moving ? 6 : 4)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func fill(_ band: FamilyBand, colour: Color) -> Color {
        switch band {
        case .none: return SR.line.opacity(0.5)
        case .home: return SR.inkGhost.opacity(0.45)
        case .away: return colour.opacity(0.4)
        case .moving: return colour
        }
    }

    /// "→ School · 09:06–09:10" over how far through the journey they are.
    private func journeyBar(_ journey: FamilyBoardRow.JourneyLine, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let progress = journey.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colour.opacity(0.18))
                        Capsule().fill(colour).frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 5)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                Text("\(journey.to) · arriving \(journey.eta)")
                    .lineLimit(1)
            }
            .font(SR.Text.mono(12))
            .foregroundStyle(SR.accentInk)
        }
        .accessibilityHidden(true)
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: Adapting the view

    static func clock(_ t: Double) -> String {
        Date(timeIntervalSince1970: t).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    @MainActor
    static func input(view: HouseholdView, forecast: FamilyForecast?, places: PlaceNamer, now: Date,
                      calendar: Calendar = .current) -> FamilyBoardInput {
        let nowT = now.timeIntervalSince1970
        let home = FamilyOrbitMath.home(people: view.people, watch: view.watch).map { (lat: $0.lat, lon: $0.lon) }
        let midnight = calendar.startOfDay(for: now).timeIntervalSince1970
        let earliest = view.people.compactMap { $0.today?.trail.compactMap { $0.count >= 3 ? $0[2] : nil }.min() }.min()
        // From 06:00, or earlier when somebody's day began earlier; never
        // before midnight, and never so late the strip has no width.
        let six = midnight + 6 * 3600
        var start = max(midnight, min(six, earliest ?? six))
        if nowT - start < 3600 { start = max(midnight, nowT - 3600) }

        let people = view.people.map { person -> FamilyBoardInput.Person in
            var p = FamilyBoardInput.Person(subject: person.subject, name: person.name, isSelf: person.isSelf,
                                            status: person.status, place: person.placeName)
            p.battery = person.batteryPct
            p.lastSeen = person.lastSeenAt.flatMap(FamilyPerson.isoDate)?.timeIntervalSince1970
            if let position = person.position {
                p.lat = position.lat
                p.lon = position.lon
            }
            p.trail = person.today?.trail
            if let moving = person.moving {
                p.movingMode = moving.mode
                p.movingSince = parseTimestamp(moving.since)?.timeIntervalSince1970
                p.speedKmh = moving.speedKmh
                if let position = person.position { p.near = places.name(lat: position.lat, lon: position.lon) }
                if let next = forecast?.next(for: person.subject), next.kind == "arriving",
                   let from = parseTimestamp(next.arriveFrom), let to = parseTimestamp(next.arriveTo) {
                    p.journey = .init(to: next.to, leftAt: parseTimestamp(next.leaveAt)?.timeIntervalSince1970,
                                      arriveFrom: from.timeIntervalSince1970, arriveTo: to.timeIntervalSince1970)
                }
            }
            return p
        }
        return FamilyBoardInput(people: people, home: home, dayStart: start, now: nowT)
    }
}
