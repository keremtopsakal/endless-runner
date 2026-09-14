import SwiftUI

struct GameViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameViewController {
        GameViewController()
    }

    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        GameViewControllerRepresentable()
            .ignoresSafeArea()
    }
}
