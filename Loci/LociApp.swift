import SwiftUI

@main
struct LociApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("Loci")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}
