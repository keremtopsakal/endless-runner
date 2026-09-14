import UIKit
import SceneKit

private enum PhysicsCategory {
    static let player = 1
    static let obstacle = 2
    static let coin = 4
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
    private let scorePanel = UIView()
    private let scoreLabel = UILabel()
    private let bestLabel = UILabel()
    private let messagePanel = UIView()
    private let messageLabel = UILabel()

    private let startPanel = UIView()
    private let titleLabel = UILabel()
    private let instructionsLabel = UILabel()
    private let startBestLabel = UILabel()
    private let playButton = UIButton(type: .system)

    private var scene: SCNScene!
    private var playerNode: SCNNode!
    private var dustParticles: SCNParticleSystem!

    private let laneWidth: Float = 1.3
    private var currentLane = 0

    private let restingY: Float = 0.8
    private let jumpY: Float = 1.8
    private let duckY: Float = 0.1

    private var isPlaying = false
    private var isJumping = false
    private var isDucking = false
    private var hasStartedOnce = false

    private var score = 0
    private var coinScore = 0
    private var elapsedTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var speed: Float = 8
    private var distanceSinceObstacle: Float = 0
    private var nextObstacleDistance: Float = 12
    private var distanceSinceScenery: Float = 0

    private var obstacles: [SCNNode] = []
    private var coins: [SCNNode] = []
    private var scenery: [SCNNode] = []

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    private let highScoreKey = "endlessRunnerHighScore"
    private var highScore: Int {
        get { UserDefaults.standard.integer(forKey: highScoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: highScoreKey) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupOverlay()
        setupGestures()
        bestLabel.text = "Best \(highScore)"
        startBestLabel.text = "Best score: \(highScore)"
        startPanel.isHidden = false
        impactLight.prepare()
        impactMedium.prepare()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneView.frame = view.bounds

        let panelWidth: CGFloat = 130
        scorePanel.frame = CGRect(
            x: view.bounds.width - panelWidth - 16,
            y: view.safeAreaInsets.top + 12,
            width: panelWidth,
            height: 56
        )
        scoreLabel.frame = CGRect(x: 0, y: 4, width: panelWidth, height: 32)
        bestLabel.frame = CGRect(x: 0, y: 34, width: panelWidth, height: 18)

        let messageWidth = min(320, view.bounds.width - 40)
        messagePanel.frame = CGRect(
            x: (view.bounds.width - messageWidth) / 2,
            y: view.bounds.height / 2 - 40,
            width: messageWidth,
            height: 80
        )
        messageLabel.frame = messagePanel.bounds.insetBy(dx: 12, dy: 8)

        let startWidth = min(320, view.bounds.width - 48)
        let startHeight: CGFloat = 300
        startPanel.frame = CGRect(
            x: (view.bounds.width - startWidth) / 2,
            y: (view.bounds.height - startHeight) / 2,
            width: startWidth,
            height: startHeight
        )
        titleLabel.frame = CGRect(x: 16, y: 20, width: startWidth - 32, height: 36)
        instructionsLabel.frame = CGRect(x: 16, y: 64, width: startWidth - 32, height: 130)
        startBestLabel.frame = CGRect(x: 16, y: 200, width: startWidth - 32, height: 20)
        playButton.frame = CGRect(x: 24, y: 232, width: startWidth - 48, height: 52)
    }

    // MARK: - Setup

    private func setupScene() {
        scene = SCNScene()
        sceneView.scene = scene
        sceneView.delegate = self
        sceneView.isPlaying = true
        let horizonColor = UIColor(red: 0.68, green: 0.85, blue: 0.98, alpha: 1)
        sceneView.backgroundColor = horizonColor
        scene.background.contents = makeSkyGradientImage()
        scene.fogColor = horizonColor
        scene.fogStartDistance = 45
        scene.fogEndDistance = 90
        scene.fogDensityExponent = 1
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
        directional.castsShadow = true
        directional.shadowRadius = 3
        directional.shadowColor = UIColor(white: 0, alpha: 0.35)
        let directionalNode = SCNNode()
        directionalNode.light = directional
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalNode)

        let camera = SCNCamera()
        camera.zFar = 110
        camera.fieldOfView = 75
        camera.wantsHDR = false
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 4.5, 9.0)
        cameraNode.eulerAngles = SCNVector3(-0.4, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        addLaneMarkers()

        playerNode = makePlayerNode()
        scene.rootNode.addChildNode(playerNode)
    }

    private func addLaneMarkers() {
        for offset: Float in [-laneWidth / 2, laneWidth / 2] {
            let stripe = SCNBox(width: 0.04, height: 0.01, length: 300, chamferRadius: 0)
            stripe.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.55)
            let node = SCNNode(geometry: stripe)
            node.position = SCNVector3(offset, 0.02, -100)
            scene.rootNode.addChildNode(node)
        }
    }

    private func makeSkyGradientImage() -> UIImage {
        let size = CGSize(width: 4, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [
                UIColor(red: 0.27, green: 0.52, blue: 0.83, alpha: 1).cgColor,
                UIColor(red: 0.68, green: 0.85, blue: 0.98, alpha: 1).cgColor
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    private func makePlayerNode() -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(0, restingY, 0)

        let bodyCapsule = SCNCapsule(capRadius: 0.35, height: 1.1)
        bodyCapsule.firstMaterial?.diffuse.contents = UIColor.systemBlue
        let bodyNode = SCNNode(geometry: bodyCapsule)
        bodyNode.position = SCNVector3(0, 0.05, 0)
        root.addChildNode(bodyNode)

        let head = SCNSphere(radius: 0.28)
        head.firstMaterial?.diffuse.contents = UIColor(red: 0.96, green: 0.8, blue: 0.65, alpha: 1)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.75, 0)
        root.addChildNode(headNode)

        let bounding = SCNCapsule(capRadius: 0.4, height: 1.6)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: bounding, options: nil))
        body.categoryBitMask = PhysicsCategory.player
        body.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.coin
        body.collisionBitMask = 0
        root.physicsBody = body

        let dust = SCNParticleSystem()
        dust.birthRate = 18
        dust.particleLifeSpan = 0.5
        dust.particleSize = 0.05
        dust.particleSizeVariation = 0.02
        dust.particleColor = UIColor(white: 0.9, alpha: 0.5)
        dust.spreadingAngle = 25
        dust.particleVelocity = 0.6
        dust.particleVelocityVariation = 0.2
        dust.emitterShape = SCNSphere(radius: 0.12)
        dust.birthLocation = .surface
        dust.loops = true
        dust.isAffectedByGravity = false
        let dustNode = SCNNode()
        dustNode.position = SCNVector3(0, -0.75, 0)
        dustNode.addParticleSystem(dust)
        root.addChildNode(dustNode)
        dustParticles = dust

        let bob = SCNAction.sequence([
            .moveBy(x: 0, y: 0.06, z: 0, duration: 0.15),
            .moveBy(x: 0, y: -0.06, z: 0, duration: 0.15)
        ])
        bodyNode.runAction(.repeatForever(bob))

        return root
    }

    private func setupOverlay() {
        scorePanel.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        scorePanel.layer.cornerRadius = 14
        view.addSubview(scorePanel)

        scoreLabel.textAlignment = .center
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        scoreLabel.textColor = .white
        scoreLabel.text = "0"
        scorePanel.addSubview(scoreLabel)

        bestLabel.textAlignment = .center
        bestLabel.font = .systemFont(ofSize: 13, weight: .medium)
        bestLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        scorePanel.addSubview(bestLabel)

        messagePanel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        messagePanel.layer.cornerRadius = 16
        messagePanel.isHidden = true
        view.addSubview(messagePanel)

        messageLabel.textAlignment = .center
        messageLabel.font = .boldSystemFont(ofSize: 22)
        messageLabel.textColor = .white
        messageLabel.numberOfLines = 2
        messagePanel.addSubview(messageLabel)

        startPanel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        startPanel.layer.cornerRadius = 22
        view.addSubview(startPanel)

        titleLabel.text = "Ceaseless Runner"
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .white
        startPanel.addSubview(titleLabel)

        instructionsLabel.text = "Swipe left or right to change lanes\nSwipe up to jump\nSwipe down to duck"
        instructionsLabel.textAlignment = .center
        instructionsLabel.font = .systemFont(ofSize: 16)
        instructionsLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        instructionsLabel.numberOfLines = 3
        startPanel.addSubview(instructionsLabel)

        startBestLabel.textAlignment = .center
        startBestLabel.font = .systemFont(ofSize: 14, weight: .medium)
        startBestLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        startPanel.addSubview(startBestLabel)

        playButton.setTitle("PLAY", for: .normal)
        playButton.titleLabel?.font = .boldSystemFont(ofSize: 20)
        playButton.setTitleColor(.black, for: .normal)
        playButton.backgroundColor = UIColor.systemYellow
        playButton.layer.cornerRadius = 14
        playButton.addTarget(self, action: #selector(handlePlayTapped), for: .touchUpInside)
        startPanel.addSubview(playButton)
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
        messagePanel.isHidden = false
    }

    // MARK: - Game flow

    private func startGame() {
        isPlaying = true
        score = 0
        coinScore = 0
        elapsedTime = 0
        speed = 8
        distanceSinceObstacle = 0
        nextObstacleDistance = 12
        distanceSinceScenery = 0
        scoreLabel.text = "0"
        messagePanel.isHidden = true

        obstacles.forEach { $0.removeFromParentNode() }
        obstacles.removeAll()
        coins.forEach { $0.removeFromParentNode() }
        coins.removeAll()
        scenery.forEach { $0.removeFromParentNode() }
        scenery.removeAll()

        currentLane = 0
        isJumping = false
        isDucking = false
        playerNode.removeAllActions()
        playerNode.position = SCNVector3(0, restingY, 0)
    }

    private func endGame() {
        guard isPlaying else { return }
        isPlaying = false
        notification.notificationOccurred(.error)
        if score > highScore {
            highScore = score
            bestLabel.text = "Best \(highScore)"
            showMessage("New Best! \(score)\nTap to Retry")
        } else {
            showMessage("Game Over  \(score)\nTap to Retry")
        }
    }

    // MARK: - Input

    @objc private func handleTap() {
        guard hasStartedOnce, !isPlaying else { return }
        startGame()
    }

    @objc private func handlePlayTapped() {
        hasStartedOnce = true
        startPanel.isHidden = true
        startGame()
    }

    @objc private func handleSwipeUp() {
        guard isPlaying, !isJumping, !isDucking else { return }
        isJumping = true
        impactMedium.impactOccurred()
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
        impactMedium.impactOccurred()
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
        impactLight.impactOccurred()
        moveToCurrentLane()
    }

    @objc private func handleSwipeRight() {
        guard isPlaying, currentLane < 1 else { return }
        currentLane += 1
        impactLight.impactOccurred()
        moveToCurrentLane()
    }

    private func moveToCurrentLane() {
        let targetX = Float(currentLane) * laneWidth
        let moveAction = SCNAction.moveBy(x: CGFloat(targetX - playerNode.position.x), y: 0, z: 0, duration: 0.18)
        moveAction.timingMode = .easeOut
        let tiltOut = SCNAction.rotateTo(x: 0, y: 0, z: CGFloat(currentLane == 0 ? 0 : (targetX > 0 ? -0.18 : 0.18)), duration: 0.09, usesShortestUnitArc: true)
        let tiltBack = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.18, usesShortestUnitArc: true)
        playerNode.runAction(moveAction)
        playerNode.runAction(.sequence([tiltOut, tiltBack]))
    }

    // MARK: - Obstacles, coins & scenery

    private func spawnObstacle() {
        let kind = ObstacleKind.allCases.randomElement()!
        let lane = Int.random(in: -1...1)

        let range = kind.yRange
        let height = range.max - range.min
        let box = SCNBox(width: 1.0, height: height, length: 0.6, chamferRadius: 0.05)
        box.firstMaterial?.diffuse.contents = kind.color
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float(lane) * laneWidth, Float(range.min) + Float(height) / 2, -80)
        node.castsShadow = true

        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: box, options: nil))
        body.categoryBitMask = PhysicsCategory.obstacle
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = 0
        node.physicsBody = body

        scene.rootNode.addChildNode(node)
        obstacles.append(node)

        let coinLane = [-1, 0, 1].filter { $0 != lane }.randomElement()!
        spawnCoin(lane: coinLane, z: -80)
    }

    private func spawnCoin(lane: Int, z: Float) {
        let sphere = SCNSphere(radius: 0.22)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow
        sphere.firstMaterial?.metalness.contents = 0.7
        sphere.firstMaterial?.roughness.contents = 0.25
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(Float(lane) * laneWidth, 1.0, z)

        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: sphere, options: nil))
        body.categoryBitMask = PhysicsCategory.coin
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = 0
        node.physicsBody = body

        let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.2))
        node.runAction(spin)

        scene.rootNode.addChildNode(node)
        coins.append(node)
    }

    private func spawnSceneryPair() {
        for side: Float in [-1, 1] {
            let height = CGFloat.random(in: 4...9)
            let building = SCNBox(width: 3, height: height, length: 3, chamferRadius: 0)
            building.firstMaterial?.diffuse.contents = UIColor(
                white: CGFloat.random(in: 0.55...0.78),
                alpha: 1
            )
            let node = SCNNode(geometry: building)
            node.position = SCNVector3(side * 4.2, Float(height) / 2, -85)
            node.castsShadow = false
            scene.rootNode.addChildNode(node)
            scenery.append(node)
        }
    }

    private func collectCoin(_ node: SCNNode) {
        guard coins.contains(node) else { return }
        coins.removeAll { $0 == node }
        impactLight.impactOccurred()
        coinScore += 5
        score = coinScore + Int(elapsedTime * 10)
        scoreLabel.text = "\(score)"
        let popUp = SCNAction.scale(to: 1.6, duration: 0.12)
        let fade = SCNAction.fadeOut(duration: 0.12)
        node.runAction(.group([popUp, fade])) {
            node.removeFromParentNode()
        }
    }
}

extension GameViewController: SCNPhysicsContactDelegate {
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let nodes = [contact.nodeA, contact.nodeB]
        if let coinNode = nodes.first(where: { $0.physicsBody?.categoryBitMask == PhysicsCategory.coin }) {
            DispatchQueue.main.async { [weak self] in
                self?.collectCoin(coinNode)
            }
        } else if nodes.contains(where: { $0.physicsBody?.categoryBitMask == PhysicsCategory.obstacle }) {
            DispatchQueue.main.async { [weak self] in
                self?.endGame()
            }
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

        advanceAndPrune(&obstacles, by: move, limit: 8)
        advanceAndPrune(&coins, by: move, limit: 8)
        advanceAndPrune(&scenery, by: move, limit: 8)

        distanceSinceObstacle += move
        if distanceSinceObstacle >= nextObstacleDistance {
            distanceSinceObstacle = 0
            nextObstacleDistance = Float.random(in: 10...16)
            spawnObstacle()
        }

        distanceSinceScenery += move
        if distanceSinceScenery >= 18 {
            distanceSinceScenery = 0
            spawnSceneryPair()
        }

        elapsedTime += delta
        speed = min(20, 8 + Float(elapsedTime) * 0.15)

        let newScore = coinScore + Int(elapsedTime * 10)
        if newScore != score {
            score = newScore
            let text = "\(score)"
            DispatchQueue.main.async { [weak self] in
                self?.scoreLabel.text = text
            }
        }
    }

    private func advanceAndPrune(_ nodes: inout [SCNNode], by move: Float, limit: Float) {
        for node in nodes {
            node.position.z += move
        }
        nodes.removeAll { node in
            if node.position.z > limit {
                node.removeFromParentNode()
                return true
            }
            return false
        }
    }
}
