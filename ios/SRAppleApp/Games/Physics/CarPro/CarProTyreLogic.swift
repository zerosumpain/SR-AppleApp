import Foundation

// Car Racer+ tyres: a simplified Pacejka "magic formula" for the force a tyre
// makes against how much it slips, combined sideways and lengthways in one
// friction circle, with grip that depends on load, temperature and wear.

/// The four tyre compounds, softest last: each grips harder, peaks at a
/// smaller slip, lets go more sharply, and wants more heat to work.
enum CarProTyreCompound: String, Codable, CaseIterable, Identifiable {
    case road
    case sport
    case semiSlick
    case slick

    var id: String { rawValue }

    var name: String {
        switch self {
        case .road: return "Road"
        case .sport: return "Sport"
        case .semiSlick: return "Semi-slick"
        case .slick: return "Slick"
        }
    }

    /// Peak friction coefficient on dry tarmac in its window.
    var mu: Double {
        switch self {
        case .road: return 1.0
        case .sport: return 1.1
        case .semiSlick: return 1.22
        case .slick: return 1.36
        }
    }

    /// Slip angle at the lateral peak, radians.
    var peakSlipAngle: Double {
        switch self {
        case .road: return 0.15
        case .sport: return 0.13
        case .semiSlick: return 0.115
        case .slick: return 0.10
        }
    }

    /// Slip ratio at the longitudinal peak.
    var peakSlipRatio: Double {
        switch self {
        case .road: return 0.14
        case .sport: return 0.125
        case .semiSlick: return 0.11
        case .slick: return 0.10
        }
    }

    /// The magic formula's shape factor C: how far the force falls past the
    /// peak (sin(C·π/2) of it is left at a full slide).
    var shape: Double {
        switch self {
        case .road: return 1.38
        case .sport: return 1.45
        case .semiSlick: return 1.52
        case .slick: return 1.6
        }
    }

    /// The temperature it grips best at, °C, and the half-width of its window.
    var optimalTemperature: Double {
        switch self {
        case .road: return 62
        case .sport: return 75
        case .semiSlick: return 86
        case .slick: return 96
        }
    }

    var window: Double {
        switch self {
        case .road: return 46
        case .sport: return 38
        case .semiSlick: return 31
        case .slick: return 26
        }
    }

    /// How quickly it wears, against road's 1.
    var wearRate: Double {
        switch self {
        case .road: return 0.7
        case .sport: return 1.0
        case .semiSlick: return 1.35
        case .slick: return 1.8
        }
    }

    /// The temperature a set starts a race at (warmed on the formation lap).
    var startTemperature: Double { optimalTemperature - window * 0.55 }

    /// The shape of its force curve.
    var curve: CarProTyreCurve { CarProTyreCurve(shape: shape) }
}

/// A magic-formula curve normalised so the peak is 1 at a slip of 1:
/// f(s) = sin(C · atan(B · s)), with B = tan(π / 2C).
struct CarProTyreCurve: Equatable {
    let shape: Double
    let stiffness: Double

    init(shape: Double) {
        self.shape = shape
        stiffness = tan(Double.pi / (2 * shape))
    }

    /// The force, 0…1, at a normalised slip `s` ≥ 0.
    func value(_ s: Double) -> Double { sin(shape * atan(stiffness * s)) }

    /// The slope at no slip: f'(0) = B · C.
    var initialSlope: Double { stiffness * shape }

    /// f(s) / s: the secant slope, finite at 0.
    func secant(_ s: Double) -> Double { s < 1e-6 ? initialSlope : value(s) / s }
}

/// What one tyre does this instant.
struct CarProTyreForce: Equatable {
    /// Along the wheel, N (positive drives forward).
    var longitudinal: Double
    /// Across the wheel, N (positive pushes to the wheel's right).
    var lateral: Double
    /// d(longitudinal)/d(slip ratio) through the origin (the secant), N:
    /// for the wheel's implicit spin step.
    var slipStiffness: Double
    /// Combined normalised slip; past 1 the tyre is sliding.
    var combinedSlip: Double
}

enum CarProTyre {
    /// Below this the slips are measured against it instead of the wheel's
    /// own speed, so a car at a standstill does not see a huge slip from a
    /// millimetre a second.
    static let slipFloorSpeed: Double = 2.5

    /// Combined slip: the slip ratio and slip angle each measured against
    /// their peak, the force read off one curve at their combined length and
    /// shared out between the two directions in proportion. The result never
    /// leaves the friction circle (ellipse, with `muX` and `muY`).
    static func force(slipRatio: Double, slipAngle: Double, load: Double, mu: Double,
                      compound: CarProTyreCompound, curve: CarProTyreCurve) -> CarProTyreForce {
        guard load > 0 else { return CarProTyreForce(longitudinal: 0, lateral: 0, slipStiffness: 0, combinedSlip: 0) }
        let sx = slipRatio / compound.peakSlipRatio
        let sy = tan(CarProMath.clamp(slipAngle, -1.5, 1.5)) / tan(compound.peakSlipAngle)
        let s = (sx * sx + sy * sy).squareRoot()
        let peak = mu * load
        let secant = curve.secant(s)
        // Lengthways a tyre grips a little harder than sideways.
        let fx = peak * 1.05 * secant * sx
        let fy = -peak * secant * sy
        return CarProTyreForce(longitudinal: fx, lateral: fy,
                               slipStiffness: peak * 1.05 * secant / compound.peakSlipRatio, combinedSlip: s)
    }

    /// Pure sideways force magnitude at a slip angle (no slip ratio), N.
    static func lateral(slipAngle: Double, load: Double, compound: CarProTyreCompound) -> Double {
        -force(slipRatio: 0, slipAngle: slipAngle, load: load, mu: compound.mu,
               compound: compound, curve: compound.curve).lateral
    }

    /// Pure lengthways force at a slip ratio (no slip angle), N.
    static func longitudinal(slipRatio: Double, load: Double, compound: CarProTyreCompound) -> Double {
        force(slipRatio: slipRatio, slipAngle: 0, load: load, mu: compound.mu,
              compound: compound, curve: compound.curve).longitudinal
    }

    /// Grip against the best, 0.78…1, from the tyre's temperature: a
    /// parabola across the compound's window, floored either side.
    static func temperatureGrip(_ temperature: Double, compound: CarProTyreCompound) -> Double {
        let off = (temperature - compound.optimalTemperature) / compound.window
        return max(0.78, 1 - 0.17 * off * off)
    }

    /// Grip against new, from wear 0 (new) … 1 (finished).
    static func wearGrip(_ wear: Double) -> Double { 1 - 0.22 * CarProMath.clamp(wear, 0, 1) }

    /// Load sensitivity: a tyre pressed harder grips a little less per newton,
    /// which is why weight moving across the car costs grip overall.
    static func loadGrip(_ load: Double, nominal: Double) -> Double {
        guard nominal > 0 else { return 1 }
        return CarProMath.clamp(1 - 0.08 * (load / nominal - 1), 0.75, 1.12)
    }

    /// Surface heat in from sliding power and rolling, out to the air faster
    /// with speed. Returns the new temperature.
    static func heat(_ temperature: Double, slipPower: Double, load: Double, speed: Double,
                     ambient: Double, dt: Double) -> Double {
        // A tread's surface holds about 900 J per degree; rolling flexes it
        // a little, sliding works it hard, and a tread near 200 °C takes no
        // more heat in.
        let input = (slipPower + load * speed * 0.0035) / 900 * CarProMath.clamp(1 - (temperature - ambient) / 180, 0, 1)
        let cooling = (temperature - ambient) * (0.018 + 0.0016 * speed)
        return temperature + (input - cooling) * dt
    }

    /// Wear from sliding work, J → share of the tread.
    static func wear(_ wear: Double, slipPower: Double, compound: CarProTyreCompound, dt: Double) -> Double {
        min(1, wear + slipPower * compound.wearRate * 1.2e-7 * dt)
    }
}
