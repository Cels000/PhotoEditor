import SwiftUI
import SwiftData

@main
struct PhotoEditorApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            // RECIPE-01: LibrarySchemaV1 now carries both LibraryItem and RecipeItem.
            // No rename needed — adding a model to an existing VersionedSchema is the
            // lightweight, non-destructive path that preserves existing user library data.
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
