import SwiftUI
import UIKit

final class CrossDeskAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

@MainActor
enum AppOrientation {
    nonisolated static let autoLandscapeKey = "crossdesk.mobile.auto-landscape"
    private static var sessionOrientations: UIInterfaceOrientationMask?

    nonisolated static func beginSession(autoLandscape: Bool) {
        DispatchQueue.main.async { beginSessionOnMain(autoLandscape: autoLandscape) }
    }

    private static func beginSessionOnMain(autoLandscape: Bool) {
        // Preserve the selected policy through repeated transport-ready callbacks.
        guard sessionOrientations == nil else { return }
        let orientations: UIInterfaceOrientationMask = autoLandscape ? .landscape : .allButUpsideDown
        sessionOrientations = orientations
        apply(to: orientations)
    }

    nonisolated static func endSession() {
        DispatchQueue.main.async {
            sessionOrientations = nil
            apply(to: .portrait)
        }
    }

    nonisolated static func resume() {
        DispatchQueue.main.async {
            apply(to: sessionOrientations ?? .portrait)
        }
    }

    /// Manual landscape toggle from the floating controls: `true` locks the
    /// session to landscape, `false` restores free rotation and rotates back to
    /// portrait right away. iPads keep every orientation and are untouched.
    nonisolated static func setSessionLandscape(_ landscape: Bool) {
        DispatchQueue.main.async { setSessionLandscapeOnMain(landscape) }
    }

    private static func setSessionLandscapeOnMain(_ landscape: Bool) {
        guard sessionOrientations != nil else { return }
        if landscape {
            sessionOrientations = .landscape
            apply(to: .landscape)
        } else {
            sessionOrientations = .allButUpsideDown
            apply(to: .allButUpsideDown, requesting: .portrait)
        }
    }

    private static func apply(to orientations: UIInterfaceOrientationMask,
                              requesting request: UIInterfaceOrientationMask? = nil) {
        // iPad keeps every orientation available, including in resizable windows.
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        CrossDeskAppDelegate.supportedOrientations = orientations
        guard UIApplication.shared.applicationState == .active else { return }
        let target = request ?? orientations
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach {
                $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
                NSLog("CrossDesk orientation update failed: %@", error.localizedDescription)
            }
        }
    }
}

@main
struct CrossDeskMobileApp: App {
    @UIApplicationDelegateAdaptor(CrossDeskAppDelegate.self) private var appDelegate
    @StateObject private var session = RemoteSessionModel()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}
