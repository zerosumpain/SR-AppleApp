import XCTest
@testable import SRAppleApp

/// Car Racer+ tyres, cars, upgrades and vehicle physics.
final class CarProPhysicsTests: XCTestCase {
    // MARK: - Tyres

    func testTyreCurvePeaksThenFalls() {
        for compound in CarProTyreCompound.allCases {
            let load = 4000.0
            let angles = stride(from: 0.0, through: 0.6, by: 0.005).map { $0 }
            let lateral = angles.map { CarProTyre.lateral(slipAngle: $0, load: load, compound: compound) }
            let peakIndex = lateral.indices.max { lateral[$0] < lateral[$1] }!
            let peakAngle = angles[peakIndex]
            XCTAssertEqual(peakAngle, compound.peakSlipAngle, accuracy: 0.02, compound.rawValue)
            XCTAssertEqual(lateral[peakIndex], compound.mu * load, accuracy: compound.mu * load * 0.02)
            // Rising to the peak, falling past it, and still gripping in a full slide.
            XCTAssertLessThan(lateral[peakIndex / 2], lateral[peakIndex])
            XCTAssertLessThan(lateral.last!, lateral[peakIndex] * 0.95)
            XCTAssertGreaterThan(lateral.last!, lateral[peakIndex] * 0.5)

            let ratios = stride(from: 0.0, through: 1.0, by: 0.005).map { $0 }
            let long = ratios.map { CarProTyre.longitudinal(slipRatio: $0, load: load, compound: compound) }
            let longPeak = long.indices.max { long[$0] < long[$1] }!
            XCTAssertEqual(ratios[longPeak], compound.peakSlipRatio, accuracy: 0.02)
            XCTAssertLessThan(long.last!, long[longPeak] * 0.95, "a locked or spinning tyre grips less")
            // Braking is the mirror of driving.
            XCTAssertEqual(CarProTyre.longitudinal(slipRatio: -0.1, load: load, compound: compound),
                           -CarProTyre.longitudinal(slipRatio: 0.1, load: load, compound: compound), accuracy: 1e-9)
        }
        // Softer compounds grip harder.
        let peaks = CarProTyreCompound.allCases.map {
            CarProTyre.lateral(slipAngle: $0.peakSlipAngle, load: 4000, compound: $0)
        }
        XCTAssertEqual(peaks, peaks.sorted())
    }

    func testCombinedSlipStaysInsideTheFrictionCircle() {
        let compound = CarProTyreCompound.sport
        let curve = compound.curve
        let load = 3500.0, mu = compound.mu
        for ratio in stride(from: -1.0, through: 1.0, by: 0.05) {
            for angle in stride(from: -0.8, through: 0.8, by: 0.05) {
                let f = CarProTyre.force(slipRatio: ratio, slipAngle: angle, load: load, mu: mu, compound: compound,
                                         curve: curve)
                let ellipse = pow(f.longitudinal / (mu * load * 1.05), 2) + pow(f.lateral / (mu * load), 2)
                XCTAssertLessThanOrEqual(ellipse, 1 + 1e-9)
            }
        }
        // Braking hard uses grip the corner wanted.
        let pure = CarProTyre.force(slipRatio: 0, slipAngle: 0.08, load: load, mu: mu, compound: compound, curve: curve)
        let braking = CarProTyre.force(slipRatio: -0.12, slipAngle: 0.08, load: load, mu: mu, compound: compound,
                                       curve: curve)
        XCTAssertLessThan(abs(braking.lateral), abs(pure.lateral))
        XCTAssertLessThan(pure.lateral, 0, "sliding right pushes the tyre left")
    }

    func testTyresGripBestInTheirWindowAndWearDown() {
        let slick = CarProTyreCompound.slick
        let best = CarProTyre.temperatureGrip(slick.optimalTemperature, compound: slick)
        XCTAssertEqual(best, 1, accuracy: 1e-9)
        XCTAssertLessThan(CarProTyre.temperatureGrip(30, compound: slick), best)
        XCTAssertLessThan(CarProTyre.temperatureGrip(160, compound: slick), best)
        XCTAssertGreaterThanOrEqual(CarProTyre.temperatureGrip(-20, compound: slick), 0.78)
        XCTAssertLessThan(CarProTyre.wearGrip(0.8), CarProTyre.wearGrip(0.1))
        // Load sensitivity: double the load, less than double the grip.
        XCTAssertLessThan(CarProTyre.loadGrip(6000, nominal: 3000), CarProTyre.loadGrip(3000, nominal: 3000))
        // Sliding heats a tyre; rolling slowly lets it cool.
        let hot = CarProTyre.heat(80, slipPower: 20000, load: 4000, speed: 30, ambient: 22, dt: 1)
        let cool = CarProTyre.heat(80, slipPower: 0, load: 4000, speed: 30, ambient: 22, dt: 1)
        XCTAssertGreaterThan(hot, 80)
        XCTAssertLessThan(cool, 80)
    }

    // MARK: - The car on open ground

    /// Drives `car` with `input` for `seconds` on open tarmac.
    private func drive(_ car: inout CarProVehicle, _ p: CarProVehicleParams, _ input: CarProInput, seconds: Double,
                       assists: CarProAssists = .full) {
        for _ in 0..<Int(seconds / CarProPhysics.dt) {
            CarProPhysics.step(&car, params: p, input: input, assists: assists, track: nil)
        }
    }

    func testBrakingMovesTheWeightForward() {
        let p = CarProCarSetup(model: .touring).params
        var car = CarProVehicle(params: p, position: .zero, heading: 0, speed: 35)
        drive(&car, p, CarProInput(throttle: 0.2), seconds: 1)
        let frontCruising = car.wheels[0].load + car.wheels[1].load
        let rearCruising = car.wheels[2].load + car.wheels[3].load
        drive(&car, p, CarProInput(brake: 1), seconds: 0.6)
        let front = car.wheels[0].load + car.wheels[1].load
        let rear = car.wheels[2].load + car.wheels[3].load
        XCTAssertGreaterThan(front, frontCruising * 1.15)
        XCTAssertLessThan(rear, rearCruising * 0.85)
        XCTAssertLessThan(car.accelForward, -6, "hard braking")
        // Total weight is conserved (no downforce on this car to speak of).
        XCTAssertEqual(front + rear, frontCruising + rearCruising, accuracy: (front + rear) * 0.05)
        // Turning right throws weight onto the left wheels.
        var turning = CarProVehicle(params: p, position: .zero, heading: 0, speed: 20)
        drive(&turning, p, CarProInput(throttle: 0.3, steer: 0.6), seconds: 1.5)
        XCTAssertGreaterThan(turning.yawRate, 0.3)
        XCTAssertGreaterThan(turning.wheels[0].load, turning.wheels[1].load)
        XCTAssertGreaterThan(turning.wheels[2].load, turning.wheels[3].load)
    }

    func testTopSpeedInEachGearMatchesGearingAndDrag() {
        for model in [CarProCarModel.hatch, .gt] {
            let p = CarProCarSetup(model: model).params
            // Held in second (manual, no shifting) it runs into the limiter.
            var car = CarProVehicle(params: p, position: .zero, heading: 0, speed: 8)
            var manual = CarProAssists.full
            manual.autoGears = false
            while car.gear < 2 {
                CarProPhysics.step(&car, params: p, input: CarProInput(throttle: 1, shiftUp: car.gear < 2 && car.shiftTimer == 0),
                                   assists: manual, track: nil)
            }
            drive(&car, p, CarProInput(throttle: 1), seconds: 12, assists: manual)
            XCTAssertEqual(car.gear, 2)
            XCTAssertEqual(car.forwardSpeed, p.limiterSpeed(gear: 2), accuracy: p.limiterSpeed(gear: 2) * 0.03, model.rawValue)
            XCTAssertGreaterThan(car.rpm, p.redline)
            // The automatic box, flat out for a long while: drag sets the top speed.
            var flat = CarProVehicle(params: p, position: .zero, heading: 0, speed: 20)
            drive(&flat, p, CarProInput(throttle: 1), seconds: 70)
            XCTAssertEqual(flat.forwardSpeed, p.topSpeed, accuracy: p.topSpeed * 0.03, model.rawValue)
            XCTAssertGreaterThanOrEqual(flat.gear, p.topGear - 1)
        }
        // Each gear's limit is the redline speed of its ratio, rising gear by gear.
        let p = CarProCarSetup(model: .touring).params
        let limits = (1...p.topGear).map { p.limiterSpeed(gear: $0) }
        XCTAssertEqual(limits, limits.sorted())
        XCTAssertEqual(limits[0], p.limiter * 2 * .pi / 60 * p.wheelRadius / (p.gears[0] * p.finalDrive), accuracy: 1e-9)
    }

    func testEngineHasACurveARedlineAndALimiter() {
        let p = CarProCarSetup(model: .roadster).params
        XCTAssertLessThan(p.torqueShape(p.idleRpm), 1)
        XCTAssertEqual(p.torqueShape(p.torqueRpm), 1, accuracy: 1e-9)
        XCTAssertLessThan(p.torqueShape(p.redline), 1)
        XCTAssertLessThan(p.engineTorque(rpm: 4000, throttle: 0, boost: 0), 0, "off the throttle the engine brakes")
        XCTAssertGreaterThan(p.limiter, p.redline)
        // A turbo adds torque once it has spooled.
        let turbo = CarProCarSetup(model: .rally).params
        XCTAssertGreaterThan(turbo.engineTorque(rpm: 4500, throttle: 1, boost: 1),
                             turbo.engineTorque(rpm: 4500, throttle: 1, boost: 0) * 1.2)
    }

    func testABSStopsTheWheelsLockingAndTractionControlStopsThemSpinning() {
        let p = CarProCarSetup(model: .gt).params
        var noAids = CarProAssists.none
        noAids.autoGears = true
        var locked = CarProVehicle(params: p, position: .zero, heading: 0, speed: 40)
        drive(&locked, p, CarProInput(brake: 1), seconds: 0.5, assists: noAids)
        XCTAssertTrue(locked.wheels[0].locked, "full brakes without ABS lock the fronts")
        var abs = CarProVehicle(params: p, position: .zero, heading: 0, speed: 40)
        drive(&abs, p, CarProInput(brake: 1), seconds: 0.5)
        XCTAssertFalse(abs.wheels.contains { $0.locked })
        XCTAssertLessThan(abs.forwardSpeed, locked.forwardSpeed, "and stops harder for it")

        // Flat out from a standstill: the rear tyres spin up without traction control.
        func launch(_ assists: CarProAssists) -> (spin: Double, speed: Double) {
            var car = CarProVehicle(params: p, position: .zero, heading: 0)
            var most = 0.0
            for _ in 0..<360 {
                CarProPhysics.step(&car, params: p, input: CarProInput(throttle: 1), assists: assists, track: nil)
                most = max(most, car.wheels[2].slipRatio, car.wheels[3].slipRatio)
            }
            return (most, car.forwardSpeed)
        }
        let spin = launch(noAids), tc = launch(.full)
        XCTAssertGreaterThan(spin.spin, p.compound.peakSlipRatio * 2)
        XCTAssertLessThan(tc.spin, spin.spin)
        XCTAssertGreaterThan(tc.speed, spin.speed * 0.95)
    }

    func testHoldingTheBrakeAtAStandstillReverses() {
        let p = CarProCarSetup(model: .hatch).params
        var car = CarProVehicle(params: p, position: .zero, heading: 0)
        drive(&car, p, CarProInput(brake: 1), seconds: 2.5)
        XCTAssertEqual(car.gear, -1)
        XCTAssertLessThan(car.forwardSpeed, -1, "the brake pedal now drives it backwards")
        drive(&car, p, CarProInput(throttle: 1), seconds: 3)
        XCTAssertGreaterThan(car.gear, 0)
        XCTAssertGreaterThan(car.forwardSpeed, 1)
    }

    func testPhysicsIsDeterministic() {
        let p = CarProCarSetup(model: .rally).params
        func run() -> CarProVehicle {
            var car = CarProVehicle(params: p, position: CarProVec(x: 3, y: -2), heading: 0.4, speed: 12)
            for step in 0..<2400 {
                let t = Double(step) * CarProPhysics.dt
                let input = CarProInput(throttle: step % 700 < 500 ? 1 : 0, brake: step % 700 >= 500 ? 0.8 : 0,
                                        steer: sin(t * 1.3) * 0.8)
                CarProPhysics.step(&car, params: p, input: input, assists: .full, track: CarProCircuits.all[0])
            }
            return car
        }
        XCTAssertEqual(run(), run())
        // A frame of any length is the same whole substeps.
        var clock = CarProStepClock()
        XCTAssertEqual((0..<60).reduce(0) { total, _ in total + clock.substeps(for: 1.0 / 60) }, 240)
        var slow = CarProStepClock()
        XCTAssertEqual(slow.substeps(for: 0.5), 24, "a long hitch is cut to a tenth of a second")
    }

    // MARK: - Upgrades and PI

    func testUpgradesImproveTheirStatAndPIAndCostMoney() {
        for model in CarProCarModel.allCases {
            for kind in CarProUpgradeKind.allCases {
                var setup = CarProCarSetup(model: model)
                var lastCost = 0
                while let next = setup.withUpgrade(kind) {
                    let before = setup.stats, after = next.stats
                    XCTAssertGreaterThan(after.pi, before.pi, "\(model) \(kind) stage \(next.upgrades[kind])")
                    XCTAssertGreaterThan(after.value(kind.primaryStat), before.value(kind.primaryStat),
                                         "\(model) \(kind) moves \(kind.primaryStat)")
                    let cost = setup.upgradeCost(kind)!
                    XCTAssertGreaterThan(cost, lastCost, "later stages cost more")
                    lastCost = cost
                    setup = next
                }
                XCTAssertEqual(setup.upgrades[kind], CarProUpgradeKind.maxStage)
                XCTAssertNil(setup.upgradeCost(kind))
            }
            XCTAssertLessThanOrEqual(CarProCarSetup(model: model, upgrades: .maxed).stats.pi, 999)
        }
        // Dearer cars cost more to upgrade, and score higher stock.
        let stock = CarProCarModel.allCases.map { CarProCarSetup(model: $0).stats.pi }
        XCTAssertEqual(stock, stock.sorted())
        XCTAssertEqual(CarProCarModel.allCases.map(\.price), CarProCarModel.allCases.map(\.price).sorted())
        XCTAssertLessThan(CarProUpgradeKind.engine.cost(stage: 1, model: .hatch),
                          CarProUpgradeKind.engine.cost(stage: 1, model: .prototype))
    }

    func testEveryCarHasAPlaceAndTheUpgradeLinesAreComplete() {
        XCTAssertEqual(CarProCarModel.allCases.count, 6)
        XCTAssertEqual(Set(CarProCarModel.allCases.map(\.spec.drive)), [.fwd, .rwd, .awd])
        XCTAssertEqual(CarProUpgradeKind.allCases.count, 9)
        XCTAssertEqual(CarProUpgradeKind.tyres.stageName(0), "Road")
        XCTAssertEqual(CarProUpgradeKind.tyres.stageName(3), "Slick")
        XCTAssertEqual(CarProCarSetup(model: .prototype).params.compound, .semiSlick)
        // Tuning stays in range and changes the car.
        let wild = CarProTuning(brakeBias: 2, wing: -1, finalDrive: 9).clamped
        XCTAssertEqual(wild.brakeBias, CarProTuning.brakeBiasRange.upperBound)
        XCTAssertEqual(wild.wing, 0)
        XCTAssertEqual(wild.finalDrive, CarProTuning.finalDriveRange.upperBound)
        let flat = CarProCarSetup(model: .gt, tuning: CarProTuning(brakeBias: 0.65, wing: 0)).params
        let steep = CarProCarSetup(model: .gt, tuning: CarProTuning(brakeBias: 0.65, wing: 1)).params
        XCTAssertGreaterThan(steep.downforceArea, flat.downforceArea)
        XCTAssertGreaterThan(steep.dragArea, flat.dragArea)
        let short = CarProCarSetup(model: .gt, tuning: CarProTuning(brakeBias: 0.65, finalDrive: 1.1)).params
        XCTAssertLessThan(short.limiterSpeed(gear: short.topGear), flat.limiterSpeed(gear: flat.topGear))
        XCTAssertEqual(CarProCarStats.piClass(250), "D")
        XCTAssertEqual(CarProCarStats.piClass(999), "R")
    }
}
