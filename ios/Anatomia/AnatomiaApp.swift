import SwiftUI

@main
struct AnatomiaApp: App {
    var body: some Scene {
        WindowGroup {
            WebAppView()
                .ignoresSafeArea()
                // the blue of the launch screen and of the web app's loading screen: no white or black at the start
                .background(Color(red: 0.118, green: 0.157, blue: 0.212))
        }
    }
}
