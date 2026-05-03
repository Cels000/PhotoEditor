import SwiftUI
import SwiftData

extension Notification.Name {
    static let recipeImported = Notification.Name("PhotoEditor.recipeImported")
}

@main
struct PhotoEditorApp: App {
    let modelContainer: ModelContainer
    @AppStorage("hasSeenFirstRun") private var hasSeenFirstRun: Bool = false

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
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .sheet(isPresented: Binding(get: { !hasSeenFirstRun }, set: { _ in })) {
                    FirstRunView(onGetStarted: { hasSeenFirstRun = true })
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) {
        guard url.pathExtension.lowercased() == ExportedRecipe.fileExtension else { return }

        // Some sources hand us a security-scoped URL (Files app).
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let doc = try RecipeFileIO.read(from: url)

            // Persist via a transient RecipeStore on the shared ModelContainer's main context.
            let context = modelContainer.mainContext
            let store = RecipeStore(context: context)

            // Decode optional thumbnail
            let thumb: Data? = doc.thumbnailJPEGBase64.flatMap { Data(base64Encoded: $0) }
            store.save(name: doc.name, stack: doc.stack, thumbnail: thumb)

            // Notify any open ContentView/RecipesSheetView so its observed RecipeStore refreshes.
            NotificationCenter.default.post(name: .recipeImported, object: nil)
        } catch {
            // Silent failure — Phase 7 polish can add a user-facing toast.
            // For now, NSLog so QA on real device can diagnose.
            NSLog("PhotoEditor: failed to import recipe at \(url.lastPathComponent): \(error)")
        }
    }
}
