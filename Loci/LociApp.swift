import SwiftData
import SwiftUI

@main
struct LociApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerConfiguration.production()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Text("Loci")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}
