import SwiftUI
import SceneKit
import UIKit

/// Lander's 3D world: the flight from `LanderLogic` drawn in SceneKit.
///
/// The flight is flat (x across, y up), so the world is built around it: the
/// ground's height map extruded into a ridge thirty metres deep, two paler
/// ridges behind it for distance, the pad lit at both ends, a starfield and
/// the Earth low in the sky. A perspective camera follows the craft and pulls
/// back with altitude, so the climb-down reads as depth rather than a scroll.
///
/// Nothing here decides anything. `update(_:)` is called once a frame on the
/// main thread with the flight as the rules left it; SceneKit renders on its
/// own thread and picks the new positions up on its next frame.
@MainActor
final class LanderSceneController {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let craft = SCNNode()
    private let flameHolder = SCNNode()
    private let flameLight = SCNLight()
    private let shadow = SCNNode()
    private var world = SCNNode()
    private var terrain: LanderTerrain?
    private var cameraAt = SCNVector3(0, 0, 0)
    private var exploded = false

    init() {
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
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(world)
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
                                   colour: UIColor(white: 0.30 - 0.08 * CGFloat(k), alpha: 1))
            ridge.position = SCNVector3(Float(-terrain.width * 0.25 * k), 0, Float(-70 * k))
            world.addChildNode(ridge)
        }
        world.addChildNode(Self.ridge(heights: terrain.heights, step: terrain.step, depth: 30,
                                      colour: UIColor(red: 0.62, green: 0.60, blue: 0.57, alpha: 1)))
        world.addChildNode(Self.pad(terrain))
        // The Earth, far off and high, the way it hangs over the Moon.
        let earth = SCNNode(geometry: SCNSphere(radius: 34))
        let blue = SCNMaterial()
        blue.lightingModel = .constant
        blue.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1)
        earth.geometry?.materials = [blue]
        earth.position = SCNVector3(Float(terrain.width * 0.7), 330, -900)
        world.addChildNode(earth)
        exploded = false
        craft.isHidden = false
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
        flameLight.intensity = CGFloat(burn) * 900

        // The craft's shadow on the ground under it, fainter and wider as it climbs.
        let ground = flight.terrain.height(at: c.x)
        let height = max(0, c.y - LanderRules.footDrop - ground)
        shadow.position = SCNVector3(Float(c.x), Float(ground + 0.08), 0)
        let spread = Float(1 + height / 25)
        shadow.scale = SCNVector3(spread, spread, 1)
        shadow.opacity = CGFloat(max(0, 0.45 - height / 160))

        if case .crashed = flight.outcome, !exploded {
            exploded = true
            explode(at: craft.position)
            craft.isHidden = true
        }

        // Follow the craft, further back the higher it is.
        let back = Float(min(max(38 + height * 0.65, 38), 150))
        let target = SCNVector3(Float(c.x), Float(c.y) + 6 + back * 0.08, back)
        let ease: Float = cameraAt.z == 0 ? 1 : 0.12
        cameraAt = SCNVector3(cameraAt.x + (target.x - cameraAt.x) * ease,
                              cameraAt.y + (target.y - cameraAt.y) * ease,
                              cameraAt.z + (target.z - cameraAt.z) * ease)
        cameraNode.position = cameraAt
        cameraNode.eulerAngles = SCNVector3(-0.16, 0, 0)
    }

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
        let silver = Self.material(UIColor(white: 0.85, alpha: 1), metal: 0.8, rough: 0.35)
        let gold = Self.material(UIColor(red: 0.85, green: 0.65, blue: 0.22, alpha: 1), metal: 0.9, rough: 0.4)
        let dark = Self.material(UIColor(white: 0.25, alpha: 1), metal: 0.5, rough: 0.6)

        let cabin = SCNNode(geometry: SCNSphere(radius: 1.0))
        cabin.geometry?.materials = [silver]
        cabin.position = SCNVector3(0, 0.55, 0)
        craft.addChildNode(cabin)
        let window = SCNNode(geometry: SCNSphere(radius: 0.32))
        window.geometry?.materials = [Self.glow(UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1))]
        window.position = SCNVector3(0, 0.7, 0.85)
        craft.addChildNode(window)
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

    private func explode(at point: SCNVector3) {
        let burst = SCNParticleSystem()
        burst.birthRate = 900
        burst.emissionDuration = 0.15
        burst.loops = false
        burst.particleLifeSpan = 1.6
        burst.particleLifeSpanVariation = 0.6
        burst.particleVelocity = 14
        burst.particleVelocityVariation = 8
        burst.spreadingAngle = 180
        burst.particleSize = 0.45
        burst.particleColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        burst.particleColorVariation = SCNVector4(0.08, 0.2, 0.3, 0)
        burst.blendMode = .additive
        burst.acceleration = SCNVector3(0, -3, 0)
        let node = SCNNode()
        node.position = point
        node.addParticleSystem(burst)
        scene.rootNode.addChildNode(node)
        let wait = SCNAction.wait(duration: 3)
        node.runAction(.sequence([wait, .removeFromParentNode()]))
    }

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

    /// The landing pad: a pale slab flush with the ground, a light at each end.
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
        return node
    }

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

    /// A starfield behind everything: the same stars every time.
    private static func starfield() -> UIImage {
        let size = CGSize(width: 600, height: 1200)
        var rng = LanderRandom(seed: 42)
        return UIGraphicsImageRenderer(size: size).image { context in
            let top = UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1).cgColor
            let bottom = UIColor(red: 0.06, green: 0.06, blue: 0.14, alpha: 1).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray,
                                         locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            for _ in 0..<420 {
                let r = CGFloat(rng.double(in: 0.4...1.6))
                let point = CGPoint(x: rng.double(in: 0...Double(size.width)), y: rng.double(in: 0...Double(size.height)))
                UIColor(white: 1, alpha: CGFloat(rng.double(in: 0.35...1))).setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)).fill()
            }
        }
    }
}

/// The SceneKit view, for SwiftUI. It renders continuously while it is on
/// screen; the controller moves the nodes.
struct LanderSceneView: UIViewRepresentable {
    let controller: LanderSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.isPlaying = false
        view.rendersContinuously = false
    }
}
