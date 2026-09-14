import UIKit
import SceneKit

private enum PhysicsCategory {
    static let player = 1
    static let obstacle = 2
}

private enum ObstacleKind: CaseIterable {
    case low
    case high
    case full

    var yRange: (min: CGFloat, max: CGFloat) {
        switch self {
        case .low: return (0, 0.6)
        case .high: return (1.15, 1.65)
        case .full: return (0, 2.2)
        }
    }

    var color: UIColor {
        switch self {
        case .low: return .systemRed
        case .high: return .systemOrange
        case .full: return .systemPurple
        }
    }
}

final class GameViewController: UIViewController {

    private let sceneView = SCNView()
    private let scoreLabel = UILabel()
    private let messageLabel = UILabel()

    private var scene: SCNScene!
    private var playerNode: SCNNode!

    private let laneWidth: Float = 2.5
    private var currentLane = 0

    private let restingY: Float = 0.8
    private let jumpY: Float = 1.8
    private let duckY: Float = 0.1

    private var isPlaying = false
    private var isJumping = false
    private var isDucking = false

    private var score = 0
    private var elapsedTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var speed: Float = 8
    private var distanceSinceSpawn: Float = 0
    private var nextSpawnDistance: Float = 12

    private var obstacles: [SCNNode] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupOverlay()
        setupGestures()
        showMessage("Tap to Start")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneView.frame = view.bounds
        scoreLabel.frame = CGRect(
            x: view.bounds.width - 140,
            y: view.safeAreaInsets.top + 12,
            width: 120,
            height: 40
        )
        messageLabel.frame = CGRect(
            x: 0,
            y: view.bounds.height / 2 - 30,
            width: view.bounds.width,
            height: 60
        )
    }

    // MARK: - Setup

    private func setupScene() {
        scene = SCNScene()
        sceneView.scene = scene
        sceneView.delegate = self
        sceneView.isPlaying = true
        sceneView.backgroundColor = UIColor(red: 0.53, green: 0.75, blue: 0.92, alpha: 1)
        scene.physicsWorld.contactDelegate = self
        scene.physicsWorld.gravity = SCNVector3(0, 0, 0)
        view.addSubview(sceneView)

        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.7, blue: 0.35, alpha: 1)
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.55, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let directional = SCNLight()
        directional.type = .directional
        directional.color = UIColor(white: 0.9, alpha: 1)
        let directionalNode = SCNNode()
        directionalNode.light = directional
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalNode)

        let camera = SCNCamera()
        camera.zFar = 120
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3.4, 6.5)
        cameraNode.eulerAngles = SCNVector3(-0.35, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let capsule = SCNCapsule(capRadius: 0.4, height: 1.6)
        capsule.firstMaterial?.diffuse.contents = UIColor.systemBlue
        let player = SCNNode(geometry: capsule)
        player.position = SCNVector3(0, restingY, 0)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: capsule, options: nil))
        body.categoryBitMask = PhysicsCategory.player
        body.contactTestBitMask = PhysicsCategory.obstacle
        body.collisionBitMask = 0
        player.physicsBody = body
        scene.rootNode.addChildNode(player)
        playerNode = player
    }

    private func setupOverlay() {
        scoreLabel.textAlignment = .right
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        scoreLabel.textColor = .white
        scoreLabel.layer.shadowColor = UIColor.black.cgColor
        scoreLabel.layer.shadowOpacity = 0.6
        scoreLabel.layer.shadowRadius = 2
        scoreLabel.layer.shadowOffset = .zero
        scoreLabel.text = "0"
        view.addSubview(scoreLabel)

        messageLabel.textAlignment = .center
        messageLabel.font = .boldSystemFont(ofSize: 26)
        messageLabel.textColor = .white
        messageLabel.layer.shadowColor = UIColor.black.cgColor
        messageLabel.layer.shadowOpacity = 0.6
        messageLabel.layer.shadowRadius = 2
        messageLabel.layer.shadowOffset = .zero
        messageLabel.numberOfLines = 1
        view.addSubview(messageLabel)
    }

    private func setupGestures() {
        let up = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        up.direction = .up
        let down = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        down.direction = .down
        let left = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        left.direction = .left
        let right = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
        right.direction = .right
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        [up, down, left, right, tap].forEach { sceneView.addGestureRecognizer($0) }
    }

    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.isHidden = false
    }

    // MARK: - Game flow

    private func startGame() {
        isPlaying = true
        score = 0
        elapsedTime = 0
        speed = 8
        distanceSinceSpawn = 0
        nextSpawnDistance = 12
        scoreLabel.text = "0"
        messageLabel.isHidden = true

        obstacles.forEach { $0.removeFromParentNode() }
        obstacles.removeAll()

        currentLane = 0
        isJumping = false
        isDucking = false
        playerNode.removeAllActions()
        playerNode.position = SCNVector3(0, restingY, 0)
    }

    private func endGame() {
        guard isPlaying else { return }
        isPlaying = false
        showMessage("Game Over - Tap to Retry")
    }

    // MARK: - Input

    @objc private func handleTap() {
        if !isPlaying {
            startGame()
        }
    }

    @objc private func handleSwipeUp() {
        guard isPlaying, !isJumping, !isDucking else { return }
        isJumping = true
        let up = SCNAction.moveBy(x: 0, y: CGFloat(jumpY - restingY), z: 0, duration: 0.28)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: CGFloat(restingY - jumpY), z: 0, duration: 0.28)
        down.timingMode = .easeIn
        playerNode.runAction(.sequence([up, down])) { [weak self] in
            DispatchQueue.main.async { self?.isJumping = false }
        }
    }

    @objc private func handleSwipeDown() {
        guard isPlaying, !isJumping, !isDucking else { return }
        isDucking = true
        let down = SCNAction.moveBy(x: 0, y: CGFloat(duckY - restingY), z: 0, duration: 0.15)
        let hold = SCNAction.wait(duration: 0.35)
        let up = SCNAction.moveBy(x: 0, y: CGFloat(restingY - duckY), z: 0, duration: 0.15)
        playerNode.runAction(.sequence([down, hold, up])) { [weak self] in
            DispatchQueue.main.async { self?.isDucking = false }
        }
    }

    @objc private func handleSwipeLeft() {
        guard isPlaying, currentLane > -1 else { return }
        currentLane -= 1
        moveToCurrentLane()
    }

    @objc private func handleSwipeRight() {
        guard isPlaying, currentLane < 1 else { return }
        currentLane += 1
        moveToCurrentLane()
    }

    private func moveToCurrentLane() {
        let targetX = Float(currentLane) * laneWidth
        let action = SCNAction.moveBy(x: CGFloat(targetX - playerNode.position.x), y: 0, z: 0, duration: 0.18)
        action.timingMode = .easeOut
        playerNode.runAction(action)
    }

    // MARK: - Obstacles

    private func spawnObstacle() {
        let kind = ObstacleKind.allCases.randomElement()!
        let lane = Int.random(in: -1...1)

        let range = kind.yRange
        let height = range.max - range.min
        let box = SCNBox(width: 1.6, height: height, length: 0.6, chamferRadius: 0.05)
        box.firstMaterial?.diffuse.contents = kind.color
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float(lane) * laneWidth, Float(range.min) + Float(height) / 2, -80)

        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: box, options: nil))
        body.categoryBitMask = PhysicsCategory.obstacle
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = 0
        node.physicsBody = body

        scene.rootNode.addChildNode(node)
        obstacles.append(node)
    }
}

extension GameViewController: SCNPhysicsContactDelegate {
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        DispatchQueue.main.async { [weak self] in
            self?.endGame()
        }
    }
}

extension GameViewController: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isPlaying else {
            lastUpdateTime = time
            return
        }
        if lastUpdateTime == 0 { lastUpdateTime = time }
        let delta = min(time - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = time

        let move = speed * Float(delta)
        for obstacle in obstacles {
            obstacle.position.z += move
        }
        obstacles.removeAll { node in
            if node.position.z > 8 {
                node.removeFromParentNode()
                return true
            }
            return false
        }

        distanceSinceSpawn += move
        if distanceSinceSpawn >= nextSpawnDistance {
            distanceSinceSpawn = 0
            nextSpawnDistance = Float.random(in: 10...16)
            spawnObstacle()
        }

        elapsedTime += delta
        speed = min(20, 8 + Float(elapsedTime) * 0.15)

        let newScore = Int(elapsedTime * 10)
        if newScore != score {
            score = newScore
            let text = "\(newScore)"
            DispatchQueue.main.async { [weak self] in
                self?.scoreLabel.text = text
            }
        }
    }
}
