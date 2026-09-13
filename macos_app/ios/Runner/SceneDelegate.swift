import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    IOSFileCoordinator.shared.importFiles(from: URLContexts.map(\.url))
  }
}
