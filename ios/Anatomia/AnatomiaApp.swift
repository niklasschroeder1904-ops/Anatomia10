import SwiftUI

@main
struct AnatomiaApp: App {
    var body: some Scene {
        WindowGroup {
            WebAppView()
                .ignoresSafeArea()
                .background(Color(red: 0.957, green: 0.965, blue: 0.984))
        }
    }
}
