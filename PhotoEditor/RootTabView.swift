import SwiftData
import SwiftUI

enum RootTab: Hashable {
    case studio
    case edit
}

/// App root: 2-tab navigation. STUDIO is the entry point (camera roll +
/// saved edits); EDIT is the active editing surface. Recipes used to be a
/// third tab, but now live inline as the LOOKS panel inside the editor —
/// users apply presets directly while editing instead of bouncing tabs.
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
                let rstore = RecipeStore(context: modelContext)
                BuiltInPresets.seedIfNeeded(store: rstore)
                recipeStore = rstore
                viewModel.recipeStore = rstore
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
