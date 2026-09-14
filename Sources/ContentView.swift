import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var scene: GameScene?

    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: currentScene(size: proxy.size))
                .ignoresSafeArea()
        }
    }

    private func currentScene(size: CGSize) -> SKScene {
        if let scene {
            return scene
        }
        let newScene = GameScene()
        newScene.size = size
        newScene.scaleMode = .resizeFill
        DispatchQueue.main.async { scene = newScene }
        return newScene
    }
}
