import SwiftUI
import SceneKit
import UIKit

/// Lander's 3D world: the flight from `LanderLogic` drawn in SceneKit.
///
/// The flight is flat (x across, y up), so the world is built around it: the
/// ground's height map extruded into a ridge thirty metres deep, its face
/// shaded in strata (a bright lit rim, darker rock below, speckled with
/// craters), boulders on top, two paler ridges behind it for distance, the
/// pad lit at both ends with a chase of runway lights and a beacon above it,
/// a starfield with the Milky Way and the Earth low in the sky. A perspective
/// camera follows the craft and pulls back with altitude, so the climb-down
/// reads as depth rather than a scroll.
///
/// The engine burns as particles (a hot core and a trail of smoke), the
/// exhaust kicks up dust when it is close to the ground, a touchdown puffs a
/// ring of dust (and a gentle one sets off flares from the pad's masts), and
/// a crash is a flash, a fireball, smoke, sparks, tumbling debris, a scorch
/// mark and a camera shake.
///
/// Nothing here decides anything. `update(_:)` is called once a frame on the
/// main thread with the flight as the rules left it; SceneKit renders on its
/// own thread and picks the new positions up on its next frame.
@MainActor
final class LanderSceneController {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// The camera's mount: the follow moves the rig, a shake moves the camera on it.
    private let rig = SCNNode()
    private let craft = SCNNode()
    private let flameHolder = SCNNode()
    private let flameLight = SCNLight()
    private let shadow = SCNNode()
    private let exhaust: SCNParticleSystem
    private let exhaustSmoke: SCNParticleSystem
    private let dustNode = SCNNode()
    private let dust: SCNParticleSystem
    private var world = SCNNode()
    private var beacon: SCNNode?
    private var terrain: LanderTerrain?
    private var cameraAt = SCNVector3(0, 0, 0)
    private var exploded = false
    private var touchedDown = false

    private let silver: SCNMaterial
    private let gold: SCNMaterial
    private let dark: SCNMaterial

    init() {
        silver = Self.material(UIColor(white: 0.85, alpha: 1), metal: 0.8, rough: 0.35)
        gold = Self.material(UIColor(red: 0.85, green: 0.65, blue: 0.22, alpha: 1), metal: 0.9, rough: 0.4)
        dark = Self.material(UIColor(white: 0.25, alpha: 1), metal: 0.5, rough: 0.6)
        exhaust = Self.flameParticles()
        exhaustSmoke = Self.smokeParticles()
        dust = Self.dustParticles()
        scene.background.contents = Self.starfield()
        buildLights()
        buildCraft()
        buildShadow()
        let camera = SCNCamera()
        camera.fieldOfView = 62
        camera.projectionDirection = .horizontal
        camera.zNear = 1
        camera.zFar = 3000
        cameraNode.camera = camera
        rig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(rig)
        scene.rootNode.addChildNode(world)
        dustNode.addParticleSystem(dust)
        scene.rootNode.addChildNode(dustNode)
    }

    /// Pause or resume everything that moves by itself: particles, the pad's
    /// lamps, a crash still burning.
    func setPaused(_ paused: Bool) {
        scene.isPaused = paused
    }

    /// A new level's ground: the old ridge goes, the new one is built.
    func load(_ terrain: LanderTerrain) {
        guard terrain != self.terrain else { return }
        self.terrain = terrain
        world.removeFromParentNode()
        world = SCNNode()
        scene.rootNode.addChildNode(world)
        // Two ridges behind, paler and higher, for distance.
        for layer in [2, 1] {
            let k = Double(layer)
            let heights = terrain.heights.enumerated().map { i, h in
                h * 0.7 + 30 * k + 18 * sin(Double(i) * 0.21 * k + k)
            }
            let ridge = Self.ridge(heights: heights, step: terrain.step * (1 + 0.5 * k), depth: 40,
                                   colour: UIColor(red: 0.30 - 0.08 * CGFloat(k), green: 0.30 - 0.08 * CGFloat(k),
                                                   blue: 0.36 - 0.08 * CGFloat(k), alpha: 1))
            ridge.position = SCNVector3(Float(-terrain.width * 0.25 * k), 0, Float(-70 * k))
            world.addChildNode(ridge)
        }
        world.addChildNode(Self.ridge(heights: terrain.heights, step: terrain.step, depth: 30,
                                      colour: UIColor(red: 0.62, green: 0.60, blue: 0.57, alpha: 1)))
        // The face towards the camera, shaded by hand, just in front of the ridge's own.
        world.addChildNode(Self.face(terrain, z: 15.05))
        world.addChildNode(Self.boulders(terrain))
        world.addChildNode(Self.pad(terrain))
        let beacon = Self.beacon(terrain)
        world.addChildNode(beacon)
        self.beacon = beacon
        world.addChildNode(Self.earth(x: terrain.width * 0.7))
        resetEffects()
    }

    /// Put everything where the flight says, once a frame.
    func update(_ flight: LanderFlight) {
        load(flight.terrain)
        let c = flight.craft
        craft.position = SCNVector3(Float(c.x), Float(c.y), 0)
        // A lean to the right is clockwise seen from the camera: negative about z.
        craft.eulerAngles = SCNVector3(0, 0, Float(-c.angle))
        let burn = Float(max(0, min(1, c.burning)))
        flameHolder.isHidden = burn <= 0.01
        flameHolder.scale = SCNVector3(1, 0.35 + 0.65 * burn + Float.random(in: 0...0.12) * burn, 1)
        flameLight.intensity = CGFloat(burn) * (800 + CGFloat.random(in: 0...200))
        exhaust.birthRate = CGFloat(burn) * 320
        exhaustSmoke.birthRate = CGFloat(burn) * 60

        // The craft's shadow on the ground under it, fainter and wider as it climbs.
        let ground = flight.terrain.height(at: c.x)
        let height = max(0, c.y - LanderRules.footDrop - ground)
        shadow.position = SCNVector3(Float(c.x), Float(ground + 0.08), 0)
        let spread = Float(1 + height / 25)
        shadow.scale = SCNVector3(spread, spread, 1)
        shadow.opacity = CGFloat(max(0, 0.45 - height / 160))

        // Dust thrown up by the exhaust when the engine is close to the ground.
        let near = max(0, 1 - height / 14)
        dustNode.position = SCNVector3(Float(c.x), Float(ground + 0.3), 0)
        dust.birthRate = CGFloat(Double(burn) * near * 240)

        // The beacon over the pad fades as the craft comes down to it.
        if let beacon {
            let above = c.y - flight.terrain.padHeight
            beacon.opacity = CGFloat(min(1, max(0, (above - 12) / 50)))
        }

        switch flight.outcome {
        case .flying:
            if exploded || touchedDown { resetEffects() }
        case .crashed:
            if !exploded {
                exploded = true
                exhaust.birthRate = 0
                exhaustSmoke.birthRate = 0
                dust.birthRate = 0
                explode(at: craft.position, terrain: flight.terrain)
                craft.isHidden = true
                flameHolder.isHidden = true
            }
        case .landed(let landing):
            if !touchedDown {
                touchedDown = true
                exhaust.birthRate = 0
                exhaustSmoke.birthRate = 0
                dust.birthRate = 0
                touchdown(at: SCNVector3(Float(c.x), Float(ground + 0.2), 0), terrain: flight.terrain, gentle: landing.gentle)
            }
        }

        // Follow the craft, further back the higher it is, looking a little
        // ahead of where it is going, and rolling a touch with its lean.
        let back = Float(min(max(38 + height * 0.65, 38), 150))
        let lead = Float(max(-12, min(12, c.vx * 0.5)))
        let target = SCNVector3(Float(c.x) + lead, Float(c.y) + 6 + back * 0.08, back)
        let ease: Float = cameraAt.z == 0 ? 1 : 0.12
        cameraAt = SCNVector3(cameraAt.x + (target.x - cameraAt.x) * ease,
                              cameraAt.y + (target.y - cameraAt.y) * ease,
                              cameraAt.z + (target.z - cameraAt.z) * ease)
        rig.position = cameraAt
        rig.eulerAngles = SCNVector3(-0.16, 0, Float(-c.angle) * 0.06)
    }

    /// A new flight: the craft back, the camera steady, the one-off effects forgotten.
    private func resetEffects() {
        exploded = false
        touchedDown = false
        craft.isHidden = false
        // Another go over the same ground (the demo flies one seed): the last
        // crash's debris, scorch and smoke go with it.
        for node in world.childNodes where node.name == Self.effectName {
            node.removeAllActions()
            node.removeFromParentNode()
        }
        cameraNode.removeAllActions()
        cameraNode.position = SCNVector3(0, 0, 0)
    }

    /// The name every one-off effect node carries, so a new flight can clear them.
    private static let effectName = "lander-effect"

    // MARK: - Building

    private func buildLights() {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.color = UIColor(white: 1, alpha: 1)
        sun.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 220
        fill.light?.color = UIColor(red: 0.55, green: 0.6, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(fill)
    }

    private func buildCraft() {
        let cabin = SCNNode(geometry: SCNSphere(radius: 1.0))
        cabin.geometry?.materials = [silver]
        cabin.position = SCNVector3(0, 0.55, 0)
        craft.addChildNode(cabin)
        let window = SCNNode(geometry: SCNSphere(radius: 0.32))
        window.geometry?.materials = [Self.glow(UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1))]
        window.position = SCNVector3(0, 0.7, 0.85)
        craft.addChildNode(window)
        // A red light on top, blinking, so the craft is easy to spot against the stars.
        let tip = SCNNode(geometry: SCNSphere(radius: 0.16))
        tip.geometry?.materials = [Self.glow(UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1))]
        tip.position = SCNVector3(0, 1.62, 0)
        tip.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.08), .wait(duration: 0.5),
                                                .fadeOpacity(to: 0.15, duration: 0.25), .wait(duration: 0.4)])))
        craft.addChildNode(tip)
        let mast = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 0.5))
        mast.geometry?.materials = [dark]
        mast.position = SCNVector3(0, 1.4, 0)
        craft.addChildNode(mast)
        let stage = SCNNode(geometry: SCNBox(width: 2.4, height: 1.0, length: 2.4, chamferRadius: 0.15))
        stage.geometry?.materials = [gold]
        stage.position = SCNVector3(0, -0.55, 0)
        craft.addChildNode(stage)
        for (dx, dz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 1.9))
            leg.geometry?.materials = [dark]
            leg.position = SCNVector3(Float(dx * 1.5), -1.35, Float(dz * 1.5))
            leg.eulerAngles = SCNVector3(Float(-dz * 0.45), 0, Float(dx * 0.45))
            craft.addChildNode(leg)
            let foot = SCNNode(geometry: SCNCylinder(radius: 0.32, height: 0.1))
            foot.geometry?.materials = [dark]
            foot.position = SCNVector3(Float(dx * 1.95), Float(-LanderRules.footDrop + 0.05), Float(dz * 1.95))
            craft.addChildNode(foot)
        }
        // The flame hangs from the nozzle; scaling the holder stretches it downwards.
        let nozzle = SCNNode(geometry: SCNCone(topRadius: 0.25, bottomRadius: 0.55, height: 0.5))
        nozzle.geometry?.materials = [dark]
        nozzle.position = SCNVector3(0, -1.25, 0)
        craft.addChildNode(nozzle)
        flameHolder.position = SCNVector3(0, -1.5, 0)
        let flame = SCNNode(geometry: SCNCone(topRadius: 0.5, bottomRadius: 0, height: 3.2))
        let fire = Self.glow(UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 0.9))
        fire.blendMode = .add
        flame.geometry?.materials = [fire]
        flame.position = SCNVector3(0, -1.6, 0)
        flameHolder.addChildNode(flame)
        let core = SCNNode(geometry: SCNCone(topRadius: 0.28, bottomRadius: 0, height: 1.8))
        let hot = Self.glow(UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.95))
        hot.blendMode = .add
        core.geometry?.materials = [hot]
        core.position = SCNVector3(0, -0.9, 0)
        flameHolder.addChildNode(core)
        flameLight.type = .omni
        flameLight.color = UIColor(red: 1, green: 0.6, blue: 0.25, alpha: 1)
        flameLight.attenuationEndDistance = 30
        flameLight.intensity = 0
        let lightNode = SCNNode()
        lightNode.light = flameLight
        lightNode.position = SCNVector3(0, -3, 0)
        flameHolder.addChildNode(lightNode)
        flameHolder.isHidden = true
        craft.addChildNode(flameHolder)
        // The exhaust's particles leave from the nozzle but live in the
        // world, so a moving craft draws a trail.
        let emitter = SCNNode()
        emitter.position = SCNVector3(0, -1.6, 0)
        emitter.addParticleSystem(exhaust)
        emitter.addParticleSystem(exhaustSmoke)
        craft.addChildNode(emitter)
        scene.rootNode.addChildNode(craft)
    }

    private func buildShadow() {
        let plane = SCNPlane(width: 4.5, height: 4.5)
        plane.cornerRadius = 2.25
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = UIColor.black
        ink.writesToDepthBuffer = false
        plane.materials = [ink]
        shadow.geometry = plane
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.opacity = 0
        scene.rootNode.addChildNode(shadow)
    }

    // MARK: - Moments

    /// Down safely: a ring of dust, and on a gentle landing flares from both masts.
    private func touchdown(at point: SCNVector3, terrain: LanderTerrain, gentle: Bool) {
        let puff = SCNParticleSystem()
        puff.birthRate = 700
        puff.emissionDuration = 0.12
        puff.loops = false
        puff.particleLifeSpan = 1.6
        puff.particleLifeSpanVariation = 0.5
        puff.particleVelocity = 9
        puff.particleVelocityVariation = 4
        puff.emittingDirection = SCNVector3(0, 1, 0)
        puff.spreadingAngle = 88
        puff.particleSize = 0.9
        puff.particleImage = Self.softDot
        puff.particleColor = UIColor(red: 0.78, green: 0.75, blue: 0.70, alpha: 0.55)
        puff.blendMode = .alpha
        puff.dampingFactor = 2.2
        puff.acceleration = SCNVector3(0, -0.8, 0)
        puff.propertyControllers = [.size: Self.ramp([0.6, 1.8, 3.0]), .opacity: Self.ramp([0.9, 0.5, 0])]
        oneShot(puff, at: point, lasting: 2.5)
        guard gentle else { return }
        for x in [terrain.padStart, terrain.padEnd] {
            let flare = SCNParticleSystem()
            flare.birthRate = 260
            flare.emissionDuration = 0.25
            flare.loops = false
            flare.particleLifeSpan = 1.3
            flare.particleLifeSpanVariation = 0.4
            flare.particleVelocity = 16
            flare.particleVelocityVariation = 5
            flare.emittingDirection = SCNVector3(0, 1, 0)
            flare.spreadingAngle = 22
            flare.particleSize = 0.35
            flare.particleImage = Self.softDot
            flare.particleColor = UIColor(red: 0.45, green: 1, blue: 0.6, alpha: 1)
            flare.particleColorVariation = SCNVector4(0.15, 0.1, 0.4, 0)
            flare.blendMode = .additive
            flare.acceleration = SCNVector3(0, -7, 0)
            flare.propertyControllers = [.opacity: Self.ramp([1, 1, 0])]
            oneShot(flare, at: SCNVector3(Float(x), Float(terrain.padHeight + 3.2), 13), lasting: 2.2)
        }
    }

    /// A crash: a flash, a fireball, smoke, sparks, tumbling debris, a scorch mark and a shake.
    private func explode(at point: SCNVector3, terrain: LanderTerrain) {
        let flash = SCNNode()
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1, green: 0.65, blue: 0.3, alpha: 1)
        light.attenuationEndDistance = 90
        light.intensity = 5000
        flash.light = light
        flash.position = SCNVector3(point.x, point.y + 2, point.z + 4)
        flash.name = Self.effectName
        world.addChildNode(flash)
        flash.runAction(.sequence([
            .customAction(duration: 0.8) { node, elapsed in
                node.light?.intensity = 5000 * max(0, 1 - elapsed / 0.8)
            },
            .removeFromParentNode(),
        ]))

        let fire = SCNParticleSystem()
        fire.birthRate = 900
        fire.emissionDuration = 0.18
        fire.loops = false
        fire.particleLifeSpan = 1.1
        fire.particleLifeSpanVariation = 0.5
        fire.particleVelocity = 11
        fire.particleVelocityVariation = 7
        fire.spreadingAngle = 180
        fire.particleSize = 1.1
        fire.particleSizeVariation = 0.5
        fire.particleImage = Self.softDot
        fire.particleColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        fire.particleColorVariation = SCNVector4(0.08, 0.2, 0.3, 0)
        fire.blendMode = .additive
        fire.dampingFactor = 1.5
        fire.acceleration = SCNVector3(0, 1.5, 0)
        fire.propertyControllers = [.size: Self.ramp([0.8, 2.2, 3.2]), .opacity: Self.ramp([1, 0.6, 0])]
        oneShot(fire, at: point, lasting: 2)

        let sparks = SCNParticleSystem()
        sparks.birthRate = 500
        sparks.emissionDuration = 0.12
        sparks.loops = false
        sparks.particleLifeSpan = 1.4
        sparks.particleLifeSpanVariation = 0.6
        sparks.particleVelocity = 22
        sparks.particleVelocityVariation = 10
        sparks.emittingDirection = SCNVector3(0, 1, 0)
        sparks.spreadingAngle = 75
        sparks.particleSize = 0.22
        sparks.particleImage = Self.softDot
        sparks.particleColor = UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 1)
        sparks.blendMode = .additive
        sparks.acceleration = SCNVector3(0, -9, 0)
        sparks.propertyControllers = [.opacity: Self.ramp([1, 0.9, 0])]
        oneShot(sparks, at: point, lasting: 2.2)

        let smoke = SCNParticleSystem()
        smoke.birthRate = 45
        smoke.emissionDuration = 2.6
        smoke.loops = false
        smoke.particleLifeSpan = 2.8
        smoke.particleLifeSpanVariation = 0.8
        smoke.particleVelocity = 3
        smoke.particleVelocityVariation = 1.5
        smoke.emittingDirection = SCNVector3(0, 1, 0)
        smoke.spreadingAngle = 30
        smoke.particleSize = 1.6
        smoke.particleImage = Self.softDot
        smoke.particleColor = UIColor(white: 0.32, alpha: 0.6)
        smoke.blendMode = .alpha
        smoke.acceleration = SCNVector3(0, 1.2, 0)
        smoke.propertyControllers = [.size: Self.ramp([0.6, 2.0, 3.6]), .opacity: Self.ramp([0, 0.7, 0])]
        oneShot(smoke, at: point, lasting: 6)

        // Pieces of the craft, thrown and tumbling, coming to rest on the ground.
        let ground = terrain
        for i in 0..<9 {
            let size = CGFloat(0.3 + 0.12 * Double(i % 4))
            let piece = SCNNode(geometry: SCNBox(width: size, height: size * 0.6, length: size, chamferRadius: 0.04))
            piece.geometry?.materials = [i % 3 == 0 ? gold : (i % 3 == 1 ? silver : dark)]
            piece.position = point
            piece.name = Self.effectName
            world.addChildNode(piece)
            let vx = Float.random(in: -10...10), vy = Float.random(in: 5...14), vz = Float.random(in: -3...6)
            let start = point
            let fly = SCNAction.customAction(duration: 1.8) { node, elapsed in
                let t = Float(elapsed)
                let x = start.x + vx * t
                let floor = Float(ground.height(at: Double(x))) + 0.15
                let y = max(floor, start.y + vy * t - 3.2 * t * t)
                node.position = SCNVector3(x, y, start.z + vz * t)
            }
            let spin = SCNAction.rotateBy(x: CGFloat.random(in: -8...8), y: CGFloat.random(in: -8...8),
                                          z: CGFloat.random(in: -8...8), duration: 1.8)
            piece.runAction(.sequence([.group([fly, spin]), .wait(duration: 2.5), .fadeOut(duration: 1.2), .removeFromParentNode()]))
        }

        // A dark scorch on the ground where it came down.
        let plane = SCNPlane(width: 7, height: 7)
        plane.cornerRadius = 3.5
        let soot = SCNMaterial()
        soot.lightingModel = .constant
        soot.diffuse.contents = UIColor(white: 0.05, alpha: 1)
        soot.writesToDepthBuffer = false
        plane.materials = [soot]
        let scorch = SCNNode(geometry: plane)
        scorch.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        let x = Double(point.x)
        scorch.position = SCNVector3(point.x, Float(terrain.height(at: x) + 0.1), 0)
        scorch.opacity = 0
        scorch.name = Self.effectName
        world.addChildNode(scorch)
        scorch.runAction(.fadeOpacity(to: 0.55, duration: 0.4))

        shake(1.4)
    }

    /// A short, dying shake of the camera on its mount.
    private func shake(_ strength: Float) {
        var moves: [SCNAction] = []
        var k = strength
        for i in 0..<12 {
            let dx: Float = i % 2 == 0 ? k : -k
            let dy: Float = i % 3 == 0 ? k * 0.7 : -k * 0.5
            moves.append(.move(to: SCNVector3(dx, dy, 0), duration: 0.035))
            k *= 0.8
        }
        moves.append(.move(to: SCNVector3(0, 0, 0), duration: 0.05))
        cameraNode.removeAllActions()
        cameraNode.runAction(.sequence(moves))
    }

    /// A particle burst in the world that tidies itself away.
    private func oneShot(_ system: SCNParticleSystem, at point: SCNVector3, lasting: TimeInterval) {
        let node = SCNNode()
        node.position = point
        node.name = Self.effectName
        node.addParticleSystem(system)
        world.addChildNode(node)
        node.runAction(.sequence([.wait(duration: lasting), .removeFromParentNode()]))
    }

    // MARK: - Particles

    /// The engine's hot core: short-lived, bright, added on.
    private static func flameParticles() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.loops = true
        p.particleLifeSpan = 0.34
        p.particleLifeSpanVariation = 0.12
        p.particleVelocity = 17
        p.particleVelocityVariation = 4
        p.emittingDirection = SCNVector3(0, -1, 0)
        p.spreadingAngle = 9
        p.particleSize = 0.6
        p.particleSizeVariation = 0.2
        p.particleImage = softDot
        p.particleColor = UIColor(red: 1, green: 0.72, blue: 0.32, alpha: 1)
        p.particleColorVariation = SCNVector4(0.04, 0.1, 0.1, 0)
        p.blendMode = .additive
        p.propertyControllers = [.size: ramp([0.5, 1.3, 2.1]), .opacity: ramp([1, 0.7, 0])]
        return p
    }

    /// The exhaust's smoke: slower, paler, lingering behind the craft.
    private static func smokeParticles() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.loops = true
        p.particleLifeSpan = 1.4
        p.particleLifeSpanVariation = 0.4
        p.particleVelocity = 9
        p.particleVelocityVariation = 3
        p.emittingDirection = SCNVector3(0, -1, 0)
        p.spreadingAngle = 16
        p.particleSize = 0.7
        p.particleImage = softDot
        p.particleColor = UIColor(white: 0.75, alpha: 0.35)
        p.blendMode = .alpha
        p.dampingFactor = 1.6
        p.propertyControllers = [.size: ramp([0.6, 1.8, 3.0]), .opacity: ramp([0, 0.5, 0])]
        return p
    }

    /// Dust blown off the ground by the exhaust.
    private static func dustParticles() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.loops = true
        p.particleLifeSpan = 1.3
        p.particleLifeSpanVariation = 0.4
        p.particleVelocity = 8
        p.particleVelocityVariation = 3
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 84
        p.particleSize = 0.8
        p.particleImage = softDot
        p.particleColor = UIColor(red: 0.80, green: 0.76, blue: 0.70, alpha: 0.5)
        p.blendMode = .alpha
        p.dampingFactor = 1.8
        p.acceleration = SCNVector3(0, -1.6, 0)
        p.propertyControllers = [.size: ramp([0.5, 1.6, 2.6]), .opacity: ramp([0.8, 0.45, 0])]
        return p
    }

    /// A value that changes over each particle's life: evenly spaced keys.
    private static func ramp(_ values: [Double]) -> SCNParticlePropertyController {
        let animation = CAKeyframeAnimation()
        animation.values = values.map { NSNumber(value: $0) }
        let last = Double(max(1, values.count - 1))
        animation.keyTimes = values.indices.map { NSNumber(value: Double($0) / last) }
        animation.duration = 1
        return SCNParticlePropertyController(animation: animation)
    }

    /// A soft round dot every particle is drawn with, so none is a square.
    private static let softDot: UIImage = {
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colours = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0.6).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 0.35, 1]) {
                let centre = CGPoint(x: side / 2, y: side / 2)
                context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                                     endCenter: centre, endRadius: side / 2, options: [])
            }
        }
    }()

    // MARK: - Pieces

    /// A height map as an extruded ridge, its front face towards the camera.
    private static func ridge(heights: [Double], step: Double, depth: CGFloat, colour: UIColor) -> SCNNode {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: -60))
        for (i, h) in heights.enumerated() {
            path.addLine(to: CGPoint(x: Double(i) * step, y: h))
        }
        path.addLine(to: CGPoint(x: Double(max(0, heights.count - 1)) * step, y: -60))
        path.close()
        path.flatness = 0.05
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.materials = [material(colour, metal: 0, rough: 0.95)]
        return SCNNode(geometry: shape)
    }

    /// The ridge's face as the camera sees it, coloured by hand: a lit rim
    /// along the skyline (paler on the flats, darker on steep slopes), grey
    /// rock under it, deep shadow at the foot, and a speckle of craters so
    /// it reads as rock rather than a cut-out.
    private static func face(_ terrain: LanderTerrain, z: Float) -> SCNNode {
        let heights = terrain.heights
        let count = heights.count
        guard count > 1 else { return SCNNode() }
        // Depth of each row below the skyline, metres; the last row is the foot.
        let rows: [Double] = [0, 1.2, 4, 14]
        let perColumn = rows.count + 1
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colours: [Float] = []
        positions.reserveCapacity(count * perColumn)
        normals.reserveCapacity(count * perColumn)
        colours.reserveCapacity(count * perColumn * 4)
        var rng = LanderRandom(seed: UInt64(count) &* 7919 &+ UInt64(max(0, terrain.padStart.rounded())))
        let front = SCNVector3(0, 0, 1)
        for i in 0..<count {
            let x = Double(i) * terrain.step
            let top = heights[i]
            let before = heights[max(0, i - 1)], after = heights[min(count - 1, i + 1)]
            let slope = abs(after - before) / (2 * terrain.step)
            let lit = 1 - min(0.4, slope * 0.35)
            let onPad = terrain.isOnPad(x)
            let speck = Float(rng.double(in: -0.06...0.06))
            // A crater's dark smudge every so often under the rim.
            let crater: Float = rng.unit() < 0.12 ? -0.12 : 0
            let rim: [Float] = onPad ? [0.92, 0.92, 0.90] : [Float(0.86 * lit), Float(0.83 * lit), Float(0.78 * lit)]
            let under: [Float] = [0.62 + speck, 0.60 + speck, 0.57 + speck]
            let rock: [Float] = [0.46 + speck + crater, 0.45 + speck + crater, 0.44 + speck + crater]
            let deep: [Float] = [0.30 + crater, 0.29 + crater, 0.30 + crater]
            let foot: [Float] = [0.10, 0.10, 0.13]
            let shades: [[Float]] = [rim, under, rock, deep, foot]
            for r in 0..<perColumn {
                let y = r < rows.count ? top - rows[r] : -60
                positions.append(SCNVector3(Float(x), Float(min(y, top)), z))
                normals.append(front)
                for channel in shades[r] { colours.append(max(0, channel)) }
                colours.append(1)
            }
        }
        var indices: [Int32] = []
        indices.reserveCapacity((count - 1) * (perColumn - 1) * 6)
        for i in 0..<(count - 1) {
            for r in 0..<(perColumn - 1) {
                let a = Int32(i * perColumn + r), b = Int32((i + 1) * perColumn + r)
                let c = b + 1, d = a + 1
                // Counter-clockwise seen from the camera, in front.
                indices.append(contentsOf: [a, d, c, a, c, b])
            }
        }
        let colourData = colours.withUnsafeBufferPointer { Data(buffer: $0) }
        let colourSource = SCNGeometrySource(data: colourData, semantic: .color, vectorCount: positions.count,
                                             usesFloatComponents: true, componentsPerVector: 4,
                                             bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                             dataStride: MemoryLayout<Float>.size * 4)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), colourSource],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let paint = SCNMaterial()
        paint.lightingModel = .constant
        paint.diffuse.contents = UIColor.white
        paint.isDoubleSided = true
        geometry.materials = [paint]
        return SCNNode(geometry: geometry)
    }

    /// Boulders strewn along the top of the ridge, clear of the pad: one
    /// flattened node, so they cost a single draw.
    private static func boulders(_ terrain: LanderTerrain) -> SCNNode {
        let holder = SCNNode()
        let rock = SCNSphere(radius: 1)
        rock.segmentCount = 10
        rock.materials = [material(UIColor(red: 0.42, green: 0.41, blue: 0.40, alpha: 1), metal: 0, rough: 1)]
        var rng = LanderRandom(seed: UInt64(max(1, terrain.padEnd.rounded())) &* 31)
        var placed = 0
        while placed < 36 {
            placed += 1
            let x = rng.double(in: 4...(max(5, terrain.width - 4)))
            if x > terrain.padStart - 4 && x < terrain.padEnd + 4 { continue }
            let size = rng.double(in: 0.4...1.6)
            let node = SCNNode(geometry: rock)
            node.position = SCNVector3(Float(x), Float(terrain.height(at: x) + size * 0.2), Float(rng.double(in: -13...13)))
            node.scale = SCNVector3(Float(size * 1.2), Float(size * 0.6), Float(size))
            node.eulerAngles = SCNVector3(0, Float(rng.double(in: 0...3)), 0)
            holder.addChildNode(node)
        }
        return holder.flattenedClone()
    }

    /// The landing pad: a pale slab flush with the ground, a light at each
    /// end, a chase of runway lights along its front edge.
    private static func pad(_ terrain: LanderTerrain) -> SCNNode {
        let node = SCNNode()
        let slab = SCNNode(geometry: SCNBox(width: CGFloat(terrain.padWidth), height: 0.4, length: 30.4, chamferRadius: 0))
        slab.geometry?.materials = [material(UIColor(white: 0.88, alpha: 1), metal: 0.1, rough: 0.6)]
        slab.position = SCNVector3(Float(terrain.padCentre), Float(terrain.padHeight - 0.18), 0)
        node.addChildNode(slab)
        let stripe = SCNNode(geometry: SCNBox(width: CGFloat(terrain.padWidth) * 0.9, height: 0.05, length: 1.2, chamferRadius: 0))
        stripe.geometry?.materials = [glow(UIColor(red: 0.35, green: 0.9, blue: 0.5, alpha: 1))]
        stripe.position = SCNVector3(Float(terrain.padCentre), Float(terrain.padHeight + 0.04), 12)
        node.addChildNode(stripe)
        // The middle mark: a bright bar across the pad, for a precise touch.
        let middle = SCNNode(geometry: SCNBox(width: 0.6, height: 0.06, length: 24, chamferRadius: 0))
        middle.geometry?.materials = [glow(UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))]
        middle.position = SCNVector3(Float(terrain.padCentre), Float(terrain.padHeight + 0.05), 0)
        node.addChildNode(middle)
        for x in [terrain.padStart, terrain.padEnd] {
            let mast = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 3))
            mast.geometry?.materials = [material(UIColor(white: 0.4, alpha: 1), metal: 0.6, rough: 0.5)]
            mast.position = SCNVector3(Float(x), Float(terrain.padHeight + 1.5), 13)
            node.addChildNode(mast)
            let lamp = SCNNode(geometry: SCNSphere(radius: 0.45))
            lamp.geometry?.materials = [glow(UIColor(red: 0.35, green: 1, blue: 0.5, alpha: 1))]
            lamp.position = SCNVector3(Float(x), Float(terrain.padHeight + 3.1), 13)
            // A slow blink, so the pad is easy to find from high up.
            lamp.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.25, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)])))
            node.addChildNode(lamp)
        }
        // Runway lights running in towards the middle from both ends.
        let bulb = SCNBox(width: 0.5, height: 0.22, length: 0.3, chamferRadius: 0.05)
        bulb.materials = [glow(UIColor(red: 1, green: 0.92, blue: 0.55, alpha: 1))]
        let spacing = 2.4
        let lamps = max(2, Int(terrain.padWidth / spacing))
        for i in 0...lamps {
            let x = terrain.padStart + terrain.padWidth * Double(i) / Double(lamps)
            let light = SCNNode(geometry: bulb)
            light.position = SCNVector3(Float(x), Float(terrain.padHeight + 0.16), 15.35)
            light.opacity = 0.2
            let fromEdge = Double(min(i, lamps - i))
            light.runAction(.sequence([
                .wait(duration: fromEdge * 0.09),
                .repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.1), .fadeOpacity(to: 0.2, duration: 0.5),
                                          .wait(duration: 0.6)])),
            ]))
            node.addChildNode(light)
        }
        return node
    }

    /// A faint column of light over the pad, to steer by from high up.
    private static func beacon(_ terrain: LanderTerrain) -> SCNNode {
        let column = SCNCylinder(radius: 0.9, height: 160)
        let light = SCNMaterial()
        light.lightingModel = .constant
        light.diffuse.contents = UIColor(red: 0.35, green: 1, blue: 0.55, alpha: 0.16)
        light.blendMode = .add
        light.writesToDepthBuffer = false
        light.isDoubleSided = true
        column.materials = [light]
        let node = SCNNode(geometry: column)
        node.position = SCNVector3(Float(terrain.padCentre), Float(terrain.padHeight + 80), 0)
        return node
    }

    /// The Earth, far off and high, the way it hangs over the Moon, with a thin blue halo.
    private static func earth(x: Double) -> SCNNode {
        let holder = SCNNode()
        let earth = SCNNode(geometry: SCNSphere(radius: 34))
        let blue = SCNMaterial()
        blue.lightingModel = .constant
        blue.diffuse.contents = earthFace
        earth.geometry?.materials = [blue]
        holder.addChildNode(earth)
        let halo = SCNNode(geometry: SCNSphere(radius: 38))
        let haze = SCNMaterial()
        haze.lightingModel = .constant
        haze.diffuse.contents = UIColor(red: 0.45, green: 0.7, blue: 1, alpha: 0.22)
        haze.blendMode = .add
        haze.writesToDepthBuffer = false
        halo.geometry?.materials = [haze]
        halo.position = SCNVector3(0, 0, -6)
        holder.addChildNode(halo)
        holder.position = SCNVector3(Float(x), 330, -900)
        return holder
    }

    /// The Earth's face: blue sea, green-brown land and white cloud, lit from one side.
    private static let earthFace: UIImage = {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var rng = LanderRandom(seed: 3)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.18, green: 0.42, blue: 0.86, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<14 {
                let w = CGFloat(rng.double(in: 18...54)), h = CGFloat(rng.double(in: 10...30))
                let rect = CGRect(x: CGFloat(rng.double(in: 0...230)), y: CGFloat(rng.double(in: 14...100)), width: w, height: h)
                UIColor(red: 0.30, green: 0.55, blue: 0.30, alpha: 1).setFill()
                UIBezierPath(ovalIn: rect).fill()
            }
            for _ in 0..<22 {
                let w = CGFloat(rng.double(in: 20...70)), h = CGFloat(rng.double(in: 3...9))
                let rect = CGRect(x: CGFloat(rng.double(in: 0...230)), y: CGFloat(rng.double(in: 0...124)), width: w, height: h)
                UIColor(white: 1, alpha: 0.7).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: h / 2).fill()
            }
        }
    }()

    private static func material(_ colour: UIColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = colour
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }

    /// A material that lights itself: lamps, the window, the flame.
    private static func glow(_ colour: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = colour
        m.emission.contents = colour
        return m
    }

    /// A starfield behind everything, the same stars every time: a deep
    /// gradient, a soft band of the Milky Way crowded with faint stars, and
    /// brighter ones in white, blue and amber, the brightest with a glint.
    private static func starfield() -> UIImage {
        let size = CGSize(width: 600, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        var rng = LanderRandom(seed: 42)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let top = UIColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1).cgColor
            let bottom = UIColor(red: 0.07, green: 0.06, blue: 0.16, alpha: 1).cgColor
            if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // The Milky Way: a few soft clouds along a diagonal, then a crowd of faint stars in it.
            let band = { (t: Double) -> CGPoint in
                CGPoint(x: Double(size.width) * (1.1 - 1.2 * t), y: Double(size.height) * (0.05 + 0.7 * t))
            }
            for i in 0..<7 {
                let centre = band(Double(i) / 6)
                let radius = CGFloat(rng.double(in: 110...190))
                let tint = i % 2 == 0 ? UIColor(red: 0.45, green: 0.40, blue: 0.75, alpha: 0.10).cgColor
                    : UIColor(red: 0.35, green: 0.50, blue: 0.80, alpha: 0.08).cgColor
                let clear = UIColor(red: 0.4, green: 0.4, blue: 0.8, alpha: 0).cgColor
                if let cloud = CGGradient(colorsSpace: space, colors: [tint, clear] as CFArray, locations: [0, 1]) {
                    cg.drawRadialGradient(cloud, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
                }
            }
            for _ in 0..<900 {
                let along = band(rng.unit())
                // Three uniforms summed: bunched towards the middle of the band.
                let spread = (rng.unit() + rng.unit() + rng.unit() - 1.5) * 120
                let point = CGPoint(x: along.x + CGFloat(spread * 0.8), y: along.y + CGFloat(spread * 0.6))
                let r = CGFloat(rng.double(in: 0.3...0.9))
                UIColor(white: 1, alpha: CGFloat(rng.double(in: 0.15...0.5))).setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)).fill()
            }
            for _ in 0..<420 {
                let r = CGFloat(rng.double(in: 0.4...1.7))
                let point = CGPoint(x: rng.double(in: 0...Double(size.width)), y: rng.double(in: 0...Double(size.height)))
                let pick = rng.unit()
                let alpha = CGFloat(rng.double(in: 0.35...1))
                let colour: UIColor = pick < 0.12 ? UIColor(red: 0.7, green: 0.8, blue: 1, alpha: alpha)
                    : pick < 0.2 ? UIColor(red: 1, green: 0.85, blue: 0.65, alpha: alpha) : UIColor(white: 1, alpha: alpha)
                colour.setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)).fill()
                if r > 1.5 {
                    // A glint: a thin cross through the brightest stars.
                    UIColor(white: 1, alpha: 0.35).setFill()
                    cg.fill(CGRect(x: point.x - 4, y: point.y - 0.25, width: 8, height: 0.5))
                    cg.fill(CGRect(x: point.x - 0.25, y: point.y - 4, width: 0.5, height: 8))
                }
            }
        }
    }
}

/// The SceneKit view, for SwiftUI. It renders continuously while a flight is
/// under way and only when something changes otherwise (a card is up, the
/// game is paused), so a briefing does not burn the battery; the controller
/// moves the nodes.
struct LanderSceneView: UIViewRepresentable {
    let controller: LanderSceneController
    /// A flight is under way: draw every frame.
    var active = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = active ? 60 : 30
        view.rendersContinuously = active
        view.isPlaying = true
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.rendersContinuously != active { view.rendersContinuously = active }
        // The blinking lamps keep SceneKit drawing even when it need not
        // render continuously: behind a card, half the frames are plenty.
        let fps = active ? 60 : 30
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.isPlaying = false
        view.rendersContinuously = false
    }
}
