import SwiftData
import SwiftUI

enum RootTab: Hashable {
    case studio
    case edit
    case recipes
}

/// App root: 3-tab navigation. Replaces the previous single-screen ContentView
/// that crammed picker, library, recipes, and editor into one toolbar with
/// cryptic icons. Each tab is its own focused destination; the editor is no
/// longer fighting for nav-bar real estate.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    // Shared editor state — lifted to root so Studio (open library item),
    // Editor (active session), and Recipes (apply recipe) all read/write the
    // same view-model.
    @State private var viewModel = EditorViewModel()
    @State private var libraryStore: LibraryStore?
    @State private var recipeStore: RecipeStore?
    @State private var selectedTab: RootTab = .edit
    @State private var showLimitedBanner: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            StudioTabView(
                viewModel: viewModel,
                libraryStore: libraryStore,
                onPhotoOpened: { withAnimation { selectedTab = .edit } }
            )
            .tabItem {
                Label {
                    Text("STUDIO").tracking(1.5)
                } icon: {
                    Image(systemName: "photo.stack")
                }
            }
            .tag(RootTab.studio)

            EditorTabView(viewModel: viewModel, showLimitedBanner: $showLimitedBanner)
                .tabItem {
                    Label {
                        Text("EDIT").tracking(1.5)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                .tag(RootTab.edit)

            RecipesTabView(
                store: recipeStore,
                onApply: { recipe in
                    viewModel.applyRecipe(recipe)
                    withAnimation { selectedTab = .edit }
                }
            )
            .tabItem {
                Label {
                    Text("RECIPES").tracking(1.5)
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
            }
            .tag(RootTab.recipes)
        }
        .tint(Theme.Colors.text)
        .task {
            // Initialize stores once, inject into the view-model.
            if libraryStore == nil {
                let store = LibraryStore(context: modelContext)
                libraryStore = store
                viewModel.libraryStore = store
            }
            if recipeStore == nil {
                NSLog("PhotoEditor: RootTabView .task — creating RecipeStore")
                let rstore = RecipeStore(context: modelContext)
                NSLog("PhotoEditor: RootTabView .task — RecipeStore ready, deferring preset seed to first Recipes tab visit")
                recipeStore = rstore
                viewModel.recipeStore = rstore
                // Deliberately NOT seeding presets here — defer to RecipesTabView.task
                // so a misbehaving seed cannot kill the app launch path.
            }
            showLimitedBanner = PhotoLibraryAccess.isLimited
        }
        .task {
            // Recipe imports via .onOpenURL post a notification; refresh store.
            for await _ in NotificationCenter.default.notifications(named: .recipeImported).map({ _ in () }) {
                recipeStore?.refresh()
            }
        }
        .successToast(message: $viewModel.successMessage)
        .alert("Error", isPresented: Binding(present: $viewModel.errorMessage), presenting: viewModel.errorMessage) { _ in
            Button("Dismiss", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text($0) }
    }
}

extension Binding where Value == Bool {
    init<T>(present source: Binding<T?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}
