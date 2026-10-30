import Foundation

// Car Racer+ cars: the six base cars, the nine upgrade lines with three
// stages each, the tuning a driver can set, the physical numbers all of that
// adds up to (`CarProVehicleParams`), and the stats and performance index
// (PI) the garage shows and the tiers check against.

/// Which wheels the engine drives.
enum CarProDrive: String, Codable, CaseIterable {
    case fwd
    case rwd
    case awd

    var name: String {
        switch self {
        case .fwd: return "Front-wheel drive"
        case .rwd: return "Rear-wheel drive"
        case .awd: return "All-wheel drive"
        }
    }

    var short: String { rawValue.uppercased() }
}

/// A car as it leaves the factory.
struct CarProCarSpec: Equatable {
    var mass: Double
    /// Share of the weight on the front axle.
    var frontWeight: Double
    var wheelbase: Double
    var trackWidth: Double
    /// Centre of mass height: what makes weight move under braking and cornering.
    var comHeight: Double
    var wheelRadius: Double = 0.31
    var idleRpm: Double = 900
    var torqueRpm: Double
    var redline: Double
    var peakTorque: Double
    /// kg·m² at the crank.
    var engineInertia: Double
    /// Extra torque at full boost from a factory turbo, as a share.
    var turbo: Double = 0
    var gears: [Double]
    var finalDrive: Double
    var shiftTime: Double
    /// Drag coefficient × frontal area, m².
    var dragArea: Double
    /// Lift coefficient × area, m² (downforce).
    var downforceArea: Double
    /// Share of the downforce on the front axle.
    var aeroFront: Double = 0.45
    /// How much an aero upgrade adds on this car, against a hatchback's 1.
    var aeroScale: Double = 1
    /// All four brakes at full pedal, N·m.
    var brakeTorque: Double
    var brakeBias: Double
    /// Brake temperature where they start to fade, °C.
    var fadeStart: Double = 520
    var drive: CarProDrive
    /// Front share of the torque, for all-wheel drive.
    var frontDriveShare: Double = 0.4
    /// Limited-slip locking, 0 open … 1 locked.
    var diffLock: Double = 0
    /// Front share of the roll stiffness: more is safer (understeer).
    var rollFront: Double = 0.56
    /// The rear tyres' grip against the fronts': a size wider on the
    /// powerful rear-driven cars, as their makers fit them.
    var rearGrip: Double = 1.06
    var length: Double
    var width: Double
}

/// The six cars in the garage, cheapest first.
enum CarProCarModel: String, Codable, CaseIterable, Identifiable {
    case hatch
    case roadster
    case touring
    case rally
    case gt
    case prototype

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hatch: return "Pip Hatch"
        case .roadster: return "Swallow Roadster"
        case .touring: return "Kestrel Touring"
        case .rally: return "Storm AWD"
        case .gt: return "Meridian GT"
        case .prototype: return "Apex Prototype"
        }
    }

    /// One sentence for the showroom.
    var line: String {
        switch self {
        case .hatch: return "A nimble front-wheel-drive hatchback. Forgiving, light and cheap to run."
        case .roadster: return "Light, rear-driven and eager to turn. Feed the throttle out of corners."
        case .touring: return "A six-speed saloon with real power. Mind the rear on the way out of bends."
        case .rally: return "Turbocharged all-wheel drive. Fierce traction on any surface."
        case .gt: return "A front-engined grand tourer with downforce and a quick-shift box."
        case .prototype: return "A featherweight racer that sticks to the road with huge downforce."
        }
    }

    /// Showroom price; the hatch is the car a career starts with.
    var price: Int {
        switch self {
        case .hatch: return 4_000
        case .roadster: return 9_000
        case .touring: return 22_000
        case .rally: return 40_000
        case .gt: return 85_000
        case .prototype: return 190_000
        }
    }

    /// Upgrades cost this many times a hatchback's.
    var costFactor: Double {
        switch self {
        case .hatch: return 1.0
        case .roadster: return 1.4
        case .touring: return 1.9
        case .rally: return 2.5
        case .gt: return 3.6
        case .prototype: return 5.0
        }
    }

    /// The factory livery's hue, 0…1, for the drawing.
    var hue: Double {
        switch self {
        case .hatch: return 0.58
        case .roadster: return 0.0
        case .touring: return 0.12
        case .rally: return 0.33
        case .gt: return 0.75
        case .prototype: return 0.9
        }
    }

    var spec: CarProCarSpec {
        switch self {
        case .hatch:
            return CarProCarSpec(mass: 1080, frontWeight: 0.61, wheelbase: 2.55, trackWidth: 1.5, comHeight: 0.53,
                                 wheelRadius: 0.30, torqueRpm: 4200, redline: 6800, peakTorque: 172, engineInertia: 0.17,
                                 gears: [3.35, 2.05, 1.45, 1.12, 0.9], finalDrive: 4.06, shiftTime: 0.28,
                                 dragArea: 0.68, downforceArea: 0.0, brakeTorque: 3600, brakeBias: 0.72,
                                 fadeStart: 480, drive: .fwd, diffLock: 0, rollFront: 0.7, length: 4.0, width: 1.76)
        case .roadster:
            return CarProCarSpec(mass: 980, frontWeight: 0.51, wheelbase: 2.33, trackWidth: 1.48, comHeight: 0.46,
                                 torqueRpm: 4800, redline: 7500, peakTorque: 198, engineInertia: 0.15,
                                 gears: [3.14, 1.89, 1.33, 1.0, 0.81], finalDrive: 4.1, shiftTime: 0.24,
                                 dragArea: 0.62, downforceArea: 0.15, brakeTorque: 3900, brakeBias: 0.67,
                                 fadeStart: 500, drive: .rwd, diffLock: 0.2, rollFront: 0.63, length: 3.95, width: 1.72)
        case .touring:
            return CarProCarSpec(mass: 1320, frontWeight: 0.53, wheelbase: 2.75, trackWidth: 1.56, comHeight: 0.53,
                                 wheelRadius: 0.32, torqueRpm: 4500, redline: 7000, peakTorque: 330, engineInertia: 0.2,
                                 gears: [3.6, 2.19, 1.53, 1.18, 0.96, 0.8], finalDrive: 3.46, shiftTime: 0.22,
                                 dragArea: 0.66, downforceArea: 0.2, brakeTorque: 5400, brakeBias: 0.68,
                                 fadeStart: 520, drive: .rwd, diffLock: 0.25, rollFront: 0.64, length: 4.6, width: 1.82)
        case .rally:
            return CarProCarSpec(mass: 1380, frontWeight: 0.6, wheelbase: 2.6, trackWidth: 1.54, comHeight: 0.5,
                                 idleRpm: 950, torqueRpm: 3600, redline: 6900, peakTorque: 290, engineInertia: 0.19,
                                 turbo: 0.3, gears: [3.3, 2.1, 1.5, 1.15, 0.95, 0.8], finalDrive: 3.9, shiftTime: 0.2,
                                 dragArea: 0.7, downforceArea: 0.3, brakeTorque: 5800, brakeBias: 0.7,
                                 fadeStart: 540, drive: .awd, frontDriveShare: 0.45, diffLock: 0.35, rollFront: 0.62,
                                 length: 4.3, width: 1.8)
        case .gt:
            return CarProCarSpec(mass: 1420, frontWeight: 0.49, wheelbase: 2.65, trackWidth: 1.62, comHeight: 0.46,
                                 wheelRadius: 0.33, torqueRpm: 5000, redline: 7800, peakTorque: 560, engineInertia: 0.21,
                                 gears: [3.0, 2.05, 1.55, 1.24, 1.03, 0.86], finalDrive: 3.55, shiftTime: 0.14,
                                 dragArea: 0.72, downforceArea: 0.9, aeroFront: 0.42, aeroScale: 1.5,
                                 brakeTorque: 7600, brakeBias: 0.67, fadeStart: 600, drive: .rwd, diffLock: 0.35,
                                 rollFront: 0.62, rearGrip: 1.1, length: 4.55, width: 1.95)
        case .prototype:
            return CarProCarSpec(mass: 930, frontWeight: 0.45, wheelbase: 2.75, trackWidth: 1.65, comHeight: 0.32,
                                 wheelRadius: 0.33, idleRpm: 1500, torqueRpm: 6500, redline: 9000, peakTorque: 520,
                                 engineInertia: 0.1, gears: [2.8, 2.1, 1.68, 1.4, 1.2, 1.04], finalDrive: 3.6,
                                 shiftTime: 0.06, dragArea: 0.85, downforceArea: 3.6, aeroFront: 0.4, aeroScale: 2.2,
                                 brakeTorque: 8600, brakeBias: 0.66, fadeStart: 700, drive: .rwd, diffLock: 0.45,
                                 rollFront: 0.6, rearGrip: 1.12, length: 4.8, width: 2.0)
        }
    }

    /// The compound the factory fits, as a tyre-upgrade stage.
    var factoryTyreStage: Int {
        switch self {
        case .hatch, .roadster: return 0
        case .touring, .rally, .gt: return 1
        case .prototype: return 2
        }
    }
}

/// The stats a garage card shows as bars.
enum CarProStatKind: String, CaseIterable, Identifiable {
    case acceleration
    case topSpeed
    case grip
    case braking
    case handling

    var id: String { rawValue }

    var name: String {
        switch self {
        case .acceleration: return "Acceleration"
        case .topSpeed: return "Top speed"
        case .grip: return "Grip"
        case .braking: return "Braking"
        case .handling: return "Handling"
        }
    }
}

/// The nine upgrade lines. Every one has three stages to buy; tyres start at
/// the car's factory compound.
enum CarProUpgradeKind: String, Codable, CaseIterable, Identifiable {
    case engine
    case turbo
    case gearbox
    case tyres
    case brakes
    case suspension
    case weight
    case aero
    case differential

    var id: String { rawValue }

    static let maxStage = 3

    var name: String {
        switch self {
        case .engine: return "Engine"
        case .turbo: return "Turbo"
        case .gearbox: return "Gearbox"
        case .tyres: return "Tyres"
        case .brakes: return "Brakes"
        case .suspension: return "Suspension"
        case .weight: return "Weight reduction"
        case .aero: return "Aero"
        case .differential: return "Differential"
        }
    }

    /// What buying it does, one sentence.
    var blurb: String {
        switch self {
        case .engine: return "More torque all the way up the rev range, and a higher redline."
        case .turbo: return "Boost for a big punch of torque once it spools up. A little lag."
        case .gearbox: return "Closer ratios and quicker shifts keep the engine in its power band."
        case .tyres: return "Softer compounds grip harder but want heat and wear faster."
        case .brakes: return "Stronger brakes that fade later when they get hot."
        case .suspension: return "A lower, stiffer car leans less and rides kerbs better."
        case .weight: return "Lighter is quicker everywhere: accelerating, braking and turning."
        case .aero: return "Wings press the car down at speed for grip, at the cost of some drag."
        case .differential: return "A limited-slip diff stops the inside wheel spinning out of corners."
        }
    }

    /// An SF Symbol for the card.
    var symbol: String {
        switch self {
        case .engine: return "engine.combustion"
        case .turbo: return "fan"
        case .gearbox: return "gearshape.2"
        case .tyres: return "circle.circle"
        case .brakes: return "stop.circle"
        case .suspension: return "arrow.up.and.down"
        case .weight: return "scalemass"
        case .aero: return "wind"
        case .differential: return "arrow.triangle.branch"
        }
    }

    /// The stat it mainly moves.
    var primaryStat: CarProStatKind {
        switch self {
        case .engine, .turbo, .gearbox, .weight: return .acceleration
        case .tyres, .aero: return .grip
        case .brakes: return .braking
        case .suspension, .differential: return .handling
        }
    }

    /// The name of a stage, 0 being what the factory fits.
    func stageName(_ stage: Int) -> String {
        if self == .tyres { return CarProTyreCompound.allCases[min(max(stage, 0), 3)].name }
        switch stage {
        case 0: return self == .turbo ? "Factory" : (self == .differential ? "Factory diff" : "Stock")
        case 1: return "Street"
        case 2: return "Sport"
        default: return "Race"
        }
    }

    private var baseCost: Double {
        switch self {
        case .engine: return 700
        case .turbo: return 900
        case .gearbox: return 500
        case .tyres: return 400
        case .brakes: return 350
        case .suspension: return 450
        case .weight: return 600
        case .aero: return 500
        case .differential: return 400
        }
    }

    /// The price of stage `stage` (1…3) on `model`, to the nearest £50.
    func cost(stage: Int, model: CarProCarModel) -> Int {
        let steps: [Double] = [1, 1.8, 3.0]
        let index = min(max(stage, 1), 3) - 1
        let raw = baseCost * model.costFactor * steps[index]
        return Int((raw / 50).rounded()) * 50
    }
}

/// Which stage each upgrade line is at.
struct CarProUpgrades: Codable, Equatable {
    var engine = 0
    var turbo = 0
    var gearbox = 0
    var tyres = 0
    var brakes = 0
    var suspension = 0
    var weight = 0
    var aero = 0
    var differential = 0

    init() {}

    subscript(kind: CarProUpgradeKind) -> Int {
        get {
            switch kind {
            case .engine: return engine
            case .turbo: return turbo
            case .gearbox: return gearbox
            case .tyres: return tyres
            case .brakes: return brakes
            case .suspension: return suspension
            case .weight: return weight
            case .aero: return aero
            case .differential: return differential
            }
        }
        set {
            let v = min(max(newValue, 0), CarProUpgradeKind.maxStage)
            switch kind {
            case .engine: engine = v
            case .turbo: turbo = v
            case .gearbox: gearbox = v
            case .tyres: tyres = v
            case .brakes: brakes = v
            case .suspension: suspension = v
            case .weight: weight = v
            case .aero: aero = v
            case .differential: differential = v
            }
        }
    }

    /// A car as it leaves the showroom.
    static func factory(for model: CarProCarModel) -> CarProUpgrades {
        var u = CarProUpgrades()
        u.tyres = model.factoryTyreStage
        return u
    }

    /// Every line at its top stage.
    static var maxed: CarProUpgrades {
        var u = CarProUpgrades()
        for kind in CarProUpgradeKind.allCases { u[kind] = CarProUpgradeKind.maxStage }
        return u
    }

    /// Stages bought beyond the factory, for a "12 of 27" label.
    func bought(for model: CarProCarModel) -> Int {
        let factory = CarProUpgrades.factory(for: model)
        return CarProUpgradeKind.allCases.reduce(0) { $0 + self[$1] - factory[$1] }
    }
}

/// What a driver can set in the garage between races.
struct CarProTuning: Codable, Equatable {
    /// Share of braking on the front axle.
    var brakeBias: Double
    /// 0 a flat wing (less drag) … 1 steep (more downforce).
    var wing: Double
    /// Final drive against the factory's: above 1 is shorter (quicker, lower top speed).
    var finalDrive: Double

    static let brakeBiasRange: ClosedRange<Double> = 0.5...0.75
    static let wingRange: ClosedRange<Double> = 0...1
    static let finalDriveRange: ClosedRange<Double> = 0.9...1.1

    init(brakeBias: Double, wing: Double = 0.5, finalDrive: Double = 1) {
        self.brakeBias = brakeBias
        self.wing = wing
        self.finalDrive = finalDrive
    }

    static func factory(for model: CarProCarModel) -> CarProTuning {
        CarProTuning(brakeBias: model.spec.brakeBias)
    }

    /// Kept inside the ranges.
    var clamped: CarProTuning {
        CarProTuning(brakeBias: CarProMath.clamp(brakeBias, Self.brakeBiasRange.lowerBound, Self.brakeBiasRange.upperBound),
                     wing: CarProMath.clamp(wing, Self.wingRange.lowerBound, Self.wingRange.upperBound),
                     finalDrive: CarProMath.clamp(finalDrive, Self.finalDriveRange.lowerBound, Self.finalDriveRange.upperBound))
    }
}

/// One car as it will be driven: a model, its upgrades and its tuning.
struct CarProCarSetup: Codable, Equatable {
    var model: CarProCarModel
    var upgrades: CarProUpgrades
    var tuning: CarProTuning

    init(model: CarProCarModel, upgrades: CarProUpgrades? = nil, tuning: CarProTuning? = nil) {
        self.model = model
        self.upgrades = upgrades ?? CarProUpgrades.factory(for: model)
        self.tuning = (tuning ?? CarProTuning.factory(for: model)).clamped
    }

    var params: CarProVehicleParams { CarProVehicleParams(setup: self) }
    var stats: CarProCarStats { CarProCarStats(params: params) }

    /// The next stage of `kind`, or nil when it is at the top.
    func nextStage(_ kind: CarProUpgradeKind) -> Int? {
        let s = upgrades[kind]
        return s < CarProUpgradeKind.maxStage ? s + 1 : nil
    }

    /// The price of the next stage of `kind`, or nil when it is at the top.
    func upgradeCost(_ kind: CarProUpgradeKind) -> Int? {
        guard let stage = nextStage(kind) else { return nil }
        return kind.cost(stage: stage, model: model)
    }

    /// This car with the next stage of `kind` fitted (for the after-bars), or nil.
    func withUpgrade(_ kind: CarProUpgradeKind) -> CarProCarSetup? {
        guard let stage = nextStage(kind) else { return nil }
        var next = self
        next.upgrades[kind] = stage
        return next
    }
}

/// Everything the physics needs to know about one car, worked out once from
/// its setup.
struct CarProVehicleParams: Equatable {
    var model: CarProCarModel
    var mass: Double
    /// Yaw inertia, kg·m².
    var yawInertia: Double
    /// Centre of mass to front and rear axle, m.
    var toFront: Double
    var toRear: Double
    var trackWidth: Double
    var comHeight: Double
    var rollFront: Double
    var wheelRadius: Double
    var wheelInertia: Double
    var idleRpm: Double
    var torqueRpm: Double
    var redline: Double
    /// The rev limiter cuts in here.
    var limiter: Double
    var peakTorque: Double
    var engineInertia: Double
    var turboGain: Double
    /// Seconds for the turbo to spool most of the way.
    var turboLag: Double
    var gears: [Double]
    var reverseRatio: Double
    var finalDrive: Double
    var shiftTime: Double
    /// The engine holds about this speed while the clutch slips off the line.
    var launchRpm: Double
    var drive: CarProDrive
    var frontDriveShare: Double
    var diffLock: Double
    var brakeTorque: Double
    var brakeBias: Double
    var fadeStart: Double
    var dragArea: Double
    var downforceArea: Double
    var aeroFront: Double
    var compound: CarProTyreCompound
    var curve: CarProTyreCurve
    /// Grip from the suspension keeping the tyres flat, against 1.
    var gripBonus: Double
    /// The rear tyres' grip against the fronts'.
    var rearGrip: Double
    /// How much kerbs and bumps reach the tyres, against stock's 1.
    var bumpScale: Double
    /// Full steering lock at a standstill, radians.
    var maxLock: Double
    /// The body, for walls, other cars and drawing.
    var length: Double
    var width: Double
    /// Drivetrain efficiency.
    var efficiency: Double = 0.9

    static let airDensity = 1.225
    static let gravity = 9.81

    init(setup: CarProCarSetup) {
        let spec = setup.model.spec
        let u = setup.upgrades
        let t = setup.tuning.clamped
        model = setup.model
        let massScale = 1 - 0.045 * Double(u.weight)
        mass = spec.mass * massScale
        toFront = spec.wheelbase * (1 - spec.frontWeight)
        toRear = spec.wheelbase * spec.frontWeight
        yawInertia = mass * toFront * toRear * 1.05
        trackWidth = spec.trackWidth
        comHeight = spec.comHeight * (1 - 0.06 * Double(u.suspension))
        rollFront = spec.rollFront
        wheelRadius = spec.wheelRadius
        wheelInertia = 1.1
        idleRpm = spec.idleRpm
        torqueRpm = spec.torqueRpm
        redline = spec.redline + 300 * Double(u.engine)
        limiter = redline + 250
        peakTorque = spec.peakTorque * (1 + 0.09 * Double(u.engine))
        engineInertia = spec.engineInertia * (1 - 0.05 * Double(u.engine))
        turboGain = spec.turbo + 0.14 * Double(u.turbo)
        turboLag = 0.2 + 0.9 * turboGain
        // Closer ratios: every gear pulled towards top gear's.
        let top = spec.gears.last ?? 1
        let squeeze = 1 - 0.07 * Double(u.gearbox)
        gears = spec.gears.map { top * pow($0 / top, squeeze) }
        reverseRatio = -(spec.gears.first ?? 3.2) * 1.05
        finalDrive = spec.finalDrive * t.finalDrive
        shiftTime = spec.shiftTime * (1 - 0.18 * Double(u.gearbox))
        launchRpm = min(spec.redline * 0.62, spec.torqueRpm * 1.05)
        drive = spec.drive
        frontDriveShare = spec.frontDriveShare
        diffLock = spec.diffLock + (0.9 - spec.diffLock) * Double(u.differential) / 3
        brakeTorque = spec.brakeTorque * (1 + 0.13 * Double(u.brakes)) * massScale.squareRoot()
        brakeBias = t.brakeBias
        fadeStart = spec.fadeStart + 90 * Double(u.brakes)
        let wingDrag = spec.downforceArea > 0 || u.aero > 0 ? 0.94 + 0.12 * t.wing : 1
        let wingLift = spec.downforceArea > 0 || u.aero > 0 ? 0.7 + 0.6 * t.wing : 1
        dragArea = (spec.dragArea + 0.03 * Double(u.aero) * spec.aeroScale.squareRoot()) * wingDrag
        downforceArea = (spec.downforceArea + 0.42 * Double(u.aero) * spec.aeroScale) * wingLift
        aeroFront = spec.aeroFront
        compound = CarProTyreCompound.allCases[min(max(u.tyres, 0), 3)]
        curve = compound.curve
        gripBonus = 1 + 0.018 * Double(u.suspension)
        rearGrip = spec.rearGrip
        bumpScale = 1 - 0.22 * Double(u.suspension)
        maxLock = 0.62
        length = spec.length
        width = spec.width
    }

    var wheelbase: Double { toFront + toRear }
    var nominalLoad: Double { mass * Self.gravity / 4 }
    var topGear: Int { gears.count }

    /// The engine's torque curve, 0…1 of peak: rising from idle to the
    /// torque peak, easing off towards the redline and falling past it.
    func torqueShape(_ rpm: Double) -> Double {
        if rpm <= idleRpm { return 0.6 }
        if rpm < torqueRpm {
            let f = (rpm - idleRpm) / (torqueRpm - idleRpm)
            return 0.6 + 0.4 * sin(f * .pi / 2)
        }
        let f = (rpm - torqueRpm) / max(1, redline - torqueRpm)
        return max(0.2, 1 - 0.24 * f * f)
    }

    /// Torque at the crank, N·m, for `throttle` 0…1 and turbo `boost` 0…1.
    /// Off the throttle the engine brakes.
    func engineTorque(rpm: Double, throttle: Double, boost: Double) -> Double {
        let drive = peakTorque * torqueShape(rpm) * (1 + turboGain * boost) * throttle
        let braking = peakTorque * (0.06 + 0.12 * rpm / redline) * (1 - throttle)
        return drive - braking
    }

    /// Overall ratio in a gear (negative in reverse; 0 in neutral).
    func ratio(_ gear: Int) -> Double {
        if gear < 0 { return reverseRatio * finalDrive }
        if gear == 0 || gear > gears.count { return 0 }
        return gears[gear - 1] * finalDrive
    }

    /// Engine rpm at road speed `speed` in `gear`.
    func rpm(speed: Double, gear: Int) -> Double {
        abs(speed / wheelRadius * ratio(gear)) * 60 / (2 * .pi)
    }

    /// Road speed at the rev limiter in `gear`, m/s.
    func limiterSpeed(gear: Int) -> Double {
        let r = abs(ratio(gear))
        guard r > 0 else { return 0 }
        return limiter * 2 * .pi / 60 / r * wheelRadius
    }

    /// Peak power at the crank with full boost, W, and the rpm it comes at.
    var peakPower: (watts: Double, rpm: Double) {
        var best = (watts: 0.0, rpm: torqueRpm)
        var rpm = idleRpm
        while rpm <= redline {
            let w = peakTorque * torqueShape(rpm) * (1 + turboGain) * rpm * 2 * .pi / 60
            if w > best.watts { best = (w, rpm) }
            rpm += 100
        }
        return best
    }

    /// Air drag at speed, N.
    func drag(_ speed: Double) -> Double { 0.5 * Self.airDensity * dragArea * speed * speed }

    /// Downforce at speed, N.
    func downforce(_ speed: Double) -> Double { 0.5 * Self.airDensity * downforceArea * speed * speed }

    /// The drive force flat out in `gear` at `speed`, N (at the wheels).
    func driveForce(speed: Double, gear: Int) -> Double {
        let rpm = max(idleRpm, self.rpm(speed: speed, gear: gear))
        guard rpm <= limiter else { return 0 }
        return engineTorque(rpm: rpm, throttle: 1, boost: 1) * abs(ratio(gear)) * efficiency / wheelRadius
    }

    /// The best drive force at `speed` over all gears, N.
    func bestDriveForce(speed: Double) -> Double {
        var best = 0.0
        for g in 1...gears.count { best = max(best, driveForce(speed: speed, gear: g)) }
        return best
    }

    /// Where flat out stops gaining: the drive force in the best gear equals
    /// drag and rolling resistance. Capped by top gear's limiter.
    var topSpeed: Double {
        let rolling = mass * Self.gravity * CarProSurface.tarmac.rolling
        func net(_ v: Double) -> Double { bestDriveForce(speed: v) - drag(v) - rolling - 0.013 * downforce(v) }
        let cap = limiterSpeed(gear: gears.count)
        if net(cap - 0.01) > 0 { return cap }
        // Net force falls with speed near the top: halve the gap to it.
        var lo = 5.0, hi = cap
        for _ in 0..<32 {
            let mid = (lo + hi) / 2
            if net(mid) > 0 { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// Share of the car's weight on the driven wheels, for traction.
    var drivenWeight: Double {
        switch drive {
        case .fwd: return toRear / wheelbase
        case .rwd: return toFront / wheelbase
        case .awd: return 1
        }
    }
}

/// A car's numbers and bars for the garage, and its performance index.
struct CarProCarStats: Equatable {
    var power: Double
    var torque: Double
    var mass: Double
    var powerToWeight: Double
    var topSpeed: Double
    var lateralG: Double
    var braking: Double
    var shiftTime: Double
    var compound: CarProTyreCompound
    var drive: CarProDrive
    /// The bars, each 0…1.
    var acceleration: Double
    var speed: Double
    var grip: Double
    var stopping: Double
    var handling: Double
    var pi: Int

    init(params p: CarProVehicleParams) {
        let peak = p.peakPower
        power = peak.watts / 1000
        torque = p.peakTorque * (1 + p.turboGain)
        mass = p.mass
        powerToWeight = power / (p.mass / 1000)
        topSpeed = p.topSpeed
        let g = CarProVehicleParams.gravity
        let v = 40.0
        let aero = p.downforce(v) / (p.mass * g)
        lateralG = p.compound.mu * p.gripBonus * (1 + aero) * 0.96
        let brakeLimit = p.brakeTorque / (p.wheelRadius * p.mass)
        braking = min(brakeLimit, lateralG * 1.05 * g) + p.drag(v) / p.mass
        shiftTime = p.shiftTime
        compound = p.compound
        drive = p.drive

        // Acceleration: power to weight, taken off by slow shifts and wide
        // ratios, and helped by traction off the line.
        let spread = (p.gears.first ?? 1) / (p.gears.last ?? 1)
        let traction = (p.drive == .awd ? 1.06 : (p.drive == .rwd ? 0.97 : 0.92))
            * (1 + 0.06 * p.diffLock) * pow(p.compound.mu * p.gripBonus, 0.3)
        let effective = powerToWeight * (1 - 0.6 * p.shiftTime) * (1 + 0.6 / spread) * traction
        acceleration = CarProMath.clamp(log(effective / 55) / log(900.0 / 55), 0, 1)
        speed = CarProMath.clamp((topSpeed - 45) / 55, 0, 1)
        grip = CarProMath.clamp((lateralG - 0.8) / 1.5, 0, 1)
        let fade = CarProMath.clamp((p.fadeStart - 450) / 520, 0, 1)
        stopping = CarProMath.clamp(0.75 * (braking - 7) / 17 + 0.25 * fade, 0, 1)
        let lean = CarProMath.clamp((0.37 - p.comHeight / p.trackWidth) / 0.2, 0, 1)
        handling = CarProMath.clamp(0.45 * lean + 0.3 * p.diffLock + 0.25 * (1 - p.bumpScale) / 0.66, 0, 1)
        let score = 0.36 * acceleration + 0.25 * grip + 0.13 * stopping + 0.12 * speed + 0.14 * handling
        pi = Int(CarProMath.clamp(100 + 1000 * score, 100, 999).rounded())
    }

    /// A bar by kind.
    func value(_ kind: CarProStatKind) -> Double {
        switch kind {
        case .acceleration: return acceleration
        case .topSpeed: return speed
        case .grip: return grip
        case .braking: return stopping
        case .handling: return handling
        }
    }

    /// The PI class letter: D up to 300, C, B, A, S, then R from 901.
    var piClass: String { Self.piClass(pi) }

    static func piClass(_ pi: Int) -> String {
        switch pi {
        case ..<301: return "D"
        case ..<451: return "C"
        case ..<601: return "B"
        case ..<751: return "A"
        case ..<901: return "S"
        default: return "R"
        }
    }
}
