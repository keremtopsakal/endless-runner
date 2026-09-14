import SpriteKit

private enum PhysicsCategory {
    static let player: UInt32 = 0x1 << 0
    static let ground: UInt32 = 0x1 << 1
    static let obstacle: UInt32 = 0x1 << 2
}

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private var player: SKShapeNode!
    private var scoreLabel: SKLabelNode!
    private var messageLabel: SKLabelNode!

    private var score = 0
    private var isPlaying = false
    private var isGrounded = true

    private let groundHeight: CGFloat = 80
    private let playerSize = CGSize(width: 40, height: 40)
    private let jumpImpulse: CGFloat = 480
    private let obstacleSpeed: CGFloat = 260

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        setupGround()
        setupPlayer()
        setupLabels()
        showMessage("Tap to Start")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard oldSize != .zero else { return }
        removeAllChildren()
        setupGround()
        setupPlayer()
        setupLabels()
        if isPlaying {
            resetPlayerPosition()
        } else {
            showMessage("Tap to Start")
        }
    }

    // MARK: - Setup

    private func setupGround() {
        let groundVisual = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: 6))
        groundVisual.fillColor = .brown
        groundVisual.strokeColor = .clear
        groundVisual.position = CGPoint(x: size.width / 2, y: groundHeight)
        groundVisual.zPosition = 1
        addChild(groundVisual)

        let groundNode = SKNode()
        let groundBody = SKPhysicsBody(
            edgeFrom: CGPoint(x: -size.width, y: groundHeight),
            to: CGPoint(x: size.width * 2, y: groundHeight)
        )
        groundBody.categoryBitMask = PhysicsCategory.ground
        groundBody.collisionBitMask = PhysicsCategory.player
        groundBody.contactTestBitMask = PhysicsCategory.player
        groundBody.friction = 0
        groundNode.physicsBody = groundBody
        addChild(groundNode)
    }

    private func setupPlayer() {
        let node = SKShapeNode(rectOf: playerSize, cornerRadius: 6)
        node.fillColor = .darkGray
        node.strokeColor = .black
        node.zPosition = 2

        let body = SKPhysicsBody(rectangleOf: playerSize)
        body.categoryBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.ground
        body.contactTestBitMask = PhysicsCategory.ground | PhysicsCategory.obstacle
        body.allowsRotation = false
        body.restitution = 0
        body.linearDamping = 0
        node.physicsBody = body

        addChild(node)
        player = node
        resetPlayerPosition()
    }

    private func resetPlayerPosition() {
        player.position = CGPoint(x: size.width * 0.25, y: groundHeight + playerSize.height / 2)
        player.physicsBody?.velocity = .zero
        isGrounded = true
    }

    private func setupLabels() {
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        scoreLabel.fontSize = 28
        scoreLabel.fontColor = .black
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: size.width - 30, y: size.height - 60)
        scoreLabel.text = "\(score)"
        scoreLabel.zPosition = 10
        addChild(scoreLabel)

        messageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        messageLabel.fontSize = 32
        messageLabel.fontColor = .black
        messageLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        messageLabel.zPosition = 10
        messageLabel.isHidden = true
        addChild(messageLabel)
    }

    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.isHidden = false
    }

    // MARK: - Game flow

    private func startGame() {
        isPlaying = true
        score = 0
        scoreLabel.text = "\(score)"
        messageLabel.isHidden = true

        enumerateChildNodes(withName: "obstacle") { node, _ in node.removeFromParent() }
        resetPlayerPosition()

        let spawn = SKAction.run { [weak self] in self?.spawnObstacle() }
        let wait = SKAction.wait(forDuration: 1.3, withRange: 0.7)
        run(.repeatForever(.sequence([spawn, wait])), withKey: "spawning")

        let scoreTick = SKAction.run { [weak self] in
            guard let self else { return }
            self.score += 1
            self.scoreLabel.text = "\(self.score)"
        }
        run(.repeatForever(.sequence([.wait(forDuration: 0.5), scoreTick])), withKey: "scoring")
    }

    private func endGame() {
        guard isPlaying else { return }
        isPlaying = false
        removeAction(forKey: "spawning")
        removeAction(forKey: "scoring")
        enumerateChildNodes(withName: "obstacle") { node, _ in node.removeAllActions() }
        showMessage("Game Over - Tap to Retry")
    }

    private func jump() {
        guard isPlaying, isGrounded else { return }
        isGrounded = false
        player.physicsBody?.velocity = .zero
        player.physicsBody?.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))
    }

    private func spawnObstacle() {
        let height = CGFloat.random(in: 30...70)
        let width: CGFloat = 24
        let obstacle = SKShapeNode(rectOf: CGSize(width: width, height: height))
        obstacle.name = "obstacle"
        obstacle.fillColor = .systemRed
        obstacle.strokeColor = .black
        obstacle.position = CGPoint(x: size.width + width, y: groundHeight + height / 2)
        obstacle.zPosition = 2

        let body = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        body.categoryBitMask = PhysicsCategory.obstacle
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.player
        body.affectedByGravity = false
        obstacle.physicsBody = body

        addChild(obstacle)

        let distance = size.width + width * 2
        let duration = TimeInterval(distance / obstacleSpeed)
        obstacle.run(.sequence([.moveBy(x: -distance, y: 0, duration: duration), .removeFromParent()]))
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPlaying {
            jump()
        } else {
            startGame()
        }
    }

    // MARK: - Physics

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if categories == PhysicsCategory.player | PhysicsCategory.ground {
            isGrounded = true
        } else if categories == PhysicsCategory.player | PhysicsCategory.obstacle {
            endGame()
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if categories == PhysicsCategory.player | PhysicsCategory.ground {
            isGrounded = false
        }
    }
}
