import SwiftUI

/// Car Racer+: a deeper top-down racer with real grip, gears and weight,
/// eight circuits, a career of four championships and a garage of cars to
/// buy, upgrade and tune. Pushed on the Games stack; each page is a part of
/// this one screen, so the bar's back button walks back through them before
/// it leaves the game, and a session on the circuit takes the whole screen.
struct CarProScreen: View {
    @StateObject private var game = CarProGame()

    var body: some View {
        ZStack(alignment: .top) {
            content
            if let notice = game.notice, game.race == nil {
                CarProNotice(text: notice)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { game.clearNotice() }
                    .accessibilityIdentifier("car-pro-notice")
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: game.notice)
        .navigationTitle(GameKind.carRacerPlus.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(game.race == nil ? .visible : .hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(game.page != .home || game.race != nil)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if game.page != .home && game.race == nil {
                    Button {
                        SRHaptic.tap()
                        game.back()
                    } label: {
                        Label(game.page == .weekend ? "Career" : "Car Racer+", systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("car-pro-bar-back")
                }
            }
        }
        .statusBarHidden(game.race != nil)
        .onAppear {
            // Build the circuits away from the main thread while the menu is read.
            Task.detached(priority: .userInitiated) { _ = CarProCircuits.all.count }
        }
        .accessibilityIdentifier("car-pro-screen")
    }

    @ViewBuilder
    private var content: some View {
        if let race = game.race {
            CarProRaceView(race: race, title: game.raceTitle, line: game.raceLine) { game.leaveRace() }
                .id(ObjectIdentifier(race))
                .transition(.opacity)
        } else {
            page
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch game.page {
        case .home: CarProHomeView(game: game)
        case .career: CarProCareerView(game: game)
        case .weekend: CarProWeekendView(game: game)
        case .quickRace: CarProQuickRaceView(game: game)
        case .timeTrial: CarProTimeTrialView(game: game)
        case .garage: CarProGarageView(game: game)
        case .settings: CarProSettingsView(game: game)
        }
    }
}

/// The front page: the car you drive, your money, and the ways to race.
struct CarProHomeView: View {
    @ObservedObject var game: CarProGame
    @State private var showHowTo = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        CarProPage {
            hero
            tiles
            howTo
        }
        .sheet(isPresented: $showHowTo) {
            CarProHowToSheet(settings: game.settings)
        }
        .accessibilityIdentifier("car-pro-home")
    }

    private var hero: some View {
        let car = game.selectedCar
        let stats = car.setup.stats
        return VStack(alignment: .leading, spacing: 12) {
            SRPageHeader(kicker: "Car Racer+", title: car.model.name, strap: car.model.line)
            ZStack(alignment: .bottomLeading) {
                CarProShowroomFloor(hue: car.model.hue)
                CarProCarPortrait(look: CarProCarLook(setup: car.setup), spin: -0.35)
                    .padding(.vertical, 14)
                HStack(spacing: 8) {
                    CarProPIBadge(pi: stats.pi, large: true)
                    Spacer(minLength: 0)
                    Text(CarProFormat.money(game.career.money))
                        .font(SR.Text.display(20))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .accessibilityLabel("Money \(CarProFormat.money(game.career.money))")
                }
                .padding(12)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            .accessibilityElement(children: .contain)
            HStack(spacing: 10) {
                CarProFact(label: "Power", value: "\(CarProPresent.horsepower(kilowatts: stats.power)) bhp")
                CarProFact(label: "Weight", value: CarProPresent.mass(stats.mass))
                CarProFact(label: "Drive", value: stats.drive.short)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            Text(careerLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var careerLine: String {
        let career = game.career
        if let season = career.season, !season.complete {
            return "\(season.tier.name): round \(season.round + 1) of \(season.tier.calendar.count), "
                + "running \(CarProFormat.ordinal(season.playerPosition)) in the table."
        }
        let titles = career.titles.count
        if career.stats.races == 0 { return "Your career starts in the Club Cup. Win prize money, buy cars, upgrade them." }
        return "\(career.stats.races) races, \(career.stats.wins) wins, \(titles) title\(titles == 1 ? "" : "s")."
    }

    private var tiles: some View {
        let columns: [GridItem] = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: SR.cardGap), GridItem(.flexible(), spacing: SR.cardGap)]
        return LazyVGrid(columns: columns, spacing: SR.cardGap) {
            CarProTile(icon: "trophy.fill", title: "Career", line: careerTileLine,
                       tint: Color(red: 0.92, green: 0.55, blue: 0.10), id: "car-pro-career") { game.open(.career) }
            CarProTile(icon: "flag.checkered", title: "Quick race", line: "Any circuit, any length, rivals in cars like yours.",
                       tint: Color(red: 0.86, green: 0.22, blue: 0.24), id: "car-pro-quick") { game.open(.quickRace) }
            CarProTile(icon: "stopwatch.fill", title: "Time trial", line: "Chase your best lap's ghost and read the trace.",
                       tint: Color(red: 0.20, green: 0.50, blue: 0.90), id: "car-pro-trial") { game.open(.timeTrial) }
            CarProTile(icon: "wrench.and.screwdriver.fill", title: "Garage", line: garageLine,
                       tint: Color(red: 0.18, green: 0.62, blue: 0.42), id: "car-pro-garage") { game.open(.garage) }
            CarProTile(icon: "slider.horizontal.3", title: "Settings", line: "\(game.settings.assists.count) of 6 aids on · \(game.settings.steering.name) steering",
                       tint: Color(red: 0.45, green: 0.45, blue: 0.55), id: "car-pro-settings") { game.open(.settings) }
            CarProTile(icon: "questionmark.circle.fill", title: "How to drive", line: "Pedals, gears, grip and the racing line.",
                       tint: Color(red: 0.55, green: 0.32, blue: 0.88), id: "car-pro-howto") { showHowTo = true }
        }
    }

    private var careerTileLine: String {
        if let season = game.career.season, !season.complete {
            return "\(season.tier.name), round \(season.round + 1) of \(season.tier.calendar.count)."
        }
        return "Four championships, Club Cup to Pro."
    }

    private var garageLine: String {
        let cars = game.career.garage.count
        return "\(cars) car\(cars == 1 ? "" : "s") · upgrades and tuning"
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Driving")
            CarProHowToDrive(steering: game.settings.steering, assists: game.settings.assists, isRace: true)
                .padding(SR.cardPadding)
                .srGlassCard(.paper)
        }
    }
}

/// The garage floor under the car: a lit gradient in the car's colour.
struct CarProShowroomFloor: View {
    let hue: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.32), Color(white: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.28), Color.clear], center: .center, startRadius: 4,
                           endRadius: 170)
            VStack(spacing: 22) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// How to drive, at length: the controls and what the car is doing under you.
struct CarProHowToSheet: View {
    let settings: CarProSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "Car Racer+", title: "How to drive",
                                 strap: "Real cars: they grip, slide, lean and wear. Smooth is fast.")
                    CarProHowToDrive(steering: settings.steering, assists: settings.assists, isRace: true)
                        .padding(SR.cardPadding)
                        .srGlassCard(.paper)
                    section("Grip", [
                        ("circle.circle", "A tyre can steer or brake or accelerate, and only so much of all three at once. Brake in a straight line, then turn."),
                        ("arrow.left.and.right", "Weight moves forward when you brake and outward in a bend. The front grips harder under braking, the rear when you accelerate."),
                        ("thermometer.medium", "Tyres work best warm. Softer compounds grip harder but want more heat and wear faster."),
                    ])
                    section("Your aids", [
                        ("steeringwheel", "Steering help catches a slide for you. Off, you counter-steer yourself."),
                        ("hand.raised.fill", "Traction control stops the wheels spinning. ABS stops them locking."),
                        ("gearshape.2.fill", "Automatic gears change for you. Manual is quicker if you change at the lights."),
                    ])
                    section("Racing", [
                        ("flag.checkered", "Qualify for a better grid place. Points go 25, 18, 15, 12, 10, 8, 6, 4, and one for the fastest lap."),
                        ("exclamationmark.triangle.fill", "Four wheels off the track deletes the lap. In a race, every third warning costs 5 seconds."),
                        ("wrench.and.screwdriver.fill", "Spend prize money on upgrades and faster cars, but keep under each championship's PI limit."),
                    ])
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 32)
            }
            .srGround(.warm)
            .navigationTitle("How to drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("car-pro-howto-done")
                }
            }
        }
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: title)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.0)
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.accent)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        Text(row.1)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
    }
}
