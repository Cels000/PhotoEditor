import SwiftUI
import SwiftData

@main
struct PhotoEditorApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: LibraryMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Per PITFALLS #12: failed migration should NOT silently destroy data.
            // For v1 (no migrations yet) this only fails in catastrophic disk scenarios;
            // fail loudly so QA notices.
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
