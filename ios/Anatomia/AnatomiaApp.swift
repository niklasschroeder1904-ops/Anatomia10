import SwiftUI

@main
struct AnatomiaApp: App {
    @StateObject private var splash = SplashModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                WebAppView(splash: splash)
                    .ignoresSafeArea()
                // the loading animation (SplashView) over the web view until the page reports that the app is on screen
                if splash.visible {
                    SplashView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // the blue of the launch screen and of the loading animation: no white or black at the start
            .background(Color(red: 0.118, green: 0.157, blue: 0.212).ignoresSafeArea())
        }
    }
}
