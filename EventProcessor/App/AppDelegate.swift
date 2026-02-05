import Foundation
import FirebaseCore
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var dependencyContainer: DependencyContainer!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
        dependencyContainer = DependencyContainer()
    }
}
